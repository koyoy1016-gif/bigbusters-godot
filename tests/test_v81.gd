extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v81.gd
## 版81：新しいロビー。
## 確かめること：
##   1. 配置：左上＝名前、右上＝ランクとコイン、右端＝フレンド・へや、下＝ステージとプレイ、いちばん下＝編成・ロビー・ガチャ（この順）
##   2. 前の「そうび・キャラ・もちもの」などのボタンは、ロビーにない（同じ入口が2つない）
##   3. ステージ：5つの枠。1つめ（きたせんじゅ）だけ遊べる。未開放は選べず、戦いも始まらない
##   4. キャラ：まんなかに1人・後ろに3人。左右に回す（スライド・矢印・キー）、後ろの人をタップでメインに。編成と保存が合う
##   5. 3Dの形は、回しても作り直さない。戦いに入ると消え、ロビーに戻るとまた出る
##   6. 下の3つのボタン：ロビーでロビーを押しても作り直さない／編成へ行ける／編成からロビーへ戻れる
##   7. 左上でプロフィール、右端でフレンド・へやの画面へ。へやの画面に、コード・編成・はじめる
##   8. ランクが上がると、お知らせ。コインの数が合う

const SCENE := "res://scenes/game_flow.tscn"
const Flow := preload("res://scripts/flow/game_flow.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const TEMP_SAVE := "user://test_v81_save.json"
const TEMP_AI := "user://test_v81_ai.json"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func buttons_in(n: Node) -> Array:
	return n.find_children("*", "Button", true, false)


func _initialize() -> void:
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = TEMP_SAVE
	flow.config["ai_picks_path"] = TEMP_AI
	root.add_child(flow)
	await process_frame
	await process_frame
	flow.goto("lobby")
	await process_frame
	await process_frame
	var ui: RefCounted = flow.lobby_ui
	ui.finish_enter()
	var lobby: Control = flow.panels["lobby"]
	var screen := Vector2(lobby.size)

	# ---- 1. 配置 ----
	var prof := lobby.find_child("Profile", true, false) as Control
	var rc := lobby.find_child("RankCoin", true, false) as Control
	var side := lobby.find_child("Side", true, false) as Control
	check(prof != null and prof.get_global_rect().position.x < screen.x * 0.2 and prof.get_global_rect().position.y < screen.y * 0.12, "左上に、アイコンと名前")
	check(rc != null and rc.get_global_rect().end.x > screen.x * 0.8 and rc.get_global_rect().position.y < screen.y * 0.12, "右上に、ランクとコイン")
	check(side != null and side.get_global_rect().end.x > screen.x * 0.85 and side.find_child("Friends", true, false) != null and side.find_child("Room", true, false) != null,
		"右端に、フレンドと へやを つくる")
	check(ui.name_label.text == str(flow.config["lobby_guest_name"]), "ログインしていなければ、名前は「ゲスト」")
	var play_r: Rect2 = flow.play_button.get_global_rect()
	var stage_btn := lobby.find_child("Stage", true, false) as Control
	check(stage_btn != null and stage_btn.get_global_rect().end.x <= play_r.position.x + 1.0 and play_r.position.y > screen.y * 0.6, "下に、ステージ（左）とプレイ（右）")
	var nav: Control = ui.nav
	var keys: Array = ui.nav_buttons.keys()
	check(keys == ["formation", "lobby", "gacha"], "いちばん下は、左から 編成・ロビー・ガチャ")
	var nr: Rect2 = nav.get_global_rect()
	check(nav.visible and nr.end.y >= screen.y - 1.0 and play_r.end.y <= nr.position.y, "下のボタンは画面のいちばん下で、プレイと重ならない")
	var xs: Array = []
	for k in keys:
		xs.append((ui.nav_buttons[k] as Control).get_global_rect().position.x)
	check(xs[0] < xs[1] and xs[1] < xs[2], "3つのボタンが横に並ぶ")
	var inside := true
	for c in [prof, rc, side, stage_btn, flow.play_button, nav]:
		var r: Rect2 = (c as Control).get_global_rect()
		if r.position.x < -1.0 or r.end.x > screen.x + 1.0 or r.position.y < -1.0 or r.end.y > screen.y + 1.0:
			inside = false
	check(inside, "部品が画面からはみ出さない（縦 %dx%d）" % [int(screen.x), int(screen.y)])

	# ---- 2. 前のボタンがない ----
	var old_names := ["そうび", "キャラ", "もちもの", "持ち物", "アカウント"]
	var found_old := false
	var formation_entries := 0
	for b in buttons_in(lobby):
		var t := str((b as Button).text)
		for nm in old_names:
			if t == nm:
				found_old = true
	for b in buttons_in(nav):
		if (b as Button).find_child("Text", true, false) != null and ((b as Button).find_child("Text", true, false) as Label).text == "編成":
			formation_entries += 1
	check(not found_old, "ロビーに、前の「そうび・キャラ・もちもの・アカウント」のボタンはない")
	check(formation_entries == 1, "編成の入口は1つだけ（いちばん下）")

	# ---- 3. ステージ ----
	var stages: Array = flow.config["stages"]
	var open_n := 0
	for st in stages:
		if bool(st["open"]):
			open_n += 1
	check(stages.size() == 5 and bool(stages[0]["open"]) and str(stages[0]["name"]) == "きたせんじゅ" and open_n == 1, "ステージは5つ。遊べるのは きたせんじゅ だけ")
	ui.open_stage_picker()
	check(ui.stage_picker.visible and ui.stage_picker_box.get_child_count() == 5, "ステージの四角をタップで、5つの中から選べる")
	ui.pick_stage(2)
	check(flow.stage_index == 0 and ui.stage_picker.visible and flow.toast_label.text == str(flow.config["stage_locked_toast"]), "未開放のステージは選べない（お知らせが出る）")
	ui.pick_stage(0)
	check(not ui.stage_picker.visible and flow.stage_index == 0 and flow.stage_label.text == "きたせんじゅ", "遊べるステージを選ぶと、閉じる")
	flow.change_stage(1)
	flow.play()
	check(flow.state == "lobby" and flow.battle == null, "未開放のステージでプレイしても、戦いは始まらない")
	flow.change_stage(-1)

	# ---- 4. キャラを回す ----
	var t0: Array = ui.team()
	check(t0.size() == 4 and t0[0] == flow.selected_character, "編成は4人（メイン＋後ろの3人）")
	var stage3d: Node3D = flow.lobby_stage
	check(stage3d != null and stage3d.units.size() == 4 and stage3d.camera.current, "3Dのキャラが4人出る")
	var built0: int = stage3d.built_count
	ui.rotate_team(1)
	var t1: Array = ui.team()
	check(t1[0] == t0[1] and t1[3] == t0[0] and flow.selected_character == t0[1], "右へスライド：左の人がまんなかへ")
	check(SaveData.load_save(TEMP_SAVE)["character"] == t0[1] and SaveData.load_ai_picks(TEMP_AI) == t1.slice(1), "回すと、メインと後ろの3人が保存される（編成と同じ）")
	check(stage3d.built_count == built0, "回しても、キャラの形を作り直さない")
	ui.rotate_team(-1)
	check(ui.team() == t0, "左へスライドで、もとにもどる")
	stage3d.finish()
	var main_unit: Dictionary = stage3d.units[0]
	var top := float(stage3d.cfg.get("platform_height", 0.0))
	check((main_unit["holder"] as Node3D).position.distance_to(Vector3(0, top, 0)) < 0.01 and (main_unit["holder"] as Node3D).scale.x > (stage3d.units[1]["holder"] as Node3D).scale.x,
		"メインはまんなかの前の台の上、後ろの人より大きい")
	check(ui.gesture(Vector2(300, 600), Vector2(460, 610)) == "swipe" and ui.team()[0] == t0[1], "スライドの動きで回る（右へ）")
	check(ui.gesture(Vector2(460, 600), Vector2(300, 590)) == "swipe" and ui.team() == t0, "左へのスライドで回る")
	stage3d.finish()
	await process_frame
	var p2: Vector2 = stage3d.screen_point(2)
	check(ui.gesture(p2, p2 + Vector2(3, 2)) == "pick" and ui.team()[0] == t0[2] and ui.team()[2] == t0[0], "後ろの人をタップすると、メインになる（入れかわる）")
	ui.pick_slot(2)
	check(ui.team() == t0, "もう一度で、もとにもどる")
	var kev := InputEventKey.new()
	kev.keycode = KEY_LEFT
	kev.pressed = true
	check(ui.on_key(kev) and ui.team()[0] == t0[1], "パソコンの左の矢印キーで回る")
	ui.rotate_team(-1)
	check(str(flow.lobby_char.text) != "", "メインの名前が、矢印のあいだに出る")
	stage3d.set_team(["hero_swordsman", "gunner"])
	stage3d.finish()
	check(stage3d.units.size() == 2, "4人より少なくても並べられる")
	stage3d.set_team(ui.team())

	# ---- 5・6. 戦いとロビーの行き来、下のボタン ----
	ui.nav_press("lobby")
	check(flow.lobby_stage == stage3d and flow.state == "lobby", "ロビーでロビーを押しても、作り直さない")
	ui.nav_press("formation")
	check(flow.state == "formation" and ui.nav.visible and not stage3d.visible, "編成ボタンで編成の画面（下のボタンは出たまま、3Dは隠す）")
	ui.nav_press("lobby")
	check(flow.state == "lobby" and stage3d.visible, "編成からロビーへ戻れる")
	ui.nav_press("gacha")
	check(flow.state == "gacha", "ガチャのボタンで、ガチャの画面（版83）")
	ui.nav_press("lobby")
	check(flow.state == "lobby", "ガチャからロビーへ戻れる")
	flow.play()
	await process_frame
	check(flow.state == "battle" and (flow.lobby_stage == null) and not ui.nav.visible, "プレイで戦いへ。ロビーの3Dと下のボタンは残らない")
	check(flow.battle != null and flow.battle.selected_character == ui.team()[0] and flow.battle.ai_picks == ui.team().slice(1), "編成の4人が戦いに渡る")
	flow.goto("lobby")
	await process_frame
	check(flow.lobby_stage != null and flow.lobby_stage.units.size() == 4 and flow.battle == null, "ロビーに戻ると、3Dのキャラがまた出る")

	# ---- 7. 画面の行き来 ----
	(lobby.find_child("Profile", true, false) as Button).pressed.emit()
	check(flow.state == "account", "左上のアイコン・名前で、プロフィールの画面")
	flow.event("back")
	(side.find_child("Friends", true, false) as Button).pressed.emit()
	check(flow.state == "friends", "フレンドの画面へ")
	flow.event("back")
	(side.find_child("Room", true, false) as Button).pressed.emit()
	var room_text := ""
	var tl := flow.panels["room"].find_child("TeamLabel", true, false) as Label
	room_text = tl.text if tl != null else ""
	check(flow.state == "room" and str(flow.room_label.text).contains(flow.room_code) and room_text.count("／") == 3, "へやの画面：コードと、編成の4人")
	flow.event("back")
	check(flow.state == "lobby", "へやの画面から戻れる")

	# ---- 版81b：仕上げ ----
	ui.rotate_team(1)
	flow.lobby_stage.finish()
	var mu: Dictionary = flow.lobby_stage.units[0]
	check(mu["view"] == null or str((mu["view"] as Node).get("current_action")) == "win", "まんなかに来たキャラは、勝ちポーズ")
	flow.lobby_stage.step(3.0)
	check(mu["view"] == null or str((mu["view"] as Node).get("current_action")) == "idle", "少ししたら、待ちの動きにもどる")
	ui.rotate_team(-1)
	flow.account_state = {"inbox": [{"type": "friend", "from": "x"}, {"type": "invite", "from": "y", "room": "1234"}]}
	ui.tick(0.6)
	check(ui.friend_badge.visible and ui.friend_badge_label.text == "2", "フレンドの申しこみ・しょうたいの数を、赤い丸で出す")
	flow.account_state = {}
	ui.tick(0.6)
	check(not ui.friend_badge.visible, "なければ、赤い丸は出ない")
	flow.change_stage(1)
	check(ui.play_skin.top_color.s < 0.3, "プレイが押せない時は、灰色")
	flow.change_stage(-1)
	check(ui.play_skin.top_color.s > 0.5 and ui.play_skin.glow_size > 0.0, "押せる時は、オレンジに光る")
	check(ui.role_pill.visible and ui.role_label.text != "", "役の色の札")
	ui.play_enter()
	await process_frame
	await process_frame
	ui.finish_enter()
	var all_shown := true
	for g in ui.enter_groups:
		if (g["node"] as Control).modulate.a < 0.99:
			all_shown = false
	check(all_shown and prof.get_global_rect().position.x < screen.x * 0.2, "出る動きのあと、部品はもとの場所に、はっきり出る")
	check(flow.portraits != null and (flow.portraits.can_render() or (flow.portraits.queue.is_empty() and flow.portraits.busy.is_empty())),
		"顔の絵は、画面のある所でだけ作る（画面のないテストでは作らない。前に作って保存した絵は使う）")
	flow.toast_label.text = ""
	ui.tick(0.1)
	check(not ui.toast_pill.visible, "おしらせがない時は、帯を出さない")

	# ---- 8. ランクとコイン ----
	flow.save["wins"] = int(flow.config["wins_per_rank"]) - 1
	flow.save["coins"] = 120
	flow._refresh_lobby()
	flow.save["wins"] = int(flow.config["wins_per_rank"])
	flow._refresh_lobby()
	check(str(flow.lobby_info.text).ends_with("2") and flow.toast_label.text.begins_with(str(flow.config["lobby_rank_up"])), "ランクが上がると、お知らせ：" + flow.toast_label.text)
	check(ui.coin_label.text == "120" and is_equal_approx(ui.rank_bar.value, 0.0), "コインの数・経験のゲージ")

	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
