extends Node
## 画面の流れ：タイトル → ロビー → 戦い → ハイライト → 報酬 → さいせん／ロビー（縦画面を先に作る。横でも動く）。
## 戦いは、試作（stick_prototype）をそのまま使う。メニューの画面は、このスクリプトがコードで作る。
## 決まりごとは flow_logic.gd、数値と文字は data/game_flow.json、保存は save_data.gd。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const Quality := preload("res://scripts/core/quality.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Replay := preload("res://scripts/flow/highlight_replay.gd")
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
	_build_panels()
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
func _make_panel(panel_name: String) -> VBoxContainer:
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
	box.add_theme_constant_override("separation", 28)
	root.add_child(box)
	layer.add_child(root)
	panels[panel_name] = root
	return box


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

	# ロビー
	var l := _make_panel(Logic.LOBBY)
	l.add_child(_make_label(str(config["title_text"]), heading, Color(str(config["title_color"]))))
	lobby_info = _make_label("", text_size, text_color)
	l.add_child(lobby_info)
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override("separation", 20)
	stage_row.add_child(_make_button(str(config["stage_prev"]), [110, 90], func(): change_stage(-1)))
	stage_label = _make_label("", heading, text_color)
	stage_label.custom_minimum_size = Vector2(360, 0)
	stage_row.add_child(stage_label)
	stage_row.add_child(_make_button(str(config["stage_next"]), [110, 90], func(): change_stage(1)))
	l.add_child(stage_row)
	play_button = _make_button(str(config["play_label"]), big, play)
	l.add_child(play_button)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	var grid_holder := CenterContainer.new()
	grid_holder.add_child(grid)
	for name_text in config["lobby_buttons"]:
		var cb: Callable = show_toast
		if str(name_text) == str(config["formation_label"]):
			cb = func(): event("formation")
		grid.add_child(_make_button(str(name_text), small, cb))
	l.add_child(grid_holder)
	quality_button = _make_button("", small, change_quality)
	var quality_holder := CenterContainer.new()
	quality_holder.add_child(quality_button)
	l.add_child(quality_holder)
	lobby_char = _make_label("", text_size, text_color)
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
	r.add_child(_make_button(str(config["rematch_label"]), big, func(): event("rematch")))
	r.add_child(_make_button(str(config["next_label"]), big, func(): event("next")))

	# つぎへ（さいせん／ロビー）
	var n := _make_panel(Logic.NEXT)
	n.add_child(_make_button(str(config["rematch_label"]), big, func(): event("rematch")))
	n.add_child(_make_button(str(config["lobby_label"]), big, func(): event("lobby")))


## 状態を切り替える：その画面だけ出す。戦いに入るときは戦いを作り、出るときは片づける
func goto(new_state: String) -> void:
	state = new_state
	state_time = 0.0
	for key in panels:
		(panels[key] as Control).visible = (key == new_state)
	if new_state == Logic.BATTLE:
		_start_battle()
	else:
		_end_battle_node()
	match new_state:
		Logic.LOBBY:
			_refresh_lobby()
		Logic.FORMATION:
			_refresh_formation()
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
	if next_state == Logic.BATTLE and name_text == "rematch":
		_rematch_pending = true
	goto(next_state)


func play() -> void:
	if not bool(config["stages"][stage_index]["open"]):
		show_toast()
		return
	event("play")


func change_stage(step: int) -> void:
	var count: int = (config["stages"] as Array).size()
	stage_index = (stage_index + step + count) % count
	_refresh_lobby()


## 画質を「低」「高」で切り替える（選びは保存する）
func change_quality() -> void:
	quality_name = Quality.next_preset(quality_name, quality_config)
	save["quality"] = quality_name
	SaveData.write_save(str(config["save_path"]), save)
	_apply_quality()
	_refresh_lobby()


func _apply_quality() -> void:
	var lights := get_tree().get_nodes_in_group("sun") if get_tree() != null else []
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
	SaveData.write_save(str(config["save_path"]), save)
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
	play_button.disabled = not bool(stage["open"])
	quality_button.text = str(config["quality_label"]) + "：" + Quality.label_of(quality_name, quality_config)


func _start_battle() -> void:
	_end_battle_node()
	var packed := load(BATTLE_SCENE) as PackedScene
	battle = packed.instantiate()
	battle.flow_mode = true
	battle.selected_character = selected_character
	battle.round_ended.connect(_on_round_ended)
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
	if battle != null:
		highlight_info = battle.highlight_data()
		var entries: Array = battle.ranking_entries()
		if not entries.is_empty():
			best_text = str(config["highlight_best"]) + "：" + battle.role_name_of(str(entries[0]["slot"])) + " " + str(int(entries[0]["hits"]))


func _give_reward() -> void:
	last_reward = Logic.reward_coins(last_won, int(config["reward_win_coins"]), int(config["reward_lose_coins"]))
	save["coins"] = int(save.get("coins", 0)) + last_reward
	if last_won:
		save["wins"] = int(save.get("wins", 0)) + 1
	SaveData.write_save(str(config["save_path"]), save)


func _process(delta: float) -> void:
	state_time += delta
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
		Logic.HIGHLIGHT:
			highlight_replay.advance(delta)
			if state_time >= float(config["highlight_sec"]):
				event("done")


## タイトルは、タッチで飛ばせる
func _unhandled_input(ev: InputEvent) -> void:
	if state == Logic.TITLE and (ev is InputEventScreenTouch or ev is InputEventMouseButton) and ev.is_pressed():
		event("loaded")
