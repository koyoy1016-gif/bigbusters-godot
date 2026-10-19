extends RefCounted
## 必殺技の見た目のまとめ役（輪・残像・斬撃）
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
const BattleNet := preload("res://scripts/prototype/battle_net.gd")
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


func ult_fx_spawn(kind: String, pos: Vector3, aim: Vector2, extra: Dictionary = {}) -> void:
	b.ult_fx_log.append(kind)
	if b.ult_fx_log.size() > 20:
		b.ult_fx_log.pop_front()
	if b.is_inside_tree():
		UltFx.spawn(b, kind, pos, aim, b.actions.def("ultimate").get("fx", {}), extra)


## 斬った瞬間：三日月の斬撃（と、踏み込んだ道の残像）。当たったら、火花と、一瞬止める・画面をゆらす。mine：自分の必殺技
func _ult_slash_fx(pos: Vector3, aim: Vector2, landed: bool, mine: bool) -> void:
	var fx: Dictionary = b.actions.def("ultimate").get("fx", {})
	if mine:
		b.ult_dash_from = Vector3.INF
	ult_fx_spawn("slash", pos, aim)
	if landed:
		var bp := Vector2(b.boss.position.x, b.boss.position.z)
		var to := bp - Vector2(pos.x, pos.z)
		var contact := bp - to.normalized() * float(b.config["boss_size"]) * 0.5 if to.length() > 0.01 else bp
		if bool(fx.get("hit_spark", true)):
			b._burst_fx(Vector3(contact.x, 1.4, contact.y), "spark")
		b.ult_fx_log.append("hit")
		if mine:
			var hs: Array = fx.get("hitstop", [0.08, 0.3])
			b._hitstop(float(hs[0]), float(hs[1]))


## 版72b：踏み込みの間、ghost_spacing m 進むごとに、剣士の形の残像を置く
func _ult_ghost_update() -> void:
	if b.actions.active != "ultimate" or b.ult_last_ghost == Vector3.INF:
		return
	var fx: Dictionary = b.actions.def("ultimate").get("fx", {})
	var here := Vector3(b.player.position.x, b.ground_y, b.player.position.z)
	var spacing := maxf(0.5, float(fx.get("ghost_spacing", 2.2)))
	# 1コマで長く進んでも、通った道の上に、決めた間かくで並べる（画面が遅くても数が減らない）
	var guard := 0
	while here.distance_to(b.ult_last_ghost) >= spacing and guard < 10:
		_spawn_ghost(b.ult_last_ghost + (here - b.ult_last_ghost).normalized() * spacing)
		guard += 1


## p（床の上）に残像を1体置く。見た目の向き・大きさは、いまの剣士と同じ
func _spawn_ghost(p: Vector3 = Vector3.INF) -> void:
	var here := Vector3(b.player.position.x, b.ground_y, b.player.position.z)
	b.ult_last_ghost = here if p == Vector3.INF else p
	var xf: Transform3D = b.char_view.global_transform if b.char_view != null and b.char_view.is_inside_tree() else Transform3D(Basis(), here)
	xf.origin += b.ult_last_ghost - here
	ult_fx_spawn("ghost", b.ult_last_ghost, b.actions.aim, {"parts": b.ult_ghost_parts, "xform": xf})
