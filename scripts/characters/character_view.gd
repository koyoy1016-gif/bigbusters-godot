extends Node3D
## キャラクターの見た目。モデル（glTF の場面）を読み込み、骨つきのアニメを動作に合わせて再生する。
## モデルがなければ、何も出さない（呼び出し側が、箱のままにする）。

const CharacterData := preload("res://scripts/characters/character_data.gd")

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
	fix_materials(model, def)
	return true


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
