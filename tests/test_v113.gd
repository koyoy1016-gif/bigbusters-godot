extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v113.gd
## 版113：画面の見た目の統一（BIGBLAST：暗い・角ばった板とボタン・太い字）。はじめの画面・ロビー・編成・ハイライト・結果・再戦の準備。
## （ベストアタッカーの役職ラベルは test_game_flow）

const Flow := preload("res://scripts/flow/game_flow.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const SCENE := "res://scenes/game_flow.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


## ボタンの見た目が、角ばっているか（ななめ・角の丸みが小さい）。FancyRect の皮をかぶったボタンは、皮の形で見る
func angular_button(b: Button) -> bool:
	var sb := b.get_theme_stylebox("normal")
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		return absf(f.skew.x) > 0.01 and f.corner_radius_top_left <= 3
	var holder := b.get_parent()
	for c in holder.get_children():
		if c is Control and c.get_script() == FancyRect:
			return FancyRect.angular and float(c.radius) > 0.0
	return false


func panel_sharp(p: Control) -> bool:
	var sb := p.get_theme_stylebox("panel")
	return sb is StyleBoxFlat and (sb as StyleBoxFlat).corner_radius_top_left <= 3


func _initialize() -> void:
	var cfg := Flow.load_config()
	var kit: Dictionary = cfg["ui_kit"]
	check(bool(kit.get("angular", false)), "BIGBLAST の見た目（ui_kit.angular）が入っている")

	# ---- 1. 部品 ----
	check(UiKit.corner(cfg, 22) <= 3 and UiKit.corner(cfg, 40) == 40 and UiKit.corner(cfg, 66) == 66, "小さな丸みは角ばらせる・顔の丸（大きな丸み）はそのまま")
	var g := UiKit.glass(cfg, 22)
	check(g.corner_radius_top_left <= 3 and g.bg_color.a > 0.8, "パネル：暗く、角ばった板")
	var b := Button.new()
	UiKit.glass_button(b, cfg, 24, Color("#2d4a7ae0"))
	var bs := b.get_theme_stylebox("normal") as StyleBoxFlat
	var bd := b.get_theme_stylebox("disabled") as StyleBoxFlat
	check(bs.skew.x > 0.0 and bs.corner_radius_top_left <= 3 and bs.border_width_left > bs.border_width_top, "ボタン：ななめ・角ばった・左に太い色の線")
	check(bd.border_color.a < bs.border_color.a, "押せないボタンは、ふちも暗い")
	b.free()
	var pts := FancyRect.slanted_points(Rect2(0, 0, 200, 80), 16.0)
	check(pts.size() == 4 and is_equal_approx(pts[0].x, 16.0) and is_equal_approx(pts[3].x, 0.0) and is_equal_approx(pts[2].x, 184.0), "色つきの板（FancyRect）：ななめの角ばった形")
	var fr := FancyRect.new()
	fr.size = Vector2(200, 80)
	var old: bool = FancyRect.angular
	FancyRect.angular = true
	fr.radius = 22.0
	var a_pts: PackedVector2Array = fr.shape_points(Rect2(Vector2.ZERO, fr.size), 22.0)
	fr.radius = 0.0
	var r_pts: PackedVector2Array = fr.shape_points(Rect2(Vector2.ZERO, fr.size), 0.0)
	check(a_pts.size() == 4 and r_pts.size() > 4, "丸みのある板は角ばった形・丸みのない背景は、そのまま")
	FancyRect.angular = old
	fr.free()

	# ---- 2. 画面 ----
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = "user://test_v113_save.json"
	flow.config["ai_picks_path"] = "user://test_v113_ai.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v113_save.json"))
	root.add_child(flow)
	if flow.panels.is_empty():
		flow._ready()
	check(FancyRect.angular, "画面の流れが始まると、角ばった見た目になる")
	# はじめの画面（アカウントを選ぶ）
	var start_btns: Array = flow.panels[Logic.START].find_children("*", "Button", true, false)
	var ang := 0
	for sb2 in start_btns:
		if angular_button(sb2):
			ang += 1
	check(start_btns.size() > 0 and ang == start_btns.size(), "はじめの画面：ボタンは全部角ばっている（%d/%d）" % [ang, start_btns.size()])
	# ロビー
	flow.goto(Logic.LOBBY)
	check(angular_button(flow.play_button), "ロビー：プレイのボタンは角ばっている")
	check(panel_sharp(flow.lobby_ui.nav), "ロビー：下の3つの帯は角ばっている")
	# 編成
	flow.goto(Logic.FORMATION)
	var fbtns: Array = flow.panels[Logic.FORMATION].find_children("*", "Button", true, false)
	var round_left := 0
	for x in fbtns:
		var st: StyleBox = x.get_theme_stylebox("normal")
		if st is StyleBoxFlat and (st as StyleBoxFlat).corner_radius_top_left > 3 and (st as StyleBoxFlat).corner_radius_top_left < 30:
			round_left += 1
	check(round_left == 0, "編成：丸いボタンは残っていない（%d）" % round_left)
	# ハイライト
	flow.best_text = "ベストアタッカー：兵隊 10"
	flow.best_role = {"name": "兵隊", "color": "#c6e33c"}
	flow.highlight_info = {}
	flow.goto(Logic.HIGHLIGHT)
	var hp: Control = flow.panels[Logic.HIGHLIGHT]
	check(hp.find_child("ReplayFrame", true, false) != null and panel_sharp(hp.find_child("ReplayFrame", true, false)), "ハイライト：再生は角ばった枠の中")
	check(flow.highlight_role.visible and flow.highlight_role.text == "兵隊", "ハイライト：ベストアタッカーの役職ラベル")
	var hb: Array = hp.find_children("*", "Button", true, false)
	check(hb.size() == 1 and angular_button(hb[0]), "ハイライト：もどるボタンは角ばっている")
	flow.best_text = ""
	flow.best_role = {}
	flow.goto(Logic.REWARD)
	flow.goto(Logic.HIGHLIGHT)
	check(not flow.highlight_role.visible, "ハイライト：記録がなければ、役職ラベルは出さない")
	# 結果・再戦の準備
	flow.goto(Logic.REWARD)
	check(angular_button(flow.result_ui.rematch_button) and angular_button(flow.result_ui.lobby_button), "結果：ボタンは角ばっている")
	flow.goto(Logic.READY)
	check(angular_button(flow.result_ui.start_button), "再戦の準備：START は角ばっている")
	root.remove_child(flow)
	flow.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v113_save.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_v113_ai.json"))
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
