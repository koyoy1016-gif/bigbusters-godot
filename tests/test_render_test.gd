extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_render_test.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg: Dictionary = load("res://scripts/experiments/render_test.gd").load_config()
	check(cfg.has("box_count") and int(cfg["box_count"]) == 300, "JSONから箱の数300を読めた")

	var packed := load("res://scenes/render_test.tscn") as PackedScene
	check(packed != null, "シーンが読み込めた")
	var node := packed.instantiate()
	root.add_child(node)  # _ready が走る
	await process_frame
	await process_frame

	check(node.box_nodes.size() == 300, "A：個別の箱が300個")
	check(node.boxes_a.get_child_count() == 300, "A：BoxesAの子が300個")
	check(node.multimesh.instance_count == 300, "B：MultiMeshが300個")
	check(node.get_node_or_null("Light") != null, "ライトがある")
	check(node.get_node_or_null("Ground") != null, "地面がある")
	check(node.info_label.text.contains("FPS") and node.info_label.text.contains("描画回数"), "FPSと描画回数の表示がある")

	check(node.mode == "A" and node.boxes_a.visible and not node.boxes_b.visible, "初期はA")
	node.set_mode("B")
	check(node.mode == "B" and not node.boxes_a.visible and node.boxes_b.visible, "Bに切り替わる")
	var ev := InputEventKey.new()
	ev.keycode = KEY_1
	ev.pressed = true
	node._unhandled_input(ev)
	check(node.mode == "A", "数字キー1でAに戻る")
	ev.keycode = KEY_2
	node._unhandled_input(ev)
	check(node.mode == "B", "数字キー2でBに切り替わる")
	node.set_mode("X")
	check(node.mode == "B", "不正なモードは無視される")
	node.button_a.pressed.emit()
	check(node.mode == "A", "ボタンAで切り替わる")

	check(node.ui_font != null, "日本語フォントが読み込めた")
	var all_text: String = node.info_label.text + node.button_a.text + node.button_b.text
	var missing := ""
	for ch in all_text:
		if ch != "\n" and not node.ui_font.has_char(ord(ch)):
			missing += ch
	check(missing == "", "画面の文字がすべてフォントにある（不足: %s）" % missing)
	for word in "描画回数個別モード":
		check(node.ui_font.has_char(ord(word)), "フォントに「%s」がある" % word)
	check(node.info_label.get_theme_font("font") == node.ui_font, "ラベルにフォントを使っている")
	check(node.button_a.get_theme_font("font") == node.ui_font, "ボタンにフォントを使っている")

	var preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(preset.contains("variant/thread_support=false"), "Web書き出しがスレッドなし")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
