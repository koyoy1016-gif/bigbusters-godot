extends RefCounted
## ハイライトの記録。戦いの最中に、全員の位置と合計ダメージを細かく控えておき、
## 「いちばんダメージを稼いだ人の、いちばん稼いだ数秒間」を探す。画面を持たない計算だけ。

## 枠 → [[時間(秒), x, z, 合計ダメージ], ...]（時間の順）
var samples: Dictionary = {}


## ボスの記録（ハイライトで本物のボスを動かすため）。[{t, x, y, z, yaw, kind, u, awake, walk, speed, bat, feint}, ...]（時間の順）
var boss_samples: Array = []


func clear() -> void:
	samples.clear()
	boss_samples.clear()


## ボスの位置・向き・いまの攻撃（種類と進み具合 u）・覚醒か・歩いた距離・歩く速さ・バットを持っているか
func record_boss(t: float, pos: Vector3, yaw: float, kind: String, u: float, awake: bool, walk_dist: float, walk_speed: float, bat: bool, feint: float = 0.0) -> void:
	if not boss_samples.is_empty() and t < float((boss_samples[boss_samples.size() - 1] as Dictionary)["t"]):
		return
	boss_samples.append({"t": t, "x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw, "kind": kind, "u": u, "awake": awake, "walk": walk_dist, "speed": walk_speed, "bat": bat, "feint": feint})


## 区間のボスの記録（前後に1つずつ余分に入れて、区間の端でも間をつなげるようにする）
func boss_path(start: float, end: float) -> Array:
	var out: Array = []
	for i in boss_samples.size():
		var s: Dictionary = boss_samples[i]
		var t := float(s["t"])
		var next_in := i + 1 < boss_samples.size() and float((boss_samples[i + 1] as Dictionary)["t"]) >= start
		var prev_in := i > 0 and float((boss_samples[i - 1] as Dictionary)["t"]) <= end
		if (t >= start and t <= end) or (t < start and next_in) or (t > end and prev_in):
			out.append(s)
	return out


## ボスの記録の、時間 t での姿。位置・向き・歩いた距離は前後の間をつなぐ。
## 攻撃の進み（u）は、同じ攻撃の続きなら間をつなぎ、攻撃が変わる所では前の記録のまま。空なら {}
static func boss_at(track: Array, t: float) -> Dictionary:
	if track.is_empty():
		return {}
	var first: Dictionary = track[0]
	if t <= float(first["t"]):
		return first.duplicate()
	for i in range(1, track.size()):
		var b: Dictionary = track[i]
		if t <= float(b["t"]):
			var a: Dictionary = track[i - 1]
			var span := float(b["t"]) - float(a["t"])
			var w := 0.0 if span <= 0.0 else (t - float(a["t"])) / span
			var out := a.duplicate()
			out["t"] = t
			for key in ["x", "y", "z", "walk", "speed"]:
				out[key] = lerpf(float(a[key]), float(b[key]), w)
			out["yaw"] = lerp_angle(float(a["yaw"]), float(b["yaw"]), w)
			if str(a["kind"]) == str(b["kind"]) and float(b["u"]) >= float(a["u"]):
				out["u"] = lerpf(float(a["u"]), float(b["u"]), w)
			return out
	return (track[track.size() - 1] as Dictionary).duplicate()


func record(slot: String, t: float, x: float, z: float, hits: float) -> void:
	if not samples.has(slot):
		samples[slot] = []
	var list: Array = samples[slot]
	if not list.is_empty() and t < float((list[list.size() - 1] as Array)[0]):
		return
	list.append([t, x, z, hits])


## 窓（window_sec 秒）の中で、いちばん合計ダメージが増えた人と区間。なければ {}。
## 同点なら、早い区間・先の枠を選ぶ。戻り値：{slot, start, end, damage}
func best_window(window_sec: float) -> Dictionary:
	var best := {}
	var best_damage := 0.0
	var slots := samples.keys()
	slots.sort()
	for slot in slots:
		var list: Array = samples[slot]
		for i in list.size():
			var t0 := float((list[i] as Array)[0])
			var j := i
			while j + 1 < list.size() and float((list[j + 1] as Array)[0]) <= t0 + window_sec:
				j += 1
			var damage := float((list[j] as Array)[3]) - float((list[i] as Array)[3])
			if damage > best_damage + 0.0001:
				best_damage = damage
				# 窓の頭の、何も当てていない時間は切り、ダメージが増えはじめる直前から始める
				var k := i
				while k + 1 < j and is_equal_approx(float((list[k + 1] as Array)[3]), float((list[i] as Array)[3])):
					k += 1
				best = {"slot": str(slot), "start": float((list[k] as Array)[0]), "end": float((list[j] as Array)[0]), "damage": damage}
	return best


## 区間の足あと。[Vector3(時間, x, z), ...]
func path(slot: String, start: float, end: float) -> Array:
	var out: Array = []
	for s in samples.get(slot, []):
		var t := float((s as Array)[0])
		if t >= start and t <= end:
			out.append(Vector3(t, float((s as Array)[1]), float((s as Array)[2])))
	return out


## 足あとの、時間 t での位置（前後を直線でつなぐ。範囲の外は端）。空なら (0,0)
static func position_on_path(points: Array, t: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var first: Vector3 = points[0]
	if t <= first.x:
		return Vector2(first.y, first.z)
	for i in range(1, points.size()):
		var b: Vector3 = points[i]
		if t <= b.x:
			var a: Vector3 = points[i - 1]
			var span := b.x - a.x
			var w := 0.0 if span <= 0.0 else (t - a.x) / span
			return Vector2(a.y, a.z).lerp(Vector2(b.y, b.z), w)
	var last: Vector3 = points[points.size() - 1]
	return Vector2(last.y, last.z)
