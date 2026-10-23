extends RefCounted
## 版82：プロフィールの画面の上の部分（大きなアイコン・名前・ID・「アイコンを えらぶ」）。下はアカウントのボタン（game_flow の account_box）。
## アイコンは、持っているキャラの中から えらぶ（顔の絵）。えらんだキャラは save の icon_char（この端末に保存）。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")

var f: Node
var header: PanelContainer
var avatar_holder: Control
var name_label: Label
var id_label: Label
var picker: Control
var picker_grid: GridContainer
var bold: Font


func _init(flow: Node) -> void:
	f = flow


func _k(key: String, def: Variant) -> Variant:
	return (f.config.get("ui_kit", {}) as Dictionary).get(key, def)


func _label(text: String, size: int, color: Color, use_bold: bool = false) -> Label:
	var l: Label = f._make_label(text, size, color)
	if use_bold and bold != null:
		l.add_theme_font_override("font", bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func icon_id() -> String:
	var id := str(f.save.get("icon_char", ""))
	if id == "" or not f.owned.has(id):
		id = str(f.config.get("default_icon_char", "hero_swordsman"))
	return id


## プロフィールの画面の上に入れる（box：アカウントの画面の縦の入れ物）
func build(box: VBoxContainer, panel_root: Control) -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	header = PanelContainer.new()
	header.name = "ProfileHeader"
	header.custom_minimum_size = Vector2(580, 0)
	header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiKit.glass(f.config, 26)
	sb.set_content_margin_all(18)
	header.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	avatar_holder = Control.new()
	avatar_holder.custom_minimum_size = Vector2(132, 132)
	row.add_child(avatar_holder)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = _label("", 36, Color.WHITE, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.clip_text = true
	col.add_child(name_label)
	id_label = _label("", 19, Color(str(_k("sub_text", "#b9c4dc"))))
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(id_label)
	var pick: Button = f._make_button(str(f.config["profile_pick_icon"]), [260, 64], open_picker)
	pick.name = "PickIcon"
	pick.add_theme_font_size_override("font_size", 22)
	UiKit.glass_button(pick, f.config, 20, Color("#2d4a7ae0"))
	UiKit.juice(pick)
	col.add_child(pick)
	row.add_child(col)
	header.add_child(row)
	box.add_child(header)
	var head := box.get_node_or_null("Heading")
	box.move_child(header, head.get_index() + 1 if head != null else 1)  # 版115：見出し（上に小さな英字つき）のすぐ下
	_build_picker(panel_root)


func _build_picker(panel_root: Control) -> void:
	picker = Control.new()
	picker.name = "IconPicker"
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.09, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	col.add_child(UiKit.outline(_label(str(f.config["profile_pick_title"]), 38, Color.WHITE, true), 6))
	var holder := CenterContainer.new()
	picker_grid = GridContainer.new()
	picker_grid.columns = 3
	picker_grid.add_theme_constant_override("h_separation", 14)
	picker_grid.add_theme_constant_override("v_separation", 14)
	holder.add_child(picker_grid)
	col.add_child(holder)
	var close: Button = f._make_button(str(f.config["back_label"]), f.config["small_button_min_size"], func(): picker.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.glass_button(close, f.config, 24)
	UiKit.juice(close)
	col.add_child(close)
	picker.add_child(col)
	picker.visible = false
	panel_root.add_child(picker)


func refresh() -> void:
	if header == null:
		return
	f._clear_box(avatar_holder)
	var box: Control = f.formation_ui.portrait_box(icon_id(), Vector2(132, 132), 66)
	avatar_holder.add_child(box)
	var ring := Panel.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0)
	rsb.set_corner_radius_all(66)
	rsb.set_border_width_all(4)
	rsb.border_color = Color(str(_k("gold", "#ffd45a")))
	rsb.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", rsb)
	avatar_holder.add_child(ring)
	var st: Dictionary = f.account_state
	var signed := bool(st.get("signedIn", false))
	var nick := str(st.get("nickname", "")) if signed else ""
	name_label.text = nick if nick != "" else str(f.config["lobby_guest_name"])
	id_label.text = (str(f.config["account_id_label"]) + "：" + str(st.get("loginId", ""))) if signed else str(f.config["profile_guest_note"])


func open_picker() -> void:
	f._clear_box(picker_grid)
	for id in f.owned:
		var cid := str(id)
		var b := Button.new()
		b.name = "Icon_" + cid
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 200)
		UiKit.clear_button(b)
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 6)
		var c := CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(f.formation_ui.portrait_box(cid, Vector2(150, 150), 75))
		col.add_child(c)
		var d := CharacterData.find(f.characters_cfg, cid)
		var sel := cid == icon_id()
		col.add_child(_label(str(d.get("name", cid)), 22, Color(str(_k("gold", "#ffd45a"))) if sel else Color.WHITE, true))
		b.add_child(col)
		b.pressed.connect(f._on_menu_press)
		b.pressed.connect(func(): choose(cid))
		UiKit.juice(b)
		picker_grid.add_child(b)
	picker.visible = true


## アイコンにするキャラを決める（持っているキャラだけ）。保存して、ロビーの左上も変える
func choose(id: String) -> void:
	if not f.owned.has(id):
		return
	f.save["icon_char"] = id
	f._write_save()
	picker.visible = false
	refresh()
	if f.lobby_ui != null:
		f.lobby_ui.refresh()
