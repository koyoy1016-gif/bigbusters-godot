extends RefCounted
## 版78：キャラごとの攻撃の当たりの形（画面を持たない）。プレイヤーとAIの味方の両方が、ここで調べる。
## ダメージの計算は damage.gd（CLAUDE.md ルール4）。数値は data/char_actions.json の hits の1つ（hit）。
## shape：
##   melee（書いていなければこれ）：いままでの近くの当たり。届く距離 = キャラの attack_reach × radius_scale
##   beam ：攻撃する人から、向き aim へ length の長さ、太さ half_width の帯。side で横にずらす（ダブルビームの左右）
##   blast：前へ dist 進んだ所（at_boss なら、届く範囲 max_dist の中で、ボスの場所）を中心に、半径 radius の円（爆弾・魔法の玉）
##   self ：自分のまわり、半径 radius の円（地面たたき）

const Damage := preload("res://scripts/combat/damage.gd")


static func shape_of(hit: Dictionary) -> String:
	return str(hit.get("shape", "melee"))


## 横の向き（aim を右へ90度）
static func side_vec(aim: Vector2) -> Vector2:
	return Vector2(-aim.y, aim.x)


## 当たりの中心（見た目を出す所）。床の上の (x, z)
static func center(hit: Dictionary, origin: Vector2, aim: Vector2, target: Vector2) -> Vector2:
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	var o := origin + side_vec(n) * float(hit.get("side", 0.0))
	match shape_of(hit):
		"blast":
			if bool(hit.get("at_boss", false)):
				var to := target - o
				var maxd := float(hit.get("max_dist", hit.get("dist", 6.0)))
				return o + (to.limit_length(maxd) if to.length() > 0.001 else n * float(hit.get("dist", 4.0)))
			return o + n * float(hit.get("dist", 4.0))
		"beam":
			return o + n * float(hit.get("length", 10.0)) * 0.5
	return origin


## 帯（ビーム）の、はしの2点
static func beam_ends(hit: Dictionary, origin: Vector2, aim: Vector2) -> Array:
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	var o := origin + side_vec(n) * float(hit.get("side", 0.0)) + n * float(hit.get("start", 0.3))
	return [o, o + n * float(hit.get("length", 10.0))]


## 当たるか。reach：近くの当たりの届く距離（melee のときだけ使う）。target_r：相手の大きさ
static func hits(hit: Dictionary, origin: Vector2, aim: Vector2, reach: float, target: Vector2, target_r: float) -> bool:
	match shape_of(hit):
		"beam":
			var e := beam_ends(hit, origin, aim)
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var d := b - a
			var k := clampf((target - a).dot(d) / maxf(d.length_squared(), 0.000001), 0.0, 1.0)
			return target.distance_to(a + d * k) <= float(hit.get("half_width", 0.6)) + target_r
		"blast":
			return target.distance_to(center(hit, origin, aim, target)) <= float(hit.get("radius", 2.0)) + target_r
		"self":
			return target.distance_to(origin) <= float(hit.get("radius", 3.0)) + target_r
	return target.distance_to(origin) <= reach + target_r
