extends RefCounted
## 版84：倒れた仲間の蘇生（画面を持たない計算だけ。テストしやすい）。数値は data/prototype_stick.json の "revive"。
## 倒れた所に、輪（蘇生の範囲）ができる。window_sec（20秒）の間に、生きている味方が輪の中に hold_sec（4秒）続けていれば、
## hp_ratio（30%）の体力で起きる。輪から出たら、進みは0にもどる。時間が過ぎたら、もう起こせない（輪は消える）。
## 1人に輪は1つ。起きたら輪は消えるので、2回起きることはない。何人で入っても、進む速さは同じ。

var cfg: Dictionary = {}
## slot → {pos: Vector2, left: float（のこり秒）, progress: float（中にいた秒）, by: String（いま中にいる人）}
var zones: Dictionary = {}
var expired: Dictionary = {}  # 時間が過ぎて、もう起こせない人


func _init(config: Dictionary = {}) -> void:
	cfg = config


func window_sec() -> float:
	return float(cfg.get("window_sec", 20.0))


func hold_sec() -> float:
	return float(cfg.get("hold_sec", 4.0))


func hp_ratio() -> float:
	return float(cfg.get("hp_ratio", 0.3))


## 輪の半径（m）：プレイヤーの当たりの大きさ（player_size）× radius_factor
func radius(player_size: float) -> float:
	return player_size * float(cfg.get("radius_factor", 1.8))


## 倒れた：輪を作る（もうあれば、作りなおさない）
func on_down(slot: String, pos: Vector2) -> bool:
	if zones.has(slot) or expired.has(slot):
		return false
	zones[slot] = {"pos": pos, "left": window_sec(), "progress": 0.0, "by": ""}
	return true


## ほかの方法（回復の膜・必殺技）で起きた：輪を消す
func clear(slot: String) -> void:
	zones.erase(slot)
	expired.erase(slot)


func reset() -> void:
	zones = {}
	expired = {}


## 1コマ進める。alive：生きている味方 {slot: 位置}。r：輪の半径。
## 戻り値：{revived: [起きた人], expired: [時間が過ぎた人]}
func update(delta: float, alive: Dictionary, r: float) -> Dictionary:
	var revived: Array = []
	var gone: Array = []
	for slot in zones.keys():
		var z: Dictionary = zones[slot]
		z["left"] = float(z["left"]) - delta
		if float(z["left"]) <= 0.0:
			zones.erase(slot)
			expired[slot] = true
			gone.append(slot)
			continue
		var who := ""
		for s in alive:
			if str(s) == str(slot):
				continue
			if (alive[s] as Vector2).distance_to(z["pos"]) <= r:
				who = str(s)
				break
		z["by"] = who
		if who == "":
			z["progress"] = 0.0  # 出たら、0にもどる
		else:
			z["progress"] = float(z["progress"]) + delta
			if float(z["progress"]) >= hold_sec():
				zones.erase(slot)
				revived.append(slot)
	return {"revived": revived, "expired": gone}


## AIの味方に、起こしに行く輪をわりあてる：輪ごとに、いちばん近い（倒れていない）AIを1人。{AIの枠: 輪の位置}
static func assign(zones_now: Dictionary, ai_pos: Dictionary) -> Dictionary:
	var out := {}
	var keys := zones_now.keys()
	keys.sort()
	for slot in keys:
		var z: Dictionary = zones_now[slot]
		var best := ""
		var best_d := INF
		for s in ai_pos:
			if str(s) == str(slot) or out.has(s):
				continue
			var d := (ai_pos[s] as Vector2).distance_to(z["pos"])
			if d < best_d:
				best_d = d
				best = str(s)
		if best != "":
			out[best] = z["pos"]
	return out
