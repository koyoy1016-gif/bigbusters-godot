extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_grab_escape.gd
## つかまれたら動けない／「にげる」の連打で逃げる／逃げられないと投げられて、転んで、起き上がる。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0
var now := [1000000.0]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func make() -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.sub_crowd.update_at(0.0, s.crowd_state)
	return s


func _initialize() -> void:
	var SCREEN := Vector2(648, 1152)
	var s := make()
	var k: Dictionary = s.attacks_cfg["kinds"]["grab"]
	var bz := float(s.config["boss_position"][1])
	var need := int(k["mash_needed"])
	check(need == 7, "逃げるのに必要な連打は、7回（版69。いま %d）" % need)

	# つかまれる
	s.player.position = Vector3(0.0, s.ground_y, bz + 6.0)
	s._start_hold(s._my_slot(), Vector2(0.0, bz + 6.0))
	check(s._me_held(), "つかまれた")
	check(not s.perform("main") and not s.perform("sub") and not s.attack(), "つかまれている間は、攻撃できない")
	s.stick_vec = Vector2(1.0, 0.0)
	var x0: float = s.player.position.x
	s._grab_update(0.016)
	s._process(0.016)
	check(absf(s.player.position.x - x0) < 0.5 or s._me_held(), "つかまれている間は、スティックで動けない")
	s.stick_vec = Vector2.ZERO

	# 逃げる：「にげる」（通常ボタンの位置）を連打
	var normal_at: Vector2 = s._button_center("normal", SCREEN)
	var hp0: float = s.my_hp
	for i in need - 1:
		s.handle_press(1, normal_at, SCREEN)
		s.handle_release(1)
	check(s.escape_progress() > 0.8 and s._me_held(), "連打の途中では、まだ逃げられない")
	var sub_at: Vector2 = s._button_center("sub", SCREEN)
	s.handle_press(2, sub_at, SCREEN)
	check(s.escape_progress() < 1.0 and s._me_held() and not s.actions.busy(), "サブのボタンでは、逃げられないし、攻撃も出ない")
	s.handle_press(1, normal_at, SCREEN)
	s._grab_update(0.016)
	check(not s._me_held() and not s.actions.busy(), "決めた回数の連打で、逃げられる（投げられない）")
	check(is_equal_approx(s.player.position.y, s.ground_y) or s.player.position.y < s.ground_y + 0.1, "逃げたら、地面にもどる")
	check(s.my_hp >= hp0 - 0.001 or s.my_hp > hp0 - float(k["squeeze_power"]) * 2.0, "逃げれば、投げのダメージは受けない")

	# 逃げられない：時間切れで、投げられる
	s.actions.reset()
	s.stun_left = 0.0
	s.my_hp = s.role_value("hp")
	s.player.position = Vector3(0.0, s.ground_y, bz + 6.0)
	s._start_hold(s._my_slot(), Vector2(0.0, bz + 6.0))
	var hold: float = s.grab_state["hold"]
	check(hold >= float(k["hold_min_sec"]) - 0.001 and hold <= float(k["hold_max_sec"]) + 0.001, "つかむ時間は、%.1f〜%.1f秒の間（いま %.2f秒）" % [float(k["hold_min_sec"]), float(k["hold_max_sec"]), hold])
	s.grab_state["t"] = hold - 0.05
	s._grab_update(0.016)
	check(s._me_held(), "つかむ時間の終わりまでは、まだ持ち上げられている")
	s.grab_state["t"] = hold + 0.1
	s._grab_update(0.016)
	check(s._me_held() and str(s.grab_state["phase"]) == "throw", "逃げられないと、ボスが投げる動きに入る（まだ手の中）")
	s._mash_escape()
	for i in need:
		s._mash_escape()
	s._grab_update(0.016)
	check(s._me_held() or s.actions.active == "thrown", "投げる動きに入ったら、連打では逃げられない")
	var guard2 := 0
	while s._me_held() and guard2 < 100:
		s._grab_update(0.016)
		guard2 += 1
	check(guard2 * 0.016 >= float(k["release_sec"]) - 0.1, "手をはなすのは、投げる動きの途中（%.2f秒後）" % (guard2 * 0.016))
	check(not s._me_held() and s.actions.active == "thrown", "逃げられないと、投げられる")
	check(s.player.position.y > s.ground_y + 2.0 or s.actions.height > 2.0, "投げられた直後は、高い所にいる")
	var hp1: float = s.my_hp
	var z0: float = s.player.position.z
	var seen_lying := false
	var guard := 0
	while s.actions.busy() and guard < 400:
		s._process(0.016)
		now[0] += 16.0
		if s.actions.t > 1.0 and s.actions.t < 1.6:
			seen_lying = true
			var before: float = s.my_hp
			s._take_damage(50.0)
			check(is_equal_approx(s.my_hp, before), "転んでいる間は、ダメージを受けない") if guard % 40 == 0 else null
		guard += 1
	check(seen_lying, "転んで、しばらく倒れている")
	check(not s.actions.busy() and is_equal_approx(s.player.position.y, s.ground_y), "起き上がって、地面で動ける")
	check(s.my_hp < hp1, "着地で、ダメージを受ける（%.1f → %.1f）" % [hp1, s.my_hp])
	check(s.player.position.z > z0 + 3.0, "ボスから離れた所に、投げ出される（z %.1f → %.1f）" % [z0, s.player.position.z])
	check(s.player.position.z > z0 + 10.0, "遠くへ投げられる（10m以上）")
	check(s.perform("normal"), "起き上がったあとは、また戦える")

	# ボタンの見た目の元：つかまれ中は、にげる
	s.actions.reset()
	s.stun_left = 0.0
	s._start_hold(s._my_slot(), Vector2(0.0, bz + 6.0))
	check(s.escape_progress() == 0.0, "つかまれた直後の、にげる進みは0")
	s._release_hold(true)

	root.remove_child(s)
	s.free()
	print("")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)

