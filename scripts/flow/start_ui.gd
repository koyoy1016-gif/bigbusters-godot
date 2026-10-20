extends RefCounted
## 版82：はじめの画面（URLを開いた時）。うしろに3Dのロビー（キャラ4人）を出し、ゲームの名前と3つのボタン：
##   1. あたらしく アカウントを つくる（ID・パスワード2回・なまえ。ブラウザ側の本物の入力欄 web/head/30_account.js）
##   2. ログイン（ID・パスワード）
##   3. ログインせずに あそぶ（ゲスト。きろくは この端末だけ、と説明してから）
## ログインずみの人は、この画面を出さずにロビーへ（毎回えらばなくてよい）。
## 入力欄を閉じて、ログインずみになったら、ロビーへ進む（game_flow.gd の _process）。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")

var f: Node
var root: Control
var create_button: Button
var login_button: Button
var guest_button: Button
var guest_confirm: Control
var note_label: Label
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


## 大きなボタン（primary：オレンジのグラデーション、そうでなければガラス）
func big_button(text: String, primary: bool, cb: Callable, name_text: String) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(520, 96)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var b: Button = f._make_button(text, [520, 96], cb)
	b.name = name_text
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	if bold != null:
		b.add_theme_font_override("font", bold)
	b.add_theme_font_size_override("font_size", 32 if primary else 30)
	if primary:
		var skin := FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 26, Color(str(_k("play_glow", "#ff7a2a"))), 10)
		skin.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(skin)
		UiKit.clear_button(b)
		b.add_theme_color_override("font_outline_color", Color(0.5, 0.15, 0.03, 0.7))
		b.add_theme_constant_override("outline_size", 6)
	else:
		UiKit.glass_button(b, f.config, 26)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	holder.add_child(b)
	UiKit.juice(b)
	b.button_down.connect(func():
		holder.pivot_offset = holder.size * 0.5
		holder.scale = Vector2(0.96, 0.96))
	b.button_up.connect(func(): holder.scale = Vector2.ONE)
	return [holder, b]


func build() -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	root = Control.new()
	root.name = Logic.START
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	f.layer.add_child(root)
	f.panels[Logic.START] = root
	root.add_child(UiKit.vignette(true, 520, Color("#070a14e6")))
	root.add_child(UiKit.vignette(false, 640, Color("#070a14f2")))
	# ゲームの名前（光る大きな字）
	var top := VBoxContainer.new()
	top.name = "Logo"
	top.add_theme_constant_override("separation", 0)
	var title := _label(str(f.config["start_title"]), int(f.config["start_title_size"]), Color(str(_k("gold", "#ffd45a"))), true)
	title.add_theme_color_override("font_outline_color", Color("#5a1a06"))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(1.0, 0.45, 0.1, 0.55))
	title.add_theme_constant_override("shadow_outline_size", 26)
	title.add_theme_constant_override("shadow_offset_y", 0)
	top.add_child(title)
	var sub := UiKit.outline(_label(str(f.config["start_subtitle"]), 26, Color.WHITE, true), 6)
	top.add_child(sub)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	top.position.y += 120
	# 3つのボタン
	var col := VBoxContainer.new()
	col.name = "Buttons"
	col.add_theme_constant_override("separation", 16)
	var c1 := big_button(str(f.config["start_create"]), true, open_create, "Create")
	create_button = c1[1]
	col.add_child(c1[0])
	var c2 := big_button(str(f.config["start_login"]), false, open_login, "Login")
	login_button = c2[1]
	col.add_child(c2[0])
	var c3 := big_button(str(f.config["start_guest"]), false, ask_guest, "Guest")
	guest_button = c3[1]
	col.add_child(c3[0])
	note_label = _label("", 19, Color(str(_k("sub_text", "#b9c4dc"))))
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.custom_minimum_size = Vector2(540, 0)
	col.add_child(note_label)
	root.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.position.y -= 60
	_build_guest_confirm()


## 「ログインせずに あそぶ」の確かめ：きろくは この端末だけ・消えることがある
func _build_guest_confirm() -> void:
	guest_confirm = Control.new()
	guest_confirm.name = "GuestConfirm"
	guest_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	guest_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.07, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	guest_confirm.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(580, 0)
	var sb := UiKit.glass(f.config, 26, 1.4)
	sb.set_content_margin_all(26)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.add_child(_label(str(f.config["start_guest_title"]), 34, Color.WHITE, true))
	var t := _label(str(f.config["start_guest_note"]), 22, Color("#dfe6f5"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(520, 0)
	col.add_child(t)
	var ok := big_button(str(f.config["start_guest_ok"]), true, enter_as_guest, "GuestOk")
	col.add_child(ok[0])
	var back := big_button(str(f.config["back_label"]), false, func(): guest_confirm.visible = false, "GuestBack")
	col.add_child(back[0])
	card.add_child(col)
	center.add_child(card)
	guest_confirm.add_child(center)
	guest_confirm.visible = false
	root.add_child(guest_confirm)


func refresh() -> void:
	var online: bool = f.account != null
	create_button.disabled = not online
	login_button.disabled = not online
	note_label.text = str(f.config["start_note"]) if online else str(f.config["account_unavailable"])
	guest_confirm.visible = false


func open_create() -> void:
	if f.account != null:
		f.account.show_form("register", f.config["account_forms"])


func open_login() -> void:
	if f.account != null:
		f.account.show_form("login", f.config["account_forms"])


func ask_guest() -> void:
	guest_confirm.visible = true
	if guest_confirm.is_inside_tree():
		guest_confirm.modulate.a = 0.0
		guest_confirm.create_tween().tween_property(guest_confirm, "modulate:a", 1.0, 0.15)


func enter_as_guest() -> void:
	guest_confirm.visible = false
	f.event("enter")


## ログインずみになって、入力欄が閉じたら、ロビーへ（game_flow の _process から呼ぶ）
func poll() -> void:
	var st: Dictionary = f.account_state
	if bool(st.get("signedIn", false)) and not bool(st.get("formOpen", false)):
		f.event("enter")
