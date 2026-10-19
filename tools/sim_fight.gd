extends SceneTree
## 戦いを、画面なしで何回か自動で回して、かかった時間・勝ち負け・体力の減りを出す（バランス調整用）。
## 自分は「ボスのそばに立ってこうげきし続ける（よけない）」、味方はAI3人。
## 使い方: godot --headless --path . --script res://tools/sim_fight.gd -- 回数 キャラID
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 5
	var char_id := str(args[1]) if args.size() > 1 else "hero_swordsman"
	var packed := load(SCENE) as PackedScene
	var wins := 0
	var times: Array = []
	for r in runs:
		var s: Node = packed.instantiate()
		s.ai_enabled = true
		s.selected_character = char_id
		root.add_child(s)
		if s.get_node_or_null("Boss") == null:
			s._ready()
		var now := [5000000.0 + r * 100000.0]
		s.clock_ms = func() -> float: return now[0]
		s.start_round()
		var dt := 0.05
		var t := 0.0
		while s.round_active() and t < 300.0:
			now[0] += dt * 1000.0
			t += dt
			var bp: Vector3 = s.boss.position
			if not s.downed:
				s.player.position = Vector3(bp.x, s.ground_y, bp.z + float(s.config["boss_size"]) * 0.5 + 1.2)
				for id in ["main", "sub", "normal"]:
					if s.perform(id):
						break
				s._actions_update(dt)
			s.combat_update(dt)
		var won: bool = s.won
		if won:
			wins += 1
			times.append(t)
		var hps: Array = []
		for k in s.ai_allies:
			hps.append(int(s.ai_allies[k]["hp"]))
		print("run %d: %s %.0f秒  自分のHP %d  AIのHP %s  AIの合計ダメージ %d" % [r, "勝ち" if won else "負け/時間切れ", t, int(s.my_hp), str(hps), int(s._ai_hits_total())])
		root.remove_child(s)
		s.free()
	print("勝ち %d / %d" % [wins, runs])
	quit()
