extends RefCounted
## 部屋の入退室を、ブラウザ側の window.bbFirebase（JS）に頼む、薄い橋渡し。
## 合言葉の形だけをここで検査し、空いている枠の選び方や書き込みは、JS側で行う。Web版でだけ実際に動く。

const RoomCode := preload("res://scripts/network/room_code.gd")

## JavaScriptBridge.eval の代わり。テストでは差し替える
var js_eval: Callable = func(code: String) -> Variant: return JavaScriptBridge.eval(code, true)


## 時間の設定（data/network.json）を、JSに渡す形にする。枠の保持時間と、書き直す間隔（ミリ秒）
static func build_timing_json(net: Dictionary) -> String:
	return JSON.stringify({
		"hold_ms": int(net.get("hold_seconds", 60)) * 1000,
		"heartbeat_ms": int(net.get("heartbeat_seconds", 5)) * 1000,
	})


static func build_join_call(config_json: String, code: String, timing_json: String = "{}") -> String:
	return "window.bbFirebase.joinRoom(%s, %s, %s)" % [JSON.stringify(config_json), JSON.stringify(code), JSON.stringify(timing_json)]


static func build_leave_call() -> String:
	return "window.bbFirebase.leaveRoom()"


static func build_send_position_call(x: float, y: float) -> String:
	return "window.bbFirebase.sendPosition(%s, %s)" % [str(x), str(y)]


## 自分が与えた合計ダメージを送る（ボスの体力は、全員の合計から計算する）
static func build_send_hits_call(total: float) -> String:
	return "window.bbFirebase.sendHits(%s)" % str(total)


## 自分の体力を送る（なかまの体力の表示と、全滅の判定に使う）
static func build_send_hp_call(hp: float, round_ms: float) -> String:
	return "window.bbFirebase.sendHp(%s, %s)" % [str(hp), str(round_ms)]


## 自分が選んだキャラの id を送る（なかまの表示と、ハイライトのキャラに使う）
static func build_send_char_call(id: String) -> String:
	return "window.bbFirebase.sendChar(%s)" % JSON.stringify(id)


## 「さいせん」か「ロビー」の投票を送る。round は、どの戦いのあとの投票か
static func build_send_vote_call(vote: String, round_ms: float) -> String:
	return "window.bbFirebase.sendVote(%s, %s)" % [JSON.stringify(vote), str(round_ms)]


## 味方に効く技の記録を送る（種類、サーバー時刻、数値、どの戦いか）
static func build_send_effect_call(type: String, t_ms: float, value: float, round_ms: float) -> String:
	return "window.bbFirebase.sendEffect(%s, %s, %s, %s)" % [JSON.stringify(type), str(t_ms), str(value), str(round_ms)]


## いまの状態（lobby / ready / battle / result）を送る
static func build_send_phase_call(phase: String) -> String:
	return "window.bbFirebase.sendPhase(%s)" % JSON.stringify(phase)


## 戦いを始める（開始の時刻を、部屋に書く）
static func build_start_round_call() -> String:
	return "window.bbFirebase.startRound()"


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
	js_eval.call(build_join_call(config_json, code, build_timing_json(RoomCode.load_config())))
	return true


func leave() -> void:
	js_eval.call(build_leave_call())


## 自分の箱の位置（0〜1）を送る。部屋に入っていなければ、JS側が何もしない
func send_position(x: float, y: float) -> void:
	js_eval.call(build_send_position_call(x, y))


## 自分が与えた合計ダメージを送る。部屋に入っていなければ、JS側が何もしない
func send_hits(total: float) -> void:
	js_eval.call(build_send_hits_call(total))


func send_hp(hp: float, round_ms: float) -> void:
	js_eval.call(build_send_hp_call(hp, round_ms))


func send_char(id: String) -> void:
	js_eval.call(build_send_char_call(id))


func send_vote(vote: String, round_ms: float) -> void:
	js_eval.call(build_send_vote_call(vote, round_ms))


func send_effect(type: String, t_ms: float, value: float, round_ms: float) -> void:
	js_eval.call(build_send_effect_call(type, t_ms, value, round_ms))


func send_phase(phase: String) -> void:
	js_eval.call(build_send_phase_call(phase))


func start_round() -> void:
	js_eval.call(build_start_round_call())


func read_state() -> Dictionary:
	return parse_state(str(js_eval.call(build_state_query())))
