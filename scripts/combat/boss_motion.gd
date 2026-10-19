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


func reset(start: Vector2) -> void:
	home = start
	pos = start
	yaw = 0.0
	speed_now = 0.0
	walk_dist = 0.0
	locks = {}
	_last_step = 0.0


## 1コマ進める。
## a：いま行われている攻撃（なければ {}）。u：その攻撃が始まってからの秒。next_a：次の攻撃（なければ {}）
## ctx：{members, positions: {枠: Vector2}}。frozen：よろけ中など、動かないとき true
func update(delta: float, a: Dictionary, u: float, next_a: Dictionary, cfg: Dictionary, ctx: Dictionary, frozen: bool = false) -> void:
	var w: Dictionary = cfg.get("walk", {})
	var before := pos
	if frozen:
		speed_now = 0.0
		return
	if not a.is_empty():
		var n := int(a["n"])
		if not locks.has(n):
			# 攻撃の始まり：ねらう人のほうを向いて、固定する
			var face := yaw
			var tp: Variant = target_pos(n, ctx)
			if tp is Vector2 and ((tp as Vector2) - pos).length() > 0.3:
				var d: Vector2 = (tp as Vector2) - pos
				face = atan2(d.x, d.y)
			locks[n] = {"pos": pos, "yaw": face}
			_last_step = 0.0
		var lk: Dictionary = locks[n]
		var kind := str(a["kind"])
		var k: Dictionary = cfg["kinds"][kind]
		var step := Attacks.step_forward(kind, u, k)
		pos = _clamp_area((lk["pos"] as Vector2) + Attacks.fwd_of(float(lk["yaw"])) * step, w)
		yaw = _turn(yaw, float(lk["yaw"]), float(w.get("turn_rate", 7.0)) * 1.6, delta)
		_last_step = step
	else:
		# 攻撃と攻撃の間：次にねらう人のほうへ歩く
		var goal := pos
		var face := yaw
		if not next_a.is_empty():
			var tp2: Variant = target_pos(int(next_a["n"]), ctx)
			if tp2 is Vector2:
				var to: Vector2 = (tp2 as Vector2) - pos
				if to.length() > 0.3:
					face = atan2(to.x, to.y)
				var stop := float(w.get("stop_dist", 4.5))
				if to.length() > stop:
					goal = pos + to.normalized() * (to.length() - stop)
		var sp := float(w.get("speed", 3.4))
		var move := goal - pos
		if move.length() > 0.05:
			pos = _clamp_area(pos + move.normalized() * minf(move.length(), sp * delta), w)
		yaw = _turn(yaw, face, float(w.get("turn_rate", 7.0)), delta)
	var moved := (pos - before).length()
	walk_dist += moved
	speed_now = lerpf(speed_now, moved / maxf(delta, 0.0001), 1.0 - exp(-12.0 * delta))


## 攻撃の始めに固定した位置と向き。まだ始まっていなければ、いまの位置と向き
func lock_of(n: int) -> Dictionary:
	return locks.get(n, {"pos": pos, "yaw": yaw})


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
