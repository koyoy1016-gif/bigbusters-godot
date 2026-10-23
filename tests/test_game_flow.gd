extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_game_flow.gd
## 画面の流れ（flow_logic.gd、save_data.gd、game_flow.gd）を確かめる。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const SCENE := "res://scenes/game_flow.tscn"
const TEMP_SAVE := "user://test_flow_save.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _collect_texts(value: Variant, key: String, out: Array) -> void:
	if value is Dictionary:
		for k in value:
			_collect_texts(value[k], str(k), out)
	elif value is Array:
		for v in value:
			_collect_texts(v, key, out)
	elif value is String:
		var s: String = value
		if key.ends_with("_path") or key.ends_with("_color") or key == "id" or s.begins_with("res://") or s.begins_with("user://") or s.begins_with("#"):
			return
		out.append(s)


## このテストの中では、_ready が自動で動かないことがあるので、動かす
func _ensure_ready(node: Node) -> void:
	if node != null and node.config.is_empty():
		node._ready()


func _initialize() -> void:
	# 決まりごと
	check(Logic.next_state("title", "loaded") == "lobby", "タイトル → ロビー")
	check(Logic.next_state("lobby", "play") == "battle", "ロビー → 戦い")
	check(Logic.next_state("lobby", "formation") == "formation" and Logic.next_state("formation", "back") == "lobby" and Logic.next_state("formation", "play") == "formation", "ロビー ⇔ へんせい")
	# 版109：戦い → 結果 →（ハイライト → 結果）／再戦 → 再戦の準備（START）→ 戦い
	check(Logic.next_state("battle", "ended") == "reward", "戦い → 結果")
	check(Logic.next_state("reward", "highlight") == "highlight" and Logic.next_state("highlight", "done") == "reward", "結果 ⇔ ハイライト")
	check(Logic.next_state("reward", "rematch") == Logic.READY and Logic.next_state("reward", "lobby") == "lobby", "結果 → 再戦の準備／ロビー")
	check(Logic.next_state(Logic.READY, "start") == "battle" and Logic.next_state(Logic.READY, "lobby") == "lobby", "再戦の準備 → START で戦い／ロビー")
	check(Logic.next_state("lobby", "ended") == "lobby" and Logic.next_state("zzz", "play") == "zzz", "決まりにない出来事では、動かない")
	check(Logic.reward_coins(true, 50, 25) == 50 and Logic.reward_coins(false, 50, 25) == 25, "報酬：勝ち50・負け25")
	check(Logic.player_rank(0, 3) == 1 and Logic.player_rank(2, 3) == 1 and Logic.player_rank(3, 3) == 2 and Logic.player_rank(7, 3) == 3, "ランクは、倒した回数で上がる")
	check(Logic.player_rank(5, 0) == 1 and Logic.player_rank(-4, 3) == 1, "ランクの計算が壊れても、1")
	var m := ["p1", "p2"]
	check(Logic.rematch_decision({"p1": "rematch", "p2": "rematch"}, m) == "rematch", "全員さいせん → さいせん")
	check(Logic.rematch_decision({"p1": "rematch", "p2": "lobby"}, m) == "lobby", "1人でもロビー → ロビー")
	check(Logic.rematch_decision({"p1": "rematch"}, m) == "wait", "まだ選んでいない人がいれば、待つ")
	check(Logic.rematch_decision({"p1": "lobby"}, ["p1"]) == "lobby" and Logic.rematch_decision({}, []) == "wait", "1人だけ／部屋が空")
	check(Logic.rematch_decision({"p1": "rematch", "p3": "lobby"}, ["p1"]) == "rematch", "部屋にいない人の選択は、見ない")

	# 保存
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": "", "owned": [], "icon_char": "", "gacha_count": 0}, "保存がなければ、最初の値")
	check(SaveData.write_save(TEMP_SAVE, {"coins": 120, "wins": 4, "quality": "high", "character": "gunner", "owned": ["gunner", "healer"], "icon_char": "healer", "gacha_count": 3}), "保存できる")
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 120, "wins": 4, "quality": "high", "character": "gunner", "owned": ["gunner", "healer"], "icon_char": "healer", "gacha_count": 3}, "保存した値が読める（版82：持っているキャラ・アイコン）")
	var f := FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	f.store_string("これはJSONではない")
	f = null
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": "", "owned": [], "icon_char": "", "gacha_count": 0}, "壊れた保存は、最初の値に戻す")
	f = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	f.store_string('{"coins": -5, "wins": "x"}')
	f = null
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": "", "owned": [], "icon_char": "", "gacha_count": 0}, "マイナスや文字の値は、捨てる")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))

	# 文字が、フォントにある
	var cfg: Dictionary = Flow.load_config()
	var font := load(str(cfg["ui_font_path"])) as Font
	var texts: Array = []
	_collect_texts(cfg, "", texts)
	var missing := ""
	for s in texts:
		for ch in str(s):
			if ch != "\n" and not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):  # 改行は字ではない（版81）
				missing += ch
	check(missing == "", "画面の流れの文字が、すべてフォントにある（足りない字：%s）" % missing)
	var base: Array = cfg["portrait_base_size"]
	check(int(base[1]) > int(base[0]), "縦画面の基準は、縦長")

	# 流れ全体（1人用）
	var packed := load(SCENE) as PackedScene
	check(packed != null, "画面の流れのシーンが読める")
	if packed != null:
		var flow: Node = packed.instantiate()
		flow.config = Flow.load_config()
		flow.config["save_path"] = TEMP_SAVE
		flow.config["ai_picks_path"] = "user://test_ai_picks.json"
		DirAccess.remove_absolute("user://test_ai_picks.json")
		root.add_child(flow)
		if flow.panels.is_empty():
			flow._ready()
		# 版109：最初から、アカウントを選ぶ画面（タイトルの読み込み画面はない）。ログインの仕組みがない所は、すぐ「あそぶ」
		check(flow.state == "start" and flow.panels["start"].visible and not flow.panels["lobby"].visible and not flow.panels.has("title"), "最初は、アカウントを選ぶ画面（TOKYO の画面はない）")
		flow._process(0.016)
		check(flow.start_ui.ready and not flow.start_ui.continue_button.disabled, "準備ができたら、ボタンが押せる")
		flow.start_ui.enter_continue()
		check(flow.state == "lobby" and flow.panels["lobby"].visible, "「あそぶ」で、ロビーへ")
		# 版81：ランクは右上の lobby_info、コインはその下の coin_label
		check(str(flow.lobby_info.text).contains("ランク 1") and flow.lobby_ui.coin_label.text == "0", "ロビーに、ランクとコイン：" + str(flow.lobby_info.text) + " / " + flow.lobby_ui.coin_label.text)
		check(flow.stage_label.text == "渋谷" and not flow.play_button.disabled, "ステージ1が選ばれていて、プレイできる")
		check(str(flow.quality_button.text).begins_with(str(flow.config["quality_label"]) + "："), "ロビーに、画質のボタン：" + str(flow.quality_button.text))
		var q0: String = flow.quality_name
		flow.change_quality()
		check(flow.quality_name != q0 and SaveData.load_save(TEMP_SAVE)["quality"] == flow.quality_name, "画質を切り替えると、保存される")
		flow.change_quality()
		check(flow.quality_name == q0, "もう一度で、元に戻る")
		flow.change_stage(1)
		check(flow.play_button.disabled and flow.stage_label.text == "？？？", "次のステージ（未開放）は、プレイできない")
		flow.play()
		check(flow.state == "lobby" and flow.toast_label.text == str(flow.config["coming_soon"]), "未開放を押すと、「準備中」と出る")
		flow.change_stage(-1)
		check(flow.stage_label.text == "渋谷", "ステージ選択は、もどせる（版81：5つの枠）")
		# へんせい：キャラを選ぶ
		check(flow.selected_character == "hero_swordsman" and flow.lobby_char.text == "剣士" and flow.lobby_ui.role_label.text == "ファイター", "最初のキャラは、主人公の剣士（版109：役職のラベル）：" + str(flow.lobby_char.text))
		flow.event("formation")
		check(flow.state == "formation" and flow.panels["formation"].visible and not flow.panels["lobby"].visible, "へんせいの画面に移る")
		# 版82：編成の画面（4つの枠・一覧9人）。はじめに持っているのは 剣士・ファイター・ガンナー・エンジェル
		check(flow.formation_ui.card_buttons.size() == 9 and flow.formation_ui.slot_buttons.size() == 4, "9人の一覧と、4つの枠")
		check(flow.owned == ["hero_swordsman", "brawler", "gunner", "healer"] and flow.lobby_ui.team() == ["hero_swordsman", "brawler", "gunner", "healer"], "はじめは4人を持っていて、その4人で編成")
		flow.select_character("gunner")
		check(flow.selected_character == "gunner" and SaveData.load_save(TEMP_SAVE)["character"] == "gunner", "キャラを選ぶと、保存される")
		check(flow.lobby_ui.team() == ["gunner", "brawler", "hero_swordsman", "healer"], "メインにしたキャラがいた枠には、前のメインが入る（同じキャラが2人にならない）")
		flow.select_character("zzz")
		flow.select_character("mage")
		check(flow.selected_character == "gunner", "知らないキャラ・持っていないキャラは選べない")
		flow.cycle_ai_pick(0)
		check(flow.ai_picks[0] == "healer" and SaveData.load_ai_picks("user://test_ai_picks.json")[0] == "healer", "なかまを、持っている次のキャラにかえて保存する（メインはかえない）")
		check(flow.selected_character == "gunner", "知らないキャラは選べない")
		flow.event("back")
		check(flow.state == "lobby" and flow.lobby_char.text == "銃士" and flow.lobby_ui.role_label.text == "シューター", "ロビーに戻ると、選んだキャラが出る")
		flow.play()
		_ensure_ready(flow.battle)
		check(flow.battle.ai_enabled and flow.battle.ai_picks[0] == "healer", "戦いに、AIの選びが渡る")
		check(flow.battle.selected_character == "gunner" and is_equal_approx(flow.battle.role_value("attack_reach"), 7.0) and is_equal_approx(flow.battle.my_hp, 105.0), "戦いは、選んだキャラ（銃士）の性能で動く")
		check(flow.state == "battle" and flow.battle != null and flow.battle.flow_mode, "プレイで、戦いが始まる（流れの中のモード）")
		check(not flow.panels["lobby"].visible, "戦いの間は、メニューを隠す")
		flow.battle.my_hits = 100.0
		flow.battle.recorder.record("p1", 0.0, 0.0, 0.0, 0.0)
		flow.battle.recorder.record("p1", 2.0, 3.0, 0.0, 100.0)
		flow.battle.round_ended.emit(true)
		flow._process(1.0)
		check(flow.state == "battle", "戦いが終わっても、少しは結果の画面を見せる")
		flow._process(3.0)
		# 版109：結果の画面（VICTORY・コイン・使ったキャラ・ハイライト・再戦・ロビー）
		check(flow.state == "reward" and flow.result_ui.result_title.text == "VICTORY" and flow.reward_label.text == "+50 COINS", "結果：VICTORY ＋50 COINS（%s）" % flow.reward_label.text)
		check(flow.last_reward == 50 and flow.result_ui.used_label.text == "銃士", "勝ちは50コイン・使ったキャラの役職ラベル")
		var saved := SaveData.load_save(TEMP_SAVE)
		check(saved["coins"] == 50 and saved["wins"] == 1, "報酬が保存される")
		check(flow.battle == null, "戦いの画面は片づけられる")
		check(flow.result_ui.highlight_button.visible, "記録があれば、ハイライトのボタンが出る")
		flow.event("highlight")
		check(flow.state == "highlight" and str(flow.highlight_best.text).contains("ベストアタッカー") and str(flow.highlight_best.text).contains("100"), "ハイライト：" + str(flow.highlight_best.text))
		check(flow.highlight_replay.visible and flow.highlight_replay.span > 0.0 and float(flow.highlight_info["damage"]) == 100.0, "ハイライトの再生が用意される")
		check(flow.highlight_role.visible and flow.highlight_role.text == "銃士" and flow.highlight_role.color == Color(str(CharacterData.find(CharacterData.load_config(), "gunner")["role_color"])),
			"版113：ベストアタッカーを、役職のラベル（役職の色）でも出す")
		flow._process(0.1)
		check(flow.state == "highlight", "ハイライトは、決めた秒数のあいだ続く")
		flow._process(float(flow.config["highlight_sec"]))
		check(flow.state == "reward" and SaveData.load_save(TEMP_SAVE)["coins"] == 50, "ハイライトから結果へ戻っても、コインはふえない（二重に付けない）")
		flow.goto("reward")
		check(SaveData.load_save(TEMP_SAVE)["coins"] == 50, "結果をもう一度出しても、コインはふえない")
		flow.event("rematch")
		check(flow.state == Logic.READY and flow.battle == null, "再戦を選んだだけでは、戦いは始まらない（再戦の準備の画面）")
		check(flow.panels[Logic.READY].visible and flow.result_ui.start_button.visible and not flow.result_ui.start_button.disabled, "START のボタンが出る")
		flow._process(1.0)
		check(flow.state == Logic.READY and flow.battle == null, "START を押すまで、待つ")
		flow.event("start")
		_ensure_ready(flow.battle)
		flow._process(0.016)
		check(flow.state == "battle" and flow.battle != null and flow.battle.round_active(), "START で、新しい試合が始まる")
		check(SaveData.load_save(TEMP_SAVE)["coins"] == 50, "再戦でも、前の試合のコインはふえない")
		flow.battle.round_ended.emit(false)
		flow._process(3.0)
		check(flow.state == "reward" and flow.result_ui.result_title.text == "DEFEAT" and flow.reward_label.text == "+25 COINS", "負け：DEFEAT ＋25 COINS")
		check(not flow.result_ui.highlight_button.visible, "記録がなければ、ハイライトのボタンは出さない")
		check(flow.last_reward == 25 and SaveData.load_save(TEMP_SAVE)["coins"] == 75 and SaveData.load_save(TEMP_SAVE)["wins"] == 1, "負けの報酬は25コイン。倒した回数は増えない")
		flow.event("lobby")
		check(flow.state == "lobby" and flow.battle == null and flow.lobby_ui.coin_label.text == "75", "ロビーに戻ると、コインが増えている")
		root.remove_child(flow)
		flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
