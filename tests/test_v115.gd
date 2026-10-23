extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v115.gd
## 版115：画面の仕上げ。ひらがなだけの表示（「あそぶ」「もどる」など、ことばの間をあける子ども向けの書き方）をやめて、漢字・カタカナに。
## 見出し（上に小さな英字）・戻るボタン（広がらない）・作る人向けのメモは出さない・勝った時の光の筋・ハイライトの背景・プロフィールの並び。

const Flow := preload("res://scripts/flow/game_flow.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SCENE := "res://scenes/game_flow.tscn"
const FILES := ["res://data/game_flow.json", "res://data/prototype_stick.json", "res://data/character_profiles.json", "res://data/char_actions.json",
	"res://data/actions.json", "res://data/quality.json", "res://data/boss_attacks.json", "res://data/characters.json", "res://data/maps.json"]
const KEEP_NOTES := ["start_note", "gacha_odds_note", "gacha_rules_note", "start_guest_note"]
var failures := 0
var bad: Array = []
var kid := RegEx.new()


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


## 遊ぶ人に見せる文字だけ調べる（_ で始まるキー・note などの作る人向けのメモは見ない）
func walk(x: Variant, path: String) -> void:
	if x is Dictionary:
		for k in x:
			var ks := str(k)
			if ks.begins_with("_") or ks == "note" or ks == "memo" or (ks.ends_with("_note") and not KEEP_NOTES.has(ks)):
				continue
			walk(x[k], path + "." + ks)
	elif x is Array:
		for v in x:
			walk(v, path)
	elif x is String and kid.search(str(x)) != null:
		bad.append(path + "=" + str(x).left(30))


func texts_in(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		texts_in(c, out)


func _initialize() -> void:
	# ---- 1. ひらがなだけの子ども向けの書き方（「ことばの あいだを あける」）が、遊ぶ人に見せる文字にない ----
	kid.compile("[\\x{3041}-\\x{3093}\\x{30a1}-\\x{30f6}ー] [\\x{3041}-\\x{3093}]")
	for f in FILES:
		walk(JSON.parse_string(FileAccess.get_file_as_string(f)), f.get_file())
	check(bad.is_empty(), "遊ぶ人に見せる文字は、ふつうの日本語（漢字・カタカナ）%s" % str(bad))
	var cfg := Flow.load_config()
	check(str(cfg["back_label"]) == "戻る" and str(cfg["stages"][0]["name"]) == "渋谷" and str(cfg["start_subtitle"]) == "4人で挑め！ 巨大ボスバトル", "例：戻る・渋谷・4人で挑め！")
	check(str(cfg["room_name_note"]) == "" and str(cfg["formation_note"]) == "", "作る人向けのメモ（部屋・編成）は、遊ぶ人に出さない")

	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v115_save.json"
	flow.config["ai_picks_path"] = "user://test_v115_ai.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v115_save.json"))
	root.add_child(flow)
	if flow.panels.is_empty():
		flow._ready()
	# ---- 2. 見出し：上に小さな英字・太い字。プロフィールの板は見出しの下 ----
	for pair in [[Logic.ACCOUNT, "PROFILE"], [Logic.ROOM, "ROOM"], [Logic.FRIENDS, "FRIENDS"]]:
		var p: Control = flow.panels[pair[0]]
		var cap := p.find_child("Caption", true, false) as Label
		var head := p.find_child("Heading", true, false) as Label
		check(cap != null and head != null and cap.text == pair[1] and cap.get_index() < head.get_index(), "%s：上に小さく %s・その下に見出し" % [pair[0], pair[1]])
	var acc: Control = flow.panels[Logic.ACCOUNT]
	var head2 := acc.find_child("Heading", true, false) as Control
	check(flow.profile_ui.header.get_index() > head2.get_index(), "プロフィール：見出しが上・プロフィールの板がその下（前は見出しが下にずれていた）")
	# ---- 3. 戻るボタン：画面の幅いっぱいに広がらない・角ばった見た目 ----
	for key in [Logic.ACCOUNT, Logic.ROOM, Logic.FRIENDS]:
		var btns: Array = (flow.panels[key] as Control).find_children("*", "Button", true, false)
		var back: Button = null
		for b in btns:
			if (b as Button).text == str(flow.config["back_label"]):
				back = b
		check(back != null and back.size_flags_horizontal == Control.SIZE_SHRINK_CENTER and back.custom_minimum_size.x <= 560.0
			and (back.get_theme_stylebox("normal") as StyleBoxFlat).skew.x > 0.0, "%s：戻るボタンは広がらない・角ばった" % key)
	var room_texts: Array = []
	texts_in(flow.panels[Logic.ROOM], room_texts)
	check(not room_texts.any(func(t): return str(t).contains("サーバー")), "部屋の画面に、作る人向けのメモは出ない")
	# ---- 4. 色つきの板（オレンジ）の上の字は白 ----
	var start_btn := flow.panels[Logic.ROOM].find_child("Start", true, false) as Button
	check(start_btn != null and start_btn.get_theme_color("font_color") == Color.WHITE, "オレンジのボタンの字は白（くっきり）")
	# ---- 5. 結果：勝った時は光の筋・負けた時はなし ----
	flow.goto(Logic.LOBBY)
	flow._on_round_ended(true)
	flow.goto(Logic.REWARD)
	check(flow.result_ui.rays.visible, "勝った時：VICTORY のうしろに光の筋")
	flow._on_round_ended(false)
	flow.goto(Logic.REWARD)
	check(not flow.result_ui.rays.visible, "負けた時：光の筋は出さない")
	# ---- 6. 画質の名前 ----
	check(str(flow.quality_button.text).ends_with("低") or str(flow.quality_button.text).ends_with("高"), "画質は「低」「高」（%s）" % flow.quality_button.text)
	root.remove_child(flow)
	flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v115_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v115_ai.json"))
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
