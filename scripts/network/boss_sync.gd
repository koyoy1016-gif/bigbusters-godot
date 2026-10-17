extends RefCounted
## ボスの体力の共有の計算。
## 各自が「自分が与えた合計ダメージ」を、自分の枠（rooms/{合言葉}/hits/{枠}）に書く。
## ボスの体力は、最大 − 全員の合計 で求める。同じ値を書き合わないので、取り合いが起きない。


## 自分以外の枠の合計ダメージ。数でない値と、0以下の値は捨てる
static func others_total(hits: Variant, my_slot: String) -> float:
	var total := 0.0
	if not (hits is Dictionary):
		return total
	for slot in hits:
		if str(slot) == my_slot:
			continue
		var value: Variant = hits[slot]
		if (value is float or value is int) and float(value) > 0.0:
			total += float(value)
	return total


## ボスの体力。0より小さくはしない
static func boss_hp(max_hp: float, my_hits: float, others: float) -> float:
	return maxf(0.0, max_hp - my_hits - others)
