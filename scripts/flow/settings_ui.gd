extends RefCounted
## 版85：プロフィールの画面の「せってい」（音楽の大きさ・効果音の大きさ・画質）。
## 大きさは、すべりバー（0〜100%）。左のアイコンを押すと、消す／もどす（0% と、前の大きさ）。
## 決めた大きさは、この端末に保存（scripts/audio/audio_settings.gd）。効果音は、動かした時に「ぽこっ」と鳴らして大きさを聞かせる。

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const LobbyIcon := preload("res://scripts/ui/lobby_icon.gd")
const AudioSettings := preload("res://scripts/audio/audio_settings.gd")

var f: Node
var card: PanelContainer
var sliders := {}  ## "music"／"sfx" → HSlider
var values := {}  ## "music"／"sfx" → Label（%）
var icons := {}  ## "music"／"sfx" → LobbyIcon
var before_mute := {"music": 0.8, "sfx": 1.0}
var bold: Font


func _init(flow: Node) -> void:
	f = flow


func _k(key: String, def: Variant) -> Variant:
	return (f.config.get("ui_kit", {}) as Dictionary).get(key, def)


func _t(key: String) -> String:
	return str((f.config.get("settings", {}) as Dictionary).get(key, key))


## box：プロフィールの縦の入れ物。index：入れる場所。quality：画質のボタン（この中へ移す）
func build(box: VBoxContainer, index: int, quality: Button) -> void:
	bold = UiKit.bold(f.font, float(_k("bold", 0.7)))
	card = PanelContainer.new()
	card.name = "SettingsCard"
	card.custom_minimum_size = Vector2(580, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := UiKit.glass(f.config, 26)
	sb.set_content_margin_all(18)
	sb.content_margin_top = 12
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var title: Label = f._make_label(_t("title"), 24, Color(str(_k("sub_text", "#b9c4dc"))))
	title.add_theme_font_override("font", bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)
	col.add_child(_slider_row("music", "music", _t("music")))
	col.add_child(_slider_row("sfx", "speaker", _t("sfx")))
	if quality != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var ic := LobbyIcon.new("sparkle", Color.WHITE)
		ic.accent = Color(str(_k("gold", "#ffd45a")))
		ic.custom_minimum_size = Vector2(48, 48)
		row.add_child(ic)
		if quality.get_parent() != null:
			quality.get_parent().remove_child(quality)
		quality.custom_minimum_size = Vector2(0, 64)
		quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quality.add_theme_font_size_override("font_size", 24)
		UiKit.glass_button(quality, f.config, 20, Color("#2d4a7ae0"))
		UiKit.juice(quality, 0.96)
		row.add_child(quality)
		col.add_child(row)
	card.add_child(col)
	box.add_child(card)
	box.move_child(card, mini(index, box.get_child_count() - 1))
	refresh()


func _slider_row(key: String, icon_kind: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.add_theme_constant_override("separation", 14)
	# 左：アイコン（押すと消す／もどす）
	var mute := Button.new()
	mute.name = "Mute_" + key
	mute.focus_mode = Control.FOCUS_NONE
	mute.custom_minimum_size = Vector2(56, 56)
	UiKit.clear_button(mute)
	var ic := LobbyIcon.new(icon_kind, Color.WHITE)
	ic.accent = Color("#ff6b5a")
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 4
	ic.offset_top = 4
	ic.offset_right = -4
	ic.offset_bottom = -4
	mute.add_child(ic)
	mute.pressed.connect(func(): toggle_mute(key))
	UiKit.juice(mute)
	row.add_child(mute)
	icons[key] = ic
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	var name_label: Label = f._make_label(text, 22, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	mid.add_child(name_label)
	var s := HSlider.new()
	s.name = "Slider_" + key
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(0, 40)
	s.focus_mode = Control.FOCUS_NONE
	_style_slider(s)
	s.value_changed.connect(func(v: float): set_volume(key, v, true))
	mid.add_child(s)
	row.add_child(mid)
	var val: Label = f._make_label("", 24, Color(str(_k("gold", "#ffd45a"))))
	val.add_theme_font_override("font", bold)
	val.custom_minimum_size = Vector2(84, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	sliders[key] = s
	values[key] = val
	return row


## すべりバーの見た目：暗いみぞ・金色に光る中身・白い丸のつまみ（画像は使わず、その場で丸を作る）
func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#060a14c0")
	track.set_corner_radius_all(UiKit.corner(f.config, 9))
	track.content_margin_top = 9
	track.content_margin_bottom = 9
	track.border_color = Color("#ffffff22")
	track.set_border_width_all(1)
	track.anti_aliasing = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(str(_k("gold", "#ffd45a")))
	fill.set_corner_radius_all(UiKit.corner(f.config, 9))
	fill.content_margin_top = 9
	fill.content_margin_bottom = 9
	fill.shadow_color = Color(1.0, 0.75, 0.25, 0.45)
	fill.shadow_size = 6
	fill.anti_aliasing = true
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob(34)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)


static func _knob(px: int) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			var r := c - 1.0
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var shade := 1.0 - clampf((float(y) - c) / r, 0.0, 1.0) * 0.12
			var ring := absf(d - (r - 2.5)) < 1.6
			var col := Color(shade, shade, shade * 0.97, a)
			if ring and a > 0.0:
				col = Color(1.0, 0.85, 0.4, a)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func refresh() -> void:
	for key in sliders:
		var v := float(f.audio_settings.get(key, 1.0))
		(sliders[key] as HSlider).set_value_no_signal(v)
		_show(key, v)


func _show(key: String, v: float) -> void:
	(values[key] as Label).text = "%d%%" % int(round(v * 100.0))
	var ic: LobbyIcon = icons.get(key)
	if ic != null and key == "sfx":
		ic.set_kind("speaker_off" if v <= 0.001 else "speaker")
	if ic != null:
		ic.modulate = Color(1, 1, 1, 0.45) if v <= 0.001 else Color.WHITE


## 大きさを変える（すべりバー・アイコン）。保存して、すぐ音に反映する
func set_volume(key: String, v: float, from_slider: bool = false) -> void:
	v = clampf(v, 0.0, 1.0)
	f.set_audio_volume(key, v)
	_show(key, v)
	if not from_slider and sliders.has(key):
		(sliders[key] as HSlider).set_value_no_signal(v)
	if key == "sfx" and v > 0.001 and f.menu_sfx != null:
		f.menu_sfx.play("click")


func toggle_mute(key: String) -> void:
	var now := float(f.audio_settings.get(key, 1.0))
	if now > 0.001:
		before_mute[key] = now
		set_volume(key, 0.0)
	else:
		set_volume(key, maxf(0.2, float(before_mute.get(key, 0.8))))
