extends Node3D
## 版83：ガチャの3Dの場面。剣士（手前）を引っぱって離すと、前へ飛び出して、前の小鬼たちを斬る。
## 背景は、ロビーの空・街並み（lobby_stage.gd をそのまま使い、台とキャラは出さない）。
## 斬れたかは、剣士が通った道（と、終わりの斬撃の扇）に、小鬼が入ったかで決める（gacha_logic.gd の hits）。1体1回だけ数える。
## 合図（signal）：killed(番号, 位置)・slashed（終わりの斬撃）・finished（斬り終わって、結果へ）。

signal killed(index: int, at: Vector3)
signal slashed
signal finished

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const LobbyStage := preload("res://scripts/flow/lobby_stage.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")

var cfg: Dictionary = {}
var logic: RefCounted
var backdrop: Node3D
var camera: Camera3D
var hero: Node3D  # 剣士（入れ物。向き・位置）
var hero_view: Node3D
var enemies: Array = []  # [{node, pos(Vector2), alive, t, fly}]
var guide: Node3D
var path_mesh: MeshInstance3D
var end_ring: MeshInstance3D
var power_ring: MeshInstance3D
var power_mat: StandardMaterial3D
var pull_hint: Node3D
var phase := "idle"  # idle / aiming / dash / slash / done
var dash_from := Vector2.ZERO
var dash_to := Vector2.ZERO
var dash_dir := Vector2(0, -1)
var dash_t := 0.0
var dash_len := 1.0
var hitstop := 0.0
var shake := 0.0
var wait := 0.0
var ghost_parts: Array = []
var last_ghost := 0.0
var clock := 0.0
var ult_fx: Dictionary = {}
var cam_look := Vector3.ZERO


func setup(chars: Dictionary, gacha_logic: RefCounted) -> void:
	name = "GachaStage"
	logic = gacha_logic
	cfg = logic.cfg
	ult_fx = Actions.load_config().get("actions", {}).get("ultimate", {}).get("fx", {})
	# 背景：ロビーの空と街（台・輪は隠す）
	backdrop = LobbyStage.new()
	backdrop.setup(chars)
	for n in ["Platform", "Ring"]:
		var c := backdrop.get_node_or_null(n)
		if c != null:
			c.visible = false
	for c in backdrop.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
			c.visible = false
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh and (c as MeshInstance3D).position.distance_to(Vector3(0, 0.24, 0)) < 0.1:
			c.visible = false
	add_child(backdrop)
	_build_arena()
	_build_hero(chars)
	_build_guide()
	camera = Camera3D.new()
	camera.name = "GachaCamera"
	add_child(camera)
	cam_look = _v3("camera_look")
	camera.look_at_from_position(_v3("camera_pos"), cam_look, Vector3.UP)
	camera.current = true
	fit_camera(Vector2(648, 1152))


func _v3(key: String) -> Vector3:
	var a: Array = cfg[key]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func fit_camera(screen: Vector2) -> void:
	if camera != null:
		camera.fov = float(cfg.get("fov_portrait", 60.0)) if screen.y > screen.x else float(cfg.get("fov_landscape", 42.0))


func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_fog = true
	return m


## 戦いの場：光る輪（剣士の立つ所）
func _build_arena() -> void:
	var sp := _v3("start_pos")
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.15
	tm.rings = 48
	tm.ring_segments = 4
	tm.material = _unshaded(Color("#ffd45a"))
	pad.mesh = tm
	pad.scale = Vector3(1, 0.2, 1)
	pad.position = sp + Vector3(0, 0.03, 0)
	add_child(pad)


func _build_hero(chars: Dictionary) -> void:
	hero = Node3D.new()
	hero.name = "Hero"
	hero.position = _v3("start_pos")
	hero.rotation.y = PI  # 前（-z）を向く
	add_child(hero)
	var def := CharacterData.find(chars, "hero_swordsman")
	if not def.is_empty() and CharacterData.has_model(def):
		var v := CharacterView.new()
		if v.setup(def):
			hero.add_child(v)
			v.play_action("idle")
			hero_view = v
		else:
			v.free()


## 引いている間の見た目：飛ぶ道（金の帯）・終わりの輪（斬撃の広さ）・足もとの力の輪・うしろへの矢印（引いてね）
func _build_guide() -> void:
	guide = Node3D.new()
	guide.name = "Guide"
	add_child(guide)
	path_mesh = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	qm.orientation = PlaneMesh.FACE_Y
	var pm := _unshaded(Color(1, 0.85, 0.35, 0.45))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	pm.albedo_texture = gt
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.material = pm
	path_mesh.mesh = qm
	guide.add_child(path_mesh)
	end_ring = MeshInstance3D.new()
	var er := TorusMesh.new()
	er.inner_radius = 0.95
	er.outer_radius = 1.0
	er.rings = 40
	er.ring_segments = 4
	er.material = _unshaded(Color(1, 0.6, 0.25, 0.9))
	end_ring.mesh = er
	guide.add_child(end_ring)
	guide.visible = false
	power_ring = MeshInstance3D.new()
	var pr := TorusMesh.new()
	pr.inner_radius = 0.9
	pr.outer_radius = 1.0
	pr.rings = 40
	pr.ring_segments = 4
	power_mat = _unshaded(Color(1, 0.8, 0.3, 0.9))
	pr.material = power_mat
	power_ring.mesh = pr
	power_ring.visible = false
	add_child(power_ring)
	# うしろへの矢印（「ここを引く」）
	pull_hint = Node3D.new()
	pull_hint.name = "PullHint"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0, 0.9), Vector3(-0.55, 0, 0.2), Vector3(0.55, 0, 0.2), Vector3(-0.22, 0, 0.2), Vector3(0.22, 0, 0.2), Vector3(-0.22, 0, -0.5), Vector3(0.22, 0, -0.5)]
	for tri in [[0, 2, 1], [3, 4, 6], [3, 6, 5]]:
		for k in tri:
			st.add_vertex(pts[k])
	var am := MeshInstance3D.new()
	am.mesh = st.commit()
	am.material_override = _unshaded(Color(1, 0.85, 0.4, 0.8))
	pull_hint.add_child(am)
	pull_hint.position = _v3("start_pos") + Vector3(0, 0.05, 1.7)
	add_child(pull_hint)


## 小鬼（むらさきの小さな鬼）を作る
func _make_oni(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Oni%d" % i
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#8a6fd6").darkened(0.08 * (i % 3))
	skin.roughness = 0.6
	skin.emission_enabled = true
	skin.emission = Color.WHITE
	skin.emission_energy_multiplier = 0.0
	root.set_meta("skin", skin)
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.42
	cap.height = 1.25
	cap.material = skin
	body.mesh = cap
	body.position = Vector3(0, 0.68, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.4
	hs.height = 0.78
	hs.material = skin
	head.mesh = hs
	head.position = Vector3(0, 1.48, 0)
	root.add_child(head)
	var horn_mat := StandardMaterial3D.new()
	horn_mat.albedo_color = Color("#ffd45a")
	horn_mat.roughness = 0.4
	for sx in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.09
		cm.height = 0.32
		cm.radial_segments = 8
		cm.material = horn_mat
		horn.mesh = cm
		horn.position = Vector3(0.2 * sx, 1.86, 0)
		horn.rotation.z = -0.35 * sx
		root.add_child(horn)
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.1
		es.height = 0.2
		es.material = _unshaded(Color.WHITE)
		eye.mesh = es
		eye.position = Vector3(0.14 * sx, 1.55, 0.33)
		root.add_child(eye)
		var pupil := MeshInstance3D.new()
		var ps := SphereMesh.new()
		ps.radius = 0.05
		ps.height = 0.1
		ps.material = _unshaded(Color("#1a1020"))
		pupil.mesh = ps
		pupil.position = Vector3(0.14 * sx, 1.55, 0.42)
		root.add_child(pupil)
	var belt := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.45
	bm.bottom_radius = 0.47
	bm.height = 0.24
	bm.radial_segments = 16
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color("#f2b33a")
	bm.material = belt_mat
	belt.mesh = bm
	belt.position = Vector3(0, 0.5, 0)
	root.add_child(belt)
	var blob := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1.4, 1.4)
	bq.orientation = PlaneMesh.FACE_Y
	var blm := _unshaded(Color(0, 0, 0.05, 0.5))
	blm.albedo_texture = UiKit.soft_dot(64)
	bq.material = blm
	blob.mesh = bq
	blob.name = "Blob"
	blob.position = Vector3(0, 0.02, 0)
	root.add_child(blob)
	return root


## 新しい1回：小鬼を並べなおし、剣士をもとの場所へ
func new_round(positions: Array) -> void:
	for e in enemies:
		if is_instance_valid(e["node"]):
			(e["node"] as Node).queue_free()
	enemies = []
	for i in positions.size():
		var p: Vector2 = positions[i]
		var n := _make_oni(i)
		n.position = Vector3(p.x, 0, p.y)
		add_child(n)
		enemies.append({"node": n, "pos": p, "alive": true, "t": 0.0, "fly": Vector3.ZERO, "phase": float(i) * 0.9})
	hero.position = _v3("start_pos")
	hero.rotation.y = PI
	if hero_view != null:
		hero_view.play_action("idle")
	phase = "idle"
	guide.visible = false
	power_ring.visible = false
	pull_hint.visible = true
	cam_look = _v3("camera_look")


## 引いている：剣士を少しうしろへ、飛ぶ道と終わりの輪を出す
func set_pull(aim: Dictionary) -> void:
	phase = "aiming"
	var power := float(aim["power"])
	var dir: Vector2 = aim["dir"]
	var sp := _v3("start_pos")
	var back := -dir * (0.25 + 1.1 * float(aim.get("raw", power)))
	hero.position = sp + Vector3(back.x, 0, back.y)
	hero.rotation.y = atan2(dir.x, dir.y)
	pull_hint.visible = false
	power_ring.visible = true
	power_ring.position = hero.position + Vector3(0, 0.05, 0)
	var pk := clampf(float(aim.get("raw", power)), 0.0, 1.0)
	power_ring.scale = Vector3.ONE * (1.6 - 0.6 * pk) * Vector3(1, 0.25, 1)
	power_mat.albedo_color = Color(1, 0.85, 0.35, 0.9).lerp(Color(1, 0.3, 0.15, 1.0), pk)
	if hero_view != null:
		hero_view.play_action("charge")
	guide.visible = power > 0.0
	if power > 0.0:
		var from := Vector2(sp.x, sp.z)
		var to := from + dir * float(aim["dist"])
		var mid := (from + to) * 0.5
		var w := float(cfg.get("hit_radius", 1.5)) * 1.6
		path_mesh.position = Vector3(mid.x, 0.04, mid.y)
		path_mesh.scale = Vector3(w, 1, from.distance_to(to))
		path_mesh.rotation.y = atan2(dir.x, dir.y)
		end_ring.position = Vector3(to.x, 0.05, to.y)
		var er := float(cfg.get("end_slash_radius", 2.8))
		end_ring.scale = Vector3(er, 0.25, er)


func clear_pull() -> void:
	phase = "idle"
	hero.position = _v3("start_pos")
	hero.rotation.y = PI
	guide.visible = false
	power_ring.visible = false
	pull_hint.visible = true
	if hero_view != null:
		hero_view.play_action("idle")


## 離した：前へ飛び出して斬る
func launch(aim: Dictionary) -> void:
	var sp := _v3("start_pos")
	dash_dir = aim["dir"]
	dash_from = Vector2(hero.position.x, hero.position.z)
	dash_to = Vector2(sp.x, sp.z) + dash_dir * float(aim["dist"])
	dash_len = maxf(dash_from.distance_to(dash_to), 0.1)
	dash_t = 0.0
	last_ghost = 0.0
	phase = "dash"
	guide.visible = false
	power_ring.visible = false
	hero.rotation.y = atan2(dash_dir.x, dash_dir.y)
	if hero_view != null:
		ghost_parts = UltFx.bake_ghost(hero_view) if hero_view.is_inside_tree() else []
		hero_view.play_action("ult_slash")
		var ap: AnimationPlayer = hero_view.get("player")
		if ap != null and ap.current_animation != "":
			ap.seek(0.5, true)


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	clock += delta
	# 小鬼：ゆらゆら待つ／斬られたら、白く光って、ふっ飛んで回って消える
	for e in enemies:
		var n: Node3D = e["node"]
		if not is_instance_valid(n):
			continue
		if bool(e["alive"]):
			n.position.y = absf(sin(clock * 3.0 + float(e["phase"]))) * 0.12
			n.rotation.y = sin(clock * 1.3 + float(e["phase"])) * 0.25
		else:
			e["t"] = float(e["t"]) + delta
			var t := float(e["t"])
			var skin: StandardMaterial3D = n.get_meta("skin")
			skin.emission_energy_multiplier = maxf(0.0, 2.5 - t * 6.0)
			n.position += (e["fly"] as Vector3) * delta
			e["fly"] = (e["fly"] as Vector3) + Vector3(0, -14.0, 0) * delta
			n.rotation.x += delta * 12.0
			n.rotation.z += delta * 7.0
			n.scale = Vector3.ONE * maxf(0.01, 1.0 - smoothstep(0.35, 0.75, t))
			if t > 0.75 and n.visible:
				n.visible = false
	if pull_hint.visible:
		pull_hint.position.z = _v3("start_pos").z + 1.7 + sin(clock * 4.0) * 0.18
	# 剣士の飛び出し
	match phase:
		"dash":
			if hitstop > 0.0:
				hitstop -= delta
			else:
				var before := dash_t
				dash_t = minf(dash_len, dash_t + float(cfg.get("dash_speed", 17.0)) * delta)
				var p := dash_from.lerp(dash_to, dash_t / dash_len)
				hero.position = Vector3(p.x, 0.0, p.y)
				_check_hits(dash_from, p, false)
				# 残像（2m ごと）
				if not ghost_parts.is_empty() and dash_t - last_ghost >= 2.0:
					last_ghost = dash_t
					var xf: Transform3D = hero_view.global_transform if hero_view != null and hero_view.is_inside_tree() else Transform3D(Basis(), hero.position)
					UltFx.spawn(self, "ghost", hero.position, dash_dir, ult_fx, {"parts": ghost_parts, "xform": xf})
				if dash_t >= dash_len and before < dash_len:
					phase = "slash"
					wait = float(cfg.get("result_delay_sec", 0.7))
					_check_hits(dash_from, dash_to, true)
					UltFx.spawn(self, "slash", hero.position, dash_dir, ult_fx)
					shake = 0.25
					slashed.emit()
		"slash":
			wait -= delta
			if wait <= 0.0:
				phase = "done"
				if hero_view != null:
					hero_view.play_action("idle")
				finished.emit()
	# カメラ：飛び出した剣士を少し追う・斬った時にゆれる
	var goal_look := _v3("camera_look")
	if phase in ["dash", "slash"]:
		goal_look = goal_look.lerp(hero.position + Vector3(0, 1.0, 0), 0.45)
	cam_look = cam_look.lerp(goal_look, clampf(delta * 5.0, 0.0, 1.0))
	shake = maxf(0.0, shake - delta)
	var off := Vector3(sin(clock * 47.0), cos(clock * 53.0), 0) * shake * 0.35
	if camera != null and camera.is_inside_tree():
		camera.look_at_from_position(_v3("camera_pos") + off, cam_look, Vector3.UP)


## a→b の道（と、終わりなら扇）に入った小鬼を斬る（1体1回だけ）
func _check_hits(a: Vector2, b: Vector2, end_slash: bool) -> void:
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if not bool(e["alive"]):
			continue
		var p: Vector2 = e["pos"]
		var hit := false
		if end_slash:
			hit = logic.hits(a, b, p)
		else:
			var reach := float(cfg.get("hit_radius", 1.5)) + float(cfg.get("enemy_radius", 0.7))
			hit = Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= reach
		if hit:
			e["alive"] = false
			var away := (p - b).normalized() if (p - b).length() > 0.01 else dash_dir
			e["fly"] = Vector3(away.x * 6.0 + dash_dir.x * 4.0, 7.0, away.y * 6.0 + dash_dir.y * 4.0)
			hitstop = float(cfg.get("hitstop_sec", 0.07))
			shake = 0.18
			var at := Vector3(p.x, 1.2, p.y)
			UltFx.spawn(self, "slash", Vector3(p.x, 0, p.y), dash_dir, ult_fx.merged({"slash_radius": 1.4}, true))
			killed.emit(i, at)


## テスト用：最後まで進める
func finish_now() -> void:
	var guard := 0
	while phase in ["dash", "slash"] and guard < 2000:
		step(1.0 / 30.0)
		guard += 1


## 剣士の、画面の上の点（つかむ所）
func hero_screen_point() -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2(-9999, -9999)
	return camera.unproject_position(hero.global_position + Vector3(0, 1.5, 0))
