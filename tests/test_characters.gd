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
	check(not hero.is_empty() and hero["name"] == "けんし", "主人公（けんし）がいる")
	check(CharacterData.find(cfg, "zzz").is_empty(), "知らないidは空")
	check(not CharacterData.has_model(hero), "モデルのファイルがまだないので、箱のまま")
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
	check(is_equal_approx(b.role_value("hp"), 160.0) and b.role().get("name") == "ガーディアン" and b.role().get("character_name") == "たて", "選んだキャラ（たて）の性能・役職名で動く")
	check(b.role_name_of("p1") == "ガーディアン", "通信なしなら、自分の役職名が出る")
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
	check(not v0.setup(hero), "モデルがなければ、読み込みは失敗（箱のまま）")
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model_path))
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
