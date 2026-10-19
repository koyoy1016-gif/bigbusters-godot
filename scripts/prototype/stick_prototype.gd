extends Node3D
## 試作：横画面で、左のスティックで動き、ジャンプ、こうげきでボスに当てる。
## 「はじめる」で戦いが始まる。ボスは、床の予告の輪のあとに範囲攻撃をする（ジャンプでよける）。
## ブラウザ版では、合言葉の部屋に自動で入り、ほかの人の動き・ボスの体力・戦いの開始を共有する。
## 合言葉は URL の ?room=1234 で決める（なければ data の既定値）。
## 数値は data/prototype_stick.json。動きは stick_math.gd、ダメージは scripts/combat/damage.gd、
## ボスの攻撃の予定は scripts/combat/boss_pattern.gd、通信は scripts/network/。

## 戦いが終わった（倒した：true、全滅：false）。画面の流れ（game_flow.gd）が受け取る
signal round_ended(won_flag: bool)
## 新しい戦いが始まった（通信で、ほかの人が始めた場合も）
signal round_started

const CONFIG_PATH := "res://data/prototype_stick.json"
const FIREBASE_CONFIG_PATH := "res://data/firebase_config.json"
const SLOTS := ["p1", "p2", "p3", "p4"]
const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const SfxPlayer := preload("res://scripts/audio/sfx.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Sync := preload("res://scripts/network/position_sync.gd")
const BossSync := preload("res://scripts/network/boss_sync.gd")
const BossModel := preload("res://scripts/boss/boss_model.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const CrowdState := preload("res://scripts/combat/crowd_state.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")
const BossMotion := preload("res://scripts/combat/boss_motion.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const BossRage := preload("res://scripts/combat/boss_rage.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var config: Dictionary = {}
var player: MeshInstance3D
var player_material: StandardMaterial3D
var boss: MeshInstance3D
var boss_model: Node3D
var boss_clock := 0.0
var boss_was_hit := false
var sub_crowd: Node3D
var recorder := Recorder.new()
var char_view: Node3D = null
var facing := Vector2(0.0, -1.0)
## 味方の技を受けとった（技の時刻の記録、見た目の点滅）
## 選んだキャラ（画面の流れから渡される。空なら、古い「枠で決まる役割」）
var selected_character := ""
var characters_cfg: Dictionary = {}
var crowd_state := CrowdState.new()
var gauge := Gauge.new(Actions.load_config())  ## 必殺技のゲージ
var banner := {"text": "", "who": "", "left": 0.0, "total": 1.0}  ## 画面に出す必殺技名
var actions := Actions.new()  ## 通常・サブ・メインの攻撃の進み（data/actions.json）
var button_flash := {}  ## 押したボタンの色を、少しのあいだ変える（ボタンid → 残り秒）
var touch_timer := 0.0
var since_sample := 0.0
var boss_material: StandardMaterial3D
var attacks_cfg: Dictionary = {}
var ai := BossAI.new()  ## ボスの攻撃の選び方（重み付きランダム）
var motion := BossMotion.new()  ## ボスの歩き（位置と向き）
var phase := BossPhase.new()  ## ボスの体力の2段階（第1形態 → 倒れて覚醒 → 第2形態）
var rage := BossRage.new()  ## 版69：近くからの攻撃が多い間、ボスが怒る（攻撃が速く、つかみ投げが多くなる）
var phase_text := {"text": "", "left": 0.0}  ## 形態が変わったときに、画面に出す文字
var hazard_nodes: Array = []
var hazard_done := {}
var grab_locked := {}
var stun_left := 0.0
var grab_state := {}
var sfx: Node = null
var last_attack_n := -1
var grab_hand := Vector3.ZERO
var grab_last_target := Vector3.ZERO
var other_lift := {}
## AIの味方（通信なし、または部屋に自分ひとりのとき、空いた枠を埋める）。テストでは既定でオフ（流れの側がオンにする）
var ai_enabled := false
var ai_picks: Array = []
var ai_cfg: Dictionary = {}
var ai_allies := {}
var ai_hits := {}
var ai_done := {}
var ai_rng := RandomNumberGenerator.new()
var current_hazards: Array = []
var current_attack: Dictionary = {}
var current_attack_u := 0.0
var camera: Camera3D
var camera_offset := Vector3.ZERO
var portrait_mode := false
var camera_target := Vector3.ZERO
var player_marker_material: StandardMaterial3D
var overlay: Control
var font: Font
var stick_vec := Vector2.ZERO
var stick_touch := -1
var ground_y := 0.0
var boss_hp := 0.0
var my_hits := 0.0
var others_hits := 0.0
var my_hp := 0.0
var downed := false
var hit_flash := 0.0
var player_hit_flash := 0.0
var won := false
var lost := false

# 戦い（0 のあいだは、戦いが始まっていない）
var round_start_ms := 0.0
var known_round := 0.0
var round_count := 0
var round_end_ms := 0.0
## 画面の流れの中で動かすとき true。「もういちど」ボタンは、流れ側が受け持つので出さない
var flow_mode := false
## 現在の時刻（ミリ秒）。テストでは差し替える
var clock_ms: Callable = func() -> float: return Time.get_unix_time_from_system() * 1000.0

# 通信（ブラウザ版だけ）
## JavaScriptBridge.eval の代わり。テストでは差し替える（橋渡しの js_eval も同じものにする）
var js_eval: Callable = func(text: String) -> Variant: return JavaScriptBridge.eval(text, true)
var use_network: bool = OS.has_feature("web")
var net_active := false
var last_char_sent_ms := -100000
var other_views := {}  ## 枠 → ほかの人のモデルの見た目（CharacterView）
var bridge := Bridge.new()
var room_code := ""
## 画面の流れ（game_flow）が決めた合言葉。空なら、URLの ?room=、なければ既定
var forced_room_code := ""
## 画面の流れ（game_flow）が、ロビーから入っている部屋の橋渡し。あれば、それを使い、部屋に入りも出もしない
var shared_bridge: RefCounted = null
## 部屋に前からあった戦いの開始時刻（これと同じ間は、新しい戦いとして始めない）
var ignore_round := 0.0
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
	sfx = SfxPlayer.new()
	sfx.name = "Sfx"
	add_child(sfx)
	_build_ui()
	if use_network or shared_bridge != null:
		_setup_network()


## 合言葉の部屋に自動で入る。ブラウザ側の入り口（window.bbFirebase）がなければ、通信なしで遊ぶ
func _setup_network() -> void:
	if shared_bridge != null:
		bridge = shared_bridge
		room_code = forced_room_code
		known_round = ignore_round
		net_active = true
		return
	var digits := int(RoomCode.load_config().get("code_digits", 4))
	if str(js_eval.call("typeof window.bbFirebase")) != "object":
		return
	var query: Variant = js_eval.call("new URLSearchParams(window.location.search).get('room')")
	room_code = forced_room_code if RoomCode.is_valid_code(forced_room_code, digits) else pick_room_code(query, str(config["default_room"]), digits)
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

	# ボス：大きな胴体（これが本体）に、頭・足・長い手2本を付ける。位置は床の上の (x, z)
	var bcfg := BossModel.load_config()
	boss = MeshInstance3D.new()
	boss.name = "Boss"
	boss_material = StandardMaterial3D.new()
	boss_material.roughness = 0.55
	StyleFx.style_material(boss_material, "skin")
	StyleFx.apply_outline(boss_material, float(StyleFx.config().get("outline_width_boss", 0.05)))
	add_child(boss)
	var bp: Array = config["boss_position"]
	boss.position = Vector3(bp[0], 0.0, bp[1])
	boss_model = BossModel.new()
	boss_model.name = "BossModel"
	boss.add_child(boss_model)
	boss_model.build(bcfg, boss_material)

	# サブ敵の群れ（見た目だけ。時間で動くので通信は要らない）
	sub_crowd = SubCrowd.new()
	sub_crowd.name = "SubCrowd"
	add_child(sub_crowd)
	sub_crowd.setup(config, Vector2(bp[0], bp[1]))
	_reset_sub_enemies()

	# ボスの攻撃の見た目（予告の輪、帯、チラシ、手）は、使うときに作って使いまわす
	attacks_cfg = Attacks.load_config()
	motion.reset(Vector2(float(bp[0]), float(bp[1])))


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
	_raise_marker(player)


## 印（頭の上の小さな箱）を、モデルの頭の上に上げる
func _raise_marker(node: Node3D) -> void:
	var marker := node.get_node_or_null("Marker") as Node3D
	if marker != null:
		marker.position.y = float(config.get("marker_height_model", config["marker_height"]))


## 動作に合わせて、モデルのアニメと向きを更新する（モデルがなければ何もしない）
func _update_character(delta: float) -> void:
	if char_view == null:
		return
	if downed:
		char_view.play_action("down")
		return
	# 攻撃の動きの間は、アニメは攻撃の出来事（steps）が決める。終わったら、走る・待つに戻る
	if not actions.busy():
		char_view.play_action(CharacterData.pick_action(false, false, false, stick_vec.length() > 0.1 and actions.move_scale() > 0.0))
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


var cam_boss_lift := Vector2.ZERO  ## ボスが高いときに、カメラが上を見る量（x）と、引く量（y）


## カメラは、自分の動きに合わせて、ゆっくりついていく（動きの一部だけ）。f 秒あたりの追いつきの速さは data で決める
func camera_update(delta: float) -> void:
	var goal := Vector3(player.position.x, 0.0, player.position.z) * float(config["camera_follow"])
	camera_target = camera_target.lerp(goal, Sync.smooth_weight(delta, float(config["camera_follow_per_sec"])))
	# 版63：ボスが高く跳んだときは、少し上を見て、少し引く（ボスの頭が画面から出ないように）。data の camera_boss_frame
	var bf: Dictionary = config.get("camera_boss_frame", {})
	var over := maxf(0.0, (motion.height if motion != null else 0.0) - float(bf.get("start_height", 1.5)))
	var want_lift := Vector2(minf(over * float(bf.get("look_up_per_m", 0.0)), float(bf.get("max_look_up", 0.0))), minf(over * float(bf.get("back_per_m", 0.0)), float(bf.get("max_back", 0.0))))
	cam_boss_lift = cam_boss_lift.lerp(want_lift, Sync.smooth_weight(delta, float(bf.get("follow_per_sec", 3.0))))
	var look_at := camera_target + Vector3(0.0, cam_boss_lift.x, 0.0)
	var back_dir := Vector3(0.0, camera_offset.y, camera_offset.z).normalized() if camera_offset.length() > 0.01 else Vector3.BACK
	var pos := camera_target + camera_offset + back_dir * cam_boss_lift.y
	# 画面のゆれ（強い攻撃に当たったとき）
	if shake_left > 0.0:
		shake_left = maxf(0.0, shake_left - delta)
		var k := shake_left / 0.3
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0)) * shake_amp * k
		if shake_left <= 0.0:
			shake_amp = 0.0
	camera.transform = Transform3D(Basis.looking_at(look_at - pos, Vector3.UP), pos)


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


## 休止：ハイライト・報酬の間、部屋に残したまま、画面と操作だけ止める（全員さいせんのため）
var dormant := false


func set_dormant(on: bool) -> void:
	dormant = on
	for child in get_children():
		if child is Node3D:
			(child as Node3D).visible = not on
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = not on
	if on:
		stick_vec = Vector2.ZERO
		stick_touch = -1


## 休止中の更新：部屋の状態だけ読む（新しい戦いの開始を受け取るため）
func _dormant_update(delta: float) -> void:
	if not net_active:
		return
	since_poll += delta
	if since_poll >= float(config["net_poll_sec"]):
		since_poll = 0.0
		var state := bridge.read_state()
		if not state.is_empty():
			apply_net_state(state)


## 部屋にいるのに、この戦いに出ていない人（あとから入ってきた人）。戦いに出た人は、開始のとき体力を部屋に書いている
func idle_members() -> Array:
	var out: Array = []
	if not net_active:
		return out
	var me := str(net_state.get("slot", ""))
	var joined := BossSync.others_hp(net_state.get("hp", {}), me, net_state.get("members", []), round_start_ms)
	for slot in net_state.get("members", []):
		if str(slot) != me and not joined.has(str(slot)):
			out.append(str(slot))
	return out


## 「さいせん」「ロビー」の投票を送る。いまの戦いの開始時刻といっしょに書く
func send_rematch_vote(vote: String) -> void:
	if net_active and str(net_state.get("slot", "")) != "":
		bridge.send_vote(vote, round_start_ms)


## いまの戦いについての投票（{枠: "rematch" か "lobby"}）
func rematch_votes() -> Dictionary:
	var raw: Variant = net_state.get("votes", {})
	return Logic.current_votes(raw if raw is Dictionary else {}, round_start_ms)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	# 部屋から抜ける（枠を空ける）
	if net_active and shared_bridge == null:
		bridge.leave()


func _process(delta: float) -> void:
	_hitstop_update()
	kb_guard_left = maxf(0.0, kb_guard_left - delta)
	if dormant:
		_dormant_update(delta)
		return
	var move := Vector2.ZERO if (downed or stun_left > 0.0) else stick_vec * actions.move_scale()
	player.position = StickMath.step_position(player.position, move, role_value("move_speed"), delta, float(config["bounds"]))
	hit_flash = maxf(0.0, hit_flash - delta)
	banner["left"] = maxf(0.0, float(banner["left"]) - delta)
	for id in button_flash.keys():
		button_flash[id] = maxf(0.0, float(button_flash[id]) - delta)
	if boss_model != null:
		boss_model.set_flash(hit_flash > 0.0)
	net_update(delta, Time.get_ticks_msec())
	combat_update(delta)
	boss_clock += delta
	if boss_model != null and boss.visible:
		_pose_boss(delta)
	_record_highlight(delta)
	_actions_update(delta)
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
	if dormant:
		return
	var screen := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			handle_press(event.index, event.position, screen)
		else:
			handle_release(event.index)
	elif event is InputEventScreenDrag:
		handle_drag(event.index, event.position, screen)


## 指が触れた。「はじめる」（戦いの外）、左の領域ならスティック、それ以外は、3つの攻撃ボタン
func handle_press(index: int, pos: Vector2, screen: Vector2) -> void:
	if _start_button_visible() and pos.distance_to(_start_center(screen)) <= float(config["start_radius_px"]):
		start_round()
	elif stick_touch == -1 and pos.x < screen.x * float(config["stick_zone_max_x_frac"]):
		stick_touch = index
		stick_vec = _stick_input(pos, screen)
	else:
		var id := _button_at(pos, screen)
		if id != "":
			button_flash[id] = float(config["press_flash_sec"])
			if not _me_held():
				perform(id)  # 版70：つかまれている間は、どのボタンも効かない（逃げる仕組みはない）


func handle_drag(index: int, pos: Vector2, screen: Vector2) -> void:
	if index == stick_touch:
		stick_vec = _stick_input(pos, screen)


func handle_release(index: int) -> void:
	if index == stick_touch:
		stick_touch = -1
		stick_vec = Vector2.ZERO


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


## サブ敵を出すか（data の sub_enemy_enabled）。出さないときは数を0にして、見た目も隠す
func sub_enemies_enabled() -> bool:
	return bool(config.get("sub_enemy_enabled", true))


func _reset_sub_enemies() -> void:
	crowd_state.reset(int(config["sub_enemy_count"]) if sub_enemies_enabled() else 0, float(config["sub_enemy_hp"]))
	if sub_crowd != null:
		sub_crowd.visible = sub_enemies_enabled()


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
	for slot in ai_allies:
		entries.append({"slot": str(slot), "hits": float(ai_hits.get(slot, 0.0))})
	entries.sort_custom(func(x, y): return float(x["hits"]) > float(y["hits"]))
	return entries


## その枠のキャラの定義。自分は選んだキャラ（なければ主人公）。ほかの人は、部屋で共有されたキャラ（まだなら {}）
func char_def_of(slot: String) -> Dictionary:
	if characters_cfg.is_empty():
		characters_cfg = CharacterData.load_config()
	if ai_allies.has(slot):
		return CharacterData.find(characters_cfg, str(ai_allies[slot]["id"]))
	if slot == str(net_state.get("slot", "p1")) or not net_active:
		return selected_def() if selected_character != "" else CharacterData.find(characters_cfg, str(characters_cfg.get("player_character", "")))
	var chars: Variant = net_state.get("chars", {})
	if chars is Dictionary and chars.has(slot):
		return CharacterData.find(characters_cfg, str(chars[slot]))
	return {}


## 役割の名前（枠から）。選んだキャラがあれば、そのキャラの役割（ほかの人は、共有されたキャラ。まだなら「なかま」）
func role_name_of(slot: String) -> String:
	if ai_allies.has(slot):
		return str(char_def_of(slot).get("role", ""))
	if selected_character != "":
		if slot == str(net_state.get("slot", "p1")) or not net_active:
			return str(role().get("name", ""))
		var def := char_def_of(slot)
		return str(def.get("role", "")) if not def.is_empty() else str(config.get("others_label", "なかま"))
	var roles: Dictionary = config["roles"]
	return str(roles.get(slot if roles.has(slot) else "p1", {}).get("name", ""))


## 自分のキャラを、部屋に知らせる。まだ知らせていないか、部屋の記録と違うときだけ送る（2秒以上あける）
func _share_my_character(now_ms: int) -> void:
	var me := str(net_state.get("slot", ""))
	var def := char_def_of(me)
	if me == "" or def.is_empty():
		return
	var mine := str(def.get("id", ""))
	var chars: Variant = net_state.get("chars", {})
	var shared := str(chars.get(me, "")) if chars is Dictionary else ""
	if shared == mine or now_ms - last_char_sent_ms < int(config.get("char_resend_ms", 2000)):
		return
	last_char_sent_ms = now_ms
	bridge.send_char(mine)


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


## 戦いの始まりで、自分の枠の最初の位置に戻る（ひとり用は p1 の位置）
func _return_to_spawn() -> void:
	var spawns: Dictionary = config.get("spawn_points", {})
	var slot := str(net_state.get("slot", "p1")) if net_active else "p1"
	var sp: Array = spawns.get(slot, spawns.get("p1", [0.0, 6.0]))
	player.position = Vector3(float(sp[0]), ground_y, float(sp[1]))
	stick_vec = Vector2.ZERO


## 戦いを始める。体力とダメージを元に戻す。途中から入った人は、その時点の攻撃の回数から数える
func _begin_round(start_ms: float) -> void:
	round_start_ms = start_ms
	round_count += 1
	won = false
	lost = false
	round_end_ms = 0.0
	downed = false
	my_hits = 0.0
	_return_to_spawn()
	my_hp = role_value("hp")
	boss.visible = true
	recorder.clear()
	since_sample = 0.0
	actions.reset()
	gauge.reset()
	banner["left"] = 0.0
	button_flash = {}
	_reset_sub_enemies()
	touch_timer = 0.0
	boss_hp = float(config["boss_hp"])
	phase.reset(float(config["boss_hp"]), float(config.get("boss_hp_awake", config["boss_hp"])), _trans_sec(), float(config.get("boss_hp_refill_sec", 1.2)))
	awake_rides_done = 0
	awake_storms_done = {}
	quick_grab_done = false
	var qw: Array = config.get("quick_grab_window", [])
	quick_grab_at = Attacks.rng_for(round_start_ms, 7331).randf_range(float(qw[0]), float(qw[1])) if qw.size() == 2 else -1.0
	phase_text = {"text": "", "left": 0.0}
	if boss_model != null:
		boss_model.reset_form()
	hazard_done = {}
	grab_locked = {}
	ai.reset(attacks_cfg, start_ms)
	rage.setup((attacks_cfg.get("ai", {}) as Dictionary).get("rage", {}))
	rage.enabled = not net_active or rage.online  # 通信中は、画面ごとに数がちがうので、ふだんは怒らない
	ai_forecast = []
	ai_forecast_t = -999.0
	ult_dash_from = Vector3.INF
	puddle_seen = {}
	field.clear()
	_landed = {}
	_ignited = {}
	motion.reset(motion.home)
	boss.position = Vector3(motion.pos.x, 0.0, motion.pos.y)
	boss.rotation.y = 0.0
	stun_left = 0.0
	grab_state = {}
	last_attack_n = -1
	_ai_reset()
	if net_active:
		bridge.send_hits(0.0)
		bridge.send_hp(my_hp, round_start_ms)
	_recompute_boss_hp()
	round_started.emit()


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
	if str(current_attack.get("kind", "")) == Attacks.BOTTLE_RIDE:
		recorder.block(t)  # 巨大酒瓶ライドの間は、ハイライトに入れない（版63）
	if boss != null and boss_model != null:
		recorder.record_boss(t, boss.position, boss.rotation.y, str(current_attack.get("kind", "")), current_attack_u, boss_model.is_awake(), motion.walk_dist, motion.speed_now, boss_model.bat_in_hand, float(current_attack.get("feint", 0.0)))
	var hits: Variant = net_state.get("hits", {})
	var half := float(config["bounds"])
	for slot in other_pos:
		var p: Vector2 = other_pos[slot]
		var v: Variant = ai_hits.get(str(slot), 0.0) if ai_allies.has(slot) else (hits.get(str(slot), 0.0) if hits is Dictionary else 0.0)
		recorder.record(str(slot), t, p.x * 2.0 * half - half, p.y * 2.0 * half - half, float(v) if (v is float or v is int) else 0.0)


## ハイライトのデータ。ベストアタッカー（いちばん稼いだ人の、いちばん稼いだ区間）。なければ {}
func highlight_data() -> Dictionary:
	var best := recorder.best_window(float(config["highlight_window_sec"]))
	if best.is_empty():
		return {}
	best["points"] = recorder.path(str(best["slot"]), float(best["start"]), float(best["end"]))
	best["boss"] = Vector2(boss.position.x, boss.position.z)
	best["boss_track"] = recorder.boss_path(float(best["start"]), float(best["end"]))
	best["bounds"] = float(config["bounds"])
	best["color"] = _slot_color(str(best["slot"]))
	best["config"] = config
	best["character"] = char_def_of(str(best["slot"]))
	return best


## ダメージを受ける
func _take_damage(amount: float, ignore_invulnerable: bool = false) -> void:
	if actions.invulnerable() and not ignore_invulnerable:
		return
	if amount > 0.0:
		_play_sfx("hurt")
	_set_my_hp(Damage.apply_damage(my_hp, amount))


## ---- 3つの攻撃（通常・サブ・メイン）。時間の進みは player_actions.gd、数値は data/actions.json ----

## 通常攻撃（いままでの「こうげき」）。始められたら true
func attack() -> bool:
	return perform("normal")


## id の攻撃を始める。始められたら true。戦いの外、ダウン中、つかまれ中は始められない
func perform(id: String) -> bool:
	if not round_active() or downed or _me_held() or stun_left > 0.0:
		return false
	var cooldown := role_value("attack_cooldown_sec") if id == "normal" else -1.0
	if id == "ultimate" and not gauge.is_ready():
		return false
	if not actions.start(id, _aim_direction(id), cooldown):
		return false
	if id == "ultimate":
		gauge.consume()
		_show_banner(str(actions.def(id).get("name", "")), role_name_of(_my_slot()), float(actions.def(id).get("banner_sec", 1.6)))
		_play_sfx("ultimate")
	facing = actions.aim
	if id == "sub":
		_play_sfx("jump")
	if char_view != null:
		char_view.face_now(actions.aim)
	_handle_action_events(actions.update(0.0))
	return true


## 攻撃の向き。ボスをねらう攻撃は、ボスの方へ。それ以外は、いま向いている方へ
func _aim_direction(id: String) -> Vector2:
	if bool(actions.def(id).get("aim_boss", false)) and boss.visible:
		var to := Vector2(boss.position.x - player.position.x, boss.position.z - player.position.z)
		if to.length() > 0.01:
			return to
	return facing


## 攻撃の進み（毎コマ）。出来事を受けとり、体を動かす
func _actions_update(delta: float) -> void:
	if actions.busy() and (downed or _me_held() or not round_active()):
		actions.cancel()
		if not _me_held():
			player.position.y = ground_y
	var was_busy := actions.busy()
	_handle_action_events(actions.update(delta))
	if was_busy:
		var half := float(config["bounds"])
		var dfwd: float = actions.frame_move.x
		if bool(actions.def(actions.active).get("stop_at_boss", false)):
			dfwd = HitArea.clip_forward(Vector2(player.position.x, player.position.z), actions.aim, dfwd, Vector2(boss.position.x, boss.position.z), float(config["boss_size"]) * 0.5 + float(actions.cfg.get("stop_margin", 0.9)))
		player.position.x = clampf(player.position.x + actions.aim.x * dfwd, -half, half)
		player.position.z = clampf(player.position.z + actions.aim.y * dfwd, -half, half)
		player.position.y = ground_y + actions.height
	if facing.length() < 0.001:
		facing = Vector2(0.0, -1.0)
	if stick_vec.length() > 0.1 and not downed and not actions.busy():
		facing = stick_vec.normalized()


func _handle_action_events(events: Array) -> void:
	for ev in events:
		match str(ev["type"]):
			"hit":
				_resolve_hit(ev)
			"mark":
				_on_action_mark(str(ev["name"]))
			"anim":
				if char_view != null:
					char_view.play_step(str(ev["anim"]), float(ev["speed"]), bool(ev.get("from_end", false)))


## 動きの途中の印（data/actions.json の marks）。投げられた着地と、版72：必殺技の「ため」「踏み込み」
func _on_action_mark(mark: String) -> void:
	if mark == "ult_charge":
		ult_fx_spawn("charge", Vector3(player.position.x, ground_y, player.position.z), actions.aim)
		return
	if mark == "ult_dash":
		ult_dash_from = Vector3(player.position.x, ground_y, player.position.z)
		return
	if mark == "landed":
		var k: Dictionary = attacks_cfg["kinds"]["grab"]
		_take_damage(Damage.damage_amount(float(k["drop_power"]), float(attacks_cfg["damage_multiplier"])), true)
		player_hit_flash = float(config["hit_flash_sec"])
		_play_sfx("thud")


## 攻撃が当たったか調べて、ダメージを与える。当たりの範囲は hit_area.gd、ダメージは damage.gd
func _resolve_hit(ev: Dictionary) -> void:
	var dmg := Damage.damage_amount(role_value("attack_power"), float(config["attack_multiplier"]) * float(ev["multiplier"]))
	var reach := HitArea.reach_of(role_value("attack_reach"), float(ev["radius_scale"]))
	_play_sfx("slash")
	var hit_boss := boss.visible and HitArea.hits(player.position, boss.position, reach, float(config["boss_size"]) * 0.5)
	if str(ev.get("action", "")) == "ultimate":
		_ult_slash_fx(Vector3(player.position.x, ground_y, player.position.z), actions.aim, hit_boss and not phase.invulnerable(), true)
	if hit_boss and phase.invulnerable():
		_play_sfx("hit")  # 倒れて覚醒する間は、当たってもダメージは入らない
	elif hit_boss:
		_play_sfx("hit")
		hit_flash = float(config["hit_flash_sec"])
		_damage_boss(dmg)
		rage.add_hit(_round_t(), _dist_to_boss_surface(Vector2(player.position.x, player.position.z)))  # 版69：近くからなら、怒りに数える
	var sub_r := float((config["sub_enemy_size"] as Array)[0]) * 0.5
	var respawn := float(config["sub_enemy_respawn_sec"])
	if bool(ev["cleave"]):
		for i in crowd_state.count():
			if crowd_state.is_alive(i) and HitArea.hits(player.position, sub_crowd.last_positions[i], reach, sub_r):
				crowd_state.hit(i, dmg, _round_t(), respawn)
	elif not hit_boss:
		var nearest := crowd_state.nearest_alive(sub_crowd.last_positions, player.position, reach + sub_r)
		if nearest >= 0:
			crowd_state.hit(nearest, dmg, _round_t(), respawn)


## ---- 版72：必殺技の見た目（構え・ため・踏み込み・斬撃・当たった演出） ----
var ult_dash_from := Vector3.INF  ## 踏み込みを始めた場所（残像に使う）
var ult_fx_log: Array = []  ## 出した見た目の種類（テスト用。新しい物が後ろ）


func ult_fx_spawn(kind: String, pos: Vector3, aim: Vector2, extra: Dictionary = {}) -> void:
	ult_fx_log.append(kind)
	if ult_fx_log.size() > 20:
		ult_fx_log.pop_front()
	if is_inside_tree():
		UltFx.spawn(self, kind, pos, aim, actions.def("ultimate").get("fx", {}), extra)


## 斬った瞬間：三日月の斬撃（と、踏み込んだ道の残像）。当たったら、火花と、一瞬止める・画面をゆらす。mine：自分の必殺技
func _ult_slash_fx(pos: Vector3, aim: Vector2, landed: bool, mine: bool) -> void:
	var fx: Dictionary = actions.def("ultimate").get("fx", {})
	if mine and ult_dash_from != Vector3.INF:
		ult_fx_spawn("trail", ult_dash_from, aim, {"to": pos})
		ult_dash_from = Vector3.INF
	ult_fx_spawn("slash", pos, aim)
	if landed:
		var bp := Vector2(boss.position.x, boss.position.z)
		var to := bp - Vector2(pos.x, pos.z)
		var contact := bp - to.normalized() * float(config["boss_size"]) * 0.5 if to.length() > 0.01 else bp
		if bool(fx.get("hit_spark", true)):
			_burst_fx(Vector3(contact.x, 1.4, contact.y), "spark")
		ult_fx_log.append("hit")
		if mine:
			var hs: Array = fx.get("hitstop", [0.08, 0.3])
			_hitstop(float(hs[0]), float(hs[1]))


## 必殺技の名前を、画面の真ん中に出す。who：使った人の表示（空なら出さない）
func _show_banner(text: String, who: String, seconds: float) -> void:
	banner = {"text": text, "who": who, "left": seconds, "total": seconds}


## ボタンの中心（画面の割合は data/prototype_stick.json の「<id>_center_frac」。縦長なら「…_portrait」）
func _button_center(id: String, screen: Vector2) -> Vector2:
	var f: Array = _layout(id + "_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


## 触れた場所にある、攻撃ボタンの id。なければ ""
func _button_at(pos: Vector2, screen: Vector2) -> String:
	for id in actions.ids():
		if pos.distance_to(_button_center(str(id), screen)) <= float(config["button_radius_px"]):
			return str(id)
	return ""


func _damage_boss(amount: float) -> void:
	gauge.charge(amount)
	my_hits += amount
	_recompute_boss_hp()
	if net_active:
		bridge.send_hits(my_hits)


func _round_t() -> float:
	return (server_now_ms() - round_start_ms) / 1000.0


## ---- 版71：AIの味方のための、ボスの攻撃の先読み ----
var ai_forecast: Array = []
var ai_forecast_t := -999.0


## いまの攻撃を、horizon 秒先まで step 秒きざみで進めて、当たる物を集める [{dt: 何秒後（実際の秒）, h: 当たり}]。
## 攻撃の中の秒 u は speed 倍で進む（版69の怒り）。攻撃が終わる先は見ない（次の攻撃は、まだ分からない）
func boss_forecast(horizon: float, step: float) -> Array:
	var out: Array = []
	if current_attack.is_empty() or not round_active() or step <= 0.0:
		return out
	var a: Dictionary = current_attack
	# 重い攻撃（巨大酒瓶ライド）は先を調べない。いま見えている予告と当たりを「すぐ当たる」として渡す（AIは走ってよける）
	if ((ai_cfg.get("tactics", {}) as Dictionary).get("forecast_skip", []) as Array).has(str(a["kind"])):
		for h in current_hazards:
			if bool(h["active"]) or float(h.get("tele", 0.0)) > 0.0:
				out.append({"dt": 0.0, "h": h})
		return out
	var sp := float(a.get("speed", 1.0))
	var end_u := (float(a["end"]) - float(a["start"])) * sp
	var k := 0.0
	while k <= horizon + 0.0001:
		var u := current_attack_u + k * sp
		if u > end_u:
			break
		for h in Attacks.hazards(a, u, attacks_cfg, _attack_ctx(a, u, true)):
			if bool(h["active"]):
				out.append({"dt": k, "h": h})
		k += step
	return out


## ボスの次の攻撃が始まるまでの秒（いまの攻撃の最中なら、終わり＋攻撃の間）。分からなければ 0
func boss_next_attack_in() -> float:
	var t := _round_t()
	var cur: Dictionary = ai.current()
	if not cur.is_empty():
		return maxf(0.0, float(cur["end"]) - t + float(attacks_cfg.get("gap_sec", 0.6)))
	var nxt: Dictionary = ai.next_attack()
	if not nxt.is_empty():
		return maxf(0.0, float(nxt["start"]) - t)
	return maxf(0.0, ai.next_start - t)


## 版69：p（x, z）から、ボスの体の表面までの距離（m。体の中なら 0 以下）
func _dist_to_boss_surface(p: Vector2) -> float:
	return p.distance_to(Vector2(boss.position.x, boss.position.z)) - float(config["boss_size"]) * 0.5


## 版69：いまボスが怒っているか（近くからの攻撃が多い間）
func boss_angry() -> bool:
	return round_active() and rage.is_angry(_round_t())


## サブ敵にふれていると、一定の間隔でダメージを受ける（ジャンプ中・ダウン中は受けない）
func _touch_update(delta: float) -> void:
	if not round_active() or downed:
		touch_timer = 0.0
		return
	var airborne := player.position.y > ground_y + float(config["dodge_height"])
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
	return others_hits + _ai_hits_total()


var awake_rides_done := 0  ## 覚醒の体力の区切りで入れた巨大酒瓶ライドの数（版64）
var awake_storms_done := {}  ## 版68：必ず入れた酒の大雨（awake_storm_at の番号 → true）
var quick_grab_at := -1.0  ## 版68：剣士をすぐ投げるつかみを入れる時刻（戦いの秒）
var quick_grab_done := false


## ボスの体力 = 最大 − 自分の合計 − ほかの人の合計。0になったら倒した（戦いの最中だけ）
func _recompute_boss_hp() -> void:
	var total := _total_boss_damage_counted()
	var ev := phase.on_total(total) if round_start_ms > 0.0 and not won and not lost else ""
	var new_hp := phase.hp(total)
	if new_hp < boss_hp - 0.001 and phase.phase != BossPhase.FALL:
		hit_flash = float(config["hit_flash_sec"])
	boss_hp = new_hp
	# 版64：覚醒の体力が4分の1減るたびに、必ず巨大酒瓶ライドを入れる（次の攻撃として）
	var steps := phase.awake_steps(total, float(config.get("awake_ride_every", 0.0)))
	if steps > awake_rides_done and not won and not lost:
		awake_rides_done = steps
		ai.request(Attacks.BOTTLE_RIDE)
	# 版68：覚醒の体力が決めた割合（4分の1・4分の3）減ったら、必ず酒の大雨（区切りごとに1回）
	if phase.is_awake() and not won and not lost:
		var lost_frac := clampf((total - phase.awake_base) / maxf(phase.max2, 1.0), 0.0, 1.0)
		var marks: Array = config.get("awake_storm_at", [])
		for i in marks.size():
			if lost_frac >= float(marks[i]) - 0.000001 and not awake_storms_done.has(i):
				awake_storms_done[i] = true
				ai.request(Attacks.FLYER_STORM)
	if ev == BossPhase.FALL:
		_on_boss_fall()
	if round_start_ms > 0.0 and ev == BossPhase.DEAD and not won and not lost:
		field.clear()  # 倒したら、残っている火・酒だまりを消す
		won = true
		round_end_ms = server_now_ms()
		_play_sfx("win")
		round_ended.emit(true)
		boss.visible = false


## ボスの体力の割合（1.0 が満タン。いまの形態の最大に対して）
func boss_hp_ratio() -> float:
	return clampf(boss_hp / maxf(1.0, phase.max_hp()), 0.0, 1.0)


## ボスに与えたダメージの合計（自分＋ほかの人＋AI。戦いの始まりの直後は、ほかの人の分を数えない）
func _total_boss_damage_counted() -> float:
	var mine := my_hits if round_start_ms > 0.0 else 0.0
	return mine + _effective_others_hits()


## 倒れて覚醒するまでの秒（ボスのモデルの stagger_sec）
func _trans_sec() -> float:
	return float(boss_model.cfg["stagger_sec"]) if boss_model != null else 3.4


## 第1形態の体力が0：攻撃をやめ、つかんでいれば放し、倒れる
func _on_boss_fall() -> void:
	current_attack = {}
	current_hazards = []
	_show_hazards([])
	if not grab_state.is_empty():
		_release_hold(true)
	if boss_model != null:
		boss_model.begin_fall()
	ai.interrupt(_round_t(), 999.0)
	field.clear()  # 倒れたら、燃えている火や酒だまりも消す
	phase_text = {"text": str(config.get("boss_down_text", "")), "left": 2.0}
	_play_sfx("thud")


## 覚醒の演出が終わった：第2形態の攻撃を始める
func _on_boss_awake() -> void:
	phase_text = {"text": str(config.get("boss_awake_text", "")), "left": 1.6}
	_play_sfx("ultimate")
	_on_awake_started()


## 第2形態が始まったときの、攻撃の準備（攻撃のしくみが使う）
func _on_awake_started() -> void:
	ai.on_awake(_round_t())


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


## ボスの動き：剣士と同じ動き素材で、待ち・歩き・攻撃・よろけを動かす（scripts/boss/boss_moves.gd）。
## 攻撃の動きは、攻撃が始まってからの秒で決まるので、予告と当たりの時刻に、振る瞬間が合う。delta は1コマの秒
func _pose_boss(delta: float = 0.0) -> void:
	var hit_now := hit_flash > 0.0 and not boss_was_hit
	boss_was_hit = hit_flash > 0.0
	boss_model.update_form(delta)
	var kind := str(current_attack.get("kind", ""))
	var kinds: Dictionary = attacks_cfg.get("kinds", {})
	var st := {"clock": boss_clock, "walk_dist": motion.walk_dist, "walk_speed": motion.speed_now, "kind": kind, "u": current_attack_u,
		"k": Attacks.kind_cfg(attacks_cfg, current_attack) if kind != "" else {}, "hit_now": hit_now, "airborne": motion.height, "grab": _grab_anim_state(), "aim_yaw": _grab_aim_yaw(),
		"ride_phase": str(motion.path_info.get("phase", "")), "ride_phase_t": float(motion.path_info.get("phase_t", 0.0)), "ride_throw_t": float(motion.path_info.get("throw_t", -1.0))}
	var res: Dictionary = boss_model.animate(delta, boss_clock, st)
	_update_ride_bottle(kind == Attacks.BOTTLE_RIDE and bool(motion.path_info.get("riding", false)))
	boss.rotation.y = motion.yaw + float(res.get("spin", 0.0)) + motion.path_spin
	_pose_sweep_hands()
	# バット投げ：投げてから受けとるまで、手にバットはない
	var in_hand := true
	if kind == Attacks.BAT_THROW:
		var bk := Attacks.kind_cfg(attacks_cfg, current_attack)
		var rel := float(bk["windup_sec"])
		in_hand = current_attack_u < rel or current_attack_u >= rel + float(bk["out_sec"]) + float(bk["back_sec"])
	if in_hand != boss_model.bat_in_hand:
		boss_model.set_bat_visible(in_hand)
	_update_jump_shadow()


## 跳んでいるボスの影（地面に、高さに合わせた大きさで）
var _shadow: MeshInstance3D
func _update_jump_shadow() -> void:
	if _shadow == null:
		_shadow = MeshInstance3D.new()
		_shadow.name = "BossShadow"
		var c := CylinderMesh.new()
		c.top_radius = 1.0
		c.bottom_radius = 1.0
		c.height = 0.02
		c.radial_segments = 20
		c.rings = 1
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0, 0, 0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		c.material = m
		_shadow.mesh = c
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shadow)
	var h := motion.height
	var riding := bool(motion.path_info.get("riding", false))
	# 覚醒のオーラの床の光は、跳んでいる間・酒瓶に乗っている間は消す（空中に円盤が浮いて見えるので）
	if boss_model != null and boss_model.aura_ground != null:
		boss_model.aura_ground.visible = h < 0.3
	_shadow.visible = h > 0.3 and not riding
	if _shadow.visible:
		_shadow.position = Vector3(motion.pos.x, 0.02, motion.pos.y)
		_shadow.scale = Vector3.ONE * lerpf(3.0, 1.6, clampf(h / 8.0, 0.0, 1.0))


## つかんでいる最中の、ボスの動きに渡す状態（つかんでいなければ {}）
func _grab_anim_state() -> Dictionary:
	if grab_state.is_empty():
		return {}
	var k: Dictionary = attacks_cfg["kinds"]["grab"]
	return {"phase": str(grab_state.get("phase", "hold")), "t": float(grab_state["t"]), "throw_t": float(grab_state.get("throw_t", 0.0)),
		"throw_sec": float(k["throw_sec"]), "release_sec": float(k["release_sec"])}


## つかみの手を向ける角度（ボスの正面から、ねらう場所までの角度。ラジアン）
func _grab_aim_yaw() -> float:
	if str(current_attack.get("kind", "")) != Attacks.GRAB:
		return 0.0
	for h in current_hazards:
		if bool(h.get("grab", false)):
			var d := Vector2(float(h["x"]) - boss.position.x, float(h["z"]) - boss.position.z)
			if d.length() > 0.3:
				return clampf(wrapf(atan2(d.x, d.y) - motion.yaw, -PI, PI), -0.9, 0.9)
	return 0.0


## 必殺技の大きな手：当たり場所（手の形）の位置に置く。動いていないときは隠す
func _pose_sweep_hands() -> void:
	var used := {"L": false, "R": false}
	var sc := float(attacks_cfg["kinds"]["hand_sweep"]["hand_scale"]) if attacks_cfg["kinds"].has("hand_sweep") else 2.4
	for h in current_hazards:
		if str(h["style"]) != "hand" or not bool(h["active"]):
			continue
		var side := "R" if float(h["dir"]) > 0.0 else "L"
		used[side] = true
		var hand: Node3D = boss_model.sweep_hands[side]
		hand.visible = true
		hand.global_position = Vector3(float(h["x"]), 0.9, float(h["z"]))
		hand.global_rotation = Vector3(0.0, PI * 0.5 * float(h["dir"]), 0.0)
		hand.scale = Vector3.ONE * sc
	for side in ["L", "R"]:
		if not used[side]:
			(boss_model.sweep_hands[side] as Node3D).visible = false


## ---- つかみ：持ち上げる・動けない・助ける ----

func _play_sfx(sound: String) -> void:
	if sfx != null and sound != "":
		sfx.play(sound)


func _me_held() -> bool:
	return not grab_state.is_empty() and str(grab_state["slot"]) == _my_slot()


func _start_hold(slot: String, from: Vector2) -> void:
	if not grab_state.is_empty():
		return
	_play_sfx("grab")
	var n := int(current_attack.get("n", 0))
	var hold := Attacks.grab_hold_sec(attacks_cfg, round_start_ms, n)
	if bool(current_attack.get("quick", false)):
		hold = float(attacks_cfg["kinds"]["grab"].get("quick_hold_sec", 0.25))  # 版68：すぐ投げるつかみ
	grab_state = {"slot": slot, "t": 0.0, "from": from, "squeeze": 0.0, "lift": 0.0, "hold": hold}
	if slot == _my_slot():
		stun_left = maxf(stun_left, 0.1)
	grab_state["phase"] = "hold"
	grab_state["throw_t"] = 0.0
	grab_hand = Vector3(from.x, 0.9, from.y)


func _release_hold(freed: bool) -> void:
	var k: Dictionary = attacks_cfg["kinds"]["grab"]
	var slot := str(grab_state["slot"])
	var decided: Variant = grab_state.get("throw_dir", null)
	grab_state = {}
	if freed:
		_play_sfx("free")
	if slot == _my_slot():
		if freed:
			stun_left = maxf(stun_left, float(k["free_stun_sec"]))
			player.position.y = ground_y
		else:
			# 逃げられなかった：放り投げられる（着地のダメージと、転んで起き上がるまでは、player_actions の「thrown」）
			# 版67：ボスからいちばん遠い人のほうへ投げる（だれもいなければ、ボスの向き）
			var away: Vector2 = decided if decided is Vector2 else throw_dir(slot)
			actions.start("thrown", away, 0.0, true)
			if char_view != null:
				char_view.face_now(-away)
			_handle_action_events(actions.update(0.0))
			_play_sfx("whoosh")
	elif ai_allies.has(slot):
		var a: Dictionary = ai_allies[slot]
		a["held"] = false
		other_lift[slot] = 0.0
		if not freed:
			# 投げられる（着地のダメージは、AiAlly.step が「landed」の印で受ける）。向きは、いちばん遠い人のほう（版67）
			var away: Vector2 = decided if decided is Vector2 else throw_dir(slot)
			(AiAlly.act(a) as Actions).start("thrown", away, 0.0, true)
		else:
			a["stun"] = float(k["free_stun_sec"])


## ---- 版68：剣士をつかんですぐ投げる（1戦に1回、決めたランダムな時刻のあと） ----
## 剣士の枠：自分が剣士（キャラを選んでいない＝ファイター、または hero_swordsman）なら自分。AIの味方の剣士も。倒れていない人だけ
func swordsman_slots() -> Array:
	var out: Array = []
	var me := _my_slot()
	var mine := selected_character
	if not downed and (mine == "" or mine == "hero_swordsman"):
		out.append(me)
	var names: Array = ai_allies.keys()
	names.sort()
	for slot in names:
		var a: Dictionary = ai_allies[slot]
		if str(a.get("id", "")) == "hero_swordsman" and not bool(a["downed"]):
			out.append(str(slot))
	return out


func _quick_grab_check(t: float) -> void:
	if quick_grab_done or quick_grab_at < 0.0 or t < quick_grab_at or won or lost or not phase.can_attack():
		return
	if not grab_state.is_empty() or str(current_attack.get("kind", "")) == Attacks.GRAB:
		return
	var targets := swordsman_slots()
	if targets.is_empty():
		return  # 剣士がいない・倒れている：無理に出さない（できるようになるまで待つ）
	quick_grab_done = true
	ai.request(Attacks.GRAB, {"target": str(targets[0]), "quick": true})


## ---- 版67：つかみ投げの、投げる向き（版70：投げられた人がほかの人にぶつかる仕組みは消した） ----


## 位置のわかる人（倒れていない）：枠 → 床の上の位置。自分・AIの味方・通信のほかの人
func _people_positions() -> Dictionary:
	var out := {}
	var me := _my_slot()
	if not downed:
		out[me] = Vector2(player.position.x, player.position.z)
	var half := float(config["bounds"])
	for slot in other_pos:
		if ai_allies.has(slot) and bool(ai_allies[slot]["downed"]):
			continue
		var np: Vector2 = other_pos[slot]
		out[str(slot)] = (ai_allies[slot]["pos"] as Vector2) if ai_allies.has(slot) else Vector2(np.x * 2.0 * half - half, np.y * 2.0 * half - half)
	return out


## 投げる向き：投げられる人（slot）を除いて、ボスからいちばん遠い人のほう。同じ距離（0.01m 以内）なら、枠の名前の順で先の人。
## だれもいない・ボスと同じ所にいるときは、ボスの正面
func throw_dir(slot: String) -> Vector2:
	var bp := Vector2(boss.position.x, boss.position.z)
	var best := ""
	var best_d := -1.0
	var people := _people_positions()
	var names: Array = people.keys()
	names.sort()
	for name in names:
		if str(name) == slot:
			continue
		var d := (people[name] as Vector2).distance_to(bp)
		if d > best_d + 0.01:
			best_d = d
			best = str(name)
	if best != "" and best_d > 0.3:
		return ((people[best] as Vector2) - bp).normalized()
	return Attacks.fwd_of(boss.rotation.y)


func _grab_update(delta: float) -> void:
	if grab_state.is_empty():
		return
	var k: Dictionary = attacks_cfg["kinds"]["grab"]
	var slot := str(grab_state["slot"])
	var mult := float(attacks_cfg["damage_multiplier"])
	grab_state["t"] = float(grab_state["t"]) + delta
	var t := float(grab_state["t"])
	# 版70：逃げる仕組み（「にげる」の連打・みんなのダメージで外れる）はない。つかまれたら必ず投げられる。
	# 外れるのは、つかまれた人が倒れたときと、戦いが終わったときだけ
	var is_me := slot == _my_slot()
	var target_down := downed if is_me else (not ai_allies.has(slot) or bool(ai_allies[slot]["downed"]))
	if target_down or not round_active():
		_release_hold(true)
		return
	var throwing := str(grab_state.get("phase", "hold")) == "throw"
	if not throwing and t >= float(grab_state["hold"]):
		# つかむ時間が終わった：ボスが、うしろへ引いて前へ投げる動きに入る（手をはなす瞬間に、飛んでいく）
		grab_state["phase"] = "throw"
		grab_state["throw_t"] = 0.0
		throwing = true
		# 版67：投げる向きは、投げる動きに入った時点で決める（いちばん遠い人のほう）。ボスもそちらを向いて投げる
		var tdir := throw_dir(slot)
		grab_state["throw_dir"] = tdir
		var gn := int(current_attack.get("n", -1))
		if motion.locks.has(gn):
			motion.locks[gn]["yaw"] = atan2(tdir.x, tdir.y)
	if throwing:
		grab_state["throw_t"] = float(grab_state["throw_t"]) + delta
		if float(grab_state["throw_t"]) >= float(k["release_sec"]):
			_release_hold(false)
			return
	# 手の位置：ボスの左手（手のひらの少し下に、体がぶら下がる）。つかんだ直後は、つかんだ場所から手へ寄せる
	var hand: Vector3 = boss_model.hand_world("L") if boss_model != null else Vector3(boss.position.x, float(k["hold_height"]), boss.position.z)
	hand.y -= float(k.get("hang_below", 1.0))
	var lift := clampf(t / float(k["lift_sec"]), 0.0, 1.0)
	var from: Vector2 = grab_state["from"]
	var start := Vector3(from.x, ground_y, from.y)
	var held := start.lerp(hand, smoothstep(0.0, 1.0, lift))
	held.y = maxf(held.y, ground_y)
	var xz := Vector2(held.x, held.z)
	var y := held.y - ground_y
	grab_hand = held
	# しめつけのダメージ
	grab_state["squeeze"] = float(grab_state["squeeze"]) + delta
	if float(grab_state["squeeze"]) >= float(k["squeeze_tick_sec"]):
		grab_state["squeeze"] = float(grab_state["squeeze"]) - float(k["squeeze_tick_sec"])
		var sq := Damage.damage_amount(float(k["squeeze_power"]), mult)
		if is_me:
			_take_damage(sq)
			player_hit_flash = float(config["hit_flash_sec"])
		else:
			var a2: Dictionary = ai_allies[slot]
			a2["hp"] = maxf(0.0, float(a2["hp"]) - sq)
			a2["flash"] = 0.15
			if float(a2["hp"]) <= 0.0:
				a2["downed"] = true
	if is_me:
		stun_left = maxf(stun_left, 0.1)
		player.position = Vector3(xz.x, ground_y + y, xz.y)
	elif ai_allies.has(slot):
		var a3: Dictionary = ai_allies[slot]
		a3["pos"] = xz
		other_lift[slot] = y
		var half := float(config["bounds"])
		other_target[slot] = Vector2((xz.x + half) / (2.0 * half), (xz.y + half) / (2.0 * half))
		other_pos[slot] = other_target[slot]


## ---- AIの味方 ----

func _ai_active() -> bool:
	if not ai_enabled:
		return false
	if not net_active:
		return true
	return (net_state.get("members", []) as Array).size() <= 1


func _ai_total() -> int:
	return (ai_cfg.get("slots", []) as Array).size()


func _ai_hits_total() -> float:
	var t := 0.0
	for slot in ai_hits:
		t += float(ai_hits[slot])
	return t


func _ai_all_down() -> bool:
	for slot in ai_allies:
		if not bool(ai_allies[slot]["downed"]):
			return false
	return true


## AIの味方を作りなおす（戦いの始まり、人数や選択が変わったとき）。いまの状況でAIが要らなければ、片づける
func _ai_reset() -> void:
	if ai_cfg.is_empty():
		ai_cfg = AiAlly.load_config()
	if characters_cfg.is_empty():
		characters_cfg = CharacterData.load_config()
	for slot in ai_allies.keys():
		_ai_remove_node(str(slot))
	ai_allies = {}
	ai_hits = {}
	ai_done = {}
	other_lift = {}
	if not _ai_active():
		return
	ai_rng.seed = int(fmod(maxf(round_start_ms, 1.0), 1000000007.0)) + 99
	var picks := _ai_picks_resolved()
	var slots: Array = ai_cfg["slots"]
	var offs: Array = ai_cfg["spawn_offsets"]
	var half := float(config["bounds"])
	for i in slots.size():
		var def := CharacterData.find(characters_cfg, str(picks[i]))
		if def.is_empty():
			continue
		var o: Array = offs[i % offs.size()]
		var a := AiAlly.make(def, i, Vector2(float(o[0]), float(o[1])))
		var slot := str(slots[i])
		ai_allies[slot] = a
		ai_hits[slot] = 0.0
		other_target[slot] = Vector2((a["pos"].x + half) / (2.0 * half), (a["pos"].y + half) / (2.0 * half))
		other_pos[slot] = other_target[slot]


## 選んだ3人（足りなければ、既定で埋める。自分のキャラは重ねても構わない）
func _ai_picks_resolved() -> Array:
	var out: Array = []
	var defaults: Array = ai_cfg.get("default_picks", [])
	for i in _ai_total():
		var id := str(ai_picks[i]) if i < ai_picks.size() else ""
		if CharacterData.find(characters_cfg, id).is_empty():
			id = str(defaults[i % defaults.size()]) if not defaults.is_empty() else ""
		out.append(id)
	return out


func _ai_remove_node(slot: String) -> void:
	other_target.erase(slot)
	other_pos.erase(slot)
	if others.has(slot):
		(others[slot] as Node).queue_free()
		others.erase(slot)
	other_views.erase(slot)


## 毎コマ：AIを、必要なら作る／片づける。戦いの最中なら動かす
func _ai_update(delta: float) -> void:
	if ai_cfg.is_empty():
		ai_cfg = AiAlly.load_config()
	var want := _ai_active()
	var have := not ai_allies.is_empty()
	if want != have:
		_ai_reset()
	if ai_allies.is_empty():
		return
	var half := float(config["bounds"])
	if round_active():
		var ctx := {"boss": Vector2(boss.position.x, boss.position.z), "boss_radius": float(config["boss_size"]) * 0.5, "bounds": half,
			"hazards": current_hazards, "cfg": ai_cfg, "attack_multiplier": float(config["attack_multiplier"]), "rng": ai_rng, "can_hit_boss": not phase.invulnerable(),
			"drop_damage": Damage.damage_amount(float(attacks_cfg["kinds"]["grab"]["drop_power"]), float(attacks_cfg["damage_multiplier"]))}
		# 版71：ボスのいまの攻撃の先読み（AIの味方が、よける・攻める時刻を決める）
		var tac: Dictionary = ai_cfg.get("tactics", {})
		var rt := _round_t()
		if rt - ai_forecast_t >= float(tac.get("forecast_every", 0.2)) or rt < ai_forecast_t:
			ai_forecast = boss_forecast(float(tac.get("forecast_sec", 2.0)), float(tac.get("forecast_step", 0.15)))
			ai_forecast_t = rt
		ctx["forecast"] = ai_forecast
		ctx["forecast_age"] = maxf(0.0, rt - ai_forecast_t)
		ctx["next_attack_in"] = boss_next_attack_in()
		var dealt_total := 0.0
		for slot in ai_allies:
			var a: Dictionary = ai_allies[slot]
			ctx["slot"] = slot
			var hit_n0 := int(a.get("hit_n", 0))
			var dealt := AiAlly.step(a, delta, ctx)
			# 版69：AIの攻撃がボスに当たった回数。近くからなら、怒りに数える
			for _i in int(a.get("hit_n", 0)) - hit_n0:
				rage.add_hit(_round_t(), _dist_to_boss_surface(a["pos"]))
			_ai_show_action(str(slot), a)
			if dealt > 0.0:
				ai_hits[slot] = float(ai_hits[slot]) + dealt
				dealt_total += dealt
			# 版72：AIの必殺技の見た目（ためと、当たった瞬間の斬撃）
			var ua: Actions = AiAlly.act(a)
			var apos: Vector2 = a["pos"]
			if str(a["banner"]) != "":
				ult_fx_spawn("charge", Vector3(apos.x, ground_y, apos.y), ua.aim)
			if dealt > 0.0 and ua.active == "ultimate":
				_ult_slash_fx(Vector3(apos.x, ground_y, apos.y), ua.aim, true, false)
			var was_held := bool(a.get("held", false))
			AiAlly.take_hazards(a, str(slot), current_hazards, ai_done, float(attacks_cfg["damage_multiplier"]))
			if bool(a.get("held", false)) and not was_held and grab_state.is_empty():
				var gp: Vector2 = a["pos"]
				_start_hold(str(slot), gp)
			elif bool(a.get("held", false)) and not was_held:
				a["held"] = false
			var p: Vector2 = a["pos"]
			other_target[slot] = Vector2((p.x + half) / (2.0 * half), (p.y + half) / (2.0 * half))
		if dealt_total > 0.0:
			_recompute_boss_hp()
	if not net_active:
		_update_others(delta)
	_check_wipe_ai_only()


## AIの攻撃の見た目：流すアニメ、向き、高さ、必殺技の名前
func _ai_show_action(slot: String, a: Dictionary) -> void:
	var act: Actions = AiAlly.act(a)
	var view: Node3D = other_views.get(slot, null)
	if view != null:
		for ev in a["events"]:
			(view as Node).play_step(str(ev["anim"]), float(ev["speed"]), bool(ev.get("from_end", false)))
		if act.busy():
			(view as Node).face_now(act.aim)
	if not bool(a.get("held", false)):
		other_lift[slot] = float(a["height"])
	if str(a["banner"]) != "":
		_show_banner(str(a["banner"]), role_name_of(slot), float(act.def("ultimate").get("banner_sec", 1.6)))
		_play_sfx("ultimate")


## 自分がダウン中で、AIも全員ダウンしたら全滅
func _check_wipe_ai_only() -> void:
	if round_active() and downed:
		_check_wipe()


func _my_slot() -> String:
	return str(net_state.get("slot", "p1")) if net_active else "p1"


## 攻撃の計算に渡す、いまの状況（ボス、みんなの位置、つかみの固定位置）。位置は (x, z)
## peek が true なら、先を調べるだけ（つかみの位置を、まだ決めない。版71：AIの味方の先読み）
func _attack_ctx(a: Dictionary, u: float, peek: bool = false) -> Dictionary:
	var half := float(config["bounds"])
	var me := _my_slot()
	var members: Array = net_state.get("members", []).duplicate() if net_active else []
	if not members.has(me):
		members.append(me)
	if downed:
		members.erase(me)
	for slot in ai_allies:
		if not members.has(slot) and not bool(ai_allies[slot]["downed"]):
			members.append(slot)
	var positions := {me: Vector2(player.position.x, player.position.z)}
	for slot in other_pos:
		var np: Vector2 = other_pos[slot]
		positions[slot] = Vector2(np.x * 2.0 * half - half, np.y * 2.0 * half - half)
	var lk := motion.lock_of(int(a["n"])) if not a.is_empty() else {"pos": motion.pos, "yaw": motion.yaw}
	var ctx := {"boss": lk["pos"], "yaw": float(lk["yaw"]), "members": members, "positions": positions,
		"locked": null, "round_start_ms": round_start_ms, "bounds": half,
		"target": lk.get("target", lk["pos"]), "curve": float(lk.get("curve", 0.0)), "area": float((attacks_cfg.get("walk", {}) as Dictionary).get("area", 13.0))}
	if not a.is_empty() and str(a["kind"]) == Attacks.GRAB and u >= float(attacks_cfg["kinds"]["grab"]["follow_sec"]):
		var n := int(a["n"])
		if not grab_locked.has(n):
			var target := Attacks.attack_target(a, members)
			var lp: Vector2 = positions.get(target, (ctx["boss"] as Vector2) + Attacks.fwd_of(float(ctx["yaw"])) * 6.0)
			if peek:
				ctx["locked"] = lp  # いまの位置で決まるとして調べる（記録はしない）
				return ctx
			grab_locked[n] = lp
		ctx["locked"] = grab_locked[n]
	return ctx


## 戦いの進み：ボスの攻撃（予告 → 当たり）。時刻だけで決まるので、全員の画面で同じになる
func combat_update(delta: float) -> void:
	player_hit_flash = maxf(0.0, player_hit_flash - delta)
	stun_left = maxf(0.0, stun_left - delta)
	current_hazards = []
	if not round_active():
		_show_hazards([])
		grab_state = {}
		return
	var t := (server_now_ms() - round_start_ms) / 1000.0
	# 体力の2段階：倒れて覚醒する演出の進み
	if phase.tick(delta, _total_boss_damage_counted()) == BossPhase.AWAKE:
		_on_boss_awake()
		_recompute_boss_hp()
	phase_text["left"] = maxf(0.0, float(phase_text["left"]) - delta)
	if phase.phase == BossPhase.FALL:
		boss_hp = phase.hp(_total_boss_damage_counted())
	var staggering: bool = not phase.can_attack() or (boss_model != null and boss_model.is_staggering())
	var cur: Dictionary = {}
	_quick_grab_check(t)
	if not staggering:
		ai.angry = rage.is_angry(t)  # 版69：怒っている間に決める・始める攻撃は、つかみ投げが多く、速い
		ai.update(t, "awake" if phase.is_awake() else "normal", _target_dist)
		cur = ai.current()
	var idx := 0 if not cur.is_empty() else -1
	# 攻撃の中の秒 u。版69：怒っている間に始まった攻撃は speed 倍で進む（予告・当たり・動きが、まとめて速くなる）
	var cur_u := (t - float(cur["start"])) * float(cur.get("speed", 1.0)) if idx >= 0 else 0.0
	var mctx := _attack_ctx({}, 0.0)
	motion.update(delta, cur, cur_u, ai.next_attack() if not staggering else {}, attacks_cfg, mctx, staggering)
	boss.position = Vector3(motion.pos.x, motion.height, motion.pos.y)
	if idx >= 0:
		var a: Dictionary = cur
		var u := cur_u
		current_attack = a
		current_attack_u = u
		if int(a["n"]) != last_attack_n:
			last_attack_n = int(a["n"])
			_play_sfx(str((sfx.cfg if sfx != null and not sfx.cfg.is_empty() else {}).get("attack_sounds", {}).get(str(a["kind"]), "")))
		current_hazards = Attacks.hazards(a, u, attacks_cfg, _attack_ctx(a, u))
	else:
		current_attack = {}
	_sake_field_update()
	# 燃えている酒だまり（攻撃が終わっても、燃えている間は当たる）
	if attacks_cfg["kinds"].has("fire_fest"):
		current_hazards.append_array(Attacks.fire_hazards(field, t, attacks_cfg["kinds"]["fire_fest"]))
	_apply_hazards(current_hazards)
	_ai_update(delta)
	_grab_update(delta)
	_show_hazards(current_hazards)
	_update_puddles(delta)
	_sake_spray_update()


## 攻撃 n でねらう人までの距離（攻撃の選び方が使う。わからなければ -1）
func _target_dist(n: int) -> float:
	var tp: Variant = BossMotion.target_pos(n, _attack_ctx({}, 0.0))
	return (tp as Vector2).distance_to(motion.pos) if tp is Vector2 else -1.0


## テスト・道具用：いまの時刻から、決めた攻撃を出す
func force_attack(kind: String) -> Dictionary:
	var t := _round_t()
	ai.n += 1
	var k: Dictionary = attacks_cfg["kinds"][kind]
	ai.cur = {"n": ai.n, "kind": kind, "start": t, "end": t + Attacks.attack_duration(kind, k, ai.n, round_start_ms), "feint": 0.0}
	ai.nxt = {}
	return ai.cur


## 酒の雨：一升瓶をふり上げた瞬間に、しぶきを空へまく（必殺技の大雨は、始めに1回）
var _last_spray_key := ""
func _sake_spray_update() -> void:
	if boss_model == null or current_attack.is_empty():
		return
	var kind := str(current_attack["kind"])
	var key := ""
	if kind == Attacks.SAKE_RAIN:
		var k: Dictionary = attacks_cfg["kinds"][kind]
		for t in int(k["throws"]):
			if current_attack_u >= Attacks.sake_throw_time(t, k):
				key = "%d_%d" % [int(current_attack["n"]), t]
	elif kind == Attacks.FLYER_STORM:
		var k2: Dictionary = attacks_cfg["kinds"][kind]
		var every := maxf(0.6, float(k2["spread_sec"]) / 6.0)
		var i := int(floor((current_attack_u - float(k2["start_sec"]) + every) / every))
		if current_attack_u >= float(k2["start_sec"]) - every and current_attack_u < float(k2["start_sec"]) + float(k2["spread_sec"]):
			key = "%d_s%d" % [int(current_attack["n"]), i]
	if key != "" and key != _last_spray_key:
		_last_spray_key = key
		if boss_model.has_method("spray_sake") and boss_model.is_inside_tree():
			boss_model.spray_sake()


## ---- ふっ飛び・ヒットストップ・画面のゆれ ----
var kb_guard_left := 0.0  ## ふっ飛んでいる間と、起き上がったあとしばらくは、ボスの攻撃が当たらない
var hitstop_until_ms := 0
var shake_amp := 0.0
var shake_left := 0.0


## ボスの攻撃でふっ飛ぶ（kind：data/actions.json の kb_light / kb_heavy / kb_slam / kb_launch）。dir：飛ぶ向き (x, z)
func _knockback(kind: String, dir: Vector2) -> void:
	if not actions.has_action(kind):
		return
	actions.start(kind, dir, 0.0, true)
	if char_view != null:
		char_view.face_now(-dir)
	_handle_action_events(actions.update(0.0))
	kb_guard_left = float(actions.def(kind).get("duration_sec", 0.5)) + float(actions.cfg.get("kb_guard_sec", 0.6))
	var hs: Array = (attacks_cfg.get("hitstop", {}) as Dictionary).get(kind, [0.05, 0.15])
	_hitstop(float(hs[0]), float(hs[1]))
	_play_sfx("thud" if kind != "kb_light" else "hurt")


## 一瞬止める（当たった重さ）と、画面をゆらす
func _hitstop(sec: float, shake: float) -> void:
	shake_amp = maxf(shake_amp, shake)
	shake_left = 0.3
	if sec > 0.0 and is_inside_tree():
		hitstop_until_ms = Time.get_ticks_msec() + int(sec * 1000.0)
		Engine.time_scale = float(config.get("hitstop_time_scale", 0.06))


func _hitstop_update() -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= hitstop_until_ms:
		Engine.time_scale = 1.0


## 当たり場所の中にいれば、ダメージ（自分の分だけ調べる）。同じ当たりは1回だけ
func _apply_hazards(hz: Array) -> void:
	if downed or _me_held() or actions.invulnerable() or kb_guard_left > 0.0:
		return
	var me := _my_slot()
	var airborne := player.position.y > ground_y + float(attacks_cfg["dodge_height"])
	for h in hz:
		if not bool(h["active"]):
			continue
		var target := str(h["target"])
		if target != "" and target != me:
			continue
		var key := "%s:%d" % [h["id"], int(h["tick"])]
		if hazard_done.has(key):
			continue
		if bool(h["jumpable"]) and airborne:
			continue
		if not Attacks.inside(h, player.position.x, player.position.z):
			continue
		hazard_done[key] = true
		player_hit_flash = float(config["hit_flash_sec"])
		_take_damage(Damage.damage_amount(float(h["power"]), float(attacks_cfg["damage_multiplier"])))
		if h.has("stun"):
			stun_left = maxf(stun_left, float(h["stun"]))
		if bool(h.get("grab", false)) and not downed:
			_start_hold(me, Vector2(float(h["x"]), float(h["z"])))
		elif str(h.get("kb", "none")) != "none" and not downed:
			_knockback(str(h["kb"]), Attacks.knock_dir(h, player.position.x, player.position.z))
			return
		if downed:
			return


func _hazard_node(i: int, pool: Array = hazard_nodes, prefix: String = "Hazard") -> MeshInstance3D:
	while pool.size() <= i:
		var n := MeshInstance3D.new()
		n.name = prefix + str(pool.size())
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		n.set_meta("mat", m)
		var zm := ShaderMaterial.new()
		zm.shader = WARNING_SHADER
		n.set_meta("zmat", zm)
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		pool.append(n)
	return pool[i]


## 床に置く、扇・輪の形（半径1。種類と角度ごとに1回だけ作る）
var _floor_meshes := {}
func _floor_mesh(key: String, half: float, inner: float) -> ArrayMesh:
	if _floor_meshes.has(key):
		return _floor_meshes[key]
	var segs := maxi(8, int(ceil(half * 2.0 / TAU * 40.0)))
	var v := PackedVector3Array()
	for i in segs:
		var a0 := -half + 2.0 * half * float(i) / float(segs)
		var a1 := -half + 2.0 * half * float(i + 1) / float(segs)
		var o0 := Vector3(sin(a0), 0.0, cos(a0))
		var o1 := Vector3(sin(a1), 0.0, cos(a1))
		if inner <= 0.0:
			v.append_array([Vector3.ZERO, o0, o1])
		else:
			v.append_array([o0 * inner, o0, o1, o0 * inner, o1, o1 * inner])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_floor_meshes[key] = m
	return m


## 当たり場所の形の見た目（予告の面）を、node に置く。grow：予告の進み（0〜1。広がりの割合。1 で全体）
func _place_zone(n: MeshInstance3D, h: Dictionary, grow: float, y: float) -> void:
	var m: StandardMaterial3D = n.get_meta("mat")
	var shape := str(h["shape"])
	var key := shape
	var g := maxf(grow, 0.02)
	n.rotation = Vector3.ZERO
	match shape:
		"sector":
			key = "sector:%.3f" % float(h["half"])
			n.mesh = _floor_mesh(key, float(h["half"]), 0.0)
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.rotation.y = float(h["yaw"])
			n.scale = Vector3.ONE * float(h["r"]) * g
		"ring":
			# 輪：内側（安全な所）から外へ広がる。外の半径が変わるので、形は段階ごとに作る（20段）
			var r_in := float(h["r_in"])
			var outer := r_in + (float(h["r"]) - r_in) * (roundf(g * 20.0) / 20.0 if grow < 1.0 else 1.0)
			var ratio := snappedf(r_in / maxf(outer, r_in + 0.01), 0.02)  # 形の種類を増やしすぎない
			key = "ring:%.2f" % ratio
			n.mesh = _floor_mesh(key, PI, ratio)
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.scale = Vector3.ONE * maxf(outer, r_in + 0.01)
		"obox", "box":
			key = "box"
			if not _floor_meshes.has("box"):
				var bm := BoxMesh.new()
				bm.size = Vector3.ONE
				_floor_meshes["box"] = bm
			n.mesh = _floor_meshes["box"]
			if shape == "obox":
				# 向きのある帯：ボスの側から、前へのびる
				var yaw := float(h["yaw"])
				var f := Attacks.fwd_of(yaw)
				var hz := float(h["hz"])
				var c := Vector2(float(h["x"]), float(h["z"])) - f * hz * (1.0 - g)
				n.position = Vector3(c.x, y, c.y)
				n.rotation.y = yaw
				n.scale = Vector3(float(h["hx"]) * 2.0, 0.04, hz * 2.0 * g)
			else:
				n.position = Vector3(0.0, y, float(h["band_z"]))
				n.scale = Vector3(float(h["band_half"]) * 2.0, 0.04, float(h["hz"]) * 2.0 * g)
		_:
			key = "disc"
			if not _floor_meshes.has("disc"):
				_floor_meshes["disc"] = _floor_mesh("disc_f", PI, 0.0)
			n.mesh = _floor_meshes["disc"]
			n.position = Vector3(float(h["x"]), y, float(h["z"]))
			n.scale = Vector3.ONE * float(h["r"]) * g
	n.material_override = m
	# 予告の見た目（版60）：丸はオレンジの円、帯はオレンジの帯、ライドの道はピンクの帯＋矢印
	var zm: ShaderMaterial = n.get_meta("zmat")
	var zs: Dictionary = attacks_cfg.get("zone_style", {})
	var ride := str(h.get("style", "")) == "ride_lane"
	var safe := str(h.get("style", "")) == "safe"
	var look: Dictionary = zs.get("ride" if ride else ("safe" if safe else "attack"), {})
	zm.set_shader_parameter("fill_color", Color(str(look.get("fill", "#ff6b2852"))))
	zm.set_shader_parameter("rim_color", Color(str(look.get("rim", "#ffcfa0f2"))))
	zm.set_shader_parameter("mode", 2 if ride else (1 if key == "box" else 0))
	zm.set_shader_parameter("grow_axis", 1 if shape == "obox" else 0)
	zm.set_shader_parameter("inner", snappedf(float(h["r_in"]) / maxf(float(h["r"]), 0.01), 0.001) if shape == "ring" else 0.0)
	zm.set_shader_parameter("size", Vector2(n.scale.x, n.scale.z))
	zm.set_shader_parameter("dir", signf(float(h.get("dir", 1.0))) if float(h.get("dir", 1.0)) != 0.0 else 1.0)
	for sk in ["stripe_width", "rim_width", "arrow_spacing", "arrow_speed"]:
		if zs.has(sk):
			zm.set_shader_parameter(sk, float(zs[sk]))
	n.material_override = zm


var hazard_fill_nodes: Array = []


## 当たり場所の見た目：予告は、うすい全体の面＋中から広がる濃い面（広がりきったら当たる）。当たる瞬間は、明るい色
func _show_hazards(hz: Array) -> void:
	var fill_used := 0
	var drop_used := 0
	var bat_used := false
	var bottle_used := 0
	var lighter_used := false
	rain_seen = false
	for i in hz.size():
		var h: Dictionary = hz[i]
		var n := _hazard_node(i)
		var m: StandardMaterial3D = n.get_meta("mat")
		var style := str(h["style"])
		var active := bool(h["active"])
		if style == "paper":
			if n.get_meta("kind", "") != "paper":
				n.set_meta("kind", "paper")
				var b := BoxMesh.new()
				b.size = Vector3.ONE
				n.mesh = b
				n.material_override = m
			n.position = Vector3(float(h["x"]), 0.9, float(h["z"]))
			n.scale = Vector3(0.9, 0.08, 1.2)
			n.rotation = Vector3(0.3, float(h["age"]) * 9.0, 0.2)
			m.albedo_color = Color(str(attacks_cfg["paper_color"]))
			n.visible = true
			continue
		n.set_meta("kind", "zone")
		if style == "bat":
			# 投げたバット：回りながら飛ぶ（当たり場所の輪は出さない）
			var fb := _flying_bat()
			fb.visible = true
			fb.global_position = Vector3(float(h["x"]), float(attacks_cfg["kinds"]["bat_throw"].get("fly_height", 2.6)), float(h["z"]))
			fb.rotation = Vector3(0.0, float(h.get("spin", 0.0)), PI * 0.5)
			bat_used = true
			n.visible = false
			continue
		if style == "sake":
			# 酒のしずく：輪の上から落ちてくる（落ちきった瞬間に当たる）。当たったら、床がぬれる
			if not active:
				var d := _drop_node(drop_used)
				drop_used += 1
				var tl := float(h["tele"])
				d.position = Vector3(float(h["x"]), 0.4 + float(attacks_cfg.get("drop_height", 14.0)) * (1.0 - tl * tl), float(h["z"]))
				d.visible = true
			elif not puddle_seen.has(str(h["id"])):
				puddle_seen[str(h["id"])] = true
				_add_puddle(Vector3(float(h["x"]), 0.0, float(h["z"])), float(h["r"]), str(h["id"]))
		if style == "bottle" and active and str(h["id"]).begins_with("rb") and not _landed.has(str(h["id"])):
			# 巨大酒瓶ライドで投げた瓶が、地面で割れる（ガラスの破片。酒だまりは残さない）
			_landed[str(h["id"])] = true
			_burst_fx(Vector3(float(h["x"]), 0.3, float(h["z"])), "glass")
			_play_sfx("thud")
		if style == "bottle" and h.has("bottle"):
			# 飛んでいる酒瓶（回りながら）
			var bn := _bottle_node(bottle_used)
			bottle_used += 1
			bn.position = h["bottle"]
			bn.rotation = Vector3(float(h.get("spin", 0.0)), 0.0, float(h.get("spin", 0.0)) * 0.6)
			bn.scale = Vector3.ONE * 1.4
			bn.visible = true
		if style == "lighter" and h.has("lighter"):
			var ln := _lighter_node()
			ln.position = h["lighter"]
			ln.rotation = Vector3(_round_t() * 8.0, 0.0, 0.0)
			ln.visible = true
			lighter_used = true
		if style == "fire":
			# 燃えている所：炎は _update_fires。当たり場所の面は出さない（炎が見えるので）
			n.visible = false
			continue
		if style == "hand" and active:
			n.visible = false
			continue
		if style == "rain":
			# 酒の大雨：ステージ全体なので、床の面は出さない（雨のしずくを全体に降らせる。安全地帯は style "safe" の円）
			rain_seen = true
			n.visible = false
			continue
		if style == "ride":
			# 走っている瓶そのものが見えるので、当たり場所の面は出さない（道の予告は ride_lane）
			n.visible = false
			continue
		var tele := float(h["tele"])
		_place_zone(n, h, 1.0, 0.03)
		var zm: ShaderMaterial = n.get_meta("zmat")
		zm.set_shader_parameter("progress", tele)
		zm.set_shader_parameter("active", 1.0 if active else 0.0)
		# 害のない予告（酒の大雨の落ちる前など）はうすく
		zm.set_shader_parameter("strength", float(attacks_cfg["kinds"]["flyers"].get("tele_alpha", 0.3)) * (0.5 + 0.5 * tele) / 0.3 if float(h.get("power", 1.0)) <= 0.0 and style != "safe" else 1.0)
		n.visible = true
	for i in range(hz.size(), hazard_nodes.size()):
		(hazard_nodes[i] as Node3D).visible = false
	for i in range(fill_used, hazard_fill_nodes.size()):
		(hazard_fill_nodes[i] as Node3D).visible = false
	for i in range(drop_used, drop_nodes.size()):
		(drop_nodes[i] as Node3D).visible = false
	if not bat_used and _fly_bat != null:
		_fly_bat.visible = false
	for i in range(bottle_used, _bottle_nodes.size()):
		(_bottle_nodes[i] as Node3D).visible = false
	_rain_fx_update(rain_seen)
	if not lighter_used and _lighter != null:
		_lighter.visible = false


## ---- 版68：酒の大雨の雨（ステージ全体に、酒のしずくが降る。見た目だけ。当たりは style "rain" の当たり場所） ----
var rain_seen := false
var _rain_fx: CPUParticles3D
func _rain_fx_update(on: bool) -> void:
	if not on:
		if _rain_fx != null:
			_rain_fx.emitting = false
		return
	if _rain_fx == null:
		var half := float(config["bounds"]) + 2.0
		_rain_fx = CPUParticles3D.new()
		_rain_fx.name = "SakeRain"
		_rain_fx.amount = int(attacks_cfg["kinds"]["flyer_storm"].get("rain_drops", 220))
		_rain_fx.lifetime = 0.9
		_rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_rain_fx.emission_box_extents = Vector3(half, 0.5, half)
		_rain_fx.position = Vector3(0, 18.0, 0)
		_rain_fx.direction = Vector3(0, -1, 0)
		_rain_fx.spread = 4.0
		_rain_fx.gravity = Vector3(0, -30, 0)
		_rain_fx.initial_velocity_min = 8.0
		_rain_fx.initial_velocity_max = 12.0
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.7, 0.08)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(str(attacks_cfg.get("sake_color", "#f2e6b8")), 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = m
		_rain_fx.mesh = bm
		_rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rain_fx)
	_rain_fx.emitting = true


## ---- 巨大酒瓶ライドの酒瓶：ボスがまたがる、横だおしの大きな一升瓶（単色の形の組み合わせ。素材は使わない）----
var _ride_bottle: Node3D
func _update_ride_bottle(on: bool) -> void:
	if not on:
		if _ride_bottle != null:
			_ride_bottle.visible = false
		return
	if _ride_bottle == null:
		var rk: Dictionary = attacks_cfg["kinds"]["bottle_ride"]
		_ride_bottle = Node3D.new()
		_ride_bottle.name = "RideBottle"
		_ride_bottle.top_level = true
		add_child(_ride_bottle)
		# 版63：一升瓶の形を、1つのなめらかな面で作り直した（scripts/boss/sake_bottle_mesh.gd）。長さ＝half_len×2、胴の半径＝bottle_radius
		var radius := float(rk.get("bottle_radius", 1.6))
		var length := float(rk["half_len"]) * 2.0
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = BottleMesh.build(length, radius, BottleMesh.colors_from(rk), 24)
		_ride_bottle.add_child(body)
		# 走ったあとに飛ぶ酒のしぶき（小さな粒。数は少なく）
		var spray := CPUParticles3D.new()
		spray.name = "Spray"
		spray.amount = 16
		spray.lifetime = 0.5
		spray.direction = Vector3(0, 1, -1)
		spray.spread = 35.0
		spray.initial_velocity_min = 4.0
		spray.initial_velocity_max = 7.0
		spray.gravity = Vector3(0, -18, 0)
		spray.position = Vector3(0, -radius * 0.3, -length * 0.5)
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		sm.radial_segments = 6
		sm.rings = 3
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(str(attacks_cfg.get("sake_color", "#f2e6b8")), 0.8)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = smat
		spray.mesh = sm
		spray.local_coords = false
		_ride_bottle.add_child(spray)
	_ride_bottle.visible = true
	# 瓶の中心は、道の計算（boss_attacks.gd の ride_at）の bottle。ボスも同じ計算から座る位置が決まるので、ずれない
	var bc: Variant = motion.path_info.get("bottle", null)
	if bc is Vector3:
		_ride_bottle.position = bc  # top_level なので、position がそのまま世界の位置
	_ride_bottle.rotation = Vector3(0.0, float(motion.path_info.get("yaw", motion.yaw)), 0.0)
	(_ride_bottle.get_node("Spray") as CPUParticles3D).emitting = str(motion.path_info.get("phase", "")) == "pass"


## 投げたバット（ボスのバットと同じ形を、大きさをそろえて作る）
var _fly_bat: Node3D
func _flying_bat() -> Node3D:
	if _fly_bat == null:
		_fly_bat = Node3D.new()
		_fly_bat.name = "FlyingBat"
		_fly_bat.top_level = true
		add_child(_fly_bat)
		var catalog: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(CharacterView.ATTACHMENTS_PATH)) as Dictionary).get("items", {})
		var pivot := Node3D.new()
		pivot.position = Vector3(0, -0.6, 0) * float(boss_model.cfg["model_scale"]) if boss_model != null else Vector3.ZERO
		pivot.scale = Vector3.ONE * (float(boss_model.cfg["model_scale"]) if boss_model != null else 4.0)
		_fly_bat.add_child(pivot)
		for part in (catalog.get("oni_bat", {}) as Dictionary).get("parts", []):
			pivot.add_child(CharacterView._make_part(part))
	return _fly_bat


## ---- 酒のしずく・ぬれた床 ----
var drop_nodes: Array = []
var puddles: Array = []  ## ぬれた丸の見た目（使いまわす）
var puddle_seen := {}  ## もう床をぬらした当たりのid
var _sake_mat: StandardMaterial3D
var _wet_mesh: CylinderMesh


func _drop_node(i: int) -> MeshInstance3D:
	while drop_nodes.size() <= i:
		if _sake_mat == null:
			_sake_mat = StandardMaterial3D.new()
			_sake_mat.albedo_color = Color(str(attacks_cfg.get("sake_color", "#f2e6b8")), 0.85)
			_sake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_sake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 1.1
		sm.radial_segments = 8
		sm.rings = 4
		sm.material = _sake_mat
		var n := MeshInstance3D.new()
		n.name = "SakeDrop%d" % drop_nodes.size()
		n.mesh = sm
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		add_child(n)
		drop_nodes.append(n)
	return drop_nodes[i]


## 床に酒だまりを残すか（版61：data の puddles_enabled。いまは残さない）
func puddles_enabled() -> bool:
	return bool(attacks_cfg.get("puddles_enabled", true))


## 床に酒だまりを作る（場所・広さは、酒の雨・大雨のしずく）
func _add_puddle(pos: Vector3, r: float, id: String = "") -> void:
	if not puddles_enabled():
		return
	var k: Dictionary = attacks_cfg["kinds"].get("flyer_storm", {})
	var key := id if id != "" else "p%d_%d" % [int(pos.x * 10.0), int(pos.z * 10.0)]
	field.add(key, Vector2(pos.x, pos.z), r * 1.1, _round_t(), float(k.get("puddle_life", 4.0)), 0.2)


## 酒だまりの見た目：床の酒だまり（field）に合わせて、ぬれた丸を置く。燃えているものには、炎
func _update_puddles(_delta: float) -> void:
	var t := _round_t()
	field.prune(t)
	var wet := Color(str(attacks_cfg.get("wet_color", "#1d2a2a")))
	var live := field.alive(t)
	var max_n := int(attacks_cfg.get("wet_max", 40))
	var used := 0
	for p in live:
		if used >= max_n:
			break
		var node := _wet_node(used)
		used += 1
		var pos: Vector2 = p["pos"]
		var r := SakeField.radius_at(p, t)
		var sx := 0.9 + 0.2 * fposmod(pos.x * 7.3 + pos.y * 3.1, 1.0)
		node.position = Vector3(pos.x, 0.015, pos.y)
		node.rotation.y = fposmod(pos.x * 1.7 - pos.y * 2.3, TAU)
		node.scale = Vector3(r * sx, 1.0, r * (2.0 - sx))
		var left := float(p["expire"]) - t
		var mat := node.material_override as StandardMaterial3D
		var burnt := float(p["burn_end"]) >= 0.0 and t >= float(p["burn_end"])
		var col := Color(0.12, 0.1, 0.09) if burnt else wet
		mat.albedo_color = Color(col.r, col.g, col.b, 0.6 * clampf(left / 1.5, 0.0, 1.0))
		node.visible = true
	for i in range(used, puddles.size()):
		(puddles[i] as Node3D).visible = false
	_update_fires(t)


func _wet_node(i: int) -> MeshInstance3D:
	while puddles.size() <= i:
		if _wet_mesh == null:
			_wet_mesh = CylinderMesh.new()
			_wet_mesh.top_radius = 1.0
			_wet_mesh.bottom_radius = 1.0
			_wet_mesh.height = 0.02
			_wet_mesh.radial_segments = 16
			_wet_mesh.rings = 1
		var node := MeshInstance3D.new()
		node.name = "Wet%d" % puddles.size()
		node.mesh = _wet_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = m
		add_child(node)
		puddles.append(node)
	return puddles[i]


## ---- 酒瓶・ライター・火（見た目） ----
var field := SakeField.new()  ## 床の酒だまり（ゲームの物）
var _bottle_nodes: Array = []
var _fire_nodes: Array = []
var _fx_pool: Array = []
var _fx_next := 0
var _lighter: Node3D
var _landed := {}  ## 割れた瓶の id
var _ignited := {}  ## 火をつけた攻撃の番号


## 戦いの進みに合わせて、瓶が割れた所に酒だまりを作り、火祭りのライターが落ちたら火をつける
func _sake_field_update() -> void:
	if current_attack.is_empty():
		return
	var kind := str(current_attack["kind"])
	if kind != Attacks.SAKE_DROP and kind != Attacks.FIRE_FEST:
		return
	var k := Attacks.kind_cfg(attacks_cfg, current_attack)
	var ctx := _attack_ctx(current_attack, current_attack_u)
	ctx["n"] = int(current_attack["n"])
	var start := float(current_attack["start"])
	for b in Attacks.sake_bottles(current_attack, k, ctx):
		if current_attack_u >= float(b["land"]) and not _landed.has(str(b["id"])):
			_landed[str(b["id"])] = true
			var to: Vector2 = b["to"]
			if puddles_enabled():
				field.add(str(b["id"]), to, float(k["puddle_r"]), start + float(b["land"]), float(k["puddle_life"]))
			_burst_fx(Vector3(to.x, 0.3, to.y), "glass")
			_play_sfx("thud")
	if kind == Attacks.FIRE_FEST and not _ignited.has(int(current_attack["n"])):
		var l := Attacks.lighter_at(current_attack_u, k, ctx)
		if current_attack_u >= float(l["land"]):
			_ignited[int(current_attack["n"])] = true
			var tg: Vector2 = l["target"]
			field.ignite("f%d" % int(current_attack["n"]), tg, start + float(l["land"]), float(k["ignite_reach"]), float(k["fire_hop"]), float(k["fire_burn"]), float(k["link_gap"]))
			_burst_fx(Vector3(tg.x, 0.3, tg.y), "spark")
			_play_sfx("ultimate")


func _bottle_node(i: int) -> Node3D:
	while _bottle_nodes.size() <= i:
		# 投げる酒瓶：巨大酒瓶と同じ形（scripts/boss/sake_bottle_mesh.gd）を小さくしたもの。立てた向き（口が上）
		var n := Node3D.new()
		n.name = "Bottle%d" % _bottle_nodes.size()
		var rk: Dictionary = attacks_cfg["kinds"].get("bottle_ride", {})
		var mi := MeshInstance3D.new()
		mi.mesh = BottleMesh.build(1.3, 0.17, BottleMesh.colors_from(rk), 10)
		mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		n.visible = false
		add_child(n)
		_bottle_nodes.append(n)
	return _bottle_nodes[i]


func _lighter_node() -> Node3D:
	if _lighter == null:
		_lighter = MeshInstance3D.new()
		_lighter.name = "Lighter"
		var b := BoxMesh.new()
		b.size = Vector3(0.45, 0.75, 0.25)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#d22c2c")
		m.emission_enabled = true
		m.emission = Color("#ff7a1a")
		m.emission_energy_multiplier = 0.8
		b.material = m
		(_lighter as MeshInstance3D).mesh = b
		_lighter.visible = false
		add_child(_lighter)
	return _lighter


## 一回だけ飛び散る粒（ガラスとしぶき／火花）。何こかを使いまわす
func _burst_fx(pos: Vector3, kind: String) -> void:
	if not is_inside_tree():
		return
	while _fx_pool.size() < 6:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 0.95
		p.amount = 24
		p.lifetime = 0.8
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3(0, -18, 0)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.06)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.material = mat
		p.mesh = bm
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_fx_pool.append(p)
	var e: CPUParticles3D = _fx_pool[_fx_next % _fx_pool.size()]
	_fx_next += 1
	e.global_position = pos
	var g := Gradient.new()
	if kind == "spark":
		g.set_color(0, Color("#fff2a0"))
		g.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	else:
		# ガラス（緑）と、酒のしぶき（白っぽい）
		g.set_color(0, Color("#7fd18a"))
		g.add_point(0.5, Color(str(attacks_cfg.get("sake_color", "#f2e6b8")), 0.9))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	e.color_ramp = g
	e.restart()


## 燃えている酒だまりに、炎の粒と、赤い光
func _update_fires(t: float) -> void:
	var burning := field.burning(t)
	for i in burning.size():
		var p: Dictionary = burning[i]
		var f := _fire_node(i)
		var pos: Vector2 = p["pos"]
		var r := SakeField.radius_at(p, t)
		f.position = Vector3(pos.x, 0.0, pos.y)
		var em := f.get_child(0) as CPUParticles3D
		em.emission_sphere_radius = r * 0.8
		em.emitting = true
		var glow := f.get_child(1) as MeshInstance3D
		glow.scale = Vector3(r, 1.0, r)
		var left := float(p["burn_end"]) - t
		(glow.material_override as StandardMaterial3D).albedo_color.a = 0.55 * clampf(left / 0.5, 0.0, 1.0)
		f.visible = true
	for i in range(burning.size(), _fire_nodes.size()):
		var f2: Node3D = _fire_nodes[i]
		f2.visible = false
		(f2.get_child(0) as CPUParticles3D).emitting = false


func _fire_node(i: int) -> Node3D:
	while _fire_nodes.size() <= i:
		var n := Node3D.new()
		n.name = "Fire%d" % _fire_nodes.size()
		var p := CPUParticles3D.new()
		p.amount = 22
		p.lifetime = 0.7
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 1.5
		p.direction = Vector3.UP
		p.spread = 15.0
		p.gravity = Vector3(0, 6, 0)
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.5
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.2
		var q := QuadMesh.new()
		q.size = Vector2(0.9, 1.4)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		q.material = m
		p.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color("#ffe066"))
		g.add_point(0.4, Color("#ff6a1a"))
		g.set_color(g.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
		p.color_ramp = g
		p.position = Vector3(0, 0.4, 0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(p)
		var glow := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 1.0
		c.bottom_radius = 1.0
		c.height = 0.02
		c.radial_segments = 16
		c.rings = 1
		glow.mesh = c
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
		glow.material_override = gm
		glow.position = Vector3(0, 0.03, 0)
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(glow)
		n.visible = false
		add_child(n)
		_fire_nodes.append(n)
	return _fire_nodes[i]


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
		if _ai_active():
			if _ai_all_down():
				lost = true
				round_end_ms = server_now_ms()
				_play_sfx("lose")
				round_ended.emit(false)
		elif BossSync.all_down(my_hp, net_state.get("hp", {}), str(net_state.get("slot", "")), net_state.get("members", []), round_start_ms):
			lost = true
			round_end_ms = server_now_ms()
			_play_sfx("lose")
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
	_share_my_character(now_ms)
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
		if not positions.has(slot) and not ai_allies.has(slot):
			other_target.erase(slot)
			other_pos.erase(slot)
			if others.has(slot):
				(others[slot] as Node).queue_free()
				others.erase(slot)
				other_views.erase(slot)


func _update_others(delta: float) -> void:
	var half := float(config["bounds"])
	var weight := Sync.smooth_weight(delta, float(config["smooth_per_sec"]))
	for slot in other_target:
		var target: Vector2 = other_target[slot]
		var current: Vector2 = other_pos.get(slot, target)
		current = current.lerp(target, weight)
		other_pos[slot] = current
		var node := _other_node(str(slot))
		var old_pos := node.position
		node.position = Vector3(current.x * 2.0 * half - half, ground_y + float(other_lift.get(slot, 0.0)), current.y * 2.0 * half - half)
		_update_other_view(str(slot), node, node.position - old_pos, delta)


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


## ほかの人のキャラの見た目。共有されたキャラにモデルがあれば、箱の代わりにモデルを出す（キャラが変われば作り直す）。
## 動いていれば走り、止まっていれば待つ。モデルがない・まだ共有されていなければ、箱のまま
func _update_other_view(slot: String, node: MeshInstance3D, step: Vector3, delta: float) -> void:
	var def := char_def_of(slot)
	var want := str(def.get("id", "")) if not def.is_empty() and CharacterData.has_model(def) else ""
	var have := ""
	if other_views.has(slot):
		have = str(other_views[slot].character.get("id", ""))
	if want != have:
		if other_views.has(slot):
			(other_views[slot] as Node).queue_free()
			other_views.erase(slot)
		if want == "":
			node.mesh = _other_box_mesh(slot)
		else:
			var view := CharacterView.new()
			if view.setup(def):
				view.position = Vector3(0.0, -ground_y, 0.0)
				node.add_child(view)
				node.mesh = null
				other_views[slot] = view
				_raise_marker(node)
			else:
				view.free()
	if other_views.has(slot) and delta > 0.0:
		var view: Node3D = other_views[slot]
		var speed := Vector2(step.x, step.z) / delta
		var moving := speed.length() > float(config.get("other_moving_speed", 0.5))
		var ally_busy: bool = ai_allies.has(slot) and (AiAlly.act(ai_allies[slot]) as Actions).busy()
		if ai_allies.has(slot) and bool(ai_allies[slot]["downed"]):
			view.play_action("down")
		elif not ally_busy:
			view.play_action("run" if moving else "idle")
			if moving:
				view.face(speed, delta)


func _other_box_mesh(slot: String) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * float(config["player_size"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _slot_color(slot)
	box.material = mat
	return box


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


func _start_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("start_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _draw_centered(center: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	var fs := int(float(config["ui_font_size"]) * scale)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	overlay.draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## なかまの体力の一覧（この戦いに出ている、自分以外）
## なかまの名前のあとに付ける、キャラの印（共有されていれば「サポート（いやし）」の形。まだなら空）
func _char_tag(slot: String) -> String:
	var def := char_def_of(slot)
	if def.is_empty():
		return ""
	return " " + str(def.get("role", "")) + "（" + str(def.get("name", "")) + "）"


func build_team_text() -> String:
	var fighters := BossSync.others_hp(net_state.get("hp", {}), str(net_state.get("slot", "")), net_state.get("members", []), round_start_ms)
	var text := ""
	for slot in fighters:
		text += "  " + str(slot) + _char_tag(str(slot)) + " " + str(ceili(float(fighters[slot])))
	for slot in ai_allies:
		text += "  " + str(slot) + _char_tag(str(slot)) + " " + str(ceili(float(ai_allies[slot]["hp"])))
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
	var held := _me_held()
	for id in actions.ids():
		var bc := _button_center(str(id), screen)
		var color := str(config["button_pressed_color"]) if float(button_flash.get(id, 0.0)) > 0.0 else (str(config["button_cooldown_color"]) if actions.cooldown_left(str(id)) > 0.0 or actions.busy() or held else str(config["button_color"]))
		var label := str(actions.def(str(id)).get("label", id))
		var is_ult := str(id) == "ultimate"
		if is_ult and not held:
			if gauge.is_ready():
				var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
				color = str(config["button_pressed_color"]) if float(button_flash.get(id, 0.0)) > 0.0 else str(config["ultimate_ready_color"])
				overlay.draw_circle(bc, br + 4.0 + 6.0 * pulse, Color(str(config["ultimate_ring_color"])).darkened(0.1))
			elif actions.busy():
				color = str(config["button_cooldown_color"])
		if held:
			label = "×"  # 版70：つかまれている間は、どのボタンも効かない
		overlay.draw_circle(bc, br, Color(color))
		if is_ult and not gauge.is_ready():
			overlay.draw_arc(bc, br + 6.0, -PI * 0.5, -PI * 0.5 + TAU * gauge.ratio(), 40, Color(str(config["ultimate_ring_color"])), 7.0)
		_draw_centered(bc, label, button_text)

	overlay.draw_string(font, Vector2(16, fs * 1.4), (str(config["hint_portrait"]) if is_portrait(screen) else str(config["hint"])) + "   " + str(config["build_label"]) + str(config["build_id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var bp: Array = _layout("bossbar_pos", screen)
	var bs: Array = _layout("bossbar_size", screen)
	var bar_rect := Rect2(Vector2(screen.x * bp[0], screen.y * bp[1]), Vector2(screen.x * bs[0], maxf(10.0, screen.y * bs[1])))
	overlay.draw_rect(bar_rect, Color(str(config["bossbar_back_color"])))
	var frac := boss_hp_ratio()
	var second := phase.phase != BossPhase.NORMAL
	overlay.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * frac, bar_rect.size.y)), Color(str(config["bossbar_color_awake"] if second else config["bossbar_color"])))
	# 第1形態の間は、右はしに「第2形態がある」ことを示す小さな印
	if not second:
		overlay.draw_rect(Rect2(bar_rect.position + Vector2(bar_rect.size.x - 6.0, 0.0), Vector2(6.0, bar_rect.size.y)), Color(str(config["bossbar_color_awake"])))
	var hp_text := str(config["boss_hp_label_awake"] if second else config["boss_hp_label"]) + "  " + str(ceili(boss_hp)) + " / " + str(int(phase.max_hp()))
	overlay.draw_string(font, Vector2(16, fs * 2.9), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var my_text := str(config["role_label"]) + "：" + str(role().get("name", "")) + (("（" + str(role()["character_name"]) + "）") if role().has("character_name") else "") + "  " + str(config["player_hp_label"]) + "  " + str(ceili(my_hp)) + " / " + str(ceili(role_value("hp")))
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
	if float(phase_text["left"]) > 0.0 and str(phase_text["text"]) != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.3), str(phase_text["text"]), Color(str(config.get("bossbar_color_awake", "#ffffff"))), 1.8)
	_draw_banner(screen)


## 必殺技の名前（使った瞬間にはね上がり、少しあとに消える）
func _draw_banner(screen: Vector2) -> void:
	var left := float(banner["left"])
	if left <= 0.0:
		return
	var total := maxf(0.01, float(banner["total"]))
	var age := total - left
	var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.25)
	var alpha := clampf(left / 0.4, 0.0, 1.0)
	var center := Vector2(screen.x * 0.5, screen.y * (float(config["banner_y_portrait"]) if is_portrait(screen) else float(config["banner_y"])))
	var fs := int(float(config["ui_font_size"]) * 2.4 * pop)
	var text := str(banner["text"])
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var back := Color(str(config["banner_back_color"]))
	back.a *= alpha
	overlay.draw_rect(Rect2(Vector2(0.0, center.y - fs * 0.9), Vector2(screen.x, fs * 1.8)), back)
	var col := Color(str(config["banner_color"]))
	col.a = alpha
	overlay.draw_string(font, center + Vector2(-w * 0.5 + 3.0, fs * 0.35 + 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha))
	overlay.draw_string(font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var who := str(banner["who"])
	if who != "":
		var fs2 := int(float(config["ui_font_size"]) * 0.9)
		var w2 := font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		overlay.draw_string(font, center + Vector2(-w2 * 0.5, fs * 0.95 + fs2 * 0.4), who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, alpha))
