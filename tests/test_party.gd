extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_party.gd
## ロビーから部屋に入り、戦いを出入りしても部屋が続くこと、あとから来た人は戦いに入れないこと、
## ロビー・時間切れで全員ロビーに戻ることを確かめる。

const SCENE := "res://scenes/game_flow.tscn"
var failures := 0
var sent: Array = []
var state := {}


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _fake(code: String) -> Variant:
	sent.append(code)
	if code == "typeof window.bbFirebase" or code == "typeof window":
		return "object"
	if code.contains("URLSearchParams"):
		return "4321"
	if code.begins_with("JSON.stringify(window.bbFirebase.state)"):
		return JSON.stringify(state)
	return null


func _ready_battle(flow: Node) -> Node:
	if flow.battle.config.is_empty():
		flow.battle._ready()
	return flow.battle


func _initialize() -> void:
	state = {"status": "in_room", "slot": "p1", "members": ["p1"], "round": 1000.0, "offset": 0.0, "votes": {}, "positions": {}, "hits": {}, "hp": {}, "chars": {}}
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.js_eval = _fake
	flow.clock_ms = func() -> float: return 2000.0
	root.add_child(flow)
	if flow.config.is_empty():
		flow._ready()
	if flow.bridge == null:
		flow.init_room()
		flow.join_room()
	check(flow.room_code == "4321" and flow.bridge != null, "ロビーの時点で、部屋に入る")
	flow.goto("lobby")
	flow._process(1.0)
	check(flow.room_label.text.contains("4321") and flow.room_label.text.contains("1"), "ロビーに、部屋の人数が出る")
	# 1人目は、待っている間に試合ができる
	flow.goto("battle")
	var b: Node = _ready_battle(flow)
	check(b.shared_bridge == flow.bridge and b.net_active and is_equal_approx(b.known_round, 1000.0), "戦いは、ロビーの部屋をそのまま使い、前の戦いは始めない")
	b.won = true
	b.round_start_ms = 2000.0
	b.net_state = state.duplicate(true)
	b.net_state["round"] = 2000.0
	# 戦いの途中で、2人目が部屋に入ってきた（戦いには出ていない）
	state["members"] = ["p1", "p2"]
	state["round"] = 2000.0
	b.net_state["members"] = ["p1", "p2"]
	check(b.idle_members() == ["p2"], "あとから来た人（戦いに出ていない）が分かる")
	sent.clear()
	flow.goto("highlight")
	flow.goto("reward")
	flow._process(0.1)
	check(not flow.rematch_button_reward.visible and not flow.rematch_button_next.visible, "あとから来た人がいたら、「さいせん」のボタンは消える")
	check(flow.rematch_wait_reward.text == str(flow.config["party_gathered_text"]), "「ロビーで あつまろう」と出る")
	flow._process(float(flow.config["rematch_timeout_sec"]) + 5.0)
	check(flow.state == "reward", "あとから来た人がいる間は、時間切れでも勝手に動かない")
	flow.event("lobby")
	check(flow.state == "lobby" and flow.battle == null and not sent.any(func(c): return str(c).contains("leaveRoom")), "「ロビー」で戻る。部屋からは出ない")
	check(sent.any(func(c): return str(c).contains("sendVote(\"lobby\"")), "ロビーの投票を送る（ほかの人もロビーへ）")
	# ロビーにいる間に、仲間が戦いを始めても、いっしょには入らない
	state["round"] = 3000.0
	flow._process(1.0)
	check(flow.state == "lobby", "戦いの最中の人の試合に、あとから入らない")
	# ロビーで合流して、いっしょに戦う：入った時点の戦いは始めない。つぎの開始から、2人で
	flow.goto("battle")
	var b2: Node = _ready_battle(flow)
	check(is_equal_approx(b2.known_round, 3000.0), "入った時点の戦いは始めない")
	b2.won = true
	b2.round_start_ms = 4000.0
	b2.net_state = state.duplicate(true)
	b2.net_state["round"] = 4000.0
	b2.net_state["hp"] = {"p2": {"hp": 50.0, "round": 4000.0}}
	check(b2.idle_members().is_empty(), "2人とも戦いに出ていれば、あとから来た人はいない")
	flow.goto("highlight")
	flow.goto("reward")
	flow._process(0.1)
	check(flow.rematch_button_reward.visible, "2人とも出ていれば、「さいせん」が使える")
	# 1人が「ロビー」→ 全員ロビー
	b2.net_state["votes"] = {"p2": {"v": "lobby", "round": 4000.0}}
	flow._process(0.1)
	check(flow.state == "lobby", "1人が「ロビー」を押すと、全員ロビーに戻る")
	# 時間切れ：そろわなければ、全員ロビー
	flow.goto("battle")
	var b3: Node = _ready_battle(flow)
	b3.won = true
	b3.round_start_ms = 5000.0
	b3.net_state = state.duplicate(true)
	b3.net_state["hp"] = {"p2": {"hp": 50.0, "round": 5000.0}}
	b3.net_state["votes"] = {"p1": {"v": "rematch", "round": 5000.0}}
	flow.goto("highlight")
	flow.goto("reward")
	sent.clear()
	flow._process(float(flow.config["rematch_timeout_sec"]) + 1.0)
	check(flow.state == "lobby" and sent.any(func(c): return str(c).contains("sendVote(\"lobby\"")), "時間内にそろわなければ、全員ロビー")
	flow.new_room()
	check(sent.any(func(c): return str(c).contains("leaveRoom")), "「べつのへや」だけは、前の部屋を出て、入り直す")
	root.remove_child(flow)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
