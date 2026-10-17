extends Control
## 4桁の合言葉で部屋に入る画面（手順1-4）と、箱の位置の同期（手順2）。
## 左：数字ボタンで合言葉を入れ、「入る」「出る」。右：自分の箱を動かして送り、部屋の他の人の箱を表示する。
## 入退室・送信・受信はブラウザ側（window.bbFirebase）に頼む（room_bridge.gd）。
## 文字や並びは data/room_screen.json、同期の数値は data/position_sync.json、桁数は data/network.json。

const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Sync := preload("res://scripts/network/position_sync.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const UI_PATH := "res://data/room_screen.json"
const SYNC_PATH := "res://data/position_sync.json"
const CONFIG_PATH := "res://data/firebase_config.json"
const SLOTS := ["p1", "p2", "p3", "p4"]

var ui: Dictionary = {}
var sync_cfg: Dictionary = {}
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
var rate_label: Label
var stage: Control
var boxes := {}
var box_targets := {}
var box_pos := {}
var key_buttons: Array[Button] = []
var since_poll: float = 0.0
var last_state: Dictionary = {}
var angle: float = 0.0
var last_sent_ms: int = -100000
var rate_elapsed: float = 0.0
var rate_sent_prev: int = 0
var rate_recv_prev: int = 0


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
	sync_cfg = CheckScreen.load_json(SYNC_PATH)
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
	column.anchor_right = 0.55
	column.offset_left = 24.0
	column.offset_top = 24.0
	column.offset_right = -12.0
	column.offset_bottom = -24.0
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	code_label = _make_label(font, int(ui["font_size"]) + 16)
	column.add_child(code_label)
	status_label = _make_label(font, int(ui["small_font_size"]))
	column.add_child(status_label)
	members_label = _make_label(font, int(ui["small_font_size"]))
	column.add_child(members_label)
	rate_label = _make_label(font, int(ui["small_font_size"]))
	column.add_child(rate_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
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
	_build_stage()


func _build_stage() -> void:
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.anchor_left = 0.55
	stage.offset_left = 12.0
	stage.offset_top = 24.0
	stage.offset_right = -24.0
	stage.offset_bottom = -24.0
	add_child(stage)
	var panel := ColorRect.new()
	panel.color = Color(str(sync_cfg["stage_color"]))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(panel)
	var colors: Array = sync_cfg["colors"]
	var size := float(sync_cfg["box_size"])
	for i in range(SLOTS.size()):
		var box := ColorRect.new()
		box.color = Color(str(colors[i]))
		box.size = Vector2(size, size)
		box.visible = false
		stage.add_child(box)
		boxes[SLOTS[i]] = box


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
	button.custom_minimum_size = Vector2(160, 80)
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
	if not is_web or not is_instance_valid(stage):
		return
	since_poll += delta
	if since_poll >= float(ui["poll_interval_sec"]):
		since_poll = 0.0
		poll()
	rate_elapsed += delta
	if rate_elapsed >= float(sync_cfg["rate_window_sec"]):
		_update_rate()
	_update_stage(delta)


## ブラウザ側の状態を読んで、画面を更新する
func poll() -> void:
	var state := bridge.read_state()
	if state.is_empty():
		return
	last_state = state
	_show_status(build_status_text(state, ui["texts"]))
	members_label.text = build_members_text(state, ui["texts"])


## 送った回数と受けた回数から、回/秒を出す
func _update_rate() -> void:
	var sent := int(last_state.get("sent", 0))
	var recv := int(last_state.get("received", 0))
	var sent_per_sec := Sync.rate_per_sec(sent, rate_sent_prev, rate_elapsed)
	var recv_per_sec := Sync.rate_per_sec(recv, rate_recv_prev, rate_elapsed)
	rate_sent_prev = sent
	rate_recv_prev = recv
	rate_elapsed = 0.0
	rate_label.text = str(sync_cfg["rate_text"]) % [sent_per_sec, recv_per_sec]


## 自分の箱を動かして、一定の間隔で送る。他の人の箱は、受け取った位置へなめらかに近づける
func _update_stage(delta: float) -> void:
	var me := str(last_state.get("slot", ""))
	if me != "":
		angle += delta * float(sync_cfg["angular_speed"])
		var target := Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * float(sync_cfg["radius"])
		box_targets[me] = target
		var now := Time.get_ticks_msec()
		if Sync.should_send(now, last_sent_ms, int(sync_cfg["send_interval_ms"])):
			last_sent_ms = now
			bridge.send_position(target.x, target.y)
	var positions := Sync.parse_positions(last_state.get("positions", {}))
	for slot in SLOTS:
		var box: ColorRect = boxes[slot]
		var target := Vector2.ZERO
		var show := false
		if slot == me:
			target = box_targets.get(me, Vector2(0.5, 0.5))
			show = true
		elif positions.has(slot):
			target = positions[slot]
			show = true
		if not show:
			box.visible = false
			box_pos.erase(slot)
			continue
		var current: Vector2 = box_pos.get(slot, target)
		if slot == me:
			current = target
		else:
			current = current.lerp(target, Sync.smooth_weight(delta, float(sync_cfg["smooth_per_sec"])))
		box_pos[slot] = current
		box.visible = true
		box.position = current * stage.size - box.size / 2.0
