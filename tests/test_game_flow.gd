extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_game_flow.gd
## 画面の流れ（flow_logic.gd、save_data.gd、game_flow.gd）を確かめる。

const Logic := preload("res://scripts/flow/flow_logic.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
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
	check(Logic.next_state("battle", "ended") == "highlight", "戦い → ハイライト")
	check(Logic.next_state("highlight", "done") == "reward", "ハイライト → 報酬")
	check(Logic.next_state("reward", "rematch") == "battle" and Logic.next_state("reward", "next") == "next", "報酬 → さいせん（戦い）／つぎへ")
	check(Logic.next_state("next", "rematch") == "battle" and Logic.next_state("next", "lobby") == "lobby", "つぎへ → さいせん（戦い）／ロビー")
	check(Logic.next_state("lobby", "ended") == "lobby" and Logic.next_state("zzz", "play") == "zzz", "決まりにない出来事では、動かない")
	check(Logic.reward_coins(true, 50, 10) == 50 and Logic.reward_coins(false, 50, 10) == 10, "報酬：倒したら多く、全滅でも少し")
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
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": ""}, "保存がなければ、最初の値")
	check(SaveData.write_save(TEMP_SAVE, {"coins": 120, "wins": 4, "quality": "high", "character": "gunner"}), "保存できる")
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 120, "wins": 4, "quality": "high", "character": "gunner"}, "保存した値が読める")
	var f := FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	f.store_string("これはJSONではない")
	f = null
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": ""}, "壊れた保存は、最初の値に戻す")
	f = FileAccess.open(TEMP_SAVE, FileAccess.WRITE)
	f.store_string('{"coins": -5, "wins": "x"}')
	f = null
	check(SaveData.load_save(TEMP_SAVE) == {"coins": 0, "wins": 0, "quality": "", "character": ""}, "マイナスや文字の値は、捨てる")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))

	# 文字が、フォントにある
	var cfg: Dictionary = Flow.load_config()
	var font := load(str(cfg["ui_font_path"])) as Font
	var texts: Array = []
	_collect_texts(cfg, "", texts)
	var missing := ""
	for s in texts:
		for ch in str(s):
			if not font.has_char(ch.unicode_at(0)) and not missing.contains(ch):
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
		check(flow.state == "title" and flow.panels["title"].visible and not flow.panels["lobby"].visible, "最初はタイトル画面")
		flow._process(0.5)
		check(flow.state == "title", "少しのあいだは、タイトルのまま")
		flow._process(2.0)
		check(flow.state == "lobby" and flow.panels["lobby"].visible, "タイトルのあと、自動でロビーに移る")
		check(str(flow.lobby_info.text).contains("ランク 1") and str(flow.lobby_info.text).contains("コイン 0"), "ロビーに、ランクとコイン：" + str(flow.lobby_info.text))
		check(flow.stage_label.text == "きたせんじゅ" and not flow.play_button.disabled, "ステージ1が選ばれていて、プレイできる")
		check(str(flow.quality_button.text).begins_with("がしつ："), "ロビーに、画質のボタン：" + str(flow.quality_button.text))
		var q0: String = flow.quality_name
		flow.change_quality()
		check(flow.quality_name != q0 and SaveData.load_save(TEMP_SAVE)["quality"] == flow.quality_name, "画質を切り替えると、保存される")
		flow.change_quality()
		check(flow.quality_name == q0, "もう一度で、元に戻る")
		flow.change_stage(1)
		check(flow.play_button.disabled and flow.stage_label.text == "？？？", "次のステージ（未開放）は、プレイできない")
		flow.play()
		check(flow.state == "lobby" and flow.toast_label.text == "じゅんびちゅう", "未開放を押すと、「じゅんびちゅう」と出る")
		flow.change_stage(1)
		check(flow.stage_label.text == "きたせんじゅ", "ステージ選択は、ぐるっと戻る")
		# へんせい：キャラを選ぶ
		check(flow.selected_character == "hero_swordsman" and str(flow.lobby_char.text).contains("ファイター けんし"), "最初のキャラは、主人公のけんし：" + str(flow.lobby_char.text))
		flow.event("formation")
		check(flow.state == "formation" and flow.panels["formation"].visible and not flow.panels["lobby"].visible, "へんせいの画面に移る")
		check(flow.formation_buttons.size() == 9 and flow.formation_buttons["hero_swordsman"].disabled and not flow.formation_buttons["gunner"].disabled, "9人のボタン。選んでいるキャラは押せない")
		flow.select_character("gunner")
		check(flow.selected_character == "gunner" and SaveData.load_save(TEMP_SAVE)["character"] == "gunner", "キャラを選ぶと、保存される")
		check(str(flow.formation_stats.text).contains("シューター じゅうし") and str(flow.formation_stats.text).contains("射撃") and str(flow.formation_stats.text).count("\n") == 2 and flow.formation_buttons["gunner"].disabled, "選んだキャラの性能とわざが出る：" + str(flow.formation_stats.text))
		flow.select_character("zzz")
		check(flow.ai_picks == ["guardian", "gunner", "mage"] and flow.ai_buttons.size() == 3, "AIの味方の最初の3人")
		flow.cycle_ai_pick(0)
		check(flow.ai_picks[0] == "summoner" and SaveData.load_ai_picks("user://test_ai_picks.json")[0] == "summoner" and str(flow.ai_buttons[0].text).contains("よびだし"), "AIの味方を、タップで次のキャラにかえて保存する")
		check(flow.selected_character == "gunner", "知らないキャラは選べない")
		flow.event("back")
		check(flow.state == "lobby" and str(flow.lobby_char.text).contains("シューター じゅうし"), "ロビーに戻ると、選んだキャラが出る")
		flow.play()
		_ensure_ready(flow.battle)
		check(flow.battle.ai_enabled and flow.battle.ai_picks[0] == "summoner", "戦いに、AIの選びが渡る")
		check(flow.battle.selected_character == "gunner" and is_equal_approx(flow.battle.role_value("attack_reach"), 7.0) and is_equal_approx(flow.battle.my_hp, 105.0), "戦いは、選んだキャラ（じゅうし）の性能で動く")
		check(flow.state == "battle" and flow.battle != null and flow.battle.flow_mode, "プレイで、戦いが始まる（流れの中のモード）")
		check(not flow.panels["lobby"].visible, "戦いの間は、メニューを隠す")
		flow.battle.my_hits = 100.0
		flow.battle.recorder.record("p1", 0.0, 0.0, 0.0, 0.0)
		flow.battle.recorder.record("p1", 2.0, 3.0, 0.0, 100.0)
		flow.battle.round_ended.emit(true)
		flow._process(1.0)
		check(flow.state == "battle", "戦いが終わっても、少しは結果の画面を見せる")
		flow._process(3.0)
		check(flow.state == "highlight" and str(flow.highlight_best.text).contains("ベストアタッカー") and str(flow.highlight_best.text).contains("100"), "ハイライト：" + str(flow.highlight_best.text))
		check(flow.battle == null, "戦いの画面は片づけられる")
		check(flow.highlight_replay.visible and flow.highlight_replay.span > 0.0 and float(flow.highlight_info["damage"]) == 100.0, "ハイライトの再生が用意される")
		flow._process(0.1)
		check(flow.state == "highlight", "ハイライトは、決めた秒数のあいだ続く")
		flow._process(float(flow.config["highlight_sec"]))
		check(flow.state == "reward" and flow.last_reward == 50 and str(flow.reward_label.text).contains("50"), "報酬：倒したので50コイン")
		var saved := SaveData.load_save(TEMP_SAVE)
		check(saved["coins"] == 50 and saved["wins"] == 1, "報酬が保存される")
		flow.event("rematch")
		_ensure_ready(flow.battle)
		flow._process(0.016)
		check(flow.state == "battle" and flow.battle != null and flow.battle.round_active(), "さいせんは、すぐ戦いが始まる")
		flow.battle.round_ended.emit(false)
		flow._process(3.0)
		check(flow.state == "highlight", "全滅でも、ハイライトへ進む")
		check(not flow.highlight_replay.visible, "記録がなければ、再生は出さない")
		flow.event("done")
		check(flow.state == "reward" and flow.last_reward == 10 and SaveData.load_save(TEMP_SAVE)["coins"] == 60 and SaveData.load_save(TEMP_SAVE)["wins"] == 1, "全滅の報酬は10コイン。倒した回数は増えない")
		flow.event("next")
		check(flow.state == "next", "つぎへ")
		flow.event("lobby")
		check(flow.state == "lobby" and flow.battle == null and str(flow.lobby_info.text).contains("コイン 60"), "ロビーに戻ると、コインが増えている")
		root.remove_child(flow)
		flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
