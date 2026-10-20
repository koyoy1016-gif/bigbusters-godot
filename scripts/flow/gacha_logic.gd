extends RefCounted
## 版83：ガチャの決まり（画面を持たない計算だけ。テストしやすい）。数字は data/gacha.json。
## 流れ（1回ごとの状態。順番どおりにしか進まない＝二重に回す・二重にもらうことがない）：
##   idle（まつ）→ aiming（剣士をつかんで引いている）→ flying（離した。コインを払った。斬っている）→ result（決まった。1回だけ渡した）→ idle
## 確率：斬った数 k ごとに、重み = 基本の確率 × (1 + kill_mult × k) を、合計100%に割りなおす。表示と抽選は、同じ関数 odds() を使う。
## レア度を決めてから、そのレア度のキャラの中から同じ確率で1人。もう持っていれば、コインが少しもどる。
## 注意：いまは端末の中で決めている（サーバーで決める仕組みはない。Firebase のルールだけでは、くじ引きをサーバーでできない）。

const RARITIES := ["N", "R", "SR", "SSR"]
const CONFIG_PATH := "res://data/gacha.json"

var cfg: Dictionary = {}
var profiles: Dictionary = {}
var state := "idle"
var pull_id := 0
var kills: Dictionary = {}  # 斬った敵の番号（1体1回だけ）
var paid_free := false
var last_result: Dictionary = {}
var granted := false


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}


func _init(config: Dictionary = {}, prof: Dictionary = {}) -> void:
	cfg = config if not config.is_empty() else load_config()
	profiles = prof


## 斬った数 k のときの、レア度ごとの確率（合計 1.0）
static func odds_for(config: Dictionary, k: int) -> Dictionary:
	var base: Dictionary = config.get("base_odds", {})
	var km: Dictionary = config.get("kill_mult", {})
	var w := {}
	var total := 0.0
	for r in RARITIES:
		var v := float(base.get(r, 0.0)) * maxf(0.1, 1.0 + float(km.get(r, 0.0)) * float(k))
		w[r] = v
		total += v
	var out := {}
	for r in RARITIES:
		out[r] = float(w[r]) / total if total > 0.0 else 0.0
	return out


func odds(k: int) -> Dictionary:
	return odds_for(cfg, k)


## レア度ごとのキャラ（data/character_profiles.json のレア度）
func pool(rarity: String) -> Array:
	var out: Array = []
	var chars: Dictionary = profiles.get("characters", {})
	for id in chars:
		if str((chars[id] as Dictionary).get("rarity", "")) == rarity:
			out.append(str(id))
	out.sort()
	return out


## 1人ずつの確率の表（回す前に見せる）：[{id, rarity, p}]。斬った数 k のとき
func item_odds(k: int) -> Array:
	var o := odds(k)
	var out: Array = []
	for r in RARITIES:
		var p: Array = pool(r)
		for id in p:
			out.append({"id": id, "rarity": r, "p": float(o[r]) / float(p.size())})
	return out


func cost() -> int:
	return int(cfg.get("cost", 100))


## 払えるか（はじめの1回は無料のとき、まだ回していなければ払わなくてよい）
func can_pay(coins: int, pulls_done: int) -> bool:
	return free_now(pulls_done) or coins >= cost()


func free_now(pulls_done: int) -> bool:
	return bool(cfg.get("first_free", false)) and pulls_done <= 0


# ---------------------------------------------------------------- 状態

func start_aim(coins: int, pulls_done: int) -> bool:
	if state != "idle" or not can_pay(coins, pulls_done):
		return false
	state = "aiming"
	return true


func cancel_aim() -> void:
	if state == "aiming":
		state = "idle"


## 離した：払う（無料の1回なら払わない）。戻り値：払うコイン（払えない・状態がちがうなら -1）
func launch(coins: int, pulls_done: int) -> int:
	if state != "aiming" or not can_pay(coins, pulls_done):
		return -1
	state = "flying"
	pull_id += 1
	kills = {}
	granted = false
	last_result = {}
	paid_free = free_now(pulls_done)
	return 0 if paid_free else cost()


## 敵を斬った（同じ敵は1回だけ。飛んでいる間だけ）。新しく数えたら true
func add_kill(enemy: int) -> bool:
	if state != "flying" or kills.has(enemy) or enemy < 0 or enemy >= int(cfg.get("enemy_count", 5)):
		return false
	kills[enemy] = true
	return true


func kill_count() -> int:
	return kills.size()


## 斬り終わった：レア度とキャラを決める（1回だけ）。owned：いま持っているキャラ。戻り値：{id, rarity, kills, odds, new, refund, pull_id}
func finish(rng: RandomNumberGenerator, owned: Array) -> Dictionary:
	if state != "flying":
		return {}
	state = "result"
	var k := kill_count()
	var o := odds(k)
	var roll := rng.randf()
	var rarity := "N"
	var acc := 0.0
	for r in RARITIES:
		acc += float(o[r])
		if roll < acc:
			rarity = r
			break
		rarity = r
	var p := pool(rarity)
	var id := str(p[rng.randi_range(0, p.size() - 1)]) if not p.is_empty() else ""
	var is_new := id != "" and not owned.has(id)
	last_result = {"id": id, "rarity": rarity, "kills": k, "odds": o, "new": is_new,
		"refund": 0 if is_new else int((cfg.get("dup_refund", {}) as Dictionary).get(rarity, 0)), "pull_id": pull_id, "free": paid_free}
	return last_result


## 結果を渡した印（二重に渡さない）。まだなら true を返して印をつける
func take_grant() -> bool:
	if state != "result" or granted:
		return false
	granted = true
	return true


func reset() -> void:
	if state == "result":
		state = "idle"


# ---------------------------------------------------------------- 当たり（斬れたか）

## 剣士の道（床の上の a → b）と、終わりの斬撃（b から dir の向きに、扇の形）に、敵 p が入るか
func hits(a: Vector2, b: Vector2, p: Vector2) -> bool:
	var reach := float(cfg.get("hit_radius", 1.5)) + float(cfg.get("enemy_radius", 0.7))
	if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= reach:
		return true
	var dir := (b - a).normalized()
	var to := p - b
	if dir.length() < 0.01 or to.length() > float(cfg.get("end_slash_radius", 2.8)) + float(cfg.get("enemy_radius", 0.7)):
		return false
	return to.length() < 0.01 or rad_to_deg(absf(dir.angle_to(to))) <= float(cfg.get("end_slash_deg", 140.0)) * 0.5


## 引いた量（画面の点）から、飛ぶ向き（床の上。前は -z）と強さ（0〜1）。引いた反対の向きへ飛ぶ。強さが足りなければ power 0
func aim_from_pull(pull_px: Vector2) -> Dictionary:
	var power := clampf(pull_px.length() / float(cfg.get("pull_max_px", 300.0)), 0.0, 1.0)
	var d := Vector2(-pull_px.x, -pull_px.y)  # 下へ引く → 前（-z）へ、右へ引く → 左へ
	if d.length() < 0.001 or pull_px.y <= 0.0:
		d = Vector2(0, -1)
		power = 0.0 if pull_px.y <= 0.0 else power
	var ang := clampf(atan2(d.x, -d.y), -deg_to_rad(float(cfg.get("max_angle_deg", 50.0))), deg_to_rad(float(cfg.get("max_angle_deg", 50.0))))
	var dir := Vector2(sin(ang), -cos(ang))
	if power < float(cfg.get("pull_min_power", 0.15)):
		power = 0.0
	var dist := lerpf(float(cfg.get("launch_min_m", 4.0)), float(cfg.get("launch_max_m", 13.0)), power)
	return {"dir": dir, "power": power, "dist": dist}


## 敵の並び（1回ごとに、少しずつ場所をずらす）
func layout(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var j := float(cfg.get("enemy_jitter", 0.5))
	for p in cfg.get("enemy_layout", []):
		out.append(Vector2(float(p[0]) + rng.randf_range(-j, j), float(p[1]) + rng.randf_range(-j, j)))
	return out
