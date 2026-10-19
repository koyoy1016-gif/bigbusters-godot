extends RefCounted
## 必殺技のゲージ（画面を持たない）。ボスに与えたダメージでたまり、いっぱいで必殺技が使える。
## 数値は data/actions.json の ultimate_gauge。プレイヤーもAIも、1人に1つずつ持つ。

var value := 0.0
var max_value := 700.0
var gain := 1.0


func _init(cfg: Dictionary = {}) -> void:
	var g: Dictionary = cfg.get("ultimate_gauge", {})
	max_value = float(g.get("max", 700.0))
	gain = float(g.get("gain_per_damage", 1.0))


## 与えたダメージの分だけ、ためる
func charge(damage: float) -> void:
	value = clampf(value + maxf(0.0, damage) * gain, 0.0, max_value)


func is_ready() -> bool:
	return value >= max_value


## 0〜1
func ratio() -> float:
	return value / maxf(0.001, max_value)


## 使う。使えたら true（ゲージは空になる）
func consume() -> bool:
	if not is_ready():
		return false
	value = 0.0
	return true


func reset() -> void:
	value = 0.0
