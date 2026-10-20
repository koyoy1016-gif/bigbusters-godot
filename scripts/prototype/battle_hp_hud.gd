extends RefCounted
## 版92：戦いの画面の体力の表示（画面に固定。カメラが動いても、場所・大きさは変わらない）。
##   ボス：画面の上。ボスのアイコン（自作の角のある顔）＋体力のメーター＋数字（いま / 最大）。
##        減った分は、少しおくれて縮む黄色の帯で見せる（どれだけ減ったか分かる）。覚醒（第2形態）はむらさき。
##   自分：ボスの下の左。丸いアイコン（キャラの顔の絵。なければ役の色の丸と人の形）＋体力の数字。
##        体力が hp_low（30）未満で赤（30 ちょうどは、ふつうの色）。まわりの輪は体力の割合。
## 数値・色・場所は data/prototype_stick.json の "hud"。字はふちどりして、夕方・夜のどちらの背景でも読める。

const BossPhase := preload("res://scripts/combat/boss_phase.gd")

var b  ## まとめ役（stick_prototype.gd）
var trail := 1.0  ## ボスのメーターの、おくれて縮む帯（割合）
var trail_hold := 0.0  ## 減ってから、帯が縮み始めるまでの残り秒
var last_frac := 1.0
var last_ms := -1
var last_hp_i := -1
var hp_pop := 0.0  ## 体力が変わった時の、数字の小さなはね（1→0）


func _init(main) -> void:
	b = main


func cfg() -> Dictionary:
	return b.config.get("hud", {})


func _pick(c: Dictionary, key: String, portrait: bool) -> Variant:
	return c.get(key + "_portrait", c.get(key)) if portrait else c.get(key)


## 画面の大きさ → 体力の表示の場所（四角・丸の中心と半径）
func layout(screen: Vector2) -> Dictionary:
	var h := cfg()
	var portrait := screen.y > screen.x
	var bc: Dictionary = h.get("boss", {})
	var pc: Dictionary = h.get("player", {})
	var bp: Array = _pick(bc, "pos", portrait)
	var bs: Array = _pick(bc, "size", portrait)
	var boss_rect := Rect2(Vector2(screen.x * float(bp[0]), screen.y * float(bp[1])), Vector2(screen.x * float(bs[0]), screen.y * float(bs[1])))
	var bir := minf(float(bc.get("icon_r", 28.0)), boss_rect.size.y * 0.62)
	var boss_icon := Vector2(boss_rect.position.x + bir + 4.0, boss_rect.position.y + boss_rect.size.y * 0.5)
	var bar_x := boss_icon.x + bir + 10.0
	var bar_h := maxf(12.0, boss_rect.size.y * float(bc.get("bar_frac", 0.4)))
	var bar_rect := Rect2(Vector2(bar_x, boss_rect.position.y + boss_rect.size.y * 0.5), Vector2(boss_rect.end.x - bar_x - 8.0, bar_h))
	var pp: Array = _pick(pc, "pos", portrait)
	var pir := float(pc.get("icon_r", 30.0))
	var p_icon := Vector2(screen.x * float(pp[0]) + pir + 4.0, screen.y * float(pp[1]) + pir + 4.0)
	var fs := int(float(b.config["ui_font_size"]) * float(pc.get("num_size", 1.3)))
	var player_rect := Rect2(p_icon - Vector2(pir + 4.0, pir + 4.0), Vector2(pir * 2.0 + 8.0 + float(pc.get("panel_w", 170.0)), pir * 2.0 + 8.0))
	return {"portrait": portrait, "boss_rect": boss_rect, "boss_icon": boss_icon, "boss_icon_r": bir, "bar_rect": bar_rect,
			"player_rect": player_rect, "player_icon": p_icon, "player_icon_r": pir, "num_pos": Vector2(p_icon.x + pir + 12.0, p_icon.y + fs * 0.36), "num_size": fs,
			"bottom": maxf(boss_rect.end.y, player_rect.end.y)}


## 自分の体力の見え方：数字は切り上げの整数。その整数が hp_low 未満なら赤（30 ちょうどは、ふつうの色）
func player_view() -> Dictionary:
	var h := cfg()
	var hp_i := ceili(maxf(float(b.my_hp), 0.0))
	var max_i := maxi(1, ceili(float(b.role_value("hp"))))
	var low := hp_i < int(h.get("hp_low", 30))
	return {"hp": hp_i, "max": max_i, "low": low, "down": bool(b.downed),
			"color": Color(str(h.get("hp_low_color", "#ff3b3b"))) if low else Color(str(h.get("hp_color", "#ffffff"))),
			"ratio": clampf(float(hp_i) / float(max_i), 0.0, 1.0)}


## ボスの体力の見え方
func boss_view() -> Dictionary:
	var bc: Dictionary = cfg().get("boss", {})
	var awake: bool = b.phase.phase != BossPhase.NORMAL
	var hp_i := ceili(maxf(float(b.boss_hp), 0.0))
	return {"frac": b.boss_hp_ratio(), "trail": trail, "awake": awake, "hp": hp_i, "max": int(b.phase.max_hp()),
			"label": str(bc.get("label_awake", "覚醒 BOSS")) if awake else str(bc.get("label", "BOSS")),
			"color": Color(str(bc.get("bar_color_awake", "#b23cff"))) if awake else Color(str(bc.get("bar_color", "#e23b3b")))}


## 時間を進める（減った分の帯・数字のはね）
func step(delta: float) -> void:
	var bc: Dictionary = cfg().get("boss", {})
	var frac: float = b.boss_hp_ratio()
	if frac > trail:
		trail = frac  # 回復・覚醒で満タンにもどる時は、帯もすぐ合わせる
	if frac < last_frac - 0.00001:
		trail_hold = float(bc.get("trail_sec", 0.6))  # 減った：少し待ってから、帯を縮める
	last_frac = frac
	if trail_hold > 0.0:
		trail_hold = maxf(0.0, trail_hold - delta)
	elif trail > frac:
		trail = maxf(frac, trail - delta * float(bc.get("trail_speed", 0.5)))
	var hp_i := ceili(maxf(float(b.my_hp), 0.0))
	if last_hp_i >= 0 and hp_i != last_hp_i:
		hp_pop = 1.0
	last_hp_i = hp_i
	hp_pop = maxf(0.0, hp_pop - delta * 5.0)


## 顔の絵がない時の丸の色：自分のキャラの役の色（data/game_flow.json の role_colors。ロビーと同じ色）
var _role_color_cache: Variant = null


func role_color() -> Color:
	if _role_color_cache == null:
		_role_color_cache = b.hud_role_color
		var gf: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_flow.json")) if FileAccess.file_exists("res://data/game_flow.json") else null
		var role := str(b.selected_def().get("role", b.role().get("name", "")))
		if gf is Dictionary and ((gf as Dictionary).get("role_colors", {}) as Dictionary).has(role):
			_role_color_cache = Color(str(gf["role_colors"][role]))
	return _role_color_cache


func reset() -> void:
	_role_color_cache = null
	trail = 1.0
	trail_hold = 0.0
	last_frac = 1.0
	last_hp_i = -1
	hp_pop = 0.0


## 描く（overlay の _draw の中から）
func draw(screen: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var dt := 0.0 if last_ms < 0 else clampf((now - last_ms) / 1000.0, 0.0, 0.1)
	last_ms = now
	step(dt)
	var L := layout(screen)
	_draw_boss(L)
	_draw_player(L)


func _text(pos: Vector2, text: String, size: int, color: Color, outline: int = -1) -> void:
	var h := cfg()
	var o := outline if outline >= 0 else int(h.get("outline_px", 5))
	if o > 0:
		b.overlay.draw_string_outline(b.font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, o, Color(str(h.get("outline_color", "#000000"))))
	b.overlay.draw_string(b.font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _circle_points(c: Vector2, r: float, n: int = 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw_boss(L: Dictionary) -> void:
	var h := cfg()
	var bc: Dictionary = h.get("boss", {})
	var v := boss_view()
	var rect: Rect2 = L["boss_rect"]
	var bar: Rect2 = L["bar_rect"]
	var ic: Vector2 = L["boss_icon"]
	var ir: float = L["boss_icon_r"]
	var frame := Color(str(bc.get("frame_color", "#f2d38a")))
	# 下じき（角を切った形）
	var cut := rect.size.y * 0.3
	var back := PackedVector2Array([rect.position + Vector2(cut, 0), Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y - cut), Vector2(rect.end.x - cut, rect.end.y), Vector2(rect.position.x, rect.end.y), rect.position + Vector2(0, cut)])
	b.overlay.draw_colored_polygon(back, Color(str(bc.get("back_color", "#1a1020d8"))))
	var closed := back.duplicate()
	closed.append(back[0])
	b.overlay.draw_polyline(closed, frame, 2.0)
	# ラベル（BOSS／覚醒 BOSS）と数字（メーターの上）
	var fs := int(float(b.config["ui_font_size"]) * float(bc.get("text_size", 0.62)))
	_text(Vector2(bar.position.x, bar.position.y - 6.0), str(v["label"]), fs, v["color"].lightened(0.35), 4)
	var num := "%d / %d" % [int(v["hp"]), int(v["max"])]
	var nw: float = b.font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(Vector2(bar.end.x - nw, bar.position.y - 6.0), num, fs, Color(str(h.get("hp_color", "#ffffff"))), 4)
	# メーター：うしろ・おくれて縮む帯・いまの体力・つや
	b.overlay.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.85))
	b.overlay.draw_rect(bar, Color(str(bc.get("bar_back_color", "#3a1420"))))
	var tw: float = bar.size.x * float(v["trail"])
	if float(v["trail"]) > float(v["frac"]):
		b.overlay.draw_rect(Rect2(bar.position, Vector2(tw, bar.size.y)), Color(str(bc.get("trail_color", "#ffe08a"))))
	var fw: float = bar.size.x * float(v["frac"])
	var col: Color = v["color"]
	b.overlay.draw_rect(Rect2(bar.position, Vector2(fw, bar.size.y)), col)
	b.overlay.draw_rect(Rect2(bar.position, Vector2(fw, bar.size.y * 0.35)), col.lightened(0.35))
	# 第1形態の間は、右はしに「第2形態がある」ことを示す小さな印（前のメーターと同じ）
	if not bool(v["awake"]):
		b.overlay.draw_rect(Rect2(Vector2(bar.end.x - 5.0, bar.position.y), Vector2(5.0, bar.size.y)), Color(str(bc.get("bar_color_awake", "#b23cff"))))
	# アイコン：自作のボスの顔（角・光る目）
	b.overlay.draw_circle(ic, ir + 3.0, frame)
	b.overlay.draw_circle(ic, ir, Color(str(bc.get("icon_back", "#2a0d18"))))
	var face := Color(str(bc.get("icon_face", "#5a1f2e")))
	var horn := Color(str(bc.get("icon_horn", "#e9dcc0")))
	b.overlay.draw_colored_polygon(PackedVector2Array([ic + Vector2(-ir * 0.55, -ir * 0.15), ic + Vector2(-ir * 0.85, -ir * 0.85), ic + Vector2(-ir * 0.2, -ir * 0.45)]), horn)
	b.overlay.draw_colored_polygon(PackedVector2Array([ic + Vector2(ir * 0.55, -ir * 0.15), ic + Vector2(ir * 0.85, -ir * 0.85), ic + Vector2(ir * 0.2, -ir * 0.45)]), horn)
	b.overlay.draw_circle(ic + Vector2(0, ir * 0.12), ir * 0.6, face)
	var eye := Color(str(bc.get("icon_eye_awake", "#ff7bff"))) if bool(v["awake"]) else Color(str(bc.get("icon_eye", "#ffd84a")))
	for sx in [-1.0, 1.0]:
		b.overlay.draw_colored_polygon(PackedVector2Array([ic + Vector2(sx * ir * 0.12, -ir * 0.02), ic + Vector2(sx * ir * 0.42, -ir * 0.1), ic + Vector2(sx * ir * 0.36, ir * 0.08)]), eye)
	b.overlay.draw_line(ic + Vector2(-ir * 0.25, ir * 0.4), ic + Vector2(ir * 0.25, ir * 0.4), Color(0, 0, 0, 0.8), 3.0)


func _draw_player(L: Dictionary) -> void:
	var h := cfg()
	var pc: Dictionary = h.get("player", {})
	var v := player_view()
	var c: Vector2 = L["player_icon"]
	var r: float = L["player_icon_r"]
	var rect: Rect2 = L["player_rect"]
	b.overlay.draw_rect(Rect2(rect.position + Vector2(r, 4.0), Vector2(rect.size.x - r, rect.size.y - 8.0)), Color(str(pc.get("panel_color", "#0b0e1aa8"))))
	# 丸いアイコン：キャラの顔の絵（なければ、役の色の丸と人の形）
	b.overlay.draw_circle(c, r + 4.0, Color(0, 0, 0, 0.75))
	var tex: Texture2D = b.hud_portrait
	if tex != null:
		var pts := _circle_points(c, r)
		var uvs := PackedVector2Array()
		var z := float(pc.get("portrait_zoom", 0.9))
		for p in pts:
			var d: Vector2 = (p - c) / r
			uvs.append(Vector2(0.5, 0.5) + d * 0.5 * z)
		b.overlay.draw_colored_polygon(pts, Color(0.55, 0.55, 0.55) if bool(v["down"]) else Color.WHITE, uvs, tex)
	else:
		var rc: Color = role_color()
		if bool(v["down"]):
			rc = rc.darkened(0.5)
		b.overlay.draw_circle(c, r, rc)
		var fg := Color(1, 1, 1, 0.9)
		b.overlay.draw_circle(c + Vector2(0, -r * 0.22), r * 0.3, fg)
		var sh := PackedVector2Array()
		for i in 17:
			var a := PI + PI * i / 16.0
			sh.append(c + Vector2(cos(a) * r * 0.55, r * 0.62 + sin(a) * r * 0.5))
		b.overlay.draw_colored_polygon(sh, fg)
	# まわりの輪：体力の割合（低い時は赤。当たった直後は白く光る）
	var ring := Color(str(pc.get("ring_low_color", "#ff3b3b"))) if bool(v["low"]) else Color(str(pc.get("ring_color", "#7ee0ff")))
	if float(b.player_hit_flash) > 0.0:
		ring = ring.lerp(Color.WHITE, 0.6)
	b.overlay.draw_arc(c, r + 2.0, 0.0, TAU, 48, Color(0.15, 0.15, 0.2, 0.9), 5.0)
	b.overlay.draw_arc(c, r + 2.0, -PI * 0.5, -PI * 0.5 + TAU * float(v["ratio"]), 48, ring, 5.0)
	# 数字（いまの体力）と、小さく最大
	var fs: int = L["num_size"]
	var pop := 1.0 + 0.12 * hp_pop
	var fs2 := int(fs * pop)
	var np: Vector2 = L["num_pos"]
	var txt := str(int(v["hp"]))
	_text(np, txt, fs2, v["color"])
	var w: float = b.font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var fs3 := int(fs * float(pc.get("max_size", 0.5)))
	_text(np + Vector2(w + 4.0, 0.0), "/ %d" % int(v["max"]), fs3, Color(str(h.get("sub_color", "#d8dcef"))), 3)
	if bool(v["down"]):
		_text(np + Vector2(0.0, fs3 + 4.0), str(b.config.get("down_text", "")), fs3, Color(str(h.get("hp_low_color", "#ff3b3b"))), 3)
