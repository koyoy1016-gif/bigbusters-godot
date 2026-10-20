extends Node
## 効果音を鳴らす。同じ音を続けて鳴らしすぎない（min_gap_sec）。音は data/sfx.json、ファイルは tools/make_sfx.py が作る。
## 鳴らす回路は決まった数（pool_size）を使いまわす（全部使っていたら、いちばん前に鳴らし始めた回路を使う）。muted にすると、鳴らさない。
## 版85：鳴らすたびに高さを少し変える（pitch_var）。距離などで小さくする（play の add_db）。プレイヤーが決めた大きさ（user_volume 0〜1）。
## 大きな音（duck_db がある音）を鳴らしたら loud を出す（音楽を少し下げるため。game_flow.gd がつなぐ）。

signal loud(db: float)

const CONFIG_PATH := "res://data/sfx.json"

var cfg: Dictionary = {}
var muted := false
var user_volume := 1.0  ## プレイヤーが決めた大きさ（0〜1。0 で鳴らさない）
var pool: Array = []
var started: Array = []  ## 回路ごとの、鳴らし始めた時刻（秒）
var streams := {}
var last_play := {}
var played: Array = []  # 鳴らした名前の記録（テスト用。多くなりすぎないよう切りつめる）
var rng := RandomNumberGenerator.new()


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 前に鳴らしたのが min_gap 秒より前か（now・last は秒）
static func gap_ok(now: float, last: float, min_gap: float) -> bool:
	return last < 0.0 or now - last >= min_gap


## 0〜1 の大きさを dB に（0 は、とても小さい）
static func volume_to_db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 1.0))


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if cfg.is_empty():
		cfg = load_config()
	if not pool.is_empty():
		return
	rng.seed = 85
	for i in int(cfg.get("pool_size", 8)):
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
		started.append(-1.0)


func set_user_volume(v: float) -> void:
	user_volume = clampf(v, 0.0, 1.0)


## 鳴らす。鳴らしたら true。add_db：大きさの足し引き（遠い・AIの味方など）。pitch：高さの倍率
func play(sound: String, add_db: float = 0.0, pitch: float = 1.0) -> bool:
	_ensure_pool()
	var sounds: Dictionary = cfg.get("sounds", {})
	if muted or user_volume <= 0.001 or not sounds.has(sound):
		return false
	var def: Dictionary = sounds[sound]
	var now := Time.get_ticks_msec() / 1000.0
	if not gap_ok(now, float(last_play.get(sound, -1.0)), float(def.get("min_gap_sec", 0.0))):
		return false
	last_play[sound] = now
	played.append(sound)
	if played.size() > 64:
		played = played.slice(32)
	if def.has("duck_db"):
		loud.emit(float(def["duck_db"]))
	if pool.is_empty():
		return true
	if not streams.has(sound):
		streams[sound] = load(str(def["file"])) as AudioStream
	var stream: AudioStream = streams[sound]
	if stream == null:
		return false
	var pick := -1
	for i in pool.size():
		if not (pool[i] as AudioStreamPlayer).playing:
			pick = i
			break
	if pick < 0:
		pick = 0
		for i in pool.size():
			if float(started[i]) < float(started[pick]):
				pick = i
	var ap := pool[pick] as AudioStreamPlayer
	var pv := float(def.get("pitch_var", 0.0))
	ap.stream = stream
	ap.volume_db = float(def.get("volume_db", 0.0)) + add_db + volume_to_db(user_volume)
	ap.pitch_scale = clampf(pitch * (1.0 + rng.randf_range(-pv, pv)), 0.3, 3.0)
	ap.play()
	started[pick] = now
	return true
