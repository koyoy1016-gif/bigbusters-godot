extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_knockback.gd
## ボスの攻撃に当たったときの、ふっ飛び・転倒・起き上がり（連続で当たって動けなくならない）

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	# ふっ飛ぶ向き
	var hs := {"x": 0.0, "z": 0.0, "kb_mode": "radial"}
	check(Attacks.knock_dir(hs, 3.0, 0.0).is_equal_approx(Vector2(1, 0)), "輪の攻撃は、中心から外へ")
	var hf := {"x": 0.0, "z": 0.0, "kb_mode": "forward", "kb_yaw": 0.0}
	check(Attacks.knock_dir(hf, 3.0, 5.0).is_equal_approx(Vector2(0, 1)), "前へのたたきつけは、ボスの前の向きへ")
	var ht := {"x": 0.0, "z": 0.0, "kb_mode": "travel", "kb_x": -1.0, "kb_z": 0.0}
	check(Attacks.knock_dir(ht, 3.0, 5.0).is_equal_approx(Vector2(-1, 0)), "走ってくる物は、進む向きへ")
	var sw := Attacks.knock_dir({"x": 0.0, "z": 0.0, "kb_mode": "sweep"}, 0.0, 5.0)
	check(sw.x > 0.3 and sw.y > 0.0, "横振り（右から左）は、左へ・少し外へ")

	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.ai_enabled = false
	s.start_round()
	now[0] += 10000.0
	var a: Dictionary = s.force_attack("bat_h")
	var k: Dictionary = s.attacks_cfg["kinds"]["bat_h"]
	# 扇の中（ボスの前）に立つ
	var hit_t := float(a["start"]) + float(k["windup_sec"]) + float(k["swing_sec"]) * 0.9
	var hp0: float = s.my_hp
	var t := float(a["start"])
	var placed := false
	var p0 := Vector3.ZERO
	while t < hit_t:
		t += 0.02
		now[0] = s.round_start_ms + t * 1000.0
		if not placed and t > float(a["start"]) + 0.4:
			var lk: Dictionary = s.motion.lock_of(int(a["n"]))
			var f: Vector2 = Attacks.fwd_of(float(lk["yaw"]))
			var spot: Vector2 = (lk["pos"] as Vector2) + f * 4.0
			s.player.position = Vector3(spot.x, s.ground_y, spot.y)
			p0 = s.player.position
			placed = true
		s.combat_update(0.02)
		if s.actions.busy():
			break
	check(s.my_hp < hp0, "横振りに当たると、ダメージ")
	check(s.actions.active == str(k["knockback"]), "横振りに当たると、ふっ飛ぶ（%s）" % s.actions.active)
	check(s.kb_guard_left > 0.0, "ふっ飛んでいる間は、ボスの攻撃が当たらない")
	var hp1: float = s.my_hp
	var max_h := 0.0
	var guard := 0
	while s.actions.busy() and guard < 400:
		t += 0.02
		now[0] = s.round_start_ms + t * 1000.0
		s._process(0.02)
		max_h = maxf(max_h, s.player.position.y - s.ground_y)
		guard += 1
	check(max_h > 0.5, "宙に浮く（高さ %.1f）" % max_h)
	var moved := Vector2(s.player.position.x - p0.x, s.player.position.z - p0.z).length()
	check(moved > 3.0, "ボスから離れる方へ、ふっ飛ぶ（%.1f m）" % moved)
	check(not s.actions.busy() and absf(s.player.position.y - s.ground_y) < 0.01, "転んだあと、起き上がって地面に立つ")
	check(s.perform("normal") or s.actions.busy(), "起き上がったら、また攻撃できる")
	s.actions.reset()
	check(absf(s.player.position.x) <= float(s.config["bounds"]) + 0.01 and absf(s.player.position.z) <= float(s.config["bounds"]) + 0.01, "ふっ飛んでも、ステージの外へ出ない（壁にうまらない）")
	# 端の近くでふっ飛んでも、外へ出ない
	s.kb_guard_left = 0.0
	s.player.position = Vector3(float(s.config["bounds"]) - 0.5, s.ground_y, 0.0)
	s._knockback("kb_launch", Vector2(1, 0))
	for i in 200:
		s._actions_update(0.02)
	check(s.player.position.x <= float(s.config["bounds"]) + 0.01, "端でふっ飛んでも、外へ出ない")
	s._exit_tree()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
