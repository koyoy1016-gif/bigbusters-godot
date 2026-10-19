extends Node3D
## キャラクターの見た目。モデル（glTF の場面）を読み込み、骨つきのアニメを動作に合わせて再生する。
## モデルがなければ、何も出さない（呼び出し側が、箱のままにする）。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const ProceduralAnims := preload("res://scripts/characters/procedural_anims.gd")
const MeshMerge := preload("res://scripts/core/mesh_merge.gd")
const ATTACHMENTS_PATH := "res://data/attachments.json"

var character: Dictionary = {}
var model: Node = null
var player: AnimationPlayer = null
var current_action := ""
var facing := 0.0


## モデルを読み込む。成功したら true
func setup(def: Dictionary) -> bool:
	character = def
	add_to_group("styled")
	if not CharacterData.has_model(def):
		return false
	var packed := load(str(def["model"])) as PackedScene
	if packed == null:
		return false
	model = packed.instantiate()
	add_child(model)
	var s := float(def.get("model_scale", 1.0))
	scale = Vector3.ONE * s
	player = _find_player(model)
	if player == null and str(def.get("anim_library", "")) != "":
		player = build_library_player(model, str(def["anim_library"]))
	if player == null and bool(def.get("procedural_anims", false)):
		player = ProceduralAnims.build_player(model, ProceduralAnims.load_config())
	fix_materials(model, def)
	attach_items(model, def.get("attachments", []))
	bake_items(model)
	return true


## 骨に付けた小物（Item_*）を、骨の動きについていく1つの形（スキン）にまとめて、描く回数を減らす。
## 小物ごとの部品（数十こ）が、材質の種類の数（2〜3回）で描ける。まとめた形を返す（小物がなければ null）
## only：まとめる小物の名前（空なら全部）。mesh_name：まとめた形の名前
static func bake_items(model: Node, only: Array = [], mesh_name: String = "Items") -> MeshInstance3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var holders := sk.find_children("Item_*", "BoneAttachment3D", false, false)
	if not only.is_empty():
		holders = holders.filter(func(h: Node) -> bool: return only.has(str(h.name).trim_prefix("Item_")))
	if holders.is_empty():
		return null
	var skin := Skin.new()
	var bind_of := {}
	var parts: Array = []
	for h in holders:
		var holder := h as BoneAttachment3D
		var bi := sk.find_bone(holder.bone_name)
		if bi < 0:
			continue
		var rest := _global_rest(sk, bi)
		if not bind_of.has(bi):
			bind_of[bi] = skin.get_bind_count()
			skin.add_named_bind(holder.bone_name, rest.affine_inverse())
		for p in MeshMerge.collect(holder):
			parts.append({"mesh": p["mesh"], "xf": rest * (p["xf"] as Transform3D), "bone": bind_of[bi]})
	var mesh := MeshMerge.merge_parts(parts, [], {})
	if mesh == null:
		return null
	for h in holders:
		sk.remove_child(h)
		h.free()
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	sk.add_child(mi)
	mi.skin = skin
	mi.skeleton = mi.get_path_to(sk)
	return mi


## data/attachments.json の小物（剣・ベルトなど）を、骨に付ける。付けた数を返す
static func attach_items(model: Node, item_ids: Array, catalog: Dictionary = {}) -> int:
	if item_ids.is_empty():
		return 0
	if catalog.is_empty():
		var f := FileAccess.open(ATTACHMENTS_PATH, FileAccess.READ)
		if f == null:
			return 0
		var parsed = JSON.parse_string(f.get_as_text())
		catalog = (parsed as Dictionary).get("items", {}) if parsed is Dictionary else {}
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return 0
	var sk := found[0] as Skeleton3D
	var count := 0
	for id in item_ids:
		if not catalog.has(id):
			continue
		var item: Dictionary = catalog[id]
		if sk.find_bone(str(item.get("bone", ""))) < 0:
			continue
		var holder := BoneAttachment3D.new()
		holder.name = "Item_" + str(id)
		holder.bone_name = str(item["bone"])
		sk.add_child(holder)
		if str(item.get("space", "")) == "model":
			# モデルの座標（体の前が +Z、上が +Y）で、そのまま書ける小物。骨の位置・向きは、ここで引き算する
			var bi := sk.find_bone(str(item["bone"]))
			var rest := _global_rest(sk, bi)
			for part in item.get("parts", []):
				holder.add_child(_make_model_part(part, rest))
			count += 1
			continue
		var pivot := Node3D.new()
		pivot.name = "Pivot"
		var off: Array = item.get("offset", [0, 0, 0])
		pivot.position = Vector3(float(off[0]), float(off[1]), float(off[2]))
		# aim：小物の +Y（剣なら刃の向き）を、骨の空間のこの向きに合わせる
		var aim_a: Array = item.get("aim", [0, 1, 0])
		var aim := Vector3(float(aim_a[0]), float(aim_a[1]), float(aim_a[2])).normalized()
		var q := Quaternion(Vector3.UP, aim) if aim.length() > 0.5 else Quaternion.IDENTITY
		var sc_a: Array = item.get("scale", [1, 1, 1])
		pivot.basis = Basis(q) * Basis.from_scale(Vector3(float(sc_a[0]), float(sc_a[1]), float(sc_a[2])))
		holder.add_child(pivot)
		for part in item.get("parts", []):
			pivot.add_child(_make_part(part))
		count += 1
	return count


## 骨の、静止の姿勢（モデル座標）。親の静止の姿勢をたどって求める（Skeleton3D の同名の関数は、骨の姿勢の更新を引き起こす）
static func _global_rest(sk: Skeleton3D, bone: int) -> Transform3D:
	var t := sk.get_bone_rest(bone)
	var p := sk.get_bone_parent(bone)
	while p >= 0:
		t = sk.get_bone_rest(p) * t
		p = sk.get_bone_parent(p)
	return t


## モデル座標で書いた部品を作る。shape：rod（from→to の円柱。r0=from側の半径、r1=to側の半径、squash=[横,奥行きの倍率]）、
## box（center, size, rotation_deg）、sphere（center, r, squash=[x,y,z]）
static func _make_model_part(part: Dictionary, rest: Transform3D) -> MeshInstance3D:
	var mesh: PrimitiveMesh
	var pos := Vector3.ZERO
	var basis := Basis.IDENTITY
	match str(part.get("shape", "rod")):
		"box":
			var sz: Array = part["size"]
			var bm := BoxMesh.new()
			bm.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
			mesh = bm
			var c: Array = part["center"]
			pos = Vector3(float(c[0]), float(c[1]), float(c[2]))
			var rot: Array = part.get("rotation_deg", [0, 0, 0])
			basis = Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2]))))
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = float(part["r"])
			sm.height = float(part["r"]) * 2.0
			sm.radial_segments = 8 if float(part["r"]) < 0.05 else 12
			sm.rings = 4 if float(part["r"]) < 0.05 else 6
			mesh = sm
			var c2: Array = part["center"]
			pos = Vector3(float(c2[0]), float(c2[1]), float(c2[2]))
			var sq: Array = part.get("squash", [1, 1, 1])
			basis = Basis.from_scale(Vector3(float(sq[0]), float(sq[1]), float(sq[2])))
		_:
			var a: Array = part["from"]
			var b: Array = part["to"]
			var from := Vector3(float(a[0]), float(a[1]), float(a[2]))
			var to := Vector3(float(b[0]), float(b[1]), float(b[2]))
			var dir := to - from
			var cm := CylinderMesh.new()
			cm.bottom_radius = float(part["r0"])
			cm.top_radius = float(part["r1"])
			cm.height = dir.length()
			cm.radial_segments = 8 if maxf(float(part["r0"]), float(part["r1"])) < 0.07 else 12
			cm.rings = 1
			mesh = cm
			pos = (from + to) * 0.5
			var sq2: Array = part.get("squash", [1, 1])
			basis = Basis(Quaternion(Vector3.UP, dir.normalized())) * Basis.from_scale(Vector3(float(sq2[0]), 1.0, float(sq2[1])))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(part.get("color", "#cccccc")))
	mat.metallic = float(part.get("metallic", 0.0))
	mat.roughness = float(part.get("roughness", 0.8))
	StyleFx.style_material(mat, StyleFx.texture_for(mat.metallic, str(part.get("tex", ""))))
	StyleFx.apply_outline(mat, float(StyleFx.config().get("outline_width", 0.014)))
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var inv := rest.basis.inverse()
	mi.transform = Transform3D(inv * basis, inv * (pos - rest.origin))
	return mi


static func _make_part(part: Dictionary) -> MeshInstance3D:
	var sz: Array = part.get("size", [0.1, 0.1, 0.1])
	var mesh: PrimitiveMesh
	match str(part.get("shape", "box")):
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = float(sz[0])
			cm.bottom_radius = float(sz[0])
			cm.height = float(sz[1])
			cm.radial_segments = 12
			cm.rings = 1
			mesh = cm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = float(sz[0])
			sm.height = float(sz[0]) * 2.0
			sm.radial_segments = 12
			sm.rings = 6
			mesh = sm
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
			mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(part.get("color", "#cccccc")))
	mat.metallic = float(part.get("metallic", 0.0))
	mat.roughness = float(part.get("roughness", 0.8))
	StyleFx.style_material(mat, StyleFx.texture_for(mat.metallic, str(part.get("tex", ""))))
	StyleFx.apply_outline(mat, float(StyleFx.config().get("outline_width", 0.014)))
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var off: Array = part.get("offset", [0, 0, 0])
	mi.position = Vector3(float(off[0]), float(off[1]), float(off[2]))
	var rot: Array = part.get("rotation_deg", [0, 0, 0])
	mi.rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	return mi


## 書き出したモデルの材質を、軽く正しく見えるように直す。
## 全部が「半透明」で出てくるので、ふつうの材質は不透明に、髪・眉・まつ毛は「切り抜き」にする
## （名前に cutout_keywords のどれかが入っているものが切り抜き）。ツヤ出し（クリアコート）は切る
static func fix_materials(node: Node, def: Dictionary) -> int:
	var keywords: Array = def.get("cutout_keywords", ["hair", "short", "eyebrow", "eyelash"])
	var count := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if mat == null:
					continue
				var nm := mat.resource_name.to_lower()
				var cut := false
				for k in keywords:
					if nm.contains(str(k).to_lower()):
						cut = true
				if cut:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					mat.alpha_scissor_threshold = float(def.get("cutout_threshold", 0.5))
				else:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mat.cull_mode = BaseMaterial3D.CULL_BACK
				mat.clearcoat_enabled = false
				StyleFx.style_material(mat)
				StyleFx.apply_outline(mat, float(StyleFx.config().get("outline_width", 0.014)))
				count += 1
	for c in node.get_children():
		count += fix_materials(c, def)
	return count


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


## 動作に合わせたアニメを流す（同じ動作なら何もしない）。アニメがなければ流さない。流したら true
func play_action(action: String) -> bool:
	if action == current_action:
		return false
	# 一度始めたら最後まで見せる動き（こうげき）。たおれる（down）だけは割りこめる
	var oneshot: Array = character.get("anim_oneshot", [])
	if oneshot.has(current_action) and action != "down" and player != null and player.is_playing() \
			and player.current_animation == CharacterData.animation_for(character, current_action):
		return false
	current_action = action
	if player == null:
		return false
	var anim := CharacterData.animation_for(character, action)
	if anim == "" or not player.has_animation(anim):
		return false
	var speeds: Variant = character.get("anim_speeds", {})
	var speed := float(speeds.get(action, 1.0)) if speeds is Dictionary else 1.0
	player.play(anim, 0.08, speed)
	return true


## 攻撃の動きの1コマ分（steps）を、すぐ流す。key は「swing」「jump_start」など、キャラの animations の名前。
## そのキャラに key がなければ、「attack」のアニメで代用する。流せたら true
func play_step(key: String, speed: float, from_end: bool = false) -> bool:
	current_action = "step"
	if player == null:
		return false
	var anim := CharacterData.animation_for(character, key)
	if anim == "" or not player.has_animation(anim):
		anim = CharacterData.animation_for(character, "attack")
	if anim == "" or not player.has_animation(anim):
		return false
	player.play(anim, 0.05, speed, from_end)
	if not from_end:
		player.seek(0.0, true)
	return true


## 保存した動きの集まり（tools/retarget_ual.gd が作る .res）から、再生係を作る。読めなければ null
static func build_library_player(model: Node, path: String) -> AnimationPlayer:
	var lib := load(path) as AnimationLibrary
	if lib == null:
		return null
	var p := AnimationPlayer.new()
	p.name = "LibraryAnimationPlayer"
	model.add_child(p)
	p.root_node = NodePath("..")
	p.add_animation_library("", lib)
	return p


## 向き（床の上の x, z）に、すぐ体を向ける
func face_now(direction: Vector2) -> void:
	if direction.length() < 0.05:
		return
	facing = atan2(direction.x, direction.y)
	rotation.y = facing


## 進む向き（床の上の x, z）に、少しずつ体を向ける。止まっているときは、そのまま
func face(direction: Vector2, delta: float, turn_per_sec: float = 12.0) -> void:
	if direction.length() < 0.05:
		return
	var goal := atan2(direction.x, direction.y)
	facing = lerp_angle(facing, goal, clampf(turn_per_sec * delta, 0.0, 1.0))
	rotation.y = facing
