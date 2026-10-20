extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_bgm.gd
## 音楽（版85：曲の切りかえ・ループ・短い曲のあとの予約・下げる・ミュート・大きさ）と、ボタンのクリック音、
## 画面の流れ（ロビーの曲・戦いに入ると消える・戦いが始まると戦いの曲・勝ち負けの短い曲・ロビーにもどると、ロビーの曲）を確かめる。

const Bgm := preload("res://scripts/audio/bgm.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SCENE := "res://scenes/game_flow.tscn"
const TEMP_SAVE := "user://test_bgm_save.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	await process_frame
	# ---- 曲のファイル ----
	var cfg := Bgm.load_config()
	var tracks: Dictionary = cfg.get("tracks", {})
	check(tracks.has("lobby") and tracks.has("battle") and tracks.has("awake") and tracks.has("win") and tracks.has("lose") and str(cfg.get("default", "")) == "lobby", "曲：ロビー・戦い・覚醒・勝ち・負け（data/bgm.json）")
	var total := 0
	for name in tracks:
		var def: Dictionary = tracks[name]
		var st := load(str(def.get("file", ""))) as AudioStream
		check(st is AudioStreamOggVorbis, "曲が読める（Ogg）：" + str(name))
		if st != null:
			var L := st.get_length()
			if bool(def.get("loop", true)):
				check(L >= 15.0 and L <= 60.0, "ループの曲は15〜60秒：%s %.1f秒" % [name, L])
			else:
				check(L >= 2.0 and L <= 8.0, "短い曲は2〜8秒：%s %.1f秒" % [name, L])
		total += FileAccess.get_file_as_bytes(str(def.get("file", ""))).size()
	check(total > 0 and total < 2500000, "曲のファイルの合計は2.5MB未満：%d" % total)

	# ---- 音楽の部品 ----
	var b: Node = Bgm.new()
	root.add_child(b)
	await process_frame
	check(not b.is_playing(), "最初は流れていない")
	check(b.start() and b.is_playing() and b.track == "lobby", "流し始めると、ロビーの曲が流れる")
	check(b.player.stream is AudioStreamOggVorbis and (b.player.stream as AudioStreamOggVorbis).loop, "ロビーの曲はループする")
	b.step(1.0)
	check(is_equal_approx(float(b.levels[b.front]), 1.0), "少しずつ大きくなって、1秒で元の大きさ")
	var lobby_front: int = b.front
	check(b.play_track("battle") and b.track == "battle" and b.front != lobby_front, "戦いの曲へ：もう1つの再生口で始める")
	b.step(0.6)
	check(float(b.levels[lobby_front]) > 0.0 and float(b.levels[lobby_front]) < 1.0 and float(b.levels[b.front]) > 0.0 and float(b.levels[b.front]) < 1.0, "入れかえの途中は、両方が鳴っている（クロスフェード）")
	b.step(1.0)
	check(float(b.levels[lobby_front]) == 0.0 and is_equal_approx(float(b.levels[b.front]), 1.0), "入れかえが終わると、前の曲は0")
	check(not (b.players[lobby_front] as AudioStreamPlayer).playing, "前の曲は止まる")
	check(b.play_track("battle") and b.log.count("battle") == 1, "同じ曲を頼んでも、最初からにはならない")
	# 勝ちの短い曲 → ロビーの曲は、終わってから
	check(b.play_track("win", 0.0) and b.track == "win" and not b.is_loop("win"), "勝ちの短い曲（ループしない）")
	check(not (b.player.stream as AudioStreamOggVorbis).loop, "短い曲は、ループしない設定")
	b.play_track("lobby")
	check(b.track == "win" and b.pending == "lobby", "短い曲の途中にロビーの曲を頼むと、予約になる")
	var win_len: float = b.stream_of("win").get_length()
	b.step(win_len * 0.5)
	check(b.track == "win", "短い曲の途中は、そのまま")
	b.step(win_len * 0.5 + 0.1)
	check(b.track == "lobby" and b.pending == "", "短い曲が終わったら、予約したロビーの曲")
	# 下げる（大きな効果音の時）
	b.step(3.0)
	var vol0: float = (b.players[b.front] as AudioStreamPlayer).volume_db
	b.duck(-9.0, 0.2)
	check(is_equal_approx((b.players[b.front] as AudioStreamPlayer).volume_db, vol0 - 9.0), "大きな効果音で、9dB下げる")
	b.step(0.1)
	check(b.duck_db == -9.0, "少しのあいだは、下げたまま")
	b.step(1.0)
	check(b.duck_db == 0.0 and is_equal_approx((b.players[b.front] as AudioStreamPlayer).volume_db, vol0), "そのあと、元にもどる")
	# プレイヤーが決めた大きさ
	b.set_user_volume(0.5)
	check(is_equal_approx((b.players[b.front] as AudioStreamPlayer).volume_db, vol0 + linear_to_db(0.5) - linear_to_db(1.0)), "大きさ50%で、約6dB小さく")
	b.set_user_volume(0.0)
	check(not b.is_playing() and not (b.players[b.front] as AudioStreamPlayer).playing, "大きさ0%で、止まる")
	b.set_user_volume(0.8)
	check(b.is_playing() and b.track == "lobby", "0%からもどすと、頼まれていた曲が流れ直す")
	b.stop()
	check(not b.is_playing(), "止めると、止まる")
	b.muted = true
	check(not b.start() and not b.is_playing(), "ミュートにすると、流れない")
	b.muted = false
	b.stop(0.5)
	b.queue_free()

	# ---- 画面の流れ ----
	var packed := load(SCENE) as PackedScene
	check(packed != null, "画面の流れのシーンが読める")
	if packed != null:
		var flow: Node = packed.instantiate()
		flow.config = Flow.load_config()
		flow.config["save_path"] = TEMP_SAVE
		flow.config["ai_picks_path"] = "user://test_bgm_ai_picks.json"
		flow.config["audio_settings_path"] = "user://test_bgm_audio.json"
		DirAccess.remove_absolute("user://test_bgm_ai_picks.json")
		DirAccess.remove_absolute("user://test_bgm_audio.json")
		root.add_child(flow)
		if flow.panels.is_empty():
			flow._ready()
		await process_frame
		check(flow.bgm != null and flow.menu_sfx != null, "画面の流れに、音楽とクリック音がある")
		var btn: Button = flow._make_button("テスト", [200, 80], func(): pass)
		root.add_child(btn)
		flow.menu_sfx.played = []
		btn.pressed.emit()
		check(flow.menu_sfx.played.has("click"), "ボタンを押すと、クリック音が鳴る")
		flow.goto(Logic.LOBBY)
		await process_frame
		check(flow.bgm.is_playing() and flow.bgm.track == "lobby", "ロビーに出ると、ロビーの曲が流れる")
		flow.goto(Logic.BATTLE)
		await process_frame
		check(flow.battle != null, "戦いが始まった")
		if flow.battle != null:
			if not flow.battle.round_active():
				flow.battle.start_round()
			flow._on_music_cue("battle")
			check(flow.bgm.track == "battle" and flow.bgm.is_playing(), "戦いの間は、戦いの曲")
			flow.battle.music_cue.emit("fall")
			check(flow.bgm.duck_db < -10.0, "ボスが倒れると、音楽を下げる")
			flow.battle.music_cue.emit("awake")
			check(flow.bgm.track == "awake", "覚醒すると、覚醒の曲")
			flow._on_round_ended(true)
			check(flow.bgm.track == "win", "勝つと、勝ちの短い曲")
		flow.goto(Logic.LOBBY)
		await process_frame
		check(flow.bgm.is_playing() and (flow.bgm.track == "lobby" or flow.bgm.pending == "lobby"), "戦いのあとロビーに戻ると、（短い曲のあと）ロビーの曲")
		# 音の大きさの設定（保存して、すぐに反映）
		flow.set_audio_volume("music", 0.3)
		flow.set_audio_volume("sfx", 0.6)
		check(is_equal_approx(flow.bgm.user_volume, 0.3) and is_equal_approx(flow.menu_sfx.user_volume, 0.6), "音の大きさを変えると、すぐに反映")
		var AudioSettings := load("res://scripts/audio/audio_settings.gd")
		var saved: Dictionary = AudioSettings.load_settings("user://test_bgm_audio.json", cfg)
		check(is_equal_approx(float(saved["music"]), 0.3) and is_equal_approx(float(saved["sfx"]), 0.6), "音の大きさは、この端末に保存される")
		flow.queue_free()
		DirAccess.remove_absolute("user://test_bgm_audio.json")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
