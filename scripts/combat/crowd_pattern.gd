extends RefCounted
## サブ敵の動き。時間だけで決まる関数（状態を持たない）。
## 全員の画面で同じ位置になるので、通信で位置を送らなくてよい。

## i 番目の敵の位置（床の上の x, z）。ボスのまわりを、少しずつ違う半径・向きで回る。
static func position_at(i: int, count: int, t: float, center: Vector2, radius: float, speed: float, wobble: float) -> Vector2:
	var n := maxi(count, 1)
	var base := TAU * float(i) / float(n)
	var dir := 1.0 if i % 2 == 0 else -1.0
	var angle := base + dir * speed * t
	var r := radius + wobble * sin(t * 0.9 + float(i) * 1.7)
	return center + Vector2(cos(angle), sin(angle)) * r


## 進む向き（Y軸まわりの角度）。回る向きの接線方向
static func heading_at(i: int, count: int, t: float, speed: float) -> float:
	var n := maxi(count, 1)
	var dir := 1.0 if i % 2 == 0 else -1.0
	var angle := TAU * float(i) / float(n) + dir * speed * t
	return -angle + (PI * 0.5 if dir > 0.0 else -PI * 0.5)
