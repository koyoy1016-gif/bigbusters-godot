extends RefCounted
## Xの技の計算（画面を持たない）。当たり判定の形と、ダメージ。
## ダメージの計算は damage.gd の関数を使う（CLAUDE.md ルール4）。数値は data/skills.json。

const Damage := preload("res://scripts/combat/damage.gd")
const PATH := "res://data/skills.json"


static func load_config(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 技のダメージ（攻撃力 × 技の倍率）
static func skill_damage(attack_power: float, skill: Dictionary) -> float:
	return Damage.damage_amount(attack_power, float(skill.get("multiplier", 0.0)))


## 扇形（前に向かって斬る）。origin から radius（＋相手の大きさ）以内で、向き facing から half_angle_deg 以内
static func in_arc(origin: Vector2, facing: Vector2, target: Vector2, radius: float, half_angle_deg: float, target_radius: float = 0.0) -> bool:
	var to := target - origin
	var d := to.length()
	if d > radius + target_radius:
		return false
	if d <= target_radius or facing.length() < 0.001:
		return true
	var angle := rad_to_deg(acos(clampf(facing.normalized().dot(to / d), -1.0, 1.0)))
	return angle <= half_angle_deg


## 細長い帯（まっすぐ飛ぶ・つらぬく）。origin から dir の向きに length まで、幅は half_width ずつ
static func in_strip(origin: Vector2, dir: Vector2, target: Vector2, length: float, half_width: float, target_radius: float = 0.0) -> bool:
	return strip_distance(origin, dir, target, length, half_width, target_radius) >= 0.0


## 帯の中なら、origin からの前向きの距離。外なら -1
static func strip_distance(origin: Vector2, dir: Vector2, target: Vector2, length: float, half_width: float, target_radius: float = 0.0) -> float:
	if dir.length() < 0.001:
		return -1.0
	var n := dir.normalized()
	var to := target - origin
	var along := to.dot(n)
	var side := absf(to.cross(n))
	if along < -target_radius or along > length + target_radius or side > half_width + target_radius:
		return -1.0
	return maxf(along, 0.0)


## 円の中（爆発）。center から radius（＋相手の大きさ）以内
static func in_circle(center: Vector2, target: Vector2, radius: float, target_radius: float = 0.0) -> bool:
	return center.distance_to(target) <= radius + target_radius


## ダッシュの行き先（向きに distance 進む。床の外には出ない）
static func dash_target(pos: Vector2, dir: Vector2, distance: float, bounds: float) -> Vector2:
	var n := dir.normalized() if dir.length() > 0.001 else Vector2.ZERO
	var p := pos + n * distance
	return Vector2(clampf(p.x, -bounds, bounds), clampf(p.y, -bounds, bounds))


## 投げる先（向きに distance。床の外には出ない）
static func lob_point(pos: Vector2, dir: Vector2, distance: float, bounds: float) -> Vector2:
	return dash_target(pos, dir, distance, bounds)
