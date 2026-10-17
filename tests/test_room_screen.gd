extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_room_screen.gd
## 4桁の入力、状態からの画面の文字、文字がフォントにあるか、書き出しの設定を確かめる。
## 入退室そのものは tests/js/room_bridge.test.mjs（JS）で確かめる。

const Screen := preload("res://scripts/network/room_screen.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const UI_PATH := "res://data/room_screen.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var ui := CheckScreen.load_json(UI_PATH)
	var texts: Dictionary = ui["texts"]
	check(not ui.is_empty(), "画面の文字（room_screen.json）が読める")

	# 入力：4桁まで、数字だけ、消せる
	var code := ""
	for d in ["1", "2", "a", "3", "4", "5"]:
		code = Screen.append_digit(code, d, 4)
	check(code == "1234", "数字だけを4桁まで入れる（%s）" % code)
	check(Screen.delete_digit(code) == "123", "1つ消せる")
	check(Screen.delete_digit("") == "", "空でも消しても落ちない")
	check(Screen.display_code("12", 4, "_") == "12__", "入力中は、残りを _ で出す")
	check(Screen.display_code("1234", 4, "_") == "1234", "4桁そろえば、そのまま出す")
	var cfg: Dictionary = RoomCode.load_config()
	check(RoomCode.is_valid_code(Screen.append_digit("", "9", 4), int(cfg["code_digits"])) == false, "1桁だけでは、部屋に入れる合言葉にならない")

	# 状態から、画面の文字
	check(Screen.build_status_text({}, texts) == texts["idle"], "状態がないときは、最初の案内")
	check(Screen.build_status_text({"status": "joining"}, texts) == texts["joining"], "入室中")
	check(Screen.build_status_text({"status": "pending"}, texts) == texts["joining"], "接続中も、入室中と同じ表示")
	check(Screen.build_status_text({"status": "in_room", "slot": "p2", "members": ["p1", "p2"]}, texts) == "部屋に入りました（枠：p2、いま2人）", "入室した：枠と人数")
	check(Screen.build_status_text({"status": "full"}, texts) == texts["full"], "満員")
	check(Screen.build_status_text({"status": "left"}, texts) == texts["left"], "退室した")
	check(Screen.build_status_text({"status": "error", "error": "network down"}, texts) == "うまくいきませんでした：network down", "失敗：エラーの文字が出る")
	check(Screen.build_members_text({"members": []}, texts) == texts["members_none"], "誰もいないときの一覧")
	check(Screen.build_members_text({"members": ["p1", "p3"]}, texts) == "いま部屋にいる枠：p1, p3", "在室の枠を並べる")

	# 画面の文字が、同梱フォントにすべてある（□にならない）
	var font := load(str(ui["ui_font_path"])) as Font
	var missing := ""
	var all_texts: Array = []
	for key in texts:
		all_texts.append(str(texts[key]))
	for key in ui["keys"]:
		all_texts.append(str(key))
	all_texts.append(str(ui["leave_key"]))
	all_texts.append(str(ui["placeholder"]))
	for t in all_texts:
		for ch in str(t).replace("%s", "").replace("%d", ""):
			if not font.has_char(ord(ch)):
				missing += ch
	check(missing == "", "表示する文字がすべてフォントにある（不足: %s）" % missing)
	check((ui["keys"] as Array).size() == 12, "ボタンは12個（1〜9、消す、0、入る）")

	# シーンとプロジェクトの設定
	check(ResourceLoader.exists("res://scenes/experiments/room_screen.tscn"), "画面のシーンがある")
	var project := FileAccess.get_file_as_string("res://project.godot")
	check(project.contains('run/main_scene.room_screen="res://scenes/experiments/room_screen.tscn"'), "画面用の機能タグのときだけ、画面から始まる")
	check(project.contains('run/main_scene="res://scenes/render_test.tscn"'), "起動シーンは render_test のまま")
	var cf := ConfigFile.new()
	check(cf.load("res://export_presets.cfg") == OK, "export_presets.cfg が読める")
	check(str(cf.get_value("preset.2", "name", "")) == "Web (Room check)", "画面用の書き出しプリセットがある")
	check(str(cf.get_value("preset.2", "custom_features", "")) == "room_screen", "画面用の機能タグ room_screen を持つ")
	check(str(cf.get_value("preset.2", "export_path", "")) == "web/room_check/index.html", "画面用の書き出し先")
	var head: String = str(cf.get_value("preset.2.options", "html/head_include", ""))
	check(head.contains("joinRoom") and head.contains("window.bbFirebase"), "画面用の入り口に、入室の処理がある")
	check(head.count("gstatic.com/firebasejs/") == 1, "画面用のSDKも、固定バージョン（1か所）")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
