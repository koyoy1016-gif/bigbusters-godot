extends Control
## 版81b：角の丸い四角を、上から下への色の変化（グラデーション）・まわりの光・ふち・上のつやで描く。
## ボタンの見た目（プレイ・選んでいる印など）に使う。画像を使わないので、軽く、どの大きさでもくっきり。

var top_color := Color("#ffb04a"):
	set(v):
		top_color = v
		queue_redraw()
var bottom_color := Color("#f2582a"):
	set(v):
		bottom_color = v
		queue_redraw()
var radius := 22.0
var border_color := Color(1, 1, 1, 0.35)
var border_width := 2.0
var glow_color := Color(1.0, 0.55, 0.2, 0.0)
var glow_size := 0.0:
	set(v):
		glow_size = v
		queue_redraw()
var shine := 0.22  # 上半分の、白いつや（0 でなし）
var corner_segments := 6


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(top: Color, bottom: Color, r: float = 22.0, glow: Color = Color(0, 0, 0, 0), glow_px: float = 0.0) -> Control:
	top_color = top
	bottom_color = bottom
	radius = r
	glow_color = glow
	glow_size = glow_px
	queue_redraw()
	return self


static func rounded_points(rect: Rect2, r: float, seg: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rr := minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var centers := [rect.position + Vector2(rect.size.x - rr, rr), rect.position + Vector2(rect.size.x - rr, rect.size.y - rr),
		rect.position + Vector2(rr, rect.size.y - rr), rect.position + Vector2(rr, rr)]
	var starts := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for c in 4:
		for i in seg + 1:
			var a: float = starts[c] + (PI / 2.0) * float(i) / float(seg)
			pts.append((centers[c] as Vector2) + Vector2(cos(a), sin(a)) * rr)
	return pts


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	# まわりの光（外へ広がるほど、うすく）
	if glow_size > 0.0 and glow_color.a > 0.0:
		for i in 4:
			var g := glow_size * float(4 - i) / 4.0
			var gc := glow_color
			gc.a *= 0.12 + 0.18 * float(i)
			draw_colored_polygon(rounded_points(rect.grow(g), radius + g, corner_segments), gc)
	var pts := rounded_points(rect, radius, corner_segments)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top_color.lerp(bottom_color, clampf(p.y / rect.size.y, 0.0, 1.0)))
	draw_polygon(pts, cols)
	if shine > 0.0:
		var top_half := Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y * 0.46))
		var sp := rounded_points(top_half, maxf(radius - 3.0, 2.0), corner_segments)
		var sc := PackedColorArray()
		for p in sp:
			sc.append(Color(1, 1, 1, shine * (1.0 - clampf((p.y - top_half.position.y) / top_half.size.y, 0.0, 1.0))))
		draw_polygon(sp, sc)
	if border_width > 0.0 and border_color.a > 0.0:
		var bp := pts.duplicate()
		bp.append(pts[0])
		draw_polyline(bp, border_color, border_width, true)
