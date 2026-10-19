extends RefCounted
## AIの味方。画面を持たない計算だけ（テストしやすい）。
## 動き：①ボスの攻撃の予告（赤い輪・帯）の中にいたら、外へ逃げる ②そうでなければ、ボスの近く（キャラの攻撃の届く距離の内側）へ行って、こうげきする。
## 位置は世界の座標 (x, z)。ボスの当たり場所（hazards）は boss_attacks.gd と同じ形。

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const Damage := preload("res://scripts/combat/damage.gd")


static func load_config(path: String = "res://data/ai_allies.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## def：キャラの定義（characters.json の1件）。index：0〜2（立つ位置の角度を決める）
static func make(def: Dictionary, index: int, spawn: Vector2) -> Dictionary:
	var st: Dictionary = def.get("stats", {})
	return {
		"id": str(def.get("id", "")), "index": index, "pos": spawn, "hp": float(st.get("hp", 100.0)), "max_hp": float(st.get("hp", 100.0)),
		"downed": false, "cd": 0.5, "hits": 0.0, "air": 0.0, "stun": 0.0, "flash": 0.0, "stats": st.duplicate(), "face": Vector2(0, -1),
		"decided": {}, "think": 0.0, "evade": Vector2.ZERO,
	}


static func is_airborne(a: Dictionary) -> bool:
	return float(a["air"]) > 0.0


## 予告や当たりの中にいるか／近づいているか。いたら、逃げる向き（なければ ZERO）
static func evade_dir(pos: Vector2, hazards: Array, margin: float, me: String) -> Vector2:
	var best := Vector2.ZERO
	var best_depth := 0.0
	for h in hazards:
		var target := str(h["target"])
		if target != "" and target != me:
			continue
		var depth := 0.0
		var dir := Vector2.ZERO
		if str(h["shape"]) == "box":
			var hz := float(h["hz"]) + margin
			var dz := pos.y - float(h["z"])
			if absf(dz) < hz:
				depth = hz - absf(dz)
				dir = Vector2(0.0, 1.0 if dz >= 0.0 else -1.0)
		else:
			var r := float(h["r"]) + margin
			var d := pos - Vector2(float(h["x"]), float(h["z"]))
			if d.length() < r:
				depth = r - d.length()
				dir = d.normalized() if d.length() > 0.01 else Vector2(1, 0)
		if depth > best_depth:
			best_depth = depth
			best = dir
	return best


## 1コマ進める。戻り値：ボスに与えたダメージ（なければ 0）
## ctx：{boss: Vector2, boss_radius, bounds, hazards, cfg（ai_allies.json）, attack_multiplier, rng: RandomNumberGenerator, can_hit_boss: bool}
static func step(a: Dictionary, delta: float, ctx: Dictionary) -> float:
	a["flash"] = maxf(0.0, float(a["flash"]) - delta)
	a["air"] = maxf(0.0, float(a["air"]) - delta)
	a["stun"] = maxf(0.0, float(a["stun"]) - delta)
	a["cd"] = maxf(0.0, float(a["cd"]) - delta)
	if bool(a["downed"]) or float(a["stun"]) > 0.0:
		return 0.0
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var speed := float(st.get("move_speed", 6.0))
	var pos: Vector2 = a["pos"]
	var me := str(ctx.get("slot", ""))
	var hz: Array = ctx["hazards"]
	# 考える間隔（反応の遅れ）
	a["think"] = float(a["think"]) - delta
	if float(a["think"]) <= 0.0:
		a["think"] = float(cfg["reaction_sec"])
		a["evade"] = evade_dir(pos, hz, float(cfg["evade_margin"]), me)
		# ジャンプでよけられる当たりが近いとき、ときどき跳ぶ
		for h in hz:
			if bool(h["jumpable"]) and float(h["tele"]) > 0.6 and Attacks.inside(h, pos.x, pos.y) and (str(h["target"]) == "" or str(h["target"]) == me):
				if (ctx["rng"] as RandomNumberGenerator).randf() < float(cfg["jump_chance"]):
					a["air"] = float(cfg["jump_sec"])
				break
	var ev: Vector2 = a["evade"]
	var moved := Vector2.ZERO
	if ev != Vector2.ZERO:
		moved = ev * speed * float(cfg["evade_speed_factor"]) * delta
	else:
		var boss: Vector2 = ctx["boss"]
		var reach := float(st.get("attack_reach", 2.0)) + float(ctx["boss_radius"])
		var ang := deg_to_rad(float((cfg["approach_angles_deg"] as Array)[int(a["index"]) % (cfg["approach_angles_deg"] as Array).size()]))
		var stand := reach * float(cfg["stand_factor"])
		var want := boss + Vector2(sin(ang), cos(ang)) * stand
		var to := want - pos
		if to.length() > 0.3:
			moved = to.normalized() * minf(speed * delta, to.length())
		a["face"] = (boss - pos).normalized() if (boss - pos).length() > 0.01 else a["face"]
	if moved != Vector2.ZERO:
		var half := float(ctx["bounds"])
		pos = Vector2(clampf(pos.x + moved.x, -half, half), clampf(pos.y + moved.y, -half, half))
		a["pos"] = pos
		if ev == Vector2.ZERO:
			pass
	# こうげき
	var dealt := 0.0
	var boss2: Vector2 = ctx["boss"]
	var reach2 := float(st.get("attack_reach", 2.0)) + float(ctx["boss_radius"])
	if bool(ctx.get("can_hit_boss", true)) and float(a["cd"]) <= 0.0 and (boss2 - pos).length() <= reach2 and not is_airborne(a):
		dealt = Damage.damage_amount(float(st.get("attack_power", 10.0)), float(ctx["attack_multiplier"]) * float(cfg["damage_scale"]))
		a["cd"] = float(st.get("attack_cooldown_sec", 0.4))
		a["hits"] = float(a["hits"]) + dealt
	return dealt


## ボスの当たりを受ける。受けたダメージの合計を返す。done：すでに当たった印（キー → true）
static func take_hazards(a: Dictionary, slot: String, hazards: Array, done: Dictionary, multiplier: float) -> float:
	if bool(a["downed"]):
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
	if total > 0.0:
		a["hp"] = maxf(0.0, float(a["hp"]) - total)
		if float(a["hp"]) <= 0.0:
			a["downed"] = true
	return total
