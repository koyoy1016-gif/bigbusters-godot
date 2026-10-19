extends RefCounted
## 通信（ほかの人の位置・状態のやりとりと、ほかの人の見た目）
## stick_prototype.gd（まとめ役。状態の変数はそちら）から分けた部品。本体の変数・関数は b. で使う。動きは分ける前と同じ。

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
const BattleAiTeam := preload("res://scripts/prototype/battle_ai_team.gd")
const BattleGrab := preload("res://scripts/prototype/battle_grab.gd")
const BattleHud := preload("res://scripts/prototype/battle_hud.gd")
const BattleAttackFx := preload("res://scripts/prototype/battle_attack_fx.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）


func _init(main: StickPrototype) -> void:
	b = main


## 通信：一定の間隔でブラウザ側の状態を読み、自分の位置を送り、ほかの人の箱をなめらかに動かす
func net_update(delta: float, now_ms: int) -> void:
	if not b.net_active:
		return
	b.since_poll += delta
	if b.since_poll >= float(b.config["net_poll_sec"]):
		b.since_poll = 0.0
		var state := b.bridge.read_state()
		if not state.is_empty():
			apply_net_state(state)
	b._share_my_character(now_ms)
	var me := str(b.net_state.get("slot", ""))
	if me != "" and Sync.should_send(now_ms, b.last_sent_ms, int(b.config["send_interval_ms"])):
		b.last_sent_ms = now_ms
		var half := float(b.config["bounds"])
		b.bridge.send_position((b.player.position.x + half) / (2.0 * half), (b.player.position.z + half) / (2.0 * half))
	_update_others(delta)


## ブラウザ側の状態を受け取る：戦いの開始、ほかの人の位置・ダメージ・体力
func apply_net_state(state: Dictionary) -> void:
	b.net_state = state
	var me := str(state.get("slot", ""))
	if b.round_start_ms <= 0.0:
		b.my_hp = b.role_value("hp")
	var members: Array = state.get("members", [])
	b.others_hits = BossSync.others_total(state.get("hits", {}), me, members)
	# 戦いの開始：新しい開始の時刻が来たら、始める。古すぎる時刻（前の日の戦いなど）は無視する
	var r := float(state.get("round", 0.0))
	if r != b.known_round:
		b.known_round = r
		var age_ms := b.server_now_ms() - r
		if r > 0.0 and age_ms <= float(b.config["round_max_sec"]) * 1000.0 and age_ms >= -float(b.config["round_future_sec"]) * 1000.0:
			b._begin_round(r)
	b._recompute_boss_hp()
	b._check_wipe()
	var positions := Sync.parse_positions(state.get("positions", {}))
	positions.erase(me)
	# いま部屋にいる人（members）の位置だけ出す。前の人の古い位置が残っていても、箱は出さない
	if state.has("members"):
		for slot in positions.keys():
			if not members.has(str(slot)):
				positions.erase(slot)
	for slot in positions:
		b.other_target[slot] = positions[slot]
	for slot in b.other_target.keys():
		if not positions.has(slot) and not b.ai_allies.has(slot):
			b.other_target.erase(slot)
			b.other_pos.erase(slot)
			if b.others.has(slot):
				(b.others[slot] as Node).queue_free()
				b.others.erase(slot)
				b.other_views.erase(slot)


func _update_others(delta: float) -> void:
	var half := float(b.config["bounds"])
	var weight := Sync.smooth_weight(delta, float(b.config["smooth_per_sec"]))
	for slot in b.other_target:
		var target: Vector2 = b.other_target[slot]
		var current: Vector2 = b.other_pos.get(slot, target)
		current = current.lerp(target, weight)
		b.other_pos[slot] = current
		var node := _other_node(str(slot))
		var old_pos := node.position
		node.position = Vector3(current.x * 2.0 * half - half, b.ground_y + float(b.other_lift.get(slot, 0.0)), current.y * 2.0 * half - half)
		_update_other_view(str(slot), node, node.position - old_pos, delta)


## ほかの人のキャラの見た目。共有されたキャラにモデルがあれば、箱の代わりにモデルを出す（キャラが変われば作り直す）。
## 動いていれば走り、止まっていれば待つ。モデルがない・まだ共有されていなければ、箱のまま
func _update_other_view(slot: String, node: MeshInstance3D, step: Vector3, delta: float) -> void:
	var def := b.char_def_of(slot)
	var want := str(def.get("id", "")) if not def.is_empty() and CharacterData.has_model(def) else ""
	var have := ""
	if b.other_views.has(slot):
		have = str(b.other_views[slot].character.get("id", ""))
	if want != have:
		if b.other_views.has(slot):
			(b.other_views[slot] as Node).queue_free()
			b.other_views.erase(slot)
		if want == "":
			node.mesh = _other_box_mesh(slot)
		else:
			var view := CharacterView.new()
			if view.setup(def):
				view.position = Vector3(0.0, -b.ground_y, 0.0)
				node.add_child(view)
				node.mesh = null
				b.other_views[slot] = view
				b._raise_marker(node)
			else:
				view.free()
	if b.other_views.has(slot) and delta > 0.0:
		var view: Node3D = b.other_views[slot]
		var speed := Vector2(step.x, step.z) / delta
		var moving := speed.length() > float(b.config.get("other_moving_speed", 0.5))
		var ally_busy: bool = b.ai_allies.has(slot) and (AiAlly.act(b.ai_allies[slot]) as Actions).busy()
		if b.ai_allies.has(slot) and bool(b.ai_allies[slot]["downed"]):
			view.play_action("down")
		elif not ally_busy:
			view.play_action("run" if moving else "idle")
			if moving:
				view.face(speed, delta)


func _other_box_mesh(slot: String) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * float(b.config["player_size"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = b._slot_color(slot)
	box.material = mat
	return box


func _other_node(slot: String) -> MeshInstance3D:
	if not b.others.has(slot):
		b.others[slot] = b._make_box("Other_" + slot, float(b.config["player_size"]), b._slot_color(slot))
		b._add_marker(b.others[slot], b._slot_color(slot))
	return b.others[slot]
