extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v118.gd
## 版118：軽量化。再戦・画面の行き来をくり返しても、物（ノード）・すてられた物（どこにもつながっていないノード）がふえ続けない。
## 戦いの中で、呼び出し・飛ぶ物・見出しを使ってから次の試合にしても、前の物が残らない。数は Performance（Godot の数え方）で測る。
## ボタンは自分の板に、見た目が変わった時だけ描き直す（毎コマは描かない）。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
const SCENE := "res://scenes/game_flow.tscn"
const BATTLE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	# ---- 1. 画面の流れ：戦い → 結果 → 再戦 → 準備 → START を4回 ----
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v118_save.json"
	flow.config["ai_picks_path"] = "user://test_v118_ai.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v118_save.json"))
	root.add_child(flow)
	await frames(3)  # 本当の _ready を待つ（手で呼ぶと、あとでもう一度呼ばれて、はじめの画面にもどる）
	flow.goto(Logic.LOBBY)
	await frames(3)
	var counts: Array = []
	var orph: Array = []
	for cycle in 4:
		if cycle == 0:
			flow.play()
		else:
			flow.event("rematch")
			flow.event("start")
		await frames(3)
		var b: Node = flow.battle
		if b == null:
			check(false, "戦いが始まる（%d回め）" % cycle)
			break
		# 戦いの中で、いろいろ使う（呼び出し・必殺技・見出し）
		b.skill_time_stop_left = 999.0
		b.show_headline("rage")
		b.show_toast("テスト")
		b.skills.apply_effect(b._my_slot(), {"type": "summon", "unit": "soldier", "count": 4, "attacks": 2, "sec": 3.0, "first": 0.2, "interval": 0.3,
			"multiplier": 1.0, "speed": 5.0, "reach": 1.0, "max_active": 12}, Vector2(0, -1), 9.0)
		for i in 30:
			b._actions_update(0.05)
			b.combat_update(0.05)
		await frames(2)
		b.round_ended.emit(true)
		flow._process(5.0)
		await frames(4)
		check(flow.state == Logic.REWARD and flow.battle == null, "%d回め：結果へ・戦いは片づけた" % (cycle + 1))
		await frames(4)
		counts.append(nodes())
		orph.append(orphans())
	print("ノードの数（結果の画面で）：", counts, "  すてられた物：", orph)
	check(counts.size() == 4 and int(counts[3]) - int(counts[1]) <= 5, "再戦をくり返しても、ノードがふえ続けない（%s）" % str(counts))
	check(orph.size() == 4 and int(orph[3]) - int(orph[1]) <= 2, "どこにもつながっていないノードが、ふえ続けない（%s）" % str(orph))

	# ---- 2. 画面の行き来（ロビー ⇔ 編成 ⇔ ガチャ ⇔ プロフィール）を10回 ----
	flow.goto(Logic.LOBBY)
	await frames(3)
	# 1周目は、はじめて開く画面の部品を作るので、数に入れない
	for st in [Logic.FORMATION, Logic.LOBBY, Logic.ACCOUNT, Logic.LOBBY]:
		flow.goto(st)
		await frames(2)
	await frames(4)
	var n0 := nodes()
	for i in 10:
		for st in [Logic.FORMATION, Logic.LOBBY, Logic.ACCOUNT, Logic.LOBBY]:
			flow.goto(st)
			await frames(1)
	await frames(4)
	var n1 := nodes()
	check(n1 - n0 <= 5, "画面の行き来を40回しても、ノードがふえ続けない（%d → %d）" % [n0, n1])
	root.remove_child(flow)
	flow.free()
	await frames(2)

	# ---- 3. 戦いの中の次の試合（start_round）：前の呼び出し・飛ぶ物・演出が残らない ----
	var s: Node = (load(BATTLE) as PackedScene).instantiate()
	s.selected_character = "summoner"
	s.ai_enabled = false  # 仲間の技の見た目は、数える時刻によって数が変わるので、自分だけで測る
	root.add_child(s)
	await frames(2)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [9000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	var per: Array = []
	for r in 3:
		s.won = false
		s.lost = false
		s._begin_round(now[0])
		s.skill_time_stop_left = 999.0
		s.perform("main")
		s.gauge.value = s.gauge.max_value
		for i in 40:
			s._actions_update(0.05)
			s.combat_update(0.05)
			now[0] += 50.0
		s.perform("ultimate")
		for i in 30:
			s._actions_update(0.05)
			s.combat_update(0.05)
			now[0] += 50.0
		# 技の見た目（光・粒）が消えるまで、少し進める（残り続ける物だけを数えるため）
		for i in 120:
			s._actions_update(0.05)
			s.combat_update(0.05)
			s.update_cues(0.05)
			now[0] += 50.0
		s.won = true
		await frames(3)
		per.append(nodes())
		now[0] += 60000.0
	s.won = false
	s._begin_round(now[0])
	await frames(3)
	check(s.skill_summons.is_empty() and s.skill_projs.is_empty() and float(s.headline["left"]) == 0.0, "次の試合：前の呼び出し・飛ぶ物・見出しは残らない")
	print("戦いを3回くり返したノードの数：", per)
	check(int(per[2]) == int(per[1]) and int(per[1]) - int(per[0]) <= 2, "戦いをくり返しても、ノードがふえない（%s）" % str(per))
	# ---- 4. ボタンは、見た目が変わった時だけ描き直す（毎コマは描かない）----
	s.won = false
	s._begin_round(now[0] + 1000.0)
	s.actions.reset()
	s.gauge.value = 0.0
	await frames(3)
	var r0: int = s.hud.button_redraws
	for i in 60:
		s.hud.update_buttons()
		await process_frame
	var idle_redraws: int = s.hud.button_redraws - r0
	check(idle_redraws <= 2, "何もしていない60コマで、ボタンの描き直しは %d 回（前は毎コマ）" % idle_redraws)
	s.perform("sub")
	var r1: int = s.hud.button_redraws
	for i in 30:
		s.actions.update(1.0 / 60.0)
		s.hud.update_buttons()
		await process_frame
	check(s.hud.button_redraws > r1, "技を使うと、ボタンを描き直す（暗くする・待ち時間の帯）")
	root.remove_child(s)
	s.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v118_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v118_ai.json"))
	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
