extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_sub_enemy.gd
## サブ敵の体力・復活（crowd_state.gd）と、戦いの中の当たり判定を確かめる。

const CrowdState := preload("res://scripts/combat/crowd_state.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var st := CrowdState.new()
	st.reset(3, 20.0)
	check(st.count() == 3 and st.is_alive(0) and not st.is_alive(5) and not st.is_alive(-1), "最初は全員生きている。範囲の外は生きていない")
	check(not st.hit(0, 5.0, 1.0, 8.0) and st.hp[0] == 15.0, "ダメージで体力が減る（倒れない）")
	check(st.hit(0, 99.0, 2.0, 8.0) and not st.is_alive(0) and st.kills == 1, "体力が0で倒れる。倒した数が増える")
	check(not st.hit(0, 5.0, 3.0, 8.0) and st.kills == 1, "倒れた敵には当たらない")
	st.refresh(9.0)
	check(not st.is_alive(0), "復活の時間（倒してから8秒）の前は、まだ倒れている")
	st.refresh(10.0)
	check(st.is_alive(0) and st.hp[0] == 20.0, "時間が来ると、体力満タンで復活する")
	var pos := PackedVector3Array([Vector3(0, 0.7, 0), Vector3(1, 0.7, 0), Vector3(10, 0.7, 0)])
	check(st.nearest_alive(pos, Vector3(0.9, 0, 0), 2.0) == 1, "届く距離の、いちばん近い敵を選ぶ")
	check(st.nearest_alive(pos, Vector3(5, 0, 5), 2.0) == -1, "遠ければ、だれにも当たらない")
	st.hit(1, 99.0, 0.0, 8.0)
	check(st.nearest_alive(pos, Vector3(0.9, 0, 0), 2.0) == 0, "倒れた敵は選ばない")
	st.reset(0, 20.0)
	check(st.nearest_alive(pos, Vector3.ZERO, 5.0) == -1, "数が0でも壊れない")

	var packed := load(SCENE) as PackedScene
	var s: Node = packed.instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [1000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.config["sub_enemy_enabled"] = true  # 本番では一旦消している（版59）。ここでは出して仕組みを確かめる
	s.start_round()
	s.sub_crowd.update_at(0.0, s.crowd_state)
	var target: Vector3 = s.sub_crowd.last_positions[0]
	s.player.position = Vector3(target.x, s.ground_y, target.z)
	var hp0: float = s.boss_hp
	check(s.attack(), "サブ敵のそばで、こうげきが当たる")
	check(is_equal_approx(s.crowd_state.hp[0], maxf(0.0, float(s.config["sub_enemy_hp"]) - s.role_value("attack_power"))), "サブ敵の体力が、攻撃力のぶん減る")
	check(s.boss_hp == hp0 and s.my_hits == 0.0, "サブ敵へのダメージは、ボスの体力にも合計ダメージにも数えない")
	s.actions.reset()
	s.attack()
	s.actions.reset()
	s.attack()
	check(not s.crowd_state.is_alive(0) and s.crowd_state.kills == 1, "何回か当てると倒れる")
	s.player.position = Vector3(0.0, s.ground_y, 14.0)
	s.actions.reset()
	var alive_hp: float = s.crowd_state.hp[1]
	s.attack()
	check(s.boss_hp == hp0 and is_equal_approx(s.crowd_state.hp[1], alive_hp), "何もないところでは、振っても当たらない")
	# ふれるとダメージ
	var hp_before: float = s.my_hp
	s.crowd_state.reset(int(s.config["sub_enemy_count"]), float(s.config["sub_enemy_hp"]))
	s.sub_crowd.update_at(0.0, s.crowd_state)
	target = s.sub_crowd.last_positions[1]
	s.player.position = Vector3(target.x, s.ground_y, target.z)
	s._touch_update(0.016)
	check(is_equal_approx(s.my_hp, hp_before - float(s.config["sub_enemy_touch_power"])), "サブ敵にふれると、ダメージを受ける")
	s._touch_update(0.016)
	check(is_equal_approx(s.my_hp, hp_before - float(s.config["sub_enemy_touch_power"])), "すぐにはもう一度受けない（間隔がある）")
	s._touch_update(float(s.config["sub_enemy_touch_interval_sec"]))
	check(s.my_hp < hp_before - float(s.config["sub_enemy_touch_power"]), "間隔がすぎると、また受ける")
	var hp_air: float = s.my_hp
	s.touch_timer = 0.0
	s.player.position.y = s.ground_y + float(s.config["dodge_height"]) + 1.0
	s._touch_update(0.016)
	check(s.my_hp == hp_air, "ジャンプ中は、ふれてもダメージを受けない")
	check(s.camera.environment != null and s.camera.environment.ambient_light_energy > 0.0, "光が当たらない面が真っ黒にならない（環境光がある）")
	# 版59：データで消したときは、1体も出ず、見た目も隠れる
	s.config["sub_enemy_enabled"] = false
	s._begin_round(now[0])
	check(s.crowd_state.count() == 0 and not s.sub_crowd.visible, "サブ敵を消す設定なら、1体も出ない")
	s.player.position = Vector3(target.x, s.ground_y, target.z)
	var hp_off: float = s.my_hp
	s.touch_timer = 0.0
	s._touch_update(0.016)
	check(s.my_hp == hp_off, "サブ敵を消す設定なら、ふれてもダメージを受けない")
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	check(on_disk is Dictionary and on_disk.get("sub_enemy_enabled", true) == false, "いまのデータでは、サブ敵は消してある")
	root.remove_child(s)
	s.free()
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
