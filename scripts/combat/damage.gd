extends RefCounted
## 攻撃とダメージの計算。ダメージの計算は、この関数（damage_amount）だけで行う（CLAUDE.md ルール4）。
## 数値（攻撃力、倍率、届く距離）は data/ のJSONから渡す。


## 与えるダメージ。攻撃力に倍率をかける。0より小さくはしない
static func damage_amount(attack: float, multiplier: float) -> float:
	return maxf(0.0, attack * multiplier)


## 体力からダメージを引く。0より小さくはしない
static func apply_damage(hp: float, damage: float) -> float:
	return maxf(0.0, hp - damage)


## 攻撃する側と相手の、床の上（XZ）の距離が、届く距離以内か
static func in_reach(attacker: Vector3, target: Vector3, reach: float) -> bool:
	return Vector2(attacker.x - target.x, attacker.z - target.z).length() <= reach
