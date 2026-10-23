extends Node3D
class_name StickPrototype
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
## 版85：音楽の合図（fall：ボスが倒れた、awake：覚醒）。画面の流れ（game_flow.gd）が曲を切りかえる
signal music_cue(cue: String)

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
const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")
const BattleUltFx := preload("res://scripts/prototype/battle_ult_fx.gd")
const BattleNet := preload("res://scripts/prototype/battle_net.gd")
const BattleSkills := preload("res://scripts/prototype/battle_skills.gd")
const BattleRevive := preload("res://scripts/prototype/battle_revive.gd")
const BattleAudio := preload("res://scripts/prototype/battle_audio.gd")
const MapLoader := preload("res://scripts/stage/map_loader.gd")
const TimeOfDay := preload("res://scripts/stage/time_of_day.gd")
const CameraRig := preload("res://scripts/prototype/camera_rig.gd")
const HpHud := preload("res://scripts/prototype/battle_hp_hud.gd")
const TargetLock := preload("res://scripts/combat/target_lock.gd")
const Projectiles := preload("res://scripts/combat/projectiles.gd")
const SkillHits := preload("res://scripts/combat/skill_hits.gd")
const BattleAiTeam := preload("res://scripts/prototype/battle_ai_team.gd")
const BattleGrab := preload("res://scripts/prototype/battle_grab.gd")
const BattleHud := preload("res://scripts/prototype/battle_hud.gd")
const BattleAttackFx := preload("res://scripts/prototype/battle_attack_fx.gd")
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
var banner := {"text": "", "who": "", "left": 0.0, "total": 1.0, "color": Color.WHITE}  ## 画面に出す必殺技名（版112：color＝役職の色）
var enemy_intro := {"left": 0.0, "total": 1.0, "name": "", "role": ""}  ## 版112：敵の登場（試合の始めに1回）
var awaken_fx := {"left": 0.0, "total": 1.0}  ## 版112：ボスの覚醒の演出（1試合に1回）
var awaken_fx_shown := false
var enemy_attack := {"left": 0.0, "total": 1.0, "text": "", "ult": false, "n": -1}  ## 版112：敵の攻撃の名前（右上。いつも1つだけ）
var cue_log: Array = []  ## 版112：出した演出の記録（テスト用。最大32）
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
var ult_fx := BattleUltFx.new(self)  ## 必殺技の見た目（battle_ult_fx.gd）
var net := BattleNet.new(self)  ## 通信（battle_net.gd）
var skills := BattleSkills.new(self)  ## 版78：キャラごとの攻撃の効果と見た目（battle_skills.gd）
var revive_sys := BattleRevive.new(self)  ## 版84：倒れた仲間の蘇生（battle_revive.gd）
var audio := BattleAudio.new(self)  ## 版85：戦いの音（ボスの足音・飛ぶ物の音。battle_audio.gd）
var map_cfg: Dictionary = {}  ## 版88：戦いのマップの設定（data/maps.json）
var map_root: Node3D = null  ## 版88：戦いのマップ（渋谷のスクランブル交差点。scripts/stage/map_loader.gd）
var tod := TimeOfDay.new()  ## 版90：時間帯（ふだんは夕方・ボスの覚醒の間は夜。scripts/stage/time_of_day.gd）
var sun: DirectionalLight3D = null
var hp_hud = HpHud.new(self)  ## 版92：体力の表示（ボス：上・自分：丸いアイコン＋数字。battle_hp_hud.gd）
var hud_portraits: Dictionary = {}  ## 版95：キャラID → 顔の絵（体力の表示の丸いアイコン。portrait_source が作る）
var portrait_source: Node = null  ## 版95：顔の絵を作る係（画面の流れ game_flow の portraits。なければ図形のアイコン）
var hud_role_color := Color("#5a6a88")  ## 版92：顔の絵がない時の、丸の色（役の色がわからない時）
## 版78：キャラごとの攻撃の状態（battle_skills.gd が使う）
var skill_fx: Array = []  ## 出している見た目 [{node, follow}]
var skill_fx_log: Array = []  ## 出した見た目の種類（テスト用）
var skill_log: Array = []  ## 起きた効果の種類（テスト用）
var skill_summons: Array = []  ## 呼び出した物 [{owner, pos, life, next, ...}]
var skill_speed := {}  ## 枠 → {left, mult}（超高速モード）
var skill_domes: Array = []  ## 版79：守り・回復の膜 [{kind, pos, radius, left, ...}]（中だけに効く）
var skill_projs: Array = []  ## 版79：飛んでいる物（銃弾・魔法・爆弾・回復の光）
var skill_gimmicks: Array = []  ## 版79：落ちたプレゼント（開いて爆発するまで）
var skill_ghosts: Array = []  ## 版79：残像
var skill_vanish := {}  ## 版79：枠 → {left, speed, bonus}（スピードファイターが消えている間）
var vanish_bonus := 1.0  ## 版79：消えた所から攻撃した、最初の技の倍率
var target_lock := TargetLock.new()  ## 版79：ターゲットロック（敵をタップ）
var ally_lock := ""  ## 版79：タップで選んだ味方（回復の光を送る先）
var approach_id := ""  ## 版79：近づいてから出す技（近くの攻撃で、敵が少し遠いとき）
var approach_left := 0.0
var _approach_go := false  ## 近づき終わって、技を出すところ（もう一度近づかない）
var lean := Vector2.ZERO  ## 版79：止まる・曲がるときの体のかたむき
var skill_time_stop_left := 0.0  ## 時間停止の残り秒
var skill_time_stop_resist_until := -999.0  ## この時刻までにまた止めると、ボスの耐性で短くなる
var boss_freeze_total := 0.0  ## 止まっていた時間の合計（ボスの攻撃の時計から引く）
var ai_team := BattleAiTeam.new(self)  ## AIの味方・先読み（battle_ai_team.gd）
var grab := BattleGrab.new(self)  ## つかみ・投げ（battle_grab.gd）
var hud := BattleHud.new(self)  ## 画面の描画（battle_hud.gd）
var attack_fx := BattleAttackFx.new(self)  ## ボスの攻撃の見た目（battle_attack_fx.gd）
var phase_text := {"text": "", "left": 0.0}  ## 形態が変わったときに、画面に出す文字
var hazard_nodes: Array = []
var hazard_done := {}
var grab_locked := {}
var stun_left := 0.0
var grab_state := {}
var sfx: Node = null
var last_attack_n := -1
var grab_last_target := Vector3.ZERO
var other_lift := {}
## AIの味方（通信なし、または部屋に自分ひとりのとき、空いた枠を埋める）。テストでは既定でオフ（流れの側がオンにする）
var ai_enabled := false
var ai_picks: Array = []
var ai_cfg: Dictionary = {}
var ai_allies := {}
var ai_hits := {}
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
var boss_last_flash := 0.0  # 版80：前のコマの hit_flash（上がったら、新しく当たった）
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
var since_pos_poll := 0.0  ## 版107：位置だけを読む間隔の時計
var net_buffers: Dictionary = {}  ## 版107：通信のなかまの位置の記録（枠 → SnapshotBuffer）
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
	# 版106：戦う4人の技・当たりの見た目を、見えない所で先に1回出しておく（はじめての見た目の引っかかりをなくす）。
	# 画面なし（テスト）では、絵の準備がないので出さない
	if DisplayServer.get_name() != "headless":
		skills.prewarm_fx()


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
	# 版88：戦いのマップ＝渋谷のスクランブル交差点（PLATEAU の本物の形。data/maps.json・scripts/stage/map_loader.gd）。
	# 交差点のまん中が (0,0,0)。前の緑の板は作らない（読めない時だけ、代わりに出す）
	map_cfg = MapLoader.current_map()
	map_root = MapLoader.build(map_cfg, "high", float(config["bounds"])) if not map_cfg.is_empty() else null
	if map_root != null:
		add_child(map_root)
	else:
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
	sun = light

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
	attack_fx.prewarm()  # 版105：投げるバットを先に作っておく（はじめて投げた瞬間の引っかかりをなくす）

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
	if map_root != null:
		tod.setup(map_cfg, camera.environment, sun, map_root)  # 版90：空・光・霧（夕方から）
	add_child(camera)
	camera.look_at_from_position(camera_offset, Vector3.ZERO, Vector3.UP)
	player_marker_material = _add_marker(player, Color(str(config["player_color"])))
	_attach_character()


## 版90：時間帯。ボスの覚醒（第2形態）の間は夜、それ以外（ふだん・勝った・負けた）は夕方。なめらかに切りかえる
func night_wanted() -> bool:
	return phase.is_awake() and not won and not lost


func _time_of_day_update(delta: float) -> void:
	if not tod.is_ready():
		return
	tod.set_night(night_wanted())
	tod.step(delta)


## 版88：戦いの場所（±bounds。交差点の中）から外へは出られない（念のための最後の守り。動きの計算でも止めている）。
## ボスにつかまれている間は、ボスの手についていくので、さわらない
func _keep_inside() -> void:
	var half := float(config["bounds"])
	if not _me_held():
		player.position.x = clampf(player.position.x, -half, half)
		player.position.z = clampf(player.position.z, -half, half)
	for slot in ai_allies:
		var a: Dictionary = ai_allies[slot]
		if bool(a.get("held", false)):
			continue
		var p: Vector2 = a["pos"]
		a["pos"] = Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))


## 版88：画質（low／high）に合わせて、マップの遠くの建物の見える距離・建物の影を変える
func set_map_quality(q: String) -> void:
	if map_root != null:
		MapLoader.set_quality(map_root, map_cfg, q)


## 版78：自分のキャラの id（選んでいなければ、既定のキャラ）
## 版79：味方（自分・AI）に、そのキャラがいるか
func _team_has(char_id: String) -> bool:
	if my_char_id() == char_id:
		return true
	for s in ai_allies:
		if str(ai_allies[s].get("id", "")) == char_id:
			return true
	return false


func my_char_id() -> String:
	if selected_character != "":
		return selected_character
	if characters_cfg.is_empty():
		characters_cfg = CharacterData.load_config()
	return str(characters_cfg.get("player_character", ""))


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
	_lean_update(delta)
	if downed:
		char_view.play_action("down")
		return
	# 版79：勝ったら、喜ぶ動き（くり返す）
	if won and not actions.busy() and char_view.has_action("win"):
		char_view.play_action("win")
		return
	# 攻撃の動きの間は、アニメは攻撃の出来事（steps）が決める。終わったら、走る・歩く・待つに戻る
	if not actions.busy():
		var act := CharacterData.pick_action(false, false, false, stick_vec.length() > 0.1 and actions.move_scale() > 0.0)
		# 版79：スティックを少しだけ倒したときは、歩く
		if act == "run" and stick_vec.length() < float(config.get("walk_stick_max", 0.45)) and char_view.has_action("walk"):
			act = "walk"
		char_view.play_action(act)
		char_view.face(stick_vec, delta)


var _lean_vel := Vector2.ZERO  ## 版79：体のかたむきに使う、なめらかにした速さ
var _lean_prev := Vector2.INF


## 版79：止まる・曲がる・走り出すときに、体を少しかたむける（速さの変わる向きへ。最大 lean_max_deg 度）
func _lean_update(delta: float) -> void:
	if delta <= 0.0:
		return
	var p2 := Vector2(player.position.x, player.position.z)
	if _lean_prev == Vector2.INF:
		_lean_prev = p2
	var v := (p2 - _lean_prev) / delta
	_lean_prev = p2
	var prev_v := _lean_vel
	_lean_vel = _lean_vel.lerp(v, clampf(10.0 * delta, 0.0, 1.0))
	var acc := (_lean_vel - prev_v) / delta
	var want := Vector2.ZERO
	if not actions.busy() and not downed:
		var f: float = char_view.facing
		var fwd := Vector2(sin(f), cos(f))
		var left := Vector2(cos(f), -sin(f))
		var k := float(config.get("lean_per_accel", 0.006))
		var mx := deg_to_rad(float(config.get("lean_max_deg", 8.0)))
		want = Vector2(clampf(acc.dot(fwd) * k, -mx, mx), clampf(acc.dot(left) * k, -mx, mx))
	lean = lean.lerp(want, clampf(8.0 * delta, 0.0, 1.0))
	char_view.rotation.x = lean.x
	char_view.rotation.z = -lean.y


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
var cam_zoom := 0.0  ## 版79：強い攻撃の時に、カメラが寄る割合（0〜。すぐ戻る）
var camera_look_h := 0.0  ## 版91：カメラが見る点の、床からの高さ（camera_rig）
var cam_zoom_goal := 0.0  ## 版91：寄る目標（cam_zoom は、ここへなめらかに近づいてから戻る）
var camera_vel := Vector3.ZERO  ## 版91：カメラがついていく速さ（ばねの動き）
var camera_rig_size := Vector2.ZERO  ## 版91：カメラの置き方を決めた時の画面の大きさ（変わったら決めなおす）


## 版79：強い攻撃（Y・Xのしめ・必殺技）が当たった手ごたえ。spec：[一瞬止める秒, 画面のゆれ, カメラの寄り]
func _impact(spec: Variant) -> void:
	if not (spec is Array) or (spec as Array).size() < 2:
		return
	var a: Array = spec
	_hitstop(float(a[0]), float(a[1]))
	if a.size() > 2:
		cam_zoom_goal = maxf(cam_zoom_goal, float(a[2]))  # 版91：一気に寄らず、なめらかに寄る（camera_update）


## カメラは、自分の動きに合わせて、ゆっくりついていく（動きの一部だけ）。f 秒あたりの追いつきの速さは data で決める
func camera_update(delta: float) -> void:
	var goal := Vector3(player.position.x, 0.0, player.position.z) * float(config["camera_follow"])
	var smooth_sec := float((config.get("camera_rig", {}) as Dictionary).get("follow_smooth_sec", 0.0))
	if smooth_sec > 0.0:
		# 版91：ばねのように、なめらかに動き始めて、なめらかに止まる（急に遠くへ動いても、カメラが跳ばない）
		var res := CameraRig.smooth_damp(camera_target, goal, camera_vel, smooth_sec, delta)
		camera_target = res[0]
		camera_vel = res[1]
	else:
		camera_target = camera_target.lerp(goal, Sync.smooth_weight(delta, float(config["camera_follow_per_sec"])))
	# 版63：ボスが高く跳んだときは、少し上を見て、少し引く（ボスの頭が画面から出ないように）。data の camera_boss_frame
	var bf: Dictionary = config.get("camera_boss_frame", {})
	var over := maxf(0.0, (motion.height if motion != null else 0.0) - float(bf.get("start_height", 1.5)))
	var want_lift := Vector2(minf(over * float(bf.get("look_up_per_m", 0.0)), float(bf.get("max_look_up", 0.0))), minf(over * float(bf.get("back_per_m", 0.0)), float(bf.get("max_back", 0.0))))
	cam_boss_lift = cam_boss_lift.lerp(want_lift, Sync.smooth_weight(delta, float(bf.get("follow_per_sec", 3.0))))
	# 版91：見る点は、床から camera_look_h（キャラの胸のあたり）。カメラは、そこから camera_offset（高さ・角度は camera_rig.gd）
	var look_at := camera_target + Vector3(0.0, camera_look_h + cam_boss_lift.x, 0.0)
	var back_dir := Vector3(0.0, camera_offset.y, camera_offset.z).normalized() if camera_offset.length() > 0.01 else Vector3.BACK
	var pos := camera_target + Vector3(0.0, camera_look_h, 0.0) + camera_offset + back_dir * cam_boss_lift.y
	# 版79：強い攻撃が当たった時の、カメラの寄り（すぐ戻る）。版91：寄るのも、なめらかに（1フレームで跳ばない）
	if cam_zoom_goal > 0.0 or cam_zoom > 0.0:
		var zin := float((config.get("camera_rig", {}) as Dictionary).get("zoom_in_per_sec", 1.5))
		if cam_zoom < cam_zoom_goal:
			cam_zoom = minf(cam_zoom_goal, cam_zoom + delta * zin)
			if is_equal_approx(cam_zoom, cam_zoom_goal):
				cam_zoom_goal = 0.0
		else:
			cam_zoom_goal = 0.0
			cam_zoom = maxf(0.0, cam_zoom - delta * float(config.get("cam_zoom_return_per_sec", 0.6)))
		pos = look_at + (pos - look_at) * (1.0 - cam_zoom)
	var basis := Basis.looking_at(look_at - pos, Vector3.UP)
	# 画面のゆれ（強い攻撃に当たったとき）。版91：なめらかな波で、カメラごと横・たてに動かす（向きは変えない＝遠くの背景ははねない）
	if shake_left > 0.0:
		shake_left = maxf(0.0, shake_left - delta)
		var total := float((config.get("camera_rig", {}) as Dictionary).get("shake_sec", 0.3))
		var o := CameraRig.shake_offset(config, total - shake_left, shake_amp, clampf(shake_left / maxf(total, 0.01), 0.0, 1.0))
		pos += (basis.x * o.x + basis.y * o.y) * float((config.get("camera_rig", {}) as Dictionary).get("shake_scale", 1.0))
		if shake_left <= 0.0:
			shake_amp = 0.0
	camera.transform = Transform3D(basis, pos)


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
	hp_hud.attach(overlay)  # 版102：体力の表示は自分の板に描き、見た目が変わった時だけ描き直す


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
	skills.prewarm_step()
	kb_guard_left = maxf(0.0, kb_guard_left - delta)
	if dormant:
		_dormant_update(delta)
		return
	var move := Vector2.ZERO if (downed or stun_left > 0.0) else stick_vec * actions.move_scale()
	player.position = StickMath.step_position(player.position, move, role_value("move_speed") * skills.speed_mult(_my_slot()), delta, float(config["bounds"]))
	hit_flash = maxf(0.0, hit_flash - delta)
	damage_numbers().update(delta)
	banner["left"] = maxf(0.0, float(banner["left"]) - delta)
	update_cues(delta)
	for id in button_flash.keys():
		button_flash[id] = maxf(0.0, float(button_flash[id]) - delta)
	dodge_text_left = maxf(0.0, dodge_text_left - delta)  # 版110：「回避！」の字
	if boss_model != null:
		# 版80：当たった直後の短い間だけ白く光る（連射でも、1発ごとに点めつして、当たったことが分かる）
		var bfs := float((config.get("hit_fx", {}) as Dictionary).get("boss_flash_sec", 0.15))
		boss_model.set_flash(hit_flash > float(config["hit_flash_sec"]) - bfs)
	net_update(delta, Time.get_ticks_msec())
	combat_update(delta)
	_time_of_day_update(delta)
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
	# 版102（軽量化）：色が変わった時だけ材質に書く（書くたびに、材質の数の送り直しが起きるため）
	var pc := _player_color()
	if player_material.albedo_color != pc:
		player_material.albedo_color = pc
	var mc := _slot_color(str(net_state.get("slot", "")))
	if player_marker_material.albedo_color != mc:
		player_marker_material.albedo_color = mc
	apply_orientation(Vector2(get_window().size) if get_window() != null else Vector2(16, 9))
	camera_update(delta)
	hp_hud.update(delta)
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
		else:
			tap_select(pos)  # 版79：ボタンの外をタップ：敵ならターゲットロック、味方なら回復の送り先


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
## 版102（軽量化）：毎コマ何回も呼ばれるので、選んだキャラと枠が同じ間は、前に作った物を返す（前は毎回、性能の辞書を写していた）。
## 呼ぶ所はどれも読むだけ（書きかえない）
var _role_cache: Dictionary = {}
var _role_key := ""


func role() -> Dictionary:
	var key := selected_character + "|" + str(net_state.get("slot", "")) + "|" + str(characters_cfg.size())
	if key == _role_key and not _role_cache.is_empty():
		return _role_cache
	_role_key = key
	_role_cache = _make_role()
	return _role_cache


func _make_role() -> Dictionary:
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


## 役職名（枠から。版109：剣士・瞬・拳士…＝キャラの name）。ほかの人は、共有されたキャラ。まだなら「なかま」。
## キャラを選んでいない時（古い試作）は、役割の名前
func role_name_of(slot: String) -> String:
	if ai_allies.has(slot):
		return str(char_def_of(slot).get("name", ""))
	if selected_character != "":
		if slot == str(net_state.get("slot", "p1")) or not net_active:
			return str(role().get("character_name", role().get("name", "")))
		var def := char_def_of(slot)
		return str(def.get("name", "")) if not def.is_empty() else str(config.get("others_label", "なかま"))
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
	tod.snap(false)  # 版90：戦いは夕方から
	hp_hud.reset()  # 版92
	round_end_ms = 0.0
	downed = false
	my_hits = 0.0
	_return_to_spawn()
	my_hp = role_value("hp")
	boss.visible = true
	recorder.clear()
	since_sample = 0.0
	# 版78：キャラごとの攻撃（data/char_actions.json）。剣士は共通の actions.json のまま
	var acfg := Actions.config_for(my_char_id())
	if str(acfg.get("character", "")) != str(actions.cfg.get("character", "")):
		actions = Actions.new(acfg)
	actions.reset()
	skills.reset()
	dodge_text_left = 0.0  # 版110
	dodge_count = 0
	revive_sys.reset()
	audio.reset()
	boss_freeze_total = 0.0
	gauge.reset()
	banner["left"] = 0.0
	# 版112：演出を消してから、敵の登場を出す（前の試合の物は残さない）
	awaken_fx = {"left": 0.0, "total": 1.0}
	awaken_fx_shown = false
	enemy_attack = {"left": 0.0, "total": 1.0, "text": "", "ult": false, "n": -1}
	show_enemy_intro()
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
	damage_numbers().items.clear()
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
	if _team_has("summoner"):
		skills.warm_mini()  # 版79：小さい兵隊の動きを、前もって作る（はじめて呼んだ時に止まらない）
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
	if skills.is_vanished(_my_slot()) and not ignore_invulnerable:
		return  # 版79：消えている間は当たらない
	amount *= skills.taken_mult(_my_slot())  # 版78・79：守りの膜の中なら、受けるダメージが減る
	if amount > 0.0 and skills.taken_mult(_my_slot()) < 1.0:
		skills.on_hazard_hit(_my_slot(), Vector2(boss.position.x, boss.position.z))
	if amount > 0.0:
		_play_sfx("hurt")
	_set_my_hp(Damage.apply_damage(my_hp, amount))


## ---- 3つの攻撃（通常・サブ・メイン）。時間の進みは player_actions.gd、数値は data/actions.json ----

## ---- 版79：ターゲットロック ----

## ボスの当たりの円柱 {kind, x, z, r, h, y0}（見えなければ {}）
func boss_info() -> Dictionary:
	if boss == null or not boss.visible:
		return {}
	return {"kind": "boss", "index": -1, "x": boss.position.x, "z": boss.position.z, "r": float(config["boss_size"]) * 0.5,
		"h": float(config.get("boss_hit_height", 5.4)), "y0": boss.position.y}


## サブ敵 i の当たりの円柱（いなければ {}）
func sub_info(i: int) -> Dictionary:
	if i < 0 or not sub_enemies_enabled() or crowd_state == null or not crowd_state.is_alive(i) or i >= sub_crowd.last_positions.size():
		return {}
	var p: Vector3 = sub_crowd.last_positions[i]
	return {"kind": "sub", "index": i, "x": p.x, "z": p.z, "r": float((config["sub_enemy_size"] as Array)[0]) * 0.5, "h": 1.4, "y0": ground_y}


## いまねらう敵：ロックした敵。いなければボス
func target_info() -> Dictionary:
	if target_lock.kind == "sub":
		var si := sub_info(target_lock.index)
		if not si.is_empty():
			return si
	return boss_info()


## ロックが、まだ有効か（敵が倒れた・消えた・戦いが終わった→外す）
func _target_lock_update(delta: float) -> void:
	target_lock.tick(delta)
	if not target_lock.is_locked():
		return
	if not round_active() or (target_lock.kind == "boss" and boss_info().is_empty()) or (target_lock.kind == "sub" and sub_info(target_lock.index).is_empty()):
		var was_sub := target_lock.kind == "sub"
		target_lock.clear()
		if was_sub and round_active() and not boss_info().is_empty() and bool(config.get("relock_on_kill", true)):
			target_lock.set_target("boss")  # 倒したら、近くの敵（ボス）を選び直す


## 画面のタップ：敵ならロック（同じ敵なら外す）、味方なら回復の送り先。どちらでもなければ何もしない
func tap_select(pos: Vector2) -> bool:
	if camera == null or not round_active():
		return false
	var cands: Array = []
	var bi := boss_info()
	if not bi.is_empty():
		var c3 := Vector3(float(bi["x"]), float(bi["y0"]) + float(bi["h"]) * 0.5, float(bi["z"]))
		if not camera.is_position_behind(c3):
			cands.append({"kind": "boss", "index": -1, "screen": camera.unproject_position(c3), "r_px": _screen_radius(c3, float(bi["r"]) * 1.1)})
	if sub_enemies_enabled():
		for i in sub_crowd.last_positions.size():
			var si := sub_info(i)
			if si.is_empty():
				continue
			var c4 := Vector3(float(si["x"]), ground_y + 0.7, float(si["z"]))
			if not camera.is_position_behind(c4):
				cands.append({"kind": "sub", "index": i, "screen": camera.unproject_position(c4), "r_px": _screen_radius(c4, 0.9)})
	var pick := TargetLock.pick(pos, cands, float(config.get("tap_slack_px", 30.0)))
	if not pick.is_empty():
		if target_lock.kind == str(pick["kind"]) and target_lock.index == int(pick["index"]):
			target_lock.clear()  # 同じ敵をもう一度タップ：ロックを外す
		else:
			target_lock.set_target(str(pick["kind"]), int(pick["index"]))
		_play_sfx("click")
		return true
	# 味方（回復の送り先）
	for slot in [_my_slot()] + ai_allies.keys():
		var p3 := skills.pos3_of(str(slot)) + Vector3(0, 1.0, 0)
		if camera.is_position_behind(p3):
			continue
		if pos.distance_to(camera.unproject_position(p3)) <= _screen_radius(p3, 0.8) + 20.0:
			ally_lock = "" if ally_lock == str(slot) else str(slot)
			return true
	return false


func _screen_radius(c: Vector3, r: float) -> float:
	var right := camera.global_transform.basis.x.normalized()
	return camera.unproject_position(c).distance_to(camera.unproject_position(c + right * r))


## ロック中に、近くの攻撃で敵が届かない：近づく必要があるか（遠すぎる時は近づかない＝届かないことを、照準の色で示す）
func _needs_approach(id: String) -> bool:
	var d := actions.def(id)
	if d.is_empty() or id == "ultimate" or (d.get("hits", []) as Array).is_empty():
		return false  # 版110：当たりのない技（Y の回避・効果の技）は、近づかない
	for h in d.get("hits", []):
		if (h as Dictionary).has("proj") or SkillHits.shape_of(h) != "melee":
			return false
	var ti := target_info()
	if ti.is_empty():
		return false
	var dist := Vector2(player.position.x, player.position.z).distance_to(Vector2(float(ti["x"]), float(ti["z"]))) - float(ti["r"])
	var reach := HitArea.reach_of(role_value("attack_reach"), float(d.get("radius_scale", 1.0)))
	return dist > reach and dist <= reach + float(config.get("approach_max_dist", 4.0))


## 近づいてから出す技：毎コマ、敵へ走る。届いたら技を出す。時間切れでも出す
func _approach_update(delta: float) -> void:
	if approach_id == "":
		return
	var ti := target_info()
	approach_left -= delta
	if ti.is_empty() or downed or not round_active():
		approach_id = ""
		return
	var to := Vector2(float(ti["x"]) - player.position.x, float(ti["z"]) - player.position.z)
	var d := actions.def(approach_id)
	var reach := HitArea.reach_of(role_value("attack_reach"), float(d.get("radius_scale", 1.0)))
	if to.length() - float(ti["r"]) <= reach * 0.9 or approach_left <= 0.0:
		var id := approach_id
		approach_id = ""
		_approach_go = true
		perform(id)
		_approach_go = false
		return
	var spd := role_value("move_speed") * skills.speed_mult(_my_slot()) * float(config.get("approach_speed_scale", 1.5))
	var stepv := to.normalized() * minf(spd * delta, to.length() - float(ti["r"]) - reach * 0.85)
	player.position.x += stepv.x
	player.position.z += stepv.y
	facing = to.normalized()
	if char_view != null:
		char_view.play_action("run")
		char_view.face_now(facing)


## 通常攻撃（いままでの「こうげき」）。始められたら true
func attack() -> bool:
	return perform("normal")


## id の攻撃を始める。始められたら true。戦いの外、ダウン中、つかまれ中は始められない
func perform(id: String) -> bool:
	if not round_active() or downed or _me_held() or stun_left > 0.0:
		return false
	var cooldown := role_value("attack_cooldown_sec") / skills.speed_mult(_my_slot()) if id == "normal" else -1.0
	if id == "ultimate" and not gauge.is_ready():
		return false
	# 版79：ロック中の近くの攻撃で、敵が少し遠いとき：まず近づいてから出す（追いかけるのは approach_max 秒まで）
	if target_lock.is_locked() and not _approach_go and approach_id == "" and _needs_approach(id):
		approach_id = id
		approach_left = float(config.get("approach_max_sec", 0.6))
		return true
	var dodge := bool(actions.def(id).get("dodge", false))
	if not actions.start(id, _dodge_direction() if dodge else _aim_direction(id), cooldown):
		return false
	if not dodge:
		vanish_bonus = skills.on_attack_start(_my_slot())  # 版79：消えていたら現れる（最初の一撃が強い）。回避では現れない
	if bool(actions.def(id).get("sweep_hit", false)):
		ult_start_pos = Vector2(player.position.x, player.position.z)  # 版72b・78：駆けぬけた道で当たりを調べる（必殺技・ダッシュ技）
	if id == "ultimate":
		gauge.consume()
		ult_last_ghost = Vector3.INF
		_show_banner(str(actions.def(id).get("name", "")), role_name_of(_my_slot()), float(actions.def(id).get("banner_sec", 1.6)))
		_play_sfx("ultimate")
	facing = actions.aim
	if dodge:
		# 版110：回避の転がりの音（ボスの攻撃の予告の音「whoosh」とは別の音にする。同じ音は続けて鳴らないので、予告が消えないように）
		_play_sfx(str((config.get("dodge", {}) as Dictionary).get("sfx_start", "jump")))
	if char_view != null:
		char_view.face_now(actions.aim)
	_handle_action_events(actions.update(0.0))
	return true


## 版110：Y の回避の向き：スティックを倒していれば、その向き。倒していなければ、ねらう敵の反対（敵がいなければ、うしろ）
func _dodge_direction() -> Vector2:
	if stick_vec.length() > 0.2:
		return stick_vec.normalized()
	var ti := target_info()
	if not ti.is_empty():
		var away := Vector2(player.position.x - float(ti["x"]), player.position.z - float(ti["z"]))
		if away.length() > 0.01:
			return away.normalized()
	return -facing if facing.length() > 0.01 else Vector2(0, 1)


var dodge_text_left := 0.0  ## 版110：「回避！」の字を出しておく秒
var dodge_count := 0  ## 版110：回避に成功した回数（テスト・記録用）


## 版110：回避に成功した（よけられる時間の中に、攻撃が当たった）：その攻撃は受けない。短い光と「回避！」
func _on_dodge_success(h: Dictionary) -> void:
	dodge_count += 1
	dodge_text_left = float((config.get("dodge", {}) as Dictionary).get("text_sec", 0.6))
	var at := Vector3(player.position.x, ground_y + 1.2, player.position.z)
	skills.spawn_at({"kind": "ring", "color": "#9fe8ff", "radius": 1.8, "life": 0.3}, at, Vector3(at.x, ground_y, at.z))
	skills.spawn_at({"kind": "spark", "color": "#e8faff", "size": 0.9, "life": 0.25}, at, at)
	_play_sfx(str((config.get("dodge", {}) as Dictionary).get("sfx_success", "free")))


## 攻撃の向き。ボスをねらう攻撃は、ボスの方へ。それ以外は、いま向いている方へ
func _aim_direction(id: String) -> Vector2:
	# 版79：ロックした敵がいれば、どの技もその敵へ向く。いなければ、今まで通り（ボスをねらう技だけボスへ）
	var ti := target_info()
	if (target_lock.is_locked() or bool(actions.def(id).get("aim_boss", false))) and not ti.is_empty():
		var to := Vector2(float(ti["x"]) - player.position.x, float(ti["z"]) - player.position.z)
		if to.length() > 0.01:
			return to
	return facing


## 攻撃の進み（毎コマ）。出来事を受けとり、体を動かす
func _actions_update(delta: float) -> void:
	if actions.busy() and (downed or _me_held() or not round_active()):
		actions.cancel()
		if not _me_held():
			player.position.y = ground_y
	_approach_update(delta)
	var was_busy := actions.busy()
	_handle_action_events(actions.update(delta))
	if not actions.busy():
		vanish_bonus = 1.0
	if was_busy:
		var half := float(config["bounds"])
		var dfwd: float = actions.frame_move.x
		if bool(actions.def(actions.active).get("stop_at_boss", false)):
			dfwd = HitArea.clip_forward(Vector2(player.position.x, player.position.z), actions.aim, dfwd, Vector2(boss.position.x, boss.position.z), float(config["boss_size"]) * 0.5 + float(actions.cfg.get("stop_margin", 0.9)))
		player.position.x = clampf(player.position.x + actions.aim.x * dfwd, -half, half)
		player.position.z = clampf(player.position.z + actions.aim.y * dfwd, -half, half)
		player.position.y = ground_y + actions.height
		_ult_ghost_update()
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
			"fx":
				skills.action_fx(_my_slot(), ev["spec"], actions.aim)
			"effect":
				skills.apply_effect(_my_slot(), ev["spec"], actions.aim, role_value("attack_power"))
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
		# 版72b：踏み込みの始めのポーズ（剣を構えた形）を1回だけ写し取り、通った道に同じ形の残像を並べる
		ult_ghost_parts = UltFx.bake_ghost(char_view) if char_view != null else []
		_spawn_ghost()
		return
	if mark == "landed":
		var k: Dictionary = attacks_cfg["kinds"]["grab"]
		_take_damage(Damage.damage_amount(float(k["drop_power"]), float(attacks_cfg["damage_multiplier"])), true)
		player_hit_flash = float(config["hit_flash_sec"])
		_play_sfx("thud")


## 攻撃が当たったか調べて、ダメージを与える。当たりの範囲は hit_area.gd、ダメージは damage.gd
func _resolve_hit(ev: Dictionary) -> void:
	# 版74：必殺技は、キャラの ultimate_scale 倍（剣士は0.7＝30%減。書いていなければ1倍）
	var ult_scale := float(role().get("ultimate_scale", 1.0)) if str(ev.get("action", "")) == "ultimate" else 1.0
	var dmg := Damage.damage_amount(role_value("attack_power"), float(config["attack_multiplier"]) * float(ev["multiplier"]) * ult_scale * skills.dealt_mult(_my_slot()) * vanish_bonus)
	var reach := HitArea.reach_of(role_value("attack_reach"), float(ev["radius_scale"]))
	var hit_boss := boss.visible and HitArea.hits(player.position, boss.position, reach, float(config["boss_size"]) * 0.5)
	# 版78：ビーム・爆発・まわりの当たり（skill_hits.gd）。当たった所に、技の見た目（hit の fx）を出す
	var hspec: Dictionary = ev.get("hit", {})
	if hspec.has("proj"):
		# 版79：飛ぶ物：発射口から撃ち、当たった時にダメージ（battle_skills.gd）
		skills.fire(_my_slot(), hspec, dmg, actions.aim, str(ev.get("action", "")))
		return  # 版85：撃った音は battle_skills.fire が鳴らす（銃・大砲・魔法・投げる）
	_play_sfx("slash")
	var ti := target_info()
	if not ti.is_empty() and str(ti.get("kind", "")) == "sub" and SkillHits.shape_of(hspec) == "melee":
		# 版79：ロックしたサブ敵への近くの攻撃
		var me2 := Vector2(player.position.x, player.position.z)
		if me2.distance_to(Vector2(float(ti["x"]), float(ti["z"]))) <= reach + float(ti["r"]):
			skills.deal(_my_slot(), dmg, str(ev.get("action", "")), Vector3(float(ti["x"]), ground_y + 0.8, float(ti["z"])), ti, hspec.get("fx", {}))
		return
	if SkillHits.shape_of(hspec) != "melee":
		var me := Vector2(player.position.x, player.position.z)
		var bxz2 := Vector2(boss.position.x, boss.position.z)
		hit_boss = boss.visible and SkillHits.hits(hspec, me, actions.aim, reach, bxz2, float(config["boss_size"]) * 0.5)
	if hspec.has("fx"):
		var fxs: Dictionary = (hspec["fx"] as Dictionary).duplicate()
		fxs["hit"] = hspec
		if not fxs.has("at"):
			fxs["at"] = "hit"
		skills.action_fx(_my_slot(), fxs, actions.aim)
	var slash_at := Vector2(player.position.x, player.position.z)
	if bool(actions.def(str(ev.get("action", ""))).get("sweep_hit", false)):
		# 版72b：駆けぬけながら斬る：始めた所から今の所までの道の、どこかから届けば当たる。斬撃は、ボスにいちばん近い所に出す
		var bxz := Vector2(boss.position.x, boss.position.z)
		hit_boss = boss.visible and HitArea.hits_sweep(ult_start_pos, slash_at, bxz, reach, float(config["boss_size"]) * 0.5)
		if hit_boss:
			slash_at = HitArea.closest_on(ult_start_pos, slash_at, bxz)
	if str(ev.get("action", "")) == "ultimate" and actions.def("ultimate").has("fx"):  # 剣士の斬撃（版78：ほかのキャラは自分の見た目）
		_ult_slash_fx(Vector3(slash_at.x, ground_y, slash_at.y), actions.aim, hit_boss and not phase.invulnerable(), true)
	if hit_boss and phase.invulnerable():
		_play_sfx("hit")  # 倒れて覚醒する間は、当たってもダメージは入らない
	elif hit_boss:
		_play_sfx("hit")
		if hspec.has("impact") or str(ev.get("action", "")) == "ultimate":
			_play_sfx("heavy")  # 版85：強い技は、低い「ずどん」も重ねる
		hit_flash = float(config["hit_flash_sec"])
		_damage_boss(dmg)
		if hspec.has("impact"):
			_impact(hspec["impact"])
		# 版79：当たった所に、役の色の火花（ファイター＝赤、剣士・アタッカー＝黄 など）
		var bi := boss_info()
		var me3 := Vector3(slash_at.x, ground_y + 1.3, slash_at.y)
		skills._spark(_my_slot(), Projectiles.surface_point(me3, bi), hspec.get("fx", {}) if hspec.get("fx", {}).has("size") else {"size": 0.7})
		_show_damage(dmg, str(ev.get("action", "")), Vector2(player.position.x, player.position.z))  # 版75：減らした量をそのまま出す
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
var ult_start_pos := Vector2.ZERO  ## 版72b：必殺技を始めた所（駆けぬけた道の当たりに使う）
var ult_ghost_parts: Array = []  ## 版72b：残像の形（踏み込みの始めに写す）
var ult_last_ghost := Vector3.INF  ## 版72b：最後に残像を置いた所


## → battle_ult_fx.gd
func _ult_ghost_update() -> void:
	ult_fx._ult_ghost_update()


## → battle_ult_fx.gd
func _spawn_ghost(p: Vector3 = Vector3.INF) -> void:
	ult_fx._spawn_ghost(p)


## → battle_ult_fx.gd
func ult_fx_spawn(kind: String, pos: Vector3, aim: Vector2, extra: Dictionary = {}) -> void:
	ult_fx.ult_fx_spawn(kind, pos, aim, extra)


## → battle_ult_fx.gd
func _ult_slash_fx(pos: Vector3, aim: Vector2, landed: bool, mine: bool) -> void:
	ult_fx._ult_slash_fx(pos, aim, landed, mine)


## → battle_hud.gd
func _show_banner(text: String, who: String, seconds: float, color: Color = Color(0, 0, 0, 0)) -> void:
	hud._show_banner(text, who, seconds, color if color.a > 0.0 else Color(str(selected_def().get("role_color", config.get("banner_color", "#ffe27a")))))


# ---------------------------------------------------------------- 版112：演出（敵の登場・覚醒・敵の攻撃の名前）

## 演出の残り時間を進める（毎コマ）
func update_cues(delta: float) -> void:
	for d in [enemy_intro, awaken_fx, enemy_attack]:
		d["left"] = maxf(0.0, float(d["left"]) - delta)


func _cue(name: String) -> void:
	cue_log.append(name)
	if cue_log.size() > 32:
		cue_log = cue_log.slice(16)


## 敵の登場（ENEMY APPROACH・名前・役）。試合の始めに1回（_begin_round から）
func show_enemy_intro() -> void:
	var ec: Dictionary = config.get("enemy_intro", {})
	var sec := float(ec.get("sec", 2.6))
	enemy_intro = {"left": sec, "total": sec, "name": str(ec.get("name", "")), "role": str(ec.get("role", "BOSS"))}
	_cue("intro")


## ボスの覚醒（AWAKENING／覚醒）。1試合に1回だけ（2回目は出さない）
func show_awakening() -> void:
	if awaken_fx_shown:
		return
	awaken_fx_shown = true
	var sec := float((config.get("awakening_fx", {}) as Dictionary).get("sec", 2.2))
	awaken_fx = {"left": sec, "total": sec}
	_cue("awaken")


## 敵の攻撃の名前（右上）。n：攻撃の番号（同じ攻撃では出し直さない）。前の名前は、すぐ入れかえる（ためない）
func show_enemy_attack(kind: String, n: int) -> void:
	if int(enemy_attack.get("n", -1)) == n and float(enemy_attack["left"]) > 0.0:
		return
	var nm := str((attacks_cfg.get("display_names", {}) as Dictionary).get(kind, ""))
	if nm == "":
		return
	var sec := float((config.get("enemy_attack_label", {}) as Dictionary).get("sec", 2.2))
	var ult := bool((((attacks_cfg.get("kinds", {}) as Dictionary).get(kind, {}) as Dictionary).get("ai", {}) as Dictionary).get("ultimate", false))
	enemy_attack = {"left": sec, "total": sec, "text": nm, "ult": ult, "n": n}
	_cue("attack:" + kind)


## → battle_hud.gd
func _button_center(id: String, screen: Vector2) -> Vector2:
	return hud._button_center(id, screen)


## → battle_hud.gd
func _button_at(pos: Vector2, screen: Vector2) -> String:
	return hud._button_at(pos, screen)


func _damage_boss(amount: float) -> void:
	gauge.charge(amount * float(role().get("gauge_rate", 1.0)))  # 版74：剣士だけ、ゲージが30%速くたまる
	my_hits += amount
	_recompute_boss_hp()
	if net_active:
		bridge.send_hits(my_hits)


func _round_t() -> float:
	return (server_now_ms() - round_start_ms) / 1000.0


## ---- 版71：AIの味方のための、ボスの攻撃の先読み ----
var ai_forecast: Array = []
var ai_forecast_t := -999.0


## → battle_ai_team.gd
func boss_forecast(horizon: float, step: float) -> Array:
	return ai_team.boss_forecast(horizon, step)


## → battle_hud.gd
func damage_numbers() -> RefCounted:
	return hud.damage_numbers()


## → battle_hud.gd
func _show_damage(amount: float, action: String, from: Vector2) -> void:
	hud._show_damage(amount, action, from)


## → battle_hud.gd
func _draw_damage_numbers(screen: Vector2) -> void:
	hud._draw_damage_numbers(screen)


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
		if not flow_mode:
			_play_sfx("win")  # 画面の流れの中では、勝ちの曲（音楽）を流すので、効果音は鳴らさない
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
	enemy_attack["left"] = 0.0  # 版112：攻撃をやめたので、攻撃の名前も消す
	_play_sfx("thud")
	music_cue.emit("fall")


## 覚醒の演出が終わった：第2形態の攻撃を始める
func _on_boss_awake() -> void:
	show_awakening()  # 版112：「AWAKENING／覚醒」（前の「覚醒！」の字の代わり）
	_play_sfx("roar")  # 版85：覚醒の雄たけび（音楽は覚醒の曲へ）
	music_cue.emit("awake")
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
	# 版80：当たるたびに（hit_flash が上がった時に）のけぞる。版79までは、つづけて当たると最初の1発だけだった
	# （当たらない間は、1コマで delta だけ減る。それより大きければ、このコマで新しく当たった）
	var hit_now := hit_flash > 0.0 and hit_flash > boss_last_flash - delta + 0.0001
	boss_last_flash = hit_flash
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


## → battle_attack_fx.gd
func _update_jump_shadow() -> void:
	attack_fx._update_jump_shadow()


## → battle_grab.gd
func _grab_anim_state() -> Dictionary:
	return grab._grab_anim_state()


## → battle_grab.gd
func _grab_aim_yaw() -> float:
	return grab._grab_aim_yaw()


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


## → battle_grab.gd
func _me_held() -> bool:
	return grab._me_held()


## → battle_grab.gd
func _start_hold(slot: String, from: Vector2) -> void:
	grab._start_hold(slot, from)


## → battle_grab.gd
func _release_hold(freed: bool) -> void:
	grab._release_hold(freed)


## → battle_grab.gd
func swordsman_slots() -> Array:
	return grab.swordsman_slots()


## → battle_grab.gd
func _quick_grab_check(t: float) -> void:
	grab._quick_grab_check(t)


## ---- 版67：つかみ投げの、投げる向き（版70：投げられた人がほかの人にぶつかる仕組みは消した） ----


## → battle_grab.gd
func _grab_update(delta: float) -> void:
	grab._grab_update(delta)


## ---- AIの味方 ----

## → battle_ai_team.gd
func _ai_active() -> bool:
	return ai_team._ai_active()


## → battle_ai_team.gd
func _ai_hits_total() -> float:
	return ai_team._ai_hits_total()


## → battle_ai_team.gd
func _ai_all_down() -> bool:
	return ai_team._ai_all_down()


## → battle_ai_team.gd
func _ai_reset() -> void:
	ai_team._ai_reset()


## → battle_ai_team.gd
func _ai_picks_resolved() -> Array:
	return ai_team._ai_picks_resolved()


## → battle_ai_team.gd
func _ai_update(delta: float) -> void:
	ai_team._ai_update(delta)


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
	skills.update(delta)
	revive_sys.update(delta)
	audio.update(delta)
	_keep_inside()
	_target_lock_update(delta)
	# 版78：時間停止の間は、ボスの攻撃の時計を止める（止まっていた時間を、攻撃の時計から引く）
	if skills.boss_frozen():
		skill_time_stop_left = maxf(0.0, skill_time_stop_left - delta)
		boss_freeze_total += delta
		if phase.tick(delta, _total_boss_damage_counted()) == BossPhase.AWAKE:
			_on_boss_awake()
			_recompute_boss_hp()
		if phase.phase == BossPhase.FALL:
			boss_hp = phase.hp(_total_boss_damage_counted())
		current_hazards = []
		_show_hazards([])
		_ai_update(delta)
		return
	var t := (server_now_ms() - round_start_ms) / 1000.0 - boss_freeze_total
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
			show_enemy_attack(str(a["kind"]), int(a["n"]))  # 版112：予告の音と同じ時に、攻撃の名前を右上へ
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


## → battle_attack_fx.gd
func _sake_spray_update() -> void:
	attack_fx._sake_spray_update()


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
	shake_left = float((config.get("camera_rig", {}) as Dictionary).get("shake_sec", 0.3))
	if sec > 0.0 and is_inside_tree():
		hitstop_until_ms = Time.get_ticks_msec() + int(sec * 1000.0)
		Engine.time_scale = float(config.get("hitstop_time_scale", 0.06))


func _hitstop_update() -> void:
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= hitstop_until_ms:
		Engine.time_scale = 1.0


## 当たり場所の中にいれば、ダメージ（自分の分だけ調べる）。同じ当たりは1回だけ
func _apply_hazards(hz: Array) -> void:
	# 版110：Y の回避の、よけられる時間の中は、当たる物を「回避成功」にする（その攻撃は受けない）
	var dodging := actions.dodging()
	if downed or _me_held() or (actions.invulnerable() and not dodging) or kb_guard_left > 0.0:
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
		if dodging:
			_on_dodge_success(h)
			continue
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


var hazard_fill_nodes: Array = []


## → battle_attack_fx.gd
func _show_hazards(hz: Array) -> void:
	attack_fx._show_hazards(hz)


var _rain_fx: CPUParticles3D


## ---- 巨大酒瓶ライドの酒瓶：ボスがまたがる、横だおしの大きな一升瓶（単色の形の組み合わせ。素材は使わない）----
var _ride_bottle: Node3D
## → battle_attack_fx.gd
func _update_ride_bottle(on: bool) -> void:
	attack_fx._update_ride_bottle(on)


## ---- 酒のしずく・ぬれた床 ----
var drop_nodes: Array = []
var puddles: Array = []  ## ぬれた丸の見た目（使いまわす）
var puddle_seen := {}  ## もう床をぬらした当たりのid


## → battle_attack_fx.gd
func puddles_enabled() -> bool:
	return attack_fx.puddles_enabled()


## → battle_attack_fx.gd
func _update_puddles(_delta: float) -> void:
	attack_fx._update_puddles(_delta)


## ---- 酒瓶・ライター・火（見た目） ----
var field := SakeField.new()  ## 床の酒だまり（ゲームの物）
var _bottle_nodes: Array = []
var _landed := {}  ## 割れた瓶の id
var _ignited := {}  ## 火をつけた攻撃の番号


## → battle_attack_fx.gd
func _sake_field_update() -> void:
	attack_fx._sake_field_update()


## → battle_attack_fx.gd
func _burst_fx(pos: Vector3, kind: String) -> void:
	attack_fx._burst_fx(pos, kind)


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
				if not flow_mode:
					_play_sfx("lose")
				round_ended.emit(false)
		elif BossSync.all_down(my_hp, net_state.get("hp", {}), str(net_state.get("slot", "")), net_state.get("members", []), round_start_ms):
			lost = true
			round_end_ms = server_now_ms()
			if not flow_mode:
				_play_sfx("lose")
			round_ended.emit(false)


## → battle_net.gd
func net_update(delta: float, now_ms: int) -> void:
	net.net_update(delta, now_ms)


## → battle_net.gd
func apply_net_state(state: Dictionary) -> void:
	net.apply_net_state(state)


## → battle_net.gd
func _update_others(delta: float) -> void:
	net._update_others(delta)


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


## → battle_net.gd
func _update_other_view(slot: String, node: MeshInstance3D, step: Vector3, delta: float) -> void:
	net._update_other_view(slot, node, step, delta)


## → battle_net.gd
func _other_node(slot: String) -> MeshInstance3D:
	return net._other_node(slot)


## → battle_hud.gd
func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return hud._stick_input(pos, screen)


## → battle_hud.gd
static func is_portrait(size: Vector2) -> bool:
	return BattleHud.is_portrait(size)


## → battle_hud.gd
func apply_orientation(window_size: Vector2) -> void:
	hud.apply_orientation(window_size)


## → battle_hud.gd
func _stick_center(screen: Vector2) -> Vector2:
	return hud._stick_center(screen)


## → battle_hud.gd
func _start_center(screen: Vector2) -> Vector2:
	return hud._start_center(screen)


## → battle_hud.gd
func build_team_text() -> String:
	return hud.build_team_text()


## → battle_hud.gd
func _draw_overlay() -> void:
	hud._draw_overlay()


