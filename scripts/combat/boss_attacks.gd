extends RefCounted
## ボスの攻撃5つの「予定」と「当たり場所」を計算する（画面を持たない。テストしやすい）。
## 攻撃は、戦いが始まってからの秒（t）だけで決まる。ランダムな場所も、戦いの開始時刻から作る「種」で決まるので、
## 全員の画面で、同じ攻撃が、同じ場所に、同じときに出る（通信で攻撃を送らない）。
## 当たったかどうかは、各自の画面が、自分の分だけ調べる。
##
## 当たり場所（hazard）の形：{id, shape: "circle" か "box", x, z, r（circle）か hx, hz（box）, active（いま当たる）, tele（予告の進み 0〜1）,
## power, jumpable（ジャンプでよけられる）, target（この枠の人だけに当たる。空なら全員）, tick（継続ダメージの何回目か。-1なら一撃）, style}

const GRAB := "grab"
const TYPHOON := "typhoon"
const FLYERS := "flyers"
const FLYER_STORM := "flyer_storm"
const HAND_SWEEP := "hand_sweep"


static func load_config(path: String = "res://data/boss_attacks.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 攻撃の予定表。[{n, kind, start, end}]。ultimates は、決まった時刻を過ぎた最初の枠で出る
static func build_schedule(cfg: Dictionary) -> Array:
	var out: Array = []
	var t := float(cfg["first_delay_sec"])
	var total := float(cfg["schedule_total_sec"])
	var cycle: Array = cfg["cycle"]
	var ults: Array = cfg["ultimates"]
	var next_ult := float(cfg["ultimate_first_sec"])
	var ult_i := 0
	var cyc_i := 0
	var n := 0
	while t < total:
		n += 1
		var kind: String
		if t >= next_ult:
			kind = str(ults[ult_i % ults.size()])
			ult_i += 1
			next_ult += float(cfg["ultimate_interval_sec"])
		else:
			kind = str(cycle[cyc_i % cycle.size()])
			cyc_i += 1
		var dur := float((cfg["kinds"][kind] as Dictionary)["duration"])
		out.append({"n": n, "kind": kind, "start": t, "end": t + dur})
		t += dur + float(cfg["gap_sec"])
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
static func hazards(a: Dictionary, u: float, cfg: Dictionary, ctx: Dictionary) -> Array:
	var k: Dictionary = cfg["kinds"][str(a["kind"])]
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
	return []


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
	var pos: Vector2 = ctx["positions"].get(target, ctx["boss"] + Vector2(0, 6))
	if u >= follow and ctx.get("locked") is Vector2:
		pos = ctx["locked"]
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
	var dir := Vector2(sin(ang), cos(ang))
	var age := u - s
	var alive := age >= 0.0 and age < float(k["life_sec"])
	var boss: Vector2 = ctx["boss"]
	var pos := boss + dir * (float(k["speed"]) * maxf(age, 0.0) + 1.5)
	return {"alive": alive, "pos": pos, "age": age, "dir": dir}


static func _flyers(a: Dictionary, u: float, k: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
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
			"tele": clampf((u - s) / tele, 0.0, 1.0), "power": float(k["power"]), "jumpable": bool(k["jumpable"]), "target": "", "tick": -1, "style": "zone"})
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
	if str(h["shape"]) == "box":
		return absf(x - float(h["x"])) <= float(h["hx"]) and absf(z - float(h["z"])) <= float(h["hz"])
	return Vector2(x - float(h["x"]), z - float(h["z"])).length() <= float(h["r"])
