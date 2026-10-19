extends Node
## 画面の流れ：タイトル → ロビー → 戦い → ハイライト → 報酬 → さいせん／ロビー（縦画面を先に作る。横でも動く）。
## 戦いは、試作（stick_prototype）をそのまま使う。メニューの画面は、このスクリプトがコードで作る。
## 決まりごとは flow_logic.gd、数値と文字は data/game_flow.json、保存は save_data.gd。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const Quality := preload("res://scripts/core/quality.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Replay := preload("res://scripts/flow/highlight_replay.gd")
const RoomLink := preload("res://scripts/network/room_link.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const AccountBridge := preload("res://scripts/network/account_bridge.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const FIREBASE_CONFIG_PATH := "res://data/firebase_config.json"
const CONFIG_PATH := "res://data/game_flow.json"
const BATTLE_SCENE := "res://scenes/prototype/stick_prototype.tscn"
const BENCH_SCENE := "res://scenes/prototype/crowd_bench.tscn"

var config: Dictionary = {}
var state := Logic.TITLE
var save: Dictionary = {}
var font: Font
var layer: CanvasLayer
var panels: Dictionary = {}
var battle: Node = null
var stage_index := 0
var state_time := 0.0
var toast_time := 0.0
var last_reward := 0
var last_won := false
var best_text := ""

var title_label: Label
var lobby_info: Label
var stage_label: Label
var play_button: Button
var toast_label: Label
var highlight_best: Label
var highlight_replay: Control
var highlight_info: Dictionary = {}
var reward_label: Label
var query_bench := false
var quality_config: Dictionary = {}
var quality_name := "low"
var quality_button: Button
var characters_cfg: Dictionary = {}
var selected_character := ""
var lobby_char: Label
var formation_stats: Label
var formation_buttons: Dictionary = {}
var room_code := ""
var room_from_url := false
var account: RefCounted = null
var account_state: Dictionary = {}
var account_poll_timer := 0.0
var account_signature := ""
var save_applied := false
var account_box: VBoxContainer
var friends_box: VBoxContainer
var invite_join_button: Button
var invite_join_from := ""
var invite_join_room := ""
var room_label: Label
var invite_button: Button
var leave_button: Button
var waiting_ready := false
var phase_sent := ""
var phase_slot := ""
var displaced_box: Control
var displaced_shown := false
var claimed_key := ""
var claim_grace := 0.0
var party_box: VBoxContainer
var party_signature := ""
var friend_box: Control
var friend_box_col: VBoxContainer
var friend_preview_sig := ""
var requested_sids: Dictionary = {}
## ロビーから入っている部屋（戦いを出入りしても、部屋は続く）
var bridge: RefCounted = null
var room_state: Dictionary = {}
var room_poll_timer := 0.0
var post_time := 0.0
var clock_ms: Callable = func() -> float: return Time.get_unix_time_from_system() * 1000.0
var js_eval: Callable = func(text: String) -> Variant: return JavaScriptBridge.eval(text, true)
var rematch_button_reward: Button
var rematch_button_next: Button
var rematch_wait_reward: Label
var rematch_wait_next: Label
var my_rematch_vote := false
var starter_cooldown := 0.0


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	if config.is_empty():
		config = load_config()
	font = load(str(config["ui_font_path"])) as Font
	save = SaveData.load_save(str(config["save_path"]))
	characters_cfg = CharacterData.load_config()
	selected_character = str(save.get("character", ""))
	if CharacterData.find(characters_cfg, selected_character).is_empty():
		selected_character = str(characters_cfg.get("player_character", ""))
	quality_config = Quality.load_config()
	quality_name = Quality.resolve(str(save.get("quality", "")), quality_config)
	layer = CanvasLayer.new()
	layer.name = "Menus"
	layer.layer = 10
	add_child(layer)
	init_room()
	_build_panels()
	join_room()
	init_account()
	if OS.has_feature("web") and str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('bench') || ''", true)) != "":
		query_bench = true
	if query_bench:
		get_tree().change_scene_to_file.call_deferred(BENCH_SCENE)
		return
	_apply_window_scale()
	_apply_quality()
	goto(Logic.TITLE)


## 縦横に合わせて、文字・ボタンの基準の大きさを変える
func _apply_window_scale() -> void:
	var win := get_window()
	if win == null:
		return
	var size := Vector2(win.size)
	var base: Array = config["portrait_base_size"] if size.y > size.x else config["landscape_base_size"]
	win.content_scale_size = Vector2i(int(base[0]), int(base[1]))


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String, min_size: Array, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_size[0], min_size[1])
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", int(config["button_font_size"]))
	button.pressed.connect(callback)
	return button


## 画面いっぱいの背景と、真ん中に縦に並べる入れ物を作る
func _make_panel(panel_name: String, separation: int = 28) -> VBoxContainer:
	var root := Control.new()
	root.name = panel_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(str(config["bg_color"]))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	root.add_child(box)
	layer.add_child(root)
	panels[panel_name] = root
	return box


## ロビー用：中身がはみ出したら、縦にスクロールできる入れ物
func _make_lobby_panel(panel_name: String, separation: int) -> VBoxContainer:
	var root := Control.new()
	root.name = panel_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(str(config["bg_color"]))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	layer.add_child(root)
	panels[panel_name] = root
	return box


## 色つきの四角い枠（中身は、子として足す）。横は、ほかの部品と同じ幅にそろえる
func _make_card(color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(int(config["lobby_card_width"]), 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(18)
	box.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", box)
	return card


## ボタンに色をつける（ふだん・おしている・おせない）
func _paint_button(button: Button, color: Color) -> void:
	for pair in [["normal", color], ["hover", color.lightened(0.1)], ["pressed", color.darkened(0.2)], ["disabled", color.darkened(0.45)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = pair[1]
		sb.set_corner_radius_all(18)
		sb.set_content_margin_all(8)
		button.add_theme_stylebox_override(pair[0], sb)


func _build_panels() -> void:
	var text_color := Color(str(config["text_color"]))
	var heading := int(config["heading_font_size"])
	var text_size := int(config["text_font_size"])
	var big: Array = config["button_min_size"]
	var small: Array = config["small_button_min_size"]

	# タイトル
	var t := _make_panel(Logic.TITLE)
	title_label = _make_label(str(config["title_text"]), int(config["title_font_size"]), Color(str(config["title_color"])))
	t.add_child(title_label)
	t.add_child(_make_label(str(config["title_loading"]), text_size, text_color))

	# ロビー（上：ランク・コイン／まんなか：ステージとプレイ／下：ボタンの並び）。縦が足りないときは、スクロールできる
	var l := _make_lobby_panel(Logic.LOBBY, int(config["lobby_separation"]))
	var top_card := _make_card(Color(str(config["lobby_card_color"])))
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 6)
	top_card.add_child(top_box)
	lobby_info = _make_label("", text_size, text_color)
	top_box.add_child(lobby_info)
	room_label = _make_label("", int(config["lobby_small_font_size"]), Color(str(config["lobby_sub_color"])))
	top_box.add_child(room_label)
	l.add_child(top_card)
	var stage_card := _make_card(Color(str(config["lobby_card_color"])))
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override("separation", 12)
	stage_row.add_child(_make_button(str(config["stage_prev"]), [100, 90], func(): change_stage(-1)))
	stage_label = _make_label("", heading, text_color)
	stage_label.custom_minimum_size = Vector2(316, 0)
	stage_row.add_child(stage_label)
	stage_row.add_child(_make_button(str(config["stage_next"]), [100, 90], func(): change_stage(1)))
	stage_card.add_child(stage_row)
	l.add_child(stage_card)
	play_button = _make_button(str(config["play_label"]), [int(config["lobby_card_width"]), 150], play)
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_paint_button(play_button, Color(str(config["lobby_play_color"])))
	l.add_child(play_button)
	var room_row := HBoxContainer.new()
	room_row.alignment = BoxContainer.ALIGNMENT_CENTER
	room_row.add_theme_constant_override("separation", 16)
	invite_button = _make_button(str(config["invite_label"]), [292, 84], invite)
	leave_button = _make_button(str(config["new_room_label"]), [292, 84], new_room)
	_paint_button(invite_button, Color(str(config["lobby_nav_color"])))
	_paint_button(leave_button, Color(str(config["lobby_nav_color"])))
	room_row.add_child(invite_button)
	room_row.add_child(leave_button)
	l.add_child(room_row)
	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 8)
	l.add_child(party_box)
	invite_join_button = _make_button("", big, join_invite)
	invite_join_button.visible = false
	l.add_child(invite_join_button)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var grid_holder := CenterContainer.new()
	grid_holder.add_child(grid)
	for name_text in config["lobby_buttons"]:
		var cb: Callable = show_toast
		if str(name_text) == str(config["formation_label"]):
			cb = func(): event("formation")
		elif str(name_text) == str(config["account_label"]):
			cb = func(): event("account")
		elif str(name_text) == str(config["friends_label"]):
			cb = func(): event("friends")
		var nav := _make_button(str(name_text), [196, 96], cb)
		nav.add_theme_font_size_override("font_size", int(config["lobby_nav_font_size"]))
		_paint_button(nav, Color(str(config["lobby_nav_color"])))
		grid.add_child(nav)
	l.add_child(grid_holder)
	quality_button = _make_button("", [400, 80], change_quality)
	var quality_holder := CenterContainer.new()
	_paint_button(quality_button, Color(str(config["lobby_card_color"])))
	quality_holder.add_child(quality_button)
	l.add_child(quality_holder)
	lobby_char = _make_label("", int(config["lobby_small_font_size"]), Color(str(config["lobby_sub_color"])))
	l.add_child(lobby_char)
	toast_label = _make_label("", text_size, Color(1.0, 0.85, 0.4))
	l.add_child(toast_label)

	# へんせい（キャラを選ぶ）
	var f := _make_panel(Logic.FORMATION)
	f.add_child(_make_label(str(config["formation_title"]), heading, Color(str(config["title_color"]))))
	var fgrid := GridContainer.new()
	fgrid.columns = 2
	fgrid.add_theme_constant_override("h_separation", 16)
	fgrid.add_theme_constant_override("v_separation", 16)
	for c in characters_cfg.get("characters", []):
		var id := str(c["id"])
		var label := str(c["role"]) + "\n" + str(c["name"])
		var b := _make_button(label, [260, 110], func(): select_character(id))
		b.add_theme_font_size_override("font_size", int(config["formation_button_font_size"]))
		formation_buttons[id] = b
		fgrid.add_child(b)
	var fholder := CenterContainer.new()
	fholder.add_child(fgrid)
	f.add_child(fholder)
	formation_stats = _make_label("", int(config["formation_stats_font_size"]), text_color)
	f.add_child(formation_stats)
	f.add_child(_make_button(str(config["back_label"]), big, func(): event("back")))

	# アカウント
	var acc_panel := _make_panel(Logic.ACCOUNT, 18)
	acc_panel.add_child(_make_label(str(config["account_title"]), heading, Color(str(config["title_color"]))))
	account_box = VBoxContainer.new()
	account_box.alignment = BoxContainer.ALIGNMENT_CENTER
	account_box.add_theme_constant_override("separation", 14)
	acc_panel.add_child(account_box)
	acc_panel.add_child(_make_button(str(config["back_label"]), big, func(): event("back")))

	# フレンド
	var fr_panel := _make_panel(Logic.FRIENDS, 18)
	fr_panel.add_child(_make_label(str(config["friends_title"]), heading, Color(str(config["title_color"]))))
	friends_box = VBoxContainer.new()
	friends_box.alignment = BoxContainer.ALIGNMENT_CENTER
	friends_box.add_theme_constant_override("separation", 12)
	fr_panel.add_child(friends_box)
	fr_panel.add_child(_make_button(str(config["back_label"]), big, func(): event("back")))

	# ハイライト
	var h := _make_panel(Logic.HIGHLIGHT)
	h.add_child(_make_label(str(config["highlight_title"]), heading, Color(str(config["title_color"]))))
	h.add_child(_make_label(str(config["highlight_note"]), text_size, text_color))
	highlight_best = _make_label("", text_size, text_color)
	h.add_child(highlight_best)
	highlight_replay = Replay.new()
	var rs: Array = config["highlight_replay_size"]
	highlight_replay.custom_minimum_size = Vector2(rs[0], rs[1])
	var replay_holder := CenterContainer.new()
	replay_holder.add_child(highlight_replay)
	h.add_child(replay_holder)
	h.add_child(_make_button(str(config["next_label"]), big, func(): event("done")))

	# 報酬
	var r := _make_panel(Logic.REWARD)
	r.add_child(_make_label(str(config["reward_title"]), heading, Color(str(config["title_color"]))))
	reward_label = _make_label("", heading, Color(1.0, 0.85, 0.4))
	r.add_child(reward_label)
	rematch_button_reward = _make_button(str(config["rematch_label"]), big, func(): event("rematch"))
	r.add_child(rematch_button_reward)
	rematch_wait_reward = _make_label("", 28, Color(1.0, 0.85, 0.4))
	r.add_child(rematch_wait_reward)
	r.add_child(_make_button(str(config["next_label"]), big, func(): event("next")))
	r.add_child(_make_button(str(config["lobby_label"]), big, func(): event("lobby")))

	# つぎへ（さいせん／ロビー）
	var n := _make_panel(Logic.NEXT)
	rematch_button_next = _make_button(str(config["rematch_label"]), big, func(): event("rematch"))
	n.add_child(rematch_button_next)
	rematch_wait_next = _make_label("", 28, Color(1.0, 0.85, 0.4))
	n.add_child(rematch_wait_next)
	n.add_child(_make_button(str(config["lobby_label"]), big, func(): event("lobby")))


	# LINEのフレンドURLを開いたとき：「ついかする／キャンセル」
	friend_box = Control.new()
	friend_box.name = "FriendPreview"
	friend_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	friend_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var f_bg := ColorRect.new()
	f_bg.color = Color(0.05, 0.07, 0.1, 0.96)
	f_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	friend_box.add_child(f_bg)
	friend_box_col = VBoxContainer.new()
	friend_box_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	friend_box_col.alignment = BoxContainer.ALIGNMENT_CENTER
	friend_box_col.add_theme_constant_override("separation", 30)
	friend_box.add_child(friend_box_col)
	friend_box.visible = false
	layer.add_child(friend_box)

	# 「ほかの画面で ひらかれました」（同じ人は、同時に1つの画面でしか遊べない）
	displaced_box = Control.new()
	displaced_box.name = "Displaced"
	displaced_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	displaced_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var d_bg := ColorRect.new()
	d_bg.color = Color(0.05, 0.07, 0.1, 0.96)
	d_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	displaced_box.add_child(d_bg)
	var d_col := VBoxContainer.new()
	d_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	d_col.alignment = BoxContainer.ALIGNMENT_CENTER
	d_col.add_theme_constant_override("separation", 40)
	displaced_box.add_child(d_col)
	d_col.add_child(_info(str(config["displaced_text"])))
	d_col.add_child(_small_button(str(config["displaced_button"]), reclaim_session))
	displaced_box.visible = false
	layer.add_child(displaced_box)

## 状態を切り替える：その画面だけ出す。戦いに入るときは戦いを作り、出るときは片づける
func goto(new_state: String) -> void:
	if new_state == Logic.HIGHLIGHT:
		_capture_result()
	if new_state == Logic.REWARD:
		post_time = 0.0
		if rematch_button_reward != null:
			rematch_button_reward.visible = true
			rematch_button_next.visible = true
	if new_state != Logic.LOBBY:
		waiting_ready = false
	state = new_state
	state_time = 0.0
	for key in panels:
		(panels[key] as Control).visible = (key == new_state)
	if new_state == Logic.BATTLE:
		if battle != null and battle.dormant:
			battle.set_dormant(false)
			_apply_quality()
		else:
			_start_battle()
		my_rematch_vote = false
	elif _keeps_room(new_state):
		battle.set_dormant(true)
	else:
		_end_battle_node()
	match new_state:
		Logic.LOBBY:
			_refresh_lobby()
		Logic.FORMATION:
			_refresh_formation()
		Logic.ACCOUNT:
			account_signature = ""
			_refresh_account()
		Logic.FRIENDS:
			account_signature = ""
			_refresh_friends()
		Logic.HIGHLIGHT:
			highlight_best.text = best_text if best_text != "" else str(config["highlight_none"])
			highlight_replay.visible = not highlight_info.is_empty()
			if not highlight_info.is_empty():
				highlight_replay.setup(highlight_info["points"], highlight_info["boss"], float(highlight_info["bounds"]), highlight_info["color"], highlight_info["config"], config, highlight_info.get("character", {}))
		Logic.REWARD:
			reward_label.text = str(config["reward_coin_prefix"]) + str(last_reward)


## 出来事で次の状態へ（決まりは flow_logic.gd）
func event(name_text: String) -> void:
	var next_state := Logic.next_state(state, name_text)
	if next_state == state:
		return
	if state == Logic.HIGHLIGHT and name_text == "done":
		_give_reward()
	if name_text == "lobby" and _room_battle():
		# ロビーに戻る：全員をロビーに戻す（部屋は続く）
		battle.send_rematch_vote("lobby")
	if name_text == "rematch" and _room_battle():
		# 通信中は、全員が「さいせん」を選んだときだけ始まる
		my_rematch_vote = true
		battle.send_rematch_vote("rematch")
		return
	if next_state == Logic.BATTLE and name_text == "rematch":
		_rematch_pending = true
	goto(next_state)


func play() -> void:
	if not bool(config["stages"][stage_index]["open"]):
		show_toast()
		return
	if waiting_ready:
		# もういちど おすと、まつのをやめる
		waiting_ready = false
		_refresh_play_button()
		return
	if Logic.others_busy(room_state):
		_refresh_play_button()
		return
	if Logic.other_members(room_state).is_empty():
		event("play")
		return
	# ほかの人がいるときは、全員が「プレイ」を押すまで待つ（いっしょに、戦いに入る）
	waiting_ready = true
	_refresh_play_button()


## 部屋の人と、ロビーの「プレイ」「しょうたい」「へやを ぬける」の表示を、いまの状態に合わせる
func _refresh_play_button() -> void:
	if play_button == null:
		return
	var stage_open := bool(config["stages"][stage_index]["open"])
	var busy := Logic.others_busy(room_state)
	if waiting_ready and busy:
		waiting_ready = false
	if waiting_ready:
		play_button.text = str(config["play_waiting_label"])
		play_button.disabled = false
	elif busy:
		play_button.text = str(config["play_busy_label"])
		play_button.disabled = true
	else:
		play_button.text = str(config["play_label"])
		play_button.disabled = not stage_open
	var full := Logic.party_full(room_state, int(config["max_party"]))
	var party := Logic.other_members(room_state).size() > 0
	invite_button.disabled = full
	invite_button.text = str(config["invite_locked_label"]) if full else str(config["invite_label"])
	leave_button.disabled = not party
	leave_button.text = str(config["new_room_label"]) if party else str(config["leave_alone_label"])


## 部屋の状態を、みんなに見せる（ロビー／まっている／戦い中／結果）。変わったときだけ送る
func _sync_phase() -> void:
	if bridge == null or str(room_state.get("status", "")) != "in_room":
		return
	var slot := str(room_state.get("slot", ""))
	var want := Logic.phase_of(state, waiting_ready)
	if want == phase_sent and slot == phase_slot:
		return
	phase_sent = want
	phase_slot = slot
	bridge.send_phase(want)


func change_stage(step: int) -> void:
	var count: int = (config["stages"] as Array).size()
	stage_index = (stage_index + step + count) % count
	_refresh_lobby()


## 画質を「低」「高」で切り替える（選びは保存する）
func change_quality() -> void:
	quality_name = Quality.next_preset(quality_name, quality_config)
	save["quality"] = quality_name
	_write_save()
	_apply_quality()
	_refresh_lobby()


func _apply_quality() -> void:
	var lights: Array[Node] = []
	if get_tree() != null:
		lights = get_tree().get_nodes_in_group("sun")
	Quality.apply(quality_name, quality_config, get_viewport(), lights)


func show_toast() -> void:
	toast_label.text = str(config["coming_soon"])
	toast_time = float(config["toast_sec"])


## キャラを選ぶ（自分の端末に保存。戦いは、選んだキャラの性能で動く）
func select_character(id: String) -> void:
	if CharacterData.find(characters_cfg, id).is_empty():
		return
	selected_character = id
	save["character"] = id
	_write_save()
	_refresh_formation()


func _refresh_formation() -> void:
	var def := CharacterData.find(characters_cfg, selected_character)
	for id in formation_buttons:
		(formation_buttons[id] as Button).disabled = (id == selected_character)
	if def.is_empty():
		formation_stats.text = ""
		return
	var labels: Dictionary = config["stat_labels"]
	var st: Dictionary = def["stats"]
	formation_stats.text = str(config["formation_selected"]) + "：" + str(def["role"]) + " " + str(def["name"]) + "\n" \
		+ str(labels["hp"]) + " " + str(int(st["hp"])) + "  " + str(labels["move_speed"]) + " " + str(int(st["move_speed"])) + "\n" \
		+ str(labels["attack_power"]) + " " + str(int(st["attack_power"])) + "  " + str(labels["attack_reach"]) + " " + str(int(st["attack_reach"])) \
		+ "  " + str(labels["skill"]) + "：" + str(def["skill"])


func _refresh_lobby() -> void:
	var rank := Logic.player_rank(int(save.get("wins", 0)), int(config["wins_per_rank"]))
	lobby_info.text = str(config["lobby_rank_label"]) + " " + str(rank) + "    " + str(config["lobby_coin_label"]) + " " + str(int(save.get("coins", 0)))
	var stage: Dictionary = config["stages"][stage_index]
	stage_label.text = str(stage["name"])
	var cdef := CharacterData.find(characters_cfg, selected_character)
	lobby_char.text = (str(config["lobby_char_label"]) + "：" + str(cdef["role"]) + " " + str(cdef["name"])) if not cdef.is_empty() else ""
	_refresh_room_label()
	_refresh_play_button()
	quality_button.text = str(config["quality_label"]) + "：" + Quality.label_of(quality_name, quality_config)


## 部屋につながった戦いが残っているか
func _room_battle() -> bool:
	return battle != null and is_instance_valid(battle) and battle.net_active


## ハイライト・報酬・つぎへの間は、部屋に残す（戦いは休止）
func _keeps_room(new_state: String) -> bool:
	return _room_battle() and new_state in [Logic.HIGHLIGHT, Logic.REWARD, Logic.NEXT]


func _on_round_started() -> void:
	# ほかの人が（または自分が）新しい戦いを始めた。休止中なら、戦いに戻る
	if battle != null and battle.dormant and state in [Logic.HIGHLIGHT, Logic.REWARD, Logic.NEXT]:
		goto(Logic.BATTLE)


## 全員さいせんの判定。1人でも「ロビー」なら全員ロビー。全員が「さいせん」なら、いちばん若い枠の人が開始の時刻を書く。
## 時間内にそろわなかったら、全員ロビーに戻す（ひとりだけ「さいせん」で、ひとりはロビー、にはならない）
func _rematch_update(delta: float) -> void:
	var votes: Dictionary = battle.rematch_votes()
	var members: Array = battle.net_state.get("members", [])
	var decision := Logic.rematch_decision(votes, members)
	if decision == "lobby":
		goto(Logic.LOBBY)
		return
	var text := ""
	# この戦いに出ていない人が部屋にいたら、「さいせん」は使えない（ロビーで合流してから、いっしょに戦う）
	var idle: Array = battle.idle_members()
	var can_rematch := idle.is_empty()
	rematch_button_reward.visible = can_rematch
	rematch_button_next.visible = can_rematch
	if not can_rematch:
		text = str(config["party_gathered_text"])
		rematch_wait_reward.text = text
		rematch_wait_next.text = text
		return
	if state != Logic.HIGHLIGHT:
		post_time += delta
		if post_time >= float(config["rematch_timeout_sec"]):
			battle.send_rematch_vote("lobby")
			goto(Logic.LOBBY)
			return
	if my_rematch_vote:
		text = str(config["rematch_wait_text"]) + "（" + str(Logic.vote_count(votes, members)) + "/" + str(members.size()) + "）"
		starter_cooldown = maxf(0.0, starter_cooldown - delta)
		if decision == "rematch" and Logic.lowest_slot(members) == str(battle.net_state.get("slot", "")) and starter_cooldown <= 0.0:
			starter_cooldown = float(config["rematch_resend_sec"])
			battle.start_round()
	rematch_wait_reward.text = text
	rematch_wait_next.text = text


## ---- アカウント（ログイン・保存・フレンド）。入力欄は、ブラウザ側の本物の入力欄 ----
func init_account() -> void:
	var acc := AccountBridge.new()
	acc.js_eval = js_eval
	if not acc.available():
		return
	account = acc
	var config_json := JSON.stringify(CheckScreen.extract_firebase_config(CheckScreen.load_json(FIREBASE_CONFIG_PATH)))
	account.init(config_json)
	account.set_save(save)


## 部屋にいる、ほかの人の一覧（アカウントの人には「フレンドに なる」ボタン）
func _refresh_party() -> void:
	var who: Dictionary = room_state.get("who", {}) if room_state.get("who") is Dictionary else {}
	var friends: Array = account_state.get("friends", [])
	var friend_sids := {}
	for f in friends:
		friend_sids[str(f.get("sid", ""))] = true
	var rows: Array = []
	for slot in Logic.other_members(room_state):
		var w: Variant = who.get(slot)
		var sid := str(w.get("sid", "")) if w is Dictionary else ""
		var nick := str(w.get("nickname", "")) if w is Dictionary else ""
		rows.append([slot, sid, nick])
	var mine := bool(account_state.get("signedIn", false))
	var sig := JSON.stringify([rows, mine, friend_sids.keys(), requested_sids.keys()])
	if sig == party_signature:
		return
	party_signature = sig
	_clear_box(party_box)
	for row in rows:
		var sid: String = row[1]
		var nick: String = row[2]
		if sid == "":
			continue  # ゲストの人には、申しこめない
		var name_text := nick if nick != "" else str(config["friends_no_name"])
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 12)
		var lab := _make_label(name_text, int(config["lobby_small_font_size"]), Color(str(config["text_color"])))
		lab.custom_minimum_size = Vector2(250, 0)
		line.add_child(lab)
		var btn: Button
		if friend_sids.has(sid):
			btn = _make_button(str(config["party_friend_done"]), [300, 70], func(): pass)
			btn.disabled = true
		elif requested_sids.has(sid):
			btn = _make_button(str(config["party_friend_sent"]), [300, 70], func(): pass)
			btn.disabled = true
		elif not mine:
			btn = _make_button(str(config["party_need_login"]), [300, 70], func(): pass)
			btn.disabled = true
		else:
			btn = _make_button(str(config["party_friend_button"]), [300, 70], func(): _request_friend_of(sid))
		btn.add_theme_font_size_override("font_size", int(config["lobby_small_font_size"]))
		_paint_button(btn, Color(str(config["lobby_nav_color"])))
		line.add_child(btn)
		party_box.add_child(line)


func _request_friend_of(sid: String) -> void:
	requested_sids[sid] = true
	party_signature = ""
	if account != null:
		account.request_friend_sid(sid)
	_refresh_party()


## フレンドのURLを、LINEなどで おくる
func share_friend_url() -> void:
	var code := str(account_state.get("friendCode", ""))
	if code == "" or str(js_eval.call("typeof window")) != "object":
		return
	var base := str(js_eval.call("window.location.origin + window.location.pathname"))
	js_eval.call(RoomLink.build_share_call(RoomLink.build_friend_url(base, code), config["friend_url_share_labels"]))


## フレンドURLを開いたときの、確認の画面
func _refresh_friend_preview() -> void:
	var pv: Variant = account_state.get("preview")
	var sig := JSON.stringify(pv) + str(requested_sids.has("__link"))
	if sig == friend_preview_sig:
		return
	friend_preview_sig = sig
	_clear_box(friend_box_col)
	if not (pv is Dictionary):
		friend_box.visible = false
		return
	var status := str(pv.get("status", ""))
	if status == "loading":
		friend_box.visible = false
		return
	friend_box.visible = true
	var nick := str(pv.get("nickname", ""))
	if nick == "":
		nick = str(config["friends_no_name"])
	if requested_sids.has("__link"):
		friend_box_col.add_child(_info(str(config["friend_preview_sent"])))
		friend_box_col.add_child(_small_button(str(config["friend_preview_ok"]), _close_friend_preview))
		return
	if status == "ok":
		friend_box_col.add_child(_info(nick + str(config["friend_preview_ask"])))
		friend_box_col.add_child(_small_button(str(config["friend_preview_add"]), func():
			requested_sids["__link"] = true
			friend_preview_sig = ""
			if account != null:
				account.request_friend_code(str(pv.get("code", "")))))
		friend_box_col.add_child(_small_button(str(config["friend_preview_cancel"]), _close_friend_preview))
	else:
		friend_box_col.add_child(_info(str(config["friend_preview_" + status]) if config.has("friend_preview_" + status) else str(config["friend_preview_error"])))
		friend_box_col.add_child(_small_button(str(config["friend_preview_ok"]), _close_friend_preview))


func _close_friend_preview() -> void:
	requested_sids.erase("__link")
	if account != null:
		account.clear_preview()
	friend_preview_sig = ""
	friend_box.visible = false


func _on_displaced() -> void:
	displaced_shown = true
	waiting_ready = false
	leave_room()
	phase_sent = ""
	if state in [Logic.BATTLE, Logic.HIGHLIGHT, Logic.REWARD, Logic.NEXT]:
		goto(Logic.LOBBY)
	displaced_box.visible = true


## この画面を、いま使う画面に取りもどす（部屋にも入り直す）
func reclaim_session() -> void:
	displaced_shown = false
	claim_grace = 3.0
	displaced_box.visible = false
	if account != null:
		account.claim_session()
	join_room()


func _poll_account(delta: float) -> void:
	if account == null:
		return
	account_poll_timer += delta
	if account_poll_timer < float(config["account_poll_sec"]):
		return
	account_poll_timer = 0.0
	var st: Dictionary = account.read_state()
	if st.is_empty():
		return
	account_state = st
	claim_grace = maxf(0.0, claim_grace - float(config["account_poll_sec"]))
	if str(st.get("status", "")) == "ok":
		var key := str(st.get("sid", "")) if bool(st.get("signedIn", false)) else "guest"
		if key != claimed_key:
			claimed_key = key
			claim_grace = 3.0
			account.claim_session()
	if bool(st.get("displaced", false)) and not displaced_shown and claim_grace <= 0.0:
		_on_displaced()
	if bool(st.get("signedIn", false)) and st.get("save") is Dictionary and not save_applied:
		save_applied = true
		_apply_server_save(st["save"])
	_refresh_invite_button()
	_refresh_friend_preview()
	if bool(st.get("signedIn", false)) and str(room_state.get("status", "")) == "in_room":
		account.announce(room_code, str(room_state.get("slot", "")))
	var sig := JSON.stringify([st.get("signedIn"), st.get("loginId"), st.get("nickname"), st.get("friendCode"), st.get("friends"), st.get("inbox"), st.get("message"), Logic.party_full(room_state, int(config["max_party"]))])
	if sig != account_signature:
		account_signature = sig
		if state == Logic.ACCOUNT:
			_refresh_account()
		elif state == Logic.FRIENDS:
			_refresh_friends()


## ログインした人の記録（サーバー）を、この端末にも反映する（サーバーの記録を正とする）
func _apply_server_save(server: Dictionary) -> void:
	save["coins"] = int(server.get("coins", save.get("coins", 0)))
	save["wins"] = int(server.get("wins", save.get("wins", 0)))
	var ch := str(server.get("character", ""))
	if ch != "" and not CharacterData.find(characters_cfg, ch).is_empty():
		save["character"] = ch
		selected_character = ch
	var q := str(server.get("quality", ""))
	if q != "":
		save["quality"] = q
		quality_name = Quality.resolve(q, quality_config)
	SaveData.write_save(str(config["save_path"]), save)
	if state == Logic.LOBBY:
		_refresh_lobby()


func _clear_box(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _info(text: String) -> Label:
	var label := _make_label(text, int(config["text_font_size"]), Color(str(config["text_color"])))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(int(config["portrait_base_size"][0]) - 40, 0)
	return label


func _small_button(text: String, callback: Callable) -> Button:
	return _make_button(text, [int(config["portrait_base_size"][0]) - 80, 80], callback)


func _show_form(kind: String) -> void:
	if account != null:
		account.show_form(kind, config["account_forms"])


func _refresh_account() -> void:
	_clear_box(account_box)
	if account == null:
		account_box.add_child(_info(str(config["account_unavailable"])))
		return
	var st := account_state
	if bool(st.get("signedIn", false)):
		account_box.add_child(_info(str(config["account_signed_in"]) + "\n" + str(config["account_id_label"]) + "：" + str(st.get("loginId", ""))))
		var nick := str(st.get("nickname", ""))
		account_box.add_child(_info(str(config["account_nickname_label"]) + "：" + (nick if nick != "" else str(config["friends_no_name"]))))
		account_box.add_child(_small_button(str(config["account_nickname"]), func(): _show_form("nickname")))
		account_box.add_child(_small_button(str(config["account_logout"]), func(): account.logout()))
	else:
		account_box.add_child(_info(str(config["account_guest"])))
		account_box.add_child(_small_button(str(config["account_create"]), func(): _show_form("register")))
		account_box.add_child(_small_button(str(config["account_login"]), func(): _show_form("login")))
		account_box.add_child(_small_button(str(config["account_recover"]), func(): _show_form("recover")))
	var message := str(st.get("message", ""))
	if message != "":
		account_box.add_child(_info(message))


func _refresh_friends() -> void:
	_clear_box(friends_box)
	if account == null:
		friends_box.add_child(_info(str(config["account_unavailable"])))
		return
	var st := account_state
	if not bool(st.get("signedIn", false)):
		friends_box.add_child(_info(str(config["friends_need_login"])))
		return
	friends_box.add_child(_info(str(config["friends_code_label"]) + "\n" + str(st.get("friendCode", ""))))
	friends_box.add_child(_small_button(str(config["friends_add"]), func(): _show_form("friend")))
	friends_box.add_child(_small_button(str(config["friends_send_url"]), share_friend_url))
	for item in st.get("inbox", []):
		var from := str(item.get("from", ""))
		var nick := str(item.get("nickname", ""))
		if nick == "":
			nick = str(config["friends_no_name"])
		if str(item.get("type", "")) == "friend":
			friends_box.add_child(_info(nick + str(config["friends_request_from"])))
			friends_box.add_child(_small_button(str(config["friends_accept"]), func(): account.accept(from)))
			friends_box.add_child(_small_button(str(config["friends_decline"]), func(): account.remove_inbox(from)))
		elif str(item.get("type", "")) == "invite":
			var room := str(item.get("room", ""))
			friends_box.add_child(_info(nick + str(config["friends_invite_from"])))
			friends_box.add_child(_small_button(str(config["friends_join"]), func(): join_invite_of(from, room)))
			friends_box.add_child(_small_button(str(config["friends_dismiss"]), func(): account.remove_inbox(from)))
	var friends: Array = st.get("friends", [])
	if friends.is_empty():
		friends_box.add_child(_info(str(config["friends_none"])))
	for f in friends:
		var fsid := str(f.get("sid", ""))
		var fnick := str(f.get("nickname", ""))
		if fnick == "":
			fnick = str(config["friends_no_name"])
		var invite_btn := _small_button(fnick + "：" + str(config["friends_invite"]), func(): account.invite(fsid, room_code))
		if Logic.party_full(room_state, int(config["max_party"])):
			invite_btn.disabled = true
			invite_btn.text = fnick + "：" + str(config["invite_locked_label"])
		friends_box.add_child(invite_btn)


## ロビーに、フレンドからのしょうたいがあれば、「◯◯のへやに さんか」を出す
func _refresh_invite_button() -> void:
	invite_join_from = ""
	invite_join_room = ""
	for item in account_state.get("inbox", []):
		if str(item.get("type", "")) == "invite":
			invite_join_from = str(item.get("from", ""))
			invite_join_room = str(item.get("room", ""))
			var nick := str(item.get("nickname", ""))
			invite_join_button.text = (nick if nick != "" else str(config["friends_no_name"])) + str(config["lobby_invite_join"])
			break
	invite_join_button.visible = state == Logic.LOBBY and invite_join_from != ""


func join_invite() -> void:
	join_invite_of(invite_join_from, invite_join_room)


## しょうたいに さんか：その部屋に入り直す（部屋は、ロビーから続く）
func join_invite_of(from: String, room: String) -> void:
	if room == "" or not RoomCode.is_valid_code(room, int(RoomCode.load_config().get("code_digits", 4))):
		return
	if account != null:
		account.remove_inbox(from)
	if battle != null:
		return
	if room == room_code and str(room_state.get("status", "")) == "in_room":
		# もう この部屋にいる：入り直さない（同じ人が2人に数えられない）
		return
	room_code = room
	room_from_url = true
	leave_room()
	join_room()
	if state != Logic.LOBBY:
		goto(Logic.LOBBY)
	else:
		_refresh_lobby()


## ロビーの時点で、部屋に入る（ブラウザ側の入り口があるときだけ。なければ通信なし）
func join_room() -> void:
	if str(js_eval.call("typeof window.bbFirebase")) != "object":
		return
	var digits := int(RoomCode.load_config().get("code_digits", 4))
	if bridge == null:
		bridge = Bridge.new()
		bridge.js_eval = js_eval
	var config_json := JSON.stringify(CheckScreen.extract_firebase_config(CheckScreen.load_json(FIREBASE_CONFIG_PATH)))
	room_state = {}
	bridge.join(config_json, room_code, digits)


func leave_room() -> void:
	if bridge != null:
		bridge.leave()


func _exit_tree() -> void:
	leave_room()


## 部屋の状態を、ときどき読む。戦いがあれば、戦いが読んだものを使う
func _poll_room(delta: float) -> void:
	if bridge == null:
		return
	if battle != null and is_instance_valid(battle) and battle.net_active:
		room_state = battle.net_state
	else:
		room_poll_timer += delta
		if room_poll_timer < float(config["room_poll_sec"]):
			return
		room_poll_timer = 0.0
		var st: Dictionary = bridge.read_state()
		if not st.is_empty():
			room_state = st
	_sync_phase()
	if state == Logic.LOBBY:
		_refresh_room_label()
		_refresh_play_button()
		_refresh_party()
		if waiting_ready and Logic.all_ready(room_state):
			waiting_ready = false
			event("play")


func _refresh_room_label() -> void:
	var text := (str(config["room_from_url_note"]) if room_from_url else str(config["room_label"])) + " " + room_code
	if bridge != null and str(room_state.get("status", "")) == "in_room":
		text += "　" + str(config["room_members_prefix"]) + str((room_state.get("members", []) as Array).size()) + str(config["room_members_suffix"])
	room_label.text = text


## 部屋の合言葉を決める：URLの ?room= があればそれ（しょうたいされた）、なければ新しく作る（毎回べつの部屋）
func init_room() -> void:
	var digits := int(RoomCode.load_config().get("code_digits", 4))
	var query: Variant = null
	if str(js_eval.call("typeof window")) == "object":
		query = js_eval.call("new URLSearchParams(window.location.search).get('room')")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var picked := RoomLink.pick(query, digits, rng)
	room_code = str(picked["code"])
	room_from_url = bool(picked["from_url"])


## 新しい合言葉の部屋にする（前の仲間とは、べつの部屋になる）
func new_room() -> void:
	var digits := int(RoomCode.load_config().get("code_digits", 4))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	room_code = RoomLink.generate_code(digits, rng)
	room_from_url = false
	waiting_ready = false
	phase_sent = ""
	leave_room()
	join_room()
	_refresh_lobby()


## しょうたい：この部屋のURLを作って、ブラウザ側の「おくる」画面を出す
func invite() -> void:
	if Logic.party_full(room_state, int(config["max_party"])):
		toast_label.text = str(config["invite_locked_label"])
		toast_time = 2.0
		return
	if str(js_eval.call("typeof window")) != "object":
		toast_label.text = str(config["invite_offline_note"])
		toast_time = 2.5
		return
	var base := str(js_eval.call("window.location.origin + window.location.pathname"))
	js_eval.call(RoomLink.build_share_call(RoomLink.build_url(base, room_code), config["share_labels"]))




func _start_battle() -> void:
	_end_battle_node()
	var packed := load(BATTLE_SCENE) as PackedScene
	battle = packed.instantiate()
	battle.flow_mode = true
	battle.selected_character = selected_character
	battle.forced_room_code = room_code
	if bridge != null:
		# 入った時点で部屋にあった戦いは、始めない（戦いの最中の人の試合に、あとから入らない）
		var latest: Dictionary = bridge.read_state()
		if not latest.is_empty():
			room_state = latest
		battle.shared_bridge = bridge
		battle.ignore_round = float(room_state.get("round", 0.0))
	battle.round_ended.connect(_on_round_ended)
	battle.round_started.connect(_on_round_started)
	add_child(battle)
	_apply_quality()


var _rematch_pending := false
var _result_timer := -1.0


func _end_battle_node() -> void:
	if battle != null:
		battle.queue_free()
		battle = null


func _on_round_ended(won_flag: bool) -> void:
	last_won = won_flag
	_result_timer = float(config["result_show_sec"])
	_capture_result()


## 結果（ハイライトの元・ベストアタッカー）を控える。戦いが終わった直後と、ハイライトに入る直前の2回やる。
## ほかの人の最終ダメージが、少し遅れて届くので、あとの回が正しい（2台で数がずれないように）
func _capture_result() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	highlight_info = battle.highlight_data()
	var entries: Array = battle.ranking_entries()
	if not entries.is_empty():
		best_text = str(config["highlight_best"]) + "：" + battle.role_name_of(str(entries[0]["slot"])) + " " + str(int(entries[0]["hits"]))


func _write_save() -> void:
	SaveData.write_save(str(config["save_path"]), save)
	if account != null:
		account.set_save(save)


func _give_reward() -> void:
	last_reward = Logic.reward_coins(last_won, int(config["reward_win_coins"]), int(config["reward_lose_coins"]))
	save["coins"] = int(save.get("coins", 0)) + last_reward
	if last_won:
		save["wins"] = int(save.get("wins", 0)) + 1
	_write_save()


func _process(delta: float) -> void:
	state_time += delta
	_poll_room(delta)
	_poll_account(delta)
	if toast_time > 0.0:
		toast_time -= delta
		if toast_time <= 0.0:
			toast_label.text = ""
	match state:
		Logic.TITLE:
			if state_time >= float(config["title_sec"]):
				event("loaded")
		Logic.BATTLE:
			# 「さいせん」のときは、戦いの画面の用意ができしだい、すぐ始める（最初の1回は、画面の「はじめる」を押す）
			if _rematch_pending and battle != null and not battle.config.is_empty():
				_rematch_pending = false
				battle.start_round()
			if _result_timer > 0.0:
				_result_timer -= delta
				if _result_timer <= 0.0:
					_result_timer = -1.0
					event("ended")
		Logic.REWARD, Logic.NEXT:
			if _room_battle():
				_rematch_update(delta)
		Logic.HIGHLIGHT:
			if _room_battle():
				_rematch_update(delta)
			highlight_replay.advance(delta)
			if state_time >= float(config["highlight_sec"]):
				event("done")


## タイトルは、タッチで飛ばせる
func _unhandled_input(ev: InputEvent) -> void:
	if state == Logic.TITLE and (ev is InputEventScreenTouch or ev is InputEventMouseButton) and ev.is_pressed():
		event("loaded")
