extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v116.gd
## 版116：演出。ボス ダウン・激昂（ボスの怒りが始まった時）・撃破・全滅の大きな見出し／自分が倒れた時の DOWN と板／復活！／仲間のお知らせ。
## 前の「ボスが おこった」（45秒からずっと点めつ）はやめた。ボスの体力の表示に名前と「激昂」。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func count(arr: Array, prefix: String) -> int:
	return arr.filter(func(x: Variant) -> bool: return str(x).begins_with(prefix)).size()


func make() -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_enabled = true
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [7000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.set_meta("now", now)
	s.sfx = null
	s.start_round()
	return s


func _initialize() -> void:
	var s := make()
	var hl: Dictionary = s.config["headlines"]
	for k in ["boss_down", "rage", "win", "lose"]:
		check(hl.has(k) and str(hl[k]["title"]) != "" and str(hl[k]["sub"]) != "", "見出し %s：英字と日本語（%s／%s）" % [k, hl.get(k, {}).get("title", ""), hl.get(k, {}).get("sub", "")])

	# ---- 1. ボス ダウン：前の「ボスが たおれた！」の字の代わり ----
	s._on_boss_fall()
	check(str(s.headline.get("kind", "")) == "boss_down" and float(s.headline["left"]) > 0.0, "ボスが倒れると、BOSS DOWN の見出し")
	check(float(s.phase_text["left"]) <= 0.0 or str(s.phase_text["text"]) == "", "前の「ボスが たおれた！」の字は出さない")
	# 大事な見出しは、下の物で消さない（ダウンの最中に激昂が来ても、ダウンのまま）
	s.show_headline("rage")
	check(str(s.headline["kind"]) == "boss_down", "大事な見出し（ダウン）の間は、激昂で上書きしない")
	s.update_cues(10.0)
	check(float(s.headline["left"]) == 0.0, "少したつと、見出しは消える")

	# ---- 2. 激昂：ボスの怒り（boss_rage）が始まった時だけ。続けて出さない ----
	var log0 := count(s.cue_log, "headline:rage")
	s.was_angry = false
	s.rage_cue_after = 0.0
	s.ai.angry = true
	# combat_update の中の判定と同じ：怒りが始まった（false → true）
	var t: float = s._round_t()
	if s.ai.angry and not s.was_angry and t >= s.rage_cue_after:
		s.show_headline("rage")
		s.rage_cue_after = t + float(hl["rage"]["min_gap_sec"])
	s.was_angry = true
	check(count(s.cue_log, "headline:rage") == log0 + 1 and str(s.headline["kind"]) == "rage", "怒りが始まると、RAGE（激昂）の見出し")
	check(bool(s.hp_hud.boss_view()["angry"]), "怒っている間は、ボスの体力の表示に「激昂」")
	check(str(s.hp_hud.boss_view()["label"]).contains(str(s.config["enemy_intro"]["name"])), "ボスの体力の表示に、ボスの名前（%s）" % s.hp_hud.boss_view()["label"])
	var src := FileAccess.get_file_as_string("res://scripts/prototype/battle_hud.gd")
	check(not src.contains("is_enraged() and int(Time.get_ticks_msec()"), "前の「ボスが おこった」（ずっと点めつ）は描かない")
	s.ai.angry = false

	# ---- 3. 自分が倒れた：DOWN・板（仲間を待つ・のこり時間）／起こしてもらう／復活！ ----
	s.update_cues(0.016)
	s._take_damage(9999.0)
	s.update_cues(0.016)
	check(s.downed and str(s.personal_cue.get("kind", "")) == "down" and float(s.personal_cue["left"]) > 0.0, "倒れると、DOWN")
	for slot in s.ai_allies:
		s.ai_allies[slot]["pos"] = Vector2(14.0, -14.0)  # 仲間は遠くにいる（まだ起こしに来ない）
	s.revive_sys.update(0.016)
	var info: Dictionary = s.revive_sys.my_status_info()
	check(str(info.get("mode", "")) == "wait" and float(info["frac"]) > 0.9 and str(info["num"]) != "", "板：仲間を待つ・のこり時間の帯（%s 秒）" % info.get("num", ""))
	check(not str(info["text"]).contains("びょう") and str(info["text"]).contains("復活"), "板の字は、ふつうの日本語（%s）" % info.get("text", ""))
	# 仲間（AI）を、そばに連れてくる
	var me := str(s._my_slot())
	var z: Dictionary = s.revive_sys.logic.zones[me]
	var helper := ""
	for slot in s.ai_allies:
		if not bool(s.ai_allies[slot]["downed"]):
			helper = str(slot)
			break
	check(helper != "", "起こしに来る仲間がいる")
	var got_progress := false
	for i in 400:
		if helper != "":
			s.ai_allies[helper]["pos"] = z["pos"]
		s.revive_sys.update(0.02)
		var inf2: Dictionary = s.revive_sys.my_status_info()
		if str(inf2.get("mode", "")) == "progress":
			got_progress = true
		if not s.downed:
			break
	check(got_progress, "板：起こしてもらっている間は REVIVING と進みの帯")
	check(not s.downed and str(s.personal_cue.get("kind", "")) == "revive", "起きると、REVIVE（復活！）")
	check(s.revive_sys.my_status_info().is_empty(), "起きたら、板は出さない")

	# ---- 4. 仲間が倒れた・起きた：小さなお知らせ ----
	s.revive_sys.update(0.016)
	var ally := ""
	for slot in s.ai_allies:
		ally = str(slot)
		break
	s.ai_allies[ally]["downed"] = true
	s.ai_allies[ally]["hp"] = 0.0
	s.revive_sys.update(0.016)
	check(str(s.toast_cue["text"]).contains("ダウン") and str(s.toast_cue["text"]).contains(s.role_name_of(ally)), "仲間が倒れると、お知らせ（%s）" % s.toast_cue["text"])
	s.show_revived(ally)
	check(str(s.toast_cue["text"]).contains("復活"), "仲間が起きると、お知らせ（%s）" % s.toast_cue["text"])

	# ---- 5. 撃破・全滅 ----
	s.show_headline("win")
	check(str(s.headline["kind"]) == "win" and str(s.headline["title"]) == "BOSS DEFEATED", "倒すと、BOSS DEFEATED（撃破！）")
	s.headline["left"] = 0.0
	s.show_headline("lose")
	check(str(s.headline["kind"]) == "lose" and str(s.headline["sub"]).contains("全滅"), "全員倒れると、DEFEAT（全滅）")

	# ---- 6. 次の試合で消える ----
	s.won = true
	s._begin_round(float(s.get_meta("now")[0]) + 1000.0)
	check(float(s.headline["left"]) == 0.0 and float(s.personal_cue["left"]) == 0.0 and float(s.toast_cue["left"]) == 0.0 and not s.was_angry,
		"次の試合：前の見出し・お知らせは残らない")
	root.remove_child(s)
	s.free()
	Engine.time_scale = 1.0
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
