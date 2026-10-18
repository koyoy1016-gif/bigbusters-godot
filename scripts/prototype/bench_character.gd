extends RefCounted
## 負荷試験用の、骨つきの仮の人型。リアルな忍者を何体まで同時に動かせるかを測るためのもの（見た目は仮）。
## 面の数（三角形）を指定して作る。骨は7本：腰・背中・頭・左右の腕・左右の脚（足は2本に分ける）。
## 剣は、右腕に付ける細い棒。体は管（筒）の集まりで、骨に重みを付ける（本物の忍者のモデルと同じ「骨つきの面」の重さが測れる）。

const BONE_NAMES := ["hips", "spine", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
const BODY_PARTS := 6


## 体の筒1本あたりの分割数（radial。縦の分割も同じ数）。面の数の目標から決める
static func radial_for(target_tris: int) -> int:
	return maxi(4, int(round(sqrt(float(maxi(1, target_tris)) / float(BODY_PARTS * 2)))))


## 筒1本の三角形の数
static func tube_tris(radial: int, rings: int) -> int:
	return radial * rings * 2


## その分割数で作ったときの、1体の三角形の数（剣を含む）
static func character_tris(radial: int) -> int:
	return BODY_PARTS * tube_tris(radial, radial) + tube_tris(6, 2)


## n 体を、横に並べる位置（x, z）。中心を 0 にして、行ごとに並べる
static func layout_positions(n: int, spacing: float) -> Array:
	var result: Array = []
	if n <= 0:
		return result
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / float(cols)))
	for i in n:
		var c := i % cols
		var r := i / cols
		result.append(Vector2((float(c) - float(cols - 1) * 0.5) * spacing, (float(r) - float(rows - 1) * 0.5) * spacing))
	return result


class MeshBuilder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()

	## 縦の筒。center は筒の真ん中、height は高さ、半径は下から上へ変わる。
	## 下は bone_low、上は bone_high の骨に付き、間は重みで混ぜる（同じ骨なら、重みは1）
	func add_tube(center: Vector3, height: float, radius_low: float, radius_high: float, radial: int, rings: int, bone_low: int, bone_high: int) -> void:
		var base := verts.size()
		for j in range(rings + 1):
			var t := float(j) / float(rings)
			var y := center.y + (t - 0.5) * height
			var radius := lerpf(radius_low, radius_high, t)
			for i in radial:
				var a := TAU * float(i) / float(radial)
				var dir := Vector3(cos(a), 0.0, sin(a))
				verts.append(Vector3(center.x + dir.x * radius, y, center.z + dir.z * radius))
				normals.append(dir)
				bones.append_array([bone_low, bone_high, 0, 0])
				weights.append_array([1.0 - t, t, 0.0, 0.0] if bone_low != bone_high else [1.0, 0.0, 0.0, 0.0])
		for j in rings:
			for i in radial:
				var a0 := base + j * radial + i
				var a1 := base + j * radial + (i + 1) % radial
				var b0 := base + (j + 1) * radial + i
				var b1 := base + (j + 1) * radial + (i + 1) % radial
				indices.append_array([a0, a1, b0, a1, b1, b0])

	func to_mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


## 骨つきの人型を1体作る。戻り値は Skeleton3D（子に MeshInstance3D がいる）。面の数は target_tris くらい
static func build(target_tris: int, material: Material) -> Skeleton3D:
	var radial := radial_for(target_tris)
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	# 骨：腰 → 背中 → 頭、背中 → 腕、腰 → 脚（立った姿勢での位置）
	var rest := {
		"hips": [-1, Vector3(0.0, 1.0, 0.0)],
		"spine": [0, Vector3(0.0, 0.25, 0.0)],
		"head": [1, Vector3(0.0, 0.5, 0.0)],
		"arm_l": [1, Vector3(-0.3, 0.2, 0.0)],
		"arm_r": [1, Vector3(0.3, 0.2, 0.0)],
		"leg_l": [0, Vector3(-0.12, 0.0, 0.0)],
		"leg_r": [0, Vector3(0.12, 0.0, 0.0)],
	}
	for name_text in BONE_NAMES:
		sk.add_bone(name_text)
	for i in BONE_NAMES.size():
		var info: Array = rest[BONE_NAMES[i]]
		sk.set_bone_parent(i, int(info[0]))
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, info[1]))
	sk.reset_bone_poses()

	var mb := MeshBuilder.new()
	# 立った姿勢の座標で作る（腰 y=1.0、背中 y=1.25、頭 y=1.75）
	mb.add_tube(Vector3(0.0, 1.22, 0.0), 0.56, 0.11, 0.17, radial, radial, 0, 1)       # 胴（腰は細く）
	mb.add_tube(Vector3(0.0, 1.78, 0.0), 0.26, 0.09, 0.09, radial, radial, 2, 2)       # 頭
	mb.add_tube(Vector3(-0.34, 1.2, 0.0), 0.6, 0.045, 0.045, radial, radial, 3, 3)    # 左腕
	mb.add_tube(Vector3(0.34, 1.2, 0.0), 0.6, 0.045, 0.045, radial, radial, 4, 4)     # 右腕
	mb.add_tube(Vector3(-0.12, 0.5, 0.0), 1.0, 0.06, 0.075, radial, radial, 5, 5)     # 左脚
	mb.add_tube(Vector3(0.12, 0.5, 0.0), 1.0, 0.06, 0.075, radial, radial, 6, 6)      # 右脚
	mb.add_tube(Vector3(0.4, 1.2, 0.0), 0.9, 0.012, 0.012, 6, 2, 4, 4)                # 剣（右腕に付く）

	var inst := MeshInstance3D.new()
	inst.name = "Body"
	inst.mesh = mb.to_mesh()
	inst.material_override = material
	sk.add_child(inst)
	inst.skeleton = NodePath("..")
	inst.skin = sk.create_skin_from_rest_transforms()
	return sk


## 歩く・剣を振る動き（骨を回す）。t は秒、phase は体ごとにずらす値
static func animate(sk: Skeleton3D, t: float, phase: float, speed: float, amount: float) -> void:
	var s := sin(t * speed + phase)
	var c := cos(t * speed + phase)
	sk.set_bone_pose_rotation(5, Quaternion(Vector3.RIGHT, s * amount))
	sk.set_bone_pose_rotation(6, Quaternion(Vector3.RIGHT, -s * amount))
	sk.set_bone_pose_rotation(3, Quaternion(Vector3.RIGHT, -s * amount))
	sk.set_bone_pose_rotation(4, Quaternion(Vector3.RIGHT, c * amount * 1.6))
	sk.set_bone_pose_rotation(1, Quaternion(Vector3.UP, s * amount * 0.3))
	sk.set_bone_pose_rotation(2, Quaternion(Vector3.UP, -s * amount * 0.4))
