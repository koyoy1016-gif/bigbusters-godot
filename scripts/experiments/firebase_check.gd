extends Control
## Firebase 匿名ログインの確認（JavaScriptBridge で Firebase JS SDK を呼べるか）。
## Web版でだけ動く。ブラウザ側の window.bbFirebase は、書き出しの head_include で読み込む。
## 設定値は data/firebase_config.json、画面の文字や位置は data/firebase_check.json から読む。

const CONFIG_PATH := "res://data/firebase_config.json"
const UI_PATH := "res://data/firebase_check.json"
const CONFIG_KEYS := ["apiKey", "authDomain", "projectId", "databaseURL", "storageBucket", "messagingSenderId", "appId"]

var ui: Dictionary = {}
var config: Dictionary = {}
var is_web: bool = OS.has_feature("web")
## JavaScriptBridge.eval の代わり。テストでは差し替える
var js_eval: Callable = func(code: String) -> Variant: return JavaScriptBridge.eval(code, true)
var label: Label
var started: bool = false
var finished: bool = false
var elapsed: float = 0.0
var since_poll: float = 0.0
var last_text: String = ""


static func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## Firebase に渡す項目だけを取り出す（メモなどの余計な項目は渡さない）
static func extract_firebase_config(raw: Dictionary) -> Dictionary:
	var result := {}
	for key in CONFIG_KEYS:
		if raw.has(key):
			result[key] = raw[key]
	return result


## ブラウザ側の状態（idle / pending / ok / error）から、画面に出す文字を作る
static func build_status_text(state: Dictionary, ui_data: Dictionary) -> String:
	var texts: Dictionary = ui_data["texts"]
	match str(state.get("status", "")):
		"ok":
			var prefix_len: int = int(ui_data["uid_prefix_length"])
			return str(texts["ok"]) % str(state.get("uid", "")).left(prefix_len)
		"error":
			return str(texts["ng"]) % str(state.get("error", ""))
		_:
			return str(texts["pending"])


func _ready() -> void:
	ui = load_json(UI_PATH)
	config = extract_firebase_config(load_json(CONFIG_PATH))
	_build_ui()
	if not is_web:
		_show(str(ui["texts"]["not_web"]))
		finished = true
		return
	_start()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(str(ui["background_color"]))
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	label = Label.new()
	var pos: Array = ui["label_position"]
	label.position = Vector2(pos[0], pos[1])
	label.custom_minimum_size = Vector2(float(ui["label_width"]), 0)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_override("font", load(str(ui["ui_font_path"])) as Font)
	label.add_theme_font_size_override("font_size", int(ui["ui_font_size"]))
	label.add_theme_color_override("font_color", Color(str(ui["text_color"])))
	add_child(label)


func _start() -> void:
	# head_include が効いていないと window.bbFirebase がない
	if str(js_eval.call("typeof window.bbFirebase")) != "object":
		_show(str(ui["texts"]["no_bridge"]))
		finished = true
		return
	started = true
	_show(str(ui["texts"]["pending"]))
	# JSON文字列を、そのままJSの文字列リテラルとして渡す（signInAnonymously を呼ぶのは1回だけ）
	var literal := JSON.stringify(JSON.stringify(config))
	js_eval.call("window.bbFirebase.signIn(%s)" % literal)


func _process(delta: float) -> void:
	if not started or finished:
		return
	elapsed += delta
	since_poll += delta
	if since_poll >= float(ui["poll_interval_sec"]):
		since_poll = 0.0
		poll()
	if not finished and elapsed >= float(ui["timeout_sec"]):
		finished = true
		var seconds := int(ui["timeout_sec"])
		_show(str(ui["texts"]["ng"]) % (str(ui["texts"]["timeout"]) % seconds))


func poll() -> void:
	var raw: Variant = js_eval.call("JSON.stringify(window.bbFirebase.state)")
	var state: Variant = JSON.parse_string(str(raw))
	if not (state is Dictionary):
		return
	_show(build_status_text(state, ui))
	var status := str(state.get("status", ""))
	if status == "ok" or status == "error":
		finished = true


func _show(text: String) -> void:
	last_text = text
	label.text = text
