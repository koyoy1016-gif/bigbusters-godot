extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_boss_ai.gd
## ボスの攻撃の選び方（重み付きランダム、scripts/combat/boss_ai.gd）

const BossAI := preload("res://scripts/combat/boss_ai.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


## 戦いを seed で始めて、form の攻撃を count 回えらぶ。距離は dist（いつも同じ）。返すのは攻撃の種類の並び
func run(cfg: Dictionary, seed: float, form: String, count: int, dist: float = 5.0) -> Array:
	var ai := BossAI.new()
	ai.reset(cfg, seed)
	if form == "awake":
		ai.on_awake(0.0)
	var t := 0.0
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < 100000:
		ai.update(t, form, func(_n: int) -> float: return dist)
		var c: Dictionary = ai.current()
		if not c.is_empty() and (out.is_empty() or int(out[out.size() - 1]["n"]) != int(c["n"])):
			out.append(c.duplicate())
		t += 0.05
		guard += 1
	return out


func _initialize() -> void:
	var cfg := Attacks.load_config()
	var a := run(cfg, 1000.0, "normal", 40)
	var b := run(cfg, 2000.0, "normal", 40)
	check(a.size() == 40 and b.size() == 40, "攻撃が出つづける（止まらない）")
	var order_a := a.map(func(x: Dictionary) -> String: return str(x["kind"]))
	var order_b := b.map(func(x: Dictionary) -> String: return str(x["kind"]))
	check(order_a != order_b, "戦いが変われば、攻撃の順番も変わる")
	check(order_a == run(cfg, 1000.0, "normal", 40).map(func(x: Dictionary) -> String: return str(x["kind"])), "同じ戦い（同じ乱数の種）なら、同じ順番")
	var seen := {}
	var repeats := 0
	for i in a.size():
		seen[str(a[i]["kind"])] = true
		if i > 0:
			if float(a[i]["start"]) < float(a[i - 1]["end"]) - 0.001:
				check(false, "攻撃が重ならない（%d）" % i)
			if str(a[i]["kind"]) == str(a[i - 1]["kind"]):
				repeats += 1
	check(seen.size() >= 5, "いろいろな攻撃が出る（%d種類）" % seen.size())
	check(not seen.has("sake_drop") and not seen.has("fire_fest") and not seen.has("flyer_storm") and not seen.has("hand_sweep"), "平常時は、覚醒の攻撃・必殺技を出さない")
	check(repeats < 12, "同じ攻撃が続きすぎない（%d回）" % repeats)
	# たくさんの種で、強い攻撃が3回続くことは少ない
	var streak3 := 0
	var total := 0
	var counts := {}
	for sd in range(20):
		var seq := run(cfg, 5000.0 + sd * 777.0, "normal", 30)
		for i in seq.size():
			total += 1
			counts[str(seq[i]["kind"])] = int(counts.get(str(seq[i]["kind"]), 0)) + 1
			if i >= 2:
				var st := true
				for j in 3:
					st = st and bool(((cfg["kinds"][str(seq[i - j]["kind"])] as Dictionary).get("ai", {}) as Dictionary).get("strong", false))
				if st:
					streak3 += 1
	check(float(streak3) / float(total) < 0.05, "強い攻撃が3回続くのは、まれ（%d / %d）" % [streak3, total])
	print("平常時の出かた（20戦×30回）：", counts)
	# 距離：遠いと、遠くまで届く攻撃が増える
	var near := {}
	var far := {}
	for sd in range(15):
		for x in run(cfg, 9000.0 + sd * 31.0, "normal", 20, 3.0):
			near[str(x["kind"])] = int(near.get(str(x["kind"]), 0)) + 1
		for x in run(cfg, 9000.0 + sd * 31.0, "normal", 20, 13.0):
			far[str(x["kind"])] = int(far.get(str(x["kind"]), 0)) + 1
	check(int(far.get("walk_swing", 0)) > int(near.get("walk_swing", 0)) and int(near.get("grab", 0)) > int(far.get("grab", 0)), "距離で、選ばれやすい攻撃が変わる（遠い：歩き振り、近い：つかみ）")
	# 覚醒：必殺技は、覚醒してしばらくたってから、間をあけて
	var aw := run(cfg, 4242.0, "awake", 60)
	var g: Dictionary = cfg["ai"]
	var last_ult := -999.0
	var ult_ok := true
	var ults := 0
	var aw_seen := {}
	for x in aw:
		aw_seen[str(x["kind"])] = true
		if bool(((cfg["kinds"][str(x["kind"])] as Dictionary).get("ai", {}) as Dictionary).get("ultimate", false)):
			ults += 1
			if float(x["start"]) < float(g["ultimate_first_sec"]) or float(x["start"]) - last_ult < float(g["ultimate_cooldown_sec"]):
				ult_ok = false
			last_ult = float(x["end"])
	check(ults >= 1 and ult_ok, "覚醒の必殺技は、覚醒してしばらくしてから・間をあけて出る（%d回）" % ults)
	check(aw_seen.has("sake_drop") and not aw_seen.has("bat_spin") and not aw_seen.has("sake_rain"), "覚醒では、覚醒用の攻撃が出る（酒の雨は使わない）")
	# 使える攻撃がないときは、代わりの攻撃
	check(BossAI.pick({}, 0.5) == "", "候補がなければ空")
	var ai := BossAI.new()
	var empty_cfg := cfg.duplicate(true)
	for k in empty_cfg["kinds"]:
		(empty_cfg["kinds"][k] as Dictionary)["ai"] = {}
	ai.reset(empty_cfg, 1.0)
	var c := ai.choose(1.0, "normal", func(_n: int) -> float: return 5.0)
	check(str(c["kind"]) == str(cfg["ai"]["fallback"]["normal"]), "使える攻撃がないときは、代わりの攻撃（止まらない）")
	# 倒れたとき：いまの攻撃をやめる
	var ai2 := BossAI.new()
	ai2.reset(cfg, 3.0)
	for i in 100:
		ai2.update(float(i) * 0.05, "normal", func(_n: int) -> float: return 5.0)
	ai2.interrupt(5.0, 999.0)
	ai2.update(5.1, "normal", func(_n: int) -> float: return 5.0)
	check(ai2.current().is_empty(), "倒れたら、攻撃しない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
