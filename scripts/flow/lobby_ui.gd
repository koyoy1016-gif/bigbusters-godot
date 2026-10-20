extends RefCounted
## 版81：新しいロビーの画面（game_flow.gd から分けた）。状態の変数（play_button・stage_label など）は game_flow.gd に置き、ここで作って入れる。
## 配置：左上＝アイコンと名前（タップでプロフィール）／右上＝ランク（経験のゲージ）とコイン／右端＝フレンド・へやを つくる／
##       まんなか＝3Dのキャラ4人（lobby_stage.gd。左右のスライド・矢印・キーで回す、後ろの人をタップでメインに）／
##       下＝ステージの四角いアイコン（タップで5つの中から選ぶ。未開放はかぎ）とプレイ／いちばん下＝編成・ロビー・ガチャ
## 編成のデータ：メイン＝selected_character、後ろの3人＝ai_picks（回すと両方を保存する）

const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const LobbyStage := preload("res://scripts/flow/lobby_stage.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")

var f: Node  # game_flow.gd
var root: Control
var name_label: Label
var icon: Control
var rank_bar: ProgressBar
var coin_label: Label
var stage_icon: Control
var stage_picker: Control
var stage_picker_box: GridContainer
var nav: Control
var nav_buttons: Dictionary = {}
var press_pos := Vector2.INF
var last_rank := -1


func _init(flow: Node) -> void:
	f = flow


func _c(key: String) -> Color:
	return Color(str(f.config[key]))


func _sz(key: String) -> Vector2:
	var a: Array = f.config[key]
	return Vector2(float(a[0]), float(a[1]))


func _style(color: Color, radius: int = 18, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## 絵と文字の入ったボタン（絵が上・文字が下）
func icon_button(kind: String, text: String, min_size: Vector2, font_size: int, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	for pair in [["normal", color], ["hover", color.lightened(0.12)], ["pressed", color.darkened(0.25)], ["disabled", color.darkened(0.45)]]:
		b.add_theme_stylebox_override(pair[0], _style(pair[1], 22, 6))
	var col := VBoxContainer.new()
	col.name = "Col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := LobbyIcon.new(kind, Color.WHITE)
	ic.name = "Icon"
	ic.custom_minimum_size = Vector2(min_size.y, min_size.y) * (0.5 if text != "" else 0.7)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	if text != "":
		var lab: Label = f._make_label(text, font_size, Color.WHITE)
		lab.name = "Text"
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(lab)
	b.add_child(col)
	b.pressed.connect(f._on_menu_press)
	b.pressed.connect(cb)
	return b


func _place(c: Control, preset: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += offset


# ---------------------------------------------------------------- ロビー

func build_lobby() -> void:
	root = Control.new()
	root.name = Logic.LOBBY
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.layer.add_child(root)
	f.panels[Logic.LOBBY] = root
	# スライド・タップを受ける面（ほかの部品より下）
	var swipe := Control.new()
	swipe.name = "SwipeArea"
	swipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	swipe.gui_input.connect(on_swipe_input)
	root.add_child(swipe)
	var text_size := int(f.config["lobby_small_font_size"])

	# 左上：アイコンと名前（タップでプロフィール）
	var who := Button.new()
	who.name = "Profile"
	who.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		who.add_theme_stylebox_override(st, _style(_c("lobby_top_color").lightened(0.08 if st == "hover" else 0.0), 40, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(78, 78)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", _style(Color("#e8742a"), 39, 0))
	icon = LobbyIcon.new("person", Color.WHITE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.add_child(icon)
	row.add_child(disc)
	var ncol := VBoxContainer.new()
	ncol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
	name_label = f._make_label("", int(f.config["lobby_name_font_size"]), Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.custom_minimum_size = Vector2(200, 0)
	name_label.clip_text = true
	ncol.add_child(name_label)
	var hint: Label = f._make_label(str(f.config["lobby_profile_hint"]), 18, _c("lobby_sub_color"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ncol.add_child(hint)
	row.add_child(ncol)
	who.add_child(row)
	who.custom_minimum_size = Vector2(310, 94)
	row.position = Vector2(8, 8)
	who.pressed.connect(f._on_menu_press)
	who.pressed.connect(func(): f.event("account"))
	root.add_child(who)
	_place(who, Control.PRESET_TOP_LEFT, Vector2(14, 14))

	# 右上：ランク（経験のゲージ）とコイン
	var info := PanelContainer.new()
	info.name = "RankCoin"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_stylebox_override("panel", _style(_c("lobby_top_color"), 20, 10))
	var icol := VBoxContainer.new()
	icol.add_theme_constant_override("separation", 4)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	var star := LobbyIcon.new("star", Color("#ffd24a"))
	star.custom_minimum_size = Vector2(34, 34)
	rrow.add_child(star)
	f.lobby_info = f._make_label("", text_size, Color.WHITE)
	f.lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rrow.add_child(f.lobby_info)
	icol.add_child(rrow)
	rank_bar = ProgressBar.new()
	rank_bar.custom_minimum_size = Vector2(200, 12)
	rank_bar.show_percentage = false
	rank_bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.15), 6, 0))
	rank_bar.add_theme_stylebox_override("fill", _style(Color("#ffd24a"), 6, 0))
	icol.add_child(rank_bar)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	var coin := LobbyIcon.new("coin")
	coin.custom_minimum_size = Vector2(34, 34)
	crow.add_child(coin)
	coin_label = f._make_label("", text_size, Color("#ffe08a"))
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	coin_label.custom_minimum_size = Vector2(150, 0)
	crow.add_child(coin_label)
	icol.add_child(crow)
	info.add_child(icol)
	root.add_child(info)
	_place(info, Control.PRESET_TOP_RIGHT, Vector2(-14, 14))

	# 右端：フレンド・へやを つくる
	var side := VBoxContainer.new()
	side.name = "Side"
	side.add_theme_constant_override("separation", 14)
	var ssz := _sz("lobby_side_button_size")
	var sfs := int(f.config["lobby_side_font_size"])
	var fb := icon_button("friends", str(f.config["lobby_friends_button"]), ssz, sfs, Color("#3a5a8c"), func(): f.event("friends"))
	fb.name = "Friends"
	side.add_child(fb)
	var rb := icon_button("room", str(f.config["lobby_room_button"]), ssz, sfs, Color("#3a5a8c"), func(): f.event("room"))
	rb.name = "Room"
	side.add_child(rb)
	root.add_child(side)
	_place(side, Control.PRESET_TOP_RIGHT, Vector2(-14, 168))

	# 下：キャラの名前と矢印・ステージ・プレイ（キャラの足もと）
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_constant_override("separation", 10)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	f.toast_label = f._make_label("", text_size, Color(1.0, 0.85, 0.4))
	bottom.add_child(f.toast_label)
	f.invite_join_button = f._make_button("", [560, 84], f.join_invite)
	f.invite_join_button.visible = false
	f.invite_join_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(f.invite_join_button)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 12)
	var asz := _sz("lobby_arrow_size")
	var left := icon_button("left", "", asz, 1, Color(0.1, 0.13, 0.2, 0.7), func(): rotate_team(1))
	left.name = "Left"
	name_row.add_child(left)
	f.lobby_char = f._make_label("", int(f.config["lobby_name_font_size"]), Color.WHITE)
	f.lobby_char.custom_minimum_size = Vector2(330, 0)
	f.lobby_char.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	f.lobby_char.add_theme_constant_override("outline_size", 8)
	name_row.add_child(f.lobby_char)
	var right := icon_button("right", "", asz, 1, Color(0.1, 0.13, 0.2, 0.7), func(): rotate_team(-1))
	right.name = "Right"
	name_row.add_child(right)
	bottom.add_child(name_row)
	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	play_row.add_theme_constant_override("separation", 16)
	var stsz := _sz("lobby_stage_button_size")
	var sbtn := Button.new()
	sbtn.name = "Stage"
	sbtn.focus_mode = Control.FOCUS_NONE
	sbtn.custom_minimum_size = stsz
	for pair in [["normal", Color("#2a3648")], ["hover", Color("#34445a")], ["pressed", Color("#1e2836")]]:
		sbtn.add_theme_stylebox_override(pair[0], _style(pair[1], 16, 6))
	var scol := VBoxContainer.new()
	scol.set_anchors_preset(Control.PRESET_FULL_RECT)
	scol.alignment = BoxContainer.ALIGNMENT_CENTER
	scol.add_theme_constant_override("separation", 0)
	scol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_icon = LobbyIcon.new("city")
	stage_icon.custom_minimum_size = Vector2(stsz.x - 30, stsz.y - 52)
	stage_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scol.add_child(stage_icon)
	f.stage_label = f._make_label("", 22, Color.WHITE)
	f.stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scol.add_child(f.stage_label)
	sbtn.add_child(scol)
	sbtn.pressed.connect(f._on_menu_press)
	sbtn.pressed.connect(open_stage_picker)
	play_row.add_child(sbtn)
	f.play_button = f._make_button(str(f.config["play_label"]), f.config["lobby_play_size"], f.play)
	f.play_button.add_theme_font_size_override("font_size", int(f.config["lobby_play_font_size"]))
	f.play_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	f._paint_button(f.play_button, _c("lobby_play_color"))
	play_row.add_child(f.play_button)
	bottom.add_child(play_row)
	root.add_child(bottom)
	_place(bottom, Control.PRESET_CENTER_BOTTOM, Vector2(0, -float(f.config["nav_height"]) - 16))
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_build_stage_picker()


## ステージを選ぶ画面（5つ。未開放は、かぎの絵で、選べない）
func _build_stage_picker() -> void:
	stage_picker = Control.new()
	stage_picker.name = "StagePicker"
	stage_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.1, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_picker.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	col.add_child(f._make_label(str(f.config["stage_picker_title"]), int(f.config["heading_font_size"]) - 16, Color.WHITE))
	var holder := CenterContainer.new()
	stage_picker_box = GridContainer.new()
	stage_picker_box.columns = 3
	stage_picker_box.add_theme_constant_override("h_separation", 14)
	stage_picker_box.add_theme_constant_override("v_separation", 14)
	holder.add_child(stage_picker_box)
	col.add_child(holder)
	var close: Button = f._make_button(str(f.config["back_label"]), f.config["small_button_min_size"], close_stage_picker)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(close)
	stage_picker.add_child(col)
	stage_picker.visible = false
	root.add_child(stage_picker)


func open_stage_picker() -> void:
	f._clear_box(stage_picker_box)
	var stages: Array = f.config["stages"]
	for i in stages.size():
		var st: Dictionary = stages[i]
		var open := bool(st.get("open", false))
		var color := Color("#e8742a") if i == f.stage_index else (Color("#2a3648") if open else Color("#1a2230"))
		var b := icon_button(str(st.get("icon", "city")) if open else "lock", str(st["name"]) if open else str(f.config["stage_locked_note"]),
			Vector2(180, 180), 22, color, func(): pick_stage(i))
		b.name = "Stage%d" % i
		if not open:
			(b.get_node("Col/Icon") as Control).modulate = Color(1, 1, 1, 0.6)
		stage_picker_box.add_child(b)
	stage_picker.visible = true


func close_stage_picker() -> void:
	stage_picker.visible = false


## ステージを選ぶ。未開放は選べない（「まだ あそべません」と出す。戦いは始まらない）
func pick_stage(i: int) -> void:
	var stages: Array = f.config["stages"]
	if i < 0 or i >= stages.size():
		return
	if not bool(stages[i].get("open", false)):
		f.toast_label.text = str(f.config["stage_locked_toast"])
		f.toast_time = 2.0
		return
	f.stage_index = i
	close_stage_picker()
	f._refresh_lobby()


# ---------------------------------------------------------------- 編成を回す

## 編成の4人（メイン＋後ろの3人）
func team() -> Array:
	var t: Array = [str(f.selected_character)]
	for id in f.ai_picks:
		t.append(str(id))
	return t


## 編成を回す。step=1：左の人がまんなかへ（右へスライド）、step=-1：右の人がまんなかへ（左へスライド）
func rotate_team(step: int) -> void:
	var t := team()
	var n := t.size()
	if n < 2:
		return
	var out: Array = []
	for i in n:
		out.append(t[(i + step + n * 4) % n])
	_apply_team(out)


## 後ろの人（slot）をタップ：その人をメインにする（メインだった人は、その場所へ）
func pick_slot(slot: int) -> void:
	var t := team()
	if slot <= 0 or slot >= t.size():
		return
	var tmp: String = t[0]
	t[0] = t[slot]
	t[slot] = tmp
	_apply_team(t)


func _apply_team(t: Array) -> void:
	f.selected_character = str(t[0])
	f.save["character"] = f.selected_character
	f.ai_picks = t.slice(1)
	SaveData.write_ai_picks(str(f.config["ai_picks_path"]), f.ai_picks)
	f._write_save()
	f._refresh_ai_buttons()
	if f.lobby_stage != null:
		f.lobby_stage.set_team(t)
	refresh()


## スライド（左右）とタップ（キャラを選ぶ）
func on_swipe_input(ev: InputEvent) -> void:
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = ev.pressed
		released = not ev.pressed
		pos = (ev as InputEventMouseButton).position
	elif ev is InputEventScreenTouch:
		pressed = ev.pressed
		released = not ev.pressed
		pos = (ev as InputEventScreenTouch).position
	if pressed:
		press_pos = pos
	elif released and press_pos != Vector2.INF:
		gesture(press_pos, pos)
		press_pos = Vector2.INF


## 押した所と離した所から：横に swipe_px 以上なら回す、ほとんど動いていなければタップ（キャラを選ぶ）
func gesture(from: Vector2, to: Vector2) -> String:
	var d := to - from
	var swipe_px := float(f.lobby_stage.cfg.get("swipe_px", 70.0)) if f.lobby_stage != null else 70.0
	if absf(d.x) >= swipe_px and absf(d.x) > absf(d.y):
		rotate_team(1 if d.x > 0.0 else -1)
		return "swipe"
	if d.length() < swipe_px * 0.5 and f.lobby_stage != null:
		var slot: int = f.lobby_stage.pick(to)
		if slot > 0:
			pick_slot(slot)
			return "pick"
	return ""


## キーボード（パソコン）：左右の矢印
func on_key(ev: InputEvent) -> bool:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if (ev as InputEventKey).keycode == KEY_LEFT:
			rotate_team(1)
			return true
		if (ev as InputEventKey).keycode == KEY_RIGHT:
			rotate_team(-1)
			return true
	return false


# ---------------------------------------------------------------- 表示を合わせる

func refresh() -> void:
	var cfgf: Dictionary = f.config
	var wins := int(f.save.get("wins", 0))
	var wpr := maxi(1, int(cfgf["wins_per_rank"]))
	var rank: int = Logic.player_rank(wins, wpr)
	f.lobby_info.text = str(cfgf["lobby_rank_label"]) + " " + str(rank)
	rank_bar.max_value = wpr
	rank_bar.value = wins % wpr
	coin_label.text = str(int(f.save.get("coins", 0)))
	if last_rank >= 0 and rank > last_rank:
		f.toast_label.text = str(cfgf["lobby_rank_up"]) + " " + str(cfgf["lobby_rank_label"]) + " " + str(rank)
		f.toast_time = 3.0
		var tw := root.create_tween() if root.is_inside_tree() else null
		if tw != null:
			f.toast_label.pivot_offset = f.toast_label.size * 0.5
			f.toast_label.scale = Vector2(1.6, 1.6)
			tw.tween_property(f.toast_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	last_rank = rank
	var st: Dictionary = f.account_state
	var nick := str(st.get("nickname", "")) if bool(st.get("signedIn", false)) else ""
	name_label.text = nick if nick != "" else str(cfgf["lobby_guest_name"])
	var stage: Dictionary = cfgf["stages"][f.stage_index]
	f.stage_label.text = str(stage["name"])
	stage_icon.set_kind(str(stage.get("icon", "city")) if bool(stage.get("open", false)) else "lock")
	var cdef := CharacterData.find(f.characters_cfg, str(f.selected_character))
	f.lobby_char.text = (str(cdef["role"]) + " " + str(cdef["name"])) if not cdef.is_empty() else ""
	set_nav_selected(f.state)


# ---------------------------------------------------------------- いちばん下の3つ

func build_nav_bar() -> void:
	nav = PanelContainer.new()
	nav.name = "NavBar"
	nav.add_theme_stylebox_override("panel", _style(_c("nav_color"), 0, 8))
	var h := float(f.config["nav_height"])
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -h
	nav.offset_bottom = 0
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for item in [["formation", "person", "nav_formation"], ["lobby", "home", "nav_lobby"], ["gacha", "gacha", "nav_gacha"]]:
		var key: String = item[0]
		var b := icon_button(item[1], str(f.config[item[2]]), Vector2(190, h - 18), 24, _c("nav_button_color"), func(): nav_press(key))
		b.name = key.capitalize()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_buttons[key] = b
		row.add_child(b)
	nav.add_child(row)
	f.layer.add_child(nav)


func nav_press(key: String) -> void:
	match key:
		"lobby":
			if f.state != Logic.LOBBY:
				f.goto(Logic.LOBBY)  # ロビーにいる時は、何もしない（作り直さない）
		"formation":
			if f.state == Logic.LOBBY:
				f.event("formation")
			elif f.state != Logic.FORMATION:
				f.goto(Logic.FORMATION)
		"gacha":
			f.toast_label.text = str(f.config["gacha_soon"])
			f.toast_time = 2.0
			if f.state != Logic.LOBBY:
				f.goto(Logic.LOBBY)


## いま開いている画面のボタンを、色で目立たせる。ロビー・編成の画面だけで出す
func set_nav_selected(state: String) -> void:
	if nav == null:
		return
	nav.visible = state in [Logic.LOBBY, Logic.FORMATION]
	var on := "lobby" if state == Logic.LOBBY else ("formation" if state == Logic.FORMATION else "")
	for key in nav_buttons:
		var b: Button = nav_buttons[key]
		var col := _c("nav_selected_color") if key == on else _c("nav_button_color")
		for pair in [["normal", col], ["hover", col.lightened(0.12)], ["pressed", col.darkened(0.25)]]:
			b.add_theme_stylebox_override(pair[0], _style(pair[1], 22, 6))


# ---------------------------------------------------------------- へや

func build_room_panel() -> void:
	var p: VBoxContainer = f._make_lobby_panel(Logic.ROOM, 18)
	p.add_child(f._make_label(str(f.config["room_title"]), int(f.config["heading_font_size"]), Color(str(f.config["title_color"]))))
	f.room_label = f._make_label("", int(f.config["text_font_size"]), Color.WHITE)
	p.add_child(f.room_label)
	f.party_box = VBoxContainer.new()
	f.party_box.add_theme_constant_override("separation", 8)
	p.add_child(f.party_box)
	var team_label: Label = f._make_label("", int(f.config["lobby_small_font_size"]), _c("lobby_sub_color"))
	team_label.name = "TeamLabel"
	team_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	team_label.custom_minimum_size = Vector2(580, 0)
	p.add_child(team_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	f.invite_button = f._make_button(str(f.config["invite_label"]), [282, 90], f.invite)
	f.leave_button = f._make_button(str(f.config["new_room_label"]), [282, 90], f.new_room)
	f._paint_button(f.invite_button, _c("lobby_nav_color"))
	f._paint_button(f.leave_button, _c("lobby_nav_color"))
	row.add_child(f.invite_button)
	row.add_child(f.leave_button)
	p.add_child(row)
	var start: Button = f._make_button(str(f.config["room_start_label"]), f.config["button_min_size"], func():
		f.goto(Logic.LOBBY)
		f.play())
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	f._paint_button(start, _c("lobby_play_color"))
	p.add_child(start)
	var note: Label = f._make_label(str(f.config["room_name_note"]), 22, _c("lobby_sub_color"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(580, 0)
	p.add_child(note)
	var back: Button = f._make_button(str(f.config["back_label"]), f.config["button_min_size"], func(): f.event("back"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(back)


## へやの画面の、編成の確認（4人）
func refresh_room() -> void:
	var lab := f.panels[Logic.ROOM].find_child("TeamLabel", true, false) as Label
	if lab == null:
		return
	var names: Array = []
	for id in team():
		var d := CharacterData.find(f.characters_cfg, str(id))
		names.append(str(d.get("name", id)))
	lab.text = str(f.config["room_team_label"]) + "：" + " ／ ".join(names)
