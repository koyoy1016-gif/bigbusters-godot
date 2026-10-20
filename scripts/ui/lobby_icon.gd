extends Control
## 版81：ロビーの小さな絵（アイコン）。画像を使わず、図形で描く（軽い・フォントに字がなくても出る）。
## kind：person（人）・home（家＝ロビー）・gacha（ガチャの機械）・friends（2人）・room（部屋＝ドアと＋）・
##       coin（コイン）・lock（かぎ）・left / right（矢印）・star（星＝ランク）・city（街＝ステージ）

var kind := "person"
var color := Color.WHITE
var accent := Color(1, 0.82, 0.3)


func _init(k: String = "person", c: Color = Color.WHITE) -> void:
	kind = k
	color = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_kind(k: String) -> void:
	kind = k
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		return
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match kind:
		"person":
			draw_circle(p.call(0.5, 0.3), s * 0.17, color)
			_body(p, 0.5, 0.92, 0.36, color)
		"friends":
			var back := color.darkened(0.25)
			draw_circle(p.call(0.66, 0.32), s * 0.13, back)
			_body(p, 0.66, 0.84, 0.27, back)
			draw_circle(p.call(0.38, 0.36), s * 0.15, color)
			_body(p, 0.38, 0.92, 0.31, color)
		"home":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.1), p.call(0.92, 0.48), p.call(0.08, 0.48)]), color)
			draw_rect(Rect2(p.call(0.2, 0.46), Vector2(0.6, 0.44) * s), color)
			draw_rect(Rect2(p.call(0.42, 0.62), Vector2(0.16, 0.28) * s), color.darkened(0.55))
		"room":
			draw_rect(Rect2(p.call(0.14, 0.12), Vector2(0.5, 0.78) * s), color)
			draw_rect(Rect2(p.call(0.22, 0.2), Vector2(0.34, 0.7) * s), color.darkened(0.55))
			draw_circle(p.call(0.5, 0.55), s * 0.035, color)
			draw_rect(Rect2(p.call(0.66, 0.44), Vector2(0.3, 0.09) * s), accent)
			draw_rect(Rect2(p.call(0.765, 0.335), Vector2(0.09, 0.3) * s), accent)
		"gacha":
			draw_circle(p.call(0.5, 0.36), s * 0.3, color)
			draw_circle(p.call(0.5, 0.36), s * 0.22, color.darkened(0.5))
			draw_circle(p.call(0.4, 0.32), s * 0.08, accent)
			draw_circle(p.call(0.6, 0.42), s * 0.07, Color(0.5, 0.8, 1.0))
			draw_rect(Rect2(p.call(0.24, 0.62), Vector2(0.52, 0.3) * s), color)
			draw_rect(Rect2(p.call(0.42, 0.7), Vector2(0.16, 0.12) * s), color.darkened(0.55))
		"coin":
			draw_circle(p.call(0.5, 0.5), s * 0.44, Color(0.85, 0.6, 0.12))
			draw_circle(p.call(0.5, 0.5), s * 0.36, Color(1.0, 0.82, 0.25))
			draw_rect(Rect2(p.call(0.44, 0.28), Vector2(0.12, 0.44) * s), Color(0.85, 0.6, 0.12))
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 0.46 if i % 2 == 0 else 0.2
				var a := -PI / 2.0 + PI * float(i) / 5.0
				pts.append(p.call(0.5 + cos(a) * r, 0.53 + sin(a) * r))
			draw_colored_polygon(pts, color)
		"lock":
			draw_arc(p.call(0.5, 0.42), s * 0.2, PI, TAU, 16, color, s * 0.09)
			draw_rect(Rect2(p.call(0.22, 0.42), Vector2(0.56, 0.46) * s), color)
			draw_circle(p.call(0.5, 0.6), s * 0.06, color.darkened(0.6))
		"left", "right":
			var d := -1.0 if kind == "left" else 1.0
			draw_colored_polygon(PackedVector2Array([p.call(0.5 + 0.22 * d, 0.5), p.call(0.5 - 0.18 * d, 0.16), p.call(0.5 - 0.18 * d, 0.84)]), color)
		"city":
			# ステージの絵：夕方の空と、ビルの並び
			draw_rect(Rect2(o, Vector2(s, s)), Color(0.98, 0.62, 0.38))
			draw_rect(Rect2(p.call(0.0, 0.0), Vector2(1.0, 0.45) * s), Color(0.42, 0.5, 0.86))
			draw_circle(p.call(0.74, 0.46), s * 0.12, Color(1.0, 0.86, 0.5))
			var hs := [0.42, 0.62, 0.36, 0.7, 0.5, 0.58]
			for i in hs.size():
				var h: float = hs[i]
				draw_rect(Rect2(p.call(0.02 + 0.165 * i, 1.0 - h), Vector2(0.14, h) * s), Color(0.2, 0.18, 0.32))
				draw_rect(Rect2(p.call(0.06 + 0.165 * i, 1.0 - h + 0.08), Vector2(0.05, 0.05) * s), Color(1.0, 0.85, 0.45))


## 肩から下の、丸い体（人の形）
func _body(p: Callable, cx: float, bottom: float, w: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(p.call(cx + cos(a) * w, bottom - 0.02 + sin(a) * w * 0.95))
	draw_colored_polygon(pts, c)
