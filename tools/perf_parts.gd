extends SceneTree
## 版94：画面の部品ごとの重さ（描く重さの目安）。部品を1つずつ消して、1コマの時間・描画の回数・三角形の数がどれだけ減るかを測る。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_parts.gd -- 出力.json [画質] [lobby/battle] [quick]
## quick：部品ごとは測らず、全部ありの数だけ（直す前と後を比べる時）
## 注意：xvfb の llvmpipe は CPU で絵を描く。時間は「部品どうしを比べる」ためだけに使う（スマホの GPU の時間とはちがう）。
## 見た目は変えない（測るあいだだけ消して、もとにもどす）。

const SCENE := "res://scenes/game_flow.tscn"
const N := 50


func mon(m: int) -> float:
	return float(Performance.get_monitor(m))


func measure() -> Dictionary:
	for i in 6:
		await process_frame
	var ft := []
	var dc := 0.0
	var pr := 0.0
	var last := Time.get_ticks_usec()
	for i in N:
		await process_frame
		var t := Time.get_ticks_usec()
		ft.append((t - last) / 1000.0)
		last = t
		dc += mon(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		pr += mon(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	ft.sort()
	return {"frame_ms": snappedf(float(ft[ft.size() / 2]), 0.1), "draw_calls": roundi(dc / N), "primitives": roundi(pr / N)}


## 部品の一覧：名前 → 消す時に見えなくするノードの配列
func battle_parts(b: Node) -> Dictionary:
	var parts := {}
	var city: Node = b.map_root.get_node_or_null("City") if b.map_root != null else null
	if city != null:
		for mi in city.find_children("*", "MeshInstance3D", true, false):
			parts["map:" + str(mi.get_meta("map_part", mi.name))] = [mi]
	if b.map_root != null and b.map_root.get_node_or_null("Border") != null:
		parts["map:Border"] = [b.map_root.get_node("Border")]
	parts["boss"] = [b.boss]
	if b.sub_crowd != null:
		parts["sub_crowd"] = [b.sub_crowd]
	var chars := []
	if b.char_view != null:
		chars.append(b.char_view)
	for slot in b.other_views:
		var v: Variant = b.other_views[slot]
		if v is Node3D:
			chars.append(v)
	parts["characters(4)"] = chars
	return parts


func lobby_parts(st: Node) -> Dictionary:
	var parts := {}
	var units := []
	for u in st.units:
		units.append(u["holder"])
	parts["characters(4)"] = units
	for c in st.get_children():
		if c is Camera3D or c is WorldEnvironment or c is DirectionalLight3D:
			continue
		if str(c.name).begins_with("Unit_"):
			continue
		var k := "lobby:" + str(c.name)
		if not parts.has(k):
			parts[k] = []
		(parts[k] as Array).append(c)
	return parts


func toggle_all(nodes: Array, on: bool) -> void:
	for n in nodes:
		if n is Node3D and is_instance_valid(n):
			(n as Node3D).visible = on


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var qname := args[1] if args.size() > 1 else "low"
	var where := args[2] if args.size() > 2 else "battle"
	OS.low_processor_usage_mode = false
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.quality_name = qname
	flow._apply_quality()
	flow.goto("lobby")
	for i in 90:
		await process_frame
	var report := {"quality": qname, "where": where, "parts": {}}
	var parts := {}
	var sun: DirectionalLight3D = null
	var env: Environment = null
	var overlay: CanvasItem = null
	if where == "battle":
		flow.play()
		for i in 5:
			await process_frame
		var b: Node = flow.battle
		b.start_round()
		for i in 90:
			await process_frame
		b.ai_enabled = false  # 部品を消している間、動きで重さが変わらないように、キャラは止める（描く重さだけを見る）
		b.set_process(false)
		parts = battle_parts(b)
		sun = b.sun
		env = b.camera.environment
		overlay = b.overlay
	else:
		var st: Node = flow.lobby_stage
		parts = lobby_parts(st)
		for n in st.find_children("*", "DirectionalLight3D", true, false):
			sun = n
		env = st.get_viewport().world_3d.environment if st.get_viewport().world_3d != null else null
		if env == null and st.camera != null:
			env = st.camera.environment
	var base := await measure()
	report["all_on"] = base
	if args.size() > 3 and args[3] == "quick":
		var f0 := FileAccess.open(out_path, FileAccess.WRITE)
		f0.store_string(JSON.stringify(report, "  "))
		f0.close()
		print("PARTS ", out_path)
		quit(0)
		return
	for k in parts:
		toggle_all(parts[k], false)
		var m := await measure()
		toggle_all(parts[k], true)
		report["parts"][k] = {"frame_ms_saved": snappedf(float(base["frame_ms"]) - float(m["frame_ms"]), 0.1), "draw_calls": int(base["draw_calls"]) - int(m["draw_calls"]), "primitives": int(base["primitives"]) - int(m["primitives"])}
	if sun != null:
		var had := sun.shadow_enabled
		sun.shadow_enabled = false
		var m2 := await measure()
		sun.shadow_enabled = had
		report["parts"]["shadows(sun)"] = {"was_on": had, "frame_ms_saved": snappedf(float(base["frame_ms"]) - float(m2["frame_ms"]), 0.1), "draw_calls": int(base["draw_calls"]) - int(m2["draw_calls"]), "primitives": int(base["primitives"]) - int(m2["primitives"])}
	if env != null:
		var bg := env.background_mode
		env.background_mode = Environment.BG_CLEAR_COLOR
		var fog := env.fog_enabled
		var m3 := await measure()
		env.background_mode = bg
		report["parts"]["sky(background)"] = {"frame_ms_saved": snappedf(float(base["frame_ms"]) - float(m3["frame_ms"]), 0.1), "draw_calls": int(base["draw_calls"]) - int(m3["draw_calls"])}
		env.fog_enabled = false
		var m4 := await measure()
		env.fog_enabled = fog
		report["parts"]["fog"] = {"frame_ms_saved": snappedf(float(base["frame_ms"]) - float(m4["frame_ms"]), 0.1)}
	if overlay != null:
		overlay.visible = false
		var m5 := await measure()
		overlay.visible = true
		report["parts"]["hud(2D)"] = {"frame_ms_saved": snappedf(float(base["frame_ms"]) - float(m5["frame_ms"]), 0.1), "draw_calls": int(base["draw_calls"]) - int(m5["draw_calls"])}
	report["all_on_again"] = await measure()
	report["viewport_3d_scale"] = root.scaling_3d_scale
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PARTS ", out_path)
	quit(0)
