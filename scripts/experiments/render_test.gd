extends Node3D
## 描画実験：個別の箱（A）と MultiMeshInstance3D（B）の FPS と描画回数を比べる。
## 数値は data/render_test.json から読む。

const CONFIG_PATH := "res://data/render_test.json"

var config: Dictionary = {}
var mode: String = "A"
var boxes_a: Node3D
var boxes_b: MultiMeshInstance3D
var box_nodes: Array[MeshInstance3D] = []
var multimesh: MultiMesh
var base_positions: Array[Vector3] = []
var angle: float = 0.0
var info_label: Label
var button_a: Button
var button_b: Button
var ui_font: Font


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
	_build_world()
	_build_ui()
	set_mode(str(config.get("default_mode", "A")))


func _build_world() -> void:
	var count: int = int(config["box_count"])
	var columns: int = int(config["grid_columns"])
	var spacing: float = float(config["grid_spacing"])
	var rows: int = ceili(float(count) / columns)
	var size: float = float(config["box_size"])

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * size
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(str(config["box_color"]))
	box_mesh.material = box_mat

	# 地面（単色の平面）
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(config["ground_size"])
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(str(config["ground_color"]))
	plane.material = ground_mat
	ground.mesh = plane
	add_child(ground)

	# ライト1つ
	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.light_energy = float(config["light_energy"])
	var rot: Array = config["light_rotation_deg"]
	light.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	add_child(light)

	# 箱の位置（A・B共通）
	var origin := Vector3(-(columns - 1) * spacing * 0.5, size * 0.5, -(rows - 1) * spacing * 0.5)
	for i in count:
		base_positions.append(origin + Vector3((i % columns) * spacing, 0.0, (i / columns) * spacing))

	# A：個別の箱
	boxes_a = Node3D.new()
	boxes_a.name = "BoxesA"
	add_child(boxes_a)
	for i in count:
		var box := MeshInstance3D.new()
		box.mesh = box_mesh
		box.position = base_positions[i]
		boxes_a.add_child(box)
		box_nodes.append(box)

	# B：MultiMesh
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box_mesh
	multimesh.instance_count = count
	boxes_b = MultiMeshInstance3D.new()
	boxes_b.name = "BoxesB"
	boxes_b.multimesh = multimesh
	add_child(boxes_b)
	_update_rotation()

	# カメラ（全体が見えるように斜め上から）
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(config["camera_fov"])
	var height: float = rows * float(config["camera_height_per_row"]) + 8.0
	camera.position = Vector3(0.0, height, rows * spacing * 0.5 + 6.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0))
	camera.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var font_size: int = int(config["ui_font_size"])
	ui_font = load(str(config["ui_font_path"])) as Font

	info_label = Label.new()
	info_label.position = Vector2(16, 12)
	info_label.add_theme_font_override("font", ui_font)
	info_label.add_theme_font_size_override("font_size", font_size)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(info_label)

	var min_size_arr: Array = config["ui_button_min_size"]
	var min_size := Vector2(min_size_arr[0], min_size_arr[1])
	var row := HBoxContainer.new()
	row.position = Vector2(16, float(config["ui_button_top"]))
	layer.add_child(row)
	button_a = _make_button("A 個別", min_size, font_size)
	button_b = _make_button("B Multi", min_size, font_size)
	button_a.pressed.connect(set_mode.bind("A"))
	button_b.pressed.connect(set_mode.bind("B"))
	row.add_child(button_a)
	row.add_child(button_b)


func _make_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE
	return button


func set_mode(new_mode: String) -> void:
	if new_mode != "A" and new_mode != "B":
		return
	mode = new_mode
	boxes_a.visible = (mode == "A")
	boxes_b.visible = (mode == "B")
	if button_a:
		button_a.disabled = (mode == "A")
		button_b.disabled = (mode == "B")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_KP_1:
				set_mode("A")
			KEY_2, KEY_KP_2:
				set_mode("B")


func _process(delta: float) -> void:
	angle += deg_to_rad(float(config["rotation_speed_deg"])) * delta
	_update_rotation()
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	info_label.text = "FPS: %d\n描画回数: %d\nモード: %s (%d個)" % [
		Engine.get_frames_per_second(), draw_calls, mode, base_positions.size()]


func _update_rotation() -> void:
	# 表示中のほうだけ回す（非表示側の計算は無駄なので省く）
	var basis := Basis(Vector3.UP, angle)
	if mode == "B":
		for i in base_positions.size():
			multimesh.set_instance_transform(i, Transform3D(basis, base_positions[i]))
	else:
		for box in box_nodes:
			box.basis = basis
