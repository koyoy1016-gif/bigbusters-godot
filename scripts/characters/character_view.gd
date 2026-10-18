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
	return true


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
