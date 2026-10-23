extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v109.gd
## 版109：BIGBLAST・はじめの画面から始まる・役職名の変更・役職のラベルと色・コイン（勝ち50・負け25）・再戦の準備。
## （画面の流れの細かい確かめは test_game_flow・test_v82・test_rematch）

const CD := preload("res://scripts/characters/character_data.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const Flow := preload("res://scripts/flow/game_flow.gd")
const RoleLabel := preload("res://scripts/ui/role_label.gd")
const SCENE := "res://scenes/game_flow.tscn"
const NAMES := {"hero_swordsman": "剣士", "sprinter": "瞬", "brawler": "拳士", "gunner": "銃士", "bomber": "奇術師", "mage": "魔法師",
	"guardian": "守護士", "summoner": "兵隊", "healer": "介護士"}
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	# ---- 1. ゲームの名前 ----
	var cfg := Flow.load_config()
	check(str(cfg["start_title"]) == "BIGBLAST", "はじめの画面のゲームの名前は BIGBLAST")
	check(str(ProjectSettings.get_setting("application/config/name")) == "BIGBLAST", "プロジェクトの名前（ブラウザのタブの名前）も BIGBLAST")
	check(Logic.TRANSITIONS.has(Logic.READY) and Logic.next_state(Logic.START, "enter") == Logic.LOBBY, "はじめの画面からロビーへ・再戦の準備がある")

	# ---- 2. 役職名（表示だけ。内部の id は変えない）と色 ----
	var chars := CD.load_config()
	var colors := {}
	for id in NAMES:
		var d := CD.find(chars, str(id))
		check(not d.is_empty() and str(d["name"]) == str(NAMES[id]), "%s の役職名は %s（id はそのまま）" % [id, NAMES[id]])
		check(d.has("role_color") and Color(str(d["role_color"])).a > 0.9, "%s：役職の識別色がある" % id)
		colors[str(d.get("role_color", ""))] = true
	check(colors.size() == NAMES.size(), "役職の色は、9人ともちがう")
	var font := load("res://assets/fonts/NotoSansJP-Regular-subset.ttf") as Font
	var missing := ""
	for id in NAMES:
		for ch in str(NAMES[id]):
			if not font.has_char(ch.unicode_at(0)):
				missing += ch
	check(missing == "", "役職名の字が、ゲームの字（フォント）にある：" + missing)

	# ---- 3. 役職のラベル ----
	var l: Control = RoleLabel.new().setup("剣士", Color("#ffd24a"), font, 30)
	check(l.custom_minimum_size.x > 60.0 and l.custom_minimum_size.y >= 40.0, "ラベルは、字に合わせた大きさ（%s）" % str(l.custom_minimum_size))
	var w0: float = l.custom_minimum_size.x
	l.text = "とても長い役職名のラベルのテスト"
	check(l.custom_minimum_size.x > w0, "名前が長いと、ラベルも長くなる")
	l.max_width = 200.0
	l.text = "長い長い長い長い長い長い名前"
	check(l.custom_minimum_size.x <= 201.0, "最大の幅をこえる時は、字を小さくして入れる（%.0f）" % l.custom_minimum_size.x)
	l.free()

	# ---- 4. コイン ----
	check(int(cfg["reward_win_coins"]) == 50 and int(cfg["reward_lose_coins"]) == 25, "コイン：勝ち50・負け25")
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v109_save.json"
	flow.config["ai_picks_path"] = "user://test_v109_ai.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v109_save.json"))
	root.add_child(flow)
	if flow.panels.is_empty():
		flow._ready()
	check(flow.state == Logic.START and not flow.panels.has("title"), "起動すると、最初にアカウントを選ぶ画面（読み込み画面はない）")
	flow.goto(Logic.LOBBY)
	var c0 := int(flow.save.get("coins", 0))
	flow._on_round_ended(true)
	flow.goto(Logic.REWARD)
	flow.goto(Logic.HIGHLIGHT)
	flow.goto(Logic.REWARD)
	flow.goto(Logic.REWARD)
	check(int(flow.save["coins"]) == c0 + 50, "勝ち：1回だけ50コイン（結果を何度出しても、ふえない）")
	flow.event("rematch")
	flow.goto(Logic.REWARD)
	check(int(flow.save["coins"]) == c0 + 50, "再戦を押して戻っても、前の試合のコインはふえない")
	flow._on_round_ended(false)
	flow.goto(Logic.REWARD)
	check(int(flow.save["coins"]) == c0 + 75 and flow.reward_label.text == "+25 COINS", "負け：25コイン（新しい試合の分だけ）")
	check(flow.result_ui.used_label.text == str(NAMES[str(flow.selected_character)]), "結果に、使ったキャラの役職名")
	flow.goto(Logic.READY)
	check(flow.result_ui.team_row.get_child_count() == 4, "再戦の準備に、チーム4人の役職ラベル")
	flow.goto(Logic.LOBBY)
	check(flow.result_ui._start_tween == null, "再戦の準備を出たら、START の光（くり返し）を止める")
	check(flow.lobby_char.text == str(NAMES[str(flow.selected_character)]) and flow.lobby_char.color == Color(str(CD.find(chars, str(flow.selected_character))["role_color"])),
		"ロビーの名前は、役職のラベル（役職の色）")
	root.remove_child(flow)
	flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v109_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v109_ai.json"))
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
