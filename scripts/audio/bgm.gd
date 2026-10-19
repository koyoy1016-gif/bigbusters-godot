extends Node
## メニューのBGMを流す。短い曲をループする。戦いの最中は止める（画面の流れは game_flow.gd が決める）。
## 音は data/bgm.json で決める。ブラウザでは、最初のタップのあとに鳴り始める。

const CONFIG_PATH := "res://data/bgm.json"

var cfg: Dictionary = {}
var muted := false
var player: AudioStreamPlayer = null
var active := false  ## 流すように指示したか（start で true、stop で false）


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
	active = true
	return true


func stop() -> void:
	active = false
	if player != null:
		player.stop()


## 流している状態か（流すように指示して、止めていない）。
## 音の再生そのもの（player.playing）は、音の処理の都合で、play() の直後に一瞬 false のことがある（画面なしのテストで、まれに落ちていた原因）。
## そのため、ゲームが決めた状態を返す
func is_playing() -> bool:
	return player != null and active
