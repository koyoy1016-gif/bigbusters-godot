extends RefCounted
## 当たりの範囲を調べる（画面を持たない）。プレイヤーの攻撃の当たりは、ここの関数だけで調べる。
## ダメージの計算は damage.gd（CLAUDE.md ルール4）。形（扇形・帯・円）は skills.gd の関数を使う。

const Damage := preload("res://scripts/combat/damage.gd")


## 攻撃が届く距離。キャラの届く距離 × 技の広さ（radius_scale）
static func reach_of(attack_reach: float, radius_scale: float) -> float:
	return attack_reach * radius_scale


## 攻撃する人（床の上の位置）から、相手（大きさ target_radius）に届くか
static func hits(attacker: Vector3, target: Vector3, reach: float, target_radius: float) -> bool:
	return Damage.in_reach(attacker, target, reach + target_radius)


## 版72b：駆けぬけながら斬る技。from から to へ通った道（床の上の x, z）のどこかから、相手（大きさ target_radius）に届くか
static func hits_sweep(from: Vector2, to: Vector2, target: Vector2, reach: float, target_radius: float) -> bool:
	return target.distance_to(closest_on(from, to, target)) <= reach + target_radius


## from〜to の線の上で、p にいちばん近い点
static func closest_on(from: Vector2, to: Vector2, p: Vector2) -> Vector2:
	var d := to - from
	var l2 := d.length_squared()
	if l2 < 0.000001:
		return from
	return from + d * clampf((p - from).dot(d) / l2, 0.0, 1.0)


## 前へ進む量 dfwd を、ボスの体に入りこまないよう、手前で止める。pos・boss は床の上の (x, z)。
## min_dist：ボスの中心から、これより近くには入らない。進んだあとの距離がそれより近ければ、進める分だけ進む
static func clip_forward(pos: Vector2, aim: Vector2, dfwd: float, boss: Vector2, min_dist: float) -> float:
	if dfwd <= 0.0 or aim.length() < 0.001:
		return dfwd
	var n := aim.normalized()
	var dist_now := pos.distance_to(boss)
	if dist_now <= min_dist:
		return 0.0
	if pos.distance_to(boss) - dfwd >= min_dist:
		return dfwd
	var after := pos + n * dfwd
	if after.distance_to(boss) >= min_dist:
		return dfwd
	# 少しずつ進めて、入る手前の量を探す
	var lo := 0.0
	var hi := dfwd
	for i in 12:
		var mid := (lo + hi) * 0.5
		if (pos + n * mid).distance_to(boss) >= min_dist:
			lo = mid
		else:
			hi = mid
	return lo
