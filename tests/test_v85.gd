extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v85.gd
## 版85：音楽と効果音。
## 確かめること：
##   1. 効果音：全部読める・短い・合計1MB未満。飛ぶ物（char_actions の prop）は全部、撃つ音と当たる音がある。
##      高さを少し変える（pitch_var）・プレイヤーの大きさ（user_volume）・0%で鳴らない・大きな音で loud（音楽を下げる合図）
##   2. 戦い：銃は「ぱん」（斬る音ではない）→ 当たると「当たり」。魔法は「ひゅいーん」→「きらきら」。剣は斬る音と当たり。必殺技の当たりは「ずどん」も
##   3. ボスの足音：1歩ごと（止まっている時は出ない）。遠いほど小さい。AIの味方の音は小さい
##   4. 倒れた・起きた・覚醒（雄たけび）・音楽の合図（fall・awake）
##   5. ガチャ：つかむ（きしみ）・25%ごとの目もり（強いほど高い）・飛び出す・斬る・結果（レア度ごと）
##   6. せってい：プロフィールに「せってい」（音楽・効果音のすべりバー・画質）。動かすと、すぐ反映して保存。アイコンで消す／もどす

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const FLOW_SCENE := "res://scenes/game_flow.tscn"
const Flow := preload("res://scripts/flow/game_flow.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const BattleAudio := preload("res://scripts/prototype/battle_audio.gd")
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")
const TEMP_SAVE := "user://test_v85_save.json"
const TEMP_AI := "user://test_v85_ai.json"
const TEMP_AUDIO := "user://test_v85_audio.json"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func make(char_id: String, ai_on: bool = false) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	s.ai_enabled = ai_on
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [3000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.start_round()
	s.skill_time_stop_left = 999.0
	s.sfx.played = []
	s.sfx.last_play = {}
	return s


func stand(s: Node, gap: float) -> void:
	var bp: Vector3 = s.boss.position
	var br := float(s.config["boss_size"]) * 0.5
	s.player.position = Vector3(bp.x, s.ground_y, bp.z + br + gap)
	s.facing = Vector2(0, -1)


func tick(s: Node, sec: float, dt: float = 0.05) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		s._actions_update(dt)
		s.combat_update(dt)
		s.sfx.last_play = {}  # テストでは時間が進まないので、同じ音の間かくは見ない
		t += dt
	Engine.time_scale = 1.0


func props_in(o: Variant, out: Dictionary) -> void:
	if o is Dictionary:
		if (o as Dictionary).get("proj", null) is Dictionary:
			out[str(o["proj"].get("prop", ""))] = true
		for v in (o as Dictionary).values():
			props_in(v, out)
	elif o is Array:
		for v in o:
			props_in(v, out)


func _initialize() -> void:
	# ---- 1. 効果音 ----
	var cfg := Sfx.load_config()
	var sounds: Dictionary = cfg["sounds"]
	var total := 0
	var ok_all := true
	for name in sounds:
		var st := load(str(sounds[name]["file"])) as AudioStream
		if st == null or st.get_length() <= 0.03 or st.get_length() >= 3.0:
			ok_all = false
			print("  だめ：", name)
		total += FileAccess.get_file_as_bytes(str(sounds[name]["file"])).size()
	check(ok_all and sounds.size() >= 39, "効果音 %d 個が読めて、どれも3秒未満" % sounds.size())
	check(total < 1000000, "効果音の合計は1MB未満（%d）" % total)
	for need in ["shot", "cannon", "magic", "magic_hit", "boom", "pop", "heal", "heavy", "boss_step", "roar", "down", "revive", "pull", "pull_tick", "launch", "gacha_hit", "reveal_n", "reveal_r", "reveal_sr", "reveal_ssr", "coin"]:
		if not sounds.has(need):
			check(false, "新しい音がある：" + need)
	var props := {}
	props_in(JSON.parse_string(FileAccess.get_file_as_string("res://data/char_actions.json")), props)
	var ps: Dictionary = cfg["proj_sounds"]
	var missing: Array = []
	for p in props:
		var pair: Variant = ps.get(p, null)
		if not (pair is Array) or not sounds.has(str(pair[1])) or (str(pair[0]) != "" and not sounds.has(str(pair[0]))):
			missing.append(p)
	check(props.size() >= 10 and missing.is_empty(), "飛ぶ物（%d 種類）は全部、撃つ音と当たる音がある %s" % [props.size(), str(missing)])

	var sx: Node = Sfx.new()
	root.add_child(sx)
	await process_frame
	var pitches := {}
	for i in 6:
		sx.last_play = {}
		sx.play("slash")
		for p in sx.pool:
			if (p as AudioStreamPlayer).playing or (p as AudioStreamPlayer).stream != null:
				pitches[snappedf((p as AudioStreamPlayer).pitch_scale, 0.0001)] = true
	var pv := float(sounds["slash"]["pitch_var"])
	var in_range := true
	for k in pitches:
		if float(k) < 1.0 - pv - 0.0001 or float(k) > 1.0 + pv + 0.0001:
			in_range = false
	check(pitches.size() >= 3 and in_range, "鳴らすたびに高さが少し変わる（±%d%%の中。%d 通り）" % [int(pv * 100), pitches.size()])
	sx.set_user_volume(0.5)
	sx.last_play = {}
	sx.play("hit", -3.0)
	var hp_vol := -999.0
	for i in sx.pool.size():
		if (sx.pool[i] as AudioStreamPlayer).stream == sx.streams.get("hit"):
			hp_vol = (sx.pool[i] as AudioStreamPlayer).volume_db
	check(is_equal_approx(hp_vol, float(sounds["hit"]["volume_db"]) - 3.0 + linear_to_db(0.5)), "大きさ：音ごとの大きさ＋足し引き＋プレイヤーの大きさ（%.1f dB）" % hp_vol)
	sx.set_user_volume(0.0)
	sx.last_play = {}
	check(not sx.play("hit"), "大きさ0%なら、鳴らさない")
	sx.set_user_volume(1.0)
	var louds: Array = []
	sx.loud.connect(func(db: float): louds.append(db))
	sx.last_play = {}
	sx.play("roar")
	sx.play("slash")
	check(louds == [float(sounds["roar"]["duck_db"])], "大きな音（雄たけび）は、音楽を下げる合図を出す（小さな音は出さない）")
	sx.queue_free()

	# ---- 2. 戦い：撃つ音・当たる音 ----
	var g := make("gunner")
	stand(g, 6.0)
	g.perform("normal")
	tick(g, 0.2, 0.02)
	check(g.sfx.played.has("shot") and not g.sfx.played.has("slash"), "ガンナー：撃つと「ぱん」（斬る音ではない）%s" % str(g.sfx.played))
	tick(g, 1.0)
	check(g.sfx.played.has("hit"), "ガンナー：弾が当たると、当たりの音")
	g.queue_free()

	var mg := make("mage")
	stand(mg, 6.0)
	mg.perform("normal")
	tick(mg, 0.3)
	check(mg.sfx.played.has("magic"), "魔法使い：撃つと「ひゅいーん」")
	tick(mg, 1.6)
	check(mg.sfx.played.has("magic_hit"), "魔法使い：当たると「きらきら」")
	mg.queue_free()

	var sw := make("hero_swordsman")
	stand(sw, 1.0)
	sw.attack()
	check(sw.sfx.played.has("slash") and sw.sfx.played.has("hit"), "剣士：斬る音と、当たりの音")
	sw.actions.reset()
	sw.sfx.played = []
	sw.sfx.last_play = {}
	sw.gauge.charge(99999.0)
	sw.perform("ultimate")
	tick(sw, 1.6)
	check(sw.sfx.played.has("heavy"), "必殺技が当たると、低い「ずどん」も重ねる")

	# ---- 3. ボスの足音・距離・AIの味方 ----
	var a: RefCounted = sw.audio
	var stride := float(sw.boss_model.cfg.get("walk_cycle_m", 5.5)) * 0.5
	sw.player.position = Vector3(sw.boss.position.x, sw.ground_y, sw.boss.position.z + 4.0)
	sw.motion.speed_now = 2.0
	sw.motion.height = 0.0
	sw.motion.walk_dist = 0.1
	a.update(0.016)
	sw.sfx.played = []
	sw.sfx.last_play = {}
	sw.motion.walk_dist = stride * 0.9
	a.update(0.016)
	check(not sw.sfx.played.has("boss_step"), "1歩に足りなければ、足音は出ない")
	sw.motion.walk_dist = stride * 1.05
	a.update(0.016)
	check(sw.sfx.played.has("boss_step") and is_equal_approx(float(a.log.back()[1]), 0.0), "1歩ごとに足音（近くでは、そのままの大きさ）")
	sw.player.position = Vector3(sw.boss.position.x, sw.ground_y, sw.boss.position.z + 60.0)
	sw.sfx.last_play = {}
	sw.motion.walk_dist = stride * 2.05
	a.update(0.016)
	check(float(a.log.back()[1]) <= float(cfg["battle"]["far_db"]) + 0.01, "遠いと、足音は小さい（%.1f dB）" % float(a.log.back()[1]))
	sw.motion.speed_now = 0.1
	sw.sfx.played = []
	sw.sfx.last_play = {}
	sw.motion.walk_dist = stride * 3.05
	a.update(0.016)
	check(not sw.sfx.played.has("boss_step"), "ほとんど止まっている時は、足音を出さない")
	var bc: Dictionary = cfg["battle"]
	check(is_equal_approx(BattleAudio.distance_db(3.0, bc), 0.0) and BattleAudio.distance_db(20.0, bc) < 0.0 and is_equal_approx(BattleAudio.distance_db(999.0, bc), float(bc["far_db"])), "遠いほど小さく（近く0・中くらい・遠くで far_db）")
	sw.player.position = Vector3(0, sw.ground_y, 0)
	check(is_equal_approx(a.slot_db(str(sw._my_slot()), Vector2(30, 30)), 0.0) and a.slot_db("p_ai", Vector2(1, 0)) <= float(bc["ai_db"]) + 0.01, "自分の音はそのまま、AIの味方の音は小さく")

	# ---- 4. 覚醒・倒れた・音楽の合図 ----
	var cues: Array = []
	sw.music_cue.connect(func(c: String): cues.append(c))
	sw.sfx.played = []
	sw.sfx.last_play = {}
	sw._on_boss_fall()
	sw._on_boss_awake()
	check(cues == ["fall", "awake"], "音楽の合図：ボスが倒れた（fall）・覚醒（awake）%s" % str(cues))
	check(sw.sfx.played.has("roar"), "覚醒すると、雄たけび")
	sw.queue_free()

	var t := make("gunner", true)
	var slots: Array = t.ai_allies.keys()
	var al: Dictionary = t.ai_allies[slots[0]]
	al["hp"] = 0.0
	al["downed"] = true
	t.revive_sys.update(0.05)
	check(t.sfx.played.has("down"), "味方が倒れると、倒れた音")
	t.sfx.last_play = {}
	t.revive_sys._revive(str(slots[0]))
	check(t.sfx.played.has("revive"), "起きると、上がるきらきらの音")
	t.queue_free()

	# ---- 5・6. ガチャ・せってい（画面の流れ） ----
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	DirAccess.remove_absolute(TEMP_AUDIO)
	var flow: Node = (load(FLOW_SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = TEMP_SAVE
	flow.config["ai_picks_path"] = TEMP_AI
	flow.config["audio_settings_path"] = TEMP_AUDIO
	root.add_child(flow)
	await process_frame
	await process_frame
	flow.goto("lobby")
	flow.save["coins"] = 250
	flow.lobby_ui.nav_press("gacha")
	await process_frame
	var ui: RefCounted = flow.gacha_ui
	var ms: Node = flow.menu_sfx
	ms.played = []
	ms.last_play = {}
	var hp: Vector2 = ui.stage.hero_screen_point()
	ui.grab(hp, true)
	check(ms.played.has("pull"), "ガチャ：剣士をつかむと、弓のきしみ")
	var tick_pitch: Array = []
	for i in range(1, 5):
		ms.last_play = {}
		ui.drag(hp + Vector2(0, 300.0 * 0.25 * float(i) + 2.0))
		for p in ms.pool:
			if (p as AudioStreamPlayer).stream == ms.streams.get("pull_tick") and not tick_pitch.has((p as AudioStreamPlayer).pitch_scale):
				tick_pitch.append((p as AudioStreamPlayer).pitch_scale)
	check(ms.played.count("pull_tick") == 4 and tick_pitch.size() >= 3 and tick_pitch.max() > tick_pitch.min(), "25%%ごとに「こつ」（4回。強いほど高い：%s）" % str(tick_pitch))
	ms.last_play = {}
	ui.release(hp + Vector2(0, 300))
	check(ms.played.has("launch"), "離すと、弦の「びゅん」")
	ms.last_play = {}
	ui.stage.finish_now()
	var r := str(ui.last_result.get("rarity", ""))
	check(int(ui.last_result.get("kills", 0)) == 0 or ms.played.has("gacha_hit"), "小鬼を斬ると「ざしゅ」")
	var want := str({"N": "reveal_n", "R": "reveal_r", "SR": "reveal_sr", "SSR": "reveal_ssr"}.get(r, "?"))
	check(ms.played.has(want), "結果は、レア度（%s）ごとの音：%s" % [r, want])

	flow.goto("account")
	await process_frame
	var panel: Control = flow.panels["account"]
	var card := panel.find_child("SettingsCard", true, false)
	var sm := panel.find_child("Slider_music", true, false) as HSlider
	var ss := panel.find_child("Slider_sfx", true, false) as HSlider
	check(card != null and sm != null and ss != null and card.find_child("QualityButton", true, false) == flow.quality_button, "プロフィールに「せってい」（音楽・効果音のすべりバー・画質のボタン）")
	check(str(flow.quality_button.text).begins_with("がしつ："), "画質のボタンは、前と同じに使える：" + flow.quality_button.text)
	check(panel.find_child("*", true, false) != null and panel.get_child(1) is ScrollContainer, "プロフィールの画面は、はみ出したら縦にスクロールできる")
	check(is_equal_approx(sm.value, 0.8) and is_equal_approx(ss.value, 1.0), "はじめは、音楽80%・効果音100%")
	sm.value = 0.4
	check(is_equal_approx(flow.bgm.user_volume, 0.4) and is_equal_approx(float(AudioSettings.load_settings(TEMP_AUDIO, {})["music"]), 0.4), "音楽のバーを動かすと、すぐに反映して保存")
	ms.played = []
	ms.last_play = {}
	ss.value = 0.6
	check(is_equal_approx(flow.menu_sfx.user_volume, 0.6) and ms.played.has("click"), "効果音のバーを動かすと、反映して「ぽこっ」と大きさを聞かせる")
	var mute := panel.find_child("Mute_sfx", true, false) as Button
	mute.pressed.emit()
	check(is_equal_approx(flow.menu_sfx.user_volume, 0.0) and is_equal_approx(ss.value, 0.0), "スピーカーのアイコンで消す（0%）")
	mute.pressed.emit()
	check(is_equal_approx(flow.menu_sfx.user_volume, 0.6) and is_equal_approx(ss.value, 0.6), "もう一度押すと、前の大きさにもどす")
	var lbl := card.find_child("Row_music", true, false)
	var texts: Array = []
	for c in lbl.find_children("*", "Label", true, false):
		texts.append((c as Label).text)
	check(texts.has("40%"), "大きさは「40%%」のように出る %s" % str(texts))
	flow.queue_free()
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	DirAccess.remove_absolute(TEMP_AUDIO)

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
