extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v117.gd
## 版117：全体の見直し。結果にタイムとダメージ・横画面のはじめの画面（名前とボタンが重ならない）・横画面で結果やハイライトがはみ出さない・スティックの見た目。

const Flow := preload("res://scripts/flow/game_flow.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const ResultUI := preload("res://scripts/flow/result_ui.gd")
const SCENE := "res://scenes/game_flow.tscn"
const UiKit := preload("res://scripts/ui/ui_kit.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	check(ResultUI._comma(1234) == "1,234" and ResultUI._comma(12) == "12" and ResultUI._comma(1234567) == "1,234,567", "数字に3けたごとの「,」")
	var st: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json")) as Dictionary).get("stick_style", {})
	check(st.has("ring") and st.has("knob"), "スティックの見た目の設定（暗い円・輪・つまみ）")

	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v117_save.json"
	flow.config["ai_picks_path"] = "user://test_v117_ai.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v117_save.json"))
	root.add_child(flow)
	if flow.panels.is_empty():
		flow._ready()

	# ---- 1. 結果：タイムとダメージ ----
	flow.goto(Logic.LOBBY)
	flow.last_stats = {"sec": 95.4, "damage": 1234.6}
	flow._on_round_ended(true)
	flow.goto(Logic.REWARD)
	var sl: Label = flow.result_ui.stats_label
	check(sl.visible and sl.text.contains("1:35") and sl.text.contains("1,234"), "結果に、タイムとダメージ（%s）" % sl.text)
	flow.last_stats = {}
	flow.goto(Logic.LOBBY)
	flow._on_round_ended(false)
	flow.goto(Logic.REWARD)
	check(not flow.result_ui.stats_label.visible, "記録がなければ、タイムとダメージは出さない")

	# ---- 2. 横画面：はじめの画面の名前とボタンが重ならない・画面の中 ----
	for sz in [Vector2(1152, 648), Vector2(648, 1152), Vector2(1402, 648)]:
		var r: Control = flow.panels[Logic.START]
		r.size = sz
		flow.start_ui.layout()
		var logo := r.get_node("Logo") as Control
		var lr := Rect2(logo.position, logo.size * logo.scale)
		var br := Rect2(flow.start_ui.buttons_col.position, flow.start_ui.buttons_col.size)
		check(lr.end.y <= br.position.y + 1.0 and lr.position.y >= 0.0 and br.end.y <= sz.y + 1.0, "%s：名前（上）とボタン（下）が重ならない・画面の中" % str(sz))

	# ---- 3. 横画面：まん中に並べた画面（結果・ハイライト）が、はみ出さない（小さくして入れる）----
	var rr := Control.new()
	rr.size = Vector2(1152, 648)
	root.add_child(rr)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in 6:
		var c := Control.new()
		c.custom_minimum_size = Vector2(500, 150)
		box.add_child(c)
	rr.add_child(box)
	UiKit.fit_center(box, rr)
	for k in 4:
		await process_frame
	var need := box.get_combined_minimum_size().y * box.scale.y
	check(box.scale.y < 1.0 and need <= 648.0 + 1.0, "横画面：中身（%.0f px）が高すぎる時は、小さくして入れる（%.2f 倍）" % [box.get_combined_minimum_size().y, box.scale.y])
	rr.size = Vector2(648, 1152)
	for k in 3:
		await process_frame
	check(is_equal_approx(box.scale.y, 1.0), "たて画面で入る時は、そのままの大きさ（%.2f 倍）" % box.scale.y)
	rr.queue_free()
	var reward_root: Control = flow.panels[Logic.REWARD]
	var has_fit := false
	for c in reward_root.get_children():
		if c is VBoxContainer and (c as Control).grow_vertical == Control.GROW_DIRECTION_BOTH:
			has_fit = true
	check(has_fit, "結果の画面は、画面に入るように小さくするしくみを使う")
	root.remove_child(flow)
	flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v117_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v117_ai.json"))
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
