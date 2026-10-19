extends RefCounted
## つかみ・投げ・すぐ投げるつかみ
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
const BattleHud := preload("res://scripts/prototype/battle_hud.gd")
const BattleAttackFx := preload("res://scripts/prototype/battle_attack_fx.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）
var grab_hand := Vector3.ZERO


func _init(main: StickPrototype) -> void:
	b = main


func _me_held() -> bool:
	return not b.grab_state.is_empty() and str(b.grab_state["slot"]) == b._my_slot()


func _start_hold(slot: String, from: Vector2) -> void:
	if not b.grab_state.is_empty():
		return
	b._play_sfx("grab")
	var n := int(b.current_attack.get("n", 0))
	var hold := Attacks.grab_hold_sec(b.attacks_cfg, b.round_start_ms, n)
	if bool(b.current_attack.get("quick", false)):
		hold = float(b.attacks_cfg["kinds"]["grab"].get("quick_hold_sec", 0.25))  # 版68：すぐ投げるつかみ
	b.grab_state = {"slot": slot, "t": 0.0, "from": from, "squeeze": 0.0, "lift": 0.0, "hold": hold}
	if slot == b._my_slot():
		b.stun_left = maxf(b.stun_left, 0.1)
	b.grab_state["phase"] = "hold"
	b.grab_state["throw_t"] = 0.0
	grab_hand = Vector3(from.x, 0.9, from.y)


func _release_hold(freed: bool) -> void:
	var k: Dictionary = b.attacks_cfg["kinds"]["grab"]
	var slot := str(b.grab_state["slot"])
	var decided: Variant = b.grab_state.get("throw_dir", null)
	b.grab_state = {}
	if freed:
		b._play_sfx("free")
	if slot == b._my_slot():
		if freed:
			b.stun_left = maxf(b.stun_left, float(k["free_stun_sec"]))
			b.player.position.y = b.ground_y
		else:
			# 逃げられなかった：放り投げられる（着地のダメージと、転んで起き上がるまでは、player_actions の「thrown」）
			# 版67：ボスからいちばん遠い人のほうへ投げる（だれもいなければ、ボスの向き）
			var away: Vector2 = decided if decided is Vector2 else throw_dir(slot)
			b.actions.start("thrown", away, 0.0, true)
			if b.char_view != null:
				b.char_view.face_now(-away)
			b._handle_action_events(b.actions.update(0.0))
			b._play_sfx("whoosh")
	elif b.ai_allies.has(slot):
		var a: Dictionary = b.ai_allies[slot]
		a["held"] = false
		b.other_lift[slot] = 0.0
		if not freed:
			# 投げられる（着地のダメージは、AiAlly.step が「landed」の印で受ける）。向きは、いちばん遠い人のほう（版67）
			var away: Vector2 = decided if decided is Vector2 else throw_dir(slot)
			(AiAlly.act(a) as Actions).start("thrown", away, 0.0, true)
		else:
			a["stun"] = float(k["free_stun_sec"])


func _grab_update(delta: float) -> void:
	if b.grab_state.is_empty():
		return
	var k: Dictionary = b.attacks_cfg["kinds"]["grab"]
	var slot := str(b.grab_state["slot"])
	var mult := float(b.attacks_cfg["damage_multiplier"])
	b.grab_state["t"] = float(b.grab_state["t"]) + delta
	var t := float(b.grab_state["t"])
	# 版70：逃げる仕組み（「にげる」の連打・みんなのダメージで外れる）はない。つかまれたら必ず投げられる。
	# 外れるのは、つかまれた人が倒れたときと、戦いが終わったときだけ
	var is_me := slot == b._my_slot()
	var target_down := b.downed if is_me else (not b.ai_allies.has(slot) or bool(b.ai_allies[slot]["downed"]))
	if target_down or not b.round_active():
		_release_hold(true)
		return
	var throwing := str(b.grab_state.get("phase", "hold")) == "throw"
	if not throwing and t >= float(b.grab_state["hold"]):
		# つかむ時間が終わった：ボスが、うしろへ引いて前へ投げる動きに入る（手をはなす瞬間に、飛んでいく）
		b.grab_state["phase"] = "throw"
		b.grab_state["throw_t"] = 0.0
		throwing = true
		# 版67：投げる向きは、投げる動きに入った時点で決める（いちばん遠い人のほう）。ボスもそちらを向いて投げる
		var tdir := throw_dir(slot)
		b.grab_state["throw_dir"] = tdir
		var gn := int(b.current_attack.get("n", -1))
		if b.motion.locks.has(gn):
			b.motion.locks[gn]["yaw"] = atan2(tdir.x, tdir.y)
	if throwing:
		b.grab_state["throw_t"] = float(b.grab_state["throw_t"]) + delta
		if float(b.grab_state["throw_t"]) >= float(k["release_sec"]):
			_release_hold(false)
			return
	# 手の位置：ボスの左手（手のひらの少し下に、体がぶら下がる）。つかんだ直後は、つかんだ場所から手へ寄せる
	var hand: Vector3 = b.boss_model.hand_world("L") if b.boss_model != null else Vector3(b.boss.position.x, float(k["hold_height"]), b.boss.position.z)
	hand.y -= float(k.get("hang_below", 1.0))
	var lift := clampf(t / float(k["lift_sec"]), 0.0, 1.0)
	var from: Vector2 = b.grab_state["from"]
	var start := Vector3(from.x, b.ground_y, from.y)
	var held := start.lerp(hand, smoothstep(0.0, 1.0, lift))
	held.y = maxf(held.y, b.ground_y)
	var xz := Vector2(held.x, held.z)
	var y := held.y - b.ground_y
	grab_hand = held
	# しめつけのダメージ
	b.grab_state["squeeze"] = float(b.grab_state["squeeze"]) + delta
	if float(b.grab_state["squeeze"]) >= float(k["squeeze_tick_sec"]):
		b.grab_state["squeeze"] = float(b.grab_state["squeeze"]) - float(k["squeeze_tick_sec"])
		var sq := Damage.damage_amount(float(k["squeeze_power"]), mult)
		if is_me:
			b._take_damage(sq)
			b.player_hit_flash = float(b.config["hit_flash_sec"])
		else:
			var a2: Dictionary = b.ai_allies[slot]
			a2["hp"] = maxf(0.0, float(a2["hp"]) - sq)
			a2["flash"] = 0.15
			if float(a2["hp"]) <= 0.0:
				a2["downed"] = true
	if is_me:
		b.stun_left = maxf(b.stun_left, 0.1)
		b.player.position = Vector3(xz.x, b.ground_y + y, xz.y)
	elif b.ai_allies.has(slot):
		var a3: Dictionary = b.ai_allies[slot]
		a3["pos"] = xz
		b.other_lift[slot] = y
		var half := float(b.config["bounds"])
		b.other_target[slot] = Vector2((xz.x + half) / (2.0 * half), (xz.y + half) / (2.0 * half))
		b.other_pos[slot] = b.other_target[slot]


## ---- 版68：剣士をつかんですぐ投げる（1戦に1回、決めたランダムな時刻のあと） ----
## 剣士の枠：自分が剣士（キャラを選んでいない＝ファイター、または hero_swordsman）なら自分。AIの味方の剣士も。倒れていない人だけ
func swordsman_slots() -> Array:
	var out: Array = []
	var me := b._my_slot()
	var mine := b.selected_character
	if not b.downed and (mine == "" or mine == "hero_swordsman"):
		out.append(me)
	var names: Array = b.ai_allies.keys()
	names.sort()
	for slot in names:
		var a: Dictionary = b.ai_allies[slot]
		if str(a.get("id", "")) == "hero_swordsman" and not bool(a["downed"]):
			out.append(str(slot))
	return out


func _quick_grab_check(t: float) -> void:
	if b.quick_grab_done or b.quick_grab_at < 0.0 or t < b.quick_grab_at or b.won or b.lost or not b.phase.can_attack():
		return
	if not b.grab_state.is_empty() or str(b.current_attack.get("kind", "")) == Attacks.GRAB:
		return
	var targets := swordsman_slots()
	if targets.is_empty():
		return  # 剣士がいない・倒れている：無理に出さない（できるようになるまで待つ）
	b.quick_grab_done = true
	b.ai.request(Attacks.GRAB, {"target": str(targets[0]), "quick": true})


## 位置のわかる人（倒れていない）：枠 → 床の上の位置。自分・AIの味方・通信のほかの人
func _people_positions() -> Dictionary:
	var out := {}
	var me := b._my_slot()
	if not b.downed:
		out[me] = Vector2(b.player.position.x, b.player.position.z)
	var half := float(b.config["bounds"])
	for slot in b.other_pos:
		if b.ai_allies.has(slot) and bool(b.ai_allies[slot]["downed"]):
			continue
		var np: Vector2 = b.other_pos[slot]
		out[str(slot)] = (b.ai_allies[slot]["pos"] as Vector2) if b.ai_allies.has(slot) else Vector2(np.x * 2.0 * half - half, np.y * 2.0 * half - half)
	return out


## 投げる向き：投げられる人（slot）を除いて、ボスからいちばん遠い人のほう。同じ距離（0.01m 以内）なら、枠の名前の順で先の人。
## だれもいない・ボスと同じ所にいるときは、ボスの正面
func throw_dir(slot: String) -> Vector2:
	var bp := Vector2(b.boss.position.x, b.boss.position.z)
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
	return Attacks.fwd_of(b.boss.rotation.y)


## つかんでいる最中の、ボスの動きに渡す状態（つかんでいなければ {}）
func _grab_anim_state() -> Dictionary:
	if b.grab_state.is_empty():
		return {}
	var k: Dictionary = b.attacks_cfg["kinds"]["grab"]
	return {"phase": str(b.grab_state.get("phase", "hold")), "t": float(b.grab_state["t"]), "throw_t": float(b.grab_state.get("throw_t", 0.0)),
		"throw_sec": float(k["throw_sec"]), "release_sec": float(k["release_sec"])}


## つかみの手を向ける角度（ボスの正面から、ねらう場所までの角度。ラジアン）
func _grab_aim_yaw() -> float:
	if str(b.current_attack.get("kind", "")) != Attacks.GRAB:
		return 0.0
	for h in b.current_hazards:
		if bool(h.get("grab", false)):
			var d := Vector2(float(h["x"]) - b.boss.position.x, float(h["z"]) - b.boss.position.z)
			if d.length() > 0.3:
				return clampf(wrapf(atan2(d.x, d.y) - b.motion.yaw, -PI, PI), -0.9, 0.9)
	return 0.0
