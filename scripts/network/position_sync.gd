extends RefCounted
## 箱の位置の同期の計算（手順2）。送る間隔、なめらかな移動、回数から「回/秒」を求める。通信なしで確かめられる部分だけ。

## 前に送ってから、interval_ms 以上たったら送る
static func should_send(now_ms: int, last_sent_ms: int, interval_ms: int) -> bool:
	return now_ms - last_sent_ms >= interval_ms


## 数えた回数の差を、秒あたりにする（秒が0以下なら0）
static func rate_per_sec(count_now: int, count_before: int, elapsed_sec: float) -> float:
	if elapsed_sec <= 0.0:
		return 0.0
	return float(count_now - count_before) / elapsed_sec


## なめらかに近づける割合（0〜1に収める）
static func smooth_weight(delta_sec: float, per_sec: float) -> float:
	return clampf(delta_sec * per_sec, 0.0, 1.0)


## 受け取った位置（{"p1": {"x":..,"y":..,"t":..}, ...}）を、枠 → Vector2 にする。壊れた項目は捨てる
static func parse_positions(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for slot in raw:
		var item: Variant = raw[slot]
		if item is Dictionary and item.has("x") and item.has("y") and _is_number(item["x"]) and _is_number(item["y"]):
			out[str(slot)] = Vector2(float(item["x"]), float(item["y"]))
	return out


static func _is_number(value: Variant) -> bool:
	return value is float or value is int


## 版107：受け取った位置を、時刻つきで（{"p1": {"x":..,"y":..,"t":..}}）→ {枠: {"p": Vector2, "t": 送った時刻}}。t がなければ -1
static func parse_samples(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for slot in raw:
		var item: Variant = raw[slot]
		if item is Dictionary and item.has("x") and item.has("y") and _is_number(item["x"]) and _is_number(item["y"]):
			var t: Variant = item.get("t", -1.0)
			out[str(slot)] = {"p": Vector2(float(item["x"]), float(item["y"])), "t": float(t) if _is_number(t) else -1.0}
	return out
