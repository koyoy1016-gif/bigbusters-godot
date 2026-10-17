extends Node3D
## スティックの試作（2つ目）：横画面で、左のスティックで1人を動かし、右のボタンでジャンプ、
## こうげきボタンで、近くのボスに当てる。
## 数値は data/prototype_stick.json。動きは stick_math.gd、ダメージは scripts/combat/damage.gd。

const CONFIG_PATH := "res://data/prototype_stick.json"
const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")

var config: Dictionary = {}
var player: MeshInstance3D
var boss: MeshInstance3D
var boss_material: StandardMaterial3D
var overlay: Control
var font: Font
var stick_vec := Vector2.ZERO
var stick_touch := -1
var button_touch := -1
var velocity_y := 0.0
var ground_y := 0.0
var boss_hp := 0.0
var attack_cooldown := 0.0
var hit_flash := 0.0
var won := false


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
	boss_hp = float(config["boss_hp"])
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

	# ボス（仮の箱）。位置は床の上の (x, z)
	boss = MeshInstance3D.new()
	boss.name = "Boss"
	var boss_box := BoxMesh.new()
	boss_box.size = Vector3.ONE * float(config["boss_size"])
	boss_material = StandardMaterial3D.new()
	boss_material.albedo_color = Color(str(config["boss_color"]))
	boss_box.material = boss_material
	boss.mesh = boss_box
	var bp: Array = config["boss_position"]
	boss.position = Vector3(bp[0], float(config["boss_size"]) * 0.5, bp[1])
	add_child(boss)

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
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	boss_material.albedo_color = Color(str(config["boss_hit_color"])) if hit_flash > 0.0 else Color(str(config["boss_color"]))
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


## 指が触れた。左の領域ならスティック、こうげき、右の領域ならジャンプ
func handle_press(index: int, pos: Vector2, screen: Vector2) -> void:
	if stick_touch == -1 and pos.x < screen.x * float(config["stick_zone_max_x_frac"]):
		stick_touch = index
		stick_vec = _stick_input(pos, screen)
	elif pos.distance_to(_attack_center(screen)) <= float(config["button_radius_px"]):
		attack()
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


## こうげき：ボスに届く距離にいて、待ち時間が終わっていれば当たる。倒したあとは当たらない
func attack() -> bool:
	if won or attack_cooldown > 0.0:
		return false
	var reach := float(config["attack_reach"]) + float(config["boss_size"]) * 0.5
	if not Damage.in_reach(player.position, boss.position, reach):
		return false
	attack_cooldown = float(config["attack_cooldown_sec"])
	boss_hp = Damage.apply_damage(boss_hp, Damage.damage_amount(float(config["attack_power"]), float(config["attack_multiplier"])))
	hit_flash = float(config["hit_flash_sec"])
	if boss_hp <= 0.0:
		won = true
		boss.visible = false
	return true


func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return StickMath.stick_vector(pos, _stick_center(screen), float(config["stick_radius_px"]), float(config["stick_dead_zone"]))


func _stick_center(screen: Vector2) -> Vector2:
	var f: Array = config["stick_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _button_center(screen: Vector2) -> Vector2:
	var f: Array = config["button_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _attack_center(screen: Vector2) -> Vector2:
	var f: Array = config["attack_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _draw_centered(center: Vector2, text: String, color: Color) -> void:
	var fs := int(config["ui_font_size"])
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	overlay.draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_overlay() -> void:
	var screen := overlay.size
	var fs := int(config["ui_font_size"])
	var text_color := Color(str(config["text_color"]))
	var button_text := Color(str(config["button_text_color"]))
	var r := float(config["stick_radius_px"])
	var c := _stick_center(screen)
	overlay.draw_circle(c, r, Color(str(config["stick_base_color"])))
	overlay.draw_circle(c + stick_vec * r, r * 0.4, Color(str(config["stick_knob_color"])))

	var br := float(config["button_radius_px"])
	var jump_color := str(config["button_pressed_color"]) if button_touch != -1 else str(config["button_color"])
	var bc := _button_center(screen)
	overlay.draw_circle(bc, br, Color(jump_color))
	_draw_centered(bc, str(config["button_label"]), button_text)

	var ac := _attack_center(screen)
	overlay.draw_circle(ac, br, Color(str(config["button_color"])))
	_draw_centered(ac, str(config["attack_label"]), button_text)

	overlay.draw_string(font, Vector2(16, fs * 1.4), str(config["hint"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var hp_text := str(config["boss_hp_label"]) + "  " + str(ceili(boss_hp)) + " / " + str(int(config["boss_hp"]))
	overlay.draw_string(font, Vector2(16, fs * 2.9), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

	if won:
		var win := str(config["win_text"])
		var w := font.get_string_size(win, HORIZONTAL_ALIGNMENT_LEFT, -1, fs * 2).x
		overlay.draw_string(font, Vector2(screen.x * 0.5 - w * 0.5, screen.y * 0.4), win, HORIZONTAL_ALIGNMENT_LEFT, -1, fs * 2, text_color)
