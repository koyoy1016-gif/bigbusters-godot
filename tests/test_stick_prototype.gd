extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_stick_prototype.gd
## スティックの試作：計算（stick_math.gd）、数値（data/prototype_stick.json）、画面の動き、書き出しの設定。

const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")
const Proto := preload("res://scripts/prototype/stick_prototype.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const SCREEN := Vector2(1280, 720)

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _unique(a: Array) -> bool:
	for i in a.size():
		for j in range(i + 1, a.size()):
			if a[i] == a[j]:
				return false
	return true


func _role_names(d: Dictionary) -> String:
	var t := ""
	for k in d["roles"]:
		t += str(d["roles"][k]["name"])
	return t


func _initialize() -> void:
	# スティックの向き
	var c := Vector2(100, 100)
	check(StickMath.stick_vector(c, c, 90.0, 0.15) == Vector2.ZERO, "中心に触れている：向きは 0")
	check(StickMath.stick_vector(c + Vector2(10, 0), c, 90.0, 0.15) == Vector2.ZERO, "遊びの内側：向きは 0")
	var full := StickMath.stick_vector(c + Vector2(90, 0), c, 90.0, 0.15)
	check(is_equal_approx(full.length(), 1.0) and full.x > 0.99, "半径の端：長さ1、右向き")
	var over := StickMath.stick_vector(c + Vector2(0, 300), c, 90.0, 0.15)
	check(is_equal_approx(over.length(), 1.0) and over.y > 0.99, "半径の外：長さ1に縮む（下向き）")
	var half := StickMath.stick_vector(c + Vector2(51.75, 0), c, 90.0, 0.15)
	check(is_equal_approx(half.x, 0.5), "遊びの外側は、0から1へ直線的に増える（半分の位置で0.5）")
	check(StickMath.stick_vector(c + Vector2(50, 0), c, 0.0, 0.15) == Vector2.ZERO, "半径が0なら向きは 0")

	# 移動
	var p := StickMath.step_position(Vector3.ZERO, Vector2(1, 0), 6.0, 0.5, 15.0)
	check(is_equal_approx(p.x, 3.0) and is_equal_approx(p.z, 0.0), "右へ倒すと、Xが増える")
	var near := StickMath.step_position(Vector3.ZERO, Vector2(0, 1), 6.0, 0.5, 15.0)
	check(near.z > 0.0 and is_equal_approx(near.x, 0.0), "下へ倒すと、手前（+Z）へ動く")
	var far := StickMath.step_position(Vector3.ZERO, Vector2(0, -1), 6.0, 0.5, 15.0)
	check(far.z < 0.0, "上へ倒すと、奥（-Z）へ動く")
	var edge := StickMath.step_position(Vector3(14.9, 0.5, 0.0), Vector2(1, 0), 6.0, 1.0, 15.0)
	check(is_equal_approx(edge.x, 15.0), "範囲の外へは出ない")
	var keep_y := StickMath.step_position(Vector3(0, 3.5, 0), Vector2(1, 1), 6.0, 0.1, 15.0)
	check(is_equal_approx(keep_y.y, 3.5), "移動では、高さ（Y）は変わらない")

	# ジャンプ
	var y := 0.5
	var vy := 8.0
	var went_up := false
	var landed := false
	for i in 120:
		var r := StickMath.jump_update(y, vy, 1.0 / 60.0, 20.0, 0.5)
		y = r.x
		vy = r.y
		if y > 0.6:
			went_up = true
		if went_up and is_equal_approx(y, 0.5):
			landed = true
			break
	check(went_up, "ジャンプで、地面から上がる")
	check(landed and is_equal_approx(vy, 0.0), "落ちると、地面に戻り、速さは0になる")
	var still := StickMath.jump_update(0.5, 0.0, 1.0 / 60.0, 20.0, 0.5)
	check(is_equal_approx(still.x, 0.5) and is_equal_approx(still.y, 0.0), "地面にいて、速さ0なら、そのまま")

	# ダメージの計算（damage.gd）
	check(Damage.damage_amount(10.0, 1.0) == 10.0, "与えるダメージ：攻撃力×倍率")
	check(Damage.damage_amount(-5.0, 1.0) == 0.0, "マイナスのダメージは0")
	check(Damage.apply_damage(20.0, 5.0) == 15.0, "体力から、ダメージを引く")
	check(Damage.apply_damage(5.0, 10.0) == 0.0, "体力は0より小さくならない")
	check(Damage.in_reach(Vector3.ZERO, Vector3(0, 0, -3), 3.5), "届く距離の内側")
	check(not Damage.in_reach(Vector3.ZERO, Vector3(0, 0, -4), 3.5), "届く距離の外側")
	check(Damage.in_reach(Vector3(0, 5, 0), Vector3(0, 0, 0), 1.0), "高さは距離に入らない（床の上の距離）")

	# 数値の設定
	var cfg := FileAccess.get_file_as_string("res://data/prototype_stick.json")
	var parsed: Variant = JSON.parse_string(cfg)
	check(parsed is Dictionary, "設定ファイルが読める")
	if parsed is Dictionary:
		var d: Dictionary = parsed
		for key in ["player_size", "move_speed", "gravity", "jump_speed", "bounds", "stick_radius_px", "stick_dead_zone", "button_radius_px"]:
			check(d.has(key) and float(d[key]) > 0.0, "数値「%s」が正の数" % key)
		check(float(d["stick_dead_zone"]) < 1.0, "遊びは1より小さい")
		check(float(d["stick_zone_max_x_frac"]) <= float(d["button_zone_min_x_frac"]), "スティックとボタンの領域が重ならない")
		var font := load(str(d["ui_font_path"])) as Font
		check(font != null, "日本語のフォントが読める")
		var text := str(d["hint"]) + str(d["button_label"]) + str(d["attack_label"]) + str(d["boss_hp_label"]) + str(d["win_text"]) + str(d["room_label"]) + str(d["room_members_prefix"]) + str(d["room_members_suffix"]) + str(d["room_connecting"]) + str(d["room_full"]) + str(d["room_reconnecting"]) + str(d["room_offline"]) + str(d["start_label"]) + str(d["restart_label"]) + str(d["lose_text"]) + str(d["down_text"]) + str(d["player_hp_label"]) + str(d["team_label"]) + str(d["room_you"]) + str(d["role_label"]) + str(d["enrage_text"]) + str(d["result_time_label"]) + str(d["result_mine_label"]) + str(d["result_team_label"]) + str(d["build_label"]) + str(d["build_id"]) + _role_names(d) + "0123456789/：（）"
		var missing := ""
		for ch in text:
			if ch != " " and font != null and not font.has_char(ch.unicode_at(0)):
				missing += ch
		check(missing == "", "表示する文字が、フォントにある（不足：%s）" % missing)

	# 画面（スティックとボタンの操作）
	var packed := load(SCENE) as PackedScene
	check(packed != null, "試作の画面が読める")
	if packed != null:
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		if scene.get_node_or_null("Player") == null:
			scene._ready()
		check(scene.get_node_or_null("Player") != null, "1人（Player）がいる")
		check(scene.get_node_or_null("Camera") != null, "カメラがある")
		var cfg_dict: Dictionary = scene.config
		var stick_at: Vector2 = Vector2(SCREEN.x * cfg_dict["stick_center_frac"][0], SCREEN.y * cfg_dict["stick_center_frac"][1])
		scene.handle_press(0, stick_at, SCREEN)
		check(scene.stick_touch == 0, "左の領域に触れると、スティックが指の番号を持つ")
		scene.handle_drag(0, stick_at + Vector2(cfg_dict["stick_radius_px"], 0.0), SCREEN)
		check(scene.stick_vec.x > 0.99, "スティックを右へ倒すと、向きが右になる")
		scene.handle_release(0)
		check(scene.stick_touch == -1 and scene.stick_vec == Vector2.ZERO, "指を離すと、スティックは戻る")

		var button_at: Vector2 = Vector2(SCREEN.x * cfg_dict["button_center_frac"][0], SCREEN.y * cfg_dict["button_center_frac"][1])
		scene.handle_press(1, button_at, SCREEN)
		check(is_equal_approx(scene.velocity_y, float(cfg_dict["jump_speed"])), "右のボタンで、ジャンプする")
		check(scene.stick_touch == -1, "右のボタンは、スティックにならない")
		scene.handle_release(1)
		scene.velocity_y = 0.0
		scene.player.position.y = scene.ground_y + 2.0
		scene.handle_press(2, button_at, SCREEN)
		check(scene.velocity_y == 0.0, "空中では、ボタンを押しても跳ばない")
		scene.handle_release(2)
		root.remove_child(scene)
		scene.free()

	# ボスへの攻撃
	var packed2 := load(SCENE) as PackedScene
	check(packed2 != null, "試作の画面が読める（攻撃）")
	if packed2 != null:
		var s2: Node = packed2.instantiate()
		root.add_child(s2)
		if s2.get_node_or_null("Boss") == null:
			s2._ready()
		check(s2.get_node_or_null("Boss") != null, "ボス（Boss）がいる")
		var cfg2: Dictionary = s2.config
		var hp0: float = s2.boss_hp
		s2.player.position = Vector3(0.0, s2.ground_y, float(cfg2["boss_position"][1]) + 2.0)
		check(not s2.attack(), "戦いが始まる前は、こうげきが当たらない")
		var now := [1000000.0]
		s2.clock_ms = func() -> float: return now[0]
		s2.player.position = Vector3(0.0, s2.ground_y, 10.0)
		s2.start_round()
		check(s2.round_active() and s2.round_count == 1, "はじめるで、戦いが始まる（通信なし）")
		check(not s2.attack(), "遠いと、こうげきは当たらない")
		check(s2.boss_hp == hp0, "遠いときは、ボスの体力は減らない")
		s2.player.position = Vector3(0.0, s2.ground_y, float(cfg2["boss_position"][1]) + 2.0)
		check(s2.attack(), "近くで、こうげきが当たる")
		check(is_equal_approx(s2.boss_hp, hp0 - s2.role_value("attack_power")), "当たると、攻撃力のぶん体力が減る")
		check(not s2.attack(), "待ち時間の内は、もう一度は当たらない")
		s2.attack_cooldown = 0.0
		var attack_at: Vector2 = Vector2(SCREEN.x * cfg2["attack_center_frac"][0], SCREEN.y * cfg2["attack_center_frac"][1])
		s2.handle_press(5, attack_at, SCREEN)
		check(s2.button_touch == -1 and s2.velocity_y == 0.0, "こうげきのボタンは、ジャンプにならない")
		s2.handle_release(5)
		s2.attack_cooldown = 0.0
		s2.my_hits = float(cfg2["boss_hp"]) - 5.0
		check(s2.attack() and s2.won and not s2.boss.visible, "体力を0にすると、勝ちになり、ボスが消える")
		s2.attack_cooldown = 0.0
		check(not s2.attack(), "倒したあとは、こうげきが当たらない")
		check(not s2.round_active(), "倒すと、戦いは終わる")
		s2.start_round()
		check(s2.round_active() and not s2.won and s2.boss.visible and s2.my_hits == 0.0 and s2.boss_hp == float(cfg2["boss_hp"]), "もういちどで、体力が元に戻り、また始まる")

		# ボスの範囲攻撃：予告 → 一撃。輪の中で地面にいると当たり、ジャンプでよけられる
		var hp_full: float = s2.role_value("hp")
		var t0: float = s2.round_start_ms
		var first_ms: float = float(cfg2["slam_first_delay_sec"]) * 1000.0
		s2.player.position = Vector3(0.0, s2.ground_y, float(cfg2["boss_position"][1]) + 2.0)
		now[0] = t0 + first_ms - float(cfg2["slam_telegraph_sec"]) * 500.0
		s2.combat_update(0.016)
		check(s2.slam_ring.visible and s2.my_hp == hp_full, "予告の最中は、輪が見えて、まだダメージは受けない")
		now[0] = t0 + first_ms + 10.0
		s2.combat_update(0.016)
		check(is_equal_approx(s2.my_hp, hp_full - float(cfg2["slam_power"])), "輪の中で、地面にいると、一撃を受ける")
		check(not s2.slam_ring.visible, "一撃のあとは、輪が消える")
		var interval_ms: float = float(cfg2["slam_interval_sec"]) * 1000.0
		var hp_before: float = s2.my_hp
		s2.player.position.y = s2.ground_y + 1.5
		now[0] = t0 + first_ms + interval_ms + 10.0
		s2.combat_update(0.016)
		check(s2.my_hp == hp_before, "ジャンプ中は、一撃をよけられる")
		s2.player.position = Vector3(14.0, s2.ground_y, 14.0)
		now[0] = t0 + first_ms + interval_ms * 2.0 + 10.0
		s2.combat_update(0.016)
		check(s2.my_hp == hp_before, "輪の外にいれば、一撃を受けない")
		# 2回目は突進：通り道（帯）の中にいると当たり、横にずれるか跳べばよけられる
		var lane2: float = Pattern.lane_x(2, cfg2["charge_lanes"])
		var charge_t: float = t0 + first_ms + interval_ms - float(cfg2["slam_telegraph_sec"]) * 500.0
		s2.last_strike = 1
		s2.my_hp = hp_full
		s2.player.position = Vector3(lane2, s2.ground_y, 2.0)
		now[0] = charge_t
		s2.combat_update(0.016)
		check(s2.charge_strip.visible and not s2.slam_ring.visible, "突進の予告の最中は、帯が見える（輪は見えない）")
		check(is_equal_approx(s2.charge_strip.position.x, lane2), "帯は、突進の通り道の位置にある")
		s2.last_strike = 2
		s2.my_hp = hp_full
		s2.player.position = Vector3(lane2, s2.ground_y, 2.0)
		s2._resolve_strike(2)
		check(is_equal_approx(s2.my_hp, hp_full - float(cfg2["charge_power"])), "突進の通り道の中にいると、突進を受ける")
		s2.my_hp = hp_full
		s2.player.position = Vector3(lane2 + float(cfg2["charge_half_width"]) + 1.0, s2.ground_y, 2.0)
		s2._resolve_strike(2)
		check(s2.my_hp == hp_full, "横にずれれば、突進をよけられる")
		s2.player.position = Vector3(lane2, s2.ground_y + 1.5, 2.0)
		s2._resolve_strike(2)
		check(s2.my_hp == hp_full, "跳んでいれば、突進をよけられる")
		s2.player.position = Vector3(0.0, s2.ground_y, float(cfg2["boss_position"][1]) + 2.0)
		var guard := 0
		while not s2.downed and guard < 20:
			guard += 1
			now[0] += interval_ms
			s2.combat_update(0.016)
		check(s2.downed and s2.my_hp <= 0.0, "体力が0になると、ダウンする")
		check(s2.lost and not s2.round_active(), "1人だけでダウンすれば、全滅で戦いが終わる")
		check(not s2.attack(), "ダウン中は、こうげきが当たらない")
		s2.start_round()
		check(s2.my_hp == hp_full and not s2.downed and not s2.lost, "もういちどで、ダウンから復活する")
		root.remove_child(s2)
		s2.free()

	# カメラの追従と、頭の上の印
	var packed5 := load(SCENE) as PackedScene
	if packed5 != null:
		var s5: Node = packed5.instantiate()
		root.add_child(s5)
		if s5.get_node_or_null("Boss") == null:
			s5._ready()
		check(s5.player.get_node_or_null("Marker") != null, "自分の箱の上に、印がある")
		check((s5.player.get_node("Marker") as MeshInstance3D).mesh.material.no_depth_test, "印は、ほかの物に隠れても見える（深さを無視）")
		var cam_start: Vector3 = s5.camera.position
		s5.player.position = Vector3(10.0, s5.ground_y, -10.0)
		for i in 60:
			s5.camera_update(0.1)
		var want: Vector3 = Vector3(10.0, 0.0, -10.0) * float(s5.config["camera_follow"]) + s5.camera_offset
		check(s5.camera.position.distance_to(want) < 0.05, "カメラは、自分の動きの一部だけ、ついていく")
		check(s5.camera.position.distance_to(cam_start) > 3.0, "カメラが動いた")
		s5.other_target["p2"] = Vector2(0.5, 0.5)
		s5._update_others(0.1)
		check(s5.others.has("p2") and (s5.others["p2"] as Node).get_node_or_null("Marker") != null, "ほかの人の箱にも、印がある")
		root.remove_child(s5)
		s5.free()

	# いかりと、結果の画面
	var packed6 := load(SCENE) as PackedScene
	if packed6 != null:
		var s6: Node = packed6.instantiate()
		root.add_child(s6)
		if s6.get_node_or_null("Boss") == null:
			s6._ready()
		var now6 := [2000000.0]
		s6.clock_ms = func() -> float: return now6[0]
		s6.start_round()
		check(not s6.is_enraged(), "始まった直後は、いかりではない")
		now6[0] += float(s6.config["enrage_after_sec"]) * 1000.0 + 100.0
		check(s6.is_enraged(), "いかりの時刻を過ぎると、いかり")
		s6.combat_update(0.016)
		check(s6.last_strike == s6._strike_count(float(s6.config["enrage_after_sec"]) + 0.1), "いかりの間も、一撃の回数が数えられる")
		s6.player.position = Vector3(0.0, s6.ground_y, float(s6.config["boss_position"][1]) + 2.0)
		s6.my_hits = 123.0
		s6.net_state = {"slot": "p1", "members": ["p1", "p2"], "hits": {"p1": 123, "p2": 77}}
		s6.round_start_ms = now6[0] - 83000.0
		s6.won = true
		s6.round_end_ms = now6[0]
		var lines: Array = s6.build_result_lines()
		check(lines.size() == 3 and str(lines[0]).ends_with("1：23"), "結果：かかった時間（83秒＝1：23）：" + str(lines))
		check(str(lines[1]).ends_with("123") and str(lines[2]).contains("p2 77"), "結果：自分とほかの人のダメージ")
		s6.won = false
		s6.round_start_ms = 0.0
		root.remove_child(s6)
		s6.free()

	# 役割（仮）：枠ごとに強さが違う
	var packed4 := load(SCENE) as PackedScene
	if packed4 != null:
		var s4: Node = packed4.instantiate()
		root.add_child(s4)
		if s4.get_node_or_null("Boss") == null:
			s4._ready()
		var roles: Dictionary = s4.config["roles"]
		check(roles.size() == 4 and roles.has("p1") and roles.has("p4"), "役割が4つある（p1〜p4）")
		var names := []
		for k in roles:
			names.append(roles[k]["name"])
		check(names.size() == 4 and _unique(names), "4つの役割の名前は、すべて違う")
		for slot in ["p1", "p2", "p3", "p4"]:
			s4.net_state = {"slot": slot}
			check(s4.role_value("hp") == float(roles[slot]["hp"]) and s4.role_value("move_speed") == float(roles[slot]["move_speed"]), "枠 %s：体力と速さが、役割どおり" % slot)
		s4.net_state = {"slot": "p2"}
		var hp_p2: float = s4.role_value("hp")
		s4.net_state = {"slot": "p1"}
		check(hp_p2 > s4.role_value("hp"), "p2（かたい）は、p1（つよい）より体力が多い")
		check(roles["p1"]["attack_power"] > roles["p2"]["attack_power"], "p1（つよい）は、p2（かたい）よりこうげきが強い")
		check(roles["p3"]["move_speed"] > roles["p1"]["move_speed"] and roles["p3"]["attack_cooldown_sec"] < roles["p1"]["attack_cooldown_sec"], "p3（はやい）は、速く動け、連続でこうげきできる")
		check(roles["p4"]["jump_speed"] > roles["p1"]["jump_speed"], "p4（とぶ）は、高く跳べる")
		s4.net_state = {}
		check(s4.role_value("hp") == float(roles["p1"]["hp"]), "通信なしのときは、p1の役割")
		s4.net_state = {"slot": "p4"}
		s4.jump()
		check(is_equal_approx(s4.velocity_y, float(roles["p4"]["jump_speed"])), "跳ぶ強さに、役割が効く")
		root.remove_child(s4)
		s4.free()

	# 通信（偽のブラウザで確かめる）
	check(Proto.pick_room_code("2468", "1111", 4) == "2468", "URLの合言葉が正しければ、それを使う")
	check(Proto.pick_room_code("24a8", "1111", 4) == "1111", "URLの合言葉が不正なら、既定の合言葉")
	check(Proto.pick_room_code(null, "1111", 4) == "1111", "URLに合言葉がなければ、既定の合言葉")
	var cfg3: Dictionary = Proto.load_config()
	check(Proto.build_room_text({}, "", false, cfg3) == str(cfg3["room_offline"]), "通信しないときの文字")
	check(Proto.build_room_text({"status": "in_room", "members": ["p1", "p2"]}, "1111", true, cfg3) == "部屋 1111：いま2人", "入室中の文字：" + Proto.build_room_text({"status": "in_room", "members": ["p1", "p2"]}, "1111", true, cfg3))
	check(Proto.build_room_text({"status": "full"}, "1111", true, cfg3) == str(cfg3["room_full"]), "満員の文字")
	check(Proto.build_room_text({"status": "reconnecting"}, "1111", true, cfg3) == str(cfg3["room_reconnecting"]), "再接続中の文字")
	check(Proto.build_room_text({"status": "joining"}, "1111", true, cfg3) == str(cfg3["room_connecting"]), "つなぎ中の文字")

	var packed3 := load(SCENE) as PackedScene
	if packed3 != null:
		var sent: Array = []
		var fake := func(text: String) -> Variant:
			sent.append(text)
			if text == "typeof window.bbFirebase":
				return "object"
			if text.begins_with("new URLSearchParams"):
				return "2222"
			if text.begins_with("JSON.stringify"):
				return JSON.stringify({"status": "in_room", "slot": "p1", "members": ["p1", "p2"], "positions": {"p2": {"x": 0.5, "y": 0.5, "t": 1}}, "hits": {"p2": 30}, "hp": {"p2": {"hp": 100, "round": 5000000}}, "round": 5000000})
			return null
		var s3: Node = packed3.instantiate()
		s3.use_network = false
		root.add_child(s3)
		if s3.get_node_or_null("Boss") == null:
			s3._ready()
		var now3 := [5000000.0 + 5000.0]
		s3.clock_ms = func() -> float: return now3[0]
		s3.js_eval = fake
		s3._setup_network()
		check(s3.net_active, "ブラウザの入り口があれば、通信が始まる")
		check(s3.room_code == "2222", "URLの合言葉の部屋に入る")
		check(sent.any(func(t): return str(t).begins_with("window.bbFirebase.joinRoom(") and str(t).contains('"2222"')), "入室の呼び出しが出る")
		s3.net_update(0.06, 1000)
		check(str(s3.net_state.get("slot", "")) == "p1", "状態を読む（自分は p1）")
		check(s3.others.has("p2") and not s3.others.has("p1"), "ほかの人（p2）の箱ができる。自分の箱は増えない")
		check(s3.round_active() and s3.round_count == 1, "部屋の開始の時刻が来ると、自分の画面でも戦いが始まる")
		check(is_equal_approx(s3.others_hits, 30.0) and is_equal_approx(s3.boss_hp, float(s3.config["boss_hp"]) - 30.0), "ほかの人のダメージで、ボスの体力が減る")
		check(sent.any(func(t): return str(t).begins_with("window.bbFirebase.sendPosition(0.5, 0.5)")), "自分の位置を送る（中心は 0.5, 0.5）")
		s3.player.position = Vector3(0.0, s3.ground_y, float(s3.config["boss_position"][1]) + 2.0)
		s3.attack_cooldown = 0.0
		check(s3.attack() and is_equal_approx(s3.boss_hp, float(s3.config["boss_hp"]) - 30.0 - s3.role_value("attack_power")), "こうげきで、体力はほかの人の分と合わせて減る")
		check(sent.any(func(t): return str(t).begins_with("window.bbFirebase.sendHits(15")), "与えたダメージを送る")
		s3.apply_net_state({"slot": "p1", "positions": {}, "hits": {"p2": 30}})
		check(not s3.others.has("p2"), "ほかの人が抜けたら、箱を消す")
		s3.apply_net_state({"slot": "p1", "hits": {"p2": 395}, "round": 5000000})
		check(s3.won and not s3.boss.visible, "ほかの人のダメージで、ボスが倒れたとき、自分の画面でも倒れる")
		check(sent.any(func(t): return str(t).begins_with("window.bbFirebase.sendHp(")), "体力を送る")
		var count_before: int = s3.round_count
		s3.start_round()
		check(sent.any(func(t): return str(t) == "window.bbFirebase.startRound()"), "通信中の「もういちど」は、部屋に開始を書く")
		now3[0] = 5000000.0 + 20000.0
		s3.apply_net_state({"slot": "p1", "members": ["p1", "p2"], "hits": {"p2": 20}, "round": 5020000})
		check(s3.round_active() and s3.round_count == count_before + 1 and s3.my_hits == 0.0, "新しい開始の時刻で、2回目の戦いが始まる")
		check(is_equal_approx(s3.boss_hp, float(s3.config["boss_hp"])), "開始の直後は、前の戦いのダメージを数えない")
		now3[0] += 2000.0
		s3.apply_net_state({"slot": "p1", "members": ["p1", "p2"], "hits": {"p2": 20}, "round": 5020000})
		check(is_equal_approx(s3.boss_hp, float(s3.config["boss_hp"]) - 20.0), "少したつと、ほかの人のダメージを数える")
		s3.player.position = Vector3(0.0, s3.ground_y, float(s3.config["boss_position"][1]) + 2.0)
		s3.apply_net_state({"slot": "p1", "members": ["p1", "p2"], "hits": {"p2": 20}, "hp": {"p2": {"hp": 60, "round": 5020000}}, "round": 5020000})
		s3._set_my_hp(0.0)
		check(s3.downed and not s3.lost, "自分だけダウンでも、仲間が生きていれば全滅ではない")
		s3.apply_net_state({"slot": "p1", "members": ["p1", "p2"], "hits": {"p2": 20}, "hp": {"p2": {"hp": 0, "round": 5020000}}, "round": 5020000})
		check(s3.lost, "仲間もダウンすれば、全滅")
		check(s3.build_team_text().contains("p2"), "なかまの体力が画面に出る")
		s3.apply_net_state({"slot": "p1", "members": ["p1", "p2", "p3"], "hits": {"p2": 20}, "hp": {"p2": {"hp": 0, "round": 5020000}, "p3": {"hp": 90, "round": 1}}, "round": 5020000})
		check(s3.lost, "古い記録の幽霊（p3）がいても、全滅のまま")
		var count_now: int = s3.round_count
		s3.apply_net_state({"slot": "p1", "members": ["p1"], "round": 4000000000000})
		check(s3.round_count == count_now, "遠い未来の開始の時刻は、始めない")
		root.remove_child(s3)
		s3.free()

	# 書き出しの設定
	var project := FileAccess.get_file_as_string("res://project.godot")
	check(project.contains('run/main_scene.stick_prototype="res://scenes/prototype/stick_prototype.tscn"'), "機能タグ stick_prototype で、この画面が開く")
	check(project.contains("emulate_touch_from_mouse=true"), "PCでは、マウスでタッチを真似られる（確認用）")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains('custom_features="stick_prototype"'), "書き出しのプリセットに stick_prototype がある")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
