extends RefCounted
## 版85：戦いの音（ボスの足音・飛ぶ物を撃った音と当たった音・遠いほど小さく・AIの味方の音は小さく）。
## 数値は data/sfx.json の battle と proj_sounds。音を鳴らすのは stick_prototype の sfx（scripts/audio/sfx.gd）。

var b: Node
var last_step := -1  ## ボスが前に足をついた歩数（walk_dist ÷ 1歩の長さ）
var log: Array = []  ## テスト用（鳴らした音と、足し引きした大きさ）


func _init(main: Node) -> void:
	b = main


func cfg() -> Dictionary:
	if b.sfx == null:
		return {}
	return b.sfx.cfg.get("battle", {})


func reset() -> void:
	last_step = -1
	log = []


## 遠いほど小さく（自分からの距離。near_m までは、そのまま。far_m で far_db）
static func distance_db(dist: float, c: Dictionary) -> float:
	var near := float(c.get("near_m", 6.0))
	var far := float(c.get("far_m", 34.0))
	var k := clampf((dist - near) / maxf(far - near, 0.1), 0.0, 1.0)
	return float(c.get("far_db", -15.0)) * k


## 撃った人（slot）の音の足し引き：自分は 0、AIの味方は ai_db（さらに遠いほど小さく）
func slot_db(slot: String, at: Vector2) -> float:
	if slot == "" or slot == str(b._my_slot()):
		return 0.0
	var me := Vector2(b.player.position.x, b.player.position.z)
	return float(cfg().get("ai_db", -8.0)) + distance_db(me.distance_to(at), cfg())


func play(sound: String, add_db: float = 0.0, pitch: float = 1.0) -> void:
	if b.sfx == null or sound == "":
		return
	if b.sfx.play(sound, add_db, pitch):
		log.append([sound, add_db])
		if log.size() > 64:
			log = log.slice(32)


## 飛ぶ物の音（prop → [撃つ音, 当たる音]）。which：0＝撃つ、1＝当たる
func proj_sound(prop: String, which: int) -> String:
	var ps: Dictionary = (b.sfx.cfg if b.sfx != null else {}).get("proj_sounds", {})
	var pair: Variant = ps.get(prop, null)
	if pair is Array and (pair as Array).size() > which:
		return str(pair[which])
	return "" if which == 0 else "hit"


func on_fire(slot: String, prop: String, at: Vector2) -> void:
	play(proj_sound(prop, 0), slot_db(slot, at))


func on_proj_hit(slot: String, prop: String, at: Vector2) -> void:
	play(proj_sound(prop, 1), slot_db(slot, at))


## 毎コマ：ボスが1歩進むたびに足音（速く動いている時だけ。遠いほど小さく）
func update(_delta: float) -> void:
	if b.boss == null or not b.boss.visible or b.motion == null:
		return
	var cycle := 5.5
	if b.boss_model != null:
		cycle = float(b.boss_model.cfg.get("walk_cycle_m", 5.5))
	var stride := maxf(cycle * 0.5, 0.5)
	var idx := int(floor(float(b.motion.walk_dist) / stride))
	if last_step >= 0 and idx != last_step and float(b.motion.speed_now) >= float(cfg().get("step_min_speed", 0.5)) and float(b.motion.height) < 0.3:
		var me := Vector2(b.player.position.x, b.player.position.z)
		var bp := Vector2(b.boss.position.x, b.boss.position.z)
		play("boss_step", distance_db(me.distance_to(bp), cfg()))
	last_step = idx
