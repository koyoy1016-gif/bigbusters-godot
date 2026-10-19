extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v66.gd
## 版66の変更：剣士の体力1.75倍・覚醒のボスの体力9000（平常4000）・回転バット移動の削除・巨大酒瓶ライドの瓶18本。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	# ---- 1. 剣士の体力：150 の1.75倍。ほかの味方は変えない ----
	var ccfg := CharacterData.load_config()
	var hero := CharacterData.find(ccfg, "hero_swordsman")
	check(is_equal_approx(float(hero["stats"]["hp"]), 150.0 * 1.75), "剣士の体力は 150 の1.75倍（%.1f）" % float(hero["stats"]["hp"]))
	var others := {"sprinter": 105.0, "brawler": 135.0, "gunner": 105.0, "bomber": 112.5, "mage": 97.5, "guardian": 240.0, "summoner": 120.0, "healer": 127.5}
	var same := true
	for id in others:
		same = same and is_equal_approx(float(CharacterData.find(ccfg, id)["stats"]["hp"]), float(others[id]))
	check(same, "ほかの味方8人の体力は変わらない")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var roles: Dictionary = cfg["roles"]
	check(is_equal_approx(float(roles["p1"]["hp"]), 262.5) and is_equal_approx(float(roles["p2"]["hp"]), 240.0) and is_equal_approx(float(roles["p3"]["hp"]), 105.0) and is_equal_approx(float(roles["p4"]["hp"]), 135.0), "キャラを選ばないときの剣士（ファイター）も 262.5。ほかの役は変わらない")

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [4000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	check(is_equal_approx(s.my_hp, 262.5) and is_equal_approx(s.role_value("hp"), 262.5), "画面：剣士は体力 262.5 で始まる")
	s.selected_character = "hero_swordsman"
	check(is_equal_approx(s.role_value("hp"), 262.5), "画面：剣士を選んだときも 262.5")
	s.selected_character = ""

	# ---- 2. ボスの体力：平常 4000、覚醒 9000 ----
	check(is_equal_approx(float(cfg["boss_hp"]), 4000.0) and is_equal_approx(float(cfg["boss_hp_awake"]), 9000.0), "データ：平常 4000、覚醒 9000")
	check(is_equal_approx(s.phase.max_hp(), 4000.0), "画面：平常の体力の最大は 4000")
	var t := 0.5
	now[0] = s.round_start_ms + t * 1000.0
	s.my_hits = 4000.0
	s._recompute_boss_hp()
	while not s.phase.is_awake() and t < 10.0:
		t += 0.05
		now[0] = s.round_start_ms + t * 1000.0
		s.combat_update(0.05)
		s._pose_boss(0.05)
	check(s.phase.is_awake() and is_equal_approx(s.phase.max_hp(), 9000.0) and is_equal_approx(s.boss_hp, 9000.0), "画面：覚醒すると、体力は満タンの 9000")
	s.my_hits = 4000.0 + 4500.0
	s._recompute_boss_hp()
	check(is_equal_approx(s.boss_hp, 4500.0) and is_equal_approx(s.boss_hp_ratio(), 0.5), "画面：覚醒の体力ゲージは 9000 を満タンとして減る（4500 で半分）")
	check(s.awake_rides_done == 2, "画面：必ず入るライドは、覚醒の体力 2250 ごと（4500 減って2回）")
	s.my_hits = 4000.0 + 8999.0
	s._recompute_boss_hp()
	check(not s.won and s.boss_hp > 0.0, "画面：覚醒の体力が残っていれば、まだ勝ちではない")
	s.my_hits = 4000.0 + 9000.0
	s._recompute_boss_hp()
	check(s.won, "画面：覚醒の体力 9000 を削りきると勝ち")
	s._exit_tree()

	# ---- 3. 回転バット移動：どちらの形態でも選ばれない（データからも削除） ----
	var acfg := Attacks.load_config()
	check(not (acfg["kinds"] as Dictionary).has("spin_bat"), "回転バット移動は、攻撃の一覧にない")
	check((acfg["kinds"] as Dictionary).has("bat_spin") and (acfg["kinds"] as Dictionary).has("spin_charge"), "回転斬り・回転突進は残っている")
	var seen := []
	for seed in [3.0, 99.0, 4242.0, 7.7e6]:
		for form in ["normal", "awake"]:
			var ai := BossAI.new()
			ai.reset(acfg, seed)
			if form == "awake":
				ai.on_awake(0.0)
			var tt := 0.0
			for i in 3000:
				tt += 0.1
				ai.update(tt, form, func(_n: int) -> float: return 6.0)
				var k := str(ai.current().get("kind", ""))
				if k == "spin_bat" and not seen.has(k):
					seen.append(k)
	check(seen.is_empty(), "平常・覚醒のどちらでも、回転バット移動は1回も選ばれない（4つの乱数×300秒）")

	# ---- 4. 巨大酒瓶ライド：突入ごとに18本。突入の回数・長さは変わらない ----
	var rk: Dictionary = acfg["kinds"]["bottle_ride"]
	check(int(rk["bottles_per_pass"]) == 18, "突入1回に酒瓶18本")
	var rk12 := rk.duplicate()
	rk12["bottles_per_pass"] = 12
	var all18 := true
	var same_len := true
	for n in [1, 4, 9, 22]:
		var ctx := {"n": n, "round_start_ms": 123.0, "bounds": 15.0, "boss": Vector2.ZERO, "area": 13.0}
		for ps in Attacks.ride_plan(rk, ctx):
			all18 = all18 and Attacks.ride_throws(ps, rk, ctx).size() == 18
		same_len = same_len and Attacks.ride_plan(rk, ctx).size() == Attacks.ride_plan(rk12, ctx).size() and is_equal_approx(Attacks.ride_total_for(rk, ctx), Attacks.ride_total_for(rk12, ctx))
	check(all18, "どの突入でも、酒瓶を18本投げる")
	check(same_len, "瓶を18本にしても、突入の回数と全体の長さは変わらない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
