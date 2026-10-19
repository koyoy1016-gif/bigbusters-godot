extends RefCounted
## 床の酒だまり（ゲームの物）。画面を持たない（テストしやすい）。
## 1つずつ：id、位置、広さ（半径）、できた時刻、消える時刻、燃えはじめる時刻・燃えおわる時刻を持つ。
## 酒瓶が割れた所にできる（boss_attacks.gd の酒瓶落とし・火祭り）。火祭りのライターで火がつくと、
## つながっている酒だまり（ふちとふちの間が link_gap m 以内）へ、順番に燃えうつる。
## 時刻は「戦いが始まってからの秒」。同じ攻撃なら全員の画面で同じになる。

var puddles: Array = []  ## [{id, pos: Vector2, r, born, expire, burn_start, burn_end, fire}]


func clear() -> void:
	puddles = []


## 酒だまりを作る（同じ id なら、何もしない）。life：消えるまでの秒。spread_sec：広がりきるまでの秒
func add(id: String, pos: Vector2, r: float, t: float, life: float, spread_sec: float = 0.6) -> void:
	for p in puddles:
		if str(p["id"]) == id:
			return
	puddles.append({"id": id, "pos": pos, "r": r, "born": t, "expire": t + life, "spread": spread_sec, "burn_start": -1.0, "burn_end": -1.0, "fire": ""})


## いま見える（消えていない）酒だまり
func alive(t: float) -> Array:
	return puddles.filter(func(p: Dictionary) -> bool: return t >= float(p["born"]) and t < float(p["expire"]))


## 広がり具合をふくめた、いまの半径
static func radius_at(p: Dictionary, t: float) -> float:
	var k := clampf((t - float(p["born"])) / maxf(float(p.get("spread", 0.6)), 0.01), 0.0, 1.0)
	return float(p["r"]) * (0.45 + 0.55 * (1.0 - (1.0 - k) * (1.0 - k)))


## 古くなった酒だまりを消す（燃えおわった物も）
func prune(t: float) -> void:
	puddles = puddles.filter(func(p: Dictionary) -> bool: return t < float(p["expire"]))


## 火をつける。origin に近い酒だまりから燃えはじめ、つながっている物へ hop_sec ずつおくれて燃えうつる。
## fire：火の事件の名前（同じ事件では、ダメージは1回だけ）。燃えた酒だまりの数を返す
func ignite(fire: String, origin: Vector2, t: float, reach: float, hop_sec: float, burn_sec: float, link_gap: float) -> int:
	var live := alive(t).filter(func(p: Dictionary) -> bool: return float(p["burn_start"]) < 0.0)
	if live.is_empty():
		return 0
	# 火のついた所に、いちばん近い酒だまり（reach m 以内）
	var first: Dictionary = {}
	var best := 1e9
	for p in live:
		var d := (p["pos"] as Vector2).distance_to(origin) - radius_at(p, t)
		if d < best:
			best = d
			first = p
	if first.is_empty() or best > reach:
		return 0
	# つながりを順にたどる（ふちとふちが近い物へ）
	var queue: Array = [[first, 0]]
	first["burn_start"] = t
	var count := 0
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var p: Dictionary = item[0]
		var hop: int = item[1]
		p["burn_start"] = t + float(hop) * hop_sec
		p["burn_end"] = float(p["burn_start"]) + burn_sec
		p["fire"] = fire
		p["expire"] = maxf(float(p["expire"]), float(p["burn_end"]) + 0.3)
		count += 1
		for q in live:
			if float(q["burn_start"]) >= 0.0:
				continue
			var gap := (q["pos"] as Vector2).distance_to(p["pos"]) - radius_at(q, t) - radius_at(p, t)
			if gap <= link_gap:
				q["burn_start"] = 0.0  # 印（あとで正しい時刻を入れる）
				queue.append([q, hop + 1])
	return count


## いま燃えている酒だまり
func burning(t: float) -> Array:
	return puddles.filter(func(p: Dictionary) -> bool: return float(p["burn_start"]) >= 0.0 and t >= float(p["burn_start"]) and t < float(p["burn_end"]))


## これから燃える（火がついたが、まだ燃えうつっていない）酒だまり
func about_to_burn(t: float) -> Array:
	return puddles.filter(func(p: Dictionary) -> bool: return float(p["burn_start"]) >= 0.0 and t < float(p["burn_start"]))
