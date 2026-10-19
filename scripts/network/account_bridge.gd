extends RefCounted
## ブラウザ側のアカウント機能（window.bbAccount。web/head/30_account.js）との橋渡し。
## ログイン・復旧コード・保存・フレンド・しょうたい。入力欄（パスワードなど）は、ブラウザ側の本物の入力欄で出す。

## JavaScriptBridge.eval の代わり。テストでは差し替える
var js_eval: Callable = func(text: String) -> Variant: return JavaScriptBridge.eval(text, true)


static func build_state_query() -> String:
	return "JSON.stringify(window.bbAccount.state)"


static func build_init_call(config_json: String) -> String:
	return "window.bbAccount.init(%s)" % JSON.stringify(config_json)


## ゲームの記録（コイン・勝ち数・キャラ・画質）を渡す。ログインずみなら、サーバーにも書く
static func build_set_save_call(save: Dictionary) -> String:
	var slim := {
		"coins": int(save.get("coins", 0)),
		"wins": int(save.get("wins", 0)),
		"character": str(save.get("character", "")),
		"quality": str(save.get("quality", "")),
	}
	return "window.bbAccount.setSave(%s)" % JSON.stringify(JSON.stringify(slim))


## 入力欄の画面を出す。kind：register / login / recover / friend / nickname
static func build_show_form_call(kind: String, labels: Dictionary) -> String:
	return "window.bbAccount.showForm(%s, %s)" % [JSON.stringify(kind), JSON.stringify(labels)]


static func build_accept_call(from_sid: String) -> String:
	return "window.bbAccount.acceptFriend(%s)" % JSON.stringify(from_sid)


static func build_remove_inbox_call(from_sid: String) -> String:
	return "window.bbAccount.removeInbox(%s)" % JSON.stringify(from_sid)


static func build_invite_call(friend_sid: String, room: String) -> String:
	return "window.bbAccount.invite(%s, %s)" % [JSON.stringify(friend_sid), JSON.stringify(room)]


## この画面を、いま使う画面にする（同じ人が、ほかの画面で使っていたら、そちらは外れる）
static func build_claim_call() -> String:
	return "window.bbAccount.claimSession()"


static func build_logout_call() -> String:
	return "window.bbAccount.logout()"


## 状態（JSON文字列）を辞書にする。壊れていれば空
static func parse_state(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


## ブラウザ側の入り口があるか
func available() -> bool:
	return str(js_eval.call("typeof window.bbAccount")) == "object"


func read_state() -> Dictionary:
	return parse_state(str(js_eval.call(build_state_query())))


func init(config_json: String) -> void:
	js_eval.call(build_init_call(config_json))


func set_save(save: Dictionary) -> void:
	js_eval.call(build_set_save_call(save))


func show_form(kind: String, labels: Dictionary) -> void:
	js_eval.call(build_show_form_call(kind, labels))


func accept(from_sid: String) -> void:
	js_eval.call(build_accept_call(from_sid))


func remove_inbox(from_sid: String) -> void:
	js_eval.call(build_remove_inbox_call(from_sid))


func invite(friend_sid: String, room: String) -> void:
	js_eval.call(build_invite_call(friend_sid, room))


func claim_session() -> void:
	js_eval.call(build_claim_call())


func logout() -> void:
	js_eval.call(build_logout_call())
