extends RefCounted
## 版69：ボスの怒り。画面を持たない（テストしやすい）。
## 味方の攻撃が、ボスの体の近く（near_m m 以内）から当たった時刻を覚えておき、
## 直前の window_sec 秒に hits 回以上あれば「怒っている」。回数が下がれば、すぐ元にもどる。
## 怒っている間に始まる攻撃は speed 倍の速さ、つかみ投げの重みは grab_mult 倍（使うのは boss_ai.gd と stick_prototype.gd）。
## 数値は data/boss_attacks.json の ai.rage。

var near_m := 3.0
var window_sec := 5.0
var hits := 20
var speed := 1.25
var grab_mult := 2.0
var online := false  ## false なら、通信中は怒らない
var enabled := true  ## 通信中で online が false のときは false にする
var times: Array = []  ## 近くから当たった時刻（戦いの秒。古い順）


func setup(cfg: Dictionary) -> void:
	near_m = float(cfg.get("near_m", near_m))
	window_sec = float(cfg.get("window_sec", window_sec))
	hits = int(cfg.get("hits", hits))
	speed = float(cfg.get("speed", speed))
	grab_mult = float(cfg.get("grab_mult", grab_mult))
	online = bool(cfg.get("online", online))
	reset()


func reset() -> void:
	times = []


## 近くから当たったか（dist_to_surface：当てた人から、ボスの体の表面までの距離 m）
func is_near(dist_to_surface: float) -> bool:
	return dist_to_surface <= near_m


## 味方の攻撃がボスに当たった。近くからなら、時刻 t を覚える
func add_hit(t: float, dist_to_surface: float) -> void:
	if not enabled or not is_near(dist_to_surface):
		return
	times.append(t)


## 直前の window_sec 秒に、近くから当たった回数（古い記録は捨てる）
func count(t: float) -> int:
	while not times.is_empty() and float(times[0]) <= t - window_sec:
		times.pop_front()
	var c := 0
	for x in times:
		if float(x) <= t:
			c += 1
	return c


## いま怒っているか
func is_angry(t: float) -> bool:
	return enabled and count(t) >= hits
