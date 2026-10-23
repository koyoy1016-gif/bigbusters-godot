extends RefCounted
## 版109：結果の画面と、再戦の準備の画面（BIGBLAST）。
## 結果：VICTORY／DEFEAT を大きく・もらったコイン（+50 COINS／+25 COINS）・使ったキャラの役職ラベル・
##       ボタン（ハイライトを見る［記録がある時だけ］・再戦・ロビーへもどる）。通信中は、なかまの待ちの字。
## 再戦の準備：チームの役職ラベル・説明・大きな START・ロビーへ。START を押すまで、戦いは始まらない。
## 画面の切りかえと、コインの付与は game_flow.gd（ここは見た目だけ）。文字は data/game_flow.json の v109。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const RoleLabel := preload("res://scripts/ui/role_label.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const RayBurst := preload("res://scripts/ui/ray_burst.gd")

var f: Node
var bold: Font
var result_title: Label
var coins_label: Label
var used_label: Control
var highlight_button: Button
var rematch_button: Button
var lobby_button: Button
var wait_label: Label
var ready_title: Label
var team_row: HBoxContainer
var start_button: Button
var ready_wait_label: Label
var ready_lobby_button: Button
var _start_tween: Tween = null
var rays: Control  ## 版115：勝った時、VICTORY のうしろで回る光の筋


func _init(flow: Node) -> void:
	f = flow


func _v(key: String, def: Variant) -> Variant:
	return (f.config.get("v109", {}) as Dictionary).get(key, def)


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = f._make_label(text, size, color)
	if bold != null:
		l.add_theme_font_override("font", bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, accent: Color, primary: bool, cb: Callable, name_text: String, size: Vector2 = Vector2(520, 100)) -> Button:
	var b: Button = f._make_button(text, [size.x, size.y], cb)
	b.name = name_text
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if bold != null:
		b.add_theme_font_override("font", bold)
	b.add_theme_font_size_override("font_size", 36 if primary else 30)
	UiKit.blast_button(b, accent, primary)
	return b


## 画面いっぱいの暗い背景と、まん中の縦の並び
func _panel(key: String) -> VBoxContainer:
	var root := Control.new()
	root.name = key
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(f._panel_bg())
	root.add_child(UiKit.vignette(true, 420, Color("#03050ce6")))
	root.add_child(UiKit.vignette(false, 520, Color("#03050cf0")))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	root.add_child(box)
	f.layer.add_child(root)
	f.panels[key] = root
	return box


func build() -> void:
	bold = UiKit.bold(f.font, 0.75)
	var gold := Color(str(_v("result_win_color", "#ffd24a")))
	# ---- 結果 ----
	var r := _panel(Logic.REWARD)
	rays = RayBurst.new()
	rays.name = "Rays"
	rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	rays.color = Color(str(_v("result_ray_color", "#ffd24a30")))
	rays.rays = 16
	rays.spin = 0.12
	(f.panels[Logic.REWARD] as Control).add_child(rays)
	(f.panels[Logic.REWARD] as Control).move_child(rays, 1)  # 背景のすぐ上（字・ボタンの下）
	result_title = _label("", int(_v("result_title_size", 110)), gold)
	result_title.name = "ResultTitle"
	result_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	result_title.add_theme_constant_override("outline_size", 16)
	result_title.add_theme_constant_override("shadow_outline_size", 28)
	result_title.add_theme_constant_override("shadow_offset_y", 0)
	r.add_child(result_title)
	coins_label = _label("", 48, Color("#ffe27a"))
	coins_label.name = "Coins"
	UiKit.outline(coins_label, 8)
	r.add_child(coins_label)
	var used_box := VBoxContainer.new()
	used_box.add_theme_constant_override("separation", 6)
	used_box.add_child(_label(str(_v("result_used", "使ったキャラ")), 22, Color("#b9c4dc")))
	used_label = RoleLabel.new().setup("", Color.WHITE, bold, 34)
	used_label.name = "UsedRole"
	used_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	used_box.add_child(used_label)
	r.add_child(used_box)
	highlight_button = _button(str(_v("result_highlight", "ハイライトを見る")), Color("#7fdcff"), false, func(): f.event("highlight"), "Highlight")
	r.add_child(highlight_button)
	rematch_button = _button(str(f.config["rematch_label"]), Color("#ff7a2a"), true, func(): f.event("rematch"), "Rematch")
	r.add_child(rematch_button)
	wait_label = _label("", 26, Color(1.0, 0.85, 0.4))
	r.add_child(wait_label)
	lobby_button = _button(str(_v("result_lobby", "ロビーへ戻る")), Color("#9fb0d0"), false, func(): f.event("lobby"), "Lobby")
	r.add_child(lobby_button)
	# ---- 再戦の準備 ----
	var rd := _panel(Logic.READY)
	ready_title = _label(str(_v("ready_title", "再戦の準備")), 64, Color.WHITE)
	UiKit.outline(ready_title, 10)
	rd.add_child(ready_title)
	team_row = HBoxContainer.new()
	team_row.name = "Team"
	team_row.alignment = BoxContainer.ALIGNMENT_CENTER
	team_row.add_theme_constant_override("separation", 10)
	rd.add_child(team_row)
	var note := _label(str(_v("ready_note", "")), 22, Color("#b9c4dc"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(600, 0)
	rd.add_child(note)
	start_button = _button(str(_v("ready_start", "START")), Color("#ff7a2a"), true, func(): f.event("start"), "Start", Vector2(560, 140))
	start_button.add_theme_font_size_override("font_size", 64)
	rd.add_child(start_button)
	ready_wait_label = _label("", 26, Color(1.0, 0.85, 0.4))
	rd.add_child(ready_wait_label)
	ready_lobby_button = _button(str(_v("result_lobby", "ロビーへ戻る")), Color("#9fb0d0"), false, func(): f.event("lobby"), "ReadyLobby")
	rd.add_child(ready_lobby_button)


## 結果を出す。won：勝ったか。coins：もらったコイン。cid：使ったキャラ。has_highlight：ハイライトの記録があるか
func show_result(won: bool, coins: int, cid: String, has_highlight: bool) -> void:
	var col := Color(str(_v("result_win_color" if won else "result_lose_color", "#ffd24a")))
	result_title.text = str(_v("result_win" if won else "result_lose", "VICTORY" if won else "DEFEAT"))
	result_title.add_theme_color_override("font_color", col)
	result_title.add_theme_color_override("font_shadow_color", Color(col.r, col.g, col.b, 0.5))
	coins_label.text = "+%d %s" % [coins, str(_v("result_coins", "COINS"))]
	var def := CharacterData.find(f.characters_cfg, cid)
	used_label.text = str(def.get("name", ""))
	used_label.color = Color(str(def.get("role_color", "#ffffff")))
	highlight_button.visible = has_highlight
	rays.visible = won
	wait_label.text = ""
	if result_title.is_inside_tree():
		result_title.pivot_offset = result_title.size * 0.5
		result_title.scale = Vector2(1.6, 1.6)
		result_title.modulate.a = 0.0
		var tw := result_title.create_tween().set_parallel(true)
		tw.tween_property(result_title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(result_title, "modulate:a", 1.0, 0.2)


## 再戦の準備を出す。team：チームのキャラの id（自分が先）
func show_ready(team: Array) -> void:
	for c in team_row.get_children():
		team_row.remove_child(c)
		c.queue_free()
	for cid in team:
		var def := CharacterData.find(f.characters_cfg, str(cid))
		if def.is_empty():
			continue
		var l := RoleLabel.new().setup(str(def.get("name", "")), Color(str(def.get("role_color", "#ffffff"))), bold, 26)
		team_row.add_child(l)
	start_button.disabled = false
	ready_wait_label.text = ""
	# START を目立たせる（ゆっくり明るく・暗く。この画面の間だけ）
	if _start_tween != null and _start_tween.is_valid():
		_start_tween.kill()
	if start_button.is_inside_tree():
		start_button.modulate = Color.WHITE
		_start_tween = start_button.create_tween().set_loops()
		_start_tween.tween_property(start_button, "modulate", Color(1.25, 1.15, 1.0), 0.6)
		_start_tween.tween_property(start_button, "modulate", Color.WHITE, 0.6)


## 再戦の準備の画面を出ていく時：START の光を止める（残さない）
func leave_ready() -> void:
	if _start_tween != null and _start_tween.is_valid():
		_start_tween.kill()
	_start_tween = null
	start_button.modulate = Color.WHITE
