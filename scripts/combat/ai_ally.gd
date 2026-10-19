extends RefCounted
## AIの味方。画面を持たない計算だけ（テストしやすい）。
## 動き：①ボスの攻撃の予告（赤い輪・帯）の中にいたら、外へ逃げる（ときどき、サブ攻撃の跳びでよける）
## ②そうでなければ、ボスの近くへ行って、プレイヤーと同じ3つの攻撃（通常・サブ・メイン）と必殺技を、player_actions.gd で使う。
## 位置は世界の座標 (x, z)。ボスの当たり場所（hazards）は boss_attacks.gd と同じ形。

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const DODGE_HEIGHT := 0.5  ## これより高く跳んでいれば、「ジャンプでよけられる」攻撃は当たらない


static func load_config(path: String = "res://data/ai_allies.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## def：キャラの定義（characters.json の1件）。index：0〜2（立つ位置の角度を決める）
static func make(def: Dictionary, index: int, spawn: Vector2) -> Dictionary:
	var st: Dictionary = def.get("stats", {})
	return {
		"id": str(def.get("id", "")), "index": index, "pos": spawn, "hp": float(st.get("hp", 100.0)), "max_hp": float(st.get("hp", 100.0)),
		"downed": false, "hits": 0.0, "height": 0.0, "stun": 0.0, "flash": 0.0, "stats": st.duplicate(), "face": Vector2(0, -1),
		"decided": {}, "think": 0.0, "think_attack": 0.0, "evade": Vector2.ZERO,
		"actions": Actions.new(), "gauge": Gauge.new(Actions.load_config()), "events": [], "banner": "", "name": str(def.get("name", "")),
	}


static func is_airborne(a: Dictionary) -> bool:
	return float(a["height"]) > DODGE_HEIGHT


## 動作中のキャラの、アニメ・向き・高さ。prototype が見た目に使う
static func act(a: Dictionary) -> Actions:
	return a["actions"]


## 予告や当たりの中にいるか／近づいているか。いたら、逃げる向き（なければ ZERO）
static func evade_dir(pos: Vector2, hazards: Array, margin: float, me: String) -> Vector2:
	var best := Vector2.ZERO
	var best_depth := 0.0
	for h in hazards:
		var target := str(h["target"])
		if target != "" and target != me:
			continue
		var e := Attacks.escape_of(h, pos.x, pos.y, margin)
		var depth := float(e["depth"])
		var dir: Vector2 = e["dir"]
		if depth > best_depth:
			best_depth = depth
			best = dir
	return best


## 1コマ進める。戻り値：ボスに与えたダメージ（なければ 0）
## ctx：{boss: Vector2, boss_radius, bounds, hazards, cfg（ai_allies.json）, attack_multiplier, rng: RandomNumberGenerator, can_hit_boss: bool, drop_damage}
## できごと：a["events"]（このコマで流すアニメ）、a["banner"]（必殺技を使った瞬間だけ、技名が入る）
static func step(a: Dictionary, delta: float, ctx: Dictionary) -> float:
	a["flash"] = maxf(0.0, float(a["flash"]) - delta)
	a["stun"] = maxf(0.0, float(a["stun"]) - delta)
	a["kb_guard"] = maxf(0.0, float(a.get("kb_guard", 0.0)) - delta)
	a["events"] = []
	a["banner"] = ""
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var actions := act(a)
	var was_busy := actions.busy()
	var dealt := 0.0
	var boss: Vector2 = ctx["boss"]
	var half := float(ctx["bounds"])
	var evs := actions.update(delta)
	if was_busy:
		var pos0: Vector2 = a["pos"]
		var dfwd := actions.frame_move.x
		if bool(actions.def(actions.active).get("stop_at_boss", false)):
			dfwd = HitArea.clip_forward(pos0, actions.aim, dfwd, boss, float(ctx["boss_radius"]) + float(actions.cfg.get("stop_margin", 0.9)))
		var p1 := pos0 + actions.aim * dfwd
		a["pos"] = Vector2(clampf(p1.x, -half, half), clampf(p1.y, -half, half))
		a["height"] = actions.height
	for ev in evs:
		match str(ev["type"]):
			"hit":
				dealt += _resolve_hit(a, ev, ctx)
			"anim":
				(a["events"] as Array).append(ev)
			"mark":
				if str(ev["name"]) == "landed":
					a["hp"] = maxf(0.0, float(a["hp"]) - float(ctx.get("drop_damage", 0.0)))
					a["flash"] = 0.15
					if float(a["hp"]) <= 0.0:
						a["downed"] = true
	if bool(a["downed"]) or bool(a.get("held", false)):
		actions.cancel()
		a["height"] = 0.0
		return _flush(a, dealt)
	if float(a["stun"]) > 0.0 or actions.busy():
		return _flush(a, dealt)
	a["height"] = 0.0
	var speed := float(st.get("move_speed", 6.0))
	var pos: Vector2 = a["pos"]
	var me := str(ctx.get("slot", ""))
	var hz: Array = ctx["hazards"]
	var rng: RandomNumberGenerator = ctx["rng"]
	# 考える間隔（反応の遅れ）
	a["think"] = float(a["think"]) - delta
	if float(a["think"]) <= 0.0:
		a["think"] = float(cfg["reaction_sec"])
		a["evade"] = evade_dir(pos, hz, float(cfg["evade_margin"]), me)
		# 「ジャンプでよけられる」当たりが近いとき、ときどき、サブ攻撃の跳びでよける
		for h in hz:
			if bool(h["jumpable"]) and float(h["tele"]) > 0.6 and Attacks.inside(h, pos.x, pos.y) and (str(h["target"]) == "" or str(h["target"]) == me):
				if rng.randf() < float(cfg["dodge_chance"]) and _start(a, "sub", ctx):
					return _flush(a, dealt)
				break
	var ev2: Vector2 = a["evade"]
	var moved := Vector2.ZERO
	if ev2 != Vector2.ZERO:
		moved = ev2 * speed * float(cfg["evade_speed_factor"]) * delta
	else:
		var reach := float(st.get("attack_reach", 2.0)) + float(ctx["boss_radius"])
		var ang := deg_to_rad(float((cfg["approach_angles_deg"] as Array)[int(a["index"]) % (cfg["approach_angles_deg"] as Array).size()]))
		var stand := reach * float(cfg["stand_factor"])
		var want := boss + Vector2(sin(ang), cos(ang)) * stand
		var to := want - pos
		if to.length() > 0.3:
			moved = to.normalized() * minf(speed * delta, to.length())
		a["face"] = (boss - pos).normalized() if (boss - pos).length() > 0.01 else a["face"]
	if moved != Vector2.ZERO:
		pos = Vector2(clampf(pos.x + moved.x, -half, half), clampf(pos.y + moved.y, -half, half))
		a["pos"] = pos
	# こうげき：届くところにいて、よけなくてよいときだけ
	var reach2 := float(st.get("attack_reach", 2.0)) + float(ctx["boss_radius"])
	if bool(ctx.get("can_hit_boss", true)) and ev2 == Vector2.ZERO and (boss - pos).length() <= reach2:
		_choose_attack(a, ctx, delta)
	return _flush(a, dealt)


## 始めた攻撃がその場で当たった分（通常攻撃）を、戻り値に足す
static func _flush(a: Dictionary, dealt: float) -> float:
	var extra := float(a.get("pending_hit", 0.0))
	a["pending_hit"] = 0.0
	return dealt + extra


## どの攻撃を使うか決める。必殺技がためてあれば必殺技、そうでなければ、ときどきメイン・サブ、あとは通常
static func _choose_attack(a: Dictionary, ctx: Dictionary, delta: float) -> void:
	var cfg: Dictionary = ctx["cfg"]
	var actions := act(a)
	var rng: RandomNumberGenerator = ctx["rng"]
	if bool(cfg.get("ai_ultimate", true)) and (a["gauge"] as Gauge).is_ready():
		if _start(a, "ultimate", ctx):
			return
	a["think_attack"] = float(a["think_attack"]) - delta
	if float(a["think_attack"]) <= 0.0:
		a["think_attack"] = float(cfg["attack_think_sec"])
		if actions.can_start("main") and rng.randf() < float(cfg["use_main_chance"]) and _start(a, "main", ctx):
			return
		if actions.can_start("sub") and rng.randf() < float(cfg["use_sub_chance"]) and _start(a, "sub", ctx):
			return
	_start(a, "normal", ctx)


## id の攻撃を、ボスに向かって始める。始められたら true
static func _start(a: Dictionary, id: String, ctx: Dictionary) -> bool:
	var actions := act(a)
	if not actions.can_start(id):
		return false
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var cooldown := float(st.get("attack_cooldown_sec", 0.4)) if id == "normal" else float(actions.def(id).get("cooldown_sec", 1.0)) * float(cfg["ai_cooldown_scale"])
	if id == "ultimate":
		if not (a["gauge"] as Gauge).consume():
			return false
		a["banner"] = str(actions.def(id).get("name", ""))
	var boss: Vector2 = ctx["boss"]
	var to := boss - (a["pos"] as Vector2)
	var aim := to if to.length() > 0.01 else (a["face"] as Vector2)
	a["face"] = aim.normalized()
	var ok := actions.start(id, aim, cooldown if id != "ultimate" else -1.0)
	if ok:
		var first := actions.update(0.0)
		for ev in first:
			if str(ev["type"]) == "hit":
				pass
			elif str(ev["type"]) == "anim":
				(a["events"] as Array).append(ev)
		# 始めてすぐ当たる攻撃（通常）は、ここで当てる
		for ev in first:
			if str(ev["type"]) == "hit":
				a["pending_hit"] = float(a.get("pending_hit", 0.0)) + _resolve_hit(a, ev, ctx)
	return ok


## 当たったか調べて、ダメージを返す（ゲージもたまる）
static func _resolve_hit(a: Dictionary, ev: Dictionary, ctx: Dictionary) -> float:
	if not bool(ctx.get("can_hit_boss", true)):
		return 0.0
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var pos: Vector2 = a["pos"]
	var reach := HitArea.reach_of(float(st.get("attack_reach", 2.0)), float(ev["radius_scale"])) + float(ctx["boss_radius"])
	if (ctx["boss"] as Vector2).distance_to(pos) > reach:
		return 0.0
	var dmg := Damage.damage_amount(float(st.get("attack_power", 10.0)), float(ctx["attack_multiplier"]) * float(ev["multiplier"]) * float(cfg["damage_scale"]))
	a["hits"] = float(a["hits"]) + dmg
	(a["gauge"] as Gauge).charge(dmg)
	return dmg


## ボスの当たりを受ける。受けたダメージの合計を返す。done：すでに当たった印（キー → true）
static func take_hazards(a: Dictionary, slot: String, hazards: Array, done: Dictionary, multiplier: float) -> float:
	if bool(a["downed"]) or bool(a.get("held", false)) or act(a).invulnerable() or float(a.get("kb_guard", 0.0)) > 0.0:
		return 0.0
	var total := 0.0
	var pos: Vector2 = a["pos"]
	for h in hazards:
		if not bool(h["active"]):
			continue
		var target := str(h["target"])
		if target != "" and target != slot:
			continue
		var key := "%s:%s:%d" % [slot, h["id"], int(h["tick"])]
		if done.has(key):
			continue
		if bool(h["jumpable"]) and is_airborne(a):
			continue
		if not Attacks.inside(h, pos.x, pos.y):
			continue
		done[key] = true
		var dmg := Damage.damage_amount(float(h["power"]), multiplier)
		total += dmg
		a["flash"] = 0.15
		if h.has("stun"):
			a["stun"] = maxf(float(a["stun"]), float(h["stun"]))
		if bool(h.get("grab", false)):
			a["held"] = true
		elif str(h.get("kb", "none")) != "none" and act(a).has_action(str(h["kb"])):
			# ふっ飛ぶ（転んで起き上がるまで、と少しの間は当たらない）
			var acts := act(a)
			var dir := Attacks.knock_dir(h, pos.x, pos.y)
			acts.start(str(h["kb"]), dir, 0.0, true)
			a["face"] = -dir
			a["kb_guard"] = float(acts.def(str(h["kb"])).get("duration_sec", 0.5)) + float(acts.cfg.get("kb_guard_sec", 0.6))
			break
	if total > 0.0:
		a["hp"] = maxf(0.0, float(a["hp"]) - total)
		if float(a["hp"]) <= 0.0:
			a["downed"] = true
	return total
