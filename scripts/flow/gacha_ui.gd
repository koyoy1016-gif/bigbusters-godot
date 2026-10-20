extends RefCounted
## 版83：ガチャの画面（3Dは gacha_stage.gd、決まりは gacha_logic.gd）。
## 上：もどる・「ガチャ」・コイン・1回の値段・「かくりつ」（回す前に、斬った数ごとの確率と、キャラ1人ずつの確率を見られる）。
## まんなか：剣士をつかんで、うしろへ引いて、離す（指でもマウスでも）。引いている間は、ちからと、飛ぶ道。
## 斬っている間：「斬った 3/5」と、いまの確率（斬るほど上がる）。
## 結果：レア度ごとの光（N：しずか・R：青い光・SR：むらさきの光の筋・SSR：虹の光の筋と白い光）、顔・名前・レア度・斬った数・使った確率。
##       「もう一度 引く」（コインを使うか確かめる）・「ロビーへ」。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const RayBurst := preload("res://scripts/ui/ray_burst.gd")
const GachaLogic := preload("res://scripts/flow/gacha_logic.gd")
const GachaStage := preload("res://scripts/flow/gacha_stage.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Roster := preload("res://scripts/flow/roster.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")

var f: Node
var logic: RefCounted
var stage: Node3D = null
var rng := RandomNumberGenerator.new()
var root: Control
var coin_label: Label
var cost_label: Label
var hint: Control
var hint_label: Label
var power_box: Control
var power_bar: ProgressBar
var power_label: Label
var counter: Label
var odds_row: HBoxContainer
var odds_note: Label
var result_box: Control
var result_card: Control
var result_rays: Control
var flash: ColorRect
var again_button: Button
var confirm_box: Control
var odds_box: Control
var back_button: Button
var press_pos := Vector2.INF
var pressing := false
var bold: Font
var last_result: Dictionary = {}


func _init(flow: Node) -> void:
	f = flow
	rng.randomize()


func _k(key: String, def: Variant) -> Variant:
	return (f.config.get("ui_kit", {}) as Dictionary).get(key, def)


func _t(key: String) -> String:
	return str(f.config.get(key, key))


func _label(text: String, size: int, color: Color, use_bold: bool = false) -> Label:
	var l: Label = f._make_label(text, size, color)
	if use_bold and bold != null:
		l.add_theme_font_override("font", bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rarity_color(r: String) -> Color:
	return Color(str((f.profiles.get("rarity_colors", {}) as Dictionary).get(r, "#9aa4b8")))


func _pill(text: String, col: Color, size: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(3)
	sb.set_content_margin(SIDE_LEFT, 12)
	sb.set_content_margin(SIDE_RIGHT, 12)
	sb.set_border_width_all(1)
	sb.border_color = col.lightened(0.4)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UiKit.outline(_label(text, size, Color.WHITE, true), 3, Color(0, 0, 0, 0.45)))
	return p


func _big(text: String, primary: bool, cb: Callable, w: float = 520.0) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, 92)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var b: Button = f._make_button(text, [w, 92], cb)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	if bold != null:
		b.add_theme_font_override("font", bold)
	b.add_theme_font_size_override("font_size", 30)
	if primary:
		var skin := FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 26, Color(str(_k("play_glow", "#ff7a2a"))), 10)
		skin.name = "Skin"
		skin.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(skin)
		UiKit.clear_button(b)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	holder.add_child(b)
	return [holder, b]


# ---------------------------------------------------------------- 画面を作る

func build() -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	logic = GachaLogic.new(GachaLogic.load_config(), f.profiles)
	root = Control.new()
	root.name = Logic.GACHA
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(on_input)
	f.layer.add_child(root)
	f.panels[Logic.GACHA] = root
	root.add_child(UiKit.vignette(true, 260, Color("#070a14d0")))
	root.add_child(UiKit.vignette(false, 380, Color("#070a14c0")))
	_build_top()
	_build_middle()
	_build_bottom()
	_build_result()
	_build_confirm()
	_build_odds_table()


func _build_top() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Top"
	bar.add_theme_constant_override("separation", 12)
	back_button = f.lobby_ui.icon_button("left", "", Vector2(64, 64), 1, Color(str(_k("arrow_color", "#0e1526a0"))), leave, 32)
	back_button.name = "Back"
	bar.add_child(back_button)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 0)
	var title := UiKit.outline(_label(_t("gacha_title"), 40, Color.WHITE, true), 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tcol.add_child(title)
	cost_label = UiKit.outline(_label("", 18, Color(str(_k("gold", "#ffd45a"))), true), 4)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tcol.add_child(cost_label)
	bar.add_child(tcol)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var coin := PanelContainer.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.add_theme_stylebox_override("panel", UiKit.glass(f.config, 22))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	var ci := LobbyIcon.new("coin")
	ci.custom_minimum_size = Vector2(30, 30)
	crow.add_child(ci)
	coin_label = _label("", 26, Color("#ffe08a"), true)
	crow.add_child(coin_label)
	coin.add_child(crow)
	bar.add_child(coin)
	var odds_btn: Button = f._make_button(_t("gacha_odds_button"), [140, 64], open_odds)
	odds_btn.name = "OddsButton"
	odds_btn.add_theme_font_size_override("font_size", 22)
	UiKit.glass_button(odds_btn, f.config, 20, Color("#2d4a7ae0"))
	bar.add_child(odds_btn)
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	bar.offset_left = 14
	bar.offset_right = -14
	bar.offset_top = 14
	counter = UiKit.outline(_label("", 50, Color.WHITE, true), 10)
	counter.set_anchors_preset(Control.PRESET_TOP_WIDE)
	counter.offset_top = 110
	counter.offset_bottom = 180
	counter.add_theme_color_override("font_outline_color", Color("#7a1a06"))
	root.add_child(counter)


func _build_middle() -> void:
	hint = PanelContainer.new()
	hint.name = "Hint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.glass(f.config, 26)
	sb.set_content_margin_all(14)
	sb.set_content_margin(SIDE_LEFT, 24)
	sb.set_content_margin(SIDE_RIGHT, 24)
	hint.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	hint_label = _label(_t("gacha_hint"), 28, Color.WHITE, true)
	col.add_child(hint_label)
	col.add_child(_label(_t("gacha_hint_sub"), 19, Color(str(_k("sub_text", "#b9c4dc")))))
	hint.add_child(col)
	var holder := CenterContainer.new()
	holder.name = "HintHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 190
	holder.offset_bottom = 300
	holder.add_child(hint)
	root.add_child(holder)


func _build_bottom() -> void:
	var col := VBoxContainer.new()
	col.name = "Bottom"
	col.add_theme_constant_override("separation", 8)
	power_box = HBoxContainer.new()
	power_box.alignment = BoxContainer.ALIGNMENT_CENTER
	power_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	power_box.add_theme_constant_override("separation", 10)
	power_box.add_child(UiKit.outline(_label(_t("gacha_power"), 22, Color.WHITE, true), 4))
	power_bar = ProgressBar.new()
	power_bar.custom_minimum_size = Vector2(320, 18)
	power_bar.show_percentage = false
	power_bar.max_value = 1.0
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.15)
	bgs.set_corner_radius_all(9)
	power_bar.add_theme_stylebox_override("background", bgs)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff8a3a")
	fill.set_corner_radius_all(9)
	power_bar.add_theme_stylebox_override("fill", fill)
	power_box.add_child(power_bar)
	power_label = UiKit.outline(_label("", 22, Color(str(_k("gold", "#ffd45a"))), true), 4)
	power_label.custom_minimum_size = Vector2(70, 0)
	power_box.add_child(power_label)
	power_box.visible = false
	col.add_child(power_box)
	odds_note = UiKit.outline(_label("", 18, Color(str(_k("sub_text", "#b9c4dc")))), 4)
	col.add_child(odds_note)
	odds_row = HBoxContainer.new()
	odds_row.name = "OddsRow"
	odds_row.alignment = BoxContainer.ALIGNMENT_CENTER
	odds_row.add_theme_constant_override("separation", 8)
	col.add_child(odds_row)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.offset_top = -float(f.config["nav_height"]) - 140
	col.offset_bottom = -float(f.config["nav_height"]) - 14


## いまの確率（斬った数 k のとき）を、レア度の札で
func _refresh_odds_row(k: int) -> void:
	f._clear_box(odds_row)
	var o: Dictionary = logic.odds(k)
	for r in GachaLogic.RARITIES:
		odds_row.add_child(_pill("%s %.1f%%" % [r, float(o[r]) * 100.0], _rarity_color(r).darkened(0.25), 18))
	odds_note.text = _t("gacha_odds_now") % k


func _build_result() -> void:
	result_box = Control.new()
	result_box.name = "Result"
	result_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_box.add_child(dim)
	result_rays = RayBurst.new()
	result_rays.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_box.add_child(result_rays)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_card = VBoxContainer.new()
	result_card.name = "Card"
	(result_card as VBoxContainer).add_theme_constant_override("separation", 12)
	center.add_child(result_card)
	result_box.add_child(center)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_box.add_child(flash)
	result_box.visible = false
	root.add_child(result_box)


func _build_confirm() -> void:
	confirm_box = Control.new()
	confirm_box.name = "Confirm"
	confirm_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_box.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	var sb := UiKit.glass(f.config, 26, 1.4)
	sb.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 16)
	var q := _label("", 28, Color.WHITE, true)
	q.name = "Question"
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(500, 0)
	col.add_child(q)
	col.add_child(_big(_t("gacha_confirm_yes"), true, confirm_again, 500)[0])
	col.add_child(_big(_t("back_label"), false, func(): confirm_box.visible = false, 500)[0])
	card.add_child(col)
	center.add_child(card)
	confirm_box.add_child(center)
	confirm_box.visible = false
	root.add_child(confirm_box)


## 確率の表（回す前に見られる）：斬った数ごとのレア度の確率と、キャラ1人ずつの確率
func _build_odds_table() -> void:
	odds_box = Control.new()
	odds_box.name = "OddsTable"
	odds_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	odds_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.1, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	odds_box.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	odds_box.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 20)
	col.add_child(pad)
	col.add_child(UiKit.outline(_label(_t("gacha_odds_title"), 34, Color.WHITE, true), 6))
	var note := _label(_t("gacha_odds_note"), 19, Color(str(_k("sub_text", "#b9c4dc"))))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(580, 0)
	col.add_child(note)
	# 斬った数 × レア度
	var t1 := GridContainer.new()
	t1.name = "RarityTable"
	t1.columns = 5
	t1.add_theme_constant_override("h_separation", 6)
	t1.add_theme_constant_override("v_separation", 6)
	var cells: Array = [_t("gacha_odds_kills")]
	for r in GachaLogic.RARITIES:
		cells.append(r)
	for k in int(logic.cfg.get("enemy_count", 5)) + 1:
		var o: Dictionary = logic.odds(k)
		cells.append(_t("gacha_odds_kills_n") % k)
		for r in GachaLogic.RARITIES:
			cells.append("%.2f%%" % (float(o[r]) * 100.0))
	for i in cells.size():
		var head := i < 5 or i % 5 == 0
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(112, 40)
		var csb := StyleBoxFlat.new()
		var rc := _rarity_color(str(cells[i])) if i >= 1 and i < 5 else Color(1, 1, 1, 0.06 if head else 0.03)
		csb.bg_color = rc.darkened(0.3) if i >= 1 and i < 5 else rc
		csb.set_corner_radius_all(8)
		csb.set_content_margin_all(4)
		cell.add_theme_stylebox_override("panel", csb)
		cell.add_child(_label(str(cells[i]), 18, Color.WHITE, head))
		t1.add_child(cell)
	var h1 := CenterContainer.new()
	h1.add_child(t1)
	col.add_child(h1)
	# キャラ1人ずつ（斬った数 0 と 最大のとき）
	col.add_child(_label(_t("gacha_odds_each"), 24, Color.WHITE, true))
	var t2 := GridContainer.new()
	t2.name = "ItemTable"
	t2.columns = 4
	t2.add_theme_constant_override("h_separation", 6)
	t2.add_theme_constant_override("v_separation", 4)
	var kmax := int(logic.cfg.get("enemy_count", 5))
	var lo: Array = logic.item_odds(0)
	var hi: Array = logic.item_odds(kmax)
	for h in [_t("gacha_odds_char"), _t("gacha_odds_rarity"), _t("gacha_odds_kills_n") % 0, _t("gacha_odds_kills_n") % kmax]:
		t2.add_child(_label(h, 17, Color(str(_k("sub_text", "#b9c4dc"))), true))
	for i in lo.size():
		var d := CharacterData.find(f.characters_cfg, str(lo[i]["id"]))
		var nl := _label(str(d.get("name", lo[i]["id"])), 19, Color.WHITE, true)
		nl.custom_minimum_size = Vector2(150, 34)
		t2.add_child(nl)
		t2.add_child(_pill(str(lo[i]["rarity"]), _rarity_color(str(lo[i]["rarity"])).darkened(0.25), 16))
		var a := _label("%.2f%%" % (float(lo[i]["p"]) * 100.0), 19, Color.WHITE)
		a.custom_minimum_size = Vector2(130, 0)
		t2.add_child(a)
		var b := _label("%.2f%%" % (float(hi[i]["p"]) * 100.0), 19, Color(str(_k("gold", "#ffd45a"))))
		b.custom_minimum_size = Vector2(130, 0)
		t2.add_child(b)
	var h2 := CenterContainer.new()
	h2.add_child(t2)
	col.add_child(h2)
	var rules := _label(_t("gacha_rules_note"), 17, Color(1, 1, 1, 0.55))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(580, 0)
	col.add_child(rules)
	var close: Array = _big(_t("back_label"), false, func():
		odds_box.visible = false
		refresh(), 400)
	col.add_child(close[0])
	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(0, 40)
	col.add_child(pad2)
	odds_box.visible = false
	root.add_child(odds_box)


# ---------------------------------------------------------------- 入る・出る

## ガチャの画面に入った：3Dの場面を作る（ロビーの3Dは隠す）
func enter() -> void:
	if stage == null or not is_instance_valid(stage):
		if f.is_inside_tree():
			stage = GachaStage.new()
			stage.setup(f.characters_cfg, logic)
			f.add_child(stage)
			stage.killed.connect(_on_killed)
			stage.slashed.connect(func(): _sfx("slash"))
			stage.finished.connect(_on_finished)
			var win: Window = f.get_window()
			if win != null:
				stage.fit_camera(Vector2(win.size))
	if stage != null:
		stage.camera.current = true
	if logic.state == "result":
		logic.reset()
	if logic.state != "idle":
		logic.state = "idle"
	_new_round()
	result_box.visible = false
	confirm_box.visible = false
	odds_box.visible = false


## ガチャの画面から出た：3Dの場面を消す（重くしない）
func exit() -> void:
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	pressing = false


func leave() -> void:
	if logic.state in ["flying"]:
		return  # 斬っている間は もどれない（コインだけ減ることがないように）
	f.event("back")


func _new_round() -> void:
	if stage != null:
		stage.new_round(logic.layout(rng))
	counter.text = ""
	power_box.visible = false
	_refresh_odds_row(0)
	refresh()


func refresh() -> void:
	var coins := int(f.save.get("coins", 0))
	coin_label.text = str(coins)
	var pulls := int(f.save.get("gacha_count", 0))
	cost_label.text = _t("gacha_free") if logic.free_now(pulls) else _t("gacha_cost") % logic.cost()
	var can: bool = logic.can_pay(coins, pulls)
	hint.visible = logic.state == "idle"
	hint_label.text = _t("gacha_hint") if can else _t("gacha_no_coins")
	if back_button != null:
		back_button.disabled = logic.state == "flying"
	if f.lobby_ui != null:
		f.lobby_ui.set_nav_selected(f.state)


func _sfx(name: String) -> void:
	if f.menu_sfx != null:
		f.menu_sfx.play(name)


# ---------------------------------------------------------------- 引く・離す

func on_input(ev: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var moved := false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		pressed = ev.pressed
		released = not ev.pressed
	elif ev is InputEventScreenTouch:
		pos = ev.position
		pressed = ev.pressed
		released = not ev.pressed
	elif ev is InputEventMouseMotion or ev is InputEventScreenDrag:
		pos = ev.position
		moved = true
	else:
		return
	if pressed:
		grab(pos)
	elif moved and pressing:
		drag(pos)
	elif released and pressing:
		release(pos)


## つかむ：剣士の近くを押したら（コインが足りなければ、お知らせ）
func grab(pos: Vector2, force: bool = false) -> bool:
	if logic.state != "idle" or result_box.visible or confirm_box.visible or odds_box.visible:
		return false
	var hp: Vector2 = stage.hero_screen_point() if stage != null else Vector2(-9999, -9999)
	if not force and pos.distance_to(hp) > float(f.config.get("gacha_grab_px", 190.0)):
		return false
	var coins := int(f.save.get("coins", 0))
	var pulls := int(f.save.get("gacha_count", 0))
	if not logic.start_aim(coins, pulls):
		f.toast_label.text = _t("gacha_no_coins")
		f.toast_time = 2.0
		return false
	pressing = true
	press_pos = pos
	hint.visible = false
	power_box.visible = true
	refresh()
	_sfx("click")
	drag(pos)
	return true


func _aim(pos: Vector2) -> Dictionary:
	var pull := pos - press_pos
	var aim: Dictionary = logic.aim_from_pull(pull)
	aim["raw"] = clampf(pull.length() / float(logic.cfg.get("pull_max_px", 300.0)), 0.0, 1.0) if pull.y > 0.0 else 0.0
	return aim


func drag(pos: Vector2) -> void:
	if logic.state != "aiming":
		return
	var aim := _aim(pos)
	power_bar.value = float(aim["raw"])
	power_label.text = "%d%%" % int(round(float(aim["raw"]) * 100.0))
	if stage != null:
		stage.set_pull(aim)


## 離す：強さが足りなければやめる。足りれば、払って（はじめの1回は無料）、飛び出す
func release(pos: Vector2) -> bool:
	pressing = false
	power_box.visible = false
	if logic.state != "aiming":
		return false
	var aim := _aim(pos)
	if float(aim["power"]) <= 0.0:
		logic.cancel_aim()
		if stage != null:
			stage.clear_pull()
		refresh()
		return false
	var coins := int(f.save.get("coins", 0))
	var pulls := int(f.save.get("gacha_count", 0))
	var pay: int = logic.launch(coins, pulls)
	if pay < 0:
		return false
	f.save["coins"] = coins - pay
	f.save["gacha_count"] = pulls + 1
	f._write_save()
	counter.text = _t("gacha_counter") % [0, int(logic.cfg.get("enemy_count", 5))]
	_sfx("whoosh")
	if stage != null:
		stage.launch(aim)
	refresh()
	return true


func _on_killed(index: int, _at: Vector3) -> void:
	if not logic.add_kill(index):
		return
	_sfx("hit")
	counter.text = _t("gacha_counter") % [logic.kill_count(), int(logic.cfg.get("enemy_count", 5))]
	if counter.is_inside_tree():
		counter.pivot_offset = counter.size * 0.5
		counter.scale = Vector2(1.5, 1.5)
		counter.create_tween().tween_property(counter, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_odds_row(logic.kill_count())


## 斬り終わった：結果を決めて、1回だけ渡す（新しいキャラは持っているキャラへ、もう持っていればコインが少しもどる）
func _on_finished() -> void:
	var res: Dictionary = logic.finish(rng, f.owned)
	if res.is_empty():
		return
	if logic.take_grant():
		if bool(res["new"]):
			f.add_owned(str(res["id"]))
		else:
			f.save["coins"] = int(f.save.get("coins", 0)) + int(res["refund"])
			f._write_save()
	last_result = res
	show_result(res)
	refresh()


# ---------------------------------------------------------------- 結果

func show_result(res: Dictionary) -> void:
	f._clear_box(result_card)
	var r := str(res["rarity"])
	var rc := _rarity_color(r)
	var id := str(res["id"])
	var d := CharacterData.find(f.characters_cfg, id)
	var prof: Dictionary = Roster.profile(f.profiles, id)
	# レア度の札・星・NEW
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	top.add_child(_pill(r, rc.darkened(0.15), 26))
	for i in int((f.profiles.get("rarity_stars", {}) as Dictionary).get(r, 1)):
		var s := LobbyIcon.new("star", rc.lightened(0.25))
		s.custom_minimum_size = Vector2(34, 34)
		top.add_child(s)
	if bool(res["new"]):
		top.add_child(_pill(_t("gacha_new"), Color("#e8304a"), 24))
	result_card.add_child(top)
	# 顔（レア度の色の光るふち）
	var face_holder := CenterContainer.new()
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(300, 300)
	var glow := FancyRect.new().setup(rc.lightened(0.2), rc.darkened(0.3), 40, Color(rc.r, rc.g, rc.b, 0.85), 18)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(glow)
	var face: Control = f.formation_ui.portrait_box(id, Vector2(280, 280), 34)
	face.position = Vector2(10, 10)
	frame.add_child(face)
	face_holder.add_child(frame)
	result_card.add_child(face_holder)
	var name_l := UiKit.outline(_label(str(d.get("name", id)), 52, Color.WHITE, true), 10)
	result_card.add_child(name_l)
	var role_c := CenterContainer.new()
	role_c.add_child(_pill(str(d.get("role", "")), f.lobby_ui.role_color(str(d.get("role", ""))), 20))
	result_card.add_child(role_c)
	var desc := _label(str(prof.get("desc", "")), 20, Color("#dfe6f5"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	result_card.add_child(desc)
	var info := _label(_t("gacha_result_kills") % [int(res["kills"]), int(logic.cfg.get("enemy_count", 5))], 24, Color(str(_k("gold", "#ffd45a"))), true)
	result_card.add_child(info)
	var orow := HBoxContainer.new()
	orow.alignment = BoxContainer.ALIGNMENT_CENTER
	orow.add_theme_constant_override("separation", 6)
	var o: Dictionary = res["odds"]
	for rr in GachaLogic.RARITIES:
		var p := _pill("%s %.1f%%" % [rr, float(o[rr]) * 100.0], _rarity_color(rr).darkened(0.25 if rr == r else 0.6), 17)
		if rr != r:
			p.modulate.a = 0.6
		orow.add_child(p)
	result_card.add_child(orow)
	if not bool(res["new"]):
		result_card.add_child(_label(_t("gacha_dup") % int(res["refund"]), 22, Color("#ffe08a"), true))
	var pulls := int(f.save.get("gacha_count", 0))
	var again: Array = _big(_t("gacha_again") % logic.cost(), true, ask_again, 520)
	again_button = again[1]
	again_button.disabled = not logic.can_pay(int(f.save.get("coins", 0)), pulls)
	if again_button.disabled:
		(again[0] as Control).get_node("Skin").set("top_color", Color("#59617a"))
		(again[0] as Control).get_node("Skin").set("bottom_color", Color("#3a4052"))
	result_card.add_child(again[0])
	result_card.add_child(_big(_t("gacha_to_lobby"), false, func():
		result_box.visible = false
		logic.reset()
		f.event("back"), 520)[0])
	result_box.visible = true
	# レア度ごとの演出
	var rays: Control = result_rays
	rays.set("color", Color(rc.r, rc.g, rc.b, 0.55))
	rays.set("rainbow", r == "SSR")
	rays.set("rays", 18 if r == "SSR" else 12)
	rays.set("power", {"N": 0.0, "R": 0.35, "SR": 0.8, "SSR": 1.0}.get(r, 0.5))
	_sfx({"N": "click", "R": "skill", "SR": "win", "SSR": "ultimate"}.get(r, "click"))
	if result_box.is_inside_tree():
		result_card.pivot_offset = Vector2(300, 400)
		result_card.scale = Vector2(0.6, 0.6)
		result_card.modulate.a = 0.0
		var tw := result_box.create_tween().set_parallel(true)
		var delay := 0.35 if r == "SSR" else 0.0
		tw.tween_property(result_card, "scale", Vector2.ONE, 0.45).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(result_card, "modulate:a", 1.0, 0.25).set_delay(delay)
		if r in ["SR", "SSR"]:
			flash.color = Color(1, 1, 1, 0.9 if r == "SSR" else 0.5)
			tw.tween_property(flash, "color:a", 0.0, 0.6)
		if r == "SSR":
			_sfx("win")


## 「もう一度 引く」：コインを使うか確かめる（はじめの無料の1回は、もう使った）
func ask_again() -> void:
	var q := confirm_box.find_child("Question", true, false) as Label
	q.text = _t("gacha_confirm") % [logic.cost(), int(f.save.get("coins", 0))]
	confirm_box.visible = true


func confirm_again() -> void:
	confirm_box.visible = false
	result_box.visible = false
	logic.reset()
	_new_round()


func open_odds() -> void:
	odds_box.visible = true
	if f.lobby_ui != null and f.lobby_ui.nav != null:
		f.lobby_ui.nav.visible = false
