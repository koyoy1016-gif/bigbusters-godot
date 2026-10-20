extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v98.gd
## 版98（軽量化 A-2）：街灯の光の輪は、夜（覚醒）の時だけ出す。夕方は形ごと隠す（見えないのに透明の重ね描きをしない）。
## 確かめること：
##   1. 夕方（ふだん）：光の輪は隠れている。夕方の強さの設定は 0（前の 0.04 もほぼ見えなかった）
##   2. 覚醒で夜へ：切りかえの途中から出る・夜はもちろん出ている（光の強さは前と同じ）
##   3. 夕方にもどると、また隠れる。街灯の頭（光る部分）は、夕方も夜も出ている

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func all_visible(arr: Array, want: bool) -> bool:
	if arr.is_empty():
		return false
	for m in arr:
		if (m as Node3D).visible != want:
			return false
	return true


func _initialize() -> void:
	var mc := MapLoader.current_map()
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.sfx = null
	s.start_round()
	s.set_process(false)
	for i in int(mc["time_of_day"].get("pool_warm_frames", 0)) + 1:
		s._time_of_day_update(1.0 / 60.0)  # 版100：戦いの画面ができた直後の数コマは、先に描くため出している（見えない）。それが終わってから
	var pools: Array = s.map_root.get_meta("light_pools", [])
	var lamps: Array = []
	for mi in s.map_root.find_children("*", "MeshInstance3D", true, false):
		if str(mi.get_meta("map_part", "")) == "Lamps":
			lamps.append(mi)
	check(pools.size() == 1 and is_zero_approx(float(mc["lamps"]["pool"])), "光の輪の形がある・夕方の強さは 0")
	check(all_visible(pools, false), "夕方（ふだん）：光の輪は隠れている（描かない）")
	check(all_visible(lamps, true), "夕方も、街灯の柱と光る頭は出ている")
	s.phase.phase = BossPhase.AWAKE
	var shown_at := -1.0
	var t := 0.0
	while t < 2.0:
		s._time_of_day_update(1.0 / 60.0)
		t += 1.0 / 60.0
		if shown_at < 0.0 and all_visible(pools, true):
			shown_at = t
	check(shown_at > 0.0 and shown_at < 0.5, "覚醒で夜へ：切りかえの早いうち（%.2f 秒）から光の輪が出る" % shown_at)
	check(all_visible(pools, true) and is_equal_approx(float(((pools[0] as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("strength_night")), float(mc["lamps"]["pool_night"])), "夜：光の輪が出ている（夜の強さは前と同じ %.2f）" % float(mc["lamps"]["pool_night"]))
	s.phase.phase = BossPhase.DEAD
	s.won = true
	for i in 240:
		s._time_of_day_update(1.0 / 60.0)
	check(all_visible(pools, false) and all_visible(lamps, true), "夕方にもどると、光の輪はまた隠れる（街灯は出たまま）")
	s.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
