extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_bottle_ride.gd
## 必殺技「巨大酒瓶ライド」：5回、ステージの外から反対の外まで横切るか（左→右、右→左…）。
## 横切る時間・切りかえの時間・ダメージが決めた範囲か。走る前に道を予告するか。最後はステージの中にもどるか。いくつかの乱数で試す。

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg := Attacks.load_config()
	check(cfg["kinds"].has("bottle_ride"), "巨大酒瓶ライドがある")
	var k: Dictionary = cfg["kinds"]["bottle_ride"]
	var bounds := 15.0
	check(float(k["power"]) >= 20.0 and float(k["power"]) <= 25.0, "ダメージは 20〜25（%s）" % k["power"])
	check(str(k["knockback"]) == "kb_launch" and str(k["kb_mode"]) == "travel", "大きくはね飛ばす（走る向き）")
	check(bool((k["ai"] as Dictionary).get("ultimate", false)) and float((k["ai"]["forms"] as Dictionary).get("normal", 0.0)) <= 0.0, "覚醒のときだけの必殺技")
	var all_ok := true
	for seed in [1.0, 777.0, 123456.0, 9.5e6, 3.3e7]:
		for n in [1, 2, 7, 30]:
			var ctx := {"boss": Vector2(2.0, -3.0), "yaw": 0.4, "target": Vector2(-1.0, 4.0), "round_start_ms": seed, "n": n, "bounds": bounds, "area": 13.0}
			var plan := Attacks.ride_plan(k, ctx)
			var ok := plan.size() == 5
			var edge := Attacks.ride_edge(k, ctx)
			# 酒瓶の後ろの端まで、ステージの外に出ているか
			ok = ok and edge - float(k["half_len"]) > bounds
			for i in plan.size():
				var ps: Dictionary = plan[i]
				ok = ok and float(ps["dir"]) == (1.0 if i % 2 == 0 else -1.0)
				var cross := float(ps["end"]) - float(ps["start"])
				ok = ok and cross >= 0.8 and cross <= 1.2
				ok = ok and float(ps["start"]) - float(ps["tele_from"]) >= 0.6
				if i > 0:
					var sw := float(ps["start"]) - float(plan[i - 1]["end"])
					ok = ok and sw >= 0.15 and sw <= 0.35
				ok = ok and absf(float(ps["z"])) <= bounds - 2.0
				# 走りはじめと終わりの位置：外から外へ
				var s0: Dictionary = Attacks.ride_at(float(ps["start"]) + 0.001, k, ctx)
				var s1: Dictionary = Attacks.ride_at(float(ps["end"]) - 0.001, k, ctx)
				ok = ok and str(s0["phase"]) == "pass" and (s0["pos"] as Vector2).x * float(ps["dir"]) < -(edge - 0.5)
				ok = ok and (s1["pos"] as Vector2).x * float(ps["dir"]) > edge - 0.5
				# 当たり：走っている間は当たる。走る前は予告だけ
				var a := {"n": n, "kind": "bottle_ride", "start": 0.0, "end": 99.0}
				var mid: Array = Attacks.hazards(a, (float(ps["start"]) + float(ps["end"])) * 0.5, cfg, ctx)
				var act := mid.filter(func(h: Dictionary) -> bool: return bool(h["active"]))
				ok = ok and act.size() == 1 and float(act[0]["kb_x"]) == float(ps["dir"])
				var pre: Array = Attacks.hazards(a, float(ps["start"]) - 0.05, cfg, ctx)
				var pre_t := pre.filter(func(h: Dictionary) -> bool: return not bool(h["active"]) and absf(float(h["z"]) - float(ps["z"])) < 0.01 and str(h["style"]) == "ride_lane")
				ok = ok and pre_t.size() == 1 and float(pre_t[0]["tele"]) > 0.8
			# 最後：ステージの中に降りて、すき。攻撃の長さに収まる
			var fin: Dictionary = Attacks.ride_at(float(k["duration"]) - 0.01, k, ctx)
			ok = ok and str(fin["phase"]) == "recover" and absf((fin["pos"] as Vector2).x) <= 13.0 and absf(float(fin["y"])) < 0.01
			var last_end := float(plan[plan.size() - 1]["end"])
			ok = ok and float(k["duration"]) - last_end >= float(k["ride_outro"]) + float(k["ride_recover"])
			if not ok:
				print("  失敗した組み合わせ：seed=%s n=%d" % [seed, n])
			all_ok = all_ok and ok
	check(all_ok, "5回、外から外へ（左右交互）・時間・予告・当たり・もどり（5つの乱数×4つの番号）")

	# 予告の帯は、走る前に出て、走っている間は消える（道の上に1つずつ）
	var ctx2 := {"boss": Vector2.ZERO, "yaw": 0.0, "target": Vector2.ZERO, "round_start_ms": 5.0, "n": 3, "bounds": bounds, "area": 13.0}
	var a2 := {"n": 3, "kind": "bottle_ride", "start": 0.0, "end": 99.0}
	var intro: Array = Attacks.hazards(a2, 0.3, cfg, ctx2)
	check(intro.is_empty(), "空へ跳んでいる間は、当たりも予告もない")
	# 道（boss_path）とボスの位置が同じ
	var path: Dictionary = Attacks.boss_path("bottle_ride", 3.0, k, ctx2)
	var r: Dictionary = Attacks.ride_at(3.0, k, ctx2)
	check(path["pos"] == r["pos"], "ボスの道と当たりの位置が同じ")

	# AI：覚醒してしばらくたてば選ばれる。第1形態では選ばれない
	var ai := BossAI.new()
	ai.reset(cfg, 1.0)
	check(not ai.candidate_weights(30.0, "normal", 5.0).has("bottle_ride"), "第1形態では出ない")
	ai.on_awake(0.0)
	check(ai.candidate_weights(30.0, "awake", 5.0).has("bottle_ride"), "覚醒したあとは出る")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
