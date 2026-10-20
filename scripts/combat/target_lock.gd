extends RefCounted
## 版79：ターゲットロック（画面を持たない）。敵をタップすると、その敵をねらう。
## kind："boss"（ボス）・"sub"（サブ敵。index が番号）・""（ロックなし＝ボスを自動でねらう）。
## 敵が倒れた・消えた・ねらえない間は、外れる（valid が false を返したら clear する）。

var kind := ""
var index := -1
## ロックしてからの秒（照準の出る動きに使う）
var age := 0.0


func set_target(k: String, i: int = -1) -> void:
	if k != kind or i != index:
		age = 0.0
	kind = k
	index = i


func clear() -> void:
	kind = ""
	index = -1
	age = 0.0


func is_locked() -> bool:
	return kind != ""


func tick(delta: float) -> void:
	if is_locked():
		age += delta


## タップした所から、いちばん近い敵を選ぶ。cands：[{kind, index, screen: Vector2（敵の中心の画面の位置）, r_px: 敵の画面の大きさ}]。
## 敵の大きさ＋ゆとり（slack_px）の中で、中心にいちばん近い物。なければ {}
static func pick(tap: Vector2, cands: Array, slack_px: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for c in cands:
		var d := tap.distance_to(c["screen"])
		if d <= float(c["r_px"]) + slack_px and d < best_d:
			best_d = d
			best = c
	return best
