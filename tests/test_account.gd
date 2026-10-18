extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_account.gd
## アカウント（ログイン・保存・フレンド・しょうたい）の、ゲーム側の画面と橋渡しを確かめる。

const AccountBridge := preload("res://scripts/network/account_bridge.gd")
const SCENE := "res://scenes/game_flow.tscn"

var failures := 0
var sent: Array = []
var acc_state := {}


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _fake(code: String) -> Variant:
	sent.append(code)
	if code == "typeof window.bbAccount" or code == "typeof window":
		return "object"
	if code == "typeof window.bbFirebase":
		return null
	if code == "JSON.stringify(window.bbAccount.state)":
		return JSON.stringify(acc_state)
	return null


func _texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_texts(c, out)


func _initialize() -> void:
	check(AccountBridge.build_init_call("{\"a\":1}") == "window.bbAccount.init(\"{\\\"a\\\":1}\")", "初期化の呼び出し（引用符もこわれない）")
	check(AccountBridge.build_set_save_call({"coins": 12, "wins": 3, "character": "healer", "quality": "low", "secret": "x"}) == "window.bbAccount.setSave(" + JSON.stringify(JSON.stringify({"coins": 12, "wins": 3, "character": "healer", "quality": "low"})) + ")", "保存の呼び出し（余計な項目は送らない）")
	check(AccountBridge.build_invite_call("SID", "1234") == "window.bbAccount.invite(\"SID\", \"1234\")", "しょうたいの呼び出し")
	check(AccountBridge.build_show_form_call("login", {"title_login": "T"}).begins_with("window.bbAccount.showForm(\"login\", {"), "入力欄の呼び出し")
	check(AccountBridge.parse_state("zzz").is_empty() and AccountBridge.parse_state("{\"signedIn\":true}")["signedIn"] == true, "状態の読み取り")

	acc_state = {"signedIn": false, "message": ""}
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.js_eval = _fake
	flow.clock_ms = func() -> float: return 2000.0
	root.add_child(flow)
	if flow.config.is_empty():
		flow._ready()
	if flow.account == null:
		flow.init_account()
	check(flow.account != null and sent.any(func(c): return str(c).begins_with("window.bbAccount.init(")), "ブラウザ側の入り口があれば、アカウントを始める")
	check(sent.any(func(c): return str(c).begins_with("window.bbAccount.setSave(")), "起動のとき、いまの記録を渡す")
	flow.goto("lobby")
	flow.event("account")
	check(flow.state == "account", "ロビー → アカウント")
	flow._process(1.0)
	var t: Array = []
	_texts(flow.account_box, t)
	check(t.any(func(x): return str(x).contains("ゲスト")) and t.any(func(x): return x == "ログインを つくる") and t.any(func(x): return x == "パスワードを わすれた"), "ゲストには、ログインを作る・ログイン・わすれたが出る")
	# 「ログインを つくる」を押すと、入力欄の画面を出す
	sent.clear()
	for c in flow.account_box.get_children():
		if c is Button and (c as Button).text == "ログインを つくる":
			(c as Button).pressed.emit()
	check(sent.any(func(c): return str(c).begins_with("window.bbAccount.showForm(\"register\"")), "「ログインを つくる」で、ブラウザ側の入力欄が出る")
	# ログインした：サーバーの記録が、この端末に反映される
	acc_state = {"signedIn": true, "loginId": "ABCDE23456", "nickname": "", "friendCode": "FRIEND23", "friends": [], "inbox": [], "message": "", "save": {"coins": 999, "wins": 7, "character": "healer", "quality": "high"}}
	flow._process(1.0)
	check(int(flow.save["coins"]) == 999 and int(flow.save["wins"]) == 7 and flow.selected_character == "healer", "ログインした人の記録（サーバー）が、この端末に入る")
	t = []
	_texts(flow.account_box, t)
	check(t.any(func(x): return str(x).contains("ABCDE23456")) and t.any(func(x): return x == "ログアウト"), "ログイン中は、IDとログアウトが出る")
	# 記録が変わったら、サーバーにも渡す
	sent.clear()
	flow._write_save()
	check(sent.any(func(c): return str(c).begins_with("window.bbAccount.setSave(")), "記録を書くたびに、アカウントにも渡す")
	# フレンド
	flow.goto("lobby")
	flow.event("friends")
	acc_state["friends"] = [{"sid": "FSID", "nickname": "びー"}]
	acc_state["inbox"] = [{"from": "ASID", "type": "friend", "nickname": "えー", "room": "", "t": 1}, {"from": "BSID", "type": "invite", "nickname": "しー", "room": "5678", "t": 2}]
	flow._process(1.0)
	t = []
	_texts(flow.friends_box, t)
	check(t.any(func(x): return str(x).contains("FRIEND23")), "自分のフレンドコードが出る")
	check(t.any(func(x): return str(x).contains("えー") and str(x).contains("もうしこみ")) and t.any(func(x): return x == "ひきうける"), "フレンドの申しこみに、ひきうけるが出る")
	check(t.any(func(x): return str(x).contains("しー") and str(x).contains("しょうたい")) and t.any(func(x): return x == "さんかする"), "しょうたいに、さんかするが出る")
	check(t.any(func(x): return str(x).contains("びー")), "フレンドの一覧")
	sent.clear()
	flow.room_code = "4321"
	for c in flow.friends_box.get_children():
		if c is Button and (c as Button).text.begins_with("びー"):
			(c as Button).pressed.emit()
		if c is Button and (c as Button).text == "ひきうける":
			(c as Button).pressed.emit()
	check(sent.any(func(c): return str(c) == "window.bbAccount.invite(\"FSID\", \"4321\")"), "フレンドの「しょうたい」で、いまの部屋の合言葉を送る")
	check(sent.any(func(c): return str(c) == "window.bbAccount.acceptFriend(\"ASID\")"), "「ひきうける」を送る")
	# しょうたいに参加：ロビーにボタンが出て、その部屋に入り直す
	flow.goto("lobby")
	flow._process(1.0)
	check(flow.invite_join_button.visible and flow.invite_join_button.text.contains("しー"), "ロビーに、しょうたいの「さんか」が出る")
	sent.clear()
	flow.join_invite()
	check(flow.room_code == "5678" and flow.room_from_url and sent.any(func(c): return str(c) == "window.bbAccount.removeInbox(\"BSID\")"), "さんかすると、その部屋に変わり、しょうたいは片づく")
	flow.join_invite_of("X", "12ab")
	check(flow.room_code == "5678", "不正な合言葉のしょうたいは、無視する")
	# ブラウザ側の入り口がなければ（通信なし）、案内を出して壊れない
	var flow2: Node = (load(SCENE) as PackedScene).instantiate()
	flow2.js_eval = func(code: String) -> Variant: return null
	root.add_child(flow2)
	if flow2.config.is_empty():
		flow2._ready()
	flow2.goto("friends")
	check(flow2.account == null and flow2.friends_box.get_child_count() == 1, "入り口がなければ、案内だけ出る")
	flow2._write_save()
	root.remove_child(flow2)
	root.remove_child(flow)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
