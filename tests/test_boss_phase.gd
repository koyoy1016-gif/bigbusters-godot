extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_boss_phase.gd
## ボスの体力の2段階制（scripts/combat/boss_phase.gd）と、戦いの画面での動き

const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var p := BossPhase.new()
	p.reset(4000.0, 4000.0, 3.4, 1.2)
	check(p.phase == "normal" and p.hp(0.0) == 4000.0 and p.max_hp() == 4000.0, "第1形態は体力4000から")
	check(p.on_total(3999.0) == "" and is_equal_approx(p.hp(3999.0), 1.0), "4000未満では、まだ倒れない")
	check(p.on_total(4100.0) == "fall" and p.phase == "fall", "第1形態の体力が0になると、倒れる（勝ちにはならない）")
	check(p.invulnerable() and not p.can_attack(), "倒れて覚醒する間は、無敵で、攻撃もしない")
	check(p.hp(4100.0) == 0.0, "倒れた直後の表示は0")
	check(p.on_total(9000.0) == "", "演出中のダメージでは、何も起きない")
	var ev := ""
	var t := 0.0
	var shown_mid := -1.0
	while ev != "awake" and t < 10.0:
		ev = p.tick(0.1, 4100.0)
		t += 0.1
		if t > 2.8 and t < 3.0:
			shown_mid = p.hp(4100.0)
	check(shown_mid > 0.0 and shown_mid < 4000.0, "演出の終わりに、体力の表示が0から増えていく（%.0f）" % shown_mid)
	check(absf(t - 3.4) < 0.15, "覚醒するのは、倒れてから約3.4秒後")
	check(ev == "awake" and p.phase == "awake" and p.max_hp() == 4000.0 and is_equal_approx(p.hp(4100.0), 4000.0), "覚醒すると、第2形態の体力4000（全回復）")
	check(not p.invulnerable() and p.can_attack(), "覚醒したら、また攻撃する・ダメージが入る")
	check(is_equal_approx(p.hp(5100.0), 3000.0), "第2形態は、覚醒してからのダメージだけで減る")
	check(p.on_total(8000.0) == "", "第2形態の体力が残っていれば、倒れない")
	check(p.on_total(8100.0) == "dead" and p.phase == "dead" and p.hp(8100.0) == 0.0, "第2形態の体力が0で、完全に倒す")
	check(p.on_total(99999.0) == "" and p.tick(5.0, 99999.0) == "", "倒したあとは、何も起きない（覚醒しなおさない）")

	# 戦いの画面で：第1形態を0にしても勝ちにならず、覚醒して、第2形態を0にして勝ち
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [1000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.my_hits = float(s.config["boss_hp"]) + 50.0
	s._recompute_boss_hp()
	check(not s.won and s.round_active() and s.boss.visible, "第1形態の体力が0でも、勝ちにならない")
	check(s.phase.phase == "fall" and s.boss_model.is_staggering(), "ボスが倒れる")
	var before: float = s.my_hits
	s.player.position = s.boss.position + Vector3(0, 0, 3.0)
	s.attack()
	check(is_equal_approx(s.my_hits, before), "倒れている間は、こうげきしてもダメージが入らない")
	var guard := 0
	while s.phase.phase == "fall" and guard < 400:
		now[0] += 20.0
		s._process(0.02)
		if not s.current_attack.is_empty() and s.phase.phase == "fall":
			check(false, "倒れている間に、攻撃が出た")
		guard += 1
	check(s.phase.phase == "awake" and s.boss_model.is_awake() and is_equal_approx(s.boss_hp, float(s.config["boss_hp_awake"])), "起き上がると覚醒し、体力が全回復（%.0f）" % s.boss_hp)
	s.my_hits += float(s.config["boss_hp_awake"]) - 10.0
	s._recompute_boss_hp()
	check(not s.won and s.boss_hp > 0.0, "第2形態の体力が残っていれば、続く")
	s.my_hits += 20.0
	s._recompute_boss_hp()
	check(s.won and not s.round_active() and s.boss_hp == 0.0, "第2形態の体力が0で、勝ち")
	now[0] += 5000.0
	s._process(0.02)
	check(s.current_hazards.is_empty() and s.phase.phase == "dead", "勝ったあとは、攻撃の当たりが残らない")
	s.start_round()
	check(s.phase.phase == "normal" and is_equal_approx(s.boss_hp, float(s.config["boss_hp"])) and not s.boss_model.is_awake(), "もういちどで、第1形態から")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
