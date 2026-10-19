extends RefCounted
## 当たりの範囲を調べる（画面を持たない）。プレイヤーの攻撃の当たりは、ここの関数だけで調べる。
## ダメージの計算は damage.gd（CLAUDE.md ルール4）。形（扇形・帯・円）は skills.gd の関数を使う。

const Damage := preload("res://scripts/combat/damage.gd")


## 攻撃が届く距離。キャラの届く距離 × 技の広さ（radius_scale）
static func reach_of(attack_reach: float, radius_scale: float) -> float:
	return attack_reach * radius_scale


## 攻撃する人（床の上の位置）から、相手（大きさ target_radius）に届くか
static func hits(attacker: Vector3, target: Vector3, reach: float, target_radius: float) -> bool:
	return Damage.in_reach(attacker, target, reach + target_radius)
