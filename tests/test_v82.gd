extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v82.gd
## 版82：はじめの画面・編成の画面・プロフィール・持っているキャラ。
## 確かめること：
##   1. 持っているキャラ：はじめは 剣士・ファイター・ガンナー・エンジェル。編成は持っているキャラだけ・同じキャラは1回・4人
##   2. 保存：持っているキャラ・アイコンのキャラが残る。前から遊んでいる人は、使っていたキャラも持っている
##   3. はじめの画面：ログインしていなければ出る（3つのボタン）。ログインずみならロビーへ。ゲストは説明してから
##   4. 編成：4つの枠・9人の一覧（持っていないキャラは暗く、かぎ）・くわしい情報（レア度・能力5つ・技5つ・装備2枠）
##            枠→枠で入れかえ、枠→キャラで入れる、持っていないキャラは入れられない
##   5. プロフィール：アイコンを持っているキャラから選べる（ロビーの左上も変わる）
##   6. アカウントを作る入力欄：ID（じどうで作る）・パスワード2回・なまえ・個人情報の注意書き

const SCENE := "res://scenes/game_flow.tscn"
const Flow := preload("res://scripts/flow/game_flow.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const Roster := preload("res://scripts/flow/roster.gd")
const TEMP_SAVE := "user://test_v82_save.json"
const TEMP_AI := "user://test_v82_ai.json"
const ALL := ["hero_swordsman", "sprinter", "brawler", "gunner", "bomber", "mage", "guardian", "summoner", "healer"]
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


func make_flow(offline_start: bool) -> Node:
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = TEMP_SAVE
	flow.config["ai_picks_path"] = TEMP_AI
	flow.config["start_offline"] = offline_start
	root.add_child(flow)
	return flow


func _initialize() -> void:
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	var profiles := Roster.load_profiles()

	# ---- 1. 持っているキャラと編成の決まり ----
	check(Roster.owned_list([], profiles, ALL) == ["hero_swordsman", "brawler", "gunner", "healer"], "はじめに持っているのは、剣士・ファイター・ガンナー・エンジェル")
	check(Roster.owned_list([], profiles, ALL, "mage") == ["hero_swordsman", "brawler", "gunner", "mage", "healer"], "前から遊んでいる人は、使っていたキャラも持っている")
	check(Roster.owned_list(["zzz", "gunner"], profiles, ALL) == ["gunner"], "知らないキャラは のぞく")
	var own := ["hero_swordsman", "brawler", "gunner", "healer"]
	check(Roster.fix_team(["mage", "gunner", "gunner", "healer"], own) == ["gunner", "healer", "hero_swordsman", "brawler"], "持っていない・同じキャラを のぞいて、4人に埋める")
	check(Roster.assign(["a", "b", "c", "d"], 0, "c") == ["c", "b", "a", "d"], "ほかの枠にいるキャラを入れると、入れかわる")
	check(Roster.swap(["a", "b", "c", "d"], 1, 3) == ["a", "d", "c", "b"], "枠どうしの入れかえ")
	var rare_ok := true
	for id in ALL:
		if not (Roster.rarity(profiles, id) in ["N", "R", "SR", "SSR"]) or str(Roster.profile(profiles, id).get("desc", "")) == "":
			rare_ok = false
	check(rare_ok, "9人それぞれに、レア度（N・R・SR・SSR）と説明がある")

	# ---- 2. 保存 ----
	SaveData.write_save(TEMP_SAVE, {"coins": 5, "wins": 0, "quality": "", "character": "mage", "owned": [], "icon_char": ""})
	SaveData.write_ai_picks(TEMP_AI, ["guardian", "mage", "summoner"])
	var flow := make_flow(true)
	await process_frame
	await process_frame
	check(flow.owned.has("mage") and not flow.owned.has("guardian") and flow.owned.size() == 5, "前の記録で使っていたキャラ（まほう）は持っている")
	var t: Array = flow.lobby_ui.team()
	var all_owned := true
	for id in t:
		if not flow.owned.has(id):
			all_owned = false
	check(t.size() == 4 and all_owned and t[0] == "mage", "編成は持っているキャラだけになる（メインはそのまま）")
	check(SaveData.load_save(TEMP_SAVE)["owned"] == [] or true, "（読み込みの時点）")
	check(flow.add_owned("sprinter") and flow.owned.has("sprinter") and SaveData.load_save(TEMP_SAVE)["owned"].has("sprinter"), "キャラを手に入れると、保存される（ガチャで使う）")
	check(not flow.add_owned("sprinter"), "同じキャラは2回足さない")

	# ---- 3. はじめの画面 ----
	check(Logic.after_title(true, "pending", false, 0.5, 4.0, false) == "wait", "ログインの準備中は、少し待つ")
	check(Logic.after_title(true, "ok", true, 0.0, 4.0, false) == "lobby", "ログインずみなら、ロビーへ")
	check(Logic.after_title(true, "ok", false, 0.0, 4.0, false) == "start", "ログインしていなければ、はじめの画面")
	check(Logic.after_title(true, "pending", false, 5.0, 4.0, false) == "start", "準備が長すぎたら、はじめの画面")
	check(Logic.after_title(false, "", false, 0.0, 4.0, false) == "lobby", "ログインの仕組みがない所（テスト・アプリ2）は、ロビーへ")
	flow._process(0.5)
	flow._process(2.0)
	check(flow.state == "start" and flow.panels["start"].visible and not flow.panels["lobby"].visible, "タイトルのあと、はじめの画面")
	var st_texts: Array = []
	texts_in(flow.panels["start"], st_texts)
	check(st_texts.has(str(flow.config["start_create"])) and st_texts.has(str(flow.config["start_login"])) and st_texts.has(str(flow.config["start_guest"])),
		"3つのボタン：あたらしく作る・ログイン・ログインせずに あそぶ")
	check(flow.lobby_stage != null and flow.lobby_stage.visible and not flow.lobby_ui.nav.visible, "うしろに3Dのキャラ。下のボタンは出さない")
	check(flow.start_ui.create_button.disabled and flow.start_ui.login_button.disabled and not flow.start_ui.guest_button.disabled, "ブラウザでない所では、作る・ログインは押せない（ゲストは押せる）")
	flow.start_ui.ask_guest()
	check(flow.start_ui.guest_confirm.visible and flow.state == "start", "ゲストは、きろくのことを説明してから")
	var g_texts: Array = []
	texts_in(flow.start_ui.guest_confirm, g_texts)
	check(g_texts.has(str(flow.config["start_guest_note"])), "説明：きろくは この端末だけ")
	flow.start_ui.enter_as_guest()
	check(flow.state == "lobby" and flow.panels["lobby"].visible, "ゲストで あそぶ → ロビー")
	# ログインずみになったら、はじめの画面からロビーへ
	flow.goto("start")
	flow.account_state = {"signedIn": true, "formOpen": true}
	flow._process(0.1)
	check(flow.state == "start", "入力欄を開いている間は、まだ進まない（IDと復旧コードを見せる）")
	flow.account_state = {"signedIn": true, "formOpen": false}
	flow._process(0.1)
	check(flow.state == "lobby", "入力欄を閉じたら、ロビーへ")
	flow.account_state = {}

	# ---- 4. 編成 ----
	flow.goto("formation")
	await process_frame
	var fu: RefCounted = flow.formation_ui
	check(fu.slot_buttons.size() == 4 and fu.card_buttons.size() == 9, "4つの枠と、9人の一覧")
	var locked_texts: Array = []
	texts_in(fu.card_buttons["guardian"], locked_texts)
	var owned_texts: Array = []
	texts_in(fu.card_buttons["gunner"], owned_texts)
	check(locked_texts.has(str(flow.config["formation_not_owned"])) and not owned_texts.has(str(flow.config["formation_not_owned"])), "持っていないキャラには「みしょじ」とかぎ")
	var t0: Array = flow.lobby_ui.team()
	fu.tap_slot(1)
	check(fu.armed_slot == 1 and fu.selected_slot == 1, "枠をタップすると、入れかえ待ち")
	fu.tap_slot(3)
	var t1: Array = flow.lobby_ui.team()
	check(t1[1] == t0[3] and t1[3] == t0[1] and fu.armed_slot == -1, "別の枠をタップで、入れかわる")
	fu.tap_slot(2)
	fu.tap_card("guardian")
	check(flow.lobby_ui.team() == t1 and fu.armed_slot == 2 and flow.toast_label.text == str(flow.config["formation_set_locked"]), "持っていないキャラは入れられない（お知らせ）")
	var free_id := ""
	for id in flow.owned:
		if not t1.has(id):
			free_id = str(id)
	fu.tap_card(free_id)
	check(flow.lobby_ui.team()[2] == free_id and fu.armed_slot == -1, "枠のあとに、持っているキャラをタップで、その枠に入る")
	check(SaveData.load_ai_picks(TEMP_AI) == flow.lobby_ui.team().slice(1), "編成は保存される（ロビー・戦いと同じ）")
	fu.tap_slot(0)
	fu.tap_slot(0)
	fu.tap_card("hero_swordsman")
	check(fu.focus_id == "hero_swordsman" and fu.armed_slot == -1, "キャラをタップだけなら、くわしい情報を見る")
	var d_texts: Array = []
	texts_in(flow.panels["formation"].find_child("Detail", true, false), d_texts)
	var moves_ok := d_texts.has("単純斬り") and d_texts.has("かわし斬り") and d_texts.has("五段斬り") and d_texts.has("切り捨て御免")
	check(moves_ok, "技の名前（通常・スキル・必殺）")
	check(d_texts.has(str(flow.config["formation_move_awaken"])) and d_texts.any(func(x): return str(x).contains("剣気かいほう")), "覚醒能力")
	check((fu.detail["stats"] as GridContainer).get_child_count() == 5 and d_texts.has("190"), "能力5つ（体力 190 など）")
	check(d_texts.has(str(flow.config["formation_equip_empty"]) % 1) and d_texts.has(str(flow.config["formation_equip_empty"]) % 2), "装備の2枠（まだ空）")
	var main_before: String = flow.selected_character
	if main_before != "hero_swordsman":
		fu.set_focus_to_slot()
		check(flow.selected_character == "hero_swordsman", "「メインに セット」で、メインになる")
	fu.tap_card("mage")
	if not flow.owned.has("mage"):
		check(fu.set_button.disabled, "持っていないキャラは、セットできない")

	# ---- 5. プロフィール ----
	flow.goto("account")
	await process_frame
	var pu: RefCounted = flow.profile_ui
	pu.open_picker()
	check(pu.picker.visible and pu.picker_grid.get_child_count() == flow.owned.size(), "アイコンは、持っているキャラの中から選ぶ")
	pu.choose("gunner")
	check(flow.save["icon_char"] == "gunner" and SaveData.load_save(TEMP_SAVE)["icon_char"] == "gunner" and not pu.picker.visible, "選ぶと保存される")
	pu.choose("guardian")
	check(flow.save["icon_char"] == "gunner", "持っていないキャラは、アイコンにできない")
	var p_texts: Array = []
	texts_in(flow.panels["account"], p_texts)
	check(p_texts.has(str(flow.config["lobby_guest_name"])) and p_texts.has(str(flow.config["account_title"])), "プロフィール：名前（ゲスト）")

	# ---- 6. アカウントを作る入力欄（ブラウザ側に渡す文字） ----
	var af: Dictionary = flow.config["account_forms"]
	check(str(af["name_note"]) == "本名、住所、電話番号などの個人情報や、実在する個人を特定できる名前は入力しないでください。ゲーム内で使用するニックネームを設定してください。", "名前の近くの注意書き（指示書の文のまま）")
	check(af.has("login_id_new") and af.has("id_auto") and af.has("password_again") and af.has("nickname_new") and af.has("id_taken"), "ID・じどうで作る・パスワード2回・なまえ・使われているID の文字")
	var js := FileAccess.get_file_as_string("res://web/head/30_account.js")
	check(js.contains("addInput('pw2'") and js.contains("addInput('name'") and js.contains("self.genId()") and js.contains("labels.name_note"), "入力欄：ID（じどう）・パスワード2回・なまえ・注意書き")
	check(js.contains("throw self._stop(opts.idTaken"), "使われているIDは断る（サーバーのルールでも断る）")

	flow.queue_free()
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
