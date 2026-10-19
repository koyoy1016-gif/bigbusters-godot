extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_awake_rides.gd
## 版64・版66：覚醒の体力は9000（版66で6000の1.5倍）。覚醒の体力が4分の1減るたびに、必ず巨大酒瓶ライドが入る（3回）。それ以外でもランダムに出る。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	check(is_equal_approx(float(cfg["boss_hp_awake"]), 11250.0) and is_equal_approx(float(cfg["boss_hp"]), 6000.0), "覚醒の体力は 11250、平常は 6000（版68）")
	check(is_equal_approx(float(cfg["awake_ride_every"]), 0.25), "区切りは4分の1")

	# 区切りの数
	var ph := BossPhase.new()
	ph.reset(4000.0, 9000.0, 3.4, 1.2)
	check(ph.awake_steps(500.0, 0.25) == 0, "第1形態では数えない")
	ph.on_total(4000.0)
	ph.tick(9.0, 4000.0)
	var ok := ph.awake_steps(4000.0 + 2249.0, 0.25) == 0 and ph.awake_steps(4000.0 + 2250.0, 0.25) == 1
	ok = ok and ph.awake_steps(4000.0 + 4500.0, 0.25) == 2 and ph.awake_steps(4000.0 + 6750.0, 0.25) == 3 and ph.awake_steps(4000.0 + 8999.0, 0.25) == 3
	check(ok, "覚醒の体力が 2250 減るごとに1つ（残り75%・50%・25%の3回。倒した所は数えない）")

	# AI：必ず次に出す。必殺技の待ち時間も無視する
	var acfg := Attacks.load_config()
	var ai := BossAI.new()
	ai.reset(acfg, 1.0)
	ai.on_awake(0.0)
	for k0 in acfg["kinds"]:
		ai.used["awake"][k0] = true  # 「まだの攻撃を先に」（版67）は、ここでは関係しないので、全部出したことにする
	ai.last_ult_end = 20.0  # 必殺技を使ったばかり（ふつうなら24秒は出ない）
	ai.update(21.0, "awake", func(_n: int) -> float: return 5.0)
	ai.request(Attacks.BOTTLE_RIDE)
	check(str(ai.next_attack().get("kind", "")) == Attacks.BOTTLE_RIDE or ai.forced.any(func(f): return str(f["kind"]) == Attacks.BOTTLE_RIDE), "いまの攻撃の次に、巨大酒瓶ライドが入る（必殺技の待ち時間があっても）")
	var t := 21.0
	var saw := false
	while t < 40.0 and not saw:
		t += 0.1
		ai.update(t, "awake", func(_n: int) -> float: return 5.0)
		saw = str(ai.current().get("kind", "")) == Attacks.BOTTLE_RIDE
	check(saw, "巨大酒瓶ライドが始まる")
	ai.request(Attacks.BOTTLE_RIDE)
	check(ai.forced.is_empty() and str(ai.next_attack().get("kind", "")) != Attacks.BOTTLE_RIDE, "ライドの最中に区切りが来ても、続けてもう1回は出さない")
	# ランダムでも出る（区切りとは別）
	var ai2 := BossAI.new()
	ai2.reset(acfg, 7.0)
	ai2.on_awake(0.0)
	check(ai2.candidate_weights(30.0, "awake", 5.0).has(Attacks.BOTTLE_RIDE), "区切り以外でも、ふつうの必殺技としてランダムに選ばれる")

	# 戦いの画面で：覚醒の体力を4分の1ずつ減らすと、そのたびにライドが入る
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	var tt := 0.5
	now[0] = s.round_start_ms + tt * 1000.0
	s.my_hits = float(s.phase.max1)
	s._recompute_boss_hp()
	# 覚醒の演出を進める
	while not s.phase.is_awake() and tt < 10.0:
		tt += 0.05
		now[0] = s.round_start_ms + tt * 1000.0
		s.combat_update(0.05)
		s._pose_boss(0.05)
	check(s.phase.is_awake() and is_equal_approx(s.phase.max_hp(), 11250.0), "画面：覚醒すると、体力の最大は 11250")
	var rides := 0
	var was_riding := false
	for q in 3:
		s.my_hits = float(s.phase.max1) + float(s.phase.max2) * 0.25 * float(q + 1) + 1.0
		s._recompute_boss_hp()
		var started := false
		var limit := tt + 40.0
		while tt < limit:
			tt += 0.05
			now[0] = s.round_start_ms + tt * 1000.0
			s.player.position = Vector3(0, s.ground_y, 40)
			s.my_hp = 150.0
			s.downed = false
			s.combat_update(0.05)
			s._pose_boss(0.05)  # 起き上がりの動き（よろけの終わり）は、ボスの動きの更新で進む
			var riding := str(s.current_attack.get("kind", "")) == Attacks.BOTTLE_RIDE
			if riding and not was_riding:
				started = true
			if started and not riding:
				was_riding = false
				# 版68：4分の1と4分の3では、ライドのあとに酒の大雨も入るので、それも終わるまで進める
				while tt < limit and (str(s.current_attack.get("kind", "")) == Attacks.FLYER_STORM or s.ai.forced.size() > 0 or str(s.ai.next_attack().get("kind", "")) == Attacks.FLYER_STORM):
					tt += 0.05
					now[0] = s.round_start_ms + tt * 1000.0
					s.my_hp = 150.0
					s.downed = false
					s.combat_update(0.05)
					s._pose_boss(0.05)
				break
			was_riding = riding
		if started:
			rides += 1
	check(rides == 3 and s.awake_rides_done == 3, "画面：残り75%%・50%%・25%%で、毎回巨大酒瓶ライドが入る（%d 回、記録 %d）" % [rides, s.awake_rides_done])
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
