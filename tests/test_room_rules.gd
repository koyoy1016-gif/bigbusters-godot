extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_room_rules.gd
## ルールのファイル（案）の形と、data/network.json との一致を確かめる。
## ルールの動作そのもの（誰が書けるか）は、このテストでは確かめられない。
## Firebaseコンソールの「ルールのプレイグラウンド」と、実機で確かめる。

const RoomCode := preload("res://scripts/network/room_code.gd")
const RULES_PATH := "res://firebase/database.rules.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _first_group(pattern: String, text: String) -> String:
	var re := RegEx.new()
	re.compile(pattern)
	var m := re.search(text)
	return m.get_string(1) if m else ""


func _initialize() -> void:
	var cfg: Dictionary = RoomCode.load_config()
	var text := FileAccess.get_file_as_string(RULES_PATH)
	check(text != "", "ルールのファイルがある")
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary and parsed.has("rules"), "JSONとして読めて、rules がある")
	if not (parsed is Dictionary and parsed.has("rules")):
		print("失敗: ", failures)
		quit(1)
		return
	var rules: Dictionary = parsed["rules"]

	# 全体は、読み書きとも拒否
	check(rules.get(".read") == false and rules.get(".write") == false, "全体の読み書きは拒否（テストモードではない）")
	check(not text.contains('"true"') and not text.contains(": true"), "どこにも true（誰でも可）がない")
	check(not text.contains("now <") and not text.contains("now >"), "期限つきの全開放（テストモードの形）がない")

	# 部屋
	var rooms: Dictionary = rules.get("rooms", {})
	check(not rooms.has(".read") and not rooms.has(".write"), "rooms 全体の一覧は、読めない・書けない")
	var code: Dictionary = rooms.get("$code", {})
	check(str(code.get(".read", "")).contains("auth != null"), "部屋の中を読めるのは、ログイン済みの人だけ")
	check(not code.has(".write"), "部屋の直下には、書き込みの許可がない")
	var code_validate := str(code.get(".validate", ""))
	check(code_validate.contains("^[0-9]"), "合言葉は数字だけ（ルールでも検査）")
	check(_first_group("\\{(\\d+)\\}", code_validate) == str(int(cfg["code_digits"])), "合言葉の桁数が network.json と一致（%s桁）" % str(int(cfg["code_digits"])))

	# 参加者
	var uid_rules: Dictionary = code.get("players", {}).get("$uid", {})
	check(str(uid_rules.get(".write", "")) == "auth != null && auth.uid === $uid", "書けるのは、ログイン済みで、自分のuidの場所だけ")
	var validate := str(uid_rules.get(".validate", ""))
	check(_first_group("numChildren\\(\\) < (\\d+)", validate) == str(int(cfg["max_players"])), "人数の上限が network.json と一致（%s人）" % str(int(cfg["max_players"])))
	check(validate.contains("data.exists()"), "すでにいる人の上書きは、人数に数えない")
	check(validate.contains("!newData.exists()"), "自分の場所を消す（出る）ことはできる")
	check(validate.contains("joinedAt") and validate.contains("=== now"), "joinedAt はサーバーの時刻")
	check(uid_rules.get("$other", {}).get(".validate") == false, "joinedAt 以外の項目は書けない")
	check(uid_rules.get("joinedAt", {}).get(".validate") == "newData.isNumber()", "joinedAt は数値")

	# 使っている場所の名前が、関数の組み立てと同じ
	check(code.has("players") and RoomCode.room_path("1234", int(cfg["code_digits"])) == "rooms/1234" and rooms.has("$code"), "rooms/{合言葉} の形が、関数と一致")

	# 適用していない（Firebase CLIの設定がない）
	check(not FileAccess.file_exists("res://firebase.json"), "firebase.json がない（このファイルは、まだ適用していない）")
	for word in ["private_key", "client_secret", "BEGIN PRIVATE KEY"]:
		check(not text.contains(word), "ルールに「%s」が含まれない" % word)

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
