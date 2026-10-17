extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_position_sync.gd
## 位置の同期の計算（送る間隔、回/秒、なめらかさ、壊れた位置の除外）と、関連する設定・ルールを確かめる。
## 実際の送受信は、tests/js/room_bridge.test.mjs と実機で確かめる。

const Sync := preload("res://scripts/network/position_sync.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const SYNC_PATH := "res://data/position_sync.json"
const RULES_PATH := "res://firebase/database.rules.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := CheckScreen.load_json(SYNC_PATH)
	check(not cfg.is_empty(), "同期の設定（position_sync.json）が読める")
	check(int(cfg["send_interval_ms"]) == 100, "送る間隔は100ミリ秒（約10回/秒）")

	# 送る間隔
	check(Sync.should_send(1000, 900, 100), "100ミリ秒たったら送る")
	check(not Sync.should_send(1000, 950, 100), "100ミリ秒たっていなければ送らない")
	check(Sync.should_send(0, -100000, 100), "最初は必ず送る")

	# 回/秒
	check(is_equal_approx(Sync.rate_per_sec(10, 0, 1.0), 10.0), "10回を1秒で数えたら、10回/秒")
	check(is_equal_approx(Sync.rate_per_sec(25, 5, 2.0), 10.0), "差（20回）を2秒で割ると、10回/秒")
	check(Sync.rate_per_sec(5, 0, 0.0) == 0.0, "経過時間が0なら0（割らない）")

	# なめらかさ
	check(is_equal_approx(Sync.smooth_weight(0.1, 10.0), 1.0), "10/秒で0.1秒なら、全部近づく")
	check(is_equal_approx(Sync.smooth_weight(0.05, 10.0), 0.5), "半分の時間なら、半分近づく")
	check(Sync.smooth_weight(5.0, 10.0) == 1.0, "時間が長くても、1を超えない")

	# 受け取った位置
	var raw := {
		"p1": {"x": 0.25, "y": 0.5, "t": 1},
		"p2": {"x": 0.75, "y": 0.1, "t": 2},
		"p3": {"x": "bad", "y": 0.5, "t": 3},
		"p4": {"y": 0.5},
	}
	var positions := Sync.parse_positions(raw)
	check(positions.size() == 2, "壊れた位置（文字・項目なし）は捨てる（%d件）" % positions.size())
	check(positions["p1"] == Vector2(0.25, 0.5) and positions["p2"] == Vector2(0.75, 0.1), "正しい位置は、そのまま取れる")
	check(Sync.parse_positions(null).is_empty() and Sync.parse_positions("x").is_empty(), "辞書でなければ空")

	# 橋渡しの呼び出し
	check(Bridge.build_send_position_call(0.5, 0.25) == "window.bbFirebase.sendPosition(0.5, 0.25)", "位置の送信の呼び出し")

	# 画面の文字がフォントにある
	var ui := CheckScreen.load_json("res://data/room_screen.json")
	var font := load(str(ui["ui_font_path"])) as Font
	var missing := ""
	for ch in str(cfg["rate_text"]).replace("%f", "").replace("%s", ""):
		if not font.has_char(ord(ch)):
			missing += ch
	check(missing == "", "送受信の表示の文字がフォントにある（不足: %s）" % missing)
	check(str(cfg["rate_text"]) % [10.0, 9.5] == "送信 10.0 回/秒、受信 9.5 回/秒", "送受信の表示が組み立つ")

	# ルール：位置は、自分の枠のときだけ書ける
	var rules_text := FileAccess.get_file_as_string(RULES_PATH)
	var rules = JSON.parse_string(rules_text)
	var pos: Dictionary = rules["rules"]["rooms"]["$code"]["positions"]["$slot"]
	check(str(pos[".write"]).contains("root.child('rooms/' + $code + '/players/' + $slot + '/uid').val() === auth.uid"), "位置は、自分の枠の人だけが書ける")
	check(str(pos[".validate"]).contains("$slot.matches(/^p[1-4]$/)") and str(pos[".validate"]).contains("hasChildren(['x', 'y', 't'])"), "位置の枠は p1〜p4、x・y・t が必要")
	check(pos["$other"][".validate"] == false, "x・y・t 以外は書けない")
	check(pos["x"][".validate"] == "newData.isNumber()" and pos["y"][".validate"] == "newData.isNumber()", "x・y は数値")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
