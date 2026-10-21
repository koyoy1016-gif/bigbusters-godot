extends SceneTree
## 版108：ふだん（夕方）と覚醒（夜）の重さをくらべる（測るだけ）。
## 画面なし（CPU の仕事だけ）：
##   godot --headless --fixed-fps 60 --path . --script res://tools/perf_awake.gd -- 出力.json [コマ数] [画質 low/high]
## 画面あり（描く仕事もふくむ。この機械は GPU がないので、描く時間は CPU で描いた時間＝くらべる用）：
##   xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --fixed-fps 60 --path . --script res://tools/perf_awake.gd -- 出力.json [コマ数] [画質]
## 同じ種（seed）・ゲームの時計は 1コマ＝1/60 秒。AI の味方とボスが自由に戦う。窓ごとに体力を大きくして、測っている間に形態が変わらないようにする。
## 覚醒は、ふつうの道すじ（与えたダメージが第1形態の体力をこえる → 倒れる → 起きる）で入れ、夜に変わりきってから測る。
## 窓ごと：1コマの時間（平均・95%・最大）・描画の回数・描いた物の数・三角形の数・描く CPU 時間・ノードの数・見えている光・見えている形・透明の形
## 4つめの引数 attacks：覚醒（夜）のまま、ボスの攻撃を1つずつ出して、攻撃ごとに同じ数を測る（5つめ：1つの攻撃のコマ数。既定 150）

const SCENE := "res://scenes/game_flow.tscn"

var sim := [1.0e7]
var added := 0


func _on_added(_n: Node) -> void:
	added += 1


func pct(arr: Array, p: float) -> float:
	var a := arr.duplicate()
	a.sort()
	return float(a[clampi(int(a.size() * p), 0, a.size() - 1)])


func avg(arr: Array) -> float:
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / maxf(1.0, float(arr.size()))


func step() -> void:
	await process_frame
	sim[0] = float(sim[0]) + 1000.0 / 60.0


func census(b: Node) -> Dictionary:
	var geo := 0
	var transparent := 0
	var lights := 0
	var particles := 0
	for n in b.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		geo += 1
		var m: Material = g.material_override
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			transparent += 1
		if g is CPUParticles3D or g is GPUParticles3D:
			particles += 1
	for n in b.find_children("*", "Light3D", true, false):
		if (n as Light3D).is_visible_in_tree():
			lights += 1
	return {"geo": geo, "transparent_override": transparent, "lights": lights, "particles": particles}


func window(b: Node, tag: String, frames: int) -> Dictionary:
	var vp := root.get_viewport_rid()
	var ft := []
	var draws := []
	var objs := []
	var prims := []
	var rcpu := []
	var last := Time.get_ticks_usec()
	var kinds := {}
	added = 0
	for i in frames:
		await step()
		var t := Time.get_ticks_usec()
		ft.append((t - last) / 1000.0)
		last = t
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
		var k := str(b.current_attack.get("kind", "")) if b.current_attack is Dictionary else ""
		kinds[k] = int(kinds.get(k, 0)) + 1
	var out := {"phase": str(b.phase.phase), "night": snappedf(float(b.tod.t), 0.01),
		"frame_avg": snappedf(avg(ft), 0.01), "frame_p95": snappedf(pct(ft, 0.95), 0.01), "frame_max": snappedf(pct(ft, 1.0), 0.01),
		"draws_avg": snappedf(avg(draws), 0.1), "draws_max": pct(draws, 1.0), "objects_avg": snappedf(avg(objs), 0.1),
		"prims_avg": int(avg(prims)), "render_cpu_avg": snappedf(avg(rcpu), 0.01), "render_cpu_p95": snappedf(pct(rcpu, 0.95), 0.01),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "added": added, "attacks": kinds}
	out.merge(census(b))
	print("AWAKE_PERF ", tag, " ", out)
	return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var frames := int(args[1]) if args.size() > 1 else 600
	var quality := args[2] if args.size() > 2 else ""
	var per_attack := args.size() > 3 and args[3] == "attacks"
	var atk_frames := int(args[4]) if args.size() > 4 else 150
	node_added.connect(_on_added)
	seed(12345)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	if quality != "":
		flow.quality_name = quality
		flow._apply_quality()
	flow.goto("lobby")
	for i in 30:
		await process_frame
	flow.play()
	for i in 5:
		await process_frame
	var b: Node = flow.battle
	b.clock_ms = func() -> float: return float(sim[0])
	b.start_round()
	for i in 60:
		await step()
	var keep1: float = b.phase.max1
	b.phase.max1 = 1.0e9  # 測っている間に倒れないように
	var rep := {"quality": quality, "frames": frames}
	rep["normal"] = await window(b, "normal", frames)
	# 覚醒：ふつうの道すじで（第1形態の体力をこえるダメージ → 倒れる → 起きる）
	b.phase.max1 = keep1
	b.my_hits = float(b.phase.max1) + 1.0
	b._recompute_boss_hp()
	var waited := 0
	var awake_ft := []
	var last := Time.get_ticks_usec()
	while not b.phase.is_awake() and waited < 900:
		await step()
		var t := Time.get_ticks_usec()
		awake_ft.append((t - last) / 1000.0)
		last = t
		waited += 1
	b.phase.max2 = 1.0e9  # 測っている間に倒しきらないように
	for i in 150:  # 夜に変わりきるまで（to_night_sec）
		await step()
		var t := Time.get_ticks_usec()
		awake_ft.append((t - last) / 1000.0)
		last = t
	rep["transition"] = {"frames": awake_ft.size(), "avg": snappedf(avg(awake_ft), 0.01), "max": snappedf(pct(awake_ft, 1.0), 0.01)}
	print("AWAKE_PERF transition ", rep["transition"])
	rep["awake"] = await window(b, "awake", frames)
	if per_attack:
		var per := {}
		for kind in (b.attacks_cfg["kinds"] as Dictionary).keys():
			b.force_attack(str(kind))
			per[str(kind)] = await window(b, "atk:" + str(kind), atk_frames)
			b.ai.interrupt(b._round_t(), 0.5)
			for i in 30:
				await step()
		rep["per_attack"] = per
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	quit(0)
