extends RefCounted
## 版79：飛ぶ攻撃（銃弾・魔法の玉・爆弾・矢など）の動きと当たり（画面を持たない）。
## 当たる時に、はじめてダメージを出す（見た目・速さ・当たり・ダメージをそろえる）。ダメージの量は撃った時に damage.gd で決めて持たせる。
## mode：
##   straight：撃った時に、ねらう敵の中心へ向けて、まっすぐ飛ぶ（銃弾。照準の補正は撃つ時だけ）
##   homing  ：ゆるく追いかける（魔法。1秒に turn_deg 度まで曲がる）
##   arc     ：放物線で、ねらった所に落ちる（爆弾・プレゼント・花火）。落ちた所で blast（半径）の中の敵に当たる
## 敵は「床に立つ円柱」（中心 x・z、半径 r、高さ h）として調べる。

## spec：{mode, speed, radius（弾の大きさ）, range（届く長さ）, turn_deg, arc（放物線の高さ）, blast（爆発の半径）, life}
static func make(spec: Dictionary, from: Vector3, target: Vector3, owner: String, dmg: float, action: String) -> Dictionary:
	var mode := str(spec.get("mode", "straight"))
	var speed := float(spec.get("speed", 30.0))
	var dir := target - from
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	var p := {"mode": mode, "pos": from, "prev": from, "from": from, "vel": dir.normalized() * speed, "speed": speed, "t": 0.0,
		"owner": owner, "dmg": dmg, "action": action, "spec": spec, "traveled": 0.0, "done": false}
	if mode == "arc":
		var land := Vector3(target.x, float(spec.get("ground", 0.0)), target.z)
		var flat := Vector2(land.x - from.x, land.z - from.z).length()
		p["land"] = land
		p["T"] = maxf(0.15, flat / maxf(speed, 0.1))
	return p


## 1コマ進める。戻り値："" 飛んでいる、"hit" 敵に当たった、"land" 落ちた（爆発）、"miss" 外れて消えた。
## tgt：敵の円柱 {x, z, r, h, y0}（ねらう敵。いなければ {}）
static func step(p: Dictionary, delta: float, tgt: Dictionary) -> String:
	if bool(p["done"]):
		return ""
	var spec: Dictionary = p["spec"]
	p["t"] = float(p["t"]) + delta
	p["prev"] = p["pos"]
	match str(p["mode"]):
		"arc":
			var T := float(p["T"])
			var k := clampf(float(p["t"]) / T, 0.0, 1.0)
			var from: Vector3 = p["from"]
			var land: Vector3 = p["land"]
			var pos := from.lerp(land, k)
			pos.y += float(spec.get("arc", 3.0)) * 4.0 * k * (1.0 - k)
			p["vel"] = (pos - (p["prev"] as Vector3)) / maxf(delta, 0.0001)
			p["pos"] = pos
			if k >= 1.0:
				p["done"] = true
				return "land"
			return ""
		"homing":
			if not tgt.is_empty():
				var aim := Vector3(float(tgt["x"]), float(tgt.get("y0", 0.0)) + float(tgt["h"]) * float(spec.get("aim_h", 0.45)), float(tgt["z"]))
				var want := (aim - (p["pos"] as Vector3)).normalized()
				var cur := (p["vel"] as Vector3).normalized()
				var ang := cur.angle_to(want)
				var maxa := deg_to_rad(float(spec.get("turn_deg", 120.0))) * delta
				if ang > 0.0001:
					var axis := cur.cross(want)
					if axis.length() < 0.0001:
						axis = Vector3.UP
					cur = cur.rotated(axis.normalized(), minf(ang, maxa))
				p["vel"] = cur * float(p["speed"])
	var step_v := (p["vel"] as Vector3) * delta
	p["pos"] = (p["pos"] as Vector3) + step_v
	p["traveled"] = float(p["traveled"]) + step_v.length()
	if not tgt.is_empty() and segment_hits(p["prev"], p["pos"], tgt, float(spec.get("radius", 0.15))):
		p["done"] = true
		return "hit"
	if float(p["traveled"]) >= float(spec.get("range", 25.0)) or float(p["t"]) >= float(spec.get("life", 3.0)) or (p["pos"] as Vector3).y < -0.5:
		p["done"] = true
		return "miss"
	return ""


## 線 a→b が、敵の円柱（半径 r＋弾の大きさ）を通るか。高さも見る
static func segment_hits(a: Vector3, b: Vector3, tgt: Dictionary, rad: float) -> bool:
	var c := Vector2(float(tgt["x"]), float(tgt["z"]))
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var d := b2 - a2
	var k := clampf((c - a2).dot(d) / maxf(d.length_squared(), 0.000001), 0.0, 1.0)
	var q := a2 + d * k
	if q.distance_to(c) > float(tgt["r"]) + rad:
		return false
	var y := lerpf(a.y, b.y, k)
	return y >= float(tgt.get("y0", 0.0)) - rad and y <= float(tgt.get("y0", 0.0)) + float(tgt["h"]) + rad


## 爆発（落ちた所 at、半径 blast）が、敵の円柱にとどくか
static func blast_hits(at: Vector3, blast: float, tgt: Dictionary) -> bool:
	if tgt.is_empty():
		return false
	return Vector2(at.x - float(tgt["x"]), at.z - float(tgt["z"])).length() <= blast + float(tgt["r"])


## 敵の表面の、点 p にいちばん近い所（火花を出す所）
static func surface_point(p: Vector3, tgt: Dictionary) -> Vector3:
	if tgt.is_empty():
		return p  # 版109：敵がいない（見えない）時は、その場所のまま（前はここで止まっていた）
	var c := Vector2(float(tgt["x"]), float(tgt["z"]))
	var d := Vector2(p.x, p.z) - c
	if d.length() < 0.001:
		d = Vector2(0, 1)
	var s := c + d.normalized() * float(tgt["r"])
	var y := clampf(p.y, float(tgt.get("y0", 0.0)) + 0.3, float(tgt.get("y0", 0.0)) + float(tgt["h"]))
	return Vector3(s.x, y, s.y)
