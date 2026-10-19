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
const SAKE_DROP := "sake_drop"
const FIRE_FEST := "fire_fest"
const BOTTLE_RIDE := "bottle_ride"
const JUMP_MOVE := "jump_move"  ## 版61：移動ジャンプ落下


## 攻撃の長さ（秒）。巨大酒瓶ライドは道の長さで変わるので、攻撃の番号と戦いの開始の時刻から計算する（全員の画面で同じ）
static func attack_duration(kind: String, k: Dictionary, n: int, round_start_ms: float) -> float:
	if kind == BOTTLE_RIDE:
		return ride_total_for(k, {"n": n, "round_start_ms": round_start_ms})
	return float(k["duration"])


## 前の向き（x, z）
static func fwd_of(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func load_config(path: String = "res://data/boss_attacks.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var out := apply_speed(parsed)
	# 巨大酒瓶ライドの時間は、横切る回数と速さから決める（攻撃の速さ attack_speed では変えない。ride_* は _sec で終わらない名前）
	if (out["kinds"] as Dictionary).has(BOTTLE_RIDE):
		out["kinds"][BOTTLE_RIDE]["duration"] = ride_total(out["kinds"][BOTTLE_RIDE])
	return out


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
		JUMP_MOVE:
			return _jump_move(a, u, k, ctx)
		SAKE_DROP:
			return _bottle_hazards(a, u, k, ctx)
		FIRE_FEST:
			return _fire_fest(a, u, k, ctx)
		BOTTLE_RIDE:
			return _bottle_ride(a, u, k, ctx)
	return []


## ---- 巨大酒瓶ライド（必殺技。版63で作り直し）：空へ跳び上がって消え → 巨大な酒瓶にまたがって、ステージの外から反対の外まで
## passes_min〜passes_max 回（4〜6回）突っこむ。向きは8方向（左右・上下・ななめ）から毎回えらぶ（前と同じ向きは使わない）
## → 空から降りてきて、すき。走る道（ピンクの帯）は、走る前から通り抜けるまで出す。走っている間、瓶の上から酒瓶を1回に bottles_per_pass 本投げる
## 道は、戦いの開始の時刻と攻撃の番号の乱数だけで決める（全員の画面で同じ。長さも決まるので、AI が攻撃の終わりを正しく計算できる）
## 道の端：ステージ（stage_half の正方形）を出てから、さらに offscreen m ＋瓶の長さの半分。カメラの映す範囲より外（tools/shot_attack.gd で確認）

## ステージの半分の広さ
static func ride_half(k: Dictionary, ctx: Dictionary) -> float:
	return float(ctx.get("bounds", k.get("stage_half", 15.0)))


## 8方向（0〜7）→ 進む向き。0 で +x（右へ）、45度ずつ
static func ride_dir_of(i: int) -> Vector2:
	var ang := float(i) * PI * 0.25
	return Vector2(cos(ang), sin(ang))


## 点 c から向き d へ進んで、正方形（±half）の外に出るまでの長さ
static func _exit_dist(c: Vector2, d: Vector2, half: float) -> float:
	var best := 1e9
	if absf(d.x) > 0.0001:
		best = minf(best, (signf(d.x) * half - c.x) / d.x)
	if absf(d.y) > 0.0001:
		best = minf(best, (signf(d.y) * half - c.y) / d.y)
	return maxf(best, 0.0)


static func ride_plan(k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var half := ride_half(k, ctx)
	var n := int(ctx.get("n", 0))
	var rs := float(ctx.get("round_start_ms", 0.0))
	var count_rng := rng_for(rs, n * 97 + 5)
	var passes := count_rng.randi_range(int(k["passes_min"]), int(k["passes_max"]))
	var t := float(k["ride_intro"])
	var prev := -1
	var out_len := float(k["offscreen"]) + float(k["half_len"])
	for i in passes:
		var rng := rng_for(rs, n * 97 + i * 13 + 1)
		# 向き：8方向から。前と同じ向き・真逆の向きは使わない（同じ道を行き来しない）
		var di := rng.randi_range(0, 7)
		var guard := 0
		while prev >= 0 and (di == prev or di == (prev + 4) % 8) and guard < 16:
			di = (di + 1 + rng.randi_range(0, 5)) % 8
			guard += 1
		prev = di
		var d := ride_dir_of(di)
		# 道が通る点：ステージの真ん中のまわり（lane_spread m 以内）
		var c := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(k["lane_spread"])
		# ななめのときも、ステージの外へ同じだけ（x・z のどちらで見ても）出るように、道の上の長さをのばす
		var ol := out_len / maxf(absf(d.x), absf(d.y))
		var back := _exit_dist(c, -d, half) + ol
		var ahead := _exit_dist(c, d, half) + ol
		var from := c - d * back
		var to := c + d * ahead
		var speed := float(k["ride_speed"]) * rng.randf_range(float(k["speed_min"]), float(k["speed_max"]))
		var cross := (back + ahead) / speed
		# 次の道の予告は、いまの突入の終わりごろから出す（切りかえ ride_switch 秒は短いまま、予告は ride_tele 秒）
		var start := t if i > 0 else t + float(k["ride_tele"])
		var tele_from := start - float(k["ride_tele"])
		out.append({"i": i, "dir_i": di, "d": d, "from": from, "to": to, "c": c, "speed": speed, "tele_from": tele_from, "start": start, "end": start + cross,
			"bob": rng.randf_range(0.15, 0.4), "bob_hz": rng.randf_range(2.0, 3.0)})
		t = start + cross + float(k["ride_switch"])
	return out


## 巨大酒瓶ライドの全体の長さ（道が決まれば決まる）。AI の攻撃の終わりに使う
static func ride_total_for(k: Dictionary, ctx: Dictionary) -> float:
	var plan := ride_plan(k, ctx)
	var last: Dictionary = plan[plan.size() - 1]
	return float(last["end"]) + float(k["ride_switch"]) + float(k["ride_outro"]) + float(k["ride_recover"])


## いちばん長いとき（設定の確認と、道が分からないときの目安）
static func ride_total(k: Dictionary) -> float:
	var half := float(k.get("stage_half", 15.0))
	var longest := (2.0 * (half + float(k["lane_spread"])) + 2.0 * (float(k["offscreen"]) + float(k["half_len"]))) * sqrt(2.0)
	var per := longest / (float(k["ride_speed"]) * float(k["speed_min"])) + float(k["ride_switch"])
	return float(k["ride_intro"]) + float(k["ride_tele"]) + per * int(k["passes_max"]) + float(k["ride_outro"]) + float(k["ride_recover"])


## 瓶にまたがったときの高さ：瓶の中心の高さ（地面から）と、ボスの足もと（原点）の高さ。
## ボスの腰（seat_hip m：足もとからの高さ。tools/measure_seat.gd）が、瓶の上の面＋おしりの厚み（seat_butt）に来るようにする
static func ride_heights(k: Dictionary, bob: float) -> Dictionary:
	var center := float(k["ride_clear"]) + float(k["bottle_radius"]) + bob
	var boss_y := center + float(k["bottle_radius"]) + float(k["seat_butt"]) - float(k["seat_hip"])
	return {"center": center, "boss_y": boss_y}


## u 秒の時点の、ボスと酒瓶の場所。phase：intro / wait / pass / outro / recover。
## 戻り値：pos（ボスの足もとの x, z）, y（ボスの足もとの高さ）, yaw, riding, bottle（瓶の中心。乗っているとき）, throw_t（いちばん近い投げる時刻からの秒）
static func ride_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var plan := ride_plan(k, ctx)
	var p0: Vector2 = ctx["boss"]
	var intro := float(k["ride_intro"])
	if u < intro:
		var q := u / intro
		return {"phase": "intro", "pos": p0, "y": float(k["sky"]) * q * q, "yaw": float(ctx.get("yaw", 0.0)), "riding": false}
	var last: Dictionary = plan[plan.size() - 1]
	for ps in plan:
		if u < float(ps["end"]):
			var d: Vector2 = ps["d"]
			var yaw := atan2(d.x, d.y)
			var f := 0.0 if u < float(ps["start"]) else (u - float(ps["start"])) / (float(ps["end"]) - float(ps["start"]))
			var bob := 0.0
			if u >= float(ps["start"]):
				bob = absf(sin((u - float(ps["start"])) * TAU * float(ps["bob_hz"]))) * float(ps["bob"])  # はねるように上下
			var hs := ride_heights(k, bob)
			# 瓶の中心が道の上を走る。ボスは瓶の中心より seat_back m うしろに座る
			var bc: Vector2 = (ps["from"] as Vector2).lerp(ps["to"], f)
			var pos := bc - d * float(k["seat_back"])
			var tt := -1.0
			for b in ride_throws(ps, k, ctx):
				var dt := u - float(b["throw"])
				if tt < -0.99 or absf(dt) < absf(tt):
					tt = dt
			return {"phase": "wait" if u < float(ps["start"]) else "pass", "pos": pos, "y": float(hs["boss_y"]), "yaw": yaw, "riding": true, "pass": ps,
				"bottle": Vector3(bc.x, float(hs["center"]), bc.y), "throw_t": tt}
	# 終わり：ステージの外から、空を通って、ステージの中へ降りる
	var inner := float(ctx.get("area", 13.0)) - 3.0
	var ld: Vector2 = last["d"]
	var land := Vector2(clampf(ld.x * inner * 0.7, -inner, inner), clampf(ld.y * inner * 0.7, -inner, inner))
	var o0 := float(last["end"]) + float(k["ride_switch"])
	var outro := float(k["ride_outro"])
	var face := atan2(-ld.x, -ld.y)
	if u < o0 + outro:
		var q2 := clampf((u - o0) / outro, 0.0, 1.0)
		return {"phase": "outro", "pos": land, "y": float(k["sky"]) * (1.0 - q2) * (1.0 - q2), "yaw": face, "riding": false}
	return {"phase": "recover", "pos": land, "y": 0.0, "yaw": face, "riding": false, "phase_t": u - o0 - outro}


## 突入1回で投げる酒瓶（bottles_per_pass 本）：[{id, throw, land, from: Vector3, to: Vector2}]
## 投げる時刻：突入の始めから終わりまで、等しい間をあけて（版65）。落ちる所：ステージの中で、走る道から離れた所（乱数）。
## おたがい throw_min_gap m 以上はなす（予告が重なりすぎないように）
static func ride_throws(ps: Dictionary, k: Dictionary, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	var half := ride_half(k, ctx)
	var d: Vector2 = ps["d"]
	var from: Vector2 = ps["from"]
	var to: Vector2 = ps["to"]
	var c: Vector2 = ps["c"]
	var cnt := int(k["bottles_per_pass"])
	var dur := float(ps["end"]) - float(ps["start"])
	var rng := rng_for(float(ps["start"]) * 1000.0 + float(ps["dir_i"]), int(ps["i"]) * 41 + 9)
	var hs := ride_heights(k, 0.0)
	var placed: Array = []
	var perp := Vector2(-d.y, d.x)
	# 版65：投げる時刻は、突入の始めから終わりまで等しい間（ステージの外から投げた瓶も、ステージの中へ飛んでくる）
	for j in cnt:
		var f := (float(j) + 0.5) / float(cnt)
		var throw := float(ps["start"]) + f * dur
		var bc := from.lerp(to, f)
		var hand := bc - d * float(k["seat_back"]) + perp * 1.2
		var land := Vector2.ZERO
		var best_gap := -1.0
		var lim := half - 1.5
		for tries in 40:
			# 落ちる所：ステージの中のどこか。道からは必ず離す。ほかの瓶とは throw_min_gap 以上離す（足りなければ、いちばん離れた所）
			var cand := Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
			if absf((cand - c).dot(perp)) < float(k["half_width"]) + float(k["throw_radius"]) + 0.5:
				continue
			var gap := 999.0
			for q in placed:
				gap = minf(gap, (q as Vector2).distance_to(cand))
			if gap > best_gap:
				best_gap = gap
				land = cand
			if gap >= float(k["throw_min_gap"]):
				break
		if best_gap < 0.0:
			# 道のそばしかない（ふつうは起きない）：道の横へずらす
			land = c + perp * (float(k["half_width"]) + float(k["throw_radius"]) + 1.0)
		placed.append(land)
		out.append({"id": "rb%d_%d_%d" % [int(ctx.get("n", 0)), int(ps["i"]), j], "i": j, "throw": throw, "land": throw + float(k["throw_flight"]),
			"from": Vector3(hand.x, float(hs["center"]) + float(k["throw_hand_up"]), hand.y), "to": land})
	return out


static func _bottle_ride(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var c2 := ctx.duplicate()
	c2["n"] = int(a["n"])
	var half := ride_half(k, c2)
	var plan := ride_plan(k, c2)
	for ps in plan:
		var d: Vector2 = ps["d"]
		var yaw := atan2(d.x, d.y)
		var from: Vector2 = ps["from"]
		var to: Vector2 = ps["to"]
		if u >= float(ps["tele_from"]) and u < float(ps["end"]):
			# 予告：これから走る道（外から外までの帯）。走っている間も、通り抜けるまで出しておく
			var mid := (from + to) * 0.5
			out.append({"id": "rdl%d_%d" % [int(a["n"]), int(ps["i"])], "shape": "obox", "x": mid.x, "z": mid.y, "hx": float(k["half_width"]), "hz": from.distance_to(to) * 0.5, "yaw": yaw,
				"active": false, "tele": clampf((u - float(ps["tele_from"])) / float(k["ride_tele"]), 0.0, 1.0), "power": float(k["power"]), "jumpable": false, "target": "", "tick": -1,
				"style": "ride_lane", "dir": 1.0})
		if u >= float(ps["start"]) and u < float(ps["end"]):
			var st := ride_at(u, k, c2)
			var bc: Vector3 = st["bottle"]
			var inside := absf(bc.x) < half + float(k["half_len"]) and absf(bc.z) < half + float(k["half_len"])
			out.append({"id": "rd%d" % int(a["n"]), "shape": "obox", "x": bc.x, "z": bc.z, "hx": float(k["half_width"]), "hz": float(k["half_len"]), "yaw": yaw,
				"active": inside, "tele": 1.0, "power": float(k["power"]), "jumpable": false, "target": "", "tick": int(ps["i"]), "style": "ride",
				"kb_mode": "travel", "kb_x": d.x, "kb_z": d.y})
		# 投げた酒瓶：落ちる所に予告の円（オレンジ）→ 落ちたら当たる。酒だまりは残さない
		if u >= float(ps["start"]) - 0.01 and u < float(ps["end"]) + float(k["throw_flight"]) + float(k["throw_hit_sec"]):
			for b in ride_throws(ps, k, c2):
				if u < float(b["throw"]) or u >= float(b["land"]) + float(k["throw_hit_sec"]):
					continue
				var tl: Vector2 = b["to"]
				var h := {"id": str(b["id"]), "shape": "circle", "x": tl.x, "z": tl.y, "r": float(k["throw_radius"]), "active": u >= float(b["land"]),
					"tele": clampf((u - float(b["throw"])) / (float(b["land"]) - float(b["throw"])), 0.0, 1.0), "power": float(k["throw_power"]), "jumpable": false,
					"target": "", "tick": -1, "style": "bottle", "spin": (u - float(b["throw"])) * 9.0, "kb": "kb_light", "kb_mode": "radial"}
				var bp: Variant = bottle_pos(b, u, {"arc_height": float(k["throw_arc"])})
				if bp is Vector3:
					h["bottle"] = bp
				out.append(h)
	return out


## ---- 酒瓶：ボスが下から上へ放り投げ、放物線で落ちて、地面で割れる（割れた所に酒だまり） ----
## 投げる瓶の一覧：[{id, i, throw, land, from: Vector3（手の位置）, to: Vector2（落ちる所）}]。同じ攻撃なら全員の画面で同じ
## 酒瓶落とし：1本めは、ねらう人の所。ほかは、ボスの前の扇の中。火祭り：ボスの前に、つながるように並べる
static func sake_bottles(a: Dictionary, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var boss: Vector2 = ctx["boss"]
	var yaw := float(ctx.get("yaw", 0.0))
	var f := fwd_of(yaw)
	var hand := Vector3(boss.x + f.x * float(k.get("hand_ahead", 1.5)), float(k.get("hand_height", 5.0)), boss.y + f.y * float(k.get("hand_ahead", 1.5)))
	var count := int(k["bottles"])
	for i in count:
		var rng := rng_for(float(ctx["round_start_ms"]), int(a["n"]) * 1000 + i * 37 + 11)
		var t0 := float(k["first_sec"]) + float(i) * float(k["every_sec"])
		var to: Vector2
		if str(a["kind"]) == FIRE_FEST:
			# 扇の中に、となりの瓶の酒だまりとつながるくらいの間で並べる（扇の外は安全）
			var ang := deg_to_rad(lerpf(-float(k["angle_deg"]), float(k["angle_deg"]), float(i) / float(maxi(count - 1, 1))) + rng.randf_range(-6.0, 6.0))
			var dist := float(k["dist"]) + rng.randf_range(-1.2, 1.2)
			to = boss + Vector2(sin(yaw + ang), cos(yaw + ang)) * dist
		elif i == 0 and ctx.get("target") is Vector2:
			to = ctx["target"]
		else:
			var ang2 := deg_to_rad(rng.randf_range(-float(k["angle_deg"]), float(k["angle_deg"])))
			to = boss + Vector2(sin(yaw + ang2), cos(yaw + ang2)) * rng.randf_range(float(k["min_dist"]), float(k["max_dist"]))
		to = _area(to, ctx)
		out.append({"id": "b%d_%d" % [int(a["n"]), i], "i": i, "throw": t0, "land": t0 + float(k["flight_sec"]), "from": hand, "to": to})
	return out


## 瓶の、u 秒の時点の位置（空中）。飛んでいなければ null
static func bottle_pos(b: Dictionary, u: float, k: Dictionary) -> Variant:
	if u < float(b["throw"]) or u >= float(b["land"]):
		return null
	var p := (u - float(b["throw"])) / (float(b["land"]) - float(b["throw"]))
	var from: Vector3 = b["from"]
	var to: Vector2 = b["to"]
	var y := lerpf(from.y, 0.3, p) + 4.0 * float(k["arc_height"]) * p * (1.0 - p)
	return Vector3(lerpf(from.x, to.x, p), y, lerpf(from.z, to.y, p))


static func _bottle_hazards(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for b in sake_bottles(a, k, ctx):
		if u < float(b["throw"]) or u >= float(b["land"]) + float(k["hit_sec"]):
			continue
		var to: Vector2 = b["to"]
		var h := {"id": str(b["id"]), "shape": "circle", "x": to.x, "z": to.y, "r": float(k["radius"]), "active": u >= float(b["land"]),
			"tele": clampf((u - float(b["throw"])) / (float(b["land"]) - float(b["throw"])), 0.0, 1.0), "power": float(k["power"]), "jumpable": false,
			"target": "", "tick": -1, "style": "bottle", "spin": (u - float(b["throw"])) * 9.0}
		var bp: Variant = bottle_pos(b, u, k)
		if bp is Vector3:
			h["bottle"] = bp
		out.append(h)
	return out


## ---- 火祭り（必殺技）：酒瓶を並べて投げ、酒だまりを作る → ライターを投げる（落ちる所に予告）→ 火がつき、つながった酒だまりへ燃えうつる ----
## 燃えている所の当たりは fire_hazards（酒だまりの状態から作る。攻撃が終わっても、燃えている間は当たる）
static func lighter_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var t0 := float(k["lighter_throw_sec"])
	var t1 := t0 + float(k["lighter_flight_sec"])
	var boss: Vector2 = ctx["boss"]
	var tgt := lighter_target(k, ctx)
	if u < t0 or u >= t1:
		return {"flying": false, "target": tgt, "land": t1}
	var p := (u - t0) / (t1 - t0)
	var y := lerpf(5.0, 0.2, p) + 4.0 * 4.0 * p * (1.0 - p)
	return {"flying": true, "pos": Vector3(lerpf(boss.x, tgt.x, p), y, lerpf(boss.y, tgt.y, p)), "target": tgt, "land": t1}


## ライターを落とす所：ボスにいちばん近い酒瓶の所（火祭りで投げた瓶）
static func lighter_target(k: Dictionary, ctx: Dictionary) -> Vector2:
	var boss: Vector2 = ctx["boss"]
	var bs := sake_bottles({"n": int(ctx.get("n", 0)), "kind": FIRE_FEST}, k, ctx)
	var best: Vector2 = boss + fwd_of(float(ctx.get("yaw", 0.0))) * float(k["dist"])
	var bd := 1e9
	for b in bs:
		var d := (b["to"] as Vector2).distance_to(boss)
		if d < bd:
			bd = d
			best = b["to"]
	return best


static func _fire_fest(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var c2 := ctx.duplicate()
	c2["n"] = int(a["n"])
	var out := _bottle_hazards(a, u, k, c2)
	var l := lighter_at(u, k, c2)
	var t0 := float(k["lighter_throw_sec"])
	if u >= t0 and u < float(l["land"]):
		var tg: Vector2 = l["target"]
		var h := {"id": "lt%d" % int(a["n"]), "shape": "circle", "x": tg.x, "z": tg.y, "r": float(k["lighter_radius"]), "active": false,
			"tele": clampf((u - t0) / float(k["lighter_flight_sec"]), 0.0, 1.0), "power": 0.0, "jumpable": false, "target": "", "tick": -1, "style": "lighter"}
		if bool(l["flying"]):
			h["lighter"] = l["pos"]
		out.append(h)
	return out


## 燃えている酒だまりの当たり（1つの火の事件では、ダメージは1回だけ：id を事件ごとに同じにする）。
## これから燃える酒だまりには、予告（当たらない）を出す
static func fire_hazards(field: RefCounted, t: float, k: Dictionary) -> Array:
	var out: Array = []
	for p in field.burning(t):
		var pos: Vector2 = p["pos"]
		out.append({"id": "fire_" + str(p["fire"]), "shape": "circle", "x": pos.x, "z": pos.y, "r": field.radius_at(p, t), "active": true, "tele": 1.0,
			"power": float(k["fire_power"]), "jumpable": false, "target": "", "tick": -1, "style": "fire", "kb": "kb_light", "kb_mode": "radial",
			"burn": clampf((t - float(p["burn_start"])) / maxf(float(p["burn_end"]) - float(p["burn_start"]), 0.01), 0.0, 1.0)})
	for p in field.about_to_burn(t):
		var pos2: Vector2 = p["pos"]
		out.append({"id": "firew_" + str(p["id"]), "shape": "circle", "x": pos2.x, "z": pos2.y, "r": field.radius_at(p, t), "active": false,
			"tele": 0.8, "power": 0.0, "jumpable": false, "target": "", "tick": -1, "style": "zone"})
	return out


## ---- ボスが自分で動く攻撃の、位置（攻撃の始めに決めた位置・向き・ねらう場所から、時刻 u だけで決まる） ----
## 戻り値：{pos: Vector2, yaw: float, y: 高さ, spin: 体ごとの回転} か、ふつうの攻撃なら {}
static func boss_path(kind: String, u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	match kind:
		SPIN_CHARGE:
			return spin_charge_at(u, k, ctx)
		JUMP_SLAM:
			return jump_at(u, k, ctx)
		JUMP_MOVE:
			return jump_move_at(u, k, ctx)
		BOTTLE_RIDE:
			var r := ride_at(u, k, ctx)
			var out := {"pos": r["pos"], "yaw": float(r["yaw"]), "y": float(r["y"]), "spin": 0.0, "riding": bool(r["riding"]), "phase": r["phase"], "phase_t": float(r.get("phase_t", 0.0))}
			if r.has("bottle"):
				out["bottle"] = r["bottle"]
				out["throw_t"] = float(r["throw_t"])
			return out
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
		# 版65：予告は、投げる向きにまっすぐな細い線だけ（円は出さない）
		out.append({"id": "btl%d" % int(a["n"]), "shape": "obox", "x": c.x, "z": c.y, "hx": float(k.get("tele_line_half_width", 0.3)), "hz": float(k["distance"]) * 0.5 + float(k["radius"]), "yaw": yaw,
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


## ---- 移動ジャンプ落下「とびかかり」（版61）：しゃがむ → 空中を移動して（最大 max_jump m）→ はなれた所へ落ちる（直撃だけ）→ すき ----
## 着地点：ねらう人のまわりに、毎回少しずらす（land_jitter m 以内。乱数は戦いの開始の時刻と攻撃の番号から）。
## 近すぎるときは min_jump m は動く。攻撃の始め（chase_sec まで）に決めたら、もう動かさない（予告とずれない・追いかけない）
static func jump_move_land(k: Dictionary, ctx: Dictionary) -> Vector2:
	var p0: Vector2 = ctx["boss"]
	var tgt: Vector2 = ctx.get("target", p0)
	var rng := rng_for(float(ctx.get("round_start_ms", 0.0)), int(ctx.get("n", 0)) * 31 + 7)
	var ang := rng.randf() * TAU
	var jit := rng.randf_range(0.0, float(k.get("land_jitter", 2.0)))
	var d := tgt + Vector2(sin(ang), cos(ang)) * jit - p0
	var dist := d.length()
	var dir := d / dist if dist > 0.01 else fwd_of(float(ctx.get("yaw", 0.0)))
	dist = clampf(dist, float(k.get("min_jump", 4.0)), float(k["max_jump"]))
	return _area(p0 + dir * dist, ctx)


static func jump_move_at(u: float, k: Dictionary, ctx: Dictionary) -> Dictionary:
	var crouch := float(k["crouch_sec"])
	var air := float(k["air_sec"])
	var p0: Vector2 = ctx["boss"]
	var land := jump_move_land(k, ctx)
	var d := land - p0
	var p := clampf((u - crouch) / air, 0.0, 1.0)
	var y := 4.0 * float(k["height"]) * p * (1.0 - p) if u >= crouch and u < crouch + air else 0.0
	var yaw := atan2(d.x, d.y) if d.length() > 0.3 else float(ctx.get("yaw", 0.0))
	return {"pos": p0.lerp(land, smoothstep(0.0, 1.0, p)), "yaw": yaw, "y": y, "spin": 0.0, "land": land}


static func _jump_move(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var land_t := float(k["crouch_sec"]) + float(k["air_sec"])
	if u >= land_t + float(k["hit_sec"]):
		return []
	var c2 := ctx.duplicate()
	c2["n"] = int(a["n"])
	var land := jump_move_land(k, c2)
	# 直撃だけ（1回。id が1つなので、二重に当たらない）。衝撃波は出さない
	return [{"id": "jm%d" % int(a["n"]), "shape": "circle", "x": land.x, "z": land.y, "r": float(k["radius"]), "active": u >= land_t, "tele": clampf(u / land_t, 0.0, 1.0),
		"power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"}]


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
