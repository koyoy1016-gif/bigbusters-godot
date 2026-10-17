extends Node3D
## スティックの試作：横画面で、左のスティックで1人を動かし、右のボタンでジャンプする。
## ボスはまだ置かない（次の工程）。数値は data/prototype_stick.json から読む。
## 動きの計算は stick_math.gd にある。

const CONFIG_PATH := "res://data/prototype_stick.json"
const StickMath := preload("res://scripts/prototype/stick_math.gd")

var config: Dictionary = {}
var player: MeshInstance3D
var overlay: Control
var font: Font
var stick_vec := Vector2.ZERO
var stick_touch := -1
var button_touch := -1
var velocity_y := 0.0
var ground_y := 0.0


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("設定ファイルを開けません: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("設定ファイルのJSONが不正です: " + path)
	return {}


func _ready() -> void:
	if config.is_empty():
		config = load_config()
	font = load(str(config["ui_font_path"])) as Font
	ground_y = float(config["player_size"]) * 0.5
	_build_world()
	_build_ui()


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(config["ground_size"])
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(str(config["ground_color"]))
	plane.material = ground_mat
	ground.mesh = plane
	add_child(ground)

	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.light_energy = float(config["light_energy"])
	var rot: Array = config["light_rotation_deg"]
	light.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	add_child(light)

	player = MeshInstance3D.new()
	player.name = "Player"
	var box := BoxMesh.new()
	box.size = Vector3.ONE * float(config["player_size"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(config["player_color"]))
	box.material = mat
	player.mesh = box
	player.position = Vector3(0.0, ground_y, 0.0)
	add_child(player)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(config["camera_fov"])
	var off: Array = config["camera_offset"]
	add_child(camera)
	camera.look_at_from_position(Vector3(off[0], off[1], off[2]), Vector3.ZERO, Vector3.UP)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)


func _process(delta: float) -> void:
	player.position = StickMath.step_position(player.position, stick_vec, float(config["move_speed"]), delta, float(config["bounds"]))
	var r := StickMath.jump_update(player.position.y, velocity_y, delta, float(config["gravity"]), ground_y)
	player.position.y = r.x
	velocity_y = r.y
	overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	var screen := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			handle_press(event.index, event.position, screen)
		else:
			handle_release(event.index)
	elif event is InputEventScreenDrag:
		handle_drag(event.index, event.position, screen)


## 指が触れた。左の領域ならスティック、右の領域ならボタン（ジャンプ）
func handle_press(index: int, pos: Vector2, screen: Vector2) -> void:
	if stick_touch == -1 and pos.x < screen.x * float(config["stick_zone_max_x_frac"]):
		stick_touch = index
		stick_vec = _stick_input(pos, screen)
	elif button_touch == -1 and pos.x >= screen.x * float(config["button_zone_min_x_frac"]):
		button_touch = index
		jump()


func handle_drag(index: int, pos: Vector2, screen: Vector2) -> void:
	if index == stick_touch:
		stick_vec = _stick_input(pos, screen)


func handle_release(index: int) -> void:
	if index == stick_touch:
		stick_touch = -1
		stick_vec = Vector2.ZERO
	if index == button_touch:
		button_touch = -1


## 地面にいるときだけ跳ぶ
func jump() -> void:
	if is_equal_approx(player.position.y, ground_y):
		velocity_y = float(config["jump_speed"])


func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return StickMath.stick_vector(pos, _stick_center(screen), float(config["stick_radius_px"]), float(config["stick_dead_zone"]))


func _stick_center(screen: Vector2) -> Vector2:
	var f: Array = config["stick_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _button_center(screen: Vector2) -> Vector2:
	var f: Array = config["button_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _draw_overlay() -> void:
	var screen := overlay.size
	var c := _stick_center(screen)
	var r := float(config["stick_radius_px"])
	overlay.draw_circle(c, r, Color(str(config["stick_base_color"])))
	overlay.draw_circle(c + stick_vec * r, r * 0.4, Color(str(config["stick_knob_color"])))

	var bc := _button_center(screen)
	var pressed := button_touch != -1
	var color := str(config["button_pressed_color"]) if pressed else str(config["button_color"])
	overlay.draw_circle(bc, float(config["button_radius_px"]), Color(color))
	var label := str(config["button_label"])
	var fs := int(config["ui_font_size"])
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	overlay.draw_string(font, bc + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(str(config["button_text_color"])))

	overlay.draw_string(font, Vector2(16, fs * 1.4), str(config["hint"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(str(config["text_color"])))
