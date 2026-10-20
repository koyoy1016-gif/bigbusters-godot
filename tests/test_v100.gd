extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v100.gd
## 版100（軽量化 B-1）：街灯の光の輪（版98 から夜まで隠している）を、戦いの画面ができた直後の数コマだけ出しておく。
## はじめて描く時の準備（シェーダー作り）を、覚醒の瞬間ではなく、戦いの始まり（「はじめる」を押す前）にすませるため。
## 確かめること：
##   1. コマの数は data/maps.json の time_of_day.pool_warm_frames
##   2. 戦いの画面ができた直後は、光の輪が出ている。でも夕方の強さは 0 なので、見た目は何も変わらない（光を足す量が 0）
##   3. そのコマ数がすぎると隠れる。戦いが始まっても（夕方のまま）隠れたまま
##   4. 覚醒（夜）では、前と同じように出る

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const MapLoader := preload("res://scripts/stage/map_loader.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func pools_visible(pools: Array) -> bool:
	for m in pools:
		if not (m as Node3D).visible:
			return false
	return not pools.is_empty()


func _initialize() -> void:
	var mc := MapLoader.current_map()
	var warm := int((mc["time_of_day"] as Dictionary).get("pool_warm_frames", 0))
	check(warm >= 1 and warm <= 5, "先に描くコマの数は data/maps.json の time_of_day.pool_warm_frames（%d）" % warm)
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.sfx = null
	s.set_process(false)
	var pools: Array = s.map_root.get_meta("light_pools", [])
	check(pools_visible(pools), "戦いの画面ができた直後：光の輪が出ている（はじめて描く準備のため）")
	var mat := (pools[0] as MeshInstance3D).material_override as ShaderMaterial
	var strength := lerpf(float(mat.get_shader_parameter("strength")), float(mat.get_shader_parameter("strength_night")), float(mat.get_shader_parameter("night")))
	check(is_zero_approx(strength) and is_zero_approx(float(mc["lamps"]["pool"])), "その間の光の強さは 0（光を足す量が 0 ＝ 見た目は何も変わらない）")
	var frames := 0
	while pools_visible(pools) and frames < 20:
		s._time_of_day_update(1.0 / 60.0)
		frames += 1
	check(frames == warm, "%d コマで隠れる" % frames)
	s.start_round()
	for i in 30:
		s._time_of_day_update(1.0 / 60.0)
	check(not pools_visible(pools), "戦いが始まっても、夕方の間は隠れたまま")
	s.phase.phase = BossPhase.AWAKE
	for i in 120:
		s._time_of_day_update(1.0 / 60.0)
	check(pools_visible(pools), "覚醒（夜）では、前と同じように出る")
	s.queue_free()
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
