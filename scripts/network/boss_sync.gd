extends RefCounted
## ボスの体力の共有の計算。
## 各自が「自分が与えた合計ダメージ」を、自分の枠（rooms/{合言葉}/hits/{枠}）に書く。
## ボスの体力は、最大 − 全員の合計 で求める。同じ値を書き合わないので、取り合いが起きない。


## 自分以外の枠の合計ダメージ。数でない値と、0以下の値は捨てる。
## members（いま部屋にいる枠）を渡したときは、抜けた人のダメージは数えない（空なら、全員分を数える）
static func others_total(hits: Variant, my_slot: String, members: Array = []) -> float:
	var total := 0.0
	if not (hits is Dictionary):
		return total
	for slot in hits:
		if str(slot) == my_slot:
			continue
		if not members.is_empty() and not members.has(str(slot)):
			continue
		var value: Variant = hits[slot]
		if (value is float or value is int) and float(value) > 0.0:
			total += float(value)
	return total


## ボスの体力。0より小さくはしない
static func boss_hp(max_hp: float, my_hits: float, others: float) -> float:
	return maxf(0.0, max_hp - my_hits - others)


## この戦い（round）に参加している、ほかの人の体力。{枠: 体力}。
## 体力の記録は {hp, round}。round が今の戦いと同じものだけ数える（前の戦いの古い記録や、戦いに出ていない人は数えない）
static func others_hp(hp_map: Variant, my_slot: String, members: Array, round_ms: float) -> Dictionary:
	var result := {}
	if not (hp_map is Dictionary):
		return result
	for slot in members:
		if str(slot) == my_slot:
			continue
		var entry: Variant = hp_map.get(str(slot), null)
		if not (entry is Dictionary):
			continue
		var value: Variant = entry.get("hp", null)
		var r: Variant = entry.get("round", null)
		if (value is float or value is int) and (r is float or r is int) and is_equal_approx(float(r), round_ms):
			result[str(slot)] = float(value)
	return result


## 全員がダウンしたか。自分の体力が0以下で、この戦いに出ているほかの全員も0以下なら true。
## この戦いの体力がまだ届いていない人（出ていない人・入ったばかりの人）は、数えない
static func all_down(my_hp: float, hp_map: Variant, my_slot: String, members: Array, round_ms: float) -> bool:
	if my_hp > 0.0:
		return false
	for slot in others_hp(hp_map, my_slot, members, round_ms):
		if float(others_hp(hp_map, my_slot, members, round_ms)[slot]) > 0.0:
			return false
	return true
