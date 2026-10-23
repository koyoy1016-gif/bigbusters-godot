extends RefCounted
## 版81b：ロビー・メニューの見た目をそろえる道具（ガラスのようなパネル・太い字・押した時の動き・上下の暗がり）。
## 色と大きさは data/game_flow.json の "ui_kit"。

const FancyRect := preload("res://scripts/ui/fancy_rect.gd")

static var _bold_cache: Dictionary = {}


## 太い字（同じフォントを太らせる。フォントのファイルは増やさない）
static func bold(font: Font, strength: float = 0.75) -> Font:
	if font == null:
		return null
	var key := str(font.get_instance_id()) + ":" + str(strength)
	if _bold_cache.has(key):
		return _bold_cache[key]
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = strength
	_bold_cache[key] = fv
	return fv


## ガラスのようなパネル：少しすける暗い色・明るいふち・下に影
static func glass(cfg: Dictionary, radius: int = -1, alpha_scale: float = 1.0) -> StyleBoxFlat:
	var k: Dictionary = cfg.get("ui_kit", {})
	var sb := StyleBoxFlat.new()
	var bg := Color(str(k.get("glass", "#0e1526b8")))
	bg.a *= alpha_scale
	sb.bg_color = bg
	sb.set_corner_radius_all(radius if radius >= 0 else int(k.get("radius", 22)))
	sb.set_border_width_all(int(k.get("border_width", 2)))
	sb.border_color = Color(str(k.get("glass_border", "#ffffff2e")))
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = int(k.get("shadow", 8))
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	sb.set_content_margin_all(10)
	return sb


## ボタンの4つの状態（ふだん・上にのせた・押している・押せない）をガラスで
static func glass_button(b: Button, cfg: Dictionary, radius: int = -1, tint: Color = Color(0, 0, 0, 0)) -> void:
	var states := {"normal": 1.0, "hover": 1.25, "pressed": 0.8, "disabled": 0.55}
	for st in states:
		var sb := glass(cfg, radius)
		if tint.a > 0.0:
			sb.bg_color = Color(tint.r, tint.g, tint.b, tint.a)
		var k: float = states[st]
		sb.bg_color = sb.bg_color.lightened(0.12) if k > 1.0 else (sb.bg_color.darkened(0.25) if k < 1.0 else sb.bg_color)
		if st == "pressed":
			sb.shadow_size = 2
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 中身を見せない（色は子の FancyRect で描く）ボタン
static func clear_button(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())


## 押した時に少しちぢみ、離すともどる（手ざわり）。何度つないでも1回だけ
static func juice(b: Control, amount: float = 0.93) -> void:
	if b.has_meta("juiced"):
		return
	b.set_meta("juiced", true)
	var set_pivot := func(): b.pivot_offset = b.size * 0.5
	b.resized.connect(set_pivot)
	if b is BaseButton:
		(b as BaseButton).button_down.connect(func():
			set_pivot.call()
			_tween_scale(b, Vector2.ONE * amount, 0.07))
		(b as BaseButton).button_up.connect(func(): _tween_scale(b, Vector2.ONE, 0.16))


static func _tween_scale(c: Control, to: Vector2, sec: float) -> void:
	if not c.is_inside_tree():
		c.scale = to
		return
	var tw := c.create_tween()
	tw.tween_property(c, "scale", to, sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 画面の上（または下）の端を暗くする帯（3Dの上でも字が読めるように）
static func vignette(top: bool, height: float, color: Color) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, color if top else Color(color.r, color.g, color.b, 0.0))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0) if top else color)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	if top:
		tr.offset_bottom = height
	else:
		tr.offset_top = -height
	return tr


## 字に、縁取りと影をつける（3Dの上で読みやすく）
static func outline(l: Label, size_px: int = 6, color: Color = Color(0, 0, 0, 0.75)) -> Label:
	l.add_theme_color_override("font_outline_color", color)
	l.add_theme_constant_override("outline_size", size_px)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


## まるい、やわらかい光の絵（光の粒・ぼんやりした光に使う）
static func soft_dot(size_px: int = 64, inner: Color = Color(1, 1, 1, 1)) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, Color(inner.r, inner.g, inner.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = size_px
	gt.height = size_px
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	return gt


## 版87：スクロールの中の部品を、押して動かした時にスクロールできるようにする。
## 「止める（STOP）」の設定の部品（パネル・ボタン・入れ物など）を「下へ伝える（PASS）」にする。
## すべりバー・文字の入力・スクロールのバーは、そのまま（それ自体を動かすため）
static func scroll_friendly(node: Node) -> void:
	if node is Control:
		var c := node as Control
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and not (c is Slider or c is ScrollBar or c is LineEdit or c is TextEdit or c is ScrollContainer):
			c.mouse_filter = Control.MOUSE_FILTER_PASS
	for ch in node.get_children():
		scroll_friendly(ch)


## 版109：BIGBLAST の角ばったボタン（ななめ・暗い板・色のふち。primary は色でぬる）。押せない時は暗く
static func blast_button(b: Button, accent: Color, primary: bool = false, skew: float = 0.18) -> void:
	var states := {"normal": 1.0, "hover": 1.15, "pressed": 0.8, "disabled": 0.45}
	for st in states:
		var sb := StyleBoxFlat.new()
		var k: float = states[st]
		var fill := accent if primary else Color(0.05, 0.06, 0.1, 0.92)
		if st == "disabled":
			fill = Color(0.12, 0.13, 0.17, 0.9)
		sb.bg_color = fill.lightened(0.12) if k > 1.0 else (fill.darkened(0.2) if k < 1.0 and st != "disabled" else fill)
		sb.set_border_width_all(3)
		sb.border_color = (accent.lightened(0.35) if primary else accent) if st != "disabled" else Color(0.3, 0.32, 0.38)
		sb.skew = Vector2(skew, 0)
		sb.set_corner_radius_all(0)
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.45 if st != "disabled" else 0.0)
		sb.shadow_size = 10 if (primary and st == "normal") else (4 if st != "disabled" else 0)
		sb.set_content_margin_all(12)
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 6)


## 版109：BIGBLAST の角ばったパネル（暗い板・色の線）
static func blast_panel(accent: Color, alpha: float = 0.9) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.09, alpha)
	sb.set_corner_radius_all(0)
	sb.border_width_left = 6
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = accent
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	sb.shadow_size = 8
	sb.set_content_margin_all(18)
	return sb

