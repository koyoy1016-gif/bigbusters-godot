extends Node3D
## 試作：横画面で、左のスティックで動き、ジャンプ、こうげきでボスに当てる。
## 「はじめる」で戦いが始まる。ボスは、床の予告の輪のあとに範囲攻撃をする（ジャンプでよける）。
## ブラウザ版では、合言葉の部屋に自動で入り、ほかの人の動き・ボスの体力・戦いの開始を共有する。
## 合言葉は URL の ?room=1234 で決める（なければ data の既定値）。
## 数値は data/prototype_stick.json。動きは stick_math.gd、ダメージは scripts/combat/damage.gd、
## ボスの攻撃の予定は scripts/combat/boss_pattern.gd、通信は scripts/network/。

## 戦いが終わった（倒した：true、全滅：false）。画面の流れ（game_flow.gd）が受け取る
signal round_ended(won_flag: bool)

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
const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const CrowdState := preload("res://scripts/combat/crowd_state.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Skills := preload("res://scripts/combat/skills.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")

var config: Dictionary = {}
var player: MeshInstance3D
var player_material: StandardMaterial3D
var boss: MeshInstance3D
var sub_crowd: Node3D
var recorder := Recorder.new()
var char_view: Node3D = null
var skills_cfg: Dictionary = {}
var skill_cooldown := 0.0
var skill_flash := 0.0
var facing := Vector2(0.0, -1.0)
var dash_left := 0.0
var dash_dir := Vector2.ZERO
var guard_left := 0.0
var bomb: Dictionary = {}
var summon_left := 0.0
var summon_timer := 0.0
var skill_fx: MeshInstance3D
var skill_fx_left := 0.0
var summon_node: MeshInstance3D
## 選んだキャラ（画面の流れから渡される。空なら、古い「枠で決まる役割」）
var selected_character := ""
var characters_cfg: Dictionary = {}
var crowd_state := CrowdState.new()
var touch_timer := 0.0
var since_sample := 0.0
var boss_material: StandardMaterial3D
var slam_ring: MeshInstance3D
var slam_material: StandardMaterial3D
var charge_strip: MeshInstance3D
var camera: Camera3D
var camera_offset := Vector3.ZERO
var portrait_mode := false
var camera_target := Vector3.ZERO
var player_marker_material: StandardMaterial3D
var charge_material: StandardMaterial3D
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
var round_end_ms := 0.0
## 画面の流れの中で動かすとき true。「もういちど」ボタンは、流れ側が受け持つので出さない
var flow_mode := false
var jump_flash := 0.0
var attack_flash := 0.0
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
	my_hp = role_value("hp")
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
	light.add_to_group("sun")
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

	# サブ敵の群れ（見た目だけ。時間で動くので通信は要らない）
	sub_crowd = SubCrowd.new()
	sub_crowd.name = "SubCrowd"
	add_child(sub_crowd)
	sub_crowd.setup(config, Vector2(bp[0], bp[1]))
	crowd_state.reset(int(config["sub_enemy_count"]), float(config["sub_enemy_hp"]))

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

	# 突進の予告の帯（ボスから手前へ伸びる、床の上の薄い板）
	charge_strip = MeshInstance3D.new()
	charge_strip.name = "ChargeStrip"
	var strip := BoxMesh.new()
	strip.size = Vector3(float(config["charge_half_width"]) * 2.0, 0.04, float(config["charge_length"]))
	charge_material = StandardMaterial3D.new()
	charge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	charge_material.albedo_color = Color(str(config["charge_color"]))
	strip.material = charge_material
	charge_strip.mesh = strip
	charge_strip.visible = false
	add_child(charge_strip)

	skill_fx = MeshInstance3D.new()
	skill_fx.name = "SkillFx"
	skill_fx.visible = false
	add_child(skill_fx)
	summon_node = MeshInstance3D.new()
	summon_node.name = "SummonAlly"
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.6, 0.8, 0.6)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.9, 0.95, 1.0)
	sbox.material = smat
	summon_node.mesh = sbox
	summon_node.visible = false
	add_child(summon_node)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = float(config["camera_fov"])
	var off: Array = config["camera_offset"]
	camera_offset = Vector3(off[0], off[1], off[2])
	camera.environment = make_environment(config)
	add_child(camera)
	camera.look_at_from_position(camera_offset, Vector3.ZERO, Vector3.UP)
	player_marker_material = _add_marker(player, Color(str(config["player_color"])))
	_attach_character()


## 自分のキャラのモデル（data/characters.json）があれば、箱の代わりに出す。なければ箱のまま
func _attach_character() -> void:
	var cfg := CharacterData.load_config()
	var def := selected_def() if selected_character != "" else CharacterData.find(cfg, str(cfg.get("player_character", "")))
	if def.is_empty() or not CharacterData.has_model(def):
		return
	var view := CharacterView.new()
	if not view.setup(def):
		view.free()
		return
	view.position = Vector3(0.0, -ground_y, 0.0)
	player.add_child(view)
	player.mesh = null
	char_view = view


## 動作に合わせて、モデルのアニメと向きを更新する（モデルがなければ何もしない）
func _update_character(delta: float) -> void:
	if char_view == null:
		return
	var airborne := player.position.y > ground_y + 0.05
	char_view.play_action(CharacterData.pick_action(downed, airborne, attack_flash > 0.0, stick_vec.length() > 0.1))
	if not downed:
		char_view.face(stick_vec, delta)


## 光が当たらない面が真っ黒にならないよう、まわりからの明るさ（環境光）を足す
static func make_environment(cfg: Dictionary) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(str(cfg["ambient_color"]))
	env.ambient_light_energy = float(cfg["ambient_energy"])
	return env


## 頭の上の印。ほかの物に隠れても見える（深さを無視する）ので、ボスの後ろに回っても、自分の位置が分かる
func _add_marker(parent: Node3D, color: Color) -> StandardMaterial3D:
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	var box := BoxMesh.new()
	box.size = Vector3.ONE * float(config["marker_size"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	box.material = mat
	marker.mesh = box
	marker.position = Vector3(0.0, float(config["marker_height"]), 0.0)
	parent.add_child(marker)
	return mat


## カメラは、自分の動きに合わせて、ゆっくりついていく（動きの一部だけ）。f 秒あたりの追いつきの速さは data で決める
func camera_update(delta: float) -> void:
	var goal := Vector3(player.position.x, 0.0, player.position.z) * float(config["camera_follow"])
	camera_target = camera_target.lerp(goal, Sync.smooth_weight(delta, float(config["camera_follow_per_sec"])))
	var pos := camera_target + camera_offset
	camera.transform = Transform3D(Basis.looking_at(camera_target - pos, Vector3.UP), pos)


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


func _exit_tree() -> void:
	# 部屋から抜ける（枠を空ける）
	if net_active:
		bridge.leave()


func _process(delta: float) -> void:
	var move := Vector2.ZERO if downed else stick_vec
	player.position = StickMath.step_position(player.position, move, role_value("move_speed"), delta, float(config["bounds"]))
	var r := StickMath.jump_update(player.position.y, velocity_y, delta, float(config["gravity"]), ground_y)
	player.position.y = r.x
	velocity_y = r.y
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	jump_flash = maxf(0.0, jump_flash - delta)
	attack_flash = maxf(0.0, attack_flash - delta)
	var boss_base := Color(str(config["enrage_color"])) if is_enraged() else Color(str(config["boss_color"]))
	boss_material.albedo_color = Color(str(config["boss_hit_color"])) if hit_flash > 0.0 else boss_base
	net_update(delta, Time.get_ticks_msec())
	combat_update(delta)
	_record_highlight(delta)
	_skill_update(delta)
	_update_character(delta)
	var crowd_t := maxf(0.0, (server_now_ms() - round_start_ms) / 1000.0) if round_active() else 0.0
	crowd_state.refresh(crowd_t)
	sub_crowd.update_at(crowd_t, crowd_state)
	_touch_update(delta)
	player_material.albedo_color = _player_color()
	player_marker_material.albedo_color = _slot_color(str(net_state.get("slot", "")))
	apply_orientation(Vector2(get_window().size) if get_window() != null else Vector2(16, 9))
	camera_update(delta)
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
	if _start_button_visible() and pos.distance_to(_start_center(screen)) <= float(config["start_radius_px"]):
		start_round()
	elif stick_touch == -1 and pos.x < screen.x * float(config["stick_zone_max_x_frac"]):
		stick_touch = index
		stick_vec = _stick_input(pos, screen)
	elif pos.distance_to(_skill_center(screen)) <= float(config["button_radius_px"]):
		skill_flash = float(config["press_flash_sec"])
		use_skill()
	elif pos.distance_to(_attack_center(screen)) <= float(config["button_radius_px"]):
		attack_flash = float(config["press_flash_sec"])
		attack()
	elif button_touch == -1 and pos.x >= screen.x * float(config["button_zone_min_x_frac"]):
		button_touch = index
		jump_flash = float(config["press_flash_sec"])
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
		velocity_y = role_value("jump_speed")


## 選んだキャラの定義。なければ {}
func selected_def() -> Dictionary:
	if selected_character == "":
		return {}
	if characters_cfg.is_empty():
		characters_cfg = CharacterData.load_config()
	return CharacterData.find(characters_cfg, selected_character)


## 自分の役割。選んだキャラがあれば、そのキャラの性能（data/characters.json）。なければ、枠で決まる古い役割（data の roles）
func role() -> Dictionary:
	var def := selected_def()
	if not def.is_empty():
		var r: Dictionary = (def["stats"] as Dictionary).duplicate()
		r["name"] = str(def["role"])
		r["character_name"] = str(def["name"])
		return r
	var slot := str(net_state.get("slot", ""))
	var roles: Dictionary = config["roles"]
	return roles.get(slot if roles.has(slot) else "p1", {})


func role_value(key: String) -> float:
	return float(role().get(key, config.get(key, 0.0)))


## 「はじめる／もういちど」ボタンを出すか。流れの中では、最初の「はじめる」だけ（もういちどは流れ側）
func _start_button_visible() -> bool:
	return not round_active() and (not flow_mode or round_count == 0)


## 与えたダメージの順位（多い順）。[{slot, hits}, ...]
func ranking_entries() -> Array:
	var me := str(net_state.get("slot", ""))
	var hits: Variant = net_state.get("hits", {})
	var entries: Array = [{"slot": me, "hits": my_hits}]
	if hits is Dictionary:
		for slot in net_state.get("members", []):
			if str(slot) == me:
				continue
			var v: Variant = hits.get(str(slot), null)
			if v is float or v is int:
				entries.append({"slot": str(slot), "hits": float(v)})
	entries.sort_custom(func(x, y): return float(x["hits"]) > float(y["hits"]))
	return entries


## 役割の名前（枠から）
func role_name_of(slot: String) -> String:
	if selected_character != "":
		# 選んだキャラの共有は、まだ（通信は今後）。ほかの人は「なかま」と出す
		return str(role().get("name", "")) if slot == str(net_state.get("slot", "p1")) or not net_active else str(config.get("others_label", "なかま"))
	var roles: Dictionary = config["roles"]
	return str(roles.get(slot if roles.has(slot) else "p1", {}).get("name", ""))


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
	round_end_ms = 0.0
	downed = false
	my_hits = 0.0
	my_hp = role_value("hp")
	boss.visible = true
	recorder.clear()
	since_sample = 0.0
	skill_cooldown = 0.0
	dash_left = 0.0
	guard_left = 0.0
	bomb = {}
	summon_left = 0.0
	summon_timer = 0.0
	crowd_state.reset(int(config["sub_enemy_count"]), float(config["sub_enemy_hp"]))
	touch_timer = 0.0
	boss_hp = float(config["boss_hp"])
	last_strike = _strike_count((server_now_ms() - start_ms) / 1000.0)
	if net_active:
		bridge.send_hits(0.0)
		bridge.send_hp(my_hp, round_start_ms)
	_recompute_boss_hp()


## ハイライト用に、全員の位置と合計ダメージを、決まった間隔で控える
func _record_highlight(delta: float) -> void:
	if not round_active():
		return
	since_sample += delta
	if since_sample < float(config["highlight_sample_sec"]):
		return
	since_sample = 0.0
	var t := (server_now_ms() - round_start_ms) / 1000.0
	var me := str(net_state.get("slot", "p1"))
	recorder.record(me, t, player.position.x, player.position.z, my_hits)
	var hits: Variant = net_state.get("hits", {})
	var half := float(config["bounds"])
	for slot in other_pos:
		var p: Vector2 = other_pos[slot]
		var v: Variant = hits.get(str(slot), 0.0) if hits is Dictionary else 0.0
		recorder.record(str(slot), t, p.x * 2.0 * half - half, p.y * 2.0 * half - half, float(v) if (v is float or v is int) else 0.0)


## ハイライトのデータ。ベストアタッカー（いちばん稼いだ人の、いちばん稼いだ区間）。なければ {}
func highlight_data() -> Dictionary:
	var best := recorder.best_window(float(config["highlight_window_sec"]))
	if best.is_empty():
		return {}
	best["points"] = recorder.path(str(best["slot"]), float(best["start"]), float(best["end"]))
	best["boss"] = Vector2(boss.position.x, boss.position.z)
	best["bounds"] = float(config["bounds"])
	best["color"] = _slot_color(str(best["slot"]))
	best["config"] = config
	return best


## こうげき：戦いの最中で、ボスに届く距離にいて、待ち時間が終わっていれば当たる。
## 与えた合計ダメージ（my_hits）を、部屋の全員に送る
func attack() -> bool:
	if not round_active() or downed or attack_cooldown > 0.0:
		return false
	var reach := role_value("attack_reach") + float(config["boss_size"]) * 0.5
	if not Damage.in_reach(player.position, boss.position, reach):
		return _attack_sub_enemy()
	attack_cooldown = role_value("attack_cooldown_sec")
	my_hits += Damage.damage_amount(role_value("attack_power"), float(config["attack_multiplier"]))
	_recompute_boss_hp()
	if net_active:
		bridge.send_hits(my_hits)
	return true


## ダメージを受ける。ダッシュ中は受けない。バリア中は、技の設定の割合に減らす
func _take_damage(amount: float) -> void:
	if dash_left > 0.0:
		return
	if guard_left > 0.0:
		amount *= float(_skill_def().get("damage_taken_multiplier", 1.0))
	_set_my_hp(Damage.apply_damage(my_hp, amount))


## 自分のXの技の名前。選んだキャラの技。なければ「斬る」
func skill_name() -> String:
	var def := selected_def()
	return str(def.get("skill", "斬る")) if not def.is_empty() else "斬る"


func _skill_def() -> Dictionary:
	if skills_cfg.is_empty():
		skills_cfg = Skills.load_config()
	var d: Variant = skills_cfg.get(skill_name(), {})
	return d if d is Dictionary else {}


func _damage_boss(amount: float) -> void:
	my_hits += amount
	_recompute_boss_hp()
	if net_active:
		bridge.send_hits(my_hits)


func _crowd_xz(i: int) -> Vector2:
	var p: Vector3 = sub_crowd.last_positions[i]
	return Vector2(p.x, p.z)


func _round_t() -> float:
	return (server_now_ms() - round_start_ms) / 1000.0


## Xの技を使う。使えたら true
func use_skill() -> bool:
	if not round_active() or downed or skill_cooldown > 0.0:
		return false
	var sc := _skill_def()
	if sc.is_empty():
		return false
	var origin := Vector2(player.position.x, player.position.z)
	var boss_xz := Vector2(boss.position.x, boss.position.z)
	var boss_r := float(config["boss_size"]) * 0.5
	var sub_r := float((config["sub_enemy_size"] as Array)[0]) * 0.5
	var power := role_value("attack_power")
	var respawn := float(config["sub_enemy_respawn_sec"])
	var dmg := Skills.skill_damage(power, sc)
	var kind := str(sc["kind"])
	match kind:
		"arc":
			var hit_any := false
			if Skills.in_arc(origin, facing, boss_xz, float(sc["radius"]), float(sc["half_angle_deg"]), boss_r):
				_damage_boss(dmg)
				hit_any = true
			for i in crowd_state.count():
				if crowd_state.is_alive(i) and Skills.in_arc(origin, facing, _crowd_xz(i), float(sc["radius"]), float(sc["half_angle_deg"]), sub_r):
					crowd_state.hit(i, dmg, _round_t(), respawn)
			var fx_mesh := CylinderMesh.new()
			fx_mesh.top_radius = float(sc["radius"])
			fx_mesh.bottom_radius = float(sc["radius"])
			fx_mesh.height = 0.05
			_show_fx(fx_mesh, Vector3(origin.x, 0.06, origin.y), sc)
			if hit_any:
				hit_flash = float(config["hit_flash_sec"])
		"line":
			var best := -2
			var hit_list: Array = []
			var d_boss := Skills.strip_distance(origin, facing, boss_xz, float(sc["length"]), float(sc["half_width"]), boss_r)
			if d_boss >= 0.0:
				hit_list.append([d_boss, -1])
			for i in crowd_state.count():
				if crowd_state.is_alive(i):
					var d := Skills.strip_distance(origin, facing, _crowd_xz(i), float(sc["length"]), float(sc["half_width"]), sub_r)
					if d >= 0.0:
						hit_list.append([d, i])
			hit_list.sort_custom(func(a, b): return a[0] < b[0])
			for h in hit_list:
				if bool(sc.get("pierce", false)) or best == -2:
					best = int(h[1])
					if int(h[1]) == -1:
						_damage_boss(dmg)
					else:
						crowd_state.hit(int(h[1]), dmg, _round_t(), respawn)
				else:
					break
			var box := BoxMesh.new()
			box.size = Vector3(float(sc["half_width"]) * 2.0, 0.05, float(sc["length"]))
			var mid := origin + facing.normalized() * float(sc["length"]) * 0.5
			_show_fx(box, Vector3(mid.x, 0.06, mid.y), sc, atan2(facing.x, facing.y))
		"dash":
			dash_dir = facing
			dash_left = float(sc["duration_sec"])
		"lob":
			var target := Skills.lob_point(origin, facing, float(sc["throw_distance"]), float(config["bounds"]))
			bomb = {"pos": target, "left": float(sc["delay_sec"]), "damage": dmg}
		"guard":
			guard_left = float(sc["duration_sec"])
			var disc := CylinderMesh.new()
			disc.top_radius = 1.4
			disc.bottom_radius = 1.4
			disc.height = 2.0
			_show_fx(disc, Vector3(origin.x, 1.0, origin.y), sc, 0.0, guard_left)
		"heal":
			my_hp = minf(role_value("hp"), my_hp + float(sc["heal"]))
			if net_active:
				bridge.send_hp(my_hp, round_start_ms)
			var disc2 := CylinderMesh.new()
			disc2.top_radius = 1.2
			disc2.bottom_radius = 1.2
			disc2.height = 0.05
			_show_fx(disc2, Vector3(origin.x, 0.06, origin.y), sc)
		"summon":
			summon_left = float(sc["duration_sec"])
			summon_timer = 0.0
	skill_cooldown = float(sc["cooldown_sec"])
	return true


## 技の見た目（床に、半透明の形を少しのあいだ出す）
func _show_fx(mesh: PrimitiveMesh, pos: Vector3, sc: Dictionary, yaw: float = 0.0, time: float = -1.0) -> void:
	if skill_fx == null:
		return
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(str(sc.get("fx_color", "#ffffffb0")))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	skill_fx.mesh = mesh
	skill_fx.position = pos
	skill_fx.rotation = Vector3(0.0, yaw, 0.0)
	skill_fx.visible = true
	skill_fx_left = time if time > 0.0 else float(sc.get("fx_sec", 0.2))


## 技の進み（待ち時間、ダッシュ、バリア、投げた爆弾、しょうかん）
func _skill_update(delta: float) -> void:
	skill_cooldown = maxf(0.0, skill_cooldown - delta)
	skill_flash = maxf(0.0, skill_flash - delta)
	if stick_vec.length() > 0.1 and not downed:
		facing = stick_vec.normalized()
	if skill_fx != null:
		skill_fx_left = maxf(0.0, skill_fx_left - delta)
		if skill_fx_left <= 0.0:
			skill_fx.visible = false
		elif guard_left > 0.0:
			skill_fx.position = Vector3(player.position.x, 1.0, player.position.z)
	if not round_active():
		dash_left = 0.0
		guard_left = 0.0
		bomb = {}
		summon_left = 0.0
		if summon_node != null:
			summon_node.visible = false
		return
	var sc := _skill_def()
	if dash_left > 0.0:
		var step := minf(delta, dash_left)
		dash_left -= delta
		var dist := float(sc.get("distance", 0.0)) * step / maxf(0.001, float(sc.get("duration_sec", 0.2)))
		var from := Vector2(player.position.x, player.position.z)
		var to := Skills.dash_target(from, dash_dir, dist, float(config["bounds"]))
		player.position.x = to.x
		player.position.z = to.y
	if guard_left > 0.0:
		guard_left = maxf(0.0, guard_left - delta)
	if not bomb.is_empty():
		bomb["left"] = float(bomb["left"]) - delta
		if float(bomb["left"]) <= 0.0:
			_explode_bomb(sc)
			bomb = {}
	if summon_left > 0.0:
		summon_left -= delta
		summon_timer += delta
		_update_summon_node(sc)
		if summon_timer >= float(sc.get("hit_interval_sec", 0.5)):
			summon_timer = 0.0
			if boss.visible:
				_damage_boss(Skills.skill_damage(role_value("attack_power"), sc))
	elif summon_node != null:
		summon_node.visible = false


func _explode_bomb(sc: Dictionary) -> void:
	var center: Vector2 = bomb["pos"]
	var dmg := float(bomb["damage"])
	var boss_xz := Vector2(boss.position.x, boss.position.z)
	if Skills.in_circle(center, boss_xz, float(sc["radius"]), float(config["boss_size"]) * 0.5):
		_damage_boss(dmg)
	var sub_r := float((config["sub_enemy_size"] as Array)[0]) * 0.5
	for i in crowd_state.count():
		if crowd_state.is_alive(i) and Skills.in_circle(center, _crowd_xz(i), float(sc["radius"]), sub_r):
			crowd_state.hit(i, dmg, _round_t(), float(config["sub_enemy_respawn_sec"]))
	var disc := CylinderMesh.new()
	disc.top_radius = float(sc["radius"])
	disc.bottom_radius = float(sc["radius"])
	disc.height = 0.05
	_show_fx(disc, Vector3(center.x, 0.06, center.y), sc)


## しょうかんした味方（見た目は、ボスのまわりを回る小さな箱。自分の画面だけ）
func _update_summon_node(sc: Dictionary) -> void:
	if summon_node == null:
		return
	summon_node.visible = true
	var a := float(sc.get("duration_sec", 8.0)) - summon_left
	summon_node.position = Vector3(boss.position.x + cos(a * 2.0) * 3.5, 0.4, boss.position.z + sin(a * 2.0) * 3.5)


## サブ敵への攻撃。届く距離のいちばん近い敵に当たる。ボスの体力には数えない（自分の画面の中だけ）
func _attack_sub_enemy() -> bool:
	var reach := role_value("attack_reach") + float((config["sub_enemy_size"] as Array)[0]) * 0.5
	var i := crowd_state.nearest_alive(sub_crowd.last_positions, player.position, reach)
	if i < 0:
		return false
	attack_cooldown = role_value("attack_cooldown_sec")
	var t := (server_now_ms() - round_start_ms) / 1000.0
	crowd_state.hit(i, Damage.damage_amount(role_value("attack_power"), float(config["attack_multiplier"])), t, float(config["sub_enemy_respawn_sec"]))
	return true


## サブ敵にふれていると、一定の間隔でダメージを受ける（ジャンプ中・ダウン中は受けない）
func _touch_update(delta: float) -> void:
	if not round_active() or downed:
		touch_timer = 0.0
		return
	var airborne := player.position.y > ground_y + float(config["dodge_height"]) or dash_left > 0.0
	var near := not airborne and crowd_state.nearest_alive(sub_crowd.last_positions, player.position, float(config["sub_enemy_touch_range"])) >= 0
	if not near:
		touch_timer = 0.0
		return
	touch_timer -= delta
	if touch_timer <= 0.0:
		touch_timer = float(config["sub_enemy_touch_interval_sec"])
		player_hit_flash = float(config["hit_flash_sec"])
		_take_damage(Damage.damage_amount(float(config["sub_enemy_touch_power"]), float(config["sub_enemy_touch_multiplier"])))


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
		round_end_ms = server_now_ms()
		round_ended.emit(true)
		boss.visible = false


## 戦いの進み：ボスの範囲攻撃（予告の輪、一撃）。時刻だけで決まるので、全員の画面で同じになる
## 戦いが始まってから t 秒までの、一撃の回数（いかりの切り替えを含む）
func _strike_count(t: float) -> int:
	return Pattern.strike_index_phased(t, float(config["slam_first_delay_sec"]), float(config["slam_interval_sec"]), float(config["enrage_after_sec"]), float(config["slam_interval_enraged_sec"]))


## ボスが、いかりの状態か（戦いの最中で、いかりの時刻を過ぎている）
func is_enraged() -> bool:
	return round_active() and (server_now_ms() - round_start_ms) / 1000.0 >= float(config["enrage_after_sec"])


## 結果の画面に出す行（かかった時間、自分と、ほかの人が与えたダメージ）
func build_result_lines() -> Array:
	var secs := int(maxf(0.0, round_end_ms - round_start_ms) / 1000.0)
	var lines: Array = [str(config["result_time_label"]) + "：" + str(secs / 60) + "：" + ("%02d" % (secs % 60))]
	lines.append(str(config["result_mine_label"]) + "：" + str(int(my_hits)))
	var entries := ranking_entries()
	if entries.size() > 1:
		var text := str(config["result_rank_label"]) + "："
		for i in entries.size():
			text += "  " + str(i + 1) + " " + role_name_of(str(entries[i]["slot"])) + " " + str(int(entries[i]["hits"]))
		lines.append(text)
	return lines


func combat_update(delta: float) -> void:
	player_hit_flash = maxf(0.0, player_hit_flash - delta)
	if not round_active():
		slam_ring.visible = false
		charge_strip.visible = false
		return
	var t := (server_now_ms() - round_start_ms) / 1000.0
	var first := float(config["slam_first_delay_sec"])
	var interval := float(config["slam_interval_sec"])
	var index := _strike_count(t)
	while last_strike < index and round_active():
		last_strike += 1
		_resolve_strike(last_strike)
	var progress := Pattern.telegraph_progress_phased(t, first, interval, float(config["slam_telegraph_sec"]), float(config["enrage_after_sec"]), float(config["slam_interval_enraged_sec"]))
	var upcoming := Pattern.attack_kind(index + 1, config["attack_cycle"])
	var alpha := lerpf(float(config["slam_min_alpha"]), float(config["slam_max_alpha"]), maxf(progress, 0.0))
	slam_ring.visible = progress >= 0.0 and round_active() and upcoming == "slam"
	charge_strip.visible = progress >= 0.0 and round_active() and upcoming == "charge"
	if slam_ring.visible:
		var base := Color(str(config["slam_color"]))
		slam_material.albedo_color = Color(base.r, base.g, base.b, alpha)
	if charge_strip.visible:
		var lane := Pattern.lane_x(index + 1, config["charge_lanes"])
		charge_strip.position = Vector3(lane, 0.03, boss.position.z + float(config["charge_length"]) * 0.5)
		var cb := Color(str(config["charge_color"]))
		charge_material.albedo_color = Color(cb.r, cb.g, cb.b, alpha)


## n 回目の一撃が当たった。輪（slam）か、突進の帯（charge）の中にいて、地面にいれば（ジャンプでよけていなければ）ダメージを受ける
func _resolve_strike(n: int) -> void:
	if downed:
		return
	var airborne := player.position.y > ground_y + float(config["dodge_height"])
	if airborne:
		return
	if dash_left > 0.0:
		return
	var kind := Pattern.attack_kind(n, config["attack_cycle"])
	var power := 0.0
	if kind == "charge":
		var lane := Pattern.lane_x(n, config["charge_lanes"])
		var from_z := boss.position.z
		if not Pattern.in_lane(player.position.x, player.position.z, lane, float(config["charge_half_width"]), from_z, from_z + float(config["charge_length"])):
			return
		power = float(config["charge_power"])
	else:
		if not Damage.in_reach(player.position, boss.position, float(config["slam_radius"])):
			return
		power = float(config["slam_power"])
	player_hit_flash = float(config["hit_flash_sec"])
	_take_damage(Damage.damage_amount(power, float(config["slam_multiplier"])))


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
			round_end_ms = server_now_ms()
			round_ended.emit(false)


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
	if round_start_ms <= 0.0:
		my_hp = role_value("hp")
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
	# いま部屋にいる人（members）の位置だけ出す。前の人の古い位置が残っていても、箱は出さない
	if state.has("members"):
		for slot in positions.keys():
			if not members.has(str(slot)):
				positions.erase(slot)
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
		_add_marker(others[slot], _slot_color(slot))
	return others[slot]


func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return StickMath.stick_vector(pos, _stick_center(screen), float(config["stick_radius_px"]), float(config["stick_dead_zone"]))


## 縦長の画面か
static func is_portrait(size: Vector2) -> bool:
	return size.y > size.x


## 配置の値。縦長の画面では、「…_portrait」があればそちらを使う
func _layout(key: String, screen: Vector2) -> Array:
	if is_portrait(screen) and config.has(key + "_portrait"):
		return config[key + "_portrait"]
	return config[key]


## 縦横の向きを合わせる：基準の大きさ（文字・ボタンの大きさの元）、カメラの見え方を切り替える。向きが変わったときだけ動く
func apply_orientation(window_size: Vector2) -> void:
	var portrait := is_portrait(window_size)
	if portrait == portrait_mode:
		return
	portrait_mode = portrait
	var base: Array = config["portrait_base_size"] if portrait else config["landscape_base_size"]
	var win := get_window()
	if win != null:
		win.content_scale_size = Vector2i(int(base[0]), int(base[1]))
	var off: Array = config["camera_offset_portrait"] if portrait else config["camera_offset"]
	camera_offset = Vector3(off[0], off[1], off[2])
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	camera.fov = float(config["camera_fov_portrait"]) if portrait else float(config["camera_fov"])


func _stick_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("stick_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _button_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("button_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _skill_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("skill_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _attack_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("attack_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _start_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("start_center_frac", screen)
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
	var jump_color := str(config["button_pressed_color"]) if (button_touch != -1 or jump_flash > 0.0) else str(config["button_color"])
	var bc := _button_center(screen)
	overlay.draw_circle(bc, br, Color(jump_color))
	_draw_centered(bc, str(config["button_label"]), button_text)

	var skc := _skill_center(screen)
	var skill_color := str(config["button_pressed_color"]) if skill_flash > 0.0 else (str(config["button_cooldown_color"]) if skill_cooldown > 0.0 else str(config["button_color"]))
	overlay.draw_circle(skc, br, Color(skill_color))
	_draw_centered(skc, skill_name(), button_text)

	var ac := _attack_center(screen)
	var attack_color := str(config["button_pressed_color"]) if attack_flash > 0.0 else (str(config["button_cooldown_color"]) if attack_cooldown > 0.0 else str(config["button_color"]))
	overlay.draw_circle(ac, br, Color(attack_color))
	_draw_centered(ac, str(config["attack_label"]), button_text)

	overlay.draw_string(font, Vector2(16, fs * 1.4), (str(config["hint_portrait"]) if is_portrait(screen) else str(config["hint"])) + "   " + str(config["build_label"]) + str(config["build_id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var bp: Array = _layout("bossbar_pos", screen)
	var bs: Array = _layout("bossbar_size", screen)
	var bar_rect := Rect2(Vector2(screen.x * bp[0], screen.y * bp[1]), Vector2(screen.x * bs[0], maxf(10.0, screen.y * bs[1])))
	overlay.draw_rect(bar_rect, Color(str(config["bossbar_back_color"])))
	var frac := clampf(boss_hp / float(config["boss_hp"]), 0.0, 1.0)
	overlay.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * frac, bar_rect.size.y)), Color(str(config["bossbar_color"])))
	var hp_text := str(config["boss_hp_label"]) + "  " + str(ceili(boss_hp)) + " / " + str(int(config["boss_hp"]))
	overlay.draw_string(font, Vector2(16, fs * 2.9), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var my_text := str(config["role_label"]) + "：" + str(role().get("name", "")) + (("（" + str(role()["character_name"]) + "）") if role().has("character_name") else "") + "  " + str(config["player_hp_label"]) + "  " + str(ceili(my_hp)) + " / " + str(int(role_value("hp")))
	if downed:
		my_text += "  " + str(config["down_text"])
	overlay.draw_string(font, Vector2(16, fs * 4.4), my_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var team := build_team_text()
	var next_line := 5.9
	if team != "":
		overlay.draw_string(font, Vector2(16, fs * next_line), team, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
		next_line += 1.5
	overlay.draw_string(font, Vector2(16, fs * next_line), build_room_text(net_state, room_code, net_active, config), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

	if _start_button_visible():
		var sc := _start_center(screen)
		overlay.draw_circle(sc, float(config["start_radius_px"]), Color(str(config["button_color"])))
		_draw_centered(sc, str(config["restart_label"]) if round_count > 0 else str(config["start_label"]), button_text)
	if won or lost:
		var result := str(config["win_text"]) if won else str(config["lose_text"])
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.22), result, text_color, 2.0)
		var lines := build_result_lines()
		for i in lines.size():
			_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.22 + fs * (2.2 + 1.5 * i)), str(lines[i]), text_color)
	if is_enraged() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.12), str(config["enrage_text"]), Color(str(config["enrage_color"])), 1.4)
