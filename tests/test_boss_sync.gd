extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_boss_sync.gd
## ボスの体力の共有の計算（boss_sync.gd）と、ダメージの橋渡し（room_bridge.gd）を確かめる。

const BossSync := preload("res://scripts/network/boss_sync.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")

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

	# 抜けた人のダメージは数えない
	check(is_equal_approx(BossSync.others_total(hits, "p1", ["p1", "p2"]), 20.0), "いる人（p2）だけ数える。抜けた人（p3）は数えない")
	check(is_equal_approx(BossSync.others_total(hits, "p1", []), 25.0), "いる人の一覧が空なら、全員分を数える")

	# 全員ダウン（体力の記録は {hp, round}。今の戦い R のものだけ数える）
	var R := 5000.0
	var m2 := ["p1", "p2"]
	check(not BossSync.all_down(10.0, {"p2": {"hp": 0.0, "round": R}}, "p1", m2, R), "自分が生きていれば、全滅ではない")
	check(BossSync.all_down(0.0, {"p2": {"hp": 0.0, "round": R}}, "p1", m2, R), "自分もほかの人もダウンなら、全滅")
	check(not BossSync.all_down(0.0, {"p2": {"hp": 30.0, "round": R}}, "p1", m2, R), "ほかの人が生きていれば、全滅ではない")
	check(BossSync.all_down(0.0, {}, "p1", m2, R), "この戦いの体力が届いていない人（出ていない人）は、数えない")
	check(BossSync.all_down(0.0, {"p2": {"hp": 50.0, "round": 4000.0}}, "p1", m2, R), "前の戦いの古い記録は、数えない")
	check(BossSync.all_down(0.0, {"p2": {"hp": 0.0, "round": R}, "p3": {"hp": 80.0, "round": 1.0}}, "p1", ["p1", "p2", "p3"], R), "古い記録を残した幽霊（p3）がいても、全滅になる")
	check(BossSync.all_down(0.0, {"p3": {"hp": 50.0, "round": R}}, "p1", ["p1"], R), "抜けた人（p3）の体力は見ない")
	check(BossSync.all_down(0.0, null, "p1", ["p1"], R), "体力の一覧が壊れていても、1人なら全滅")
	check(BossSync.others_hp({"p2": {"hp": 40, "round": R}, "p3": 20.0}, "p1", ["p1", "p2", "p3"], R) == {"p2": 40.0}, "古い形（数だけ）の記録は、数えない")

	# ボスの攻撃の予定
	check(Pattern.strike_index(0.0, 3.0, 4.0) == 0 and Pattern.strike_index(2.9, 3.0, 4.0) == 0, "最初の一撃の前は、0回")
	check(Pattern.strike_index(3.0, 3.0, 4.0) == 1, "最初の一撃の時刻で、1回")
	check(Pattern.strike_index(6.9, 3.0, 4.0) == 1 and Pattern.strike_index(7.0, 3.0, 4.0) == 2, "そのあと、4秒ごとに増える")
	check(Pattern.strike_index(-1.0, 3.0, 4.0) == 0 and Pattern.strike_index(5.0, 3.0, 0.0) == 0, "時刻がマイナス・間隔が0なら、0回")
	check(Pattern.telegraph_progress(0.0, 3.0, 4.0, 1.2) == -1.0, "予告の前は -1")
	check(is_equal_approx(Pattern.telegraph_progress(1.8, 3.0, 4.0, 1.2), 0.0), "予告の始まりは 0")
	check(is_equal_approx(Pattern.telegraph_progress(2.4, 3.0, 4.0, 1.2), 0.5), "予告の途中は 0.5")
	check(Pattern.telegraph_progress(3.0, 3.0, 4.0, 1.2) == -1.0, "一撃のあと、次の予告までは -1")
	check(is_equal_approx(Pattern.telegraph_progress(6.4, 3.0, 4.0, 1.2), 0.5), "2回目の予告の途中も 0.5")
	check(Pattern.telegraph_progress(-1.0, 3.0, 4.0, 1.2) == -1.0, "時刻がマイナスなら -1")

	# ボスの体力
	check(is_equal_approx(BossSync.boss_hp(100.0, 30.0, 25.0), 45.0), "体力 = 最大 − 自分 − ほかの人")
	check(BossSync.boss_hp(100.0, 80.0, 40.0) == 0.0, "体力は0より小さくならない")
	check(BossSync.boss_hp(100.0, 0.0, 0.0) == 100.0, "誰も当てていなければ、最大のまま")

	# 橋渡し
	check(Bridge.build_send_hits_call(30.0) == "window.bbFirebase.sendHits(30.0)", "ダメージを送る呼び出し：%s" % Bridge.build_send_hits_call(30.0))
	check(Bridge.build_send_hp_call(75.0, 5000.0) == "window.bbFirebase.sendHp(75.0, 5000.0)", "体力を送る呼び出し")
	check(Bridge.build_start_round_call() == "window.bbFirebase.startRound()", "戦いを始める呼び出し")
	var log: Array = []
	var bridge := Bridge.new()
	bridge.js_eval = func(code: String) -> Variant:
		log.append(code)
		return null
	bridge.send_hits(12.5)
	check(log.size() == 1 and str(log[0]).begins_with("window.bbFirebase.sendHits(12.5"), "send_hits が、JSを呼ぶ")
	bridge.send_hp(60.0, 5000.0)
	bridge.start_round()
	check(log.size() == 3 and str(log[1]).begins_with("window.bbFirebase.sendHp(60") and str(log[2]) == "window.bbFirebase.startRound()", "send_hp と start_round が、JSを呼ぶ")

	# 入り口（head_include）にダメージの送受信がある（3つの書き出しすべて）
	var cf := ConfigFile.new()
	check(cf.load("res://export_presets.cfg") == OK, "export_presets.cfg が読める")
	for preset in ["preset.1.options", "preset.2.options", "preset.3.options"]:
		var head: String = str(cf.get_value(preset, "html/head_include", ""))
		check(head.contains("sendHits") and head.contains("/hits") and head.contains("sendHp") and head.contains("startRound") and head.contains("serverTimeOffset"), "%s の入り口に、ダメージ・体力・開始の時刻の送受信がある" % preset)
	var h1 := str(cf.get_value("preset.1.options", "html/head_include", ""))
	check(h1 == str(cf.get_value("preset.2.options", "html/head_include", "")) and h1 == str(cf.get_value("preset.3.options", "html/head_include", "")), "3つの入り口（JS）が同じ内容")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
