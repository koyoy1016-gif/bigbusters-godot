extends Node3D
## 負荷試験：骨つきの仮の人型を、何体まで同時に動かせるか測る（リアルな忍者を入れる前の目安）。
## 開き方：書き出したページの URL の最後に ?bench=1 を付ける。
## 画面で、体の数（たい）・1体の面の数（めん）・かげ（影）を変えて、FPS を見る。
## 「じどうそくてい」を押すと、決めた組み合わせを順に測って、結果を画面に出す（スクリーンショットで共有できる）。
## 数値は data/crowd_bench.json。人型は bench_character.gd。

const Char := preload("res://scripts/prototype/bench_character.gd")
const CONFIG_PATH := "res://data/crowd_bench.json"

var config: Dictionary = {}
var font: Font
var characters: Array = []
var material: StandardMaterial3D
var light: DirectionalLight3D
var camera: Camera3D
var info_label: Label
var count_value: Label
var tris_value: Label
var shadow_button: Button
var sweep_button: Button
var result_label: Label
var count_index := 0
var tris_index := 0
var shadow_on := false
var time_sec := 0.0
var portrait_mode := false
var applied_tris := 0

# 自動測定
var sweeping := false
var sweep_steps: Array = []
var sweep_index := 0
var sweep_elapsed := 0.0
var sweep_samples: Array = []
var sweep_results: Array = []
## 現在の FPS を返す関数（テストでは差し替える）
var fps_source: Callable = func() -> float: return Engine.get_frames_per_second()


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 測る組み合わせ（体の数 × 面の数）の一覧
static func build_sweep_steps(counts: Array, tris: Array) -> Array:
	var steps: Array = []
	for c in counts:
		for t in tris:
			steps.append({"count": int(c), "tris": int(t)})
	return steps


## 配列の中の、値の場所（JSONの数は小数で入るので、整数にして比べる）。なければ -1
static func index_of(values: Array, wanted: int) -> int:
	for i in values.size():
		if int(values[i]) == wanted:
			return i
	return -1


## 測った FPS の平均（空なら 0）
static func average(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for v in samples:
		sum += float(v)
	return sum / float(samples.size())


func _ready() -> void:
	if config.is_empty():
		config = load_config()
	font = load(str(config["ui_font_path"])) as Font
	count_index = int(config["default_count_index"])
	tris_index = int(config["default_triangles_index"])
	_build_world()
	_build_ui()
	_rebuild_characters()
	_apply_orientation(Vector2(get_window().size) if get_window() != null else Vector2(16, 9))


func _build_world() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(config["ground_size"])
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(str(config["ground_color"]))
	plane.material = gm
	ground.mesh = plane
	add_child(ground)
	light = DirectionalLight3D.new()
	light.name = "Light"
	light.add_to_group("sun")
	light.light_energy = float(config["light_energy"])
	var rot: Array = config["light_rotation_deg"]
	light.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	light.shadow_enabled = shadow_on
	add_child(light)
	material = StandardMaterial3D.new()
	material.albedo_color = Color(str(config["character_color"]))
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", int(config["font_size"]))
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _make_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(config["button_min_size"][0], config["button_min_size"][1])
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", int(config["button_font_size"]))
	b.pressed.connect(callback)
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	top.add_child(_make_label(str(config["title"])))
	info_label = _make_label("")
	top.add_child(info_label)
	result_label = _make_label("")
	top.add_child(result_label)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 12)
	layer.add_child(bottom)
	bottom.add_child(_stepper(str(config["count_label"]), func(): change_count(-1), func(): change_count(1), "count"))
	bottom.add_child(_stepper(str(config["tris_label"]), func(): change_tris(-1), func(): change_tris(1), "tris"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var shadow_row_label := _make_label(str(config["shadow_label"]))
	row.add_child(shadow_row_label)
	shadow_button = _make_button("", toggle_shadow)
	row.add_child(shadow_button)
	sweep_button = _make_button(str(config["sweep_label"]), start_sweep)
	row.add_child(sweep_button)
	bottom.add_child(row)
	_refresh_ui()


func _stepper(label_text: String, minus: Callable, plus: Callable, which: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_make_label(label_text))
	row.add_child(_make_button(str(config["minus_label"]), minus))
	var value := _make_label("")
	value.custom_minimum_size = Vector2(150, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	if which == "count":
		count_value = value
	else:
		tris_value = value
	row.add_child(_make_button(str(config["plus_label"]), plus))
	return row


func current_count() -> int:
	return int(config["counts"][count_index])


func current_tris() -> int:
	return int(config["triangles"][tris_index])


func change_count(step: int) -> void:
	var n: int = (config["counts"] as Array).size()
	count_index = clampi(count_index + step, 0, n - 1)
	_rebuild_characters()
	_refresh_ui()


func change_tris(step: int) -> void:
	var n: int = (config["triangles"] as Array).size()
	tris_index = clampi(tris_index + step, 0, n - 1)
	_rebuild_characters()
	_refresh_ui()


func toggle_shadow() -> void:
	shadow_on = not shadow_on
	light.shadow_enabled = shadow_on
	_refresh_ui()


func _refresh_ui() -> void:
	count_value.text = str(current_count())
	tris_value.text = str(current_tris()) if current_tris() < 1000 else str(current_tris() / 1000) + str(config["unit_k"])
	shadow_button.text = str(config["on_text"]) if shadow_on else str(config["off_text"])


## 体を作り直す（数・面の数を変えたとき）
func _rebuild_characters() -> void:
	for c in characters:
		(c as Node).queue_free()
	characters.clear()
	var positions := Char.layout_positions(current_count(), float(config["spacing"]))
	for i in positions.size():
		var sk := Char.build(current_tris(), material)
		sk.position = Vector3(positions[i].x, 0.0, positions[i].y)
		add_child(sk)
		characters.append(sk)
	applied_tris = Char.character_tris(Char.radial_for(current_tris()))


## 縦横に合わせて、画面の基準・カメラを切り替える
func _apply_orientation(window_size: Vector2) -> void:
	var portrait := window_size.y > window_size.x
	if portrait == portrait_mode and camera.fov > 0.0 and camera.position != Vector3.ZERO:
		return
	portrait_mode = portrait
	var base: Array = config["portrait_base_size"] if portrait else config["landscape_base_size"]
	var win := get_window()
	if win != null:
		win.content_scale_size = Vector2i(int(base[0]), int(base[1]))
	var pos: Array = config["camera_position_portrait"] if portrait else config["camera_position"]
	var target: Array = config["camera_target"]
	var p := Vector3(pos[0], pos[1], pos[2])
	var tg := Vector3(target[0], target[1], target[2])
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	camera.fov = float(config["camera_fov_portrait"]) if portrait else float(config["camera_fov"])
	camera.transform = Transform3D(Basis.looking_at(tg - p, Vector3.UP), p)


func start_sweep() -> void:
	if sweeping:
		return
	sweeping = true
	sweep_steps = build_sweep_steps(config["sweep_counts"], config["sweep_triangles"])
	sweep_index = 0
	sweep_results.clear()
	_begin_sweep_step()


func _begin_sweep_step() -> void:
	var step: Dictionary = sweep_steps[sweep_index]
	count_index = maxi(0, index_of(config["counts"], int(step["count"])))
	tris_index = maxi(0, index_of(config["triangles"], int(step["tris"])))
	_rebuild_characters()
	_refresh_ui()
	sweep_elapsed = 0.0
	sweep_samples.clear()


## 自動測定の1コマ分（delta 秒）。ならし（warmup）のあと、測る時間（measure）だけ FPS を集めて平均する
func sweep_update(delta: float) -> void:
	if not sweeping:
		return
	sweep_elapsed += delta
	var warm := float(config["sweep_warmup_sec"])
	if sweep_elapsed > warm:
		sweep_samples.append(float(fps_source.call()))
	if sweep_elapsed >= warm + float(config["sweep_measure_sec"]):
		var step: Dictionary = sweep_steps[sweep_index]
		sweep_results.append({"count": step["count"], "tris": step["tris"], "fps": average(sweep_samples)})
		sweep_index += 1
		if sweep_index >= sweep_steps.size():
			sweeping = false
			print(build_result_text())
		else:
			_begin_sweep_step()


## 結果の文字（1行に1組み合わせ）
func build_result_text() -> String:
	var lines: Array = []
	for r in sweep_results:
		lines.append(str(r["count"]) + str(config["count_label"]) + " " + str(int(r["tris"]) / 1000) + str(config["unit_k"]) + " : " + str(int(round(float(r["fps"])))) + " " + str(config["fps_label"]))
	return "\n".join(lines)


func _process(delta: float) -> void:
	time_sec += delta
	_apply_orientation(Vector2(get_window().size) if get_window() != null else Vector2(16, 9))
	for i in characters.size():
		Char.animate(characters[i], time_sec, float(i) * 0.7, float(config["swing_speed"]), float(config["swing_amount"]))
	sweep_update(delta)
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	info_label.text = str(config["fps_label"]) + " " + str(int(Engine.get_frames_per_second())) + "   " + str(config["draw_label"]) + " " + str(draws) + "   " + str(config["memory_label"]) + " " + str(int(mem)) + str(config["unit_mb"])
	if sweeping:
		result_label.text = str(config["sweep_running"]) + " " + str(sweep_index + 1) + "/" + str(sweep_steps.size())
	elif not sweep_results.is_empty():
		result_label.text = str(config["result_label"]) + "\n" + build_result_text()
	else:
		result_label.text = str(config["per_char_label"]) + " " + str(applied_tris)
