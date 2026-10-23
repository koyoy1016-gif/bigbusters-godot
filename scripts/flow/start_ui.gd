extends RefCounted
## 版82・109：はじめの画面＝アカウントを選ぶ画面（ゲームを開くと、最初にこの画面。版109で TOKYO の読み込み画面をやめた）。
## うしろに3Dのロビー（キャラ4人）を出し、ゲームの名前 BIGBLAST と、ボタン：
##   0. つづける（ログインずみの人。いまのアカウントで遊ぶ）
##   1. あたらしく アカウントを つくる（ID・パスワード2回・なまえ。ブラウザ側の本物の入力欄 web/head/30_account.js）
##   2. ログイン（ログインずみの人には「べつの アカウントで ログイン」）
##   3. ログインせずに あそぶ（ゲスト。きろくは この端末だけ、と説明してから）
## ログインの準備ができるまでは「じゅんびちゅう」を小さく出し、ボタンは押せない（flow_logic.start_ready）。準備ができたら、ボタンを出す。
## ログインの仕組みがない所（テスト・アプリ2）は、すぐ「あそぶ」だけ押せる。
## 入力欄を開いてログインずみになり、入力欄を閉じたら、ロビーへ進む（game_flow.gd の _process から poll）。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")

var f: Node
var root: Control
var create_button: Button
var login_button: Button
var guest_button: Button
var continue_button: Button  ## 版109：ログインずみの人の「つづける」
var continue_holder: Control
var guest_confirm: Control
var note_label: Label
var loading_label: Label  ## 版109：準備中の小さな字（点が動く）
var buttons_col: Control
var bold: Font
var ready := false  ## 版109：ボタンを押せるか（ログインの準備ができた）
var waited := 0.0
var form_opened := false  ## 版109：この画面で入力欄を開いたか（ログインずみの人を、勝手にロビーへ進めない）


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
		b.add_theme_color_override("font_color", Color.WHITE)  # 版113：オレンジの上で、くっきり白く
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.02, 0.85))
		b.add_theme_constant_override("outline_size", 8)
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


## 版117：名前（上）とボタン（下）を置く。たて：名前は上から10%・ボタンは下から60。横：名前は小さく上に・ボタンは下に。重なる時は名前を小さく
func layout() -> void:
	if root == null or buttons_col == null:
		return
	var sz := root.size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return
	var land := sz.x > sz.y
	var logo := root.get_node_or_null("Logo") as Control
	var cs := buttons_col.get_combined_minimum_size()
	buttons_col.size = cs
	buttons_col.position = Vector2((sz.x - cs.x) * 0.5, sz.y - cs.y - (32.0 if land else 60.0))
	if logo == null:
		return
	var ls := logo.get_combined_minimum_size()
	logo.size = ls
	var top_y := sz.y * (0.04 if land else 0.1)
	var room := buttons_col.position.y - 16.0 - top_y
	var k := clampf(room / maxf(ls.y, 1.0), 0.45, 0.72 if land else 1.0)
	logo.pivot_offset = Vector2(ls.x * 0.5, 0.0)
	logo.scale = Vector2(k, k)
	logo.position = Vector2((sz.x - ls.x) * 0.5, top_y)


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
	loading_label = _label(_v("start_loading", "じゅんびちゅう"), 22, Color(str(_k("sub_text", "#b9c4dc"))))
	loading_label.name = "Loading"
	top.add_child(loading_label)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	top.position.y += 120
	# 3つのボタン
	var col := VBoxContainer.new()
	col.name = "Buttons"
	col.add_theme_constant_override("separation", 16)
	buttons_col = col
	var c0 := big_button(_v("start_continue", "つづける"), true, enter_continue, "Continue")
	continue_holder = c0[0]
	continue_button = c0[1]
	col.add_child(c0[0])
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
	# 版117：画面の大きさ・向きが変わった時と、ボタンの数が変わった時に、置き直す（横画面で、名前とボタンが重なっていた）
	root.resized.connect(layout)
	col.minimum_size_changed.connect(layout)
	top.minimum_size_changed.connect(layout)
	layout.call_deferred()
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


func _v(key: String, def: String) -> String:
	return str((f.config.get("v109", {}) as Dictionary).get(key, def))


## 画面に入った時：準備中から始める（ログインの準備ができたら、ボタンを出す）
func refresh() -> void:
	ready = false
	waited = 0.0
	form_opened = false
	guest_confirm.visible = false
	_apply_ready()


## 準備ができたか（ログインの仕組みがない所は、すぐ）
func _check_ready() -> bool:
	var st: Dictionary = f.account_state
	return Logic.start_ready(f.account != null, str(st.get("status", "")), waited, float(f.config.get("start_wait_sec", 4.0)))


## ボタンの出し方を、いまの状態に合わせる
func _apply_ready() -> void:
	var online: bool = f.account != null
	var signed := online and bool((f.account_state as Dictionary).get("signedIn", false))
	loading_label.visible = not ready
	buttons_col.visible = ready
	for b in [continue_button, create_button, login_button, guest_button]:
		(b as Button).disabled = not ready
	# ログインずみ：「つづける（なまえ）」を大きく。ログインは「べつの アカウントで」
	continue_holder.visible = signed or not online
	var nick := str((f.account_state as Dictionary).get("nickname", ""))
	if not online:
		continue_button.text = _v("start_offline_play", "あそぶ")
	else:
		continue_button.text = _v("start_continue", "つづける") + ("（" + nick + "）" if nick != "" else "")
	(create_button.get_parent() as Control).visible = online and not signed
	login_button.text = _v("start_other_login", "別のアカウントでログイン") if signed else str(f.config["start_login"])
	(login_button.get_parent() as Control).visible = online
	(guest_button.get_parent() as Control).visible = online and not signed
	note_label.text = str(f.config["start_note"]) if online else str(f.config["account_unavailable"])


func open_create() -> void:
	if f.account != null and ready:
		form_opened = true
		f.account.show_form("register", f.config["account_forms"])


func open_login() -> void:
	if f.account != null and ready:
		form_opened = true
		f.account.show_form("login", f.config["account_forms"])


## 版109：「つづける」（ログインずみ）・「あそぶ」（ログインの仕組みがない所）：そのままロビーへ
func enter_continue() -> void:
	if ready:
		f.event("enter")


func ask_guest() -> void:
	if not ready:
		return
	guest_confirm.visible = true
	if guest_confirm.is_inside_tree():
		guest_confirm.modulate.a = 0.0
		guest_confirm.create_tween().tween_property(guest_confirm, "modulate:a", 1.0, 0.15)


func enter_as_guest() -> void:
	guest_confirm.visible = false
	f.event("enter")


## 毎コマ（game_flow の _process から）：準備ができたらボタンを出す。
## この画面で入力欄を開いて、ログインずみになり、入力欄が閉じたら、ロビーへ
func poll(delta: float = 0.0) -> void:
	waited += delta
	if not ready:
		if _check_ready():
			ready = true
			_apply_ready()
			if buttons_col.is_inside_tree():
				buttons_col.modulate.a = 0.0
				buttons_col.create_tween().tween_property(buttons_col, "modulate:a", 1.0, float((f.config.get("v109", {}) as Dictionary).get("start_ready_fade_sec", 0.25)))
		else:
			# 控えめな読み込みの合図（点が1つずつふえる。0.4秒ごと）
			var n := int(waited / 0.4) % 4
			loading_label.text = _v("start_loading", "じゅんびちゅう") + ".".repeat(n)
		return
	var st: Dictionary = f.account_state
	if form_opened and bool(st.get("signedIn", false)) and not bool(st.get("formOpen", false)):
		form_opened = false
		f.event("enter")
		return
	# ログインの状態が変わった（ログアウト・別の端末など）：ボタンの出し方を合わせる
	var signed := f.account != null and bool(st.get("signedIn", false))
	if signed != continue_holder.visible and f.account != null:
		_apply_ready()
