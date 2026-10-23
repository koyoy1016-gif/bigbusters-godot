extends RefCounted
## プレイヤーの3つの攻撃（通常・サブ・メイン）の「時間の進み」だけを持つ（画面もダメージも持たない）。
## 何がいつ起きるか（当たる時刻、アニメの切り替え、体の動き）は data/actions.json。
## この部品は「いまこれが起きた」という出来事（events）を返すだけ。実際のダメージは、呼ぶ側が
## damage.gd（CLAUDE.md ルール4）で計算し、当たりの形は hit_area.gd で調べる。

const PATH := "res://data/actions.json"
## 版78：キャラごとの攻撃（A・X・Y・必殺）。actions.json の同じ名前の動きを、キャラの分で置きかえる
const CHAR_PATH := "res://data/char_actions.json"

var cfg: Dictionary = {}
var active := ""
var t := 0.0
var duration := 0.0
var aim := Vector2(0.0, -1.0)
var cooldowns := {}
## この1コマで動く量。x = 前向きに進んだ距離、y = 地面からの高さ
var frame_move := Vector2.ZERO
var height := 0.0
var _hit_i := 0
var _step_i := 0
var _mark_i := 0
var _last_fwd := 0.0
var _queue: Array = []
var _fx_i := 0
var _eff_i := 0
## 版78：待ち時間の減る速さ（スピードファイターの超高速モードで 1.75）
var cd_rate := 1.0
## 版111：続けて押した時の、次の技（combo：{"next": 次の技の id, "window_sec": 終わってから何秒以内}）。
## combo_from の技が終わってから combo_left 秒の間に、同じ技を押すと、次の技になる（兵隊の A の2回目＝2体投げ）
var combo_from := ""
var combo_left := 0.0


func _init(config: Dictionary = {}) -> void:
	cfg = config if not config.is_empty() else load_config()


static func load_config(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static var _char_cache: Dictionary = {}


## 版79：キャラの役の情報（_meta：役・必殺技の色・火花の色）。剣士は actions.json の _meta
static func meta_for(char_id: String) -> Dictionary:
	if _char_cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHAR_PATH)) if FileAccess.file_exists(CHAR_PATH) else null
		_char_cache = (parsed as Dictionary).get("characters", {}) if parsed is Dictionary else {}
		_char_cache["_base"] = load_config().get("_meta", {})
	var c: Dictionary = _char_cache.get(char_id, {})
	return c.get("_meta", _char_cache.get("_base", {}))


## 版78：キャラ char_id の攻撃の設定（共通の actions.json に、data/char_actions.json のキャラの分を上書きした物）。
## キャラの分がなければ、共通のまま（剣士）
static func config_for(char_id: String) -> Dictionary:
	var base := load_config()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHAR_PATH)) if FileAccess.file_exists(CHAR_PATH) else null
	if not (parsed is Dictionary) or not (parsed as Dictionary).get("characters", {}).has(char_id):
		return base
	var mine: Dictionary = (parsed as Dictionary)["characters"][char_id]
	var acts: Dictionary = (base.get("actions", {}) as Dictionary).duplicate(true)
	for id in mine:
		if str(id).begins_with("_"):
			continue
		acts[id] = (mine[id] as Dictionary).duplicate(true)
	base["actions"] = acts
	base["character"] = char_id
	return base


## ボタンに出す順（通常、サブ、メイン）
func ids() -> Array:
	return cfg.get("order", [])


## その動きがあるか
func has_action(id: String) -> bool:
	return (cfg.get("actions", {}) as Dictionary).has(id)


func def(id: String) -> Dictionary:
	var d: Variant = (cfg.get("actions", {}) as Dictionary).get(id, {})
	return d if d is Dictionary else {}


func busy() -> bool:
	return active != ""


func cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


## 技の動いている間の、歩きの速さの割合（0 なら立ち止まる）。何もしていなければ 1
func move_scale() -> float:
	return float(def(active).get("move_scale", 1.0)) if busy() else 1.0


func can_start(id: String) -> bool:
	return not busy() and not def(id).is_empty() and cooldown_left(id) <= 0.0


## 動いている間は、ダメージを受けない動きか（投げられて転んでいる間など）。
## 版110：i_window [始め, 終わり]（秒）がある動き（Y の回避）は、その間だけ
func invulnerable() -> bool:
	if not busy():
		return false
	var d := def(active)
	return bool(d.get("i_frames", false)) or _in_window(d)


## 版110：Y の回避の、よけられる時間の中か（攻撃が当たれば「回避成功」）
func dodging() -> bool:
	return busy() and bool(def(active).get("dodge", false)) and _in_window(def(active))


func _in_window(d: Dictionary) -> bool:
	var w: Variant = d.get("i_window", null)
	return w is Array and (w as Array).size() == 2 and t >= float(w[0]) and t <= float(w[1])


## 始める。始められたら true。cooldown_override が 0 より大きければ、待ち時間（と、それに合わせる長さ）をそれにする。
## force が true なら、いまの動きを打ち切って、待ち時間も見ずに始める（投げられたときなど、相手から強いられる動き）
func start(id: String, aim_dir: Vector2, cooldown_override: float = -1.0, force: bool = false) -> bool:
	if force:
		if def(id).is_empty():
			return false
		cancel()
	elif not can_start(id):
		return false
	var base_id := id
	var nxt := combo_next(id)
	if not force and nxt != "":
		id = nxt  # 版111：続けて押した2回目は、次の技（待ち時間はその技の物）
		cooldown_override = -1.0
	combo_from = ""
	combo_left = 0.0
	var d := def(id)
	var cd := cooldown_override if cooldown_override > 0.0 else float(d.get("cooldown_sec", 1.0))
	active = id
	t = 0.0
	duration = cd if bool(d.get("duration_from_cooldown", false)) else float(d.get("duration_sec", 1.0))
	aim = aim_dir.normalized() if aim_dir.length() > 0.001 else Vector2(0.0, -1.0)
	cooldowns[id] = cd
	if base_id != id:
		cooldowns[base_id] = cd  # ボタン（もとの技）にも、待ち時間を出す
	_hit_i = 0
	_step_i = 0
	_mark_i = 0
	_fx_i = 0
	_eff_i = 0
	_last_fwd = 0.0
	frame_move = Vector2.ZERO
	height = float(offset_at(d.get("path", []), 0.0).y)
	_queue = []
	_fire_due()
	return true


## 版111：いま id を押したら、続けて押した時の次の技になるか。なるなら、その id。ならなければ ""
func combo_next(id: String) -> String:
	if combo_left <= 0.0 or combo_from != id:
		return ""
	var nxt := str((def(id).get("combo", {}) as Dictionary).get("next", ""))
	return nxt if not def(nxt).is_empty() else ""


## 途中でやめる（ダウン、つかまれた、戦いが終わった）。待ち時間は、そのまま残る
func cancel() -> void:
	combo_from = ""
	combo_left = 0.0
	active = ""
	frame_move = Vector2.ZERO
	height = 0.0
	_queue = []


## 全部元に戻す（待ち時間も消す）
func reset() -> void:
	cancel()
	cooldowns = {}


## 時間を進める。この1コマで起きた出来事の一覧を返す：
## {"type": "hit", "action", "multiplier", "radius_scale", "cleave"}、 {"type": "anim", "anim", "speed", "from_end"}、 {"type": "mark", "name"}（着地などの印）
func update(delta: float) -> Array:
	for id in cooldowns.keys():
		cooldowns[id] = maxf(0.0, float(cooldowns[id]) - delta * cd_rate)
	frame_move = Vector2.ZERO
	if combo_left > 0.0 and not busy():
		combo_left = maxf(0.0, combo_left - delta)
	if not busy():
		var out := _queue
		_queue = []
		return out
	t += delta
	_fire_due()
	var d := def(active)
	var off := offset_at(d.get("path", []), minf(t, duration))
	frame_move.x = off.x - _last_fwd
	_last_fwd = off.x
	height = off.y
	if t >= duration:
		# 版111：続けて押せる技なら、終わってから少しの間、次の技を受けつける
		var combo: Dictionary = d.get("combo", {})
		combo_from = active if not combo.is_empty() else ""
		combo_left = float(combo.get("window_sec", 0.0)) if not combo.is_empty() else 0.0
		active = ""
		height = 0.0
	var events := _queue
	_queue = []
	return events


func _fire_due() -> void:
	var d := def(active)
	var hits: Array = d.get("hits", [])
	while _hit_i < hits.size() and float(hits[_hit_i]["t"]) <= t:
		# 版78：当たりの形（shape：melee・beam・blast・self）と、その大きさ。書いていなければ、いままでの近くの当たり
		_queue.append({"type": "hit", "action": active, "multiplier": float(hits[_hit_i]["multiplier"]),
			"radius_scale": float(d.get("radius_scale", 1.0)), "cleave": bool(d.get("cleave", false)), "hit": hits[_hit_i]})
		_hit_i += 1
	var steps: Array = d.get("steps", [])
	while _step_i < steps.size() and float(steps[_step_i]["t"]) <= t:
		_queue.append({"type": "anim", "anim": str(steps[_step_i]["anim"]), "speed": float(steps[_step_i]["speed"]),
			"from_end": bool(steps[_step_i].get("from_end", false))})
		_step_i += 1
	# 版78：見た目（fx）と、効果（effects：速くなる・ドーム・回復・時間停止・呼び出しなど）
	var fxs: Array = d.get("fx_events", [])
	while _fx_i < fxs.size() and float(fxs[_fx_i]["t"]) <= t:
		_queue.append({"type": "fx", "action": active, "spec": fxs[_fx_i]})
		_fx_i += 1
	var effs: Array = d.get("effects", [])
	while _eff_i < effs.size() and float(effs[_eff_i]["t"]) <= t:
		_queue.append({"type": "effect", "action": active, "spec": effs[_eff_i]})
		_eff_i += 1
	var marks: Array = d.get("marks", [])
	while _mark_i < marks.size() and float(marks[_mark_i]["t"]) <= t:
		_queue.append({"type": "mark", "name": str(marks[_mark_i]["name"])})
		_mark_i += 1


## 体の動きの道（path）の、時刻 time での (前向きの距離, 高さ)。キーとキーの間は、なめらかにつなぐ
static func offset_at(path: Array, time: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if time <= float(path[0]["t"]):
		return Vector2(float(path[0]["fwd"]), float(path[0]["h"]))
	for i in range(1, path.size()):
		var b: Dictionary = path[i]
		if time <= float(b["t"]):
			var a: Dictionary = path[i - 1]
			var span := maxf(0.0001, float(b["t"]) - float(a["t"]))
			var k := smoothstep(0.0, 1.0, (time - float(a["t"])) / span)
			return Vector2(lerpf(float(a["fwd"]), float(b["fwd"]), k), lerpf(float(a["h"]), float(b["h"]), k))
	var last: Dictionary = path[path.size() - 1]
	return Vector2(float(last["fwd"]), float(last["h"]))
