extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_lobby_rules.gd
## ロビーの決まり：戦い中の部屋には入れない／全員が「プレイ」を押してから始まる／しょうたいは1人のときだけ／
## 同じ人が2つの画面で使えない（外された画面は、あそべない）

const SCENE := "res://scenes/game_flow.tscn"
const Logic := preload("res://scripts/flow/flow_logic.gd")
var failures := 0
var sent: Array = []
var state := {}
var acc := {}


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _fake(code: String) -> Variant:
	sent.append(code)
	if code == "typeof window.bbFirebase" or code == "typeof window" or code == "typeof window.bbAccount":
		return "object"
	if code.contains("URLSearchParams"):
		return "4321"
	if code.begins_with("JSON.stringify(window.bbFirebase.state)"):
		return JSON.stringify(state)
	if code.begins_with("JSON.stringify(window.bbAccount.state)"):
		return JSON.stringify(acc)
	return null


func _count(prefix: String) -> int:
	var n := 0
	for c in sent:
		if str(c).begins_with(prefix):
			n += 1
	return n


func _initialize() -> void:
	# --- 計算 ---
	var room := {"status": "in_room", "slot": "p1", "members": ["p1", "p2"], "phases": {}}
	check(Logic.other_members(room) == ["p2"], "自分以外の人")
	check(Logic.other_members({"status": "left", "slot": "", "members": ["p1"]}).is_empty(), "部屋にいなければ、ひとりあつかい")
	check(not Logic.others_busy(room), "phase がなければ、戦い中ではない")
	room["phases"] = {"p2": {"v": "battle", "t": 1}}
	check(Logic.others_busy(room), "ほかの人が戦い中")
	room["phases"] = {"p2": {"v": "result", "t": 1}}
	check(Logic.others_busy(room), "ほかの人が結果の画面でも、まだ入れない")
	room["phases"] = {"p2": {"v": "lobby", "t": 1}}
	check(not Logic.others_busy(room) and not Logic.all_ready(room), "ロビーにいる人は、まだ ready ではない")
	room["phases"] = {"p2": {"v": "ready", "t": 1}}
	check(Logic.all_ready(room), "全員 ready")
	check(Logic.all_ready({"status": "in_room", "slot": "p1", "members": ["p1"], "phases": {}}), "ひとりなら、すぐ始められる")
	check(Logic.phase_of("lobby", true) == "ready" and Logic.phase_of("lobby", false) == "lobby", "ロビーの状態名")
	check(Logic.phase_of("battle", false) == "battle" and Logic.phase_of("reward", false) == "result" and Logic.phase_of("account", false) == "lobby", "戦い・結果・そのほか")

	# --- ゲームの流れ ---
	state = {"status": "in_room", "slot": "p1", "members": ["p1"], "round": 0.0, "offset": 0.0, "votes": {}, "positions": {}, "hits": {}, "hp": {}, "chars": {}, "phases": {}}
	acc = {"status": "ok", "signedIn": false, "sid": "", "displaced": false, "inbox": [], "friends": []}
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.js_eval = _fake
	flow.clock_ms = func() -> float: return 2000.0
	root.add_child(flow)
	if flow.config.is_empty():
		flow._ready()
	if flow.bridge == null:
		flow.init_room()
		flow.join_room()
	flow.goto("lobby")
	flow._poll_room(1.0)
	check(flow.invite_button.disabled == false and flow.leave_button.disabled == true, "ひとりのとき：しょうたいできる／ぬけるは押せない")
	check(_count("window.bbFirebase.sendPhase(\"lobby\")") == 1, "ロビーの状態を部屋に送る")

	# ひとりでプレイ → すぐ戦い
	flow.play()
	check(flow.state == "battle", "ひとりなら、プレイですぐ戦いに入る")
	flow.goto("lobby")

	# ふたり：ほかの人が戦い中 → おまちください
	state["members"] = ["p1", "p2"]
	state["phases"] = {"p2": {"v": "battle", "t": 1}}
	flow._poll_room(1.0)
	check(flow.play_button.disabled and flow.play_button.text == str(flow.config["play_busy_label"]), "ほかの人が戦い中：プレイは押せず、おまちくださいと出る")
	flow.play()
	check(flow.state == "lobby" and not flow.waiting_ready, "戦い中は、プレイを押しても入れない")
	check(flow.invite_button.disabled == false and flow.leave_button.disabled == false, "ふたり：しょうたいも ぬけるも押せる（4人まで呼べる）")
	state["members"] = ["p1", "p2", "p3", "p4"]
	flow._poll_room(1.0)
	check(flow.invite_button.disabled and flow.invite_button.text == str(flow.config["invite_locked_label"]), "4人そろうと、しょうたいは押せない")
	flow.invite()
	check(_count("window.bbShare") == 0, "4人のとき、しょうたいの画面は出ない")
	state["members"] = ["p1", "p2"]

	# 戦いが終わって、相手がロビーに戻った → 押すと「まっています」
	state["phases"] = {"p2": {"v": "lobby", "t": 2}}
	flow._poll_room(1.0)
	check(not flow.play_button.disabled, "相手がロビーに戻れば、押せる")
	flow.play()
	check(flow.waiting_ready and flow.state == "lobby", "相手がまだなら、まつ")
	flow._poll_room(1.0)
	check(_count("window.bbFirebase.sendPhase(\"ready\")") == 1, "ready を送る")
	# もういちどおすと、やめる
	flow.play()
	check(not flow.waiting_ready, "もういちど おすと、まつのをやめる")
	flow.play()
	# 相手も押した → 同時に戦いへ
	state["phases"] = {"p2": {"v": "ready", "t": 3}}
	flow._poll_room(1.0)
	check(flow.state == "battle" and not flow.waiting_ready, "全員が押したら、戦いに入る")
	flow.goto("lobby")

	# へやを ぬける
	var before: String = flow.room_code
	flow.new_room()
	check(flow.room_code != before, "ぬけると新しい部屋")
	check(_count("window.bbFirebase.leaveRoom()") >= 1, "ぬけるとき、部屋から退出する")

	# ほかの画面で開かれた
	state["members"] = ["p1"]
	state["phases"] = {}
	flow._poll_account(1.0)
	check(_count("window.bbAccount.claimSession()") == 1, "起動したら、この画面を使う画面にする")
	acc["displaced"] = true
	flow.claim_grace = 0.0
	flow._poll_account(1.0)
	check(flow.displaced_box.visible, "外されたら、案内の画面を出す")
	flow.goto("lobby")
	flow.reclaim_session()
	check(not flow.displaced_box.visible and _count("window.bbAccount.claimSession()") == 2, "「この画面で つかう」で取りもどす")
	# 部屋の人にフレンド申請
	acc = {"status": "ok", "signedIn": true, "sid": "AAAAAAAAAAAA", "friendCode": "ABCDEFGH", "nickname": "えー", "displaced": false, "inbox": [], "friends": [], "preview": null}
	state["members"] = ["p1", "p2", "p3"]
	state["who"] = {"p2": {"sid": "BBBBBBBBBBBB", "nickname": "びー"}}
	flow.goto("lobby")
	flow._poll_room(1.0)
	flow._poll_account(1.0)
	flow._poll_room(1.0)
	check(flow.party_box.get_child_count() == 1, "アカウントの人だけ、一覧に出る（ゲストの p3 は出ない）")
	check(_count("window.bbAccount.announce(") >= 1, "自分の席の持ち主を部屋に書く")
	flow._request_friend_of("BBBBBBBBBBBB")
	check(_count("window.bbAccount.requestFriendSid(\"BBBBBBBBBBBB\")") == 1, "ボタンで、フレンドの申しこみを送る")
	flow._poll_room(1.0)
	check(flow.party_box.get_child(0).get_child(1).disabled, "送ったあとは、もうしこみずみ")
	# LINEのフレンドURL
	acc["preview"] = {"code": "ZZZZZZZZ", "status": "ok", "nickname": "しー"}
	flow._poll_account(1.0)
	check(flow.friend_box.visible and flow.friend_box_col.get_child_count() == 3, "ついかする／キャンセルの画面が出る")
	flow._close_friend_preview()
	check(not flow.friend_box.visible and _count("window.bbAccount.clearPreview()") == 1, "キャンセルで閉じる")
	acc["preview"] = {"code": "ZZZZZZZZ", "status": "needlogin", "nickname": ""}
	flow._poll_account(1.0)
	check(flow.friend_box.visible and flow.friend_box_col.get_child_count() == 2, "ログインしていなければ、案内だけ出る")
	var RoomLinkT := load("res://scripts/network/room_link.gd")
	check(RoomLinkT.build_friend_url("https://x.io/a/?room=1#h", "ABCDEFGH") == "https://x.io/a/?friend=ABCDEFGH", "フレンドURLの形")
	flow.queue_free()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
