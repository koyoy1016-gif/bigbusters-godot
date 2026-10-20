extends Node
## 版85：音楽。曲（data/bgm.json の tracks：ロビー・戦い・覚醒・勝ち・負け）を切りかえる。曲は tools/make_music.py が作る。
## 再生口を2つ使い、前の曲を小さくしながら次の曲を大きくする（クロスフェード）。
## 勝ち・負けの短い曲（loop: false）の途中で、ループする曲を頼まれたら、短い曲が終わってから流す（pending）。
## 大きな効果音の時は、少しだけ下げる（duck）。プレイヤーが決めた大きさ（user_volume 0〜1）もかける。
## 前からの使い方（start／stop／is_playing）も、そのまま使える。start は、頼まれている曲（なければ default）を流す。
## 大きさの変化は _process で少しずつ（テストでは step(秒) で進める）。ブラウザでは、最初のタップのあとに鳴り始める。

const CONFIG_PATH := "res://data/bgm.json"
const SILENT := 0.0001

var cfg: Dictionary = {}
var muted := false
var user_volume := 1.0
var players: Array = []  ## 再生口2つ
var levels: Array = [0.0, 0.0]  ## 再生口ごとの今の大きさ（0〜1。フェードの途中）
var targets: Array = [0.0, 0.0]  ## 目ざす大きさ
var speeds: Array = [1.0, 1.0]  ## 1秒に変わる量
var names: Array = ["", ""]  ## 再生口ごとの曲の名前
var front := 0  ## いまの曲を鳴らしている再生口
var player: AudioStreamPlayer = null  ## いまの曲の再生口（前の版のテスト・道具のため）
var track := ""  ## いまの曲（"" なら流していない）
var wanted := ""  ## 流すように頼まれた曲（ミュート中も覚えておく）
var pending := ""  ## 短い曲が終わったら流す曲
var active := false  ## 流すように指示したか（start／play_track で true、stop で false）
var track_t := 0.0  ## いまの曲を流し始めてからの秒
var duck_db := 0.0  ## いまの下げ幅（0 か、負の dB）
var duck_hold := 0.0  ## 下げたままにする残りの秒
var log: Array = []  ## テスト用（流した曲の名前）
var streams := {}


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ready() -> void:
	_ensure_player()


func _ensure_player() -> void:
	if not players.is_empty():
		return
	if cfg.is_empty():
		cfg = load_config()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % i
		p.volume_db = -80.0
		add_child(p)
		players.append(p)
	player = players[0]


func tracks() -> Dictionary:
	return cfg.get("tracks", {})


func track_cfg(name: String) -> Dictionary:
	return tracks().get(name, {})


func is_loop(name: String) -> bool:
	return bool(track_cfg(name).get("loop", true))


## 曲の音（ループの設定もする）。なければ null
func stream_of(name: String) -> AudioStream:
	if streams.has(name):
		return streams[name]
	var def := track_cfg(name)
	if def.is_empty():
		return null
	var st := load(str(def.get("file", ""))) as AudioStream
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = is_loop(name)
	elif st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD if is_loop(name) else AudioStreamWAV.LOOP_DISABLED
	streams[name] = st
	return st


## プレイヤーが決めた大きさ（0〜1）。0 にすると止め、0 からもどすと、頼まれている曲を流し直す
func set_user_volume(v: float) -> void:
	var was_off := user_volume <= 0.001
	user_volume = clampf(v, 0.0, 1.0)
	if user_volume <= 0.001:
		_silence()
	elif was_off and active and wanted != "":
		play_track(wanted, float(cfg.get("start_fade_sec", 0.4)))
	_apply_volumes()


## すぐに全部止める（頼まれている曲は覚えておく）
func _silence() -> void:
	track = ""
	pending = ""
	for i in players.size():
		levels[i] = 0.0
		targets[i] = 0.0
		names[i] = ""
		(players[i] as AudioStreamPlayer).stop()


## 曲を流す。fade：入れかえる秒（負なら data の fade_sec。0 ですぐ）。流したら（または、短い曲のあとに流す予約をしたら）true
func play_track(name: String, fade: float = -1.0) -> bool:
	_ensure_player()
	wanted = name
	active = true
	if muted or user_volume <= 0.001:
		_silence()
		return false
	var st := stream_of(name)
	if st == null:
		return false
	if fade < 0.0:
		fade = float(cfg.get("fade_sec", 1.0))
	# 勝ち・負けの短い曲を流している最中：ループする曲は、終わってから
	if track != "" and not is_loop(track) and is_loop(name) and track_t < _length(track) - 0.05:
		pending = name
		return true
	pending = ""
	if name == track and (players[front] as AudioStreamPlayer).playing:
		targets[front] = 1.0
		speeds[front] = 1.0 / maxf(fade, 0.01)
		return true
	# 前の曲は小さくして止める。次の曲は、もう1つの再生口で始める
	var old := front
	targets[old] = 0.0
	speeds[old] = 1.0 / maxf(fade if is_loop(name) else float(cfg.get("jingle_fade_sec", 0.25)), 0.01)
	front = 1 - old
	var p := players[front] as AudioStreamPlayer
	p.stream = st
	names[front] = name
	levels[front] = 0.0 if fade > 0.0 else 1.0
	targets[front] = 1.0
	speeds[front] = 1.0 / maxf(fade if fade > 0.0 else 0.01, 0.01)
	player = p
	track = name
	track_t = 0.0
	_apply_volumes()
	p.play()
	log.append(name)
	if log.size() > 32:
		log = log.slice(16)
	return true


## 流し始める（頼まれている曲。なければ default）。流したら true（ミュート中や音がないときは false）
func start() -> bool:
	_ensure_player()
	var name := wanted if wanted != "" else str(cfg.get("default", "lobby"))
	if active and track == name and not muted:
		return true
	return play_track(name, float(cfg.get("start_fade_sec", 0.4)))


## 止める。fade：小さくしていく秒（0 ですぐ）
func stop(fade: float = 0.0) -> void:
	active = false
	track = ""
	pending = ""
	for i in players.size():
		targets[i] = 0.0
		if fade <= 0.0:
			levels[i] = 0.0
			(players[i] as AudioStreamPlayer).stop()
		else:
			speeds[i] = 1.0 / fade


## 流している状態か（流すように指示して、止めていない）。
## 音の再生そのもの（player.playing）は、音の処理の都合で、play() の直後に一瞬 false のことがある（画面なしのテストで、まれに落ちていた原因）。
## そのため、ゲームが決めた状態を返す
func is_playing() -> bool:
	return not players.is_empty() and active and track != ""


## 少しのあいだ音楽を下げる（db は負。重ねた時は、大きく下げる方）。hold：下げたままの秒
func duck(db: float, hold: float = 0.15) -> void:
	duck_db = minf(duck_db, db)
	duck_hold = maxf(duck_hold, hold)
	_apply_volumes()


func _process(delta: float) -> void:
	step(delta)


## 時間を進める（フェード・下げたあとに戻す・短い曲の終わり）
func step(delta: float) -> void:
	if players.is_empty():
		return
	for i in players.size():
		levels[i] = move_toward(float(levels[i]), float(targets[i]), float(speeds[i]) * delta)
		if float(levels[i]) <= 0.0 and float(targets[i]) <= 0.0 and (players[i] as AudioStreamPlayer).playing:
			(players[i] as AudioStreamPlayer).stop()
	var rest := delta
	if duck_hold > 0.0:
		var used := minf(duck_hold, rest)
		duck_hold -= used
		rest -= used
	if duck_hold <= 0.0 and duck_db < 0.0:
		duck_db = minf(0.0, duck_db + rest * absf(float(cfg.get("duck_db_per_sec", 20.0))))
	if track != "":
		track_t += delta
		if not is_loop(track) and track_t >= _length(track):
			# 短い曲が終わった：予約していた曲を流す（なければ、そのまま静かに）
			var next := pending
			pending = ""
			if next != "":
				play_track(next, float(cfg.get("after_jingle_fade_sec", 1.5)))
	_apply_volumes()


func _length(name: String) -> float:
	var st := stream_of(name)
	return st.get_length() if st != null else 0.0


func _apply_volumes() -> void:
	for i in players.size():
		var base := float(track_cfg(str(names[i])).get("volume_db", -14.0))
		var lv := maxf(float(levels[i]), SILENT)
		(players[i] as AudioStreamPlayer).volume_db = base + linear_to_db(lv) + duck_db + linear_to_db(maxf(user_volume, SILENT))
