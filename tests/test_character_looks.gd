extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_character_looks.gd
## 2026-10-20：味方キャラの見た目（data/character_looks.json と scripts/characters/body_builder.gd）。
## 画面のないテストでは、作った面の中身は読めない（画面なしの描画は形を保たない）。形の出来は tools/shot_look.gd の画像で見る。
## ここでは：データの決まり、骨の部位の分け方、左右反対の部品、当てはめても落ちないこと、キャラの強さの数値を変えていないこと。

const BB := preload("res://scripts/characters/body_builder.gd")
const CD := preload("res://scripts/characters/character_data.gd")
const CV := preload("res://scripts/characters/character_view.gd")
## 見た目を作る前の、キャラの強さ（変えていないことの確認。版59の値）
const STATS := {"sprinter": [105.0, 12.0, 10.0], "brawler": [135.0, 15.0, 8.0], "gunner": [105.0, 13.5, 6.0], "bomber": [112.5, 16.5, 5.0],
	"mage": [97.5, 18.0, 5.5], "guardian": [240.0, 10.5, 5.0], "summoner": [120.0, 9.0, 6.0], "healer": [127.5, 7.5, 6.0]}
const SHAPES := ["loft", "tube", "rod", "sphere", "box", "torus", "extrude"]
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var looks := BB.load_looks()
	var cfg := CD.load_config()
	check(not looks.is_empty(), "見た目のデータが読める")
	# 骨の部位
	check(BB.group_of("upperarm01.L") == "upperarm" and BB.group_of("lowerarm02.R") == "forearm", "腕の部位")
	check(BB.group_of("finger2-3.L") == "hand" and BB.group_of("wrist.R") == "hand", "手の部位")
	check(BB.group_of("upperleg02.L") == "thigh" and BB.group_of("lowerleg01.R") == "shin" and BB.group_of("toe1-1.L") == "foot", "脚の部位")
	check(BB.group_of("spine01") == "chest" and BB.group_of("spine04") == "belly" and BB.group_of("pelvis.L") == "hips", "胴の部位")
	check(BB.group_of("neck02") == "neck" and BB.group_of("eye.L") == "head" and BB.group_of("jaw") == "head", "首・頭の部位")
	# 左右反対
	var p := {"bone": "wrist.L", "shape": "sphere", "center": [0.5, 1.2, 0.2], "r": 0.1, "rotation_deg": [0, 30, 10], "mirror": true}
	var m := BB.mirror_part(p)
	check(str(m["bone"]) == "wrist.R" and is_equal_approx(float(m["center"][0]), -0.5) and not m.has("mirror"), "左右反対の部品は、骨と x が入れかわる")
	check(is_equal_approx(float(p["center"][0]), 0.5), "もとの部品は変わらない")
	var t := {"shape": "tube", "points": [[0.1, 1, 0], [0.2, 1, 0]], "bone": "head"}
	check(is_equal_approx(float(BB.mirror_part(t)["points"][1][0]), -0.2), "管の点も反対になる")
	# 形を作れる
	for shape in SHAPES:
		var part := {"shape": shape, "center": [0, 1, 0], "size": [0.1, 0.1, 0.1], "r": 0.05, "R": 0.1, "from": [0, 1, 0], "to": [0, 1.2, 0],
			"r0": 0.05, "r1": 0.02, "points": [[0, 1, 0], [0, 1.1, 0.05], [0, 1.2, 0]], "rings": [[[0, 1, 0], 0.1, 0.1], [[0, 1.2, 0], 0.05, 0.05]],
			"points2d": [[0, 0], [0.1, 0], [0.05, 0.1]], "depth": 0.02, "color": "#ff0000"}
		check(BB.make_part_mesh(part) != null, "形を作れる：" + shape)
	# 見た目ごとの決まり
	for id in looks:
		var lk: Dictionary = looks[id]
		check(lk.has("ref") and FileAccess.file_exists("res://" + str(lk["ref"])), "%s：参考画像がある" % id)
		var bad := 0
		for part in lk.get("parts", []):
			if not SHAPES.has(str(part.get("shape", ""))) or str(part.get("bone", "")) == "":
				bad += 1
		check(bad == 0, "%s：部品の形と骨が正しい" % id)
		var def := CD.find(cfg, str(id))
		check(not def.is_empty() and str(def.get("look", "")) == str(id), "%s：キャラの一覧から見た目を指している" % id)
		check(CD.has_model(def) and str(def.get("anim_library", "")) != "", "%s：体（剣士と同じ）と動きを使う" % id)
		var baked: Node = (load(str(def["model"])) as PackedScene).instantiate()
		check(str(baked.get_meta("look_baked", "")) == str(id), "%s：前もって作った形を読む（ゲームの中で作らない）" % id)
		var bsk := baked.find_children("*", "Skeleton3D", true, false)
		check(bsk.size() == 1 and (bsk[0] as Skeleton3D).get_bone_count() == 137, "%s：作った形の骨も剣士と同じ" % id)
		baked.free()
		var model: Node = (load("res://assets/models/hero_swordsman.glb") as PackedScene).instantiate()
		var tris := BB.apply(model, lk)
		check(tris > 0, "%s：当てはめられる（三角形 %d）" % [id, tris])
		var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		check(sk.get_bone_count() == 137 and sk.find_bone("head") >= 0, "%s：骨は剣士と同じ（動きが使える）" % id)
		check(sk.get_node_or_null("Human") != null, "%s：体がある" % id)
		model.free()
	# 強さの数値を変えていない
	for id in STATS:
		var def := CD.find(cfg, str(id))
		var st: Dictionary = def.get("stats", {})
		var want: Array = STATS[id]
		check(is_equal_approx(float(st.get("hp", 0)), want[0]) and is_equal_approx(float(st.get("attack_power", 0)), want[1])
			and is_equal_approx(float(st.get("move_speed", 0)), want[2]), "%s：体力・攻撃力・速さは変えていない" % id)
	var hero := CD.find(cfg, "hero_swordsman")
	check(float(hero["stats"]["hp"]) == 190.0 and float(hero["stats"]["attack_power"]) == 22.5, "剣士の数値は変えていない")
	check(not hero.has("look"), "剣士の見た目は変えていない")
	# 画面のキャラとして出せる（モデルが読めて、動きの再生係がある）
	for id in looks:
		var v: Node3D = CV.new()
		root.add_child(v)
		check(v.setup(CD.find(cfg, str(id))) and v.player != null and v.player.has_animation("Idle"), "%s：キャラとして出せて、動きがある" % id)
		v.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
