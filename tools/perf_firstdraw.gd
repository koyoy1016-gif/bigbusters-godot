extends SceneTree
## 版100：はじめて描く物と、1コマだけ長い「引っかかり」を結びつける（測るだけ）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 390x844 --path . --script res://tools/perf_firstdraw.gd -- 出力.json [warm]
## 戦いで、ボスの攻撃を1つずつ出し、最後に覚醒する。毎コマ、見えている形（GeometryInstance3D）の「描き方の種類」
## （材質の設定・シェーダー・影を落とすか・形の種類）を集め、はじめて出た種類と、そのコマの長さを記録する。
## 描き方の種類がはじめて出たコマが長い＝その描き方の準備（シェーダー作り）で止まった、の目安。
## 2つめの引数に warm を入れると、戦いの始まりの「先に描いておく」（版100）を通したあとで測る。

const SCENE := "res://scenes/game_flow.tscn"
const FRAMES := 45

var seen := {}
var log_rows: Array = []


## 材質の「描き方の種類」（同じ種類なら、同じシェーダーを使う）
static func mat_key(m: Material) -> String:
	if m == null:
		return "none"
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "shader:" + (sh.resource_path.get_file() if sh != null and sh.resource_path != "" else str(sh))
	if m is BaseMaterial3D:
		var s := m as BaseMaterial3D
		return "std:t%d s%d b%d c%d bb%d vc%d em%d tex%d nd%d" % [s.transparency, s.shading_mode, s.blend_mode, s.cull_mode, s.billboard_mode, int(s.vertex_color_use_as_albedo), int(s.emission_enabled), int(s.albedo_texture != null), int(s.no_depth_test)]
	return m.get_class()


static func node_keys(g: GeometryInstance3D) -> Array:
	# 版108：骨で動く形（skin）かどうかは、描き方の種類に入れない。Compatibility の描き方（drivers/gles3/shaders/scene.glsl）には
	# 骨の種類の作り分けがなく（骨の計算は別の小さなシェーダーで先にすませる）、同じシェーダーを使うため。
	# 粒（CPUParticles3D）と MultiMesh は、たくさん並べる描き方（USE_INSTANCING）なので、別の種類にする
	var kind := "inst" if (g is CPUParticles3D or g is MultiMeshInstance3D or g is GPUParticles3D) else "mesh"
	var shadow := "sh" if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else ""
	var mats: Array = []
	if g.material_override != null:
		mats.append(g.material_override)
	elif g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
		var mi := g as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si)
			mats.append(m)
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
		var mm := (g as MultiMeshInstance3D).multimesh.mesh
		for si in mm.get_surface_count():
			mats.append(mm.surface_get_material(si))
	elif g is CPUParticles3D and (g as CPUParticles3D).mesh != null:
		var pm := (g as CPUParticles3D).mesh
		for si in pm.get_surface_count():
			mats.append(pm.surface_get_material(si))
	elif g is GPUParticles3D or g is CPUParticles3D:
		mats.append(null)
	var out := []
	for m in mats:
		out.append("%s|%s|%s" % [kind, shadow, mat_key(m)])
	return out


func visible_tree(n: Node) -> bool:
	var cur := n
	while cur != null:
		if cur is Node3D and not (cur as Node3D).visible:
			return false
		cur = cur.get_parent()
	return true


## 見えている形の、はじめて出た描き方の種類（と、その形の名前）
func new_keys() -> Array:
	var found := []
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		if not visible_tree(g):
			continue
		for k in node_keys(g as GeometryInstance3D):
			if not seen.has(k):
				seen[k] = true
				found.append("%s  ← %s" % [k, str(g.name)])
	return found


func step_frames(tag: String, n: int) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var pending := new_keys()
	for i in n:
		await process_frame
		var t := Time.get_ticks_usec()
		var dt := (t - last) / 1000.0
		worst = maxf(worst, dt)
		if not pending.is_empty():
			log_rows.append({"at": tag, "frame": i, "ms": snappedf(dt, 0.1), "new": pending})
		pending = new_keys()
		last = Time.get_ticks_usec()
	return worst


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var warm := args.size() > 1 and args[1] == "warm"
	OS.low_processor_usage_mode = false
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 30:
		await process_frame
	new_keys()  # ロビーで見えている物は、もう準備ずみ
	flow.play()
	var report := {"warm": warm}
	report["enter_worst"] = await step_frames("enter", 6)
	var b: Node = flow.battle
	if warm and b.has_method("warm_up_done"):
		while not b.warm_up_done():
			await step_frames("warm", 1)
	b.start_round()
	b.skill_time_stop_left = 0.0
	report["start_worst"] = await step_frames("start", 20)
	var per := {}
	for kind in (b.attacks_cfg["kinds"] as Dictionary).keys():
		b.force_attack(str(kind))
		per[str(kind)] = snappedf(await step_frames(str(kind), FRAMES), 0.1)
	report["attacks"] = per
	b.phase.on_total(b.phase.max1 + 1.0)
	report["awake_worst"] = snappedf(await step_frames("awake", 150), 0.1)
	report["log"] = log_rows
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("FIRSTDRAW ", out_path)
	quit(0)
