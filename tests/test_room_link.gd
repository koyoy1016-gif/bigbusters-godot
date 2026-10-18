extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_room_link.gd
## 部屋の合言葉の自動生成と、しょうたいURL（room_link.gd、game_flow.gd）を確かめる。

const RoomLink := preload("res://scripts/network/room_link.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const SCENE := "res://scenes/game_flow.tscn"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	var all_valid := true
	for i in 200:
		var c := RoomLink.generate_code(4, rng)
		all_valid = all_valid and RoomCode.is_valid_code(c, 4)
		seen[c] = true
	check(all_valid, "自動の合言葉は、いつも4桁の数字")
	check(seen.size() > 150, "自動の合言葉は、毎回ちがう（200回で150種類以上）")
	check(RoomLink.pick("0042", 4, rng) == {"code": "0042", "from_url": true}, "URLの合言葉があれば、それを使う")
	check(RoomLink.pick(null, 4, rng)["from_url"] == false and RoomCode.is_valid_code(RoomLink.pick(null, 4, rng)["code"], 4), "URLになければ、新しく作る")
	check(RoomLink.pick("12ab", 4, rng)["from_url"] == false and RoomLink.pick("123", 4, rng)["from_url"] == false, "URLの合言葉が不正なら、新しく作る")
	check(RoomLink.build_url("https://x.github.io/bb/stick/", "1234") == "https://x.github.io/bb/stick/?room=1234", "しょうたいURL")
	check(RoomLink.build_url("https://x.github.io/bb/stick/?room=9999#a", "1234") == "https://x.github.io/bb/stick/?room=1234", "もとの ? や # は捨てる")
	var call := RoomLink.build_share_call("https://x/?room=1234", {"title": "T\"q"})
	check(call.begins_with("window.bbShare.show(\"https://x/?room=1234\", ") and call.contains("\\\"q"), "ブラウザ側の呼び出し（引用符もこわれない）")

	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	var log: Array = []
	flow.js_eval = func(code: String) -> Variant:
		log.append(code)
		if code == "typeof window":
			return "object"
		if code.contains("URLSearchParams"):
			return "5678"
		if code.contains("location.origin"):
			return "https://x.github.io/bb/stick/"
		return null
	root.add_child(flow)
	if flow.config.is_empty():
		flow._ready()
	flow.init_room()
	check(flow.room_code == "5678" and flow.room_from_url, "しょうたいURLで来たら、その部屋になる")
	flow.goto("lobby")
	check(flow.room_label.text.contains("5678") and flow.room_label.text.contains(str(flow.config["room_from_url_note"])), "ロビーに、しょうたいされた部屋の合言葉が出る")
	flow.invite()
	check(log.any(func(c): return str(c).begins_with("window.bbShare.show(\"https://x.github.io/bb/stick/?room=5678\"")), "「しょうたい」で、この部屋のURLのおくる画面が出る")
	flow.new_room()
	check(flow.room_code != "5678" and not flow.room_from_url and flow.room_label.text.contains(flow.room_code), "「あたらしいへや」で、べつの合言葉になる")
	flow.goto("battle")
	check(flow.battle != null and flow.battle.forced_room_code == flow.room_code, "戦いは、この合言葉の部屋に入る")
	flow.goto("lobby")
	flow.js_eval = func(code: String) -> Variant: return null
	flow.toast_label.text = ""
	flow.invite()
	check(flow.toast_label.text == str(flow.config["invite_offline_note"]), "ブラウザ以外では、案内を出して壊れない")
	root.remove_child(flow)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
