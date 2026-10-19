extends SceneTree
## ハイライトの再生の写真を撮る（見た目の確認用）。戦いをAIつきでしばらく回し、記録からハイライトを作って、何枚か撮る。
## xvfb-run -s "-screen 0 800x800x24" godot --path . --rendering-driver opengl3 --script res://tools/shot_highlight.gd -- 出力の頭 [戦うフレーム数]
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Replay := preload("res://scripts/flow/highlight_replay.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://highlight"
	var frames := int(args[1]) if args.size() > 1 else 900
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	s.start_round()
	for i in frames:
		await process_frame
	var info: Dictionary = s.highlight_data()
	print("HIGHLIGHT slot=", info.get("slot", ""), " boss_track=", (info.get("boss_track", []) as Array).size(), " points=", (info.get("points", []) as Array).size())
	if info.is_empty():
		quit(1)
		return
	var fcfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_flow.json"))
	root.remove_child(s)
	var rep := Replay.new()
	root.add_child(rep)
	rep.size = Vector2(560, 560)
	var ccfg := CharacterData.load_config()
	var hero := CharacterData.find(ccfg, str(ccfg["player_character"]))
	rep.setup(info["points"], info["boss"], float(info["bounds"]), info["color"], info["config"], fcfg, hero, info.get("boss_track", []))
	for shot in 3:
		for i in 30:
			rep.advance(1.0 / 30.0)
			await process_frame
		var img := root.get_texture().get_image()
		var path := out + "_%d.png" % shot
		img.save_png(path)
		print("SHOT ", path, " boss_kind=", str(Replay.Recorder.boss_at(rep.boss_track, (rep.points[0] as Vector3).x + rep.play_time).get("kind", "")))
	quit(0)
