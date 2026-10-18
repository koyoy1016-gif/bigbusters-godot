extends RefCounted
## ハイライトの記録。戦いの最中に、全員の位置と合計ダメージを細かく控えておき、
## 「いちばんダメージを稼いだ人の、いちばん稼いだ数秒間」を探す。画面を持たない計算だけ。

## 枠 → [[時間(秒), x, z, 合計ダメージ], ...]（時間の順）
var samples: Dictionary = {}


func clear() -> void:
	samples.clear()


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
