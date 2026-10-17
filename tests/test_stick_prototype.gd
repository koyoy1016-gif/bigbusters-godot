extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_stick_prototype.gd
## スティックの試作：計算（stick_math.gd）、数値（data/prototype_stick.json）、画面の動き、書き出しの設定。

const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const SCREEN := Vector2(1280, 720)

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


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
		var text := str(d["hint"]) + str(d["button_label"]) + str(d["attack_label"]) + str(d["boss_hp_label"]) + str(d["win_text"]) + "0123456789/"
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
		check(not s2.attack(), "遠いと、こうげきは当たらない")
		check(s2.boss_hp == hp0, "遠いときは、ボスの体力は減らない")
		s2.player.position = Vector3(0.0, s2.ground_y, float(cfg2["boss_position"][1]) + 2.0)
		check(s2.attack(), "近くで、こうげきが当たる")
		check(is_equal_approx(s2.boss_hp, hp0 - float(cfg2["attack_power"])), "当たると、攻撃力のぶん体力が減る")
		check(not s2.attack(), "待ち時間の内は、もう一度は当たらない")
		s2.attack_cooldown = 0.0
		var attack_at: Vector2 = Vector2(SCREEN.x * cfg2["attack_center_frac"][0], SCREEN.y * cfg2["attack_center_frac"][1])
		s2.handle_press(5, attack_at, SCREEN)
		check(s2.button_touch == -1 and s2.velocity_y == 0.0, "こうげきのボタンは、ジャンプにならない")
		s2.handle_release(5)
		s2.attack_cooldown = 0.0
		s2.boss_hp = 5.0
		check(s2.attack() and s2.won and not s2.boss.visible, "体力を0にすると、勝ちになり、ボスが消える")
		s2.attack_cooldown = 0.0
		check(not s2.attack(), "倒したあとは、こうげきが当たらない")
		root.remove_child(s2)
		s2.free()

	# 書き出しの設定
	var project := FileAccess.get_file_as_string("res://project.godot")
	check(project.contains('run/main_scene.stick_prototype="res://scenes/prototype/stick_prototype.tscn"'), "機能タグ stick_prototype で、この画面が開く")
	check(project.contains("emulate_touch_from_mouse=true"), "PCでは、マウスでタッチを真似られる（確認用）")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.contains('custom_features="stick_prototype"'), "書き出しのプリセットに stick_prototype がある")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
