extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_bgm.gd
## メニューのBGM（ファイル、ループ、ミュート）と、ボタンのクリック音、戦いの最中にBGMを止めること、を確かめる。

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
	# 音のファイル
	var cfg := Bgm.load_config()
	check(cfg.has("file") and cfg.has("volume_db"), "BGMの設定（data/bgm.json）が読める")
	var st := load(str(cfg.get("file", ""))) as AudioStreamWAV
	check(st != null, "BGMの音が読める")
	if st != null:
		check(st.get_length() >= 5.0 and st.get_length() <= 30.0, "BGMは短い（5〜30秒）：" + str(st.get_length()))
	var bytes := FileAccess.get_file_as_bytes(str(cfg.get("file", ""))).size()
	check(bytes > 0 and bytes < 1000000, "BGMのファイルは1MB未満：" + str(bytes))

	# BGMの部品
	var b: Node = Bgm.new()
	root.add_child(b)
	b._ready()
	await process_frame
	check(not b.is_playing(), "最初は流れていない")
	check(b.start() and b.is_playing(), "流し始めると、流れる")
	check(b.player.stream != null and b.player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGMはループして流れる")
	b.stop()
	check(not b.is_playing(), "止めると、止まる")
	b.muted = true
	check(not b.start() and not b.is_playing(), "ミュートにすると、流れない")
	b.muted = false
	b.queue_free()

	# 画面の流れ：ボタンのクリック音と、戦いの最中のBGM
	var packed := load(SCENE) as PackedScene
	check(packed != null, "画面の流れのシーンが読める")
	if packed != null:
		var flow: Node = packed.instantiate()
		flow.config = Flow.load_config()
		flow.config["save_path"] = TEMP_SAVE
		flow.config["ai_picks_path"] = "user://test_bgm_ai_picks.json"
		DirAccess.remove_absolute("user://test_bgm_ai_picks.json")
		root.add_child(flow)
		if flow.panels.is_empty():
			flow._ready()
		await process_frame
		check(flow.bgm != null and flow.menu_sfx != null, "画面の流れに、BGMとクリック音がある")
		var btn: Button = flow._make_button("テスト", [200, 80], func(): pass)
		root.add_child(btn)
		flow.menu_sfx.played = []
		btn.pressed.emit()
		check(flow.menu_sfx.played.has("click"), "ボタンを押すと、クリック音が鳴る")
		flow.goto(Logic.LOBBY)
		await process_frame
		check(flow.bgm.is_playing(), "ロビーに出ると、BGMが流れる")
		flow.goto(Logic.BATTLE)
		await process_frame
		check(not flow.bgm.is_playing(), "戦いの最中は、BGMが止まる")
		flow.goto(Logic.LOBBY)
		await process_frame
		check(flow.bgm.is_playing(), "戦いのあとロビーに戻ると、BGMが流れ直す")
		flow.queue_free()

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
