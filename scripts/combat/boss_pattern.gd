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
