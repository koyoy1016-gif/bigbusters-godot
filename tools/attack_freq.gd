extends SceneTree
## ボスの攻撃が、実際の戦いでどのくらいの割合で出るかを数える（攻撃パターンのまとめ用）。
## 戦いを画面なしで回し、ボスが始めた攻撃を、形態（平常・覚醒）ごとに数える。
## 自分はボスのそばでこうげきし続ける。数を集めるため、自分とAIの体力は減っても毎コマ戻す（倒れない）。
## 使い方: godot --headless --path . --script res://tools/attack_freq.gd -- 回数
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 6
	var packed := load(SCENE) as PackedScene
	var counts := {"normal": {}, "awake": {}}
	var forms_time := {"normal": 0.0, "awake": 0.0}
	var busy := {"normal": {}, "awake": {}}  ## 攻撃ごとの、その攻撃をしていた秒
	var forced_rides := 0
	var fight_times: Array = []
	var awake_times: Array = []
	for r in runs:
		var s: Node = packed.instantiate()
		s.ai_enabled = true
		root.add_child(s)
		if s.get_node_or_null("Boss") == null:
			s._ready()
		var now := [7000000.0 + r * 137000.0]
		s.clock_ms = func() -> float: return now[0]
		s.sfx = null
		s.start_round()
		var dt := 0.05
		var t := 0.0
		var last_n := -1
		var awake_at := -1.0
		while s.round_active() and t < 400.0:
			now[0] += dt * 1000.0
			t += dt
			var bp: Vector3 = s.boss.position
			s.player.position = Vector3(bp.x, s.ground_y, bp.z + float(s.config["boss_size"]) * 0.5 + 1.2)
			s.my_hp = 150.0
			s.downed = false
			for k in s.ai_allies:
				s.ai_allies[k]["hp"] = float(s.ai_allies[k]["max_hp"])
				s.ai_allies[k]["downed"] = false
			for id in ["main", "sub", "normal"]:
				if s.perform(id):
					break
			s._actions_update(dt)
			s.combat_update(dt)
			s._pose_boss(dt)
			var form := "awake" if s.phase.is_awake() else "normal"
			if s.phase.is_awake() and awake_at < 0.0:
				awake_at = t
			if s.phase.phase == "normal" or s.phase.is_awake():
				forms_time[form] += dt
			var cur: Dictionary = s.ai.current()
			if not cur.is_empty():
				busy[form][str(cur["kind"])] = float(busy[form].get(str(cur["kind"]), 0.0)) + dt
			if not cur.is_empty() and int(cur["n"]) != last_n:
				last_n = int(cur["n"])
				var kind := str(cur["kind"])
				counts[form][kind] = int(counts[form].get(kind, 0)) + 1
		fight_times.append(t)
		awake_times.append(t - awake_at if awake_at >= 0.0 else 0.0)
		forced_rides += int(s.awake_rides_done)
		# この戦いで、形態ごとに出なかった攻撃（版67：全部の攻撃を1回は出す、の確認）
		for f in ["normal", "awake"]:
			var miss: Array = s.ai.unused_in(f)
			print("MISS %d %s：%s" % [r, f, str(miss) if not miss.is_empty() else "なし（全部出た）"])
		print("RUN %d：%.0f 秒（覚醒 %.0f 秒）%s" % [r, t, t - awake_at if awake_at >= 0.0 else 0.0, "勝ち" if s.won else "終わらず"])
		root.remove_child(s)
		s.free()
	for form in ["normal", "awake"]:
		var total := 0
		for k in counts[form]:
			total += int(counts[form][k])
		print("FORM %s：攻撃 %d 回、%.0f 秒（1回あたり %.2f 秒）" % [form, total, forms_time[form], forms_time[form] / maxf(total, 1)])
		var keys: Array = counts[form].keys()
		keys.sort_custom(func(a, b): return int(counts[form][a]) > int(counts[form][b]))
		for k in keys:
			print("FREQ %s %s %d %.1f%% 時間 %.0f秒 %.0f%%" % [form, k, int(counts[form][k]), 100.0 * float(counts[form][k]) / maxf(total, 1), float(busy[form].get(k, 0.0)), 100.0 * float(busy[form].get(k, 0.0)) / maxf(forms_time[form], 0.01)])
	print("RIDES_FORCED %d（%d 戦）" % [forced_rides, runs])
	quit()
