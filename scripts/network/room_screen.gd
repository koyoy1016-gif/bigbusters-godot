extends Control
## 4桁の合言葉で部屋に入る画面（手順1-4）。数字ボタンで合言葉を入れ、「入る」で入室、「出る」で退室する。
## 入退室はブラウザ側（window.bbFirebase）に頼む（room_bridge.gd）。文字や並びは data/room_screen.json、桁数は data/network.json から読む。

const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const UI_PATH := "res://data/room_screen.json"
const CONFIG_PATH := "res://data/firebase_config.json"
const NETWORK_PATH := "res://data/network.json"

var ui: Dictionary = {}
var digits: int = 4
var code: String = ""
var config_json: String = ""
var bridge := Bridge.new()
## JavaScriptBridge.eval の代わり。テストでは差し替える（橋渡しの js_eval も同じものにする）
var js_eval: Callable = func(text: String) -> Variant: return JavaScriptBridge.eval(text, true)
var is_web: bool = OS.has_feature("web")
var code_label: Label
var status_label: Label
var members_label: Label
var key_buttons: Array[Button] = []
var since_poll: float = 0.0


## 合言葉に数字を1つ足す。桁数を超えない、数字以外は足さない
static func append_digit(current: String, digit: String, digit_count: int) -> String:
	if current.length() >= digit_count or not digit.is_valid_int():
		return current
	return current + digit


static func delete_digit(current: String) -> String:
	return current.left(maxi(0, current.length() - 1))


## 入力中の合言葉を、画面に出す形にする（例：「12__」）
static func display_code(current: String, digit_count: int, placeholder: String) -> String:
	var text := current
	while text.length() < digit_count:
		text += placeholder
	return text


## 部屋の状態（JS）から、画面に出す1行の文字を作る
static func build_status_text(state: Dictionary, texts: Dictionary) -> String:
	match str(state.get("status", "")):
		"in_room":
			var members: Array = state.get("members", [])
			return str(texts["in_room"]) % [str(state.get("slot", "")), members.size()]
		"joining", "pending":
			return str(texts["joining"])
		"full":
			return str(texts["full"])
		"left":
			return str(texts["left"])
		"ok":
			return str(texts["ok"])
		"error":
			return str(texts["error"]) % str(state.get("error", ""))
		_:
			return str(texts["idle"])


## 部屋にいる枠の一覧の文字
static func build_members_text(state: Dictionary, texts: Dictionary) -> String:
	var members: Array = state.get("members", [])
	if members.is_empty():
		return str(texts["members_none"])
	var names := ""
	for m in members:
		names += ("" if names.is_empty() else ", ") + str(m)
	return str(texts["members"]) % names


func _ready() -> void:
	ui = CheckScreen.load_json(UI_PATH)
	digits = int(RoomCode.load_config().get("code_digits", 4))
	config_json = JSON.stringify(CheckScreen.extract_firebase_config(CheckScreen.load_json(CONFIG_PATH)))
	_build_ui()
	if not is_web:
		_show_status(str(ui["texts"]["not_web"]))
		_set_keys_enabled(false)
		return
	if str(js_eval.call("typeof window.bbFirebase")) != "object":
		_show_status(str(ui["texts"]["no_bridge"]))
		_set_keys_enabled(false)
		return
	bridge.js_eval = js_eval
	_show_status(str(ui["texts"]["idle"]))
	_refresh_code()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(str(ui["background_color"]))
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var font := load(str(ui["ui_font_path"])) as Font
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24.0
	column.offset_top = 24.0
	column.offset_right = -24.0
	column.offset_bottom = -24.0
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	code_label = _make_label(font, int(ui["font_size"]) + 16)
	column.add_child(code_label)
	status_label = _make_label(font, int(ui["small_font_size"]))
	column.add_child(status_label)
	members_label = _make_label(font, int(ui["small_font_size"]))
	column.add_child(members_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	for key in ui["keys"]:
		var button := _make_button(font, str(key))
		button.pressed.connect(_on_key.bind(str(key)))
		grid.add_child(button)
		key_buttons.append(button)
	var leave := _make_button(font, str(ui["leave_key"]))
	leave.pressed.connect(_on_leave)
	column.add_child(leave)
	key_buttons.append(leave)


func _make_label(font: Font, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(str(ui["text_color"])))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_button(font: Font, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", int(ui["font_size"]))
	button.custom_minimum_size = Vector2(220, 84)
	return button


func _on_key(key: String) -> void:
	if key == str(ui["keys"][9]):
		code = delete_digit(code)
	elif key == str(ui["keys"][11]):
		_join()
		return
	else:
		code = append_digit(code, key, digits)
	_refresh_code()


func _join() -> void:
	if code.length() != digits:
		_show_status(str(ui["texts"]["need_digits"]))
		return
	bridge.join(config_json, code, digits)
	since_poll = 0.0


func _on_leave() -> void:
	bridge.leave()
	since_poll = 0.0


func _refresh_code() -> void:
	code_label.text = display_code(code, digits, str(ui["placeholder"]))


func _set_keys_enabled(enabled: bool) -> void:
	for b in key_buttons:
		b.disabled = not enabled


func _show_status(text: String) -> void:
	status_label.text = text


func _process(delta: float) -> void:
	if not is_web or not is_instance_valid(status_label):
		return
	since_poll += delta
	if since_poll >= float(ui["poll_interval_sec"]):
		since_poll = 0.0
		poll()


## ブラウザ側の状態を読んで、画面を更新する
func poll() -> void:
	var state := bridge.read_state()
	if state.is_empty():
		return
	_show_status(build_status_text(state, ui["texts"]))
	members_label.text = build_members_text(state, ui["texts"])
