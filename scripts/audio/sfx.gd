extends Node
## 効果音を鳴らす。同じ音を続けて鳴らしすぎない（min_gap_sec）。音は data/sfx.json、ファイルは tools/make_sfx.py が作る。
## 鳴らす回路は決まった数（pool_size）を使いまわす。muted にすると、鳴らさない。

const CONFIG_PATH := "res://data/sfx.json"

var cfg: Dictionary = {}
var muted := false
var pool: Array = []
var streams := {}
var last_play := {}
var played: Array = []  # 鳴らした名前の記録（テスト用。多くなりすぎないよう切りつめる）


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 前に鳴らしたのが min_gap 秒より前か（now・last は秒）
static func gap_ok(now: float, last: float, min_gap: float) -> bool:
	return last < 0.0 or now - last >= min_gap


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if cfg.is_empty():
		cfg = load_config()
	if not pool.is_empty():
		return
	for i in int(cfg.get("pool_size", 8)):
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)


## 鳴らす。鳴らしたら true
func play(sound: String) -> bool:
	_ensure_pool()
	var sounds: Dictionary = cfg.get("sounds", {})
	if muted or not sounds.has(sound):
		return false
	var def: Dictionary = sounds[sound]
	var now := Time.get_ticks_msec() / 1000.0
	if not gap_ok(now, float(last_play.get(sound, -1.0)), float(def.get("min_gap_sec", 0.0))):
		return false
	last_play[sound] = now
	played.append(sound)
	if played.size() > 64:
		played = played.slice(32)
	if pool.is_empty():
		return true
	if not streams.has(sound):
		streams[sound] = load(str(def["file"])) as AudioStream
	var stream: AudioStream = streams[sound]
	if stream == null:
		return false
	for p in pool:
		var ap := p as AudioStreamPlayer
		if not ap.playing:
			ap.stream = stream
			ap.volume_db = float(def.get("volume_db", 0.0))
			ap.play()
			return true
	var first := pool[0] as AudioStreamPlayer
	first.stream = stream
	first.volume_db = float(def.get("volume_db", 0.0))
	first.play()
	return true
