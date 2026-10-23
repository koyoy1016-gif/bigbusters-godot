extends RefCounted
## 版81：新しいロビーの画面（game_flow.gd から分けた）。状態の変数（play_button・stage_label など）は game_flow.gd に置き、ここで作って入れる。
## 版81b：見た目を仕上げた（ガラスのようなパネル・太い字・光るプレイ・3Dの顔のアイコン・上下の暗がり・出る時の動き・押した時の手ざわり）。
## 配置：左上＝アイコンと名前（タップでプロフィール）／右上＝ランク（経験のゲージ）とコイン／右端＝フレンド・へやを つくる／
##       まんなか＝3Dのキャラ4人（lobby_stage.gd。左右のスライド・矢印・キーで回す、後ろの人をタップでメインに）／
##       下＝役と名前・ステージの四角いアイコン（タップで5つの中から選ぶ。未開放はかぎ）とプレイ／いちばん下＝編成・ロビー・ガチャ
## 編成のデータ：メイン＝selected_character、後ろの3人＝ai_picks（回すと両方を保存する）
## 色・大きさは data/game_flow.json（"ui_kit"・"role_colors"・"lobby_*"）

const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const RoleLabel := preload("res://scripts/ui/role_label.gd")

var f: Node  # game_flow.gd
var root: Control
var name_label: Label
var name_sub: Label
var icon: Control  # 図形のアイコン（3Dの顔の絵ができるまで）
var avatar_tex: TextureRect  # 3Dの顔の絵
var avatar_disc: Panel
var rank_bar: ProgressBar
var rank_next: Label
var coin_label: Label
var role_pill: PanelContainer
var role_label: Label
var stage_icon: Control
var stage_picker: Control
var stage_picker_box: GridContainer
var play_skin: Control  # プレイの色（FancyRect）
var play_glow_tween: Tween
var toast_pill: Control
var friend_badge: Control
var friend_badge_label: Label
var nav: Control
var nav_buttons: Dictionary = {}
var nav_marks: Dictionary = {}
var enter_groups: Array = []  # 出る時の動き：[{node, from（ずらす量）}]
var enter_tween: Tween
var press_pos := Vector2.INF
var last_rank := -1
var badge_timer := 0.0
var bold: Font


func _init(flow: Node) -> void:
	f = flow


func _c(key: String) -> Color:
	return Color(str(f.config[key]))


func _k(key: String, def: Variant) -> Variant:
	return (f.config.get("ui_kit", {}) as Dictionary).get(key, def)


func _sz(key: String) -> Vector2:
	var a: Array = f.config[key]
	return Vector2(float(a[0]), float(a[1]))


func _style(color: Color, radius: int = 18, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(UiKit.corner(f.config, radius))  # 版113：角ばった見た目
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _label(text: String, size: int, color: Color, use_bold: bool = false) -> Label:
	var l: Label = f._make_label(text, size, color)
	if use_bold and bold != null:
		l.add_theme_font_override("font", bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 絵と文字の入ったボタン（絵が上・文字が下）。ガラスの見た目・押した時の手ざわり
func icon_button(kind: String, text: String, min_size: Vector2, font_size: int, color: Color, cb: Callable, radius: int = 22) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	UiKit.glass_button(b, f.config, radius, color)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := LobbyIcon.new(kind, Color.WHITE)
	ic.name = "Icon"
	ic.custom_minimum_size = Vector2(min_size.y, min_size.y) * (0.46 if text != "" else 0.6)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	if text != "":
		var lab := _label(text, font_size, Color.WHITE, true)
		lab.name = "Text"
		col.add_child(lab)
	b.add_child(col)
	b.pressed.connect(f._on_menu_press)
	b.pressed.connect(cb)
	UiKit.juice(b)
	return b


func _place(c: Control, preset: int, offset: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.position += offset


func _enter(node: Control, from: Vector2) -> void:
	enter_groups.append({"node": node, "from": from})


# ---------------------------------------------------------------- ロビー

func build_lobby() -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	root = Control.new()
	root.name = Logic.LOBBY
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.layer.add_child(root)
	f.panels[Logic.LOBBY] = root
	# 上下の暗がり（3Dの上でも字が読めるように）
	root.add_child(UiKit.vignette(true, float(_k("vignette_top", 200)), Color(str(_k("vignette_color", "#0a0e1ab0")))))
	root.add_child(UiKit.vignette(false, float(_k("vignette_bottom", 460)), Color(str(_k("vignette_color", "#0a0e1ab0")))))
	# スライド・タップを受ける面（ほかの部品より下）
	var swipe := Control.new()
	swipe.name = "SwipeArea"
	swipe.set_anchors_preset(Control.PRESET_FULL_RECT)
	swipe.mouse_filter = Control.MOUSE_FILTER_STOP
	swipe.gui_input.connect(on_swipe_input)
	root.add_child(swipe)
	_build_profile()
	_build_rank_coin()
	_build_side()
	_build_bottom()
	_build_stage_picker()


## 左上：まるいアイコン（3Dの顔の絵）と名前
func _build_profile() -> void:
	var who := Button.new()
	who.name = "Profile"
	who.focus_mode = Control.FOCUS_NONE
	var pill := UiKit.glass(f.config, 48)
	pill.set_content_margin_all(0)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = pill.duplicate()
		if st == "hover":
			sb.bg_color = sb.bg_color.lightened(0.1)
		who.add_theme_stylebox_override(st, sb)
	who.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(8, 8)
	# アイコン：役の色の丸の中に、顔の絵（丸く切りぬく）。まわりに金の輪
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(80, 80)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_disc = Panel.new()
	avatar_disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_disc.add_theme_stylebox_override("panel", _style(Color("#e8742a"), 40, 0))
	avatar_disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	icon = LobbyIcon.new("person", Color.WHITE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_disc.add_child(icon)
	avatar_tex = TextureRect.new()
	avatar_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_disc.add_child(avatar_tex)
	holder.add_child(avatar_disc)
	var ring := Panel.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := _style(Color(0, 0, 0, 0), 40, 0)
	rsb.set_border_width_all(3)
	rsb.border_color = Color(str(_k("gold", "#ffd45a")))
	ring.add_theme_stylebox_override("panel", rsb)
	holder.add_child(ring)
	row.add_child(holder)
	var ncol := VBoxContainer.new()
	ncol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
	ncol.add_theme_constant_override("separation", 0)
	name_label = _label("", int(f.config["lobby_name_font_size"]), Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.custom_minimum_size = Vector2(190, 0)
	name_label.clip_text = true
	ncol.add_child(name_label)
	name_sub = _label(str(f.config["lobby_profile_hint"]), 18, Color(str(_k("sub_text", "#b9c4dc"))))
	name_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ncol.add_child(name_sub)
	row.add_child(ncol)
	who.add_child(row)
	who.custom_minimum_size = Vector2(318, 96)
	who.pressed.connect(f._on_menu_press)
	who.pressed.connect(func(): f.event("account"))
	UiKit.juice(who, 0.96)
	root.add_child(who)
	_place(who, Control.PRESET_TOP_LEFT, Vector2(14, 14))
	_enter(who, Vector2(-40, 0))


## 右上：ランク（星のしるし・経験のゲージ・つぎまで）とコイン
func _build_rank_coin() -> void:
	var info := PanelContainer.new()
	info.name = "RankCoin"
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_stylebox_override("panel", UiKit.glass(f.config, 20))
	var icol := VBoxContainer.new()
	icol.add_theme_constant_override("separation", 5)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	var badge := FancyRect.new().setup(Color("#ffe58a"), Color("#e8a21e"), 18, Color(1, 0.8, 0.3, 0.6), 4)
	badge.custom_minimum_size = Vector2(38, 38)
	badge.border_color = Color(1, 1, 1, 0.6)
	var star := LobbyIcon.new("star", Color("#7a4a08"))
	star.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(star)
	rrow.add_child(badge)
	f.lobby_info = _label("", int(f.config["lobby_small_font_size"]), Color.WHITE, true)
	f.lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rrow.add_child(f.lobby_info)
	icol.add_child(rrow)
	rank_bar = ProgressBar.new()
	rank_bar.custom_minimum_size = Vector2(204, 12)
	rank_bar.show_percentage = false
	var bg_sb := _style(Color(1, 1, 1, 0.14), 6, 0)
	rank_bar.add_theme_stylebox_override("background", bg_sb)
	var fill := _style(Color(str(_k("gold", "#ffd45a"))), 6, 0)
	fill.border_width_bottom = 3
	fill.border_color = Color("#e09a1a")
	rank_bar.add_theme_stylebox_override("fill", fill)
	icol.add_child(rank_bar)
	rank_next = _label("", 17, Color(str(_k("sub_text", "#b9c4dc"))))
	rank_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	icol.add_child(rank_next)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.custom_minimum_size = Vector2(0, 2)
	icol.add_child(sep)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	var coin := LobbyIcon.new("coin")
	coin.custom_minimum_size = Vector2(34, 34)
	crow.add_child(coin)
	coin_label = _label("", int(f.config["lobby_small_font_size"]), Color("#ffe08a"), true)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	coin_label.custom_minimum_size = Vector2(150, 0)
	crow.add_child(coin_label)
	icol.add_child(crow)
	info.add_child(icol)
	root.add_child(info)
	_place(info, Control.PRESET_TOP_RIGHT, Vector2(-14, 14))
	_enter(info, Vector2(40, 0))


## 右端：フレンド（おしらせの数）・へやを つくる。まるいガラスのボタンと、下に文字
func _build_side() -> void:
	var side := VBoxContainer.new()
	side.name = "Side"
	side.add_theme_constant_override("separation", 12)
	var ssz := _sz("lobby_side_button_size")
	var sfs := int(f.config["lobby_side_font_size"])
	for item in [["Friends", "friends", "lobby_friends_button", "friends"], ["Room", "room", "lobby_room_button", "room"]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(ssz.x, ssz.x)
		var ev: String = item[3]
		var b := icon_button(item[1], "", Vector2(ssz.x, ssz.x), 1, Color(str(_k("side_color", "#2d4a7acc"))), func(): f.event(ev), int(ssz.x / 2))
		b.name = item[0]
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(b)
		if item[0] == "Friends":
			# フレンドの申しこみ・しょうたいの数（赤い丸）
			friend_badge = Panel.new()
			friend_badge.name = "Badge"
			friend_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bsb := _style(Color("#ff4a5a"), 14, 0)
			bsb.set_border_width_all(2)
			bsb.border_color = Color.WHITE
			friend_badge.add_theme_stylebox_override("panel", bsb)
			friend_badge.custom_minimum_size = Vector2(28, 28)
			friend_badge.size = Vector2(28, 28)
			friend_badge.position = Vector2(ssz.x - 24, -4)
			friend_badge_label = _label("", 16, Color.WHITE, true)
			friend_badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			friend_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			friend_badge.add_child(friend_badge_label)
			friend_badge.visible = false
			holder.add_child(friend_badge)
		col.add_child(holder)
		var lab := UiKit.outline(_label(str(f.config[item[2]]), sfs, Color.WHITE, true), 5)
		col.add_child(lab)
		side.add_child(col)
	root.add_child(side)
	_place(side, Control.PRESET_TOP_RIGHT, Vector2(-16, 214))
	_enter(side, Vector2(60, 0))


## 下：役と名前（左右の矢印）・ステージ・プレイ・おしらせ
func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.add_theme_constant_override("separation", 12)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	var text_size := int(f.config["lobby_small_font_size"])
	# おしらせ（ガラスの丸い帯。字がない時は隠す）
	var tholder := CenterContainer.new()
	toast_pill = PanelContainer.new()
	toast_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := UiKit.glass(f.config, 26)
	tsb.set_content_margin(SIDE_LEFT, 22)
	tsb.set_content_margin(SIDE_RIGHT, 22)
	toast_pill.add_theme_stylebox_override("panel", tsb)
	f.toast_label = _label("", text_size - 2, Color(str(_k("gold", "#ffd45a"))), true)
	toast_pill.add_child(f.toast_label)
	toast_pill.visible = false
	tholder.add_child(toast_pill)
	bottom.add_child(tholder)
	f.invite_join_button = f._make_button("", [560, 84], f.join_invite)
	f.invite_join_button.visible = false
	f.invite_join_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.glass_button(f.invite_join_button, f.config, 26, Color("#2f6b48dd"))
	bottom.add_child(f.invite_join_button)
	# 役（色の札）と名前、左右の矢印
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 14)
	var asz := _sz("lobby_arrow_size")
	var left := icon_button("left", "", asz, 1, Color(str(_k("arrow_color", "#0e1526a0"))), func(): rotate_team(1), int(asz.x / 2))
	left.name = "Left"
	name_row.add_child(left)
	var ncol := VBoxContainer.new()
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
	ncol.add_theme_constant_override("separation", 2)
	ncol.custom_minimum_size = Vector2(320, 0)
	var pill_holder := CenterContainer.new()
	role_pill = PanelContainer.new()
	role_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_label = _label("", 19, Color.WHITE, true)
	role_pill.add_child(role_label)
	pill_holder.add_child(role_pill)
	ncol.add_child(pill_holder)
	# 版109：名前は、役職のラベル（役職の色の札。scripts/ui/role_label.gd）
	f.lobby_char = RoleLabel.new().setup("", Color.WHITE, bold, int(f.config["lobby_name_font_size"]) + 4)
	f.lobby_char.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ncol.add_child(f.lobby_char)
	name_row.add_child(ncol)
	var right := icon_button("right", "", asz, 1, Color(str(_k("arrow_color", "#0e1526a0"))), func(): rotate_team(-1), int(asz.x / 2))
	right.name = "Right"
	name_row.add_child(right)
	bottom.add_child(name_row)
	# ステージ（左）とプレイ（右）
	var play_row := HBoxContainer.new()
	play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	play_row.add_theme_constant_override("separation", 16)
	play_row.add_child(_build_stage_tile())
	play_row.add_child(_build_play())
	bottom.add_child(play_row)
	root.add_child(bottom)
	_place(bottom, Control.PRESET_CENTER_BOTTOM, Vector2(0, -float(f.config["nav_height"]) - 18))
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_enter(bottom, Vector2(0, 60))


## ステージの四角：絵・下に名前（暗いグラデーションの上）・上に「ステージ」
func _build_stage_tile() -> Control:
	var stsz := _sz("lobby_stage_button_size")
	var sbtn := Button.new()
	sbtn.name = "Stage"
	sbtn.focus_mode = Control.FOCUS_NONE
	sbtn.custom_minimum_size = stsz
	UiKit.clear_button(sbtn)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _style(Color("#1a2234"), 20, 0))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	stage_icon = LobbyIcon.new("city")
	stage_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(stage_icon)
	var shade := UiKit.vignette(false, stsz.y * 0.55, Color(0.03, 0.04, 0.08, 0.92))
	frame.add_child(shade)
	sbtn.add_child(frame)
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := _style(Color(0, 0, 0, 0), 20, 0)
	bsb.set_border_width_all(2)
	bsb.border_color = Color(1, 1, 1, 0.45)
	border.add_theme_stylebox_override("panel", bsb)
	sbtn.add_child(border)
	var cap := UiKit.outline(_label(str(f.config["lobby_stage_label"]), 16, Color(str(_k("gold", "#ffd45a"))), true), 4)
	cap.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	cap.position = Vector2(10, 6)
	sbtn.add_child(cap)
	f.stage_label = UiKit.outline(_label("", 20, Color.WHITE, true), 4)
	f.stage_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	f.stage_label.offset_top = -34
	f.stage_label.offset_bottom = -6
	sbtn.add_child(f.stage_label)
	sbtn.pressed.connect(f._on_menu_press)
	sbtn.pressed.connect(open_stage_picker)
	UiKit.juice(sbtn)
	return sbtn


## プレイ：オレンジのグラデーションと、ゆっくり脈打つ光
func _build_play() -> Control:
	var psz := _sz("lobby_play_size")
	var holder := Control.new()
	holder.name = "PlayHolder"
	holder.custom_minimum_size = psz
	play_skin = FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 26,
		Color(str(_k("play_glow", "#ff7a2a"))), 10)
	play_skin.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_skin.border_color = Color(1, 1, 1, 0.5)
	holder.add_child(play_skin)
	f.play_button = f._make_button(str(f.config["play_label"]), [psz.x, psz.y], f.play)
	f.play_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.play_button.add_theme_font_size_override("font_size", int(f.config["lobby_play_font_size"]))
	if bold != null:
		f.play_button.add_theme_font_override("font", bold)
	f.play_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.clear_button(f.play_button)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		f.play_button.add_theme_color_override(st, Color.WHITE)
	f.play_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	f.play_button.add_theme_color_override("font_outline_color", Color(0.55, 0.18, 0.04, 0.7))
	f.play_button.add_theme_constant_override("outline_size", 6)
	holder.add_child(f.play_button)
	# 押した時：色の板もいっしょにちぢむ
	f.play_button.button_down.connect(func(): _press_holder(holder, 0.94))
	f.play_button.button_up.connect(func(): _press_holder(holder, 1.0))
	return holder


func _press_holder(c: Control, k: float) -> void:
	c.pivot_offset = c.size * 0.5
	if c.is_inside_tree():
		c.create_tween().tween_property(c, "scale", Vector2.ONE * k, 0.08 if k < 1.0 else 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## プレイの色を、押せる・押せないに合わせる（game_flow の _refresh_play_button から呼ぶ）
func refresh_play_skin() -> void:
	if play_skin == null:
		return
	var off: bool = f.play_button.disabled
	play_skin.top_color = Color("#6b7384") if off else Color(str(_k("play_top", "#ffb84d")))
	play_skin.bottom_color = Color("#3f4656") if off else Color(str(_k("play_bottom", "#f04e23")))
	play_skin.glow_color = Color(0, 0, 0, 0) if off else Color(str(_k("play_glow", "#ff7a2a")))
	var waiting: bool = f.waiting_ready
	f.play_button.add_theme_font_size_override("font_size", 28 if (waiting or off and str(f.play_button.text).length() > 6) else int(f.config["lobby_play_font_size"]))


## ステージを選ぶ画面（5つ。未開放は、かぎの絵で、選べない）
func _build_stage_picker() -> void:
	stage_picker = Control.new()
	stage_picker.name = "StagePicker"
	stage_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_picker.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	col.add_child(UiKit.outline(_label(str(f.config["stage_picker_title"]), int(f.config["heading_font_size"]) - 14, Color.WHITE, true), 6))
	var holder := CenterContainer.new()
	stage_picker_box = GridContainer.new()
	stage_picker_box.columns = 3
	stage_picker_box.add_theme_constant_override("h_separation", 16)
	stage_picker_box.add_theme_constant_override("v_separation", 16)
	holder.add_child(stage_picker_box)
	col.add_child(holder)
	var close: Button = f._make_button(str(f.config["back_label"]), f.config["small_button_min_size"], close_stage_picker)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.glass_button(close, f.config, 26)
	UiKit.juice(close)
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
		var b := Button.new()
		b.name = "Stage%d" % i
		b.custom_minimum_size = Vector2(176, 206)
		b.focus_mode = Control.FOCUS_NONE
		var sel: bool = i == f.stage_index
		UiKit.glass_button(b, f.config, 22, Color("#3a2410e0") if sel else (Color("#16203ae0") if open else Color("#0d1220e0")))
		var col := VBoxContainer.new()
		col.name = "Col"
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 10
		col.offset_right = -10
		col.offset_top = 10
		col.offset_bottom = -8
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 6)
		var pic := Panel.new()
		pic.custom_minimum_size = Vector2(156, 132)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_theme_stylebox_override("panel", _style(Color("#1a2234"), 14, 0))
		pic.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var ic := LobbyIcon.new(str(st.get("icon", "city")) if open else "lock", Color(1, 1, 1, 0.55))
		ic.name = "Icon"
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		if not open:
			ic.offset_left = 40
			ic.offset_right = -40
			ic.offset_top = 26
			ic.offset_bottom = -26
		pic.add_child(ic)
		col.add_child(pic)
		var nm := _label(str(st["name"]) if open else str(f.config["stage_locked_note"]), 21 if open else 18,
			Color.WHITE if open else Color(1, 1, 1, 0.5), true)
		col.add_child(nm)
		b.add_child(col)
		if sel:
			var mark := FancyRect.new().setup(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 22, Color(str(_k("play_glow", "#ff7a2a"))), 8)
			mark.shine = 0.0
			mark.border_color = Color(str(_k("gold", "#ffd45a")))
			mark.border_width = 3.0
			mark.set_anchors_preset(Control.PRESET_FULL_RECT)
			mark.show_behind_parent = true
			b.add_child(mark)
		b.pressed.connect(f._on_menu_press)
		b.pressed.connect(func(): pick_stage(i))
		UiKit.juice(b)
		stage_picker_box.add_child(b)
	stage_picker.visible = true
	if stage_picker.is_inside_tree():
		stage_picker.modulate.a = 0.0
		stage_picker.create_tween().tween_property(stage_picker, "modulate:a", 1.0, 0.18)


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


# ---------------------------------------------------------------- 出る時の動き

## ロビーに入った時：上の部品は横から、下の部品は下から、すっと出る
func play_enter() -> void:
	if root == null or not root.is_inside_tree():
		return
	finish_enter()
	await root.get_tree().process_frame  # 位置が決まってから動かす
	if enter_tween != null and enter_tween.is_valid():
		enter_tween.kill()
	enter_tween = root.create_tween().set_parallel(true)
	var k := 0
	for g in enter_groups:
		var n: Control = g["node"]
		var base := n.position
		n.set_meta("enter_base", base)
		n.position = base + (g["from"] as Vector2)
		n.modulate.a = 0.0
		enter_tween.tween_property(n, "position", base, 0.42).set_delay(0.05 * k).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		enter_tween.tween_property(n, "modulate:a", 1.0, 0.3).set_delay(0.05 * k)
		k += 1


## 出る動きを、すぐ終わらせる（テスト・画面の切りかえ）
func finish_enter() -> void:
	if enter_tween != null and enter_tween.is_valid():
		enter_tween.kill()
	for g in enter_groups:
		var n: Control = g["node"]
		if n.has_meta("enter_base"):
			n.position = n.get_meta("enter_base")
			n.remove_meta("enter_base")
		n.modulate.a = 1.0


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
	# 名前の札が、ぽんと出なおす
	var plate: Control = f.lobby_char.get_parent()
	if plate != null and plate.is_inside_tree():
		plate.pivot_offset = plate.size * 0.5
		plate.scale = Vector2(0.86, 0.86)
		plate.create_tween().tween_property(plate, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## スライド（左右）とタップ（キャラを選ぶ）。動かしている間は、カメラが少しずれる（奥行きが見える）
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
	elif (ev is InputEventMouseMotion or ev is InputEventScreenDrag) and press_pos != Vector2.INF and f.lobby_stage != null:
		var w := maxf(root.size.x, 1.0)
		f.lobby_stage.drag = clampf(((ev.position as Vector2).x - press_pos.x) / w, -1.0, 1.0)
		return
	if pressed:
		press_pos = pos
	elif released and press_pos != Vector2.INF:
		if f.lobby_stage != null:
			f.lobby_stage.drag = 0.0
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
		if slot >= 0:
			open_formation(slot)  # 版87：タップしたキャラの編成へ（前は、メインと入れかえていた）
			return "pick"
	return ""


## 版87：ロビーでキャラをタップした：編成の画面を、そのキャラの枠を選んだ状態（入れかえ待ち）で開く
func open_formation(slot: int) -> void:
	if f.formation_ui != null:
		f.formation_ui.open_slot(slot)
	if f.menu_sfx != null:
		f.menu_sfx.play("click")
	nav_press("formation")


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
	rank_next.text = str(cfgf["lobby_rank_next"]).replace("{n}", str(wpr - wins % wpr))
	coin_label.text = str(int(f.save.get("coins", 0)))
	if last_rank >= 0 and rank > last_rank:
		f.toast_label.text = str(cfgf["lobby_rank_up"]) + " " + str(cfgf["lobby_rank_label"]) + " " + str(rank)
		f.toast_time = 3.0
		if toast_pill.is_inside_tree():
			toast_pill.visible = true
			toast_pill.pivot_offset = toast_pill.size * 0.5
			toast_pill.scale = Vector2(1.5, 1.5)
			toast_pill.create_tween().tween_property(toast_pill, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	last_rank = rank
	var st: Dictionary = f.account_state
	var signed := bool(st.get("signedIn", false))
	var nick := str(st.get("nickname", "")) if signed else ""
	name_label.text = nick if nick != "" else str(cfgf["lobby_guest_name"])
	name_sub.text = str(cfgf["lobby_profile_hint"])
	var stage: Dictionary = cfgf["stages"][f.stage_index]
	f.stage_label.text = str(stage["name"])
	stage_icon.set_kind(str(stage.get("icon", "city")) if bool(stage.get("open", false)) else "lock")
	var cdef := CharacterData.find(f.characters_cfg, str(f.selected_character))
	# 役は色の札に、名前は大きな字に
	f.lobby_char.text = str(cdef["name"]) if not cdef.is_empty() else ""
	if not cdef.is_empty():
		f.lobby_char.color = Color(str(cdef.get("role_color", "#ffffff")))
	role_label.text = str(cdef["role"]) if not cdef.is_empty() else ""
	role_pill.visible = not cdef.is_empty()
	if not cdef.is_empty():
		var rc := role_color(str(cdef["role"]))
		var psb := _style(rc, 14, 3)
		psb.set_content_margin(SIDE_LEFT, 16)
		psb.set_content_margin(SIDE_RIGHT, 16)
		psb.set_border_width_all(2)
		psb.border_color = rc.lightened(0.45)
		role_pill.add_theme_stylebox_override("panel", psb)
	_refresh_avatar()
	_refresh_badge()
	set_nav_selected(f.state)


## 役の色（ファイター＝赤・シューター＝黄・ガーディアン＝青・サポート＝緑）
func role_color(role: String) -> Color:
	var rc: Dictionary = f.config.get("role_colors", {})
	return Color(str(rc.get(role, "#5a6a88")))


## 左上のアイコン：お気に入りのキャラ（まだ選べないので、いまは剣士）の3Dの顔の絵
func _refresh_avatar() -> void:
	var id := str(f.save.get("icon_char", f.config.get("default_icon_char", "hero_swordsman")))
	var def := CharacterData.find(f.characters_cfg, id)
	if not def.is_empty():
		avatar_disc.add_theme_stylebox_override("panel", _style(role_color(str(def["role"])).darkened(0.2), 40, 0))
	if f.portraits == null or def.is_empty():
		return
	f.portraits.request(id, def, func(tex: Texture2D):
		if is_instance_valid(avatar_tex):
			avatar_tex.texture = tex
			icon.visible = false)


## フレンドの申しこみ・しょうたいの数
func _refresh_badge() -> void:
	if friend_badge == null:
		return
	var n := (f.account_state.get("inbox", []) as Array).size() if f.account_state.get("inbox") is Array else 0
	friend_badge.visible = n > 0
	friend_badge_label.text = str(mini(n, 9)) + ("+" if n > 9 else "")


## 毎コマ（game_flow の _process から）：おしらせの帯・数の丸
func tick(delta: float) -> void:
	if toast_pill != null:
		toast_pill.visible = str(f.toast_label.text) != ""
	badge_timer += delta
	if badge_timer >= 0.5:
		badge_timer = 0.0
		_refresh_badge()


# ---------------------------------------------------------------- いちばん下の3つ

func build_nav_bar() -> void:
	nav = PanelContainer.new()
	nav.name = "NavBar"
	var nsb := UiKit.glass(f.config, 0, 1.25)
	nsb.set_corner_radius_all(0)
	nsb.corner_radius_top_left = UiKit.corner(f.config, 28)
	nsb.corner_radius_top_right = UiKit.corner(f.config, 28)
	nsb.set_border_width_all(0)
	nsb.border_width_top = 2
	nsb.set_content_margin_all(8)
	nsb.content_margin_bottom = 10
	nav.add_theme_stylebox_override("panel", nsb)
	var h := float(f.config["nav_height"])
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -h
	nav.offset_bottom = 0
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	for item in [["formation", "person", "nav_formation"], ["lobby", "home", "nav_lobby"], ["gacha", "gacha", "nav_gacha"]]:
		var key: String = item[0]
		var b := Button.new()
		b.name = key.capitalize()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(180, h - 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.clear_button(b)
		# 選んでいる時：うしろのやわらかい光と、上の短い線
		var glow := FancyRect.new().setup(Color(1, 0.55, 0.2, 0.22), Color(1, 0.45, 0.15, 0.04), 22)
		glow.name = "Glow"
		glow.shine = 0.0
		glow.border_width = 0.0
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(glow)
		var mark := FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 3, Color(1, 0.5, 0.2, 0.7), 4)
		mark.name = "Mark"
		mark.shine = 0.0
		mark.border_width = 0.0
		mark.set_anchors_preset(Control.PRESET_CENTER_TOP)
		mark.custom_minimum_size = Vector2(44, 6)
		mark.size = Vector2(44, 6)
		mark.position = Vector2(-22, 0)
		b.add_child(mark)
		var col := VBoxContainer.new()
		col.name = "Col"
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := LobbyIcon.new(item[1], Color.WHITE)
		ic.name = "Icon"
		ic.custom_minimum_size = Vector2(46, 46)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		var lab := _label(str(f.config[item[2]]), 22, Color.WHITE, true)
		lab.name = "Text"
		col.add_child(lab)
		b.add_child(col)
		b.pressed.connect(f._on_menu_press)
		b.pressed.connect(func(): nav_press(key))
		UiKit.juice(b, 0.9)
		nav_buttons[key] = b
		nav_marks[key] = [glow, mark, ic, lab]
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
			if f.state == Logic.LOBBY:
				f.event("gacha")
			elif f.state != Logic.GACHA:
				f.goto(Logic.GACHA)


## いま開いている画面のボタンを目立たせる（オレンジの字・上の線・うしろの光）。ロビー・編成の画面だけで出す
func set_nav_selected(state: String) -> void:
	if nav == null:
		return
	# ガチャは、引いている・斬っている・結果の間は出さない（とちゅうで出られないように）
	var gacha_idle: bool = f.gacha_ui == null or f.gacha_ui.logic.state == "idle"
	nav.visible = state in [Logic.LOBBY, Logic.FORMATION] or (state == Logic.GACHA and gacha_idle)
	var on := "lobby" if state == Logic.LOBBY else ("formation" if state == Logic.FORMATION else ("gacha" if state == Logic.GACHA else ""))
	var dim := Color(str(_k("nav_dim", "#8f9cb8")))
	var hot := Color(str(_k("nav_hot", "#ffb05a")))
	for key in nav_marks:
		var parts: Array = nav_marks[key]
		var sel: bool = key == on
		(parts[0] as Control).visible = sel
		(parts[1] as Control).visible = sel
		(parts[2] as Control).color = hot if sel else dim
		(parts[2] as Control).queue_redraw()
		(parts[3] as Label).add_theme_color_override("font_color", hot if sel else dim)


# ---------------------------------------------------------------- へや

func build_room_panel() -> void:
	var p: VBoxContainer = f._make_lobby_panel(Logic.ROOM, 18)
	p.add_child(UiKit.outline(_label(str(f.config["room_title"]), int(f.config["heading_font_size"]), Color.WHITE, true), 6))
	# へやのコード（大きく）と人数
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(580, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", UiKit.glass(f.config, 24))
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 8)
	ccol.add_child(_label(str(f.config["room_code_label"]), 22, Color(str(_k("sub_text", "#b9c4dc")))))
	f.room_label = _label("", int(f.config["text_font_size"]), Color.WHITE, true)
	ccol.add_child(f.room_label)
	var seats := HBoxContainer.new()
	seats.name = "Seats"
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	seats.add_theme_constant_override("separation", 14)
	for i in int(f.config["max_party"]):
		var s := LobbyIcon.new("person", Color(1, 1, 1, 0.25))
		s.custom_minimum_size = Vector2(46, 46)
		seats.add_child(s)
	ccol.add_child(seats)
	card.add_child(ccol)
	p.add_child(card)
	f.party_box = VBoxContainer.new()
	f.party_box.add_theme_constant_override("separation", 8)
	p.add_child(f.party_box)
	# あなたの編成（4人の顔）
	var team_card := PanelContainer.new()
	team_card.custom_minimum_size = Vector2(580, 0)
	team_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	team_card.add_theme_stylebox_override("panel", UiKit.glass(f.config, 24))
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 8)
	var team_label := _label("", 22, Color(str(_k("sub_text", "#b9c4dc"))))
	team_label.name = "TeamLabel"
	team_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	team_label.custom_minimum_size = Vector2(540, 0)
	tcol.add_child(team_label)
	var faces := HBoxContainer.new()
	faces.name = "Faces"
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	faces.add_theme_constant_override("separation", 14)
	tcol.add_child(faces)
	team_card.add_child(tcol)
	p.add_child(team_card)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	f.invite_button = f._make_button(str(f.config["invite_label"]), [282, 90], f.invite)
	f.leave_button = f._make_button(str(f.config["new_room_label"]), [282, 90], f.new_room)
	UiKit.glass_button(f.invite_button, f.config, 24, Color("#2d4a7ae0"))
	UiKit.glass_button(f.leave_button, f.config, 24)
	UiKit.juice(f.invite_button)
	UiKit.juice(f.leave_button)
	row.add_child(f.invite_button)
	row.add_child(f.leave_button)
	p.add_child(row)
	var sh := Control.new()
	sh.custom_minimum_size = Vector2(f.config["button_min_size"][0], f.config["button_min_size"][1])
	sh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sskin := FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 24, Color(str(_k("play_glow", "#ff7a2a"))), 8)
	sskin.set_anchors_preset(Control.PRESET_FULL_RECT)
	sh.add_child(sskin)
	var start: Button = f._make_button(str(f.config["room_start_label"]), f.config["button_min_size"], func():
		f.goto(Logic.LOBBY)
		f.play())
	start.name = "Start"
	start.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.clear_button(start)
	if bold != null:
		start.add_theme_font_override("font", bold)
	sh.add_child(start)
	p.add_child(sh)
	var note := _label(str(f.config["room_name_note"]), 20, Color(str(_k("sub_text", "#b9c4dc"))))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	p.add_child(note)
	var back: Button = f._make_button(str(f.config["back_label"]), f.config["small_button_min_size"], func(): f.event("back"))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.glass_button(back, f.config, 24)
	UiKit.juice(back)
	p.add_child(back)


## へやの画面：人数の席（いる人は明るく）・編成の4人（顔の絵と名前）
func refresh_room() -> void:
	var panel: Control = f.panels[Logic.ROOM]
	var lab := panel.find_child("TeamLabel", true, false) as Label
	if lab == null:
		return
	var names: Array = []
	for id in team():
		var d := CharacterData.find(f.characters_cfg, str(id))
		names.append(str(d.get("name", id)))
	lab.text = str(f.config["room_team_label"]) + "：" + " ／ ".join(names)
	var seats := panel.find_child("Seats", true, false)
	var n := 1
	if str(f.room_state.get("status", "")) == "in_room":
		n = maxi(1, (f.room_state.get("members", []) as Array).size())
	if seats != null:
		for i in seats.get_child_count():
			var s := seats.get_child(i) as Control
			s.set("color", Color(str(_k("gold", "#ffd45a"))) if i < n else Color(1, 1, 1, 0.22))
			s.queue_redraw()
	var faces := panel.find_child("Faces", true, false) as HBoxContainer
	if faces == null:
		return
	f._clear_box(faces)
	for id in team():
		var d := CharacterData.find(f.characters_cfg, str(id))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var disc := Panel.new()
		disc.custom_minimum_size = Vector2(104, 104)
		disc.add_theme_stylebox_override("panel", _style(role_color(str(d.get("role", ""))).darkened(0.25), 52, 0))
		disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		var ph := LobbyIcon.new("person", Color(1, 1, 1, 0.8))
		ph.set_anchors_preset(Control.PRESET_FULL_RECT)
		disc.add_child(ph)
		var tr := TextureRect.new()
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		disc.add_child(tr)
		col.add_child(disc)
		col.add_child(_label(str(d.get("name", id)), 20, Color.WHITE, true))
		faces.add_child(col)
		if f.portraits != null and not d.is_empty():
			f.portraits.request(str(id), d, func(tex: Texture2D):
				if is_instance_valid(tr):
					tr.texture = tex
					ph.visible = false)
