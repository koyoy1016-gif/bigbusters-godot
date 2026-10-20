extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v86.gd
## 版86：ボス戦らしい戦いの曲と、スマホで音が聞こえやすくする仕組み。
## 確かめること：
##   1. 戦いの曲・覚醒の曲は、作り直した長さ（24小節：戦い150BPM＝38.4秒・覚醒166BPM＝約34.7秒）で、ループする
##   2. 画面の流れ：ロビーではロビーの曲、戦いが始まると戦いの曲、覚醒で覚醒の曲（版85のつなぎのまま）
##   3. ブラウザ用の JS（web/head/05_audio.js）が、3つの書き出し設定（export_presets.cfg）に入っている
##      （iPhone の消音スイッチでも鳴らす audioSession・見えない間は止める）

const Bgm := preload("res://scripts/audio/bgm.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SCENE := "res://scenes/game_flow.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	await process_frame
	# ---- 1. 曲 ----
	var b: Node = Bgm.new()
	root.add_child(b)
	await process_frame
	var bl: float = b.stream_of("battle").get_length()
	var al: float = b.stream_of("awake").get_length()
	check(absf(bl - 24.0 * 4.0 * 60.0 / 150.0) < 0.15, "戦いの曲：24小節・150BPM（%.1f秒）" % bl)
	check(absf(al - 24.0 * 4.0 * 60.0 / 166.0) < 0.15, "覚醒の曲：24小節・166BPM（%.1f秒）" % al)
	check(b.is_loop("battle") and b.is_loop("awake") and (b.stream_of("battle") as AudioStreamOggVorbis).loop, "戦い・覚醒の曲はループする")
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/bgm/battle.ogg").size()
	check(bytes > 100000 and bytes < 800000, "戦いの曲のファイルは800KB未満（%d）" % bytes)
	b.queue_free()

	# ---- 2. 画面の流れ ----
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v86_save.json"
	flow.config["ai_picks_path"] = "user://test_v86_ai.json"
	flow.config["audio_settings_path"] = "user://test_v86_audio.json"
	root.add_child(flow)
	await process_frame
	flow.goto(Logic.LOBBY)
	await process_frame
	check(flow.bgm.track == "lobby" and flow.bgm.is_playing(), "ロビーでは、ロビーの曲")
	flow.goto(Logic.BATTLE)
	await process_frame
	if flow.battle != null and not flow.battle.round_active():
		flow.battle.start_round()
	flow._on_music_cue("battle")
	check(flow.bgm.track == "battle" and flow.bgm.is_playing(), "戦いでは、ボス戦の曲")
	flow.battle.music_cue.emit("awake")
	check(flow.bgm.track == "awake", "覚醒すると、覚醒の曲")
	flow.queue_free()
	for p in ["user://test_v86_save.json", "user://test_v86_ai.json", "user://test_v86_audio.json"]:
		DirAccess.remove_absolute(p)

	# ---- 3. ブラウザ用の JS ----
	var js := FileAccess.get_file_as_string("res://web/head/05_audio.js")
	check(js.contains("navigator.audioSession") and js.contains("'playback'") and js.contains("visibilitychange") and js.contains("suspend"), "JS：消音スイッチでも鳴らす（audioSession＝playback）・見えない間は止める")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.count("navigator.audioSession.type = 'playback'") == 3, "JS は3つの書き出し設定に入っている（tools/sync_head.py）")

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
