extends Node3D
## キャラクターの見た目。モデル（glTF の場面）を読み込み、骨つきのアニメを動作に合わせて再生する。
## モデルがなければ、何も出さない（呼び出し側が、箱のままにする）。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const ProceduralAnims := preload("res://scripts/characters/procedural_anims.gd")
const ATTACHMENTS_PATH := "res://data/attachments.json"

var character: Dictionary = {}
var model: Node = null
var player: AnimationPlayer = null
var current_action := ""
var facing := 0.0


## モデルを読み込む。成功したら true
func setup(def: Dictionary) -> bool:
	character = def
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
	if player == null and bool(def.get("procedural_anims", false)):
		player = ProceduralAnims.build_player(model, ProceduralAnims.load_config())
	fix_materials(model, def)
	attach_items(model, def.get("attachments", []))
	return true


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
	current_action = action
	if player == null:
		return false
	var anim := CharacterData.animation_for(character, action)
	if anim == "" or not player.has_animation(anim):
		return false
	player.play(anim)
	return true


## 進む向き（床の上の x, z）に、少しずつ体を向ける。止まっているときは、そのまま
func face(direction: Vector2, delta: float, turn_per_sec: float = 12.0) -> void:
	if direction.length() < 0.05:
		return
	var goal := atan2(direction.x, direction.y)
	facing = lerp_angle(facing, goal, clampf(turn_per_sec * delta, 0.0, 1.0))
	rotation.y = facing
