extends RefCounted
## ボスの攻撃5つの「予定」と「当たり場所」を計算する（画面を持たない。テストしやすい）。
## 攻撃は、戦いが始まってからの秒（t）だけで決まる。ランダムな場所も、戦いの開始時刻から作る「種」で決まるので、
## 全員の画面で、同じ攻撃が、同じ場所に、同じときに出る（通信で攻撃を送らない）。
## 当たったかどうかは、各自の画面が、自分の分だけ調べる。
##
## 当たり場所（hazard）の形：{id, shape, x, z, ..., active（いま当たる）, tele（予告の進み 0〜1）,
## power, jumpable（ジャンプでよけられる）, target（この枠の人だけに当たる。空なら全員）, tick（継続ダメージの何回目か。-1なら一撃）, style}
## shape："circle"（x, z, r）／"box"（x, z, hx, hz。向きなし）／"sector"（扇。x, z が中心、r、yaw＝向き、half＝半分の角度）／
##        "ring"（輪。x, z, r_in〜r）／"obox"（向きのある長方形。x, z が中心、hx＝横の半分、hz＝前後の半分、yaw）
## yaw は、ボスの向き（0 で +Z を向く。前は (sin yaw, cos yaw)）
## ボスの位置と向きは、攻撃が始まったときに固定する（ctx の boss・yaw）。予告と当たりが、ずれないように

const GRAB := "grab"
const TYPHOON := "typhoon"
const FLYERS := "flyers"
const FLYER_STORM := "flyer_storm"
const HAND_SWEEP := "hand_sweep"
const BAT_H := "bat_h"
const BAT_V := "bat_v"
const BAT_SPIN := "bat_spin"
const TAIL_SPIN := "tail_spin"
const WALK_SWING := "walk_swing"
const SAKE_RAIN := "sake_rain"
const THRUST := "thrust"
const BAT_THROW := "bat_throw"
const SPIN_CHARGE := "spin_charge"
const JUMP_SLAM := "jump_slam"


## 前の向き（x, z）
static func fwd_of(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func load_config(path: String = "res://data/boss_attacks.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return apply_speed(parsed) if parsed is Dictionary else {}


## attack_speed（1.5 なら1.5倍の速さ）で、攻撃の時間（*_sec と duration）を短くし、回る速さ・飛ぶ速さを上げる。
## speed_exempt にある物（つかむ時間など）は変えない。攻撃と攻撃の間（gap_sec）も短くする
static func apply_speed(cfg: Dictionary) -> Dictionary:
	var sp := float(cfg.get("attack_speed", 1.0))
	if sp <= 0.0 or is_equal_approx(sp, 1.0):
		return cfg
	var out := cfg.duplicate(true)
	var exempt: Array = out.get("speed_exempt", [])
	out["gap_sec"] = float(out["gap_sec"]) / sp
	for kind in out["kinds"]:
		var k: Dictionary = out["kinds"][kind]
		for key in k.keys():
			var name := str(key)
			if exempt.has(name) or not (k[key] is float or k[key] is int):
				continue
			if name == "spin_deg_per_sec" or name == "speed" or name == "walk_speed":
				k[key] = float(k[key]) * sp
			elif name == "duration" or name.ends_with("_sec"):
				k[key] = float(k[key]) / sp
	return out


## t 秒のときに行われている攻撃の番号（予定表の位置）。なければ -1
static func active_index(schedule: Array, t: float) -> int:
	for i in schedule.size():
		var a: Dictionary = schedule[i]
		if t >= float(a["start"]) and t < float(a["end"]):
			return i
		if t < float(a["start"]):
			break
	return -1


## 戦いの開始時刻と攻撃の番号から作る、乱数。全員の画面で同じ値が出る
static func rng_for(round_start_ms: float, n: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fmod(round_start_ms, 1000000007.0)) + n * 7919 + 17
	return rng


## つかみの的になる人（人数でまわす）。members は枠の名前の配列（並び順は全員で同じにする）
static func grab_target(n: int, members: Array) -> String:
	if members.is_empty():
		return ""
	var sorted := members.duplicate()
	sorted.sort()
	return str(sorted[(n - 1) % sorted.size()])


## 当たり場所の一覧。a は予定表の1件、u はその攻撃が始まってからの秒。
## ctx：{boss: Vector2, members: Array, positions: {枠: Vector2}（いま見えている位置）, locked: Vector2 か null（つかみの、決まった位置）, round_start_ms, bounds}
## 攻撃 a の設定。フェイント（a の feint 秒）があれば、ためを長くして、feint_sec に入れる
static func kind_cfg(cfg: Dictionary, a: Dictionary) -> Dictionary:
	var k: Dictionary = cfg["kinds"][str(a["kind"])]
	var f := float(a.get("feint", 0.0))
	if f <= 0.0:
		return k
	var k2 := k.duplicate()
	k2["feint_sec"] = f
	k2["feint_at"] = float(k["windup_sec"])
	k2["windup_sec"] = float(k["windup_sec"]) + f
	k2["duration"] = float(k["duration"]) + f
	return k2


static func hazards(a: Dictionary, u: float, cfg: Dictionary, ctx: Dictionary) -> Array:
	var k: Dictionary = kind_cfg(cfg, a)
	var out := _hazards_raw(a, u, k, cfg, ctx)
	# ふっ飛び：当たり場所が自分で決めていなければ、攻撃の設定（knockback・kb_mode）を付ける
	for h in out:
		if not (h as Dictionary).has("kb"):
			h["kb"] = str(k.get("knockback", "kb_light"))
		if not (h as Dictionary).has("kb_mode"):
			h["kb_mode"] = str(k.get("kb_mode", "radial"))
		if not (h as Dictionary).has("kb_yaw"):
			h["kb_yaw"] = float(ctx.get("yaw", 0.0))
	return out


## ふっ飛ぶ向き（x, z）。h の kb_mode：radial（当たり場所の中心から外へ）／forward（ボスの前へ）／
## travel（動いている向き：kb_x, kb_z）／sweep（振りの進む向き＋少し外へ）
static func knock_dir(h: Dictionary, x: float, z: float) -> Vector2:
	var c := Vector2(float(h.get("x", 0.0)), float(h.get("z", 0.0)))
	var radial := Vector2(x, z) - c
	radial = radial.normalized() if radial.length() > 0.05 else fwd_of(float(h.get("kb_yaw", 0.0)))
	match str(h.get("kb_mode", "radial")):
		"forward":
			return fwd_of(float(h.get("kb_yaw", 0.0)))
		"travel":
			var d := Vector2(float(h.get("kb_x", 0.0)), float(h.get("kb_z", 0.0)))
			return d.normalized() if d.length() > 0.01 else radial
		"sweep":
			# 振りの向き：角度が増える向き（右から左）。sweep_sign が -1 なら逆
			var tangent := Vector2(radial.y, -radial.x) * float(h.get("sweep_sign", 1.0))
			return (tangent * 0.75 + radial * 0.6).normalized()
	return radial


static func _hazards_raw(a: Dictionary, u: float, k: Dictionary, cfg: Dictionary, ctx: Dictionary) -> Array:
	match str(a["kind"]):
		GRAB:
			return _grab(a, u, k, ctx)
		TYPHOON:
			return _typhoon(a, u, k, ctx)
		FLYERS:
			return _flyers(a, u, k, ctx)
		FLYER_STORM:
			return _storm(a, u, k, ctx)
		HAND_SWEEP:
			return _sweep(a, u, k, cfg, ctx)
		BAT_H:
			return _bat_h(a, u, k, ctx)
		BAT_V:
			return _bat_v(a, u, k, ctx)
		BAT_SPIN:
			return _bat_spin(a, u, k, ctx)
		TAIL_SPIN:
			return _tail_spin(a, u, k, ctx)
		WALK_SWING:
			return _walk_swing(a, u, k, ctx)
		SAKE_RAIN:
			return _sake_rain(a, u, k, ctx)
		THRUST:
			return _thrust(a, u, k, ctx)
		BAT_THROW:
			return _bat_throw(a, u, k, ctx)
		SPIN_CHARGE:
			return _spin_charge(a, u, k, ctx)
		JUMP_SLAM:
			return _jump_slam(a, u, k, ctx)
	return []


## ---- ボスが自分で動く攻撃の、位置（攻撃の始めに決めた位置・向き・ねらう場所から、時刻 u だけで決まる） ----
## 戻り値：{pos: Vector2, yaw: float, y: 高さ, spin: 体ごとの回転} か、ふつうの攻撃なら {}
static func boss_path(kind: String, u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	match kind:
		SPIN_CHARGE:
			return spin_charge_at(u, k, ctx)
		JUMP_SLAM:
			return jump_at(u, k, ctx)
	return {}


static func _area(p: Vector2, ctx: Dictionary) -> Vector2:
	var half := float(ctx.get("area", 13.0))
	return Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))


## ---- 前方突き「ケンカ突き」：両手で構えて、前へまっすぐ突く。細長い帯 ----
static func _thrust(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var w := float(k["windup_sec"])
	if u >= w + float(k["hit_sec"]):
		return []
	var yaw := float(ctx.get("yaw", 0.0))
	var f := fwd_of(yaw)
	var c := boss_at(THRUST, w, k, ctx) + f * (float(k["start"]) + float(k["length"]) * 0.5)
	return [{"id": "th%d" % int(a["n"]), "shape": "obox", "x": c.x, "z": c.y, "hx": float(k["half_width"]), "hz": float(k["length"]) * 0.5, "yaw": yaw,
		"active": u >= w, "tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"}]


## ---- バット投げ「ブン投げ」：前へ投げたバットが、回りながら飛んでいき、もどってくる（ボスが受けとる） ----
## u 秒の時点のバットの位置と、飛んでいる向き。飛んでいなければ {flying: false}
static func bat_throw_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var w := float(k["windup_sec"])
	var out_s := float(k["out_sec"])
	var back_s := float(k["back_sec"])
	var yaw := float(ctx.get("yaw", 0.0))
	var f := fwd_of(yaw)
	var start: Vector2 = (ctx["boss"] as Vector2) + f * float(k["hand_ahead"])
	var far := start + f * float(k["distance"])
	if u < w or u >= w + out_s + back_s:
		return {"flying": false}
	if u < w + out_s:
		var p := (u - w) / out_s
		var e := 1.0 - (1.0 - p) * (1.0 - p)
		return {"flying": true, "pos": start.lerp(far, e), "dir": f, "leg": 0, "spin": (u - w) * float(k["spin_rate"]) * TAU}
	var q := (u - w - out_s) / back_s
	return {"flying": true, "pos": far.lerp(start, q * q), "dir": -f, "leg": 1, "spin": (u - w) * float(k["spin_rate"]) * TAU}


static func _bat_throw(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var w := float(k["windup_sec"])
	var yaw := float(ctx.get("yaw", 0.0))
	var f := fwd_of(yaw)
	var start: Vector2 = (ctx["boss"] as Vector2) + f * float(k["hand_ahead"])
	if u < w:
		# 予告：バットが飛ぶ道（帯）
		var c := start + f * float(k["distance"]) * 0.5
		out.append({"id": "btl%d" % int(a["n"]), "shape": "obox", "x": c.x, "z": c.y, "hx": float(k["radius"]), "hz": float(k["distance"]) * 0.5 + float(k["radius"]), "yaw": yaw,
			"active": false, "tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"})
		return out
	var b := bat_throw_at(u, k, ctx)
	if bool(b["flying"]):
		var p: Vector2 = b["pos"]
		var d: Vector2 = b["dir"]
		out.append({"id": "bt%d" % int(a["n"]), "shape": "circle", "x": p.x, "z": p.y, "r": float(k["radius"]), "active": true, "tele": 1.0, "power": float(k["power"]),
			"jumpable": bool(k["jumpable"]), "target": "", "tick": int(b["leg"]), "style": "bat", "spin": float(b["spin"]), "kb_mode": "travel", "kb_x": d.x, "kb_z": d.y})
	return out


## ---- 回転突進「暴走スピン」：回りながら、曲がった道を走る（始めに道を決める。追いかけない）→ 止まって、ふらつく ----
static func spin_charge_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var w := float(k["windup_sec"])
	var run := float(k["run_sec"])
	var p0: Vector2 = ctx["boss"]
	var yaw0 := float(ctx.get("yaw", 0.0))
	var curve := float(ctx.get("curve", 0.0))
	var v := float(k["speed"])
	var t := clampf(u - w, 0.0, run)
	var h := yaw0 + curve * t
	var pos: Vector2
	if absf(curve) < 0.001:
		pos = p0 + fwd_of(yaw0) * v * t
	else:
		pos = p0 + Vector2(-cos(h) + cos(yaw0), sin(h) - sin(yaw0)) * (v / curve)
	var spin_k := smoothstep(0.0, w, u) * (1.0 - smoothstep(w + run, w + run + 0.5, u))
	var turns := float(k["spin_rate"]) * TAU
	return {"pos": _area(pos, ctx), "yaw": h, "y": 0.0, "spin": turns * (u - w * 0.5) * spin_k, "running": u >= w and u < w + run, "dir": fwd_of(h)}


static func _spin_charge(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var w := float(k["windup_sec"])
	var run := float(k["run_sec"])
	if u >= w + run:
		return []
	var st := spin_charge_at(u, k, ctx)
	var out: Array = []
	if u < w:
		# 予告：走りはじめの向きの道（先の方までは出さない＝曲がる）
		var p0: Vector2 = ctx["boss"]
		var f := fwd_of(float(ctx.get("yaw", 0.0)))
		var c := p0 + f * float(k["tele_len"]) * 0.5
		out.append({"id": "scl%d" % int(a["n"]), "shape": "obox", "x": c.x, "z": c.y, "hx": float(k["radius"]), "hz": float(k["tele_len"]) * 0.5, "yaw": float(ctx.get("yaw", 0.0)),
			"active": false, "tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"})
	var p: Vector2 = st["pos"]
	var d: Vector2 = st["dir"]
	var tick := int(floor((u - w) / float(k["tick_sec"]))) if u >= w else -1
	out.append({"id": "sc%d" % int(a["n"]), "shape": "circle", "x": p.x, "z": p.y, "r": float(k["radius"]), "active": u >= w, "tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]),
		"jumpable": bool(k["jumpable"]), "target": "", "tick": tick, "style": "zone", "kb_mode": "travel", "kb_x": d.x, "kb_z": d.y})
	return out


## ---- ジャンプ落下「ドスン落とし」：しゃがむ → 高く跳ぶ（ねらった所へ）→ 落ちる（直撃）→ 衝撃の輪が外へ広がる ----
static func jump_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var crouch := float(k["crouch_sec"])
	var air := float(k["air_sec"])
	var p0: Vector2 = ctx["boss"]
	var tgt: Vector2 = ctx.get("target", p0)
	var d := tgt - p0
	if d.length() > float(k["max_jump"]):
		d = d.normalized() * float(k["max_jump"])
	var land := _area(p0 + d, ctx)
	var p := clampf((u - crouch) / air, 0.0, 1.0)
	var y := 4.0 * float(k["height"]) * p * (1.0 - p) if u >= crouch and u < crouch + air else 0.0
	var yaw := atan2(d.x, d.y) if d.length() > 0.3 else float(ctx.get("yaw", 0.0))
	return {"pos": p0.lerp(land, smoothstep(0.0, 1.0, p)), "yaw": yaw, "y": y, "spin": 0.0, "land": land}


static func _jump_slam(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var land_t := float(k["crouch_sec"]) + float(k["air_sec"])
	var wave := float(k["wave_sec"])
	if u >= land_t + wave:
		return out
	var land: Vector2 = jump_at(u, k, ctx)["land"]
	var tele := clampf(u / land_t, 0.0, 1.0)
	if u < land_t + float(k["hit_sec"]):
		# 直撃：落ちる所の輪（ジャンプではよけられない）
		out.append({"id": "jd%d" % int(a["n"]), "shape": "circle", "x": land.x, "z": land.y, "r": float(k["radius"]), "active": u >= land_t, "tele": tele,
			"power": float(k["power"]), "jumpable": false, "target": "", "tick": -1, "style": "zone", "kb": "kb_slam", "kb_mode": "radial"})
	# 衝撃の輪：落ちたあと、外へ広がる（ジャンプでよけられる）。予告は、いちばん外まで
	var r_max := float(k["wave_radius"])
	var r_in := float(k["radius"])
	var r_out := r_max
	var active := false
	if u >= land_t:
		var p := clampf((u - land_t) / wave, 0.0, 1.0)
		r_out = lerpf(float(k["radius"]), r_max, p)
		r_in = maxf(0.0, r_out - float(k["wave_width"]))
		active = true
	out.append({"id": "jw%d" % int(a["n"]), "shape": "ring", "x": land.x, "z": land.y, "r_in": r_in, "r": r_out, "active": active, "tele": tele * 0.6,
		"power": float(k["wave_power"]), "jumpable": true, "target": "", "tick": -1, "style": "zone", "kb": "kb_heavy", "kb_mode": "radial"})
	return out


## 酒の雨：throw 回めに投げる時刻
static func sake_throw_time(throw: int, k: Dictionary) -> float:
	return float(k["first_sec"]) + float(throw) * float(k["every_sec"])


## 酒の雨：throw 回めに投げた i 粒めの、落ちる場所（ボスの前の扇の中。全員の画面で同じ）と、落ちる時刻
static func sake_spot(a: Dictionary, throw: int, i: int, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var rng := rng_for(float(ctx["round_start_ms"]), int(a["n"]) * 1000 + throw * 37 + i)
	var ang := deg_to_rad(rng.randf_range(-float(k["angle_deg"]), float(k["angle_deg"]))) + float(ctx.get("yaw", 0.0))
	var dist := rng.randf_range(float(k["min_dist"]), float(k["max_dist"]))
	var t0 := sake_throw_time(throw, k)
	var land := t0 + float(k["fall_sec"]) + float(k["fall_spread_sec"]) * float(i) / float(maxi(int(k["per_throw"]) - 1, 1))
	return {"pos": (ctx["boss"] as Vector2) + Vector2(sin(ang), cos(ang)) * dist, "throw": t0, "land": land}


## 酒の雨：ボスが一升瓶をふり上げて、酒を空へばらまく → 少しして、上から降ってくる（落ちる所に、先に輪が出る）
static func _sake_rain(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for t in int(k["throws"]):
		for i in int(k["per_throw"]):
			var sp := sake_spot(a, t, i, k, ctx)
			var t0: float = sp["throw"]
			var land: float = sp["land"]
			if u < t0 or u >= land + float(k["hit_sec"]):
				continue
			var p: Vector2 = sp["pos"]
			out.append({"id": "sk%d_%d_%d" % [int(a["n"]), t, i], "shape": "circle", "x": p.x, "z": p.y, "r": float(k["radius"]), "active": u >= land,
				"tele": clampf((u - t0) / (land - t0), 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "sake"})
	return out


## 攻撃中に、ボスが前へ出る距離（u 秒の時点）。横振り・縦振りは、振るときに一歩ふみこむ。歩きながら振るは、歩き続ける
static func step_forward(kind: String, u: float, k: Dictionary) -> float:
	match kind:
		BAT_H:
			var w := float(k["windup_sec"])
			return float(k["lunge"]) * smoothstep(w - 0.15, w + float(k["swing_sec"]), u)
		BAT_V:
			var w2 := float(k["windup_sec"])
			return float(k["lunge"]) * smoothstep(w2 - 0.2, w2, u)
		THRUST:
			# ためで少しうしろへ下がり、突くときに一気に前へ出る
			var w3 := float(k["windup_sec"])
			var back := -float(k.get("pull_back", 1.2)) * smoothstep(0.0, w3 - 0.12, u)
			return back + (float(k["lunge"]) + float(k.get("pull_back", 1.2))) * smoothstep(w3 - 0.12, w3 + float(k["hit_sec"]), u)
		WALK_SWING:
			var t0 := float(k["first_sec"]) * 0.4
			var t1 := float(k["duration"]) - 0.35
			return float(k["walk_speed"]) * clampf(u - t0, 0.0, maxf(t1 - t0, 0.0))
	return 0.0


## u 秒の時点の、ボスの位置（攻撃の始めの位置 boss と向き yaw から）
static func boss_at(kind: String, u: float, k: Dictionary, ctx: Dictionary) -> Vector2:
	return (ctx["boss"] as Vector2) + fwd_of(float(ctx.get("yaw", 0.0))) * step_forward(kind, u, k)


## 扇。k の center_deg：扇のまん中の向きを、ボスの正面から何度ずらすか（+ がボスの左）
static func _sector(id: String, c: Vector2, r: float, yaw: float, arc_deg: float, active: bool, tele: float, k: Dictionary, tick: int = -1) -> Dictionary:
	return {"id": id, "shape": "sector", "x": c.x, "z": c.y, "r": r, "yaw": yaw + deg_to_rad(float(k.get("center_deg", 0.0))), "half": deg_to_rad(arc_deg) * 0.5, "active": active,
		"tele": tele, "power": float(k.get("power", 0.0)), "jumpable": bool(k.get("jumpable", true)), "target": "", "tick": tick, "style": "zone"}


## 振りぬく扇：予告はバットが通る全体（sweep_from_deg〜sweep_to_deg）。振っている間は、バットが通りすぎた所までが当たる
## （動きとそろえる：バットがまだ来ていない所には、まだ当たらない）。p は振りの進み（0〜1）
static func _sweep_sector(id: String, c: Vector2, yaw: float, k: Dictionary, active: bool, tele: float, p: float) -> Dictionary:
	var a0 := float(k.get("sweep_from_deg", -80.0))
	var a1 := float(k.get("sweep_to_deg", 80.0))
	if active:
		a1 = a0 + (a1 - a0) * clampf(p, 0.08, 1.0)
	var h := _sector(id, c, float(k["radius"]), yaw, absf(a1 - a0), active, tele, k)
	h["yaw"] = yaw + deg_to_rad((a0 + a1) * 0.5)
	return h


## バットの横振り：予告の扇 → 右から左へ振りぬく（バットが通った所から当たる）
static func _bat_h(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var w := float(k["windup_sec"])
	var sw := float(k["swing_sec"])
	var end := w + sw
	if u >= end:
		return []
	var c := boss_at(BAT_H, end, k, ctx)
	return [_sweep_sector("bh%d" % int(a["n"]), c, float(ctx.get("yaw", 0.0)), k, u >= w, clampf(u / w, 0.0, 1.0), (u - w) / sw)]


## バットの縦振り：前へまっすぐの帯 → たたきつける
static func _bat_v(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var w := float(k["windup_sec"])
	if u >= w + maxf(float(k["hit_sec"]), float(k.get("wave_sec", 0.0))):
		return []
	var yaw := float(ctx.get("yaw", 0.0)) + deg_to_rad(float(k.get("center_deg", 0.0)))
	var f := fwd_of(yaw)
	var c := boss_at(BAT_V, w, k, ctx) + f * (float(k["start"]) + float(k["length"]) * 0.5)
	var out: Array = []
	if u < w + float(k["hit_sec"]):
		out.append({"id": "bv%d" % int(a["n"]), "shape": "obox", "x": c.x, "z": c.y, "hx": float(k["half_width"]), "hz": float(k["length"]) * 0.5, "yaw": yaw,
			"active": u >= w, "tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"})
	# 地面を伝う衝撃波：たたいた所から、さらに前へ走る（ジャンプでよけられる）。予告は、走る道
	var wave_from := float(k["start"]) + float(k["length"])
	var wl := float(k["wave_len"])
	var root := boss_at(BAT_V, w, k, ctx)
	if u < w:
		var cw := root + f * (wave_from + wl * 0.5)
		out.append({"id": "bvwl%d" % int(a["n"]), "shape": "obox", "x": cw.x, "z": cw.y, "hx": float(k["wave_half_width"]), "hz": wl * 0.5, "yaw": yaw,
			"active": false, "tele": clampf(u / w, 0.0, 1.0) * 0.5, "power": 0.0, "jumpable": true, "target": "", "tick": -1, "style": "zone"})
	elif u < w + float(k["wave_sec"]):
		var p := (u - w) / float(k["wave_sec"])
		var seg := float(k["wave_seg"])
		var cw2 := root + f * (wave_from + (wl - seg) * p + seg * 0.5)
		out.append({"id": "bvw%d" % int(a["n"]), "shape": "obox", "x": cw2.x, "z": cw2.y, "hx": float(k["wave_half_width"]), "hz": seg * 0.5, "yaw": yaw,
			"active": true, "tele": 1.0, "power": float(k["wave_power"]), "jumpable": true, "target": "", "tick": -1, "style": "zone", "kb": "kb_light", "kb_mode": "forward", "part": "wave"})
	return out


## バットの回転斬り：まわりの輪。回っている間は、tick_sec ごとにダメージ
static func _bat_spin(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var wind := float(k["windup_sec"])
	var end_active := float(k["duration"]) - float(k["recover_sec"]) - float(k.get("finish_sec", 0.0))
	if u >= end_active:
		return []
	var boss: Vector2 = ctx["boss"]
	var active := u >= wind
	var tick := int(floor((u - wind) / float(k["tick_sec"]))) if active else -1
	return [{"id": "bs%d" % int(a["n"]), "shape": "circle", "x": boss.x, "z": boss.y, "r": float(k["radius"]), "active": active,
		"tele": clampf(u / wind, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": tick, "style": "zone"}]


## しっぽ回し：体のまわりの輪（すぐそばは安全）。しっぽが1回まわる間だけ当たる
static func _tail_spin(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var w := float(k["windup_sec"])
	if u >= w + float(k["sweep_sec"]):
		return []
	var boss: Vector2 = ctx["boss"]
	return [{"id": "ts%d" % int(a["n"]), "shape": "ring", "x": boss.x, "z": boss.y, "r_in": float(k["r_in"]), "r": float(k["radius"]), "active": u >= w,
		"tele": clampf(u / w, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"}]


## 歩きながら振る：i 回めに振る時刻
static func swing_time(i: int, k: Dictionary) -> float:
	return float(k["first_sec"]) + float(i) * float(k["every_sec"])


static func _walk_swing(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var yaw := float(ctx.get("yaw", 0.0))
	for i in int(k["swings"]):
		var hit_t := swing_time(i, k)
		var from := hit_t - float(k["tele_sec"])
		if u < from or u >= hit_t + float(k["hit_sec"]):
			continue
		var c := boss_at(WALK_SWING, hit_t, k, ctx)
		out.append(_sweep_sector("ws%d_%d" % [int(a["n"]), i], c, yaw, k, u >= hit_t, clampf((u - from) / float(k["tele_sec"]), 0.0, 1.0), (u - hit_t) / float(k["hit_sec"])))
	return out


static func _grab(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var target := grab_target(int(a["n"]), ctx["members"])
	if target == "":
		return []
	var follow := float(k["follow_sec"])
	var lock := float(k["lock_sec"])
	var hit_from := follow + lock
	var hit_to := hit_from + float(k["hit_sec"])
	if u >= hit_to:
		return []
	var pos: Vector2 = ctx["positions"].get(target, (ctx["boss"] as Vector2) + fwd_of(float(ctx.get("yaw", 0.0))) * 6.0)
	if u >= follow and ctx.get("locked") is Vector2:
		pos = ctx["locked"]
	# ボスの手が届く所まで（それより遠くの人は、つかめない）
	var bp: Vector2 = ctx["boss"]
	var reach := float(k.get("reach", 99.0))
	if (pos - bp).length() > reach:
		pos = bp + (pos - bp).normalized() * reach
	var active := u >= hit_from
	return [{"id": "gr%d" % int(a["n"]), "shape": "circle", "x": pos.x, "z": pos.y, "r": float(k["hit_radius"]), "active": active,
		"tele": clampf(u / hit_from, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": target, "tick": -1, "style": "zone", "stun": float(k["stun_sec"]), "grab": true}]


static func _typhoon(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var wind := float(k["windup_sec"])
	var end_active := float(k["duration"]) - float(k["recover_sec"])
	var boss: Vector2 = ctx["boss"]
	var active := u >= wind and u < end_active
	var tick := int(floor((u - wind) / float(k["tick_sec"]))) if active else -1
	return [{"id": "ty%d" % int(a["n"]), "shape": "circle", "x": boss.x, "z": boss.y, "r": float(k["radius"]), "active": active,
		"tele": clampf(u / wind, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": tick, "style": "zone"}]


## チラシ：ボスから、前のほうへ、いろいろな向きに飛ぶ
static func flyer_state(a: Dictionary, i: int, u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var rng := rng_for(float(ctx["round_start_ms"]), int(a["n"]) * 100 + i)
	var count := int(k["count"])
	var s := float(k["start_sec"]) + float(k["spread_sec"]) * float(i) / float(maxi(count - 1, 1))
	var ang := deg_to_rad(rng.randf_range(-float(k["angle_deg"]), float(k["angle_deg"])))
	var yaw := float(ctx.get("yaw", 0.0))
	var dir := Vector2(sin(ang + yaw), cos(ang + yaw))
	var age := u - s
	var alive := age >= 0.0 and age < float(k["life_sec"])
	var boss: Vector2 = ctx["boss"]
	var pos := boss + dir * (float(k["speed"]) * maxf(age, 0.0) + 1.5)
	return {"alive": alive, "pos": pos, "age": age, "dir": dir}


static func _flyers(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	# 予告：チラシが飛ぶ扇を、投げ始める前から、投げ終わるまで出しておく（この扇そのものは当たらない）
	var last := float(k["start_sec"]) + float(k["spread_sec"])
	if u < last:
		var reach := float(k["speed"]) * float(k["life_sec"]) + 1.5
		var fan := _sector("ft%d" % int(a["n"]), ctx["boss"], reach, float(ctx.get("yaw", 0.0)), float(k["angle_deg"]) * 2.0, false, clampf(u / float(k["start_sec"]), 0.0, 1.0), k)
		fan["power"] = 0.0
		out.append(fan)
	for i in int(k["count"]):
		var f := flyer_state(a, i, u, k, ctx)
		if bool(f["alive"]):
			var p: Vector2 = f["pos"]
			out.append({"id": "fl%d_%d" % [int(a["n"]), i], "shape": "circle", "x": p.x, "z": p.y, "r": float(k["radius"]), "active": true, "tele": 1.0,
				"power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "paper", "age": float(f["age"])})
	return out


## 必殺技A：空から、チラシがたくさん落ちてくる（落ちる場所に、先に輪が出る）
static func storm_spot(a: Dictionary, i: int, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var rng := rng_for(float(ctx["round_start_ms"]), int(a["n"]) * 100 + i)
	var ax: Array = k["area_x"]
	var az: Array = k["area_z"]
	var s := float(k["start_sec"]) + float(k["spread_sec"]) * float(i) / float(maxi(int(k["count"]) - 1, 1))
	return {"pos": Vector2(rng.randf_range(float(ax[0]), float(ax[1])), rng.randf_range(float(az[0]), float(az[1]))), "start": s}


static func _storm(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var tele := float(k["telegraph_sec"])
	for i in int(k["count"]):
		var sp := storm_spot(a, i, k, ctx)
		var s: float = sp["start"]
		if u < s or u >= s + tele + float(k["hit_sec"]):
			continue
		var p: Vector2 = sp["pos"]
		out.append({"id": "st%d_%d" % [int(a["n"]), i], "shape": "circle", "x": p.x, "z": p.y, "r": float(k["radius"]), "active": u >= s + tele,
			"tele": clampf((u - s) / tele, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "sake"})
	return out


## 必殺技B：手が、画面の端から端まで3回、走りぬける（予告の帯が先に出る）。1回めは左から右、2回めは右から左…
static func sweep_pass(p: int, u: float, k: Dictionary) -> Dictionary:
	var tele := float(k["telegraph_sec"])
	var pass_sec := float(k["pass_sec"])
	var start := float(p) * (tele + pass_sec + float(k["gap_sec"]))
	var f := (u - start - tele) / pass_sec
	return {"start": start, "tele_p": clampf((u - start) / tele, 0.0, 1.0), "moving": f >= 0.0 and f <= 1.0, "f": clampf(f, 0.0, 1.0), "visible": u >= start and f <= 1.0}


static func _sweep(a: Dictionary, u: float, k: Dictionary, cfg: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var half := float(ctx["bounds"])
	var zs: Array = k["z_list"]
	for p in int(k["passes"]):
		var sp := sweep_pass(p, u, k)
		if not bool(sp["visible"]):
			continue
		var z := float(zs[p % zs.size()])
		var dir := 1.0 if p % 2 == 0 else -1.0
		var hand_x := (-half - 2.0 + (2.0 * half + 4.0) * float(sp["f"])) * dir
		out.append({"id": "sw%d_%d" % [int(a["n"]), p], "shape": "box", "x": hand_x, "z": z, "hx": float(k["hand_half_x"]), "hz": float(k["half_width"]),
			"active": bool(sp["moving"]), "tele": float(sp["tele_p"]), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "hand",
			"band_z": z, "band_half": half, "dir": dir})
	return out


## 点（x, z）が当たり場所の中にいるか
static func inside(h: Dictionary, x: float, z: float) -> bool:
	var d := Vector2(x - float(h["x"]), z - float(h["z"]))
	match str(h["shape"]):
		"box":
			return absf(d.x) <= float(h["hx"]) and absf(d.y) <= float(h["hz"])
		"obox":
			var l := local_of(d, float(h["yaw"]))
			return absf(l.x) <= float(h["hx"]) and absf(l.y) <= float(h["hz"])
		"sector":
			if d.length() > float(h["r"]):
				return false
			if d.length() < 0.6:
				return true
			var f := fwd_of(float(h["yaw"]))
			return absf(f.angle_to(d)) <= float(h["half"])
		"ring":
			return d.length() <= float(h["r"]) and d.length() >= float(h["r_in"])
	return d.length() <= float(h["r"])


## d（世界の向きの差）を、向き yaw から見た座標にする（x：右/左、y：前）
static func local_of(d: Vector2, yaw: float) -> Vector2:
	var f := fwd_of(yaw)
	var r := Vector2(f.y, -f.x)
	return Vector2(d.dot(r), d.dot(f))


## つかむ時間（hold_min_sec〜hold_max_sec。攻撃の番号から決まるので、全員の画面で同じ）
static func grab_hold_sec(cfg: Dictionary, round_start_ms: float, n: int) -> float:
	var k: Dictionary = cfg["kinds"][GRAB]
	var rng := rng_for(round_start_ms, n * 31 + 5)
	return rng.randf_range(float(k["hold_min_sec"]), float(k["hold_max_sec"]))


## 当たり場所から外へ逃げる向きと、どれだけ中にいるか（AIのよけ方が使う）。中にいなければ depth は 0 以下
static func escape_of(h: Dictionary, x: float, z: float, margin: float) -> Dictionary:
	var d := Vector2(x - float(h["x"]), z - float(h["z"]))
	var dl := d.length()
	var radial := d / dl if dl > 0.01 else Vector2(1, 0)
	match str(h["shape"]):
		"box":
			var hz := float(h["hz"]) + margin
			return {"depth": hz - absf(d.y) if absf(d.x) <= float(h["hx"]) + margin else -1.0, "dir": Vector2(0.0, 1.0 if d.y >= 0.0 else -1.0)}
		"obox":
			var l := local_of(d, float(h["yaw"]))
			var hx := float(h["hx"]) + margin
			if absf(l.x) > hx or absf(l.y) > float(h["hz"]) + margin:
				return {"depth": -1.0, "dir": Vector2.ZERO}
			var f := fwd_of(float(h["yaw"]))
			var side := Vector2(f.y, -f.x) * (1.0 if l.x >= 0.0 else -1.0)
			return {"depth": hx - absf(l.x), "dir": side}
		"sector":
			var r := float(h["r"]) + margin
			if dl > r:
				return {"depth": -1.0, "dir": Vector2.ZERO}
			var f2 := fwd_of(float(h["yaw"]))
			var ang := absf(f2.angle_to(d)) if dl > 0.01 else 0.0
			if dl > 0.6 and ang > float(h["half"]) + margin / maxf(dl, 1.0):
				return {"depth": -1.0, "dir": Vector2.ZERO}
			# うしろへ回りこむか、外へ出るか、近いほう
			var out_d := r - dl
			var around := (float(h["half"]) - ang) * maxf(dl, 1.0) + margin
			if around < out_d:
				var s2 := Vector2(f2.y, -f2.x)
				return {"depth": around, "dir": (s2 * (1.0 if d.dot(s2) >= 0.0 else -1.0) - f2 * 0.3).normalized()}
			return {"depth": out_d, "dir": radial}
		"ring":
			var ro := float(h["r"]) + margin
			var ri := float(h["r_in"]) - margin
			if dl > ro or dl < ri:
				return {"depth": -1.0, "dir": Vector2.ZERO}
			if dl - ri < ro - dl:
				return {"depth": dl - ri, "dir": -radial}
			return {"depth": ro - dl, "dir": radial}
	var rc := float(h["r"]) + margin
	return {"depth": rc - dl, "dir": radial}
