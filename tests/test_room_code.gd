extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_room_code.gd

const RoomCode := preload("res://scripts/network/room_code.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	# 設定値（data/network.json）
	var cfg: Dictionary = RoomCode.load_config()
	check(not cfg.is_empty(), "network.json が読める")
	check(cfg.get("code_digits") is float and int(cfg["code_digits"]) == 4, "合言葉は4桁")
	check(cfg.get("max_players") is float and int(cfg["max_players"]) == 4, "人数の上限は4人")
	check(float(cfg["max_players"]) == floorf(float(cfg["max_players"])) and int(cfg["max_players"]) >= 1, "人数の上限は1以上の整数")
	var digits: int = int(cfg["code_digits"])

	# 合言葉の検査：通るもの
	for code in ["1234", "0000", "9999", "0007", "1000"]:
		check(RoomCode.is_valid_code(code, digits), "合言葉として通る：%s" % code)

	# 合言葉の検査：通らないもの
	var bad := {
		"": "空",
		"123": "3桁",
		"12345": "5桁",
		"abcd": "英字",
		"12a4": "英字が混ざる",
		"12 4": "空白が混ざる",
		" 123": "先頭の空白",
		"1234 ": "末尾の空白",
		"1234\n": "末尾の改行",
		"-123": "マイナス",
		"+123": "プラス",
		"1.23": "小数点",
		"1e23": "指数表記",
		"１２３４": "全角の数字",
		"١٢٣٤": "アラビア・インドの数字",
		"../1": "上の階層へ",
		"1/23": "スラッシュ",
		"12#4": "記号（データベースで使えない文字）",
		"12.4": "ドット",
	}
	for code in bad:
		check(not RoomCode.is_valid_code(code, digits), "合言葉として通らない：%s（%s）" % [code.replace("\n", "\\n"), bad[code]])

	# 桁数は、引数で決まる（コードに4を直接書いていない）
	check(RoomCode.is_valid_code("123", 3), "3桁を指定すれば、3桁が通る")
	check(not RoomCode.is_valid_code("1234", 3), "3桁を指定すれば、4桁は通らない")
	check(not RoomCode.is_valid_code("", 0) and not RoomCode.is_valid_code("1", -1), "桁数が0以下なら、何も通らない")

	# 部屋の場所
	check(RoomCode.room_path("1234", digits) == "rooms/1234", "部屋の場所：rooms/1234")
	check(RoomCode.room_path("0007", digits) == "rooms/0007", "先頭の0が消えない：rooms/0007")
	check(RoomCode.room_path("12345", digits) == "", "不正な合言葉は、空の場所")
	check(RoomCode.room_path("../1", digits) == "", "上の階層を指す合言葉は、空の場所")
	check(RoomCode.room_path("12/4", digits) == "", "スラッシュを含む合言葉は、空の場所")
	check(RoomCode.room_path("", digits) == "", "空の合言葉は、空の場所")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
