extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_skills.gd
## Xの技の計算（skills.gd）を確かめる。

const Skills := preload("res://scripts/combat/skills.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := Skills.load_config()
	var chars := CharacterData.load_config()
	var ok := true
	for c in chars["characters"]:
		var sk: Variant = cfg.get(str(c["skill"]), null)
		if not (sk is Dictionary) or not sk.has("kind") or float(sk.get("cooldown_sec", 0.0)) <= 0.0 and str(sk.get("kind", "")) != "dash":
			ok = false
	check(ok, "全キャラのXの技が、skills.json にある")
	check(is_equal_approx(Skills.skill_damage(10.0, cfg["斬る"]), 25.0), "ダメージ ＝ 攻撃力 × 倍率（斬る 10×2.5）")
	check(Skills.skill_damage(-5.0, cfg["斬る"]) == 0.0, "ダメージは0より小さくならない")
	# 扇形
	var o := Vector2.ZERO
	var f := Vector2(0, -1)
	check(Skills.in_arc(o, f, Vector2(0, -3), 3.5, 70.0), "真正面の近くは当たる")
	check(not Skills.in_arc(o, f, Vector2(0, 3), 3.5, 70.0), "真うしろは当たらない")
	check(not Skills.in_arc(o, f, Vector2(0, -6), 3.5, 70.0), "遠いと当たらない")
	check(Skills.in_arc(o, f, Vector2(0, -6), 3.5, 70.0, 3.0), "相手が大きければ、届く")
	check(Skills.in_arc(o, f, Vector2(2.5, -1.5), 3.5, 70.0) and not Skills.in_arc(o, f, Vector2(3.0, 0.5), 3.5, 70.0), "角度の内は当たる。外は当たらない")
	check(Skills.in_arc(o, Vector2.ZERO, Vector2(1, 0), 3.5, 70.0), "向きが分からなくても壊れない")
	# 帯
	check(Skills.in_strip(o, f, Vector2(0.5, -10), 14.0, 0.6) and not Skills.in_strip(o, f, Vector2(2.0, -10), 14.0, 0.6), "帯の幅の内は当たる。外は当たらない")
	check(not Skills.in_strip(o, f, Vector2(0, -20), 14.0, 0.6) and not Skills.in_strip(o, f, Vector2(0, 5), 14.0, 0.6), "長さの外（遠い・うしろ）は当たらない")
	check(is_equal_approx(Skills.strip_distance(o, f, Vector2(0, -7), 14.0, 0.6), 7.0), "帯の中なら、前向きの距離を返す")
	check(Skills.strip_distance(o, Vector2.ZERO, Vector2(0, -7), 14.0, 0.6) == -1.0, "向きがなければ外")
	# 円・ダッシュ・投げ
	check(Skills.in_circle(Vector2(5, 5), Vector2(6, 5), 3.2) and not Skills.in_circle(Vector2(5, 5), Vector2(10, 5), 3.2) and Skills.in_circle(Vector2(5, 5), Vector2(10, 5), 3.2, 2.0), "爆発の円")
	check(Skills.dash_target(Vector2(0, 0), Vector2(1, 0), 5.0, 15.0).is_equal_approx(Vector2(5, 0)), "ダッシュは、向きに進む")
	check(Skills.dash_target(Vector2(14, 0), Vector2(1, 0), 5.0, 15.0).is_equal_approx(Vector2(15, 0)), "ダッシュは、床の外に出ない")
	check(Skills.dash_target(Vector2(1, 1), Vector2.ZERO, 5.0, 15.0).is_equal_approx(Vector2(1, 1)), "向きがなければ動かない")
	check(Skills.lob_point(Vector2(0, 0), Vector2(0, -1), 6.0, 15.0).is_equal_approx(Vector2(0, -6)), "投げる先")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
