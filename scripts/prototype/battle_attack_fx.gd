extends RefCounted
## ボスの攻撃の見た目（予告の面・雨・巨大酒瓶ライドの瓶・飛ぶバット・しずく・ぬれた床・酒瓶・ライター・火・火花・跳ぶ影）。当たりやダメージは決めない（見せるだけ）
## stick_prototype.gd（まとめ役。状態の変数はそちら）から分けた部品。本体の変数・関数は b. で使う。動きは分ける前と同じ。

const CONFIG_PATH := "res://data/prototype_stick.json"
const FIREBASE_CONFIG_PATH := "res://data/firebase_config.json"
const SLOTS := ["p1", "p2", "p3", "p4"]
const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const SfxPlayer := preload("res://scripts/audio/sfx.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Sync := preload("res://scripts/network/position_sync.gd")
const BossSync := preload("res://scripts/network/boss_sync.gd")
const BossModel := preload("res://scripts/boss/boss_model.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const CrowdState := preload("res://scripts/combat/crowd_state.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")
const BossMotion := preload("res://scripts/combat/boss_motion.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const BossRage := preload("res://scripts/combat/boss_rage.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）
## 跳んでいるボスの影（地面に、高さに合わせた大きさで）
var _shadow: MeshInstance3D
## 酒の雨：一升瓶をふり上げた瞬間に、しぶきを空へまく（必殺技の大雨は、始めに1回）
var _last_spray_key := ""
## 床に置く、扇・輪の形（半径1。種類と角度ごとに1回だけ作る）
var _floor_meshes := {}
## ---- 版68：酒の大雨の雨（ステージ全体に、酒のしずくが降る。見た目だけ。当たりは style "rain" の当たり場所） ----
var rain_seen := false
## 投げたバット（ボスのバットと同じ形を、大きさをそろえて作る）
var _fly_bat: Node3D
var _sake_mat: StandardMaterial3D
var _wet_mesh: CylinderMesh
var _fire_nodes: Array = []
var _fx_pool: Array = []
var _fx_next := 0
var _lighter: Node3D


func _init(main: StickPrototype) -> void:
	b = main


## pool を渡さなければ、本体の hazard_nodes（予告の面）を使う
func _hazard_node(i: int, pool_in: Variant = null, prefix: String = "Hazard") -> MeshInstance3D:
	var pool: Array = b.hazard_nodes if pool_in == null else pool_in
	while pool.size() <= i:
		var n := MeshInstance3D.new()
		n.name = prefix + str(pool.size())
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		n.set_meta("mat", m)
		var zm := ShaderMaterial.new()
		zm.shader = WARNING_SHADER
		n.set_meta("zmat", zm)
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(n)
		pool.append(n)
	return pool[i]


func _floor_mesh(key: String, half: float, inner: float) -> ArrayMesh:
	if _floor_meshes.has(key):
		return _floor_meshes[key]
	var segs := maxi(8, int(ceil(half * 2.0 / TAU * 40.0)))
	var v := PackedVector3Array()
	for i in segs:
		var a0 := -half + 2.0 * half * float(i) / float(segs)
		var a1 := -half + 2.0 * half * float(i + 1) / float(segs)
		var o0 := Vector3(sin(a0), 0.0, cos(a0))
		var o1 := Vector3(sin(a1), 0.0, cos(a1))
		if inner <= 0.0:
			v.append_array([Vector3.ZERO, o0, o1])
		else:
			v.append_array([o0 * inner, o0, o1, o0 * inner, o1, o1 * inner])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_floor_meshes[key] = m
	return m


## 当たり場所の形の見た目（予告の面）を、node に置く。grow：予告の進み（0〜1。広がりの割合。1 で全体）
func _place_zone(n: MeshInstance3D, h: Dictionary, grow: float, y: float) -> void:
	var m: StandardMaterial3D = n.get_meta("mat")
	var shape := str(h["shape"])
	var key := shape
	var g := maxf(grow, 0.02)
	n.rotation = Vector3.ZERO
	match shape:
		"sector":
			key = "sector:%.3f" % float(h["half"])
			n.mesh = _floor_mesh(key, float(h["half"]), 0.0)
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.rotation.y = float(h["yaw"])
			n.scale = Vector3.ONE * float(h["r"]) * g
		"ring":
			# 輪：内側（安全な所）から外へ広がる。外の半径が変わるので、形は段階ごとに作る（20段）
			var r_in := float(h["r_in"])
			var outer := r_in + (float(h["r"]) - r_in) * (roundf(g * 20.0) / 20.0 if grow < 1.0 else 1.0)
			var ratio := snappedf(r_in / maxf(outer, r_in + 0.01), 0.02)  # 形の種類を増やしすぎない
			key = "ring:%.2f" % ratio
			n.mesh = _floor_mesh(key, PI, ratio)
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.scale = Vector3.ONE * maxf(outer, r_in + 0.01)
		"obox", "box":
			key = "box"
			if not _floor_meshes.has("box"):
				var bm := BoxMesh.new()
				bm.size = Vector3.ONE
				_floor_meshes["box"] = bm
			n.mesh = _floor_meshes["box"]
			if shape == "obox":
				# 向きのある帯：ボスの側から、前へのびる
				var yaw := float(h["yaw"])
				var f := Attacks.fwd_of(yaw)
				var hz := float(h["hz"])
				var c := Vector2(float(h["x"]), float(h["z"])) - f * hz * (1.0 - g)
				n.position = Vector3(c.x, y, c.y)
				n.rotation.y = yaw
				n.scale = Vector3(float(h["hx"]) * 2.0, 0.04, hz * 2.0 * g)
			else:
				n.position = Vector3(0.0, y, float(h["band_z"]))
				n.scale = Vector3(float(h["band_half"]) * 2.0, 0.04, float(h["hz"]) * 2.0 * g)
		_:
			key = "disc"
			if not _floor_meshes.has("disc"):
				_floor_meshes["disc"] = _floor_mesh("disc_f", PI, 0.0)
			n.mesh = _floor_meshes["disc"]
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.scale = Vector3.ONE * float(h["r"]) * g
	n.material_override = m
	# 予告の見た目（版60）：丸はオレンジの円、帯はオレンジの帯、ライドの道はピンクの帯＋矢印
	var zm: ShaderMaterial = n.get_meta("zmat")
	var zs: Dictionary = b.attacks_cfg.get("zone_style", {})
	var ride := str(h.get("style", "")) == "ride_lane"
	var safe := str(h.get("style", "")) == "safe"
	var look: Dictionary = zs.get("ride" if ride else ("safe" if safe else "attack"), {})
	zm.set_shader_parameter("fill_color", Color(str(look.get("fill", "#ff6b2852"))))
	zm.set_shader_parameter("rim_color", Color(str(look.get("rim", "#ffcfa0f2"))))
	zm.set_shader_parameter("mode", 2 if ride else (1 if key == "box" else 0))
	zm.set_shader_parameter("grow_axis", 1 if shape == "obox" else 0)
	zm.set_shader_parameter("inner", snappedf(float(h["r_in"]) / maxf(float(h["r"]), 0.01), 0.001) if shape == "ring" else 0.0)
	zm.set_shader_parameter("size", Vector2(n.scale.x, n.scale.z))
	zm.set_shader_parameter("dir", signf(float(h.get("dir", 1.0))) if float(h.get("dir", 1.0)) != 0.0 else 1.0)
	for sk in ["stripe_width", "rim_width", "arrow_spacing", "arrow_speed"]:
		if zs.has(sk):
			zm.set_shader_parameter(sk, float(zs[sk]))
	n.material_override = zm


## 当たり場所の見た目：予告は、うすい全体の面＋中から広がる濃い面（広がりきったら当たる）。当たる瞬間は、明るい色
func _show_hazards(hz: Array) -> void:
	var fill_used := 0
	var drop_used := 0
	var bat_used := false
	var bottle_used := 0
	var lighter_used := false
	rain_seen = false
	for i in hz.size():
		var h: Dictionary = hz[i]
		var n := _hazard_node(i)
		var m: StandardMaterial3D = n.get_meta("mat")
		var style := str(h["style"])
		var active := bool(h["active"])
		if style == "paper":
			if n.get_meta("kind", "") != "paper":
				n.set_meta("kind", "paper")
				var bk := BoxMesh.new()
				bk.size = Vector3.ONE
				n.mesh = bk
				n.material_override = m
			n.position = Vector3(float(h["x"]), 0.9, float(h["z"]))
			n.scale = Vector3(0.9, 0.08, 1.2)
			n.rotation = Vector3(0.3, float(h["age"]) * 9.0, 0.2)
			m.albedo_color = Color(str(b.attacks_cfg["paper_color"]))
			n.visible = true
			continue
		n.set_meta("kind", "zone")
		if style == "bat":
			# 投げたバット：回りながら飛ぶ（当たり場所の輪は出さない）
			var fb := _flying_bat()
			fb.visible = true
			fb.global_position = Vector3(float(h["x"]), float(b.attacks_cfg["kinds"]["bat_throw"].get("fly_height", 2.6)), float(h["z"]))
			fb.rotation = Vector3(0.0, float(h.get("spin", 0.0)), PI * 0.5)
			bat_used = true
			n.visible = false
			continue
		if style == "sake":
			# 酒のしずく：輪の上から落ちてくる（落ちきった瞬間に当たる）。当たったら、床がぬれる
			if not active:
				var d := _drop_node(drop_used)
				drop_used += 1
				var tl := float(h["tele"])
				d.position = Vector3(float(h["x"]), 0.4 + float(b.attacks_cfg.get("drop_height", 14.0)) * (1.0 - tl * tl), float(h["z"]))
				d.visible = true
			elif not b.puddle_seen.has(str(h["id"])):
				b.puddle_seen[str(h["id"])] = true
				_add_puddle(Vector3(float(h["x"]), 0.0, float(h["z"])), float(h["r"]), str(h["id"]))
		if style == "bottle" and active and str(h["id"]).begins_with("rb") and not b._landed.has(str(h["id"])):
			# 巨大酒瓶ライドで投げた瓶が、地面で割れる（ガラスの破片。酒だまりは残さない）
			b._landed[str(h["id"])] = true
			_burst_fx(Vector3(float(h["x"]), 0.3, float(h["z"])), "glass")
			b._play_sfx("thud")
		if style == "bottle" and h.has("bottle"):
			# 飛んでいる酒瓶（回りながら）
			var bn := _bottle_node(bottle_used)
			bottle_used += 1
			bn.position = h["bottle"]
			bn.rotation = Vector3(float(h.get("spin", 0.0)), 0.0, float(h.get("spin", 0.0)) * 0.6)
			bn.scale = Vector3.ONE * 1.4
			bn.visible = true
		if style == "lighter" and h.has("lighter"):
			var ln := _lighter_node()
			ln.position = h["lighter"]
			ln.rotation = Vector3(b._round_t() * 8.0, 0.0, 0.0)
			ln.visible = true
			lighter_used = true
		if style == "fire":
			# 燃えている所：炎は _update_fires。当たり場所の面は出さない（炎が見えるので）
			n.visible = false
			continue
		if style == "hand" and active:
			n.visible = false
			continue
		if style == "rain":
			# 酒の大雨：ステージ全体なので、床の面は出さない（雨のしずくを全体に降らせる。安全地帯は style "safe" の円）
			rain_seen = true
			n.visible = false
			continue
		if style == "ride":
			# 走っている瓶そのものが見えるので、当たり場所の面は出さない（道の予告は ride_lane）
			n.visible = false
			continue
		var tele := float(h["tele"])
		_place_zone(n, h, 1.0, 0.03)
		var zm: ShaderMaterial = n.get_meta("zmat")
		zm.set_shader_parameter("progress", tele)
		zm.set_shader_parameter("active", 1.0 if active else 0.0)
		# 害のない予告（酒の大雨の落ちる前など）はうすく
		zm.set_shader_parameter("strength", float(b.attacks_cfg["kinds"]["flyers"].get("tele_alpha", 0.3)) * (0.5 + 0.5 * tele) / 0.3 if float(h.get("power", 1.0)) <= 0.0 and style != "safe" else 1.0)
		n.visible = true
	for i in range(hz.size(), b.hazard_nodes.size()):
		(b.hazard_nodes[i] as Node3D).visible = false
	for i in range(fill_used, b.hazard_fill_nodes.size()):
		(b.hazard_fill_nodes[i] as Node3D).visible = false
	for i in range(drop_used, b.drop_nodes.size()):
		(b.drop_nodes[i] as Node3D).visible = false
	if not bat_used and _fly_bat != null:
		_fly_bat.visible = false
	for i in range(bottle_used, b._bottle_nodes.size()):
		(b._bottle_nodes[i] as Node3D).visible = false
	_rain_fx_update(rain_seen)
	if not lighter_used and _lighter != null:
		_lighter.visible = false


func _rain_fx_update(on: bool) -> void:
	if not on:
		if b._rain_fx != null:
			b._rain_fx.emitting = false
		return
	if b._rain_fx == null:
		var half := float(b.config["bounds"]) + 2.0
		b._rain_fx = CPUParticles3D.new()
		b._rain_fx.name = "SakeRain"
		b._rain_fx.amount = int(b.attacks_cfg["kinds"]["flyer_storm"].get("rain_drops", 220))
		b._rain_fx.lifetime = 0.9
		b._rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		b._rain_fx.emission_box_extents = Vector3(half, 0.5, half)
		b._rain_fx.position = Vector3(0, 18.0, 0)
		b._rain_fx.direction = Vector3(0, -1, 0)
		b._rain_fx.spread = 4.0
		b._rain_fx.gravity = Vector3(0, -30, 0)
		b._rain_fx.initial_velocity_min = 8.0
		b._rain_fx.initial_velocity_max = 12.0
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.7, 0.08)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(b.attacks_cfg.get("sake_color", "#f2e6b8")), 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = m
		b._rain_fx.mesh = bm
		b._rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(b._rain_fx)
	b._rain_fx.emitting = true


func _update_ride_bottle(on: bool) -> void:
	if not on:
		if b._ride_bottle != null:
			b._ride_bottle.visible = false
		return
	if b._ride_bottle == null:
		var rk: Dictionary = b.attacks_cfg["kinds"]["bottle_ride"]
		b._ride_bottle = Node3D.new()
		b._ride_bottle.name = "RideBottle"
		b._ride_bottle.top_level = true
		b.add_child(b._ride_bottle)
		# 版63：一升瓶の形を、1つのなめらかな面で作り直した（scripts/boss/sake_bottle_mesh.gd）。長さ＝half_len×2、胴の半径＝bottle_radius
		var radius := float(rk.get("bottle_radius", 1.6))
		var length := float(rk["half_len"]) * 2.0
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = BottleMesh.build(length, radius, BottleMesh.colors_from(rk), 24)
		b._ride_bottle.add_child(body)
		# 走ったあとに飛ぶ酒のしぶき（小さな粒。数は少なく）
		var spray := CPUParticles3D.new()
		spray.name = "Spray"
		spray.amount = 16
		spray.lifetime = 0.5
		spray.direction = Vector3(0, 1, -1)
		spray.spread = 35.0
		spray.initial_velocity_min = 4.0
		spray.initial_velocity_max = 7.0
		spray.gravity = Vector3(0, -18, 0)
		spray.position = Vector3(0, -radius * 0.3, -length * 0.5)
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		sm.radial_segments = 6
		sm.rings = 3
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(str(b.attacks_cfg.get("sake_color", "#f2e6b8")), 0.8)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = smat
		spray.mesh = sm
		spray.local_coords = false
		b._ride_bottle.add_child(spray)
	b._ride_bottle.visible = true
	# 瓶の中心は、道の計算（boss_attacks.gd の ride_at）の bottle。ボスも同じ計算から座る位置が決まるので、ずれない
	var bc: Variant = b.motion.path_info.get("bottle", null)
	if bc is Vector3:
		b._ride_bottle.position = bc  # top_level なので、position がそのまま世界の位置
	b._ride_bottle.rotation = Vector3(0.0, float(b.motion.path_info.get("yaw", b.motion.yaw)), 0.0)
	(b._ride_bottle.get_node("Spray") as CPUParticles3D).emitting = str(b.motion.path_info.get("phase", "")) == "pass"


func _flying_bat() -> Node3D:
	if _fly_bat == null:
		_fly_bat = Node3D.new()
		_fly_bat.name = "FlyingBat"
		_fly_bat.top_level = true
		b.add_child(_fly_bat)
		var catalog: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(CharacterView.ATTACHMENTS_PATH)) as Dictionary).get("items", {})
		var pivot := Node3D.new()
		pivot.position = Vector3(0, -0.6, 0) * float(b.boss_model.cfg["model_scale"]) if b.boss_model != null else Vector3.ZERO
		pivot.scale = Vector3.ONE * (float(b.boss_model.cfg["model_scale"]) if b.boss_model != null else 4.0)
		_fly_bat.add_child(pivot)
		for part in (catalog.get("oni_bat", {}) as Dictionary).get("parts", []):
			pivot.add_child(CharacterView._make_part(part))
		# 版105（軽量化）：44この部品を1つの形にまとめる（手に持っているバットと同じまとめ方。描画の回数が 44回→数回、作る時間も短い）
		MeshMerge.merge_children(pivot, [], {})
		_fly_bat.visible = false
	return _fly_bat


## 版105（軽量化）：戦いの始まりに、投げるバットを先に作っておく（はじめて投げた瞬間に作ると、その1コマが長くなるため）
func prewarm() -> void:
	if b.boss_model != null and b.is_inside_tree():
		_flying_bat()


func _drop_node(i: int) -> MeshInstance3D:
	while b.drop_nodes.size() <= i:
		if _sake_mat == null:
			_sake_mat = StandardMaterial3D.new()
			_sake_mat.albedo_color = Color(str(b.attacks_cfg.get("sake_color", "#f2e6b8")), 0.85)
			_sake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_sake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 1.1
		sm.radial_segments = 8
		sm.rings = 4
		sm.material = _sake_mat
		var n := MeshInstance3D.new()
		n.name = "SakeDrop%d" % b.drop_nodes.size()
		n.mesh = sm
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		b.add_child(n)
		b.drop_nodes.append(n)
	return b.drop_nodes[i]


## 床に酒だまりを残すか（版61：data の puddles_enabled。いまは残さない）
func puddles_enabled() -> bool:
	return bool(b.attacks_cfg.get("puddles_enabled", true))


## 床に酒だまりを作る（場所・広さは、酒の雨・大雨のしずく）
func _add_puddle(pos: Vector3, r: float, id: String = "") -> void:
	if not puddles_enabled():
		return
	var k: Dictionary = b.attacks_cfg["kinds"].get("flyer_storm", {})
	var key := id if id != "" else "p%d_%d" % [int(pos.x * 10.0), int(pos.z * 10.0)]
	b.field.add(key, Vector2(pos.x, pos.z), r * 1.1, b._round_t(), float(k.get("puddle_life", 4.0)), 0.2)


## 酒だまりの見た目：床の酒だまり（field）に合わせて、ぬれた丸を置く。燃えているものには、炎
func _update_puddles(_delta: float) -> void:
	var t := b._round_t()
	b.field.prune(t)
	var wet := Color(str(b.attacks_cfg.get("wet_color", "#1d2a2a")))
	var live := b.field.alive(t)
	var max_n := int(b.attacks_cfg.get("wet_max", 40))
	var used := 0
	for p in live:
		if used >= max_n:
			break
		var node := _wet_node(used)
		used += 1
		var pos: Vector2 = p["pos"]
		var r := SakeField.radius_at(p, t)
		var sx := 0.9 + 0.2 * fposmod(pos.x * 7.3 + pos.y * 3.1, 1.0)
		node.position = Vector3(pos.x, 0.015, pos.y)
		node.rotation.y = fposmod(pos.x * 1.7 - pos.y * 2.3, TAU)
		node.scale = Vector3(r * sx, 1.0, r * (2.0 - sx))
		var left := float(p["expire"]) - t
		var mat := node.material_override as StandardMaterial3D
		var burnt := float(p["burn_end"]) >= 0.0 and t >= float(p["burn_end"])
		var col := Color(0.12, 0.1, 0.09) if burnt else wet
		mat.albedo_color = Color(col.r, col.g, col.b, 0.6 * clampf(left / 1.5, 0.0, 1.0))
		node.visible = true
	for i in range(used, b.puddles.size()):
		(b.puddles[i] as Node3D).visible = false
	_update_fires(t)


func _wet_node(i: int) -> MeshInstance3D:
	while b.puddles.size() <= i:
		if _wet_mesh == null:
			_wet_mesh = CylinderMesh.new()
			_wet_mesh.top_radius = 1.0
			_wet_mesh.bottom_radius = 1.0
			_wet_mesh.height = 0.02
			_wet_mesh.radial_segments = 16
			_wet_mesh.rings = 1
		var node := MeshInstance3D.new()
		node.name = "Wet%d" % b.puddles.size()
		node.mesh = _wet_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = m
		b.add_child(node)
		b.puddles.append(node)
	return b.puddles[i]


## 戦いの進みに合わせて、瓶が割れた所に酒だまりを作り、火祭りのライターが落ちたら火をつける
func _sake_field_update() -> void:
	if b.current_attack.is_empty():
		return
	var kind := str(b.current_attack["kind"])
	if kind != Attacks.SAKE_DROP and kind != Attacks.FIRE_FEST:
		return
	var k := Attacks.kind_cfg(b.attacks_cfg, b.current_attack)
	var ctx := b._attack_ctx(b.current_attack, b.current_attack_u)
	ctx["n"] = int(b.current_attack["n"])
	var start := float(b.current_attack["start"])
	for bk in Attacks.sake_bottles(b.current_attack, k, ctx):
		if b.current_attack_u >= float(bk["land"]) and not b._landed.has(str(bk["id"])):
			b._landed[str(bk["id"])] = true
			var to: Vector2 = bk["to"]
			if puddles_enabled():
				b.field.add(str(bk["id"]), to, float(k["puddle_r"]), start + float(bk["land"]), float(k["puddle_life"]))
			_burst_fx(Vector3(to.x, 0.3, to.y), "glass")
			b._play_sfx("thud")
	if kind == Attacks.FIRE_FEST and not b._ignited.has(int(b.current_attack["n"])):
		var l := Attacks.lighter_at(b.current_attack_u, k, ctx)
		if b.current_attack_u >= float(l["land"]):
			b._ignited[int(b.current_attack["n"])] = true
			var tg: Vector2 = l["target"]
			b.field.ignite("f%d" % int(b.current_attack["n"]), tg, start + float(l["land"]), float(k["ignite_reach"]), float(k["fire_hop"]), float(k["fire_burn"]), float(k["link_gap"]))
			_burst_fx(Vector3(tg.x, 0.3, tg.y), "spark")
			b._play_sfx("ultimate")


func _bottle_node(i: int) -> Node3D:
	while b._bottle_nodes.size() <= i:
		# 投げる酒瓶：巨大酒瓶と同じ形（scripts/boss/sake_bottle_mesh.gd）を小さくしたもの。立てた向き（口が上）
		var n := Node3D.new()
		n.name = "Bottle%d" % b._bottle_nodes.size()
		var rk: Dictionary = b.attacks_cfg["kinds"].get("bottle_ride", {})
		var mi := MeshInstance3D.new()
		mi.mesh = BottleMesh.build(1.3, 0.17, BottleMesh.colors_from(rk), 10)
		mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.visible = false
		b.add_child(n)
		b._bottle_nodes.append(n)
	return b._bottle_nodes[i]


func _lighter_node() -> Node3D:
	if _lighter == null:
		_lighter = MeshInstance3D.new()
		_lighter.name = "Lighter"
		var bk := BoxMesh.new()
		bk.size = Vector3(0.45, 0.75, 0.25)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#d22c2c")
		m.emission_enabled = true
		m.emission = Color("#ff7a1a")
		m.emission_energy_multiplier = 0.8
		bk.material = m
		(_lighter as MeshInstance3D).mesh = bk
		_lighter.visible = false
		b.add_child(_lighter)
	return _lighter


## 一回だけ飛び散る粒（ガラスとしぶき／火花）。何こかを使いまわす
func _burst_fx(pos: Vector3, kind: String) -> void:
	if not b.is_inside_tree():
		return
	while _fx_pool.size() < 6:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.95
		p.amount = 24
		p.lifetime = 0.8
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3(0, -18, 0)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.06)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = mat
		p.mesh = bm
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(p)
		_fx_pool.append(p)
	var e: CPUParticles3D = _fx_pool[_fx_next % _fx_pool.size()]
	_fx_next += 1
	e.global_position = pos
	var g := Gradient.new()
	if kind == "spark":
		g.set_color(0, Color("#fff2a0"))
		g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	else:
		# ガラス（緑）と、酒のしぶき（白っぽい）
		g.set_color(0, Color("#7fd18a"))
		g.add_point(0.5, Color(str(b.attacks_cfg.get("sake_color", "#f2e6b8")), 0.9))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	e.color_ramp = g
	e.restart()


## 燃えている酒だまりに、炎の粒と、赤い光
func _update_fires(t: float) -> void:
	var burning := b.field.burning(t)
	for i in burning.size():
		var p: Dictionary = burning[i]
		var f := _fire_node(i)
		var pos: Vector2 = p["pos"]
		var r := SakeField.radius_at(p, t)
		f.position = Vector3(pos.x, 0.0, pos.y)
		var em := f.get_child(0) as CPUParticles3D
		em.emission_sphere_radius = r * 0.8
		em.emitting = true
		var glow := f.get_child(1) as MeshInstance3D
		glow.scale = Vector3(r, 1.0, r)
		var left := float(p["burn_end"]) - t
		(glow.material_override as StandardMaterial3D).albedo_color.a = 0.55 * clampf(left / 0.5, 0.0, 1.0)
		f.visible = true
	for i in range(burning.size(), _fire_nodes.size()):
		var f2: Node3D = _fire_nodes[i]
		f2.visible = false
		(f2.get_child(0) as CPUParticles3D).emitting = false


func _fire_node(i: int) -> Node3D:
	while _fire_nodes.size() <= i:
		var n := Node3D.new()
		n.name = "Fire%d" % _fire_nodes.size()
		var p := CPUParticles3D.new()
		p.amount = 22
		p.lifetime = 0.7
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 1.5
		p.direction = Vector3.UP
		p.spread = 15.0
		p.gravity = Vector3(0, 6, 0)
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.5
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.2
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 1.4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		q.material = m
		p.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color("#ffe066"))
		g.add_point(0.4, Color("#ff6a1a"))
		g.set_color(g.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
		p.color_ramp = g
		p.position = Vector3(0, 0.4, 0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(p)
		var glow := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 1.0
		c.bottom_radius = 1.0
		c.height = 0.02
		c.radial_segments = 16
		c.rings = 1
		glow.mesh = c
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
		glow.material_override = gm
		glow.position = Vector3(0, 0.03, 0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(glow)
		n.visible = false
		b.add_child(n)
		_fire_nodes.append(n)
	return _fire_nodes[i]


func _sake_spray_update() -> void:
	if b.boss_model == null or b.current_attack.is_empty():
		return
	var kind := str(b.current_attack["kind"])
	var key := ""
	if kind == Attacks.SAKE_RAIN:
		var k: Dictionary = b.attacks_cfg["kinds"][kind]
		for t in int(k["throws"]):
			if b.current_attack_u >= Attacks.sake_throw_time(t, k):
				key = "%d_%d" % [int(b.current_attack["n"]), t]
	elif kind == Attacks.FLYER_STORM:
		var k2: Dictionary = b.attacks_cfg["kinds"][kind]
		var every := maxf(0.6, float(k2["spread_sec"]) / 6.0)
		var i := int(floor((b.current_attack_u - float(k2["start_sec"]) + every) / every))
		if b.current_attack_u >= float(k2["start_sec"]) - every and b.current_attack_u < float(k2["start_sec"]) + float(k2["spread_sec"]):
			key = "%d_s%d" % [int(b.current_attack["n"]), i]
	if key != "" and key != _last_spray_key:
		_last_spray_key = key
		if b.boss_model.has_method("spray_sake") and b.boss_model.is_inside_tree():
			b.boss_model.spray_sake()


func _update_jump_shadow() -> void:
	if _shadow == null:
		_shadow = MeshInstance3D.new()
		_shadow.name = "BossShadow"
		var c := CylinderMesh.new()
		c.top_radius = 1.0
		c.bottom_radius = 1.0
		c.height = 0.02
		c.radial_segments = 20
		c.rings = 1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0, 0, 0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		c.material = m
		_shadow.mesh = c
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.add_child(_shadow)
	var h := b.motion.height
	var riding := bool(b.motion.path_info.get("riding", false))
	# 覚醒のオーラの床の光は、跳んでいる間・酒瓶に乗っている間は消す（空中に円盤が浮いて見えるので）
	if b.boss_model != null and b.boss_model.aura_ground != null:
		b.boss_model.aura_ground.visible = h < 0.3
	_shadow.visible = h > 0.3 and not riding
	if _shadow.visible:
		_shadow.position = Vector3(b.motion.pos.x, 0.02, b.motion.pos.y)
		_shadow.scale = Vector3.ONE * lerpf(3.0, 1.6, clampf(h / 8.0, 0.0, 1.0))
