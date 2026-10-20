extends Control
## 版83：まんなかから広がって回る光の筋（ガチャの結果の演出）。rainbow なら虹色。
var color := Color(1, 0.85, 0.4, 0.5)
var rays := 14
var spin := 0.35
var rainbow := false
var power := 1.0
var t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := size.length() * 0.75
	for i in rays:
		var a0 := TAU * float(i) / float(rays) + t * spin
		var a1 := a0 + TAU / float(rays) * 0.42
		var col := color
		if rainbow:
			col = Color.from_hsv(fmod(float(i) / float(rays) + t * 0.15, 1.0), 0.65, 1.0, color.a)
		col.a *= power
		var pts := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r])
		var cols := PackedColorArray([col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)])
		draw_polygon(pts, cols)
