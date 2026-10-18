extends Node3D
## 試作：横画面で、左のスティックで動き、ジャンプ、こうげきでボスに当てる。
## 「はじめる」で戦いが始まる。ボスは、床の予告の輪のあとに範囲攻撃をする（ジャンプでよける）。
## ブラウザ版では、合言葉の部屋に自動で入り、ほかの人の動き・ボスの体力・戦いの開始を共有する。
## 合言葉は URL の ?room=1234 で決める（なければ data の既定値）。
## 数値は data/prototype_stick.json。動きは stick_math.gd、ダメージは scripts/combat/damage.gd、
## ボスの攻撃の予定は scripts/combat/boss_pattern.gd、通信は scripts/network/。

const CONFIG_PATH := "res://data/prototype_stick.json"
const FIREBASE_CONFIG_PATH := "res://data/firebase_config.json"
const SLOTS := ["p1", "p2", "p3", "p4"]
const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Sync := preload("res://scripts/network/position_sync.gd")
const BossSync := preload("res://scripts/network/boss_sync.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")

var config: Dictionary = {}
var player: MeshInstance3D
var player_material: StandardMaterial3D
var boss: MeshInstance3D
var boss_material: StandardMaterial3D
var slam_ring: MeshInstance3D
var slam_material: StandardMaterial3D
var overlay: Control
var font: Font
var stick_vec := Vector2.ZERO
var stick_touch := -1
var button_touch := -1
var velocity_y := 0.0
var ground_y := 0.0
var boss_hp := 0.0
var my_hits := 0.0
var others_hits := 0.0
var my_hp := 0.0
var downed := false
var attack_cooldown := 0.0
var hit_flash := 0.0
var player_hit_flash := 0.0
var won := false
var lost := false

# 戦い（0 のあいだは、戦いが始まっていない）
var round_start_ms := 0.0
var known_round := 0.0
var round_count := 0
var last_strike := 0
## 現在の時刻（ミリ秒）。テストでは差し替える
var clock_ms: Callable = func() -> float: return Time.get_unix_time_from_system() * 1000.0

# 通信（ブラウザ版だけ）
## JavaScriptBridge.eval の代わり。テストでは差し替える（橋渡しの js_eval も同じものにする）
var js_eval: Callable = func(text: String) -> Variant: return JavaScriptBridge.eval(text, true)
var use_network: bool = OS.has_feature("web")
var net_active := false
var bridge := Bridge.new()
var room_code := ""
var net_state: Dictionary = {}
var others := {}
var other_target := {}
var other_pos := {}
var since_poll := 0.0
var last_sent_ms := -100000


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


## URL の ?room= の値が正しい合言葉ならそれを使う。なければ既定の合言葉
static func pick_room_code(query: Variant, default_code: String, digit_count: int) -> String:
	if query is String and RoomCode.is_valid_code(query, digit_count):
		return query
	return default_code


## 部屋の状態から、画面に出す1行の文字を作る
static func build_room_text(state: Dictionary, code: String, active: bool, cfg: Dictionary) -> String:
	if not active:
		return str(cfg["room_offline"])
	match str(state.get("status", "")):
		"in_room":
			var members: Array = state.get("members", [])
			var text := str(cfg["room_label"]) + " " + code + "：" + str(cfg["room_members_prefix"]) + str(members.size()) + str(cfg["room_members_suffix"])
			var slot := str(state.get("slot", ""))
			if slot != "":
				text += "（" + str(cfg["room_you"]) + " " + slot + "）"
			return text
		"full":
			return str(cfg["room_full"])
		"reconnecting":
			return str(cfg["room_reconnecting"])
		_:
			return str(cfg["room_connecting"])


func _ready() -> void:
	if config.is_empty():
		config = load_config()
	font = load(str(config["ui_font_path"])) as Font
	ground_y = float(config["player_size"]) * 0.5
	boss_hp = float(config["boss_hp"])
	my_hp = float(config["player_hp"])
	_build_world()
	_build_ui()
	if use_network:
		_setup_network()


## 合言葉の部屋に自動で入る。ブラウザ側の入り口（window.bbFirebase）がなければ、通信なしで遊ぶ
func _setup_network() -> void:
	var digits := int(RoomCode.load_config().get("code_digits", 4))
	if str(js_eval.call("typeof window.bbFirebase")) != "object":
		return
	var query: Variant = js_eval.call("new URLSearchParams(window.location.search).get('room')")
	room_code = pick_room_code(query, str(config["default_room"]), digits)
	var config_json := JSON.stringify(CheckScreen.extract_firebase_config(CheckScreen.load_json(FIREBASE_CONFIG_PATH)))
	bridge.js_eval = js_eval
	net_active = true
	bridge.join(config_json, room_code, digits)


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

	player = _make_box("Player", float(config["player_size"]), Color(str(config["player_color"])))
	player_material = (player.mesh as BoxMesh).material as StandardMaterial3D
	player.position = Vector3(0.0, ground_y, 0.0)

	# ボス（仮の箱）。位置は床の上の (x, z)
	boss = _make_box("Boss", float(config["boss_size"]), Color(str(config["boss_color"])))
	boss_material = (boss.mesh as BoxMesh).material as StandardMaterial3D
	var bp: Array = config["boss_position"]
	boss.position = Vector3(bp[0], float(config["boss_size"]) * 0.5, bp[1])

	# 範囲攻撃の予告の輪（床の上の、薄い円盤）
	slam_ring = MeshInstance3D.new()
	slam_ring.name = "SlamRing"
	var disc := CylinderMesh.new()
	disc.top_radius = float(config["slam_radius"])
	disc.bottom_radius = float(config["slam_radius"])
	disc.height = 0.04
	slam_material = StandardMaterial3D.new()
	slam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slam_material.albedo_color = Color(str(config["slam_color"]))
	disc.material = slam_material
	slam_ring.mesh = disc
	slam_ring.position = Vector3(bp[0], 0.03, bp[1])
	slam_ring.visible = false
	add_child(slam_ring)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(config["camera_fov"])
	var off: Array = config["camera_offset"]
	add_child(camera)
	camera.look_at_from_position(Vector3(off[0], off[1], off[2]), Vector3.ZERO, Vector3.UP)


func _make_box(node_name: String, size: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	node.mesh = box
	add_child(node)
	return node


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
	var move := Vector2.ZERO if downed else stick_vec
	player.position = StickMath.step_position(player.position, move, float(config["move_speed"]), delta, float(config["bounds"]))
	var r := StickMath.jump_update(player.position.y, velocity_y, delta, float(config["gravity"]), ground_y)
	player.position.y = r.x
	velocity_y = r.y
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	boss_material.albedo_color = Color(str(config["boss_hit_color"])) if hit_flash > 0.0 else Color(str(config["boss_color"]))
	net_update(delta, Time.get_ticks_msec())
	combat_update(delta)
	player_material.albedo_color = _player_color()
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


## 指が触れた。「はじめる」（戦いの外）、左の領域ならスティック、こうげき、右の領域ならジャンプ
func handle_press(index: int, pos: Vector2, screen: Vector2) -> void:
	if not round_active() and pos.distance_to(_start_center(screen)) <= float(config["start_radius_px"]):
		start_round()
	elif stick_touch == -1 and pos.x < screen.x * float(config["stick_zone_max_x_frac"]):
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


## 地面にいるときだけ跳ぶ。ダウン中は跳べない
func jump() -> void:
	if downed:
		return
	if is_equal_approx(player.position.y, ground_y):
		velocity_y = float(config["jump_speed"])


## 戦いの最中か（始まっていて、まだ終わっていない）
func round_active() -> bool:
	return round_start_ms > 0.0 and not won and not lost


## サーバーの時刻（ミリ秒）。端末の時計が少しずれていても、全員で同じになるよう、ずれを足す
func server_now_ms() -> float:
	return float(clock_ms.call()) + float(net_state.get("offset", 0.0))


## 「はじめる／もういちど」。通信中は、開始の時刻を部屋に書く（全員の画面で同時に始まる）。通信なしなら、すぐ始める
func start_round() -> void:
	if round_active():
		return
	if net_active:
		if str(net_state.get("slot", "")) != "":
			bridge.start_round()
	else:
		_begin_round(server_now_ms())


## 戦いを始める。体力とダメージを元に戻す。途中から入った人は、その時点の攻撃の回数から数える
func _begin_round(start_ms: float) -> void:
	round_start_ms = start_ms
	round_count += 1
	won = false
	lost = false
	downed = false
	my_hits = 0.0
	my_hp = float(config["player_hp"])
	boss.visible = true
	boss_hp = float(config["boss_hp"])
	last_strike = Pattern.strike_index((server_now_ms() - start_ms) / 1000.0, float(config["slam_first_delay_sec"]), float(config["slam_interval_sec"]))
	if net_active:
		bridge.send_hits(0.0)
		bridge.send_hp(my_hp, round_start_ms)
	_recompute_boss_hp()


## こうげき：戦いの最中で、ボスに届く距離にいて、待ち時間が終わっていれば当たる。
## 与えた合計ダメージ（my_hits）を、部屋の全員に送る
func attack() -> bool:
	if not round_active() or downed or attack_cooldown > 0.0:
		return false
	var reach := float(config["attack_reach"]) + float(config["boss_size"]) * 0.5
	if not Damage.in_reach(player.position, boss.position, reach):
		return false
	attack_cooldown = float(config["attack_cooldown_sec"])
	my_hits += Damage.damage_amount(float(config["attack_power"]), float(config["attack_multiplier"]))
	_recompute_boss_hp()
	if net_active:
		bridge.send_hits(my_hits)
	return true


## 戦いの始まりの直後は、ほかの人の古いダメージ（前の戦いの分）が残っているので、少しのあいだ数えない
func _effective_others_hits() -> float:
	if round_start_ms <= 0.0:
		return 0.0
	if server_now_ms() - round_start_ms < float(config["round_grace_sec"]) * 1000.0:
		return 0.0
	return others_hits


## ボスの体力 = 最大 − 自分の合計 − ほかの人の合計。0になったら倒した（戦いの最中だけ）
func _recompute_boss_hp() -> void:
	var mine := my_hits if round_start_ms > 0.0 else 0.0
	var new_hp := BossSync.boss_hp(float(config["boss_hp"]), mine, _effective_others_hits())
	if new_hp < boss_hp - 0.001:
		hit_flash = float(config["hit_flash_sec"])
	boss_hp = new_hp
	if round_start_ms > 0.0 and boss_hp <= 0.0 and not won and not lost:
		won = true
		boss.visible = false


## 戦いの進み：ボスの範囲攻撃（予告の輪、一撃）。時刻だけで決まるので、全員の画面で同じになる
func combat_update(delta: float) -> void:
	player_hit_flash = maxf(0.0, player_hit_flash - delta)
	if not round_active():
		slam_ring.visible = false
		return
	var t := (server_now_ms() - round_start_ms) / 1000.0
	var first := float(config["slam_first_delay_sec"])
	var interval := float(config["slam_interval_sec"])
	var index := Pattern.strike_index(t, first, interval)
	while last_strike < index and round_active():
		last_strike += 1
		_resolve_strike()
	var progress := Pattern.telegraph_progress(t, first, interval, float(config["slam_telegraph_sec"]))
	slam_ring.visible = progress >= 0.0 and round_active()
	if slam_ring.visible:
		var base := Color(str(config["slam_color"]))
		slam_material.albedo_color = Color(base.r, base.g, base.b, lerpf(float(config["slam_min_alpha"]), float(config["slam_max_alpha"]), progress))


## 一撃が当たった。輪の中にいて、地面にいれば（ジャンプでよけていなければ）ダメージを受ける
func _resolve_strike() -> void:
	if downed:
		return
	var airborne := player.position.y > ground_y + float(config["dodge_height"])
	if airborne or not Damage.in_reach(player.position, boss.position, float(config["slam_radius"])):
		return
	player_hit_flash = float(config["hit_flash_sec"])
	_set_my_hp(Damage.apply_damage(my_hp, Damage.damage_amount(float(config["slam_power"]), float(config["slam_multiplier"]))))


func _set_my_hp(value: float) -> void:
	my_hp = value
	if my_hp <= 0.0:
		downed = true
	if net_active:
		bridge.send_hp(my_hp, round_start_ms)
	_check_wipe()


## 部屋にいる全員がダウンしたら、全滅
func _check_wipe() -> void:
	if downed and not lost and round_start_ms > 0.0:
		if BossSync.all_down(my_hp, net_state.get("hp", {}), str(net_state.get("slot", "")), net_state.get("members", []), round_start_ms):
			lost = true


## 通信：一定の間隔でブラウザ側の状態を読み、自分の位置を送り、ほかの人の箱をなめらかに動かす
func net_update(delta: float, now_ms: int) -> void:
	if not net_active:
		return
	since_poll += delta
	if since_poll >= float(config["net_poll_sec"]):
		since_poll = 0.0
		var state := bridge.read_state()
		if not state.is_empty():
			apply_net_state(state)
	var me := str(net_state.get("slot", ""))
	if me != "" and Sync.should_send(now_ms, last_sent_ms, int(config["send_interval_ms"])):
		last_sent_ms = now_ms
		var half := float(config["bounds"])
		bridge.send_position((player.position.x + half) / (2.0 * half), (player.position.z + half) / (2.0 * half))
	_update_others(delta)


## ブラウザ側の状態を受け取る：戦いの開始、ほかの人の位置・ダメージ・体力
func apply_net_state(state: Dictionary) -> void:
	net_state = state
	var me := str(state.get("slot", ""))
	var members: Array = state.get("members", [])
	others_hits = BossSync.others_total(state.get("hits", {}), me, members)
	# 戦いの開始：新しい開始の時刻が来たら、始める。古すぎる時刻（前の日の戦いなど）は無視する
	var r := float(state.get("round", 0.0))
	if r != known_round:
		known_round = r
		var age_ms := server_now_ms() - r
		if r > 0.0 and age_ms <= float(config["round_max_sec"]) * 1000.0 and age_ms >= -float(config["round_future_sec"]) * 1000.0:
			_begin_round(r)
	_recompute_boss_hp()
	_check_wipe()
	var positions := Sync.parse_positions(state.get("positions", {}))
	positions.erase(me)
	for slot in positions:
		other_target[slot] = positions[slot]
	for slot in other_target.keys():
		if not positions.has(slot):
			other_target.erase(slot)
			other_pos.erase(slot)
			if others.has(slot):
				(others[slot] as Node).queue_free()
				others.erase(slot)


func _update_others(delta: float) -> void:
	var half := float(config["bounds"])
	var weight := Sync.smooth_weight(delta, float(config["smooth_per_sec"]))
	for slot in other_target:
		var target: Vector2 = other_target[slot]
		var current: Vector2 = other_pos.get(slot, target)
		current = current.lerp(target, weight)
		other_pos[slot] = current
		var node := _other_node(str(slot))
		node.position = Vector3(current.x * 2.0 * half - half, ground_y, current.y * 2.0 * half - half)


func _slot_color(slot: String) -> Color:
	var colors: Array = config["slot_colors"]
	var index := SLOTS.find(slot)
	if index < 0:
		return Color(str(config["player_color"]))
	return Color(str(colors[index % colors.size()]))


## 自分の箱の色：同じ人は、全員の画面で同じ色（枠の色）。ダウン中・ダメージを受けた瞬間は別の色
func _player_color() -> Color:
	if downed:
		return Color(str(config["player_down_color"]))
	if player_hit_flash > 0.0:
		return Color(str(config["player_hit_color"]))
	return _slot_color(str(net_state.get("slot", "")))


func _other_node(slot: String) -> MeshInstance3D:
	if not others.has(slot):
		others[slot] = _make_box("Other_" + slot, float(config["player_size"]), _slot_color(slot))
	return others[slot]


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


func _start_center(screen: Vector2) -> Vector2:
	var f: Array = config["start_center_frac"]
	return Vector2(screen.x * f[0], screen.y * f[1])


func _draw_centered(center: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	var fs := int(float(config["ui_font_size"]) * scale)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	overlay.draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## なかまの体力の一覧（この戦いに出ている、自分以外）
func build_team_text() -> String:
	var fighters := BossSync.others_hp(net_state.get("hp", {}), str(net_state.get("slot", "")), net_state.get("members", []), round_start_ms)
	var text := ""
	for slot in fighters:
		text += "  " + str(slot) + " " + str(ceili(float(fighters[slot])))
	if text == "":
		return ""
	return str(config["team_label"]) + text


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
	var my_text := str(config["player_hp_label"]) + "  " + str(ceili(my_hp)) + " / " + str(int(config["player_hp"]))
	if downed:
		my_text += "  " + str(config["down_text"])
	overlay.draw_string(font, Vector2(16, fs * 4.4), my_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var team := build_team_text()
	var next_line := 5.9
	if team != "":
		overlay.draw_string(font, Vector2(16, fs * next_line), team, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
		next_line += 1.5
	overlay.draw_string(font, Vector2(16, fs * next_line), build_room_text(net_state, room_code, net_active, config), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

	if not round_active():
		var sc := _start_center(screen)
		overlay.draw_circle(sc, float(config["start_radius_px"]), Color(str(config["button_color"])))
		_draw_centered(sc, str(config["restart_label"]) if round_count > 0 else str(config["start_label"]), button_text)
	if won or lost:
		var result := str(config["win_text"]) if won else str(config["lose_text"])
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.3), result, text_color, 2.0)
