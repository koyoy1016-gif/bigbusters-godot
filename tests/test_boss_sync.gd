extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_boss_sync.gd
## ボスの体力の共有の計算（boss_sync.gd）と、ダメージの橋渡し（room_bridge.gd）を確かめる。

const BossSync := preload("res://scripts/network/boss_sync.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	# 自分以外の合計
	var hits := {"p1": 30.0, "p2": 20.0, "p3": 5.0}
	check(is_equal_approx(BossSync.others_total(hits, "p1"), 25.0), "自分（p1）を除いた合計")
	check(is_equal_approx(BossSync.others_total(hits, "p4"), 55.0), "自分が枠にいなければ、全員の合計")
	check(BossSync.others_total({}, "p1") == 0.0, "誰もいなければ0")
	check(BossSync.others_total(null, "p1") == 0.0, "壊れた値（null）は0")
	check(BossSync.others_total("abc", "p1") == 0.0, "壊れた値（文字）は0")
	check(is_equal_approx(BossSync.others_total({"p1": "x", "p2": -5.0, "p3": 7}, ""), 7.0), "数でない値と、マイナスは捨てる（整数は数える）")

	# ボスの体力
	check(is_equal_approx(BossSync.boss_hp(100.0, 30.0, 25.0), 45.0), "体力 = 最大 − 自分 − ほかの人")
	check(BossSync.boss_hp(100.0, 80.0, 40.0) == 0.0, "体力は0より小さくならない")
	check(BossSync.boss_hp(100.0, 0.0, 0.0) == 100.0, "誰も当てていなければ、最大のまま")

	# 橋渡し
	check(Bridge.build_send_hits_call(30.0) == "window.bbFirebase.sendHits(30.0)", "ダメージを送る呼び出し：%s" % Bridge.build_send_hits_call(30.0))
	var log: Array = []
	var bridge := Bridge.new()
	bridge.js_eval = func(code: String) -> Variant:
		log.append(code)
		return null
	bridge.send_hits(12.5)
	check(log.size() == 1 and str(log[0]).begins_with("window.bbFirebase.sendHits(12.5"), "send_hits が、JSを呼ぶ")

	# 入り口（head_include）にダメージの送受信がある（3つの書き出しすべて）
	var cf := ConfigFile.new()
	check(cf.load("res://export_presets.cfg") == OK, "export_presets.cfg が読める")
	for preset in ["preset.1.options", "preset.2.options", "preset.3.options"]:
		var head: String = str(cf.get_value(preset, "html/head_include", ""))
		check(head.contains("sendHits") and head.contains("/hits"), "%s の入り口に、ダメージの送受信がある" % preset)
	var h1 := str(cf.get_value("preset.1.options", "html/head_include", ""))
	check(h1 == str(cf.get_value("preset.2.options", "html/head_include", "")) and h1 == str(cf.get_value("preset.3.options", "html/head_include", "")), "3つの入り口（JS）が同じ内容")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
