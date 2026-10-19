extends Node
## メニューのBGMを流す。短い曲をループする。戦いの最中は止める（画面の流れは game_flow.gd が決める）。
## 音は data/bgm.json で決める。ブラウザでは、最初のタップのあとに鳴り始める。

const CONFIG_PATH := "res://data/bgm.json"

var cfg: Dictionary = {}
var muted := false
var player: AudioStreamPlayer = null


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	_ensure_player()


func _ensure_player() -> void:
	if player != null:
		return
	if cfg.is_empty():
		cfg = load_config()
	player = AudioStreamPlayer.new()
	player.name = "Player"
	add_child(player)
	var st := load(str(cfg.get("file", ""))) as AudioStreamWAV
	if st != null:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		player.stream = st
	player.volume_db = float(cfg.get("volume_db", -14.0))


## 流し始める。流し始めたら true（ミュート中や音がないときは false）
func start() -> bool:
	_ensure_player()
	if muted or player.stream == null:
		return false
	if not player.playing:
		player.play()
	return true


func stop() -> void:
	if player != null:
		player.stop()


func is_playing() -> bool:
	return player != null and player.playing
