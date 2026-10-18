extends Control
## ハイライトの再生（真上から見た、かんたんな図）。ベストアタッカーの足あとが、ボスのまわりを動く。
## 最初の形：本物の3D再生ではなく、2Dの図。

const Recorder := preload("res://scripts/combat/highlight_recorder.gd")

var points: Array = []
var boss := Vector2.ZERO
var bounds := 15.0
var player_color := Color.WHITE
var boss_color := Color(0.75, 0.22, 0.17)
var back_color := Color(0.29, 0.42, 0.29)
var play_time := 0.0
var span := 0.0


func setup(path_points: Array, boss_xz: Vector2, half_bounds: float, color: Color) -> void:
	points = path_points
	boss = boss_xz
	bounds = half_bounds
	player_color = color
	play_time = 0.0
	span = 0.0
	if not points.is_empty():
		span = (points[points.size() - 1] as Vector3).x - (points[0] as Vector3).x
	queue_redraw()


## 再生を進める。区間の終わりまで行ったら、最初から繰り返す
func advance(delta: float) -> void:
	play_time += delta
	if span > 0.0 and play_time > span + 0.5:
		play_time = 0.0
	queue_redraw()


func current_position() -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	return Recorder.position_on_path(points, (points[0] as Vector3).x + play_time)


func _to_screen(p: Vector2) -> Vector2:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	return origin + (p + Vector2(bounds, bounds)) / (2.0 * bounds) * side


func _draw() -> void:
	var side := minf(size.x, size.y)
	draw_rect(Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), back_color)
	var bs := side * 0.12
	draw_rect(Rect2(_to_screen(boss) - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), boss_color)
	if points.is_empty():
		return
	var trail := PackedVector2Array()
	var limit := (points[0] as Vector3).x + play_time
	for pt in points:
		var v: Vector3 = pt
		if v.x <= limit:
			trail.append(_to_screen(Vector2(v.y, v.z)))
	if trail.size() >= 2:
		draw_polyline(trail, Color(player_color.r, player_color.g, player_color.b, 0.6), 3.0)
	draw_circle(_to_screen(current_position()), side * 0.035, player_color)
