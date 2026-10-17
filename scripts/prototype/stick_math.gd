extends RefCounted
## スティックとジャンプの計算（画面に依らない、テストできる形）。
## 向き：スティックを下に倒す（画面の下）＝手前（+Z、カメラ側）。上に倒す＝奥（-Z）。


## タッチの位置から、スティックの向き（長さは0〜1）を求める。
## 中心の近く（遊び dead_zone の内側）は 0。外側へ行くほど 0→1 に増える。
static func stick_vector(touch: Vector2, center: Vector2, radius: float, dead_zone: float) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var offset: Vector2 = (touch - center) / radius
	var length: float = offset.length()
	if length <= dead_zone or length <= 0.0:
		return Vector2.ZERO
	var magnitude: float = clampf((length - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	return offset / length * magnitude


## 向き（stick）に従って、X・Zだけを動かす。Yは変えない。範囲（bounds）の外へは出ない。
static func step_position(pos: Vector3, stick: Vector2, speed: float, delta: float, bounds: float) -> Vector3:
	var x: float = clampf(pos.x + stick.x * speed * delta, -bounds, bounds)
	var z: float = clampf(pos.z + stick.y * speed * delta, -bounds, bounds)
	return Vector3(x, pos.y, z)


## ジャンプの1コマ。返り値は (新しい高さ, 新しい上向きの速さ)。
## 地面（ground_y）に着いたら、高さは地面、速さは 0 になる。
static func jump_update(y: float, vy: float, delta: float, gravity: float, ground_y: float) -> Vector2:
	var new_vy: float = vy - gravity * delta
	var new_y: float = y + new_vy * delta
	if new_y <= ground_y:
		return Vector2(ground_y, 0.0)
	return Vector2(new_y, new_vy)
