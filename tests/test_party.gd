extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_party.gd
## ロビーから部屋に入り、戦いを出入りしても部屋が続くこと、ロビー・時間切れで全員ロビーに戻ることを確かめる。

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
	state = {"status": "in_room", "slot": "p1", "members": ["p1", "p2"], "round": 1000.0, "offset": 0.0, "votes": {}, "positions": {}, "hits": {}, "hp": {}, "chars": {}}
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
	check(sent.any(func(c): return str(c).begins_with("window.bbFirebase.joinRoom(") and str(c).contains("\"4321\"")), "入室の呼び出し")
	flow.goto("lobby")
	flow._process(1.0)
	check(flow.room_label.text.contains("4321") and flow.room_label.text.contains("2"), "ロビーに、部屋の人数が出る")
	check(is_equal_approx(flow.stale_round, 1000.0) and flow.state == "lobby", "部屋に前からあった戦いの時刻は、新しい戦いとして扱わない")
	# 戦いに入っても、部屋は同じ橋渡し
	flow.goto("battle")
	var b: Node = _ready_battle(flow)
	check(b.shared_bridge == flow.bridge and b.net_active and is_equal_approx(b.known_round, 1000.0), "戦いは、ロビーの部屋をそのまま使い、前の戦いは始めない")
	b.won = true
	b.round_start_ms = 1000.0
	sent.clear()
	flow.goto("highlight")
	flow.goto("reward")
	flow.goto("next")
	flow.goto("lobby")
	check(flow.battle == null and not sent.any(func(c): return str(c).contains("leaveRoom")), "ロビーに戻っても、部屋からは出ない")
	check(is_equal_approx(flow.stale_round, 1000.0), "ロビーに戻った時点の戦いの時刻を覚える")
	# 仲間が新しい戦いを始めたら、ロビーにいる人もいっしょに戦いに入る
	state["round"] = 1900.0
	flow._process(1.0)
	check(flow.state == "battle" and flow.battle != null, "仲間が戦いを始めると、ロビーの人も戦いに入る")
	_ready_battle(flow)
	check(is_equal_approx(flow.battle.known_round, 1000.0), "（入った戦いは、その新しい時刻から始まる）")
	flow.battle.net_state = state
	# 1人が「ロビー」→ 全員ロビー
	var b2: Node = flow.battle
	b2.won = true
	b2.round_start_ms = 1900.0
	flow.goto("highlight")
	flow.goto("reward")
	state["votes"] = {"p2": {"v": "lobby", "round": 1900.0}}
	b2.net_state = state
	flow._process(0.1)
	check(flow.state == "lobby", "1人が「ロビー」を押すと、全員ロビーに戻る")
	# 時間切れ：そろわなければ、全員ロビー
	flow.goto("battle")
	var b3: Node = _ready_battle(flow)
	b3.won = true
	b3.round_start_ms = 1900.0
	b3.net_state = state
	state["votes"] = {"p1": {"v": "rematch", "round": 1900.0}}
	flow.goto("highlight")
	flow.goto("reward")
	sent.clear()
	flow._process(float(flow.config["rematch_timeout_sec"]) + 1.0)
	check(flow.state == "lobby" and sent.any(func(c): return str(c).contains("sendVote(\"lobby\"")), "時間内にそろわなければ、全員ロビー（ロビーの投票も送る）")
	flow.new_room()
	check(sent.any(func(c): return str(c).contains("leaveRoom")) and flow.stale_pending, "「あたらしいへや」だけは、前の部屋を出て、入り直す")
	root.remove_child(flow)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
