extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_firebase_check.gd
## 通信そのものは試せない（Web版のブラウザが必要）。ここでは、設定の読み込み・文字の組み立て・
## 状態の切り替え・書き出し設定を確かめる。

const Check := preload("res://scripts/experiments/firebase_check.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var ui: Dictionary = Check.load_json("res://data/firebase_check.json")
	var raw: Dictionary = Check.load_json("res://data/firebase_config.json")
	check(not ui.is_empty(), "表示の設定（firebase_check.json）が読める")

	# 設定値
	var cfg: Dictionary = Check.extract_firebase_config(raw)
	check(cfg.size() == 7, "Firebaseに渡す項目が7つ")
	check(not cfg.has("_memo"), "メモ欄は渡さない")
	check(cfg["projectId"] == "bigbusters-new", "projectId")
	check(str(cfg["apiKey"]).begins_with("AIza") and str(cfg["apiKey"]).length() == 39, "apiKeyの形")
	var cfg_text := JSON.stringify(cfg)
	for word in ["private_key", "client_secret", "client_email", "BEGIN PRIVATE KEY", "service_account"]:
		check(not cfg_text.contains(word), "渡す設定に「%s」が含まれない" % word)

	# 画面の文字
	var ok_text: String = Check.build_status_text({"status": "ok", "uid": "abcdef123456"}, ui)
	check(ok_text == "Firebase OK（abcdef）", "成功：uidの先頭6文字だけ出る（%s）" % ok_text)
	check(not ok_text.contains("123456"), "成功：uidの続きは出ない")
	var ng_text: String = Check.build_status_text({"status": "error", "error": "auth/operation-not-allowed oops"}, ui)
	check(ng_text == "Firebase NG：auth/operation-not-allowed oops", "失敗：エラーの文字が出る")
	check(Check.build_status_text({"status": "pending"}, ui) == "Firebase 接続中…", "接続中")
	check(Check.build_status_text({"status": "ok", "uid": "ab"}, ui) == "Firebase OK（ab）", "uidが短くても落ちない")

	# 画面の文字が、同梱フォントにすべてある（□にならない）
	var font := load(str(ui["ui_font_path"])) as Font
	var missing := ""
	for key in ui["texts"]:
		for ch in str(ui["texts"][key]).replace("%s", "").replace("%d", ""):
			if not font.has_char(ord(ch)):
				missing += ch
	check(missing == "", "表示する文字がすべてフォントにある（不足: %s）" % missing)

	# シーン：PC（Webでない）
	var packed := load("res://scenes/experiments/firebase_check.tscn") as PackedScene
	check(packed != null, "シーンが読み込める")
	var node: Control = packed.instantiate()
	root.add_child(node)
	await process_frame
	check(not node.is_web, "このテストはWeb版ではない")
	check(node.last_text == ui["texts"]["not_web"], "Webでないときは、その旨を表示する")
	node.queue_free()

	# シーン：Web版のふりをして、状態の切り替えを確かめる
	var log: Array = []
	var states: Array = [{"status": "pending"}, {"status": "ok", "uid": "Zy9xWvUt"}]
	var bridge := func(code: String) -> Variant:
		log.append(code)
		if code == "typeof window.bbFirebase":
			return "object"
		if code.begins_with("JSON.stringify(window.bbFirebase.state)"):
			var s: Dictionary = states[0] if states.size() == 1 else states.pop_front()
			return JSON.stringify(s)
		return null
	var web: Control = _make_fake_web(packed, bridge)
	root.add_child(web)
	await process_frame
	var sign_calls := log.filter(func(c): return str(c).begins_with("window.bbFirebase.signIn("))
	check(sign_calls.size() == 1, "signInは1回だけ呼ぶ")
	check(str(sign_calls[0]).contains("bigbusters-new") and not str(sign_calls[0]).contains("_memo"), "signInに設定値（メモ抜き）を渡す")
	check(web.last_text == "Firebase 接続中…", "開始直後は「接続中」")
	web._process(0.25)
	check(web.last_text == "Firebase 接続中…" and not web.finished, "まだ終わっていない")
	web._process(0.25)
	check(web.last_text == "Firebase OK（Zy9xWv）" and web.finished, "成功の表示になり、確認が終わる")
	var calls_after := log.size()
	web._process(1.0)
	check(log.size() == calls_after, "終わったあとは、もう問い合わせない")
	web.queue_free()

	var error_bridge := func(code: String) -> Variant:
		if code == "typeof window.bbFirebase":
			return "object"
		if code.begins_with("JSON.stringify("):
			return JSON.stringify({"status": "error", "error": "auth/network-request-failed x"})
		return null
	var web_ng: Control = _make_fake_web(packed, error_bridge)
	root.add_child(web_ng)
	await process_frame
	web_ng._process(0.25)
	check(web_ng.last_text == "Firebase NG：auth/network-request-failed x" and web_ng.finished, "失敗の表示になる")
	web_ng.queue_free()

	var none_bridge := func(code: String) -> Variant:
		return "undefined" if code == "typeof window.bbFirebase" else null
	var web_none: Control = _make_fake_web(packed, none_bridge)
	root.add_child(web_none)
	await process_frame
	check(web_none.last_text == ui["texts"]["no_bridge"] and web_none.finished, "head_includeが効いていないときは、その旨を表示する")
	web_none.queue_free()

	var hang_bridge := func(code: String) -> Variant:
		if code == "typeof window.bbFirebase":
			return "object"
		if code.begins_with("JSON.stringify("):
			return JSON.stringify({"status": "pending"})
		return null
	var web_hang: Control = _make_fake_web(packed, hang_bridge)
	root.add_child(web_hang)
	await process_frame
	web_hang._process(float(ui["timeout_sec"]) + 1.0)
	check(web_hang.last_text.begins_with("Firebase NG：接続が") and web_hang.finished, "終わらないときは時間切れのNGを出す")
	web_hang.queue_free()

	# 書き出しの設定
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.count("variant/thread_support=false") == 3 and not presets.contains("thread_support=true"), "Web書き出しは3つとも、スレッドなし")
	var cf := ConfigFile.new()
	check(cf.load("res://export_presets.cfg") == OK, "export_presets.cfg が読める")
	var head: String = str(cf.get_value("preset.1.options", "html/head_include", ""))
	var version: String = str(ui["sdk_version"])
	check(head.contains("https://www.gstatic.com/firebasejs/%s/" % version), "SDKは公式CDN（gstatic）の固定バージョン %s" % version)
	check(head.contains("signInAnonymously") and head.contains("window.bbFirebase"), "head_include に匿名ログインの呼び出しがある")
	check(not head.contains("latest") and head.count("gstatic.com/firebasejs/") == 1, "バージョンを固定している（latestなし）")
	check(not head.contains("AIza") and not head.contains("apiKey") and not head.contains("bigbusters-new"), "head_include に設定値を直接書いていない")
	check(str(cf.get_value("preset.0.options", "html/head_include", "x")) == "", "通常のWeb書き出し（preset.0）は変えていない")
	check(str(cf.get_value("preset.1", "custom_features", "")) == "firebase_check", "確認用の書き出しは、機能タグ firebase_check を持つ")

	# 起動シーンは変えていない
	var project := FileAccess.get_file_as_string("res://project.godot")
	check(project.contains('run/main_scene="res://scenes/render_test.tscn"'), "起動シーンは render_test のまま")
	check(project.contains('run/main_scene.firebase_check="res://scenes/experiments/firebase_check.tscn"'), "firebase_check の機能タグのときだけ、確認シーンから始まる")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)


func _make_fake_web(packed: PackedScene, bridge: Callable) -> Control:
	var node: Control = packed.instantiate()
	node.is_web = true
	node.js_eval = bridge
	return node
