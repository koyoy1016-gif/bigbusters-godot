extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v83.gd
## 版83：剣士を引っぱって敵を斬るガチャ。
## 確かめること：
##   1. 確率：斬った数ごとに合計100%・斬るほどSSRが上がる・表示（表）と抽選が同じ関数・キャラ1人ずつの確率の合計も100%
##   2. 斬れたか：道の近く・終わりの扇の中の敵だけ。1体1回だけ数える。飛んでいる間だけ
##   3. 状態：まつ→引く→飛ぶ→結果→まつ の順だけ。二重に払わない・二重にもらわない。コインが足りなければ引けない。はじめの1回は無料
##   4. 抽選：たくさん回すと、確率どおりの割合に近い（斬った数 0 と 5）
##   5. 画面：引いて離すと払って飛び出し、斬った数と確率が変わり、結果で持っているキャラに入る（もう持っていればコインがもどる）
##   6. 回す前に確率の表を見られる。ロビーの下の「ガチャ」から入れる。ガチャの3Dは出ると消える

const SCENE := "res://scenes/game_flow.tscn"
const Flow := preload("res://scripts/flow/game_flow.gd")
const GachaLogic := preload("res://scripts/flow/gacha_logic.gd")
const Roster := preload("res://scripts/flow/roster.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const TEMP_SAVE := "user://test_v83_save.json"
const TEMP_AI := "user://test_v83_ai.json"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func texts_in(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		texts_in(c, out)


func _initialize() -> void:
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	var profiles := Roster.load_profiles()
	var g := GachaLogic.new(GachaLogic.load_config(), profiles)
	var cfg: Dictionary = g.cfg

	# ---- 1. 確率 ----
	var sums_ok := true
	var prev_ssr := -1.0
	var rising := true
	for k in int(cfg["enemy_count"]) + 1:
		var o: Dictionary = g.odds(k)
		var s := 0.0
		for r in GachaLogic.RARITIES:
			s += float(o[r])
		if absf(s - 1.0) > 0.000001:
			sums_ok = false
		if float(o["SSR"]) <= prev_ssr:
			rising = false
		prev_ssr = float(o["SSR"])
	check(sums_ok, "斬った数（0〜5）ごとに、確率の合計は100%")
	check(rising and float(g.odds(5)["SSR"]) > float(g.odds(0)["SSR"]) * 3.0, "斬るほど SSR が出やすい（0体 %.1f%% → 5体 %.1f%%）" % [float(g.odds(0)["SSR"]) * 100.0, float(g.odds(5)["SSR"]) * 100.0])
	check(float(g.odds(5)["SSR"]) < 0.5, "たくさん斬っても、かならず SSR ではない")
	check(is_equal_approx(float(g.odds(0)["SSR"]), float(cfg["base_odds"]["SSR"])), "0体なら、基本の確率のまま")
	var items: Array = g.item_odds(3)
	var item_sum := 0.0
	var ids := {}
	for it in items:
		item_sum += float(it["p"])
		ids[str(it["id"])] = true
	check(absf(item_sum - 1.0) < 0.000001 and ids.size() == 9, "キャラ1人ずつの確率（9人）の合計も100%")
	check(g.pool("SSR") == ["mage", "summoner"] and g.pool("N") == ["brawler", "gunner"], "レア度ごとのキャラ（N：ファイター・ガンナー／SSR：魔法使い・おもちゃの兵隊）")

	# ---- 2. 斬れたか ----
	var a := Vector2(0, 2)
	var b := Vector2(0, -8)
	check(g.hits(a, b, Vector2(0.5, -4)), "道の近くの敵は斬れる")
	check(not g.hits(a, b, Vector2(4.5, -4)), "道から遠い敵は斬れない")
	check(g.hits(a, b, Vector2(1.5, -9.8)), "終わりの斬撃（前の扇）の中は斬れる")
	check(not g.hits(a, b, Vector2(0, 5.5)), "うしろは斬れない")
	var aim: Dictionary = g.aim_from_pull(Vector2(0, 300))
	check((aim["dir"] as Vector2).is_equal_approx(Vector2(0, -1)) and is_equal_approx(float(aim["power"]), 1.0) and is_equal_approx(float(aim["dist"]), float(cfg["launch_max_m"])), "まっすぐ下へ引くと、前へ最大で飛ぶ")
	var side: Dictionary = g.aim_from_pull(Vector2(200, 200))
	check((side["dir"] as Vector2).x < 0.0 and rad_to_deg(absf((side["dir"] as Vector2).angle_to(Vector2(0, -1)))) <= float(cfg["max_angle_deg"]) + 0.01, "右下へ引くと、左前へ（角度は上限まで）")
	check(float(g.aim_from_pull(Vector2(0, 20))["power"]) == 0.0 and float(g.aim_from_pull(Vector2(0, -200))["power"]) == 0.0, "少しだけ・上へ引いたのは、飛ばない（やめる）")

	# ---- 3. 状態・払う・二重 ----
	check(not g.start_aim(0, 1), "コインが足りなければ、引けない")
	check(g.free_now(0) and g.start_aim(0, 0), "はじめの1回は、コインがなくても引ける（無料）")
	check(g.launch(0, 0) == 0 and g.state == "flying" and g.paid_free, "無料の1回：払うのは 0")
	check(g.launch(0, 0) == -1, "飛んでいる間に、もう一度は払えない（二重に回さない）")
	check(g.add_kill(2) and not g.add_kill(2) and not g.add_kill(99) and g.kill_count() == 1, "同じ敵は1回だけ・ない敵は数えない")
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	var res: Dictionary = g.finish(rng, ["hero_swordsman"])
	check(not res.is_empty() and g.state == "result" and int(res["kills"]) == 1 and res.has("odds"), "斬り終わると、結果が決まる（斬った数と、使った確率つき）")
	check(g.finish(rng, []).is_empty(), "結果は1回だけ決まる")
	check(not g.add_kill(3), "結果のあとは、斬った数がふえない")
	check(g.take_grant() and not g.take_grant(), "結果をもらえるのは1回だけ（二重にもらわない）")
	g.reset()
	check(g.state == "idle" and g.start_aim(150, 1) and g.launch(150, 1) == int(cfg["cost"]), "2回めからは、コインを払う（%d）" % int(cfg["cost"]))

	# ---- 4. 抽選の割合 ----
	for k in [0, 5]:
		var counts := {"N": 0, "R": 0, "SR": 0, "SSR": 0}
		var gg := GachaLogic.new(cfg, profiles)
		var r2 := RandomNumberGenerator.new()
		r2.seed = 1000 + k
		var n := 20000
		for i in n:
			gg.state = "aiming"
			gg.launch(999, 5)
			for e in k:
				gg.add_kill(e)
			var rr: Dictionary = gg.finish(r2, [])
			counts[str(rr["rarity"])] += 1
			gg.reset()
		var o: Dictionary = gg.odds(k)
		var close := true
		for r in GachaLogic.RARITIES:
			if absf(float(counts[r]) / n - float(o[r])) > 0.012:
				close = false
		check(close, "斬った数 %d：2万回の割合が、表示した確率に近い（SSR %.2f%% / 表示 %.2f%%）" % [k, float(counts["SSR"]) * 100.0 / n, float(o["SSR"]) * 100.0])

	# ---- 5・6. 画面 ----
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = TEMP_SAVE
	flow.config["ai_picks_path"] = TEMP_AI
	root.add_child(flow)
	await process_frame
	await process_frame
	flow.goto("lobby")
	flow.save["coins"] = 250
	flow.lobby_ui.nav_press("gacha")
	await process_frame
	check(flow.state == "gacha" and flow.panels["gacha"].visible and flow.gacha_ui.stage != null and flow.gacha_ui.stage.camera.current, "ロビーの下の「ガチャ」で、ガチャの画面（3D）")
	check(flow.lobby_stage == null or not flow.lobby_stage.visible, "ロビーの3Dは隠す")
	var ui: RefCounted = flow.gacha_ui
	check(ui.stage.enemies.size() == 5, "前に小鬼が5体（正面・左ななめ・右ななめ・奥）")
	var t1: Array = []
	texts_in(flow.panels["gacha"], t1)
	check(t1.has(str(flow.config["gacha_free"])), "はじめの1回は無料と出る")
	ui.open_odds()
	var t2: Array = []
	texts_in(ui.odds_box, t2)
	check(ui.odds_box.visible and t2.has("3.00%") and t2.has(str(flow.config["gacha_rules_note"])), "回す前に、確率の表（斬った数ごと・キャラ1人ずつ）と決まりを見られる")
	ui.odds_box.visible = false
	var hp: Vector2 = ui.stage.hero_screen_point()
	check(ui.grab(hp, true) and ui.logic.state == "aiming" and not flow.lobby_ui.nav.visible, "剣士をつかめる（下のボタンは隠す）")
	ui.drag(hp + Vector2(0, 150))
	check(ui.power_bar.value > 0.4 and ui.stage.guide.visible, "引くと、ちからと、飛ぶ道が出る")
	check(ui.release(hp + Vector2(0, 300)) and ui.logic.state == "flying", "離すと、飛び出す")
	check(int(flow.save["coins"]) == 250 and int(flow.save["gacha_count"]) == 1, "はじめの1回は、コインが減らない")
	ui.stage.finish_now()
	check(ui.logic.state == "result" and ui.result_box.visible and not ui.last_result.is_empty(), "斬り終わると、結果が出る")
	var res2: Dictionary = ui.last_result
	check(int(res2["kills"]) == ui.stage.enemies.filter(func(e): return not bool(e["alive"])).size(), "斬った数は、ほんとうに斬った小鬼の数（%d）" % int(res2["kills"]))
	check(int(res2["kills"]) >= 1, "まっすぐ前に飛ぶと、正面の小鬼は斬れる")
	if bool(res2["new"]):
		check(flow.owned.has(str(res2["id"])) and SaveData.load_save(TEMP_SAVE)["owned"].has(str(res2["id"])), "新しいキャラは、持っているキャラに入る（保存）")
	else:
		check(int(flow.save["coins"]) == 250 + int(res2["refund"]), "もう持っていれば、コインがもどる")
	var coins_now := int(flow.save["coins"])
	var owned_now: Array = flow.owned.duplicate()
	ui._on_finished()
	check(int(flow.save["coins"]) == coins_now and flow.owned == owned_now, "結果は二重にもらえない")
	ui.ask_again()
	check(ui.confirm_box.visible, "「もう一度」は、コインを使うか確かめる")
	ui.confirm_again()
	check(ui.logic.state == "idle" and not ui.result_box.visible, "もう一度：まつ にもどる")
	var c0 := int(flow.save["coins"])
	ui.grab(hp, true)
	ui.release(hp + Vector2(0, 300))
	check(int(flow.save["coins"]) == c0 - 100, "2回めは100コイン使う")
	ui.stage.finish_now()
	flow.save["coins"] = 50
	ui.confirm_again()
	check(not ui.grab(hp, true) and flow.toast_label.text == str(flow.config["gacha_no_coins"]), "コインが足りなければ、引けない（お知らせ）")
	ui.leave()
	await process_frame
	check(flow.state == "lobby" and ui.stage == null, "ロビーへ戻ると、ガチャの3Dは消える")

	flow.queue_free()
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
