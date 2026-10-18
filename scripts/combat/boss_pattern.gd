extends RefCounted
## ボスの攻撃の予定。「戦いが始まってからの秒数」だけで決まるので、全員の画面で同じ動きになる（通信で動きを送らない）。
## 攻撃：床に予告の輪が出て（telegraph 秒）、そのあと一撃。これを interval 秒ごとに繰り返す。最初の一撃は first_delay 秒のとき。


## これまでに一撃が当たった回数（t 秒の時点）
static func strike_index(t: float, first_delay: float, interval: float) -> int:
	if interval <= 0.0 or t < first_delay:
		return 0
	return int(floor((t - first_delay) / interval)) + 1


## 次の一撃の予告の進み具合（0〜1）。予告の最中でなければ -1
static func telegraph_progress(t: float, first_delay: float, interval: float, telegraph: float) -> float:
	if t < 0.0 or interval <= 0.0 or telegraph <= 0.0:
		return -1.0
	var next_strike: float = first_delay + float(strike_index(t, first_delay, interval)) * interval
	var remaining: float = next_strike - t
	if remaining > telegraph:
		return -1.0
	return clampf(1.0 - remaining / telegraph, 0.0, 1.0)


## n 回目の一撃の種類（cycle を順番に繰り返す）。n は 1 から
static func attack_kind(n: int, cycle: Array) -> String:
	if cycle.is_empty() or n < 1:
		return ""
	return str(cycle[(n - 1) % cycle.size()])


## n 回目の突進の、通り道の中心の x（lanes を順番に使う。時刻だけで決まるので、全員の画面で同じ）
static func lane_x(n: int, lanes: Array) -> float:
	if lanes.is_empty() or n < 1:
		return 0.0
	return float(lanes[(n - 1) % lanes.size()])


## 突進の通り道（帯）の中にいるか。x が中心から half_width 以内で、z が from_z〜to_z の間
static func in_lane(x: float, z: float, center_x: float, half_width: float, from_z: float, to_z: float) -> bool:
	return absf(x - center_x) <= half_width and z >= from_z and z <= to_z


## いかり付きの一撃の回数。phase_t 秒より前は、いつもの間隔。phase_t 秒からは、phase_t + 間隔2 × j 秒に一撃（j は 1 から）。
## 「秒数」だけで決まるので、全員の画面で同じになる（ボスの体力で決めると、画面ごとにずれる）
static func strike_index_phased(t: float, first_delay: float, interval: float, phase_t: float, interval2: float) -> int:
	if interval2 <= 0.0 or t < phase_t:
		return strike_index(t, first_delay, interval)
	return strike_index(phase_t, first_delay, interval) + int(floor((t - phase_t) / interval2))


## いかり付きの、予告の進み具合（0〜1）。予告の最中でなければ -1
static func telegraph_progress_phased(t: float, first_delay: float, interval: float, telegraph: float, phase_t: float, interval2: float) -> float:
	if interval2 <= 0.0 or t < 0.0 or telegraph <= 0.0:
		return telegraph_progress(t, first_delay, interval, telegraph)
	var next_strike: float
	if t < phase_t:
		next_strike = first_delay + float(strike_index(t, first_delay, interval)) * interval
		if next_strike > phase_t:
			next_strike = phase_t + interval2
	else:
		next_strike = phase_t + (floor((t - phase_t) / interval2) + 1.0) * interval2
	var remaining: float = next_strike - t
	if remaining > telegraph:
		return -1.0
	return clampf(1.0 - remaining / telegraph, 0.0, 1.0)

