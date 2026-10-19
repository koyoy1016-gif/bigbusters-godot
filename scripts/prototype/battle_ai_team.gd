extends RefCounted
## AIの味方のまとめと、ボスの攻撃の先読み
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
const BattleGrab := preload("res://scripts/prototype/battle_grab.gd")
const BattleHud := preload("res://scripts/prototype/battle_hud.gd")
const BattleAttackFx := preload("res://scripts/prototype/battle_attack_fx.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）
var ai_done := {}
var ai_rng := RandomNumberGenerator.new()


func _init(main: StickPrototype) -> void:
	b = main


func _ai_active() -> bool:
	if not b.ai_enabled:
		return false
	if not b.net_active:
		return true
	return (b.net_state.get("members", []) as Array).size() <= 1


func _ai_total() -> int:
	return (b.ai_cfg.get("slots", []) as Array).size()


func _ai_hits_total() -> float:
	var t := 0.0
	for slot in b.ai_hits:
		t += float(b.ai_hits[slot])
	return t


func _ai_all_down() -> bool:
	for slot in b.ai_allies:
		if not bool(b.ai_allies[slot]["downed"]):
			return false
	return true


## AIの味方を作りなおす（戦いの始まり、人数や選択が変わったとき）。いまの状況でAIが要らなければ、片づける
func _ai_reset() -> void:
	if b.ai_cfg.is_empty():
		b.ai_cfg = AiAlly.load_config()
	if b.characters_cfg.is_empty():
		b.characters_cfg = CharacterData.load_config()
	for slot in b.ai_allies.keys():
		_ai_remove_node(str(slot))
	b.ai_allies = {}
	b.ai_hits = {}
	ai_done = {}
	b.other_lift = {}
	if not _ai_active():
		return
	ai_rng.seed = int(fmod(maxf(b.round_start_ms, 1.0), 1000000007.0)) + 99
	var picks := _ai_picks_resolved()
	var slots: Array = b.ai_cfg["slots"]
	var offs: Array = b.ai_cfg["spawn_offsets"]
	var half := float(b.config["bounds"])
	for i in slots.size():
		var def := CharacterData.find(b.characters_cfg, str(picks[i]))
		if def.is_empty():
			continue
		var o: Array = offs[i % offs.size()]
		var a := AiAlly.make(def, i, Vector2(float(o[0]), float(o[1])))
		var slot := str(slots[i])
		b.ai_allies[slot] = a
		b.ai_hits[slot] = 0.0
		b.other_target[slot] = Vector2((a["pos"].x + half) / (2.0 * half), (a["pos"].y + half) / (2.0 * half))
		b.other_pos[slot] = b.other_target[slot]


## 選んだ3人（足りなければ、既定で埋める。自分のキャラは重ねても構わない）
func _ai_picks_resolved() -> Array:
	var out: Array = []
	var defaults: Array = b.ai_cfg.get("default_picks", [])
	for i in _ai_total():
		var id := str(b.ai_picks[i]) if i < b.ai_picks.size() else ""
		if CharacterData.find(b.characters_cfg, id).is_empty():
			id = str(defaults[i % defaults.size()]) if not defaults.is_empty() else ""
		out.append(id)
	return out


func _ai_remove_node(slot: String) -> void:
	b.other_target.erase(slot)
	b.other_pos.erase(slot)
	if b.others.has(slot):
		(b.others[slot] as Node).queue_free()
		b.others.erase(slot)
	b.other_views.erase(slot)


## 毎コマ：AIを、必要なら作る／片づける。戦いの最中なら動かす
func _ai_update(delta: float) -> void:
	if b.ai_cfg.is_empty():
		b.ai_cfg = AiAlly.load_config()
	var want := _ai_active()
	var have := not b.ai_allies.is_empty()
	if want != have:
		_ai_reset()
	if b.ai_allies.is_empty():
		return
	var half := float(b.config["bounds"])
	if b.round_active():
		var ctx := {"boss": Vector2(b.boss.position.x, b.boss.position.z), "boss_radius": float(b.config["boss_size"]) * 0.5, "bounds": half,
			"hazards": b.current_hazards, "cfg": b.ai_cfg, "attack_multiplier": float(b.config["attack_multiplier"]) * b.skills.dealt_mult(), "rng": ai_rng, "can_hit_boss": not b.phase.invulnerable(),
			"drop_damage": Damage.damage_amount(float(b.attacks_cfg["kinds"]["grab"]["drop_power"]), float(b.attacks_cfg["damage_multiplier"]))}
		# 版71：ボスのいまの攻撃の先読み（AIの味方が、よける・攻める時刻を決める）
		var tac: Dictionary = b.ai_cfg.get("tactics", {})
		var rt := b._round_t()
		if rt - b.ai_forecast_t >= float(tac.get("forecast_every", 0.2)) or rt < b.ai_forecast_t:
			b.ai_forecast = boss_forecast(float(tac.get("forecast_sec", 2.0)), float(tac.get("forecast_step", 0.15)))
			b.ai_forecast_t = rt
		ctx["forecast"] = b.ai_forecast
		ctx["forecast_age"] = maxf(0.0, rt - b.ai_forecast_t)
		ctx["next_attack_in"] = boss_next_attack_in()
		var dealt_total := 0.0
		for slot in b.ai_allies:
			var a: Dictionary = b.ai_allies[slot]
			ctx["slot"] = slot
			var hit_n0 := int(a.get("hit_n", 0))
			var dealt := AiAlly.step(a, delta, ctx)
			# 版69：AIの攻撃がボスに当たった回数。近くからなら、怒りに数える
			for _i in int(a.get("hit_n", 0)) - hit_n0:
				b.rage.add_hit(b._round_t(), b._dist_to_boss_surface(a["pos"]))
			_ai_show_action(str(slot), a)
			# 版78：AIの技の見た目と効果（ビーム・ドーム・回復・呼び出しなど）
			for oe in a.get("out_events", []):
				match str(oe["type"]):
					"fx":
						b.skills.action_fx(str(slot), oe["spec"], AiAlly.act(a).aim)
					"effect":
						b.skills.apply_effect(str(slot), oe["spec"], AiAlly.act(a).aim, float((a["stats"] as Dictionary).get("attack_power", 10.0)))
					"hitfx":
						var hf: Dictionary = (oe["hit"]["fx"] as Dictionary).duplicate()
						hf["hit"] = oe["hit"]
						if not hf.has("at"):
							hf["at"] = "hit"
						b.skills.action_fx(str(slot), hf, AiAlly.act(a).aim)
			for he in a.get("hit_events", []):
				b._show_damage(float(he["dmg"]), str(he["action"]), a["pos"])  # 版75：AIの一撃ずつ
			if dealt > 0.0:
				b.ai_hits[slot] = float(b.ai_hits[slot]) + dealt
				dealt_total += dealt
			# 版72：AIの必殺技の見た目（ためと、当たった瞬間の斬撃）
			var ua: Actions = AiAlly.act(a)
			var apos: Vector2 = a["pos"]
			if str(a["banner"]) != "":
				b.ult_fx_spawn("charge", Vector3(apos.x, b.ground_y, apos.y), ua.aim)
			if dealt > 0.0 and ua.active == "ultimate" and ua.def("ultimate").has("fx"):
				var at := HitArea.closest_on(a.get("ult_from", apos), apos, Vector2(b.boss.position.x, b.boss.position.z))
				b._ult_slash_fx(Vector3(at.x, b.ground_y, at.y), ua.aim, true, false)
			var was_held := bool(a.get("held", false))
			AiAlly.take_hazards(a, str(slot), b.current_hazards, ai_done, float(b.attacks_cfg["damage_multiplier"]) * b.skills.taken_mult())
			if bool(a.get("held", false)) and not was_held and b.grab_state.is_empty():
				var gp: Vector2 = a["pos"]
				b._start_hold(str(slot), gp)
			elif bool(a.get("held", false)) and not was_held:
				a["held"] = false
			var p: Vector2 = a["pos"]
			b.other_target[slot] = Vector2((p.x + half) / (2.0 * half), (p.y + half) / (2.0 * half))
		if dealt_total > 0.0:
			b._recompute_boss_hp()
	if not b.net_active:
		b._update_others(delta)
	_check_wipe_ai_only()


## AIの攻撃の見た目：流すアニメ、向き、高さ、必殺技の名前
func _ai_show_action(slot: String, a: Dictionary) -> void:
	var act: Actions = AiAlly.act(a)
	var view: Node3D = b.other_views.get(slot, null)
	if view != null:
		for ev in a["events"]:
			(view as Node).play_step(str(ev["anim"]), float(ev["speed"]), bool(ev.get("from_end", false)))
		if act.busy():
			(view as Node).face_now(act.aim)
	if not bool(a.get("held", false)):
		b.other_lift[slot] = float(a["height"])
	if str(a["banner"]) != "":
		b._show_banner(str(a["banner"]), b.role_name_of(slot), float(act.def("ultimate").get("banner_sec", 1.6)))
		b._play_sfx("ultimate")


## 自分がダウン中で、AIも全員ダウンしたら全滅
func _check_wipe_ai_only() -> void:
	if b.round_active() and b.downed:
		b._check_wipe()


## いまの攻撃を、horizon 秒先まで step 秒きざみで進めて、当たる物を集める [{dt: 何秒後（実際の秒）, h: 当たり}]。
## 攻撃の中の秒 u は speed 倍で進む（版69の怒り）。攻撃が終わる先は見ない（次の攻撃は、まだ分からない）
func boss_forecast(horizon: float, step: float) -> Array:
	var out: Array = []
	if b.current_attack.is_empty() or not b.round_active() or step <= 0.0:
		return out
	var a: Dictionary = b.current_attack
	# 重い攻撃（巨大酒瓶ライド）は先を調べない。いま見えている予告と当たりを「すぐ当たる」として渡す（AIは走ってよける）
	if ((b.ai_cfg.get("tactics", {}) as Dictionary).get("forecast_skip", []) as Array).has(str(a["kind"])):
		for h in b.current_hazards:
			if bool(h["active"]) or float(h.get("tele", 0.0)) > 0.0:
				out.append({"dt": 0.0, "h": h})
		return out
	var sp := float(a.get("speed", 1.0))
	var end_u := (float(a["end"]) - float(a["start"])) * sp
	var k := 0.0
	while k <= horizon + 0.0001:
		var u := b.current_attack_u + k * sp
		if u > end_u:
			break
		for h in Attacks.hazards(a, u, b.attacks_cfg, b._attack_ctx(a, u, true)):
			if bool(h["active"]):
				out.append({"dt": k, "h": h})
		k += step
	return out


## ボスの次の攻撃が始まるまでの秒（いまの攻撃の最中なら、終わり＋攻撃の間）。分からなければ 0
func boss_next_attack_in() -> float:
	var t := b._round_t()
	var cur: Dictionary = b.ai.current()
	if not cur.is_empty():
		return maxf(0.0, float(cur["end"]) - t + float(b.attacks_cfg.get("gap_sec", 0.6)))
	var nxt: Dictionary = b.ai.next_attack()
	if not nxt.is_empty():
		return maxf(0.0, float(nxt["start"]) - t)
	return maxf(0.0, b.ai.next_start - t)
