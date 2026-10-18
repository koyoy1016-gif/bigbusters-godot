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

	# 参加者（枠は p1〜p4。空いている枠にだけ入れる。枠の数は network.json の max_players と一致）
	var slot_rules: Dictionary = code.get("players", {}).get("$slot", {})
	check(str(slot_rules.get(".write", "")) == "auth != null && (!data.exists() || data.child('uid').val() === auth.uid || (data.child('seen').isNumber() && data.child('seen').val() < now - 60000))", "書けるのは、ログイン済みで、空いている枠か、自分の枠か、書き直されず60秒過ぎた枠だけ")
	check(_first_group("now - (\\d+)", str(slot_rules.get(".write", ""))) == str(int(cfg["hold_seconds"]) * 1000), "枠の保持時間（60秒）が network.json と一致")
	var validate := str(slot_rules.get(".validate", ""))
	check(_first_group("\\^p\\[1-(\\d)\\]", validate) == str(int(cfg["max_players"])), "枠の数が network.json と一致（%s人）" % str(int(cfg["max_players"])))
	check(validate.contains("newData.child('uid').val() === auth.uid"), "枠に入るとき、自分のuidを書く（他人の名前で入れない）")
	check(validate.contains("!newData.exists()"), "自分の枠を消す（出る）ことはできる")
	check(validate.contains("joinedAt"), "joinedAt を必ず書く")
	check(validate.contains("'seen'") and slot_rules.get("seen", {}).get(".validate") == "newData.isNumber()", "seen（最後に生きていた時刻）を必ず書く・数値")
	check(slot_rules.get("uid", {}).get(".validate") == "newData.isString()", "uid は文字")
	check(slot_rules.get("$other", {}).get(".validate") == false, "uid と joinedAt 以外の項目は書けない")
	check(slot_rules.get("joinedAt", {}).get(".validate") == "newData.isNumber()", "joinedAt は数値")

	# 与えたダメージ（hits）：自分の枠にだけ、0以上の数を書ける
	var hits_rules: Dictionary = code.get("hits", {}).get("$slot", {})
	var own_slot_write := "auth != null && root.child('rooms/' + $code + '/players/' + $slot + '/uid').val() === auth.uid"
	check(str(hits_rules.get(".write", "")) == own_slot_write, "ダメージを書けるのは、自分の枠の人だけ（位置と同じ条件）")
	var hits_validate := str(hits_rules.get(".validate", ""))
	check(hits_validate.contains("isNumber()") and hits_validate.contains(">= 0"), "ダメージは0以上の数")
	check(_first_group("\\^p\\[1-(\\d)\\]", hits_validate) == str(int(cfg["max_players"])), "ダメージの枠の数も network.json と一致")

	# 戦いの開始の時刻（round）：部屋にいる人だけが書ける。数値
	var round_rules: Dictionary = code.get("round", {})
	var round_write := str(round_rules.get(".write", ""))
	for slot_name in ["p1", "p2", "p3", "p4"]:
		check(round_write.contains("/players/%s/uid').val() === auth.uid" % slot_name), "開始の時刻は、枠 %s の人なら書ける" % slot_name)
	check(round_write.begins_with("auth != null"), "開始の時刻を書けるのは、ログイン済みの人だけ")
	check(str(round_rules.get(".validate", "")) == "newData.isNumber()", "開始の時刻は数値")

	# 体力（hp）：自分の枠にだけ、0〜1000の数を書ける
	var hp_rules: Dictionary = code.get("hp", {}).get("$slot", {})
	check(str(hp_rules.get(".write", "")) == own_slot_write, "体力を書けるのは、自分の枠の人だけ")
	check(str(hp_rules.get(".validate", "")).contains("hasChildren(['hp', 'round'])"), "体力の記録は {hp, round}")
	check(str(hp_rules.get("hp", {}).get(".validate", "")).contains("<= 1000") and str(hp_rules.get("hp", {}).get(".validate", "")).contains(">= 0"), "体力は0〜1000の数")
	check(str(hp_rules.get("round", {}).get(".validate", "")) == "newData.isNumber()" and hp_rules.get("$other", {}).get(".validate", true) == false, "どの戦いかは数。ほかの項目は書けない")

	# キャラ（chars）：自分の枠にだけ、半角の英数字とアンダーバーの名前（32字まで）を書ける
	var chars_rules: Dictionary = code.get("chars", {}).get("$slot", {})
	check(str(chars_rules.get(".write", "")) == own_slot_write, "キャラを書けるのは、自分の枠の人だけ")
	check(str(chars_rules.get(".validate", "")).contains("isString()") and str(chars_rules.get(".validate", "")).contains("{1,32}"), "キャラの名前は、32字までの文字")
	check(_first_group("\\^p\\[1-(\\d)\\]", str(chars_rules.get(".validate", ""))) == str(int(cfg["max_players"])), "キャラの枠の数も network.json と一致")

	# 投票（votes）：{v: rematch か lobby, round}
	var votes_rules: Dictionary = code.get("votes", {}).get("$slot", {})
	check(str(votes_rules.get(".write", "")) == own_slot_write, "投票を書けるのは、自分の枠の人だけ")
	check(str(votes_rules.get(".validate", "")).contains("hasChildren(['v', 'round'])"), "投票の記録は {v, round}")
	check(str(votes_rules.get("v", {}).get(".validate", "")).contains("'rematch'") and str(votes_rules.get("v", {}).get(".validate", "")).contains("'lobby'"), "投票は rematch か lobby だけ")
	check(votes_rules.get("round", {}).get(".validate", "") == "newData.isNumber()" and votes_rules.get("$other", {}).get(".validate", true) == false, "どの戦いのあとかは数。ほかの項目は書けない")

	# 効果（effects）：味方に効く技の記録 {type, t, value, round}
	var fx_rules: Dictionary = code.get("effects", {}).get("$slot", {})
	check(str(fx_rules.get(".write", "")) == own_slot_write, "効果を書けるのは、自分の枠の人だけ")
	check(str(fx_rules.get(".validate", "")).contains("hasChildren(['type', 't', 'value', 'round'])"), "効果の記録は {type, t, value, round}")
	check(str(fx_rules.get("value", {}).get(".validate", "")).contains("<= 1000") and fx_rules.get("$other", {}).get(".validate", true) == false, "効果の数値は上限つき。ほかの項目は書けない")

	# 使っている場所の名前が、関数の組み立てと同じ
	check(code.has("players") and RoomCode.room_path("1234", int(cfg["code_digits"])) == "rooms/1234" and rooms.has("$code"), "rooms/{合言葉} の形が、関数と一致")

	# 適用していない（Firebase CLIの設定がない）
	check(not FileAccess.file_exists("res://firebase.json"), "firebase.json がない（このファイルは、まだ適用していない）")
	for word in ["private_key", "client_secret", "BEGIN PRIVATE KEY"]:
		check(not text.contains(word), "ルールに「%s」が含まれない" % word)

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
