extends RefCounted
## 版82：編成の画面（game_flow.gd から分けた）。
## 上：4つの枠（メイン＋なかま3人。顔の絵・名前・役の色）。
## まんなか：選んだキャラのくわしい情報（顔・レア度・名前・役・装備2枠（まだ空）・説明・体力/攻撃/防御/速さ/届く・技の名前・覚醒）。
## 下：キャラの一覧（顔の絵のカード。持っていないキャラは暗く、かぎ）。
## 入れかえ：枠をタップ → 別の枠をタップで入れかえ、または一覧のキャラをタップで、その枠に入れる。
##           一覧のキャラをタップだけなら、くわしい情報を見る（「この枠に セット」で入れる）。
## 版87：キャラ（枠・一覧）を長押しすると持ち上がり、指についてくる。枠の上で離すと入る（キャラが入っている枠なら、2人が入れかわる）。
##       枠の外で離すと、元にもどる。少し動かしてから長押しにならなければ、ふつうのスクロール。画面は下までスクロールできる。
##       ロビーでキャラをタップすると、そのキャラの枠を選んだ状態で、この画面が開く（open_slot）。
## 編成のデータ：メイン＝selected_character、なかま＝ai_picks（ロビー・戦いと同じ）。持っているキャラだけ入れられる。

const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const FancyRect := preload("res://scripts/ui/fancy_rect.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const Roster := preload("res://scripts/flow/roster.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const RoleLabel := preload("res://scripts/ui/role_label.gd")

var f: Node
var lobby_ui: RefCounted
var root: Control
var slot_buttons: Array = []
var card_buttons: Dictionary = {}  # id → Button
var selected_slot := 0
var armed_slot := -1  # 枠をタップした直後（次のタップで入れかえる）
var focus_id := ""
var hint_label: Label
var grid: GridContainer
var detail: Dictionary = {}  # くわしい情報の部品
var set_button: Button
var bold: Font
var scroll: ScrollContainer
var drag_layer: Control  ## 版87：持ち上げたキャラの絵（いちばん上）
var press: Dictionary = {}  ## 版87：押している所 {kind: "slot"/"card", key, pos, t, moved}
var dragging := false
var ghost: Control = null
var hover_slot := -1
var drag_log: Array = []  ## テスト用（lift・drop・cancel）


func _init(flow: Node, lui: RefCounted) -> void:
	f = flow
	lobby_ui = lui


func _k(key: String, def: Variant) -> Variant:
	return (f.config.get("ui_kit", {}) as Dictionary).get(key, def)


func _label(text: String, size: int, color: Color, use_bold: bool = false) -> Label:
	var l: Label = f._make_label(text, size, color)
	if use_bold and bold != null:
		l.add_theme_font_override("font", bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(color: Color, radius: int, margin: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


func _rarity_color(r: String) -> Color:
	return Color(str((f.profiles.get("rarity_colors", {}) as Dictionary).get(r, "#9aa4b8")))


## 顔の絵の入った、角の丸い枠（役の色の背景・下に暗いグラデーション）
func portrait_box(id: String, box_size: Vector2, radius: int) -> Control:
	var d := CharacterData.find(f.characters_cfg, id)
	var frame := Panel.new()
	frame.custom_minimum_size = box_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var role_col: Color = lobby_ui.role_color(str(d.get("role", "")))
	frame.add_theme_stylebox_override("panel", _style(role_col.darkened(0.35), radius))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var bgfx := FancyRect.new().setup(role_col.darkened(0.05), role_col.darkened(0.55), radius)
	bgfx.shine = 0.12
	bgfx.border_width = 0.0
	bgfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(bgfx)
	var ph := LobbyIcon.new("person", Color(1, 1, 1, 0.55))
	ph.name = "Placeholder"
	ph.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(ph)
	var tr := TextureRect.new()
	tr.name = "Face"
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tr)
	if f.portraits != null and not d.is_empty():
		f.portraits.request(id, d, func(tex: Texture2D):
			if is_instance_valid(tr):
				tr.texture = tex
				ph.visible = false)
	return frame


func _rarity_pill(r: String, font_size: int = 15) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := _rarity_color(r)
	var sb := _style(c.darkened(0.15), 8, 2)
	sb.set_content_margin(SIDE_LEFT, 7)
	sb.set_content_margin(SIDE_RIGHT, 7)
	sb.set_border_width_all(1)
	sb.border_color = c.lightened(0.45)
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(r, font_size, Color.WHITE, true)
	UiKit.outline(l, 3, Color(0, 0, 0, 0.5))
	p.add_child(l)
	return p


# ---------------------------------------------------------------- 画面を作る

func build() -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	root = Control.new()
	root.name = Logic.FORMATION
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := FancyRect.new().setup(Color("#1b2140"), Color("#0b0e1c"), 0)
	bg.shine = 0.0
	bg.border_width = 0.0
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	scroll.add_child(page)
	drag_layer = Control.new()
	drag_layer.name = "DragLayer"
	drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(drag_layer)
	f.layer.add_child(root)
	f.panels[Logic.FORMATION] = root

	# 見出し
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	head.add_child(pad)
	var back: Button = lobby_ui.icon_button("left", "", Vector2(64, 64), 1, Color(str(_k("arrow_color", "#0e1526a0"))), func(): f.event("back"), 32)
	back.name = "Back"
	head.add_child(back)
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 0)
	var title := _label(str(f.config["formation_title"]), 40, Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hcol.add_child(title)
	hint_label = _label("", 19, Color(str(_k("sub_text", "#b9c4dc"))))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hcol.add_child(hint_label)
	head.add_child(hcol)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 8)
	page.add_child(top_pad)
	page.add_child(head)

	# 4つの枠
	var slots_row := HBoxContainer.new()
	slots_row.name = "Slots"
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_row.add_theme_constant_override("separation", 10)
	slot_buttons = []
	for i in Roster.TEAM_SIZE:
		var b := Button.new()
		b.name = "Slot%d" % i
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(146, 200)
		UiKit.clear_button(b)
		b.mouse_filter = Control.MOUSE_FILTER_PASS  # 版87：押したまま動かすと、スクロールできる
		b.gui_input.connect(func(ev: InputEvent): _on_pointer(ev, "slot", i, b))
		UiKit.juice(b)
		slot_buttons.append(b)
		slots_row.add_child(b)
	page.add_child(slots_row)

	# くわしい情報
	page.add_child(_build_detail())

	# 一覧
	var list_head := _label(str(f.config["formation_list_title"]), 24, Color.WHITE, true)
	page.add_child(list_head)
	var gholder := CenterContainer.new()
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	gholder.add_child(grid)
	page.add_child(gholder)
	var nav_space := Control.new()
	nav_space.custom_minimum_size = Vector2(0, float(f.config["nav_height"]) + 20)
	page.add_child(nav_space)


func _build_detail() -> Control:
	var card := PanelContainer.new()
	card.name = "Detail"
	card.custom_minimum_size = Vector2(612, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var csb := UiKit.glass(f.config, 24)
	csb.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", csb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var face_holder := Control.new()
	face_holder.name = "FaceHolder"
	face_holder.custom_minimum_size = Vector2(150, 150)
	top.add_child(face_holder)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	var rholder := Control.new()
	rholder.name = "RarityHolder"
	rholder.custom_minimum_size = Vector2(56, 26)
	rrow.add_child(rholder)
	var stars := HBoxContainer.new()
	stars.name = "Stars"
	stars.add_theme_constant_override("separation", 2)
	rrow.add_child(stars)
	info.add_child(rrow)
	# 版109：名前は、役職のラベル（役職の色の札）
	var name_l: Control = RoleLabel.new().setup("", Color.WHITE, UiKit.bold(f.font, 0.75), 32)
	name_l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(name_l)
	var role_row := HBoxContainer.new()
	var role_holder := PanelContainer.new()
	role_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var role_l := _label("", 18, Color.WHITE, true)
	role_holder.add_child(role_l)
	role_row.add_child(role_holder)
	var own_l := _label("", 18, Color(str(_k("sub_text", "#b9c4dc"))))
	role_row.add_child(own_l)
	role_row.add_theme_constant_override("separation", 10)
	info.add_child(role_row)
	# 装備の2枠（まだ空）
	var equip := HBoxContainer.new()
	equip.add_theme_constant_override("separation", 8)
	for i in 2:
		var e := PanelContainer.new()
		e.custom_minimum_size = Vector2(170, 46)
		var esb := _style(Color(1, 1, 1, 0.05), 12, 4)
		esb.set_border_width_all(2)
		esb.border_color = Color(1, 1, 1, 0.18)
		e.add_theme_stylebox_override("panel", esb)
		var el := _label(str(f.config["formation_equip_empty"]) % (i + 1), 16, Color(1, 1, 1, 0.45))
		e.add_child(el)
		equip.add_child(e)
	info.add_child(equip)
	top.add_child(info)
	col.add_child(top)
	var desc := _label("", 20, Color("#dfe6f5"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.custom_minimum_size = Vector2(580, 0)
	col.add_child(desc)
	# 能力（数とバー）
	var stats := GridContainer.new()
	stats.name = "Stats"
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 18)
	stats.add_theme_constant_override("v_separation", 6)
	col.add_child(stats)
	# 技
	var moves := VBoxContainer.new()
	moves.name = "Moves"
	moves.add_theme_constant_override("separation", 6)
	col.add_child(moves)
	var note := _label(str(f.config["formation_note"]), 15, Color(1, 1, 1, 0.45))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(580, 0)
	col.add_child(note)
	# この枠に セット
	var sh := Control.new()
	sh.custom_minimum_size = Vector2(580, 84)
	var skin := FancyRect.new().setup(Color(str(_k("play_top", "#ffb84d"))), Color(str(_k("play_bottom", "#f04e23"))), 22, Color(str(_k("play_glow", "#ff7a2a"))), 6)
	skin.name = "Skin"
	skin.set_anchors_preset(Control.PRESET_FULL_RECT)
	sh.add_child(skin)
	set_button = f._make_button("", [580, 84], set_focus_to_slot)
	set_button.name = "SetButton"
	set_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.clear_button(set_button)
	if bold != null:
		set_button.add_theme_font_override("font", bold)
	set_button.add_theme_font_size_override("font_size", 30)
	set_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	sh.add_child(set_button)
	col.add_child(sh)
	card.add_child(col)
	detail = {"face": face_holder, "rarity": rholder, "stars": stars, "name": name_l, "role": role_l, "role_holder": role_holder, "own": own_l,
		"desc": desc, "stats": stats, "moves": moves, "skin": skin}
	return card


# ---------------------------------------------------------------- 表示を合わせる

func team() -> Array:
	return lobby_ui.team()


func refresh() -> void:
	if root == null:
		return
	var t := team()
	if focus_id == "" or CharacterData.find(f.characters_cfg, focus_id).is_empty():
		focus_id = str(t[selected_slot]) if selected_slot < t.size() else str(t[0])
	_refresh_slots(t)
	_refresh_grid(t)
	_refresh_detail(t)
	hint_label.text = str(f.config["formation_hint_armed"]) if armed_slot >= 0 else str(f.config["formation_hint"])
	# 版87：止める設定の部品（パネル・字の入れ物など）を、下へ伝える設定に（どこを押して動かしても、スクロールできる）
	UiKit.scroll_friendly(scroll)


func _refresh_slots(t: Array) -> void:
	for i in slot_buttons.size():
		var b: Button = slot_buttons[i]
		for c in b.get_children():
			b.remove_child(c)
			c.queue_free()
		var col := VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 4)
		var tag := _label(str(f.config["formation_main"]) if i == 0 else str(f.config["formation_mate"]) % i, 17,
			Color(str(_k("gold", "#ffd45a"))) if i == 0 else Color(str(_k("sub_text", "#b9c4dc"))), true)
		col.add_child(tag)
		var holder := CenterContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < t.size():
			var id := str(t[i])
			holder.add_child(portrait_box(id, Vector2(132, 132), 20))
			col.add_child(holder)
			var d := CharacterData.find(f.characters_cfg, id)
			col.add_child(_label(str(d.get("name", id)), 20, Color.WHITE, true))
		else:
			var empty := PanelContainer.new()
			empty.custom_minimum_size = Vector2(132, 132)
			var esb := _style(Color(1, 1, 1, 0.05), 20)
			esb.set_border_width_all(2)
			esb.border_color = Color(1, 1, 1, 0.25)
			empty.add_theme_stylebox_override("panel", esb)
			empty.add_child(_label(str(f.config["formation_empty"]), 22, Color(1, 1, 1, 0.6), true))
			holder.add_child(empty)
			col.add_child(holder)
		b.add_child(col)
		# 選んでいる枠：金のふちと光（入れかえ待ちは、もっと強く）
		if i == selected_slot:
			var mark := FancyRect.new().setup(Color(1, 0.8, 0.3, 0.1), Color(1, 0.6, 0.2, 0.04), 22,
				Color(1, 0.7, 0.25, 0.9 if armed_slot == i else 0.45), 10 if armed_slot == i else 6)
			mark.shine = 0.0
			mark.border_color = Color(str(_k("gold", "#ffd45a")))
			mark.border_width = 3.0
			mark.set_anchors_preset(Control.PRESET_FULL_RECT)
			mark.show_behind_parent = true
			b.add_child(mark)


func _columns() -> int:
	var w := 648.0
	if f.get_viewport() != null:
		w = f.get_viewport().get_visible_rect().size.x
	return clampi(int((w - 24.0) / 150.0), 3, 7)


func _refresh_grid(t: Array) -> void:
	grid.columns = _columns()
	f._clear_box(grid)
	card_buttons = {}
	var owned: Array = f.owned
	for c in f.characters_cfg.get("characters", []):
		var id := str(c["id"])
		var b := Button.new()
		b.name = "Card_" + id
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 178)
		UiKit.clear_button(b)
		var box := portrait_box(id, Vector2(140, 178), 18)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(box)
		var shade := UiKit.vignette(false, 70, Color(0.02, 0.03, 0.08, 0.95))
		box.add_child(shade)
		var nm := UiKit.outline(_label(str(c["name"]), 21, Color.WHITE, true), 4)
		nm.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		nm.offset_top = -36
		nm.offset_bottom = -6
		b.add_child(nm)
		var rp := _rarity_pill(Roster.rarity(f.profiles, id))
		rp.position = Vector2(6, 6)
		b.add_child(rp)
		var in_team := t.find(id)
		if in_team >= 0:
			var badge := PanelContainer.new()
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bsb := _style(Color(str(_k("play_bottom", "#f04e23"))), 10, 2)
			bsb.set_content_margin(SIDE_LEFT, 6)
			bsb.set_content_margin(SIDE_RIGHT, 6)
			badge.add_theme_stylebox_override("panel", bsb)
			badge.add_child(_label(str(f.config["formation_main"]) if in_team == 0 else str(f.config["formation_mate"]) % in_team, 14, Color.WHITE, true))
			b.add_child(badge)
			badge.reset_size()
			badge.position = Vector2(140.0 - badge.get_combined_minimum_size().x - 6.0, 6.0)
		if not owned.has(id):
			var dim := ColorRect.new()
			dim.color = Color(0.02, 0.03, 0.08, 0.62)
			dim.set_anchors_preset(Control.PRESET_FULL_RECT)
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(dim)
			var lock := LobbyIcon.new("lock", Color(1, 1, 1, 0.8))
			b.add_child(lock)
			lock.size = Vector2(46, 46)
			lock.position = Vector2(47, 44)
			var nl := _label(str(f.config["formation_not_owned"]), 15, Color(1, 1, 1, 0.8), true)
			nl.position = Vector2(0, 96)
			nl.size = Vector2(140, 22)
			b.add_child(nl)
		if id == focus_id:
			# 見ているキャラ：金のふちと、外へのやわらかい光（中はおおわない）
			var mark := Panel.new()
			mark.name = "Focus"
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var msb := _style(Color(0, 0, 0, 0), 18)
			msb.set_border_width_all(4)
			msb.border_color = Color(str(_k("gold", "#ffd45a")))
			mark.add_theme_stylebox_override("panel", msb)
			mark.set_anchors_preset(Control.PRESET_FULL_RECT)
			b.add_child(mark)
			var glow := Panel.new()
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glow.show_behind_parent = true
			var gsb := _style(Color(1, 0.75, 0.3, 0.9), 18)
			gsb.shadow_color = Color(1, 0.65, 0.2, 0.6)
			gsb.shadow_size = 12
			glow.add_theme_stylebox_override("panel", gsb)
			glow.set_anchors_preset(Control.PRESET_FULL_RECT)
			b.add_child(glow)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.gui_input.connect(func(ev: InputEvent): _on_pointer(ev, "card", id, b))
		UiKit.juice(b)
		card_buttons[id] = b
		grid.add_child(b)


func _refresh_detail(t: Array) -> void:
	var id := focus_id
	var d := CharacterData.find(f.characters_cfg, id)
	var pr: Dictionary = Roster.profile(f.profiles, id)
	var r := Roster.rarity(f.profiles, id)
	var face: Control = detail["face"]
	f._clear_box(face)
	face.add_child(portrait_box(id, Vector2(150, 150), 24))
	var rh: Control = detail["rarity"]
	f._clear_box(rh)
	rh.add_child(_rarity_pill(r, 18))
	var stars: HBoxContainer = detail["stars"]
	f._clear_box(stars)
	for k in int((f.profiles.get("rarity_stars", {}) as Dictionary).get(r, 1)):
		var si := LobbyIcon.new("star", _rarity_color(r).lightened(0.2))
		si.custom_minimum_size = Vector2(24, 24)
		stars.add_child(si)
	detail["name"].text = str(d.get("name", id))
	detail["name"].color = Color(str(d.get("role_color", "#ffffff")))
	var role := str(d.get("role", ""))
	(detail["role"] as Label).text = role
	var rc: Color = lobby_ui.role_color(role)
	var psb := _style(rc, 12, 3)
	psb.set_content_margin(SIDE_LEFT, 12)
	psb.set_content_margin(SIDE_RIGHT, 12)
	(detail["role_holder"] as PanelContainer).add_theme_stylebox_override("panel", psb)
	var owned: bool = f.owned.has(id)
	(detail["own"] as Label).text = str(f.config["formation_owned"]) if owned else str(f.config["formation_not_owned_long"])
	(detail["desc"] as Label).text = str(pr.get("desc", ""))
	# 能力
	var stats: GridContainer = detail["stats"]
	f._clear_box(stats)
	var st: Dictionary = d.get("stats", {})
	var labels: Dictionary = f.config["stat_labels"]
	var maxes: Dictionary = f.config["formation_stat_max"]
	var rows := [["hp", float(st.get("hp", 0)), "%d" % ceili(float(st.get("hp", 0)))],
		["attack_power", float(st.get("attack_power", 0)), "%.1f" % float(st.get("attack_power", 0))],
		["defense", float(pr.get("defense", 0)), "%d" % int(pr.get("defense", 0))],
		["move_speed", float(st.get("move_speed", 0)), "%.1f" % float(st.get("move_speed", 0))],
		["attack_reach", float(st.get("attack_reach", 0)), "%.1fm" % float(st.get("attack_reach", 0))]]
	for row in rows:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var nl := _label(str(labels.get(row[0], row[0])), 18, Color(str(_k("sub_text", "#b9c4dc"))))
		nl.custom_minimum_size = Vector2(90, 0)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cell.add_child(nl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = float(maxes.get(row[0], 100.0))
		bar.value = float(row[1])
		bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.12), 5))
		bar.add_theme_stylebox_override("fill", _style(rc.lightened(0.15), 5))
		cell.add_child(bar)
		var vl := _label(str(row[2]), 19, Color.WHITE, true)
		vl.custom_minimum_size = Vector2(66, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.add_child(vl)
		stats.add_child(cell)
	# 技
	var moves: VBoxContainer = detail["moves"]
	f._clear_box(moves)
	var acts: Dictionary = Actions.config_for(id).get("actions", {})
	var move_rows := [["normal", "formation_move_normal"], ["sub", "formation_move_sub"], ["main", "formation_move_main"], ["ultimate", "formation_move_ult"]]
	for mr in move_rows:
		var a: Dictionary = acts.get(mr[0], {})
		moves.add_child(_move_row(str(f.config[mr[1]]), str(a.get("name", "-")), rc))
	var aw: Dictionary = pr.get("awaken", {})
	moves.add_child(_move_row(str(f.config["formation_move_awaken"]), str(aw.get("name", "-")) + "：" + str(aw.get("text", "")), Color("#8a6cff")))
	# セットの ボタン
	var in_slot := t.find(id)
	var can := owned and in_slot != selected_slot
	set_button.disabled = not can
	var skin: Control = detail["skin"]
	skin.top_color = Color(str(_k("play_top", "#ffb84d"))) if can else Color("#59617a")
	skin.bottom_color = Color(str(_k("play_bottom", "#f04e23"))) if can else Color("#3a4052")
	skin.glow_color = Color(str(_k("play_glow", "#ff7a2a"))) if can else Color(0, 0, 0, 0)
	if not owned:
		set_button.text = str(f.config["formation_set_locked"])
	elif in_slot == selected_slot:
		set_button.text = str(f.config["formation_set_already"])
	else:
		set_button.text = (str(f.config["formation_set_main"]) if selected_slot == 0 else str(f.config["formation_set_mate"]) % selected_slot)


func _move_row(tag: String, text: String, col: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(118, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _style(col.darkened(0.35), 10, 3)
	sb.set_border_width_all(1)
	sb.border_color = col.lightened(0.2)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(tag, 15, Color.WHITE, true))
	row.add_child(p)
	var l := _label(text, 19, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


# ---------------------------------------------------------------- 操作

## 枠をタップ：入れかえ待ちの時に別の枠なら入れかえ。そうでなければ、その枠を選んで入れかえ待ちに
func tap_slot(i: int) -> void:
	var t := team()
	if armed_slot >= 0 and armed_slot != i:
		_apply(Roster.swap(t, armed_slot, i))
		selected_slot = i
		armed_slot = -1
	elif armed_slot == i:
		armed_slot = -1
	else:
		selected_slot = i
		armed_slot = i
	focus_id = str(team()[selected_slot]) if selected_slot < team().size() else focus_id
	refresh()


## 一覧のキャラをタップ：入れかえ待ちなら、その枠に入れる。そうでなければ、くわしい情報を見る
func tap_card(id: String) -> void:
	focus_id = id
	if armed_slot >= 0:
		if f.owned.has(id):
			_apply(Roster.assign(team(), armed_slot, id))
			armed_slot = -1
		else:
			f.toast_label.text = str(f.config["formation_set_locked"])
			f.toast_time = 2.0
	refresh()


## くわしい情報のキャラを、選んでいる枠に入れる
func set_focus_to_slot() -> void:
	if not f.owned.has(focus_id):
		return
	_apply(Roster.assign(team(), selected_slot, focus_id))
	armed_slot = -1
	refresh()


func _apply(t: Array) -> void:
	lobby_ui._apply_team(t)


# ---------------------------------------------------------------- 版87：長押しで持って入れかえる

func _cfg_f(key: String, def: float) -> float:
	return float(f.config.get(key, def))


## 枠・カードの押す・動かす・離す（マウスと、タッチから作られるマウスの出来事）。座標は、画面（キャンバス）の位置にそろえる
func _on_pointer(ev: InputEvent, kind: String, key: Variant, ctrl: Control) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var gp: Vector2 = ctrl.get_global_transform() * (ev as InputEventMouseButton).position
		if (ev as InputEventMouseButton).pressed:
			pointer_down(kind, key, gp)
		else:
			var was := dragging
			pointer_up(gp)
			if was:
				ctrl.accept_event()
	elif ev is InputEventMouseMotion and not press.is_empty():
		pointer_move(ctrl.get_global_transform() * (ev as InputEventMouseMotion).position)
		if dragging:
			ctrl.accept_event()  # 持っている間は、スクロールしない


func pointer_down(kind: String, key: Variant, pos: Vector2) -> void:
	_end_drag(false)
	press = {"kind": kind, "key": key, "pos": pos, "t": 0.0, "moved": false, "last": pos}


func pointer_move(pos: Vector2) -> void:
	if press.is_empty():
		return
	press["last"] = pos
	if dragging:
		_move_ghost(pos)
		return
	if pos.distance_to(press["pos"]) > _cfg_f("formation_drag_tolerance_px", 14.0):
		press["moved"] = true  # 長押しの前に動いた：スクロール


## 毎コマ（編成の画面の時。game_flow._process から）：動かさずに長押しの秒になったら、持ち上げる
func tick(delta: float) -> void:
	if press.is_empty() or dragging or bool(press["moved"]):
		return
	press["t"] = float(press["t"]) + delta
	if float(press["t"]) >= _cfg_f("formation_long_press_sec", 0.35):
		_lift()


func pointer_up(pos: Vector2) -> void:
	if press.is_empty():
		return
	var p := press
	if dragging:
		drop(pos)
	elif not bool(p["moved"]):
		# 長押しにならなかった：ふつうのタップ
		press = {}
		f._on_menu_press()
		if str(p["kind"]) == "slot":
			tap_slot(int(p["key"]))
		else:
			tap_card(str(p["key"]))
	press = {}


## 持ち上げたキャラの id（枠なら、その枠のキャラ）
func _press_id() -> String:
	if str(press.get("kind", "")) == "slot":
		var t := team()
		var i := int(press["key"])
		return str(t[i]) if i < t.size() else ""
	return str(press.get("key", ""))


func _lift() -> void:
	var id := _press_id()
	if id == "":
		press["moved"] = true
		return
	if str(press["kind"]) == "card" and not f.owned.has(id):
		# 持っていないキャラは、入れられない
		press["moved"] = true
		f.toast_label.text = str(f.config["formation_set_locked"])
		f.toast_time = 2.0
		drag_log.append("locked")
		return
	dragging = true
	drag_log.append("lift:" + id)
	if f.menu_sfx != null:
		f.menu_sfx.play("pull_tick", 0.0, 1.3)
	Input.vibrate_handheld(25)
	var src := _source_control()
	if src != null:
		src.modulate = Color(1, 1, 1, 0.35)
	ghost = Control.new()
	ghost.name = "Ghost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := Vector2(132, 164)
	ghost.size = gs
	ghost.pivot_offset = gs * 0.5
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := _style(Color(0, 0, 0, 0.0), 22)
	ssb.shadow_color = Color(0, 0, 0, 0.55)
	ssb.shadow_size = 18
	ssb.shadow_offset = Vector2(0, 10)
	shadow.add_theme_stylebox_override("panel", ssb)
	shadow.position = Vector2(0, 0)
	shadow.size = Vector2(132, 132)
	ghost.add_child(shadow)
	var box := portrait_box(id, Vector2(132, 132), 22)
	box.size = Vector2(132, 132)
	ghost.add_child(box)
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rsb := _style(Color(0, 0, 0, 0), 22)
	rsb.set_border_width_all(4)
	rsb.border_color = Color(str(_k("gold", "#ffd45a")))
	ring.add_theme_stylebox_override("panel", rsb)
	ring.size = Vector2(132, 132)
	ghost.add_child(ring)
	var d := CharacterData.find(f.characters_cfg, id)
	# 名前は、暗い札の上に（下の枠の名前と重なっても読める）
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psb := _style(Color(0.04, 0.06, 0.12, 0.92), 12, 2)
	psb.set_border_width_all(2)
	psb.border_color = Color(str(_k("gold", "#ffd45a")))
	plate.add_theme_stylebox_override("panel", psb)
	plate.add_child(_label(str(d.get("name", id)), 20, Color.WHITE, true))
	plate.position = Vector2(6, 128)
	plate.size = Vector2(120, 34)
	ghost.add_child(plate)
	drag_layer.add_child(ghost)
	ghost.rotation = 0.06
	_move_ghost(press["last"])
	if ghost.is_inside_tree():
		ghost.scale = Vector2(0.9, 0.9)
		ghost.create_tween().tween_property(ghost, "scale", Vector2(1.12, 1.12), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hint_label.text = str(f.config.get("formation_hint_drag", ""))


func _source_control() -> Control:
	if str(press.get("kind", "")) == "slot":
		var i := int(press["key"])
		return slot_buttons[i] if i >= 0 and i < slot_buttons.size() else null
	return card_buttons.get(str(press.get("key", "")), null)


## 指の少し上に絵を置く（指で隠れないように）。下の枠を光らせる
func _move_ghost(pos: Vector2) -> void:
	if ghost == null:
		return
	ghost.global_position = pos - ghost.size * 0.5 + Vector2(0, -_cfg_f("formation_ghost_lift_px", 56.0))
	var hs := slot_at(pos)
	if hs != hover_slot:
		hover_slot = hs
		var src := _source_control()
		for i in slot_buttons.size():
			var b: Control = slot_buttons[i]
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2(1.08, 1.08) if i == hs else Vector2.ONE
			if i == hs:
				b.modulate = Color(1.25, 1.15, 0.9)
			elif b == src:
				b.modulate = Color(1, 1, 1, 0.35)
			else:
				b.modulate = Color.WHITE
			_drop_mark(b, i == hs)


## 置ける枠の印（金の太いふちと、外への光）。on でなければ消す
func _drop_mark(b: Control, on: bool) -> void:
	var old := b.get_node_or_null("DropMark")
	if old != null:
		b.remove_child(old)
		old.queue_free()
	if not on:
		return
	var m := Panel.new()
	m.name = "DropMark"
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _style(Color(1, 0.85, 0.35, 0.12), 22)
	sb.set_border_width_all(5)
	sb.border_color = Color(str(_k("gold", "#ffd45a")))
	sb.shadow_color = Color(1, 0.7, 0.2, 0.7)
	sb.shadow_size = 14
	m.add_theme_stylebox_override("panel", sb)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(m)


## その位置の枠（なければ -1）
func slot_at(pos: Vector2) -> int:
	for i in slot_buttons.size():
		var r: Rect2 = (slot_buttons[i] as Control).get_global_rect()
		if r.grow(6.0).has_point(pos):
			return i
	return -1


## 離した：枠の上なら入れる（キャラがいれば入れかえ）。枠の外なら元にもどす
func drop(pos: Vector2) -> bool:
	if not dragging:
		return false
	var id := _press_id()
	var target := slot_at(pos)
	var ok := false
	if target >= 0:
		var t := team()
		if str(press["kind"]) == "slot":
			var from := int(press["key"])
			if from != target:
				_apply(Roster.swap(t, from, target))
				ok = true
		else:
			if t.find(id) != target:
				_apply(Roster.assign(t, target, id))
				ok = true
	if ok:
		drag_log.append("drop:%s>%d" % [id, target])
		selected_slot = target
		focus_id = id
		armed_slot = -1
		if f.menu_sfx != null:
			f.menu_sfx.play("free")
		_end_drag(true)
		refresh()
		var b: Control = slot_buttons[target]
		if b.is_inside_tree():
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2(1.18, 1.18)
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		drag_log.append("cancel:" + id)
		_end_drag(false)
	press = {}
	return ok


## 持ち上げをやめる。placed でなければ、絵は元の所へもどって消える
func _end_drag(placed: bool) -> void:
	if not dragging and ghost == null:
		return
	var src := _source_control() if not press.is_empty() else null
	dragging = false
	hover_slot = -1
	for b in slot_buttons:
		(b as Control).scale = Vector2.ONE
		(b as Control).modulate = Color.WHITE
		_drop_mark(b, false)
	for k in card_buttons:
		(card_buttons[k] as Control).modulate = Color.WHITE
	if ghost != null and is_instance_valid(ghost):
		var g := ghost
		if not placed and src != null and is_instance_valid(src) and g.is_inside_tree() and src.is_inside_tree():
			var tw := g.create_tween().set_parallel(true)
			tw.tween_property(g, "global_position", src.get_global_rect().get_center() - g.size * 0.5, 0.18)
			tw.tween_property(g, "scale", Vector2(0.8, 0.8), 0.18)
			tw.tween_property(g, "modulate:a", 0.0, 0.18)
			tw.chain().tween_callback(g.queue_free)
		else:
			g.queue_free()
	ghost = null
	if hint_label != null:
		hint_label.text = str(f.config["formation_hint_armed"]) if armed_slot >= 0 else str(f.config["formation_hint"])


## 版87：ロビーでキャラをタップした時：その枠を選んだ状態（入れかえ待ち）で、編成の画面を開く
func open_slot(slot: int) -> void:
	var t := team()
	selected_slot = clampi(slot, 0, maxi(0, t.size() - 1))
	armed_slot = selected_slot
	focus_id = str(t[selected_slot]) if selected_slot < t.size() else focus_id
	if scroll != null:
		scroll.scroll_vertical = 0
	refresh()
