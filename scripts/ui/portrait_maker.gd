extends Node
## 版81b：キャラの3Dの形から、顔から肩までの絵（アイコン）を作る。
## 画面の外の小さな3Dの場面（SubViewport）にキャラを1人出し、頭の骨にカメラを向けて1枚写す。作った絵は覚えて使い回す。
## 1度に1人ずつ作る（重くしない）。画面のない所（テスト）では作らず、呼ぶ側は図形のアイコンのまま。
## 数値は data/game_flow.json の "portrait"。

const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")

var cfg: Dictionary = {}
var cache: Dictionary = {}  # id → ImageTexture
var queue: Array = []  # [{id, def, cbs: [Callable]}]
var busy: Dictionary = {}  # いま作っている：{id, vp, view, frames, cbs}


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## id の絵がほしい。できていればすぐ cb(絵)、なければ作ってから cb(絵)。作れない所では呼ばない
func request(id: String, def: Dictionary, cb: Callable) -> void:
	if cache.has(id):
		cb.call(cache[id])
		return
	if not can_render() or def.is_empty() or not CharacterData.has_model(def):
		return
	if not busy.is_empty() and str(busy["id"]) == id:
		(busy["cbs"] as Array).append(cb)
		return
	for q in queue:
		if str(q["id"]) == id:
			(q["cbs"] as Array).append(cb)
			return
	queue.append({"id": id, "def": def, "cbs": [cb]})


func _process(_delta: float) -> void:
	if busy.is_empty():
		if queue.is_empty():
			return
		_start(queue.pop_front())
		return
	busy["frames"] = int(busy["frames"]) + 1
	if int(busy["frames"]) == 2:
		_aim()
	elif int(busy["frames"]) >= 4:
		_finish()


func _start(item: Dictionary) -> void:
	var size := int(cfg.get("size", 256))
	var vp := SubViewport.new()
	vp.name = "Portrait_" + str(item["id"])
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(cfg.get("ambient", "#b8c4e8")))
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, 30, 0)
	key.light_energy = 1.15
	key.light_color = Color("#fff1e0")
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color("#9ec0ff")
	vp.add_child(rim)
	var view := CharacterView.new()
	var ok := view.setup(item["def"])
	vp.add_child(view)
	if ok:
		view.play_action("idle")
		if view.player != null:
			view.player.seek(float(cfg.get("pose_sec", 0.4)), true)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = float(cfg.get("fov", 24.0))
	vp.add_child(cam)
	cam.current = true
	busy = {"id": item["id"], "vp": vp, "view": view, "frames": 0, "cbs": item["cbs"]}


## 頭の骨の所へ、カメラを向ける（顔から肩まで入るように）
func _aim() -> void:
	var view: Node3D = busy["view"]
	var cam := (busy["vp"] as SubViewport).get_node("Cam") as Camera3D
	var head := view.global_position + Vector3(0, float(cfg.get("fallback_head_m", 3.0)), 0)
	for sk in view.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var i := s.find_bone("head")
		if i >= 0:
			head = (s.global_transform * s.get_bone_global_pose(i)).origin
			break
	var look := head + Vector3(0, float(cfg.get("look_drop_m", -0.08)), 0)
	cam.look_at_from_position(look + Vector3(0, float(cfg.get("cam_rise_m", 0.06)), float(cfg.get("distance_m", 2.1))), look, Vector3.UP)


func _finish() -> void:
	var vp: SubViewport = busy["vp"]
	var img := vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	var id := str(busy["id"])
	var cbs: Array = busy["cbs"]
	vp.queue_free()
	busy = {}
	if tex == null:
		return
	cache[id] = tex
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(tex)
