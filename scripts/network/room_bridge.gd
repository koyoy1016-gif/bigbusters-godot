extends RefCounted
## 部屋の入退室を、ブラウザ側の window.bbFirebase（JS）に頼む、薄い橋渡し。
## 合言葉の形だけをここで検査し、空いている枠の選び方や書き込みは、JS側で行う。Web版でだけ実際に動く。

const RoomCode := preload("res://scripts/network/room_code.gd")

## JavaScriptBridge.eval の代わり。テストでは差し替える
var js_eval: Callable = func(code: String) -> Variant: return JavaScriptBridge.eval(code, true)


static func build_join_call(config_json: String, code: String) -> String:
	return "window.bbFirebase.joinRoom(%s, %s)" % [JSON.stringify(config_json), JSON.stringify(code)]


static func build_leave_call() -> String:
	return "window.bbFirebase.leaveRoom()"


static func build_send_position_call(x: float, y: float) -> String:
	return "window.bbFirebase.sendPosition(%s, %s)" % [str(x), str(y)]


static func build_state_query() -> String:
	return "JSON.stringify(window.bbFirebase.state)"


## JSの状態（JSON文字列）を辞書にする。壊れていれば空の辞書
static func parse_state(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


## 合言葉の形が正しいときだけ、JSに入室を頼む。正しくなければ何もせず false
func join(config_json: String, code: String, digits: int) -> bool:
	if not RoomCode.is_valid_code(code, digits):
		return false
	js_eval.call(build_join_call(config_json, code))
	return true


func leave() -> void:
	js_eval.call(build_leave_call())


## 自分の箱の位置（0〜1）を送る。部屋に入っていなければ、JS側が何もしない
func send_position(x: float, y: float) -> void:
	js_eval.call(build_send_position_call(x, y))


func read_state() -> Dictionary:
	return parse_state(str(js_eval.call(build_state_query())))
