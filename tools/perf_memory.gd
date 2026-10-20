extends SceneTree
## 版94：ロビー → 戦い → ロビー で、どの資源（モデル・画像・音・形）がメモリに残るかを調べる（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_memory.gd -- 出力.json [くり返す回数]

const SCENE := "res://scenes/game_flow.tscn"
var frames_battle := 300
const EXT := ["glb", "gltf", "png", "jpg", "webp", "res", "tres", "tscn", "ogg", "wav", "mp3", "gdshader", "ttf", "otf"]


func mon(m: int) -> float:
	return float(Performance.get_monitor(m))


func mem() -> Dictionary:
	return {"static_mb": snappedf(mon(Performance.MEMORY_STATIC) / 1048576.0, 0.1), "texture_mb": snappedf(mon(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"buffer_mb": snappedf(mon(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1), "objects": int(mon(Performance.OBJECT_COUNT)),
			"resources": int(mon(Performance.OBJECT_RESOURCE_COUNT)), "nodes": int(mon(Performance.OBJECT_NODE_COUNT)), "orphans": int(mon(Performance.OBJECT_ORPHAN_NODE_COUNT))}


func files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var e := f.get_extension().to_lower()
		if e in EXT:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with(".") or sub in ["tests", "tools", "web", "docs", "addons"]:
			continue
		files(dir.path_join(sub), out)


func cached(all: Array) -> Array:
	var out := []
	for p in all:
		if ResourceLoader.has_cached(p):
			out.append(p)
	return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var cycles := int(args[1]) if args.size() > 1 else 3
	frames_battle = int(args[2]) if args.size() > 2 else 300
	print("MEM start")
	var all := []
	files("res://", all)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 120:
		await process_frame
	var rep := {"lobby_1": mem()}
	var a := cached(all)
	var runs := []
	for c in cycles:
		flow.play()
		for i in 5:
			await process_frame
		flow.battle.start_round()
		for i in frames_battle:
			await process_frame
		var in_battle := mem()
		var b := cached(all)
		flow.goto("lobby")
		for i in 120:
			await process_frame
		var back := mem()
		print("MEM cycle ", c, " ", back)
		var cc := cached(all)
		var stay := []
		for p in cc:
			if not a.has(p):
				stay.append(p)
		runs.append({"battle": in_battle, "back_in_lobby": back, "cached_in_battle": b.size(), "cached_back": cc.size(), "stays_after_battle": stay})
	rep["runs"] = runs
	rep["cached_lobby_1"] = a
	# 静的な覚え書き（static var）の大きさ
	var CV = load("res://scripts/characters/character_view.gd")
	var SF = load("res://scripts/characters/style_fx.gd")
	rep["static_caches"] = {"CharacterView._built_cache": CV._built_cache.size(), "StyleFx._outline_cache": SF._outline_cache.size(), "StyleFx._tex_cache": SF._tex_cache.size()}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	print("MEM ", out_path)
	quit(0)
