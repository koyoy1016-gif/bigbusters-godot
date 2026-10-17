extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_room_bridge.gd
## 橋渡し（GDScript側）と、ブラウザ側の入り口（head_include）の形を確かめる。
## JSの中の動き（空いている枠、取り合い、退出）は tests/js/room_bridge.test.mjs で確かめる。

const Bridge := preload("res://scripts/network/room_bridge.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const PRESETS := "res://export_presets.cfg"
const CONFIG_JSON := '{"projectId":"bigbusters-new"}'

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var digits := int(RoomCode.load_config()["code_digits"])

	# 合言葉の形が正しくないときは、JSを呼ばない
	var log_bad: Array = []
	var bad := Bridge.new()
	bad.js_eval = func(code: String) -> Variant:
		log_bad.append(code)
		return null
	check(bad.join(CONFIG_JSON, "12a4", digits) == false and log_bad.is_empty(), "不正な合言葉（英字）は、JSを呼ばずに止める")
	check(bad.join(CONFIG_JSON, "123", digits) == false and log_bad.is_empty(), "3桁は、JSを呼ばずに止める")

	# 正しい合言葉は、入室を頼む
	var log: Array = []
	var bridge := Bridge.new()
	bridge.js_eval = func(code: String) -> Variant:
		log.append(code)
		if code.begins_with("JSON.stringify"):
			return '{"status":"in_room","slot":"p1","members":["p1"],"uid":"abc"}'
		return null
	check(bridge.join(CONFIG_JSON, "1234", digits) == true, "正しい合言葉は、入室を頼める")
	check(str(log[0]).begins_with("window.bbFirebase.joinRoom(") and str(log[0]).ends_with(', "1234")'), "入室の呼び出しに、合言葉が入る（%s）" % str(log[0]))
	check(str(log[0]).contains("bigbusters-new"), "入室の呼び出しに、設定（JSON）が渡る")
	bridge.leave()
	check(log[1] == "window.bbFirebase.leaveRoom()", "退出の呼び出し")
	var state := bridge.read_state()
	check(state.get("status") == "in_room" and state.get("slot") == "p1", "状態を読める（in_room・p1）")
	check(state.get("members") is Array and (state["members"] as Array).size() == 1, "在室の一覧を読める")
	check(Bridge.parse_state("壊れた文字").is_empty(), "壊れた状態は、空の辞書になる")

	# ブラウザ側の入り口（head_include）の形
	var cf := ConfigFile.new()
	check(cf.load(PRESETS) == OK, "export_presets.cfg が読める")
	var head: String = str(cf.get_value("preset.1.options", "html/head_include", ""))
	for word in ["joinRoom", "leaveRoom", "onDisconnect", "onValue", "PERMISSION_DENIED", "firebase-database.js", "signInAnonymously", "window.bbFirebase"]:
		check(head.contains(word), "入り口に「%s」がある" % word)
	check(head.count("gstatic.com/firebasejs/") == 1, "SDKの場所は1か所だけ（固定バージョン）")
	for word in ["apiKey", "AIza", "bigbusters-new"]:
		check(not head.contains(word), "入り口に設定値（%s）を直接書いていない" % word)

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
