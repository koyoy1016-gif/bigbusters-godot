extends RefCounted
## 版75：与えたダメージの数字（画面を持たない。動きの計算だけ。描くのは stick_prototype.gd の _draw_damage_numbers）。
## 体力を減らす所（_damage_boss・AIの _resolve_hit）が、実際に減らした量をそのまま add に渡す。表示のために別の計算はしない。
## 動き：出た瞬間に大きく出て、弾んで元の大きさへ → 少し上へ浮きながら、すきとおって消える。
## 種類 kind："normal"（ふつう）／"strong"（強い攻撃：大きく、強く弾む。衝撃線つき）／"critical"（特別な色と文字。いまのゲームにクリティカルはないので、出す所はない）
## 数値は data/prototype_stick.json の damage_numbers。

var cfg: Dictionary = {}
var items: Array = []  ## [{amount, text, kind, world: Vector3, age, life, dx, dy}]（古い順）
var _recent: Array = []  ## 少し前に出した時刻（続けて出たら、ずらす）
var clock := 0.0


func _init(config: Dictionary = {}) -> void:
	cfg = config


## 出す。amount：実際に与えたダメージ（0以下なら出さない）。world：出す場所（3Dの位置）。戻り値：出した物（出さなければ {}）
func add(amount: float, world: Vector3, kind: String = "normal") -> Dictionary:
	if amount <= 0.0 or not is_finite(amount):
		return {}
	var k := kind if (cfg.get("kinds", {}) as Dictionary).has(kind) else "normal"
	var kc: Dictionary = kind_cfg(k)
	# 短い間に続けて出たら、左右と上へ少しずつずらして、重なりにくくする
	var win := float(cfg.get("stack_window", 0.3))
	while not _recent.is_empty() and clock - float(_recent[0]) > win:
		_recent.pop_front()
	var n := _recent.size()
	_recent.append(clock)
	var side := 0.0 if n == 0 else (1.0 if n % 2 == 1 else -1.0) * ceilf(n / 2.0)
	var it := {"amount": amount, "text": text_of(amount, k), "kind": k, "world": world, "age": 0.0,
		"life": float(kc.get("life", cfg.get("life", 0.65))),
		"dx": side * float(cfg.get("stack_dx", 28.0)), "dy": -float(n) * float(cfg.get("stack_dy", 18.0))}
	items.append(it)
	while items.size() > int(cfg.get("max_items", 24)):
		items.pop_front()
	return it


func kind_cfg(kind: String) -> Dictionary:
	return (cfg.get("kinds", {}) as Dictionary).get(kind, {})


## 出す文字（format の {n} が、四捨五入した数）
func text_of(amount: float, kind: String) -> String:
	var n := int(roundf(snappedf(amount, 0.001)))  # 22.5×22×0.7 が 346.4999… になる小さな誤差をそろえてから四捨五入
	return str(kind_cfg(kind).get("format", "{n}")).replace("{n}", str(n))


## 時間を進める。消えた物を取りのぞく
func update(delta: float) -> void:
	clock += delta
	for it in items:
		it["age"] = float(it["age"]) + delta
	var keep: Array = []
	for it in items:
		if float(it["age"]) < float(it["life"]):
			keep.append(it)
	items = keep


## age 秒のときの見た目 {scale（文字の大きさの倍率）, rise（上へ浮いた px）, alpha（0〜1）, shake（左右のゆれ px）, burst（衝撃線の強さ 0〜1）}
func look(it: Dictionary) -> Dictionary:
	var kc := kind_cfg(str(it["kind"]))
	var life := float(it["life"])
	var t := clampf(float(it["age"]) / maxf(life, 0.01), 0.0, 1.0)
	var age := float(it["age"])
	var pop := float(kc.get("pop", 1.6))  # 出た瞬間の大きさ
	var pop_sec := float(kc.get("pop_sec", 0.14))
	var scale := 1.0
	if age < pop_sec:
		# 大きく出て、ばねのように元の大きさへ（少し小さくなって、もどる）
		var x := age / pop_sec
		scale = lerpf(pop, 1.0, x) - sin(x * PI) * 0.12
	else:
		var x2 := clampf((age - pop_sec) / 0.12, 0.0, 1.0)
		scale = 1.0 + sin(x2 * PI) * 0.06 * (1.0 - x2)
	var rise := float(cfg.get("rise_px", 56.0)) * (1.0 - pow(1.0 - t, 2.0))
	var fade_from := float(cfg.get("fade_from", 0.55))
	var alpha := 1.0 if t < fade_from else 1.0 - (t - fade_from) / maxf(1.0 - fade_from, 0.01)
	var shake := 0.0
	if float(kc.get("shake_px", 0.0)) > 0.0:
		shake = sin(age * 70.0) * float(kc["shake_px"]) * (1.0 - t)
	var burst := 0.0
	if bool(kc.get("burst", false)):
		burst = clampf(1.0 - age / float(kc.get("burst_sec", 0.16)), 0.0, 1.0)
	return {"scale": scale, "rise": rise, "alpha": clampf(alpha, 0.0, 1.0), "shake": shake, "burst": burst}


## 画面の位置 p を、文字が画面の外に出ないよう、ふちから margin の内側に入れる
static func keep_on_screen(p: Vector2, screen: Vector2, half_size: Vector2, margin: float) -> Vector2:
	var lo := Vector2(margin, margin) + half_size
	var hi := screen - Vector2(margin, margin) - half_size
	return Vector2(clampf(p.x, lo.x, maxf(lo.x, hi.x)), clampf(p.y, lo.y, maxf(lo.y, hi.y)))
