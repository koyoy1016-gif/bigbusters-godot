extends RefCounted
## ボスの歩き（位置と向き）。画面を持たない（テストしやすい）。
## - 攻撃と攻撃の間：次の攻撃でねらう人のほうへ歩き、手前（stop_dist）で止まって、その人のほうを向く
## - 攻撃が始まった瞬間に、位置と向きを固定する（予告と当たりがずれないように）。攻撃中に前へ出る分は boss_attacks.gd の step_forward
## - よろけ中は動かない
## ねらう人の位置は、それぞれの画面で見えている位置を使う（通信で送られてくる位置。少しの遅れで、画面ごとにわずかにずれることがある）
##
## 設定は data/boss_attacks.json の walk：{speed, stop_dist, turn_rate, area}

const Attacks := preload("res://scripts/combat/boss_attacks.gd")

var pos := Vector2.ZERO  ## いまの位置 (x, z)
var yaw := 0.0  ## いまの向き（0 で +Z を向く）
var speed_now := 0.0  ## いまの歩く速さ（m/秒。足の運びに使う）
var walk_dist := 0.0  ## 歩いた道のりの合計（足の運びの角度に使う）
var home := Vector2.ZERO
var locks := {}  ## 攻撃の番号 → {pos, yaw}（始まったときの位置と向き）
var _last_step := 0.0  ## 攻撃中に前へ出た分（直前のコマ）
var height := 0.0  ## 地面からの高さ（跳ぶ攻撃）
var vel := Vector2.ZERO  ## 歩く速さ（向きつき）。急に動き出したり止まったりしないよう、少しずつ変える
var path_spin := 0.0  ## 自分で動く攻撃の、体ごとの回転
var path_info := {}  ## 自分で動く攻撃の、いまの道の情報（巨大酒瓶ライドの phase・riding など。見た目に使う）


func reset(start: Vector2) -> void:
	home = start
	pos = start
	yaw = 0.0
	speed_now = 0.0
	walk_dist = 0.0
	locks = {}
	_last_step = 0.0
	height = 0.0
	vel = Vector2.ZERO
	path_spin = 0.0


## 1コマ進める。
## a：いま行われている攻撃（なければ {}）。u：その攻撃が始まってからの秒。next_a：次の攻撃（なければ {}）
## ctx：{members, positions: {枠: Vector2}}。frozen：よろけ中など、動かないとき true
func update(delta: float, a: Dictionary, u: float, next_a: Dictionary, cfg: Dictionary, ctx: Dictionary, frozen: bool = false) -> void:
	var w: Dictionary = cfg.get("walk", {})
	var before := pos
	height = 0.0
	path_spin = 0.0
	path_info = {}
	if frozen:
		speed_now = 0.0
		vel = Vector2.ZERO
		return
	if not a.is_empty():
		var n := int(a["n"])
		var kind := str(a["kind"])
		var k: Dictionary = Attacks.kind_cfg(cfg, a)
		var chase := float(k.get("chase_sec", 0.0))
		if not locks.has(n) or u < chase:
			# 攻撃の始まり（と、ねらいを合わせる間）：ねらう人のほうへ歩きながら向きを合わせ、位置と向きを決めなおす。
			# この間は、予告の範囲もボスについてくる。chase_sec を過ぎたら固定（予告と当たりがずれない）
			var face := yaw if not locks.has(n) else float(locks[n]["yaw"])
			var p0 := pos
			var tp: Variant = target_pos_of(a, ctx)
			if tp is Vector2:
				var d: Vector2 = (tp as Vector2) - pos
				if d.length() > 0.3:
					face = atan2(d.x, d.y)
				var stop := float(k.get("stop_dist", w.get("stop_dist", 4.5)))
				if locks.has(n) and d.length() > stop:
					p0 = _clamp_area(pos + d.normalized() * minf(d.length() - stop, float(w.get("speed", 4.5)) * float(w.get("chase_speed_ratio", 0.6)) * delta), w)
			if not locks.has(n):
				face = _turn(yaw, face, 30.0, delta)
			# 曲がる向き・ねらう場所も、ここで決める（回転突進・ジャンプ）
			var rng := Attacks.rng_for(float(ctx.get("round_start_ms", 0.0)), n * 17 + 3)
			var curve := rng.randf_range(float(k.get("curve_min", 0.0)), float(k.get("curve_max", 0.0))) * (1.0 if rng.randf() < 0.5 else -1.0)
			locks[n] = {"pos": p0 - Attacks.fwd_of(face) * Attacks.step_forward(kind, u, k), "yaw": face, "target": tp if tp is Vector2 else p0 + Attacks.fwd_of(face) * 6.0, "curve": curve}
		var lk: Dictionary = locks[n]
		var path := Attacks.boss_path(kind, u, k, path_ctx(lk, w, ctx, n))
		if not path.is_empty():
			# 自分で動く攻撃（回転突進・ジャンプ）：道の上を動く
			pos = path["pos"]
			# 酒瓶に乗っている間は、瓶と同じ向きにぴったり合わせる（向きがずれて、瓶からはみ出して見えないように）
			yaw = float(path["yaw"]) if bool(path.get("riding", false)) else _turn(yaw, float(path["yaw"]), 14.0, delta)
			height = float(path.get("y", 0.0))
			path_spin = float(path.get("spin", 0.0))
			path_info = path
		else:
			var step := Attacks.step_forward(kind, u, k)
			pos = _clamp_area((lk["pos"] as Vector2) + Attacks.fwd_of(float(lk["yaw"])) * step, w)
			yaw = _turn(yaw, float(lk["yaw"]), float(w.get("turn_rate", 7.0)) * 1.6, delta)
			_last_step = step
		vel = Vector2.ZERO
	else:
		# 攻撃と攻撃の間：次にねらう人のほうへ歩く。もう近ければ、その人のまわりを回りこむように歩き続ける（立ち止まらない）
		var goal := pos
		var face := yaw
		if not next_a.is_empty():
			var tp2: Variant = target_pos_of(next_a, ctx)
			if tp2 is Vector2:
				var to: Vector2 = (tp2 as Vector2) - pos
				if to.length() > 0.3:
					face = atan2(to.x, to.y)
				var nk: Dictionary = (cfg.get("kinds", {}) as Dictionary).get(str(next_a.get("kind", "")), {})
				var stop := float(nk.get("stop_dist", w.get("stop_dist", 4.5)))
				if to.length() > stop + float(w.get("circle_band", 1.0)):
					goal = pos + to.normalized() * (to.length() - stop)
				else:
					# もう近い：その人のまわりを回りこみながら、距離を stop に保つ（立ち止まらない）
					var side := Vector2(to.y, -to.x).normalized() * (1.0 if int(next_a["n"]) % 2 == 0 else -1.0)
					goal = pos + side * float(w.get("circle_step", 1.5)) + to.normalized() * (to.length() - stop)
		# 歩く：少しずつ速くなり、目標の近くでは少しずつ遅くなる（急に動き出さない・急に止まらない）
		var sp := float(w.get("speed", 4.5))
		var move := goal - pos
		var want := Vector2.ZERO
		if move.length() > 0.05:
			want = move.normalized() * sp * clampf(move.length() / float(w.get("slow_dist", 1.2)), 0.25, 1.0)
		var acc := float(w.get("accel", 9.0)) if want.length() >= vel.length() else float(w.get("decel", 12.0))
		vel = vel.move_toward(want, acc * delta)
		pos = _clamp_area(pos + vel * delta, w)
		# ステージの端へ向かって歩きつづけない（端では、その向きの速さを消す）
		var half := float(w.get("area", 13.0))
		if absf(pos.x) >= half - 0.01 and signf(vel.x) == signf(pos.x):
			vel.x = 0.0
		if absf(pos.y) >= half - 0.01 and signf(vel.y) == signf(pos.y):
			vel.y = 0.0
		yaw = _turn(yaw, face, float(w.get("turn_rate", 7.0)), delta)
	var moved := (pos - before).length()
	walk_dist += moved
	speed_now = lerpf(speed_now, moved / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))


## 自分で動く攻撃に渡す情報（始めの位置・向き・ねらう場所・曲がる向き・動ける広さ）
## （巨大酒瓶ライドは、攻撃の番号 n・戦いの開始の時刻・ステージの端 bounds も使う）
static func path_ctx(lk: Dictionary, w: Dictionary, ctx: Dictionary = {}, n: int = 0) -> Dictionary:
	return {"boss": lk["pos"], "yaw": float(lk["yaw"]), "target": lk.get("target", lk["pos"]), "curve": float(lk.get("curve", 0.0)), "area": float(w.get("area", 13.0)),
		"n": n, "round_start_ms": float(ctx.get("round_start_ms", 0.0)), "bounds": float(ctx.get("bounds", 15.0))}


## 攻撃の始めに固定した位置と向き。まだ始まっていなければ、いまの位置と向き
func lock_of(n: int) -> Dictionary:
	return locks.get(n, {"pos": pos, "yaw": yaw})


## 攻撃 a でねらう人の位置（攻撃に target があれば、その人。版68）
static func target_pos_of(a: Dictionary, ctx: Dictionary) -> Variant:
	var target := Attacks.attack_target(a, ctx.get("members", []))
	if target == "":
		return null
	return (ctx.get("positions", {}) as Dictionary).get(target, null)


## 攻撃 n でねらう人の位置（いない／わからなければ null）
static func target_pos(n: int, ctx: Dictionary) -> Variant:
	var target := Attacks.grab_target(n, ctx.get("members", []))
	if target == "":
		return null
	return (ctx.get("positions", {}) as Dictionary).get(target, null)


static func _turn(from: float, to: float, rate: float, delta: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + diff * (1.0 - exp(-rate * delta))


static func _clamp_area(p: Vector2, w: Dictionary) -> Vector2:
	var area := float(w.get("area", 12.0))
	return Vector2(clampf(p.x, -area, area), clampf(p.y, -area, area))
