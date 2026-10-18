extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_rematch.gd
## 通信中の「全員さいせん」（投票の取り出し、休止、開始係、戻り）を確かめる。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const SCENE := "res://scenes/game_flow.tscn"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var raw := {"p1": {"v": "rematch", "round": 1000.0}, "p2": {"v": "rematch", "round": 500.0}, "p3": "bad"}
	var cur := Logic.current_votes(raw, 1000.0)
	check(cur == {"p1": "rematch"}, "いまの戦いの投票だけ取り出す（古い・壊れたものは無視）")
	check(Logic.lowest_slot(["p3", "p2", "p4"]) == "p2" and Logic.lowest_slot([]) == "", "いちばん若い枠")
	check(Logic.vote_count({"p1": "rematch", "p2": "lobby", "p9": "rematch"}, ["p1", "p2"]) == 1, "さいせんの人数（部屋にいる人だけ）")

	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	if flow.config.is_empty():
		flow._ready()
	flow.goto("battle")
	var b: Node = flow.battle
	if b.config.is_empty():
		b._ready()
	var sent: Array = []
	b.net_active = true
	b.bridge.js_eval = func(code: String) -> Variant:
		sent.append(code)
		return null
	b.round_start_ms = 1000.0
	b.won = true
	b.known_round = 1000.0
	b.net_state = {"slot": "p1", "members": ["p1", "p2"], "votes": {}, "round": 1000.0}
	flow.goto("highlight")
	check(flow.battle == b and b.dormant, "通信中は、ハイライトの間も、戦いを部屋に残して休止する")
	check(not (b.get_node("UI") as CanvasLayer).visible, "休止中は戦いの画面を隠す")
	flow.goto("reward")
	flow.event("rematch")
	check(flow.state == "reward" and flow.my_rematch_vote, "通信中の「さいせん」は、投票だけして待つ")
	check(sent.any(func(c): return str(c).contains("sendVote(\"rematch\"")), "投票を部屋に送る")
	flow._rematch_update(0.1)
	check(flow.rematch_wait_reward.text.contains("0/2"), "待ち表示：0/2")
	b.net_state["votes"] = {"p1": {"v": "rematch", "round": 1000.0}}
	flow._rematch_update(0.1)
	check(flow.rematch_wait_reward.text.contains("1/2"), "待ち表示：1/2")
	sent.clear()
	flow._rematch_update(0.1)
	check(not sent.any(func(c): return str(c).contains("startRound")), "全員がそろうまで、開始しない")
	b.net_state["votes"] = {"p1": {"v": "rematch", "round": 1000.0}, "p2": {"v": "rematch", "round": 1000.0}}
	flow._rematch_update(0.1)
	check(sent.any(func(c): return str(c).to_lower().contains("startround")), "全員そろったら、いちばん若い枠(p1)が開始を書く")
	sent.clear()
	flow._rematch_update(0.1)
	check(sent.is_empty(), "開始の書き込みは、すぐには繰り返さない")
	# p2 は開始係ではない
	b.net_state["slot"] = "p2"
	flow.starter_cooldown = 0.0
	flow._rematch_update(0.1)
	check(sent.is_empty(), "開始係でない人は、書かない")
	# 新しい戦いが始まったら、休止を解いて戦いに戻る
	b.dormant = true
	b._begin_round(5000.0)
	check(flow.state == "battle" and not b.dormant and flow.battle == b, "新しい戦いが始まると、戦いに戻る（作り直さない）")
	check((b.get_node("UI") as CanvasLayer).visible and not flow.my_rematch_vote, "画面が戻り、投票はリセットされる")
	# ロビーに戻れば、片づく
	flow.goto("highlight")
	flow.goto("lobby")
	check(flow.battle == null, "ロビーに戻ると、部屋の戦いは片づく")
	root.remove_child(flow)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
