extends Control
## 版109：役職のラベル（剣士・瞬・拳士…）。ひと目で分かる、かっこいい札。
## 斜めの黒い板・役職の色のふち・うすい発光・斜めのしま・上の金属っぽい光・太い字（縁どり）。
## 色だけで分けない：必ず字で役職名を出す。描くのは中身が変わった時だけ（毎コマ描き直さない）。
## 使い方：var l := RoleLabel.new(); l.setup("剣士", Color("#ffd24a"), font, 30)。text を変えると、大きさも合わせる。

var text := "":
	set(v):
		if v == text:
			return
		text = v
		_fit()
var color := Color("#ffd24a"):
	set(v):
		color = v
		queue_redraw()
var font: Font = null
var font_size := 28
## 斜めの量（高さに対する割合）
var slant := 0.28
## 発光の強さ（0 で発光なし）
var glow := 1.0
## 字の左右のゆとり（字の高さに対する割合）
var pad := 0.7
## ラベルの最大の幅（px。0 は制限なし）。こえたら字を小さくする
var max_width := 0.0
var _size_used := 28


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(t: String, c: Color, f: Font, size_px: int = 28) -> Control:
	font = f
	font_size = size_px
	color = c
	text = t
	_fit()
	return self


## 字の大きさに合わせて、札の大きさを決める（長い名前は、max_width に入るように字を小さくする）
func _fit() -> void:
	var f := font if font != null else ThemeDB.fallback_font
	_size_used = font_size
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size_used).x
	var h := float(_size_used) * 1.5
	var total := w + float(_size_used) * pad * 2.0 + h * slant
	if max_width > 0.0 and total > max_width and w > 0.0:
		var k := clampf((max_width - float(_size_used) * pad * 2.0 - h * slant) / w, 0.4, 1.0)
		_size_used = maxi(10, int(float(_size_used) * k))
		w = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _size_used).x
		h = float(_size_used) * 1.5
		total = w + float(_size_used) * pad * 2.0 + h * slant
	custom_minimum_size = Vector2(ceilf(total), ceilf(h))
	queue_redraw()


func _draw() -> void:
	if text == "":
		return
	var f := font if font != null else ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	var s := h * slant
	var plate := PackedVector2Array([Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)])
	# うすい発光（外へ広げた板を、うすく重ねる）
	if glow > 0.0:
		for i in 3:
			var e := float(i + 1) * 2.5
			var g := PackedVector2Array([Vector2(s - e, -e), Vector2(w + e, -e), Vector2(w - s + e, h + e), Vector2(-e, h + e)])
			draw_colored_polygon(g, Color(color.r, color.g, color.b, 0.10 * glow / float(i + 1)))
	# 黒い板（下へ少し暗く）
	draw_colored_polygon(plate, Color(0.04, 0.05, 0.09, 0.92))
	# 斜めのしま（板の中だけ）
	var step := h * 0.55
	var x := -h
	while x < w:
		var a := Vector2(x + s, 0)
		var b := Vector2(x + s + h * 0.25, 0)
		var c := Vector2(x + h * 0.25, h)
		var d := Vector2(x, h)
		var clipped := Geometry2D.intersect_polygons(PackedVector2Array([a, b, c, d]), plate)
		for poly in clipped:
			draw_colored_polygon(poly, Color(color.r, color.g, color.b, 0.10))
		x += step
	# 左の色の帯（役職の色）
	var bar := PackedVector2Array([Vector2(s, 0), Vector2(s + h * 0.18, 0), Vector2(h * 0.18, h), Vector2(0, h)])
	draw_colored_polygon(bar, color)
	# 上の金属っぽい光
	draw_line(Vector2(s + 2, 1.5), Vector2(w - 2, 1.5), Color(1, 1, 1, 0.35), 1.5)
	# ふち（役職の色）
	var edge := plate.duplicate()
	edge.append(plate[0])
	draw_polyline(edge, color.lightened(0.15), 2.0, true)
	# 字：縁どり＋白（役職の色のかげ）
	var fs := _size_used
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := (w - tw) * 0.5 + h * 0.06
	var ty := h * 0.5 + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	draw_string_outline(f, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(4, fs / 6), Color(0, 0, 0, 0.85))
	draw_string(f, Vector2(tx + 1.5, ty + 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color.r, color.g, color.b, 0.55))
	draw_string(f, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
