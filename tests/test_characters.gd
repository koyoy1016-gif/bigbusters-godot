extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_characters.gd
## キャラのデータ（character_data.gd）と、モデルの読み込み・アニメ（character_view.gd）を確かめる。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Bench := preload("res://scripts/prototype/bench_character.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := CharacterData.load_config()
	check(CharacterData.validate(cfg).is_empty(), "キャラのデータに誤りがない：" + str(CharacterData.validate(cfg)))
	var hero := CharacterData.find(cfg, str(cfg["player_character"]))
	check(not hero.is_empty() and hero["name"] == "剣士", "主人公（剣士。版109で けんし→剣士）がいる")
	check(CharacterData.find(cfg, "zzz").is_empty(), "知らないidは空")
	# 2026-10-20：8人の味方は、みんな見た目（剣士と同じ体＋服・装備）を持つようになった。モデルのないキャラは、作って確かめる
	var no_model := CharacterData.find(cfg, "guardian").duplicate(true)
	no_model["model"] = ""
	check(not CharacterData.has_model(no_model), "モデルのファイルがないキャラは、箱のまま")
	check(CharacterData.has_model(hero), "主人公（けんし）は、本物のモデルのファイルがある")
	check(float(hero["tri_budget"]) <= float(cfg["budgets"]["ally"]), "面の数の予算が、味方の上限以内")
	var font := load("res://assets/fonts/NotoSansJP-Regular-subset.ttf") as Font
	var ok := true
	for ch in str(hero["name"]):
		if not font.has_char(ch.unicode_at(0)):
			ok = false
	check(ok, "名前の文字がフォントにある")
	var roles := cfg["role_colors"] as Dictionary
	check(roles.size() == 4, "役職は4つ（4色）")
	var kinds := {}
	var all_ok := true
	for c in cfg["characters"]:
		kinds[str(c["archetype"])] = true
		if not roles.has(str(c["role"])):
			all_ok = false
		for ch in str(c["name"]):
			if not font.has_char(ch.unicode_at(0)):
				all_ok = false
	for k in roles:
		for ch in str(k):
			if not font.has_char(ch.unicode_at(0)):
				all_ok = false
	check(all_ok, "全員の役職が4つのどれか。名前・役職名の文字がフォントにある")
	var count := {}
	for c in cfg["characters"]:
		count[str(c["role"])] = int(count.get(str(c["role"]), 0)) + 1
	var most := 0
	var least := 99
	for k in roles:
		most = maxi(most, int(count.get(k, 0)))
		least = mini(least, int(count.get(k, 0)))
	check(least >= 1 and most <= 3, "どの役職にも1人以上いて、多すぎない（最少 " + str(least) + "・最多 " + str(most) + "）")
	var skills_ok := true
	for c in cfg["characters"]:
		if str(c.get("skill", "")) == "" or not c.has("break_power"):
			skills_ok = false
	check(skills_ok, "全員に、Xの技と、ゲージ割りの強さがある")
	var skill_font_ok := true
	for c in cfg["characters"]:
		for ch in str(c["skill"]):
			if not font.has_char(ch.unicode_at(0)):
				skill_font_ok = false
	check(skill_font_ok, "Xの技の名前の文字がフォントにある")
	var skills := {}
	for c in cfg["characters"]:
		skills[str(c["id"])] = str(c["skill"])
	check(skills["hero_swordsman"] == "斬る" and skills["guardian"] == "バリア" and skills["sprinter"] == "ダッシュ" and skills["brawler"] == "ダッシュ" and skills["gunner"] == "射撃" and skills["healer"] == "回復" and skills["bomber"] == "投げ" and skills["mage"] == "魔法" and skills["summoner"] == "召喚", "Xの技は、ユーザーが決めた仮案どおり")
	for want in ["swordsman", "speed", "fist", "gun", "bomb", "magic", "shield", "summon", "heal"]:
		check(kinds.has(want), "タイプ " + want + " がいる")
	for a in cfg["actions"]:
		check(CharacterData.animation_for(hero, a) != "", "動作 " + a + " のアニメ名がある")
	check(CharacterData.pick_action(true, true, true, true) == "down", "ダウンが最優先")
	check(CharacterData.pick_action(false, true, true, true) == "jump", "つぎにジャンプ")
	check(CharacterData.pick_action(false, false, true, true) == "attack", "つぎにこうげき")
	check(CharacterData.pick_action(false, false, false, true) == "run", "動いていれば走る")
	check(CharacterData.pick_action(false, false, false, false) == "idle", "何もなければ待つ")
	# 誤りの検出
	var packed_battle := load("res://scenes/prototype/stick_prototype.tscn") as PackedScene
	var b: Node = packed_battle.instantiate()
	b.selected_character = "guardian"
	root.add_child(b)
	if b.get_node_or_null("Boss") == null:
		b._ready()
	check(is_equal_approx(b.role_value("hp"), 240.0) and b.role().get("name") == "ガーディアン" and b.role().get("character_name") == "守護士", "選んだキャラ（守護士）の性能で動く")
	check(b.role_name_of("p1") == "守護士", "通信なしなら、自分の役職名（版109：守護士）が出る")
	# 通信：ほかの人のキャラが共有されたら、そのキャラの役職名が出る
	b.net_active = true
	b.net_state = {"slot": "p1", "members": ["p1", "p2", "p3"], "chars": {"p2": "healer"}}
	check(b.role_name_of("p1") == "守護士", "通信中も、自分は自分の役職名")
	check(b.role_name_of("p2") == "介護士", "ほかの人のキャラが共有されていれば、その役職名（介護士）")
	check(b.role_name_of("p3") == "仲間", "まだ共有されていない人は「仲間」（版115）")
	check(str(b.char_def_of("p2").get("id", "")) == "healer" and b.char_def_of("p3").is_empty(), "枠のキャラの定義を引ける（未共有は空）")
	check(str(b.char_def_of("p1").get("id", "")) == "guardian", "自分の枠は、選んだキャラ")
	b.net_state["chars"] = {"p2": "no_such_character"}
	check(b.char_def_of("p2").is_empty(), "知らないキャラの id でも、壊れない（空）")
	# 自分のキャラを部屋に知らせる
	var sent: Array = []
	b.bridge.js_eval = func(code: String) -> Variant:
		sent.append(code)
		return null
	b.last_char_sent_ms = -100000
	b.net_state = {"slot": "p1", "members": ["p1"], "chars": {}}
	b._share_my_character(100000)
	check(sent.size() == 1 and str(sent[0]).contains("sendChar(\"guardian\")"), "まだ知らせていなければ、自分のキャラを送る")
	b._share_my_character(100500)
	check(sent.size() == 1, "2秒以内には、もう一度送らない")
	b._share_my_character(103000)
	check(sent.size() == 2, "2秒たっても部屋の記録がなければ、もう一度送る")
	b.net_state["chars"] = {"p1": "guardian"}
	b._share_my_character(110000)
	check(sent.size() == 2, "部屋の記録が同じなら、送らない")
	# ほかの人の見た目：共有されたキャラにモデルがあれば、箱の代わりにモデル
	b.net_state = {"slot": "p1", "members": ["p1", "p2"], "chars": {"p2": "hero_swordsman"}}
	var n2: MeshInstance3D = b._other_node("p2")
	check(n2.mesh != null, "最初は箱")
	b._update_other_view("p2", n2, Vector3.ZERO, 0.1)
	check(b.other_views.has("p2") and n2.mesh == null, "剣士（モデルあり）が共有されたら、箱を外してモデルを出す")
	check(is_equal_approx(n2.get_node("Marker").position.y, float(b.config["marker_height_model"])), "印が、モデルの頭の上に上がる")
	b._update_other_view("p2", n2, Vector3(1, 0, 0), 0.1)
	check(b.other_views["p2"].current_action == "run", "動いていれば走る")
	b._update_other_view("p2", n2, Vector3.ZERO, 0.1)
	check(b.other_views["p2"].current_action == "idle", "止まれば待つ")
	# 2026-10-20：味方8人はみんなモデルを持つので、一覧にないキャラ（モデルなし）で確かめる
	b.net_state["chars"] = {"p2": "no_such_character"}
	b._update_other_view("p2", n2, Vector3.ZERO, 0.1)
	check(not b.other_views.has("p2") and n2.mesh != null, "モデルのないキャラに変わったら、箱にもどる")
	b.net_active = false
	root.remove_child(b)
	b.free()
	var bad := {"actions": ["idle"], "budgets": {"ally": 100}, "player_character": "nobody", "characters": [
		{"id": "a", "name": "x", "kind": "ally", "tri_budget": 999, "animations": {}},
		{"id": "a", "name": "y", "kind": "ally", "tri_budget": 1, "animations": {"idle": "I"}},
		{"name": "z"}]}
	var errs := CharacterData.validate(bad)
	check(errs.size() >= 4, "壊れたデータの誤りを見つける：" + str(errs.size()) + "件")

	# モデルなし
	var v0 := CharacterView.new()
	check(not v0.setup(no_model), "モデルがなければ、読み込みは失敗（箱のまま）")
	v0.free()

	# モデルあり（骨つきの試験用の人型＋アニメ入りの場面を作って、読み込む）
	var holder := Node3D.new()
	holder.name = "Model"
	var skinned := Bench.build(2000, StandardMaterial3D.new())
	holder.add_child(skinned)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()
	for n in ["Idle", "Run", "Jump", "Sword_Attack", "Death"]:
		var anim := Animation.new()
		anim.length = 1.0
		lib.add_animation(n, anim)
	ap.add_animation_library("", lib)
	holder.add_child(ap)
	ap.owner = holder
	skinned.owner = holder
	for c in skinned.get_children():
		c.owner = holder
	var packed := PackedScene.new()
	packed.pack(holder)
	var model_path := "user://test_hero.tscn"
	check(ResourceSaver.save(packed, model_path) == OK, "試験用のモデルの場面を保存")
	var def := hero.duplicate(true)
	def["model"] = model_path
	check(CharacterData.has_model(def), "ファイルがあれば、モデルありになる")
	var view := CharacterView.new()
	root.add_child(view)
	check(view.setup(def) and view.model != null and view.player != null, "モデルを読み込み、アニメ再生の部品が見つかる")
	check(view.play_action("run") and view.player.current_animation == "Run", "走るのアニメが流れる")
	check(not view.play_action("run"), "同じ動作なら、流し直さない")
	check(view.play_action("attack") and view.player.current_animation == "Sword_Attack", "こうげきのアニメに変わる")
	def["animations"]["jump"] = "NoSuchAnim"
	var view2 := CharacterView.new()
	root.add_child(view2)
	view2.setup(def)
	check(not view2.play_action("jump"), "モデルにないアニメ名でも、壊れない")
	view.face(Vector2(1, 0), 1.0)
	check(is_equal_approx(view.rotation.y, PI * 0.5), "右に動くと、右を向く")
	var r := view.rotation.y
	view.face(Vector2.ZERO, 1.0)
	check(view.rotation.y == r, "止まっているときは、向きを変えない")
	# 本物の剣士のモデル（MPFB）：骨・メッシュ・材質直しが効いている
	var rv := CharacterView.new()
	root.add_child(rv)
	check(rv.setup(hero), "剣士の本物のモデルを読み込める")
	var skels := rv.model.find_children("*", "Skeleton3D", true, false)
	check(skels.size() == 1 and (skels[0] as Skeleton3D).get_bone_count() >= 100, "骨が100本以上ある")
	var tris := 0
	var hair_ok := false
	var body_ok := false
	for m in rv.model.find_children("*", "MeshInstance3D", true, false):
		if m.has_meta("proxy"):
			continue  # 版103：影だけ・輪郭線だけの形（同じ点の写し。色を塗る形ではない）は数えない
		var mesh := (m as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(i)
			tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mt := mesh.surface_get_material(i) as StandardMaterial3D
			if mt.resource_name.to_lower().contains("short"):
				hair_ok = mt.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			if mt.resource_name == "Human.body":
				body_ok = mt.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	check(hair_ok and body_ok, "髪は切り抜き、体は不透明に直っている")
	check(tris > 1000 and tris <= int(float(cfg["budgets"]["ally"]) * 2.4), "面の数が予算の2.4倍以内（いまは約33,000＝体＋小物。あとで減らすか、予算を上げる）：" + str(tris))
	# 小物（長い刀・袴・鎧・結び髪など）：骨に付く。setup では、付けたあと1つの形にまとめる（tests/test_mesh_merge.gd）ので、
	# 付ける手順そのものは、まとめる前のモデルで確かめる
	var raw: Node = (load(str(hero["model"])) as PackedScene).instantiate()
	root.add_child(raw)
	CharacterView.attach_items(raw, hero.get("attachments", []))
	var items := raw.find_children("Item_*", "BoneAttachment3D", true, false)
	check(items.size() == 31, "刀と、侍の装備（31こ）が骨に付いている：" + str(items.size()))
	var sword := raw.find_child("Item_katana_long", true, false) as BoneAttachment3D
	check(sword != null and sword.bone_name == "wrist.R", "刀は右手首の骨に付く")
	check(sword != null and sword.get_child(0).get_child_count() == 5, "刀は5つの部品（つか・柄巻き×2・つば・刃）")
	var kote := raw.find_child("Item_sam_kote_L", true, false) as BoneAttachment3D
	check(kote != null and kote.bone_name == "lowerarm01.L" and kote.get_child_count() == 2, "籠手は、前腕の骨に付く")
	var tail := raw.find_child("Item_sam_ponytail", true, false) as BoneAttachment3D
	check(tail != null and tail.bone_name == "head", "結び髪は、頭の骨に付く")
	var none := CharacterView.attach_items(rv.model, ["no_such_item"])
	check(none == 0, "知らない小物の id は、何も付けない")
	var bad_bone := CharacterView.attach_items(rv.model, ["x"], {"x": {"bone": "no_such_bone", "parts": []}})
	check(bad_bone == 0, "骨がなければ、付けない")
	check(CharacterView.attach_items(rv.model, []) == 0, "小物の指定が空なら、何もしない")
	rv.queue_free()
	raw.queue_free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
