extends RefCounted
## 戦いの画面の体力の表示（画面に固定。カメラが動いても、場所・大きさは変わらない）。
## 版92：ボス＝上（アイコン＋メーター）、自分＝丸いアイコン＋数字。
## 版95（ユーザーの指示）：数字はやめて、ボスもキャラもバーだけ。戦っている4人（自分・なかま・AI）の
##   丸いアイコン＋体力のバーを、たてに並べる（たて画面：ボスの下の左・横画面：左上）。自分がいちばん上で金のふち。
##   体力が hp_low（30）未満のバーは赤（30 ちょうどは緑）。
##   たおれた人は、アイコンを暗く・バーは空。
##   ボス：自作の角のある顔のアイコン＋メーター。減った分は、少しおくれて縮む黄色の帯。覚醒（第2形態）はむらさき。
## 数値・色・場所は data/prototype_stick.json の "hud"。夕方・夜のどちらの背景でも見えるように、濃い下じきと黒いふち。
## 版102（軽量化）：体力の表示は、自分の描く板（layer）に描き、**見た目が変わった時だけ**描き直す（前は毎コマ全部描き直していた）。
##   毎コマは update で「見た目を決める数」（sig）だけを集め、前のコマと同じなら描かない。場所（layout）は画面の大きさごとに1回だけ計算する。

const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const BossSync := preload("res://scripts/network/boss_sync.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const SLOTS := ["p1", "p2", "p3", "p4"]

var b  ## まとめ役（stick_prototype.gd）
var trail := 1.0  ## ボスのメーターの、おくれて縮む帯（割合）
var trail_hold := 0.0  ## 減ってから、帯が縮み始めるまでの残り秒
var last_frac := 1.0
var requested := {}  ## 顔の絵を、もう頼んだキャラID
var _role_colors: Dictionary = {}
var layer: Control  ## 版102：体力の表示を描く板（overlay の子。overlay の絵より先＝下に描く）
var ci: CanvasItem  ## いま描いている先（layer。古い呼び方の draw では overlay）
var _sig: Array = []  ## 前に描いた時の「見た目を決める数」
var _layout_size := Vector2(-1, -1)
var _layout: Dictionary = {}
var _circle_unit := PackedVector2Array()  ## 半径1の円の点（1回だけ作る）
var redraws := 0  ## 描き直した回数（テスト・測る用）


func _init(main) -> void:
	b = main


func cfg() -> Dictionary:
	return b.config.get("hud", {})


func _pick(c: Dictionary, key: String, portrait: bool) -> Variant:
	return c.get(key + "_portrait", c.get(key)) if portrait else c.get(key)


## 版102：体力の表示を描く板を作る（overlay の子。overlay の絵より先＝下に描く。前と同じ重なり方）
func attach(parent: Control) -> void:
	layer = Control.new()
	layer.name = "HpHud"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	layer.draw.connect(_on_layer_draw)
	parent.add_child(layer)


## 毎コマ：ボスの帯を進め、見た目が変わった時だけ描き直す
func update(delta: float) -> void:
	step(delta)
	if layer == null:
		return
	var sig := signature(layer.size)
	if sig != _sig:
		_sig = sig
		layer.queue_redraw()


## すぐ描き直す（体力などを外から変えて、写真を撮る時など）
func refresh() -> void:
	_sig = []
	if layer != null:
		layer.queue_redraw()


## 見た目を決める数（これが前のコマと同じなら、描き直さない）。party_views より軽い：同じ元の数だけを集める
func signature(screen: Vector2) -> Array:
	var sig: Array = [screen, snappedf(float(b.boss_hp_ratio()), 0.0005), snappedf(trail, 0.0005), b.phase.phase != BossPhase.NORMAL,
			ceili(maxf(float(b.my_hp), 0.0)), b.role_value("hp"), bool(b.downed), float(b.player_hit_flash) > 0.0, b.selected_character, b.hud_portraits.size()]
	for slot in SLOTS:
		if b.ai_allies.has(slot):
			var a: Dictionary = b.ai_allies[slot]
			sig.append_array([slot, str(a.get("id", "")), ceili(maxf(float(a["hp"]), 0.0)), float(a.get("max_hp", 0.0)), bool(a.get("downed", false))])
	if b.net_active:
		for key in ["members", "hp", "chars"]:
			var v: Variant = b.net_state.get(key, null)
			sig.append(v.duplicate(true) if (v is Dictionary or v is Array) else v)
		sig.append_array([b.round_start_ms, str(b._my_slot())])
	return sig


func _on_layer_draw() -> void:
	ci = layer
	redraws += 1
	var L := layout(layer.size)
	_draw_boss(L)
	_draw_party(L)


## 画面の大きさ → 体力の表示の場所（版102：画面の大きさが同じなら、前の計算を使う）
func layout(screen: Vector2) -> Dictionary:
	if screen == _layout_size and not _layout.is_empty():
		return _layout
	_layout_size = screen
	_layout = _calc_layout(screen)
	return _layout


func _calc_layout(screen: Vector2) -> Dictionary:
	var h := cfg()
	var portrait := screen.y > screen.x
	var bc: Dictionary = h.get("boss", {})
	var pc: Dictionary = h.get("party", {})
	var bp: Array = _pick(bc, "pos", portrait)
	var bs: Array = _pick(bc, "size", portrait)
	var boss_rect := Rect2(Vector2(screen.x * float(bp[0]), screen.y * float(bp[1])), Vector2(screen.x * float(bs[0]), screen.y * float(bs[1])))
	var bir := minf(float(bc.get("icon_r", 28.0)), boss_rect.size.y * 0.62)
	var boss_icon := Vector2(boss_rect.position.x + bir + 4.0, boss_rect.position.y + boss_rect.size.y * 0.5)
	var bar_x := boss_icon.x + bir + 10.0
	var bar_h := maxf(12.0, boss_rect.size.y * float(bc.get("bar_frac", 0.4)))
	var bar_rect := Rect2(Vector2(bar_x, boss_rect.position.y + boss_rect.size.y * 0.5), Vector2(boss_rect.end.x - bar_x - 8.0, bar_h))
	# 4人：たてに並べる。たて画面はボスの下の左、横画面は左上（ボスは上のまんなか）
	var cell_h := screen.y * float(_pick(pc, "cell_h", portrait))
	var colw := screen.x * float(_pick(pc, "w", portrait))
	var top := Vector2(screen.x * float(pc.get("x_portrait", 0.025)), boss_rect.end.y + float(pc.get("gap_px", 6.0))) if portrait \
			else Vector2(screen.x * float((pc.get("pos", [0.012, 0.02]) as Array)[0]), screen.y * float((pc.get("pos", [0.012, 0.02]) as Array)[1]))
	var row := Rect2(top, Vector2(colw, cell_h * 4.0))
	var ir := minf(float(pc.get("icon_r", 22.0)), cell_h * 0.42)
	var cells := []
	for i in 4:
		var cell := Rect2(Vector2(row.position.x, row.position.y + cell_h * i), Vector2(colw, cell_h)).grow_individual(0.0, -1.5, 0.0, -1.5)
		var ic := Vector2(cell.position.x + ir + 5.0, cell.position.y + cell.size.y * 0.5)
		var bx := ic.x + ir + 8.0
		var bh := float(pc.get("bar_h", 12.0))
		# 版110：バーの上に、役職名（小さく）を出すので、バーを少し下げる
		var by := ic.y - bh * 0.5 + float(pc.get("bar_drop_px", 7.0))
		cells.append({"cell": cell, "icon": ic, "icon_r": ir, "bar": Rect2(Vector2(bx, by), Vector2(maxf(10.0, cell.end.x - bx - 8.0), bh))})
	# まんなかに出す文字（怒り・勝ち負け）が重ならない高さ：4人の列がまんなかまで来ていなければ、ボスの下でよい
	var center_bottom := row.end.y if row.end.x > screen.x * 0.3 else boss_rect.end.y
	return {"portrait": portrait, "boss_rect": boss_rect, "boss_icon": boss_icon, "boss_icon_r": bir, "bar_rect": bar_rect,
			"party_rect": row, "cells": cells, "bottom": maxf(row.end.y, boss_rect.end.y), "center_bottom": center_bottom}


## 1人分の見え方。hp・最大は切り上げの整数。その整数が hp_low 未満なら low（赤）
func _entry(slot: String, id: String, hp: float, max_hp: float, down: bool, me: bool) -> Dictionary:
	var h := cfg()
	var pc: Dictionary = h.get("party", {})
	var hp_i := ceili(maxf(hp, 0.0))
	var max_i := maxi(1, ceili(max_hp))
	var low := hp_i < int(h.get("hp_low", 30))
	return {"slot": slot, "id": id, "hp": hp_i, "max": max_i, "ratio": clampf(float(hp_i) / float(max_i), 0.0, 1.0), "low": low,
			"down": down or hp_i <= 0, "me": me,
			"color": Color(str(h.get("hp_low_color", "#ff3b3b"))) if low else Color(str(pc.get("bar_color", "#46d16a")))}


## 自分の見え方（版92 と同じ呼び方）
func player_view() -> Dictionary:
	var me := str(b._my_slot())
	var def: Dictionary = b.char_def_of(me)
	return _entry(me, str(def.get("id", b.selected_character)), float(b.my_hp), float(b.role_value("hp")), bool(b.downed), true)


## 戦っている4人（自分が先、そのあと枠の順）：自分・通信のなかま・AI
func party_views() -> Array:
	var me := str(b._my_slot())
	var out := [player_view()]
	var members: Array = b.net_state.get("members", []) if b.net_active else []
	var fighters: Dictionary = BossSync.others_hp(b.net_state.get("hp", {}), me, members, b.round_start_ms) if b.net_active else {}
	for slot in SLOTS:
		if slot == me:
			continue
		var def: Dictionary = b.char_def_of(slot)
		var id := str(def.get("id", ""))
		var mx := float((def.get("stats", {}) as Dictionary).get("hp", 100.0))
		if b.ai_allies.has(slot):
			var a: Dictionary = b.ai_allies[slot]
			out.append(_entry(slot, id, float(a["hp"]), float(a.get("max_hp", mx)), bool(a.get("downed", false)), false))
		elif members.has(slot):
			out.append(_entry(slot, id, float(fighters.get(slot, mx)), mx, false, false))
	return out


## ボスの見え方（数字は出さない。hp・max はテスト用）
func boss_view() -> Dictionary:
	var bc: Dictionary = cfg().get("boss", {})
	var awake: bool = b.phase.phase != BossPhase.NORMAL
	return {"frac": b.boss_hp_ratio(), "trail": trail, "awake": awake, "hp": ceili(maxf(float(b.boss_hp), 0.0)), "max": int(b.phase.max_hp()),
			"label": str(bc.get("label_awake", "覚醒 BOSS")) if awake else str(bc.get("label", "BOSS")),
			"color": Color(str(bc.get("bar_color_awake", "#b23cff"))) if awake else Color(str(bc.get("bar_color", "#e23b3b")))}


## 時間を進める（ボスの減った分の帯）
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


## 顔の絵がない時の丸の色：そのキャラの役の色（data/game_flow.json の role_colors。ロビーと同じ色）
func role_color(id: String) -> Color:
	if _role_colors.is_empty():
		var gf: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_flow.json")) if FileAccess.file_exists("res://data/game_flow.json") else null
		_role_colors = (gf as Dictionary).get("role_colors", {"_": "#5a6a88"}) if gf is Dictionary else {"_": "#5a6a88"}
	var def := CharacterData.find(b.characters_cfg, id) if not b.characters_cfg.is_empty() else {}
	return Color(str(_role_colors.get(str(def.get("role", "")), b.hud_role_color.to_html())))


var _labels: Dictionary = {}


## 版110：キャラの役職名と役職の色（覚える）
func _label_of(id: String) -> Array:
	if not _labels.has(id):
		var def := CharacterData.find(b.characters_cfg if not b.characters_cfg.is_empty() else CharacterData.load_config(), id)
		_labels[id] = [str(def.get("name", "")), Color(str(def.get("role_color", "#ffffff")))]
	return _labels[id]


## 顔の絵（なければ、画面の流れの portrait_source に1回だけ頼む）
func portrait_of(id: String) -> Texture2D:
	if b.hud_portraits.has(id):
		return b.hud_portraits[id]
	if id != "" and not requested.has(id) and b.portrait_source != null and is_instance_valid(b.portrait_source):
		requested[id] = true
		var def := CharacterData.find(b.characters_cfg if not b.characters_cfg.is_empty() else CharacterData.load_config(), id)
		if not def.is_empty():
			var bb = b
			b.portrait_source.request(id, def, func(tex: Texture2D):
				if is_instance_valid(bb):
					bb.hud_portraits[id] = tex)
	return null


func reset() -> void:
	trail = 1.0
	trail_hold = 0.0
	last_frac = 1.0
	refresh()


## 描く（古い呼び方：overlay の _draw の中から。版102 からは layer が自分で描く）
func draw(screen: Vector2) -> void:
	ci = b.overlay
	var L := layout(screen)
	_draw_boss(L)
	_draw_party(L)


func _text(pos: Vector2, text: String, size: int, color: Color, outline: int = -1) -> void:
	var h := cfg()
	var o := outline if outline >= 0 else int(h.get("outline_px", 5))
	if o > 0:
		ci.draw_string_outline(b.font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, o, Color(str(h.get("outline_color", "#000000"))))
	ci.draw_string(b.font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _circle_points(c: Vector2, r: float, n: int = 32) -> PackedVector2Array:
	if _circle_unit.size() != n:
		_circle_unit = PackedVector2Array()
		for i in n:
			var a := TAU * i / n
			_circle_unit.append(Vector2(cos(a), sin(a)))
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		pts[i] = c + _circle_unit[i] * r
	return pts


func _bar(rect: Rect2, frac: float, col: Color, back: Color) -> void:
	ci.draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.85))
	ci.draw_rect(rect, back)
	var w := rect.size.x * clampf(frac, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), col)
		ci.draw_rect(Rect2(rect.position, Vector2(w, rect.size.y * 0.35)), col.lightened(0.35))


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
	ci.draw_colored_polygon(back, Color(str(bc.get("back_color", "#1a1020d8"))))
	var closed := back.duplicate()
	closed.append(back[0])
	ci.draw_polyline(closed, frame, 2.0)
	# ラベル（BOSS／覚醒 BOSS）。数字は出さない（版95）
	var fs := int(float(b.config["ui_font_size"]) * float(bc.get("text_size", 0.62)))
	_text(Vector2(bar.position.x, bar.position.y - 6.0), str(v["label"]), fs, v["color"].lightened(0.35), 4)
	# メーター：うしろ・おくれて縮む帯・いまの体力・つや
	ci.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.85))
	ci.draw_rect(bar, Color(str(bc.get("bar_back_color", "#3a1420"))))
	if float(v["trail"]) > float(v["frac"]):
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(v["trail"]), bar.size.y)), Color(str(bc.get("trail_color", "#ffe08a"))))
	var fw: float = bar.size.x * float(v["frac"])
	var col: Color = v["color"]
	ci.draw_rect(Rect2(bar.position, Vector2(fw, bar.size.y)), col)
	ci.draw_rect(Rect2(bar.position, Vector2(fw, bar.size.y * 0.35)), col.lightened(0.35))
	# 第1形態の間は、右はしに「第2形態がある」ことを示す小さな印
	if not bool(v["awake"]):
		ci.draw_rect(Rect2(Vector2(bar.end.x - 5.0, bar.position.y), Vector2(5.0, bar.size.y)), Color(str(bc.get("bar_color_awake", "#b23cff"))))
	# アイコン：自作のボスの顔（角・光る目）
	ci.draw_circle(ic, ir + 3.0, frame)
	ci.draw_circle(ic, ir, Color(str(bc.get("icon_back", "#2a0d18"))))
	var face := Color(str(bc.get("icon_face", "#5a1f2e")))
	var horn := Color(str(bc.get("icon_horn", "#e9dcc0")))
	ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(-ir * 0.55, -ir * 0.15), ic + Vector2(-ir * 0.85, -ir * 0.85), ic + Vector2(-ir * 0.2, -ir * 0.45)]), horn)
	ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(ir * 0.55, -ir * 0.15), ic + Vector2(ir * 0.85, -ir * 0.85), ic + Vector2(ir * 0.2, -ir * 0.45)]), horn)
	ci.draw_circle(ic + Vector2(0, ir * 0.12), ir * 0.6, face)
	var eye := Color(str(bc.get("icon_eye_awake", "#ff7bff"))) if bool(v["awake"]) else Color(str(bc.get("icon_eye", "#ffd84a")))
	for sx in [-1.0, 1.0]:
		ci.draw_colored_polygon(PackedVector2Array([ic + Vector2(sx * ir * 0.12, -ir * 0.02), ic + Vector2(sx * ir * 0.42, -ir * 0.1), ic + Vector2(sx * ir * 0.36, ir * 0.08)]), eye)
	ci.draw_line(ic + Vector2(-ir * 0.25, ir * 0.4), ic + Vector2(ir * 0.25, ir * 0.4), Color(0, 0, 0, 0.8), 3.0)


func _draw_party(L: Dictionary) -> void:
	var h := cfg()
	var pc: Dictionary = h.get("party", {})
	var views := party_views()
	var cells: Array = L["cells"]
	for i in mini(views.size(), cells.size()):
		var v: Dictionary = views[i]
		var c: Dictionary = cells[i]
		var cell: Rect2 = c["cell"]
		var ic: Vector2 = c["icon"]
		var r: float = c["icon_r"]
		ci.draw_rect(Rect2(cell.position + Vector2(r, 3.0), Vector2(cell.size.x - r, cell.size.y - 6.0)), Color(str(pc.get("cell_back", "#0b0e1aa8"))))
		# 丸いアイコン：キャラの顔の絵（なければ、役の色の丸と人の形）。たおれたら暗く
		var ring := Color(str(pc.get("me_ring", "#ffd34a"))) if bool(v["me"]) else Color(str(pc.get("ring", "#0b0e1a")))
		if bool(v["me"]) and float(b.player_hit_flash) > 0.0:
			ring = ring.lerp(Color.WHITE, 0.6)  # 自分が当たった直後は、ふちが白く光る
		ci.draw_circle(ic, r + 3.0, ring)
		var tex := portrait_of(str(v["id"]))
		var dim := Color(0.45, 0.45, 0.45) if bool(v["down"]) else Color.WHITE
		if tex != null:
			var pts := _circle_points(ic, r)
			var uvs := PackedVector2Array()
			var z := float(pc.get("portrait_zoom", 0.9))
			for p in pts:
				uvs.append(Vector2(0.5, 0.5) + (p - ic) / r * 0.5 * z)
			ci.draw_colored_polygon(pts, dim, uvs, tex)
		else:
			ci.draw_circle(ic, r, role_color(str(v["id"])) * dim)
			var fg := Color(1, 1, 1, 0.9) * dim
			ci.draw_circle(ic + Vector2(0, -r * 0.22), r * 0.3, fg)
			var sh := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				sh.append(ic + Vector2(cos(a) * r * 0.55, r * 0.62 + sin(a) * r * 0.5))
			ci.draw_colored_polygon(sh, fg)
		# 版110：役職名（役職の色・小さく。バーの上）
		var nm := str(_label_of(str(v["id"]))[0])
		if nm != "":
			var br0: Rect2 = c["bar"]
			_text(Vector2(br0.position.x + 1.0, br0.position.y - 3.0), nm, int(pc.get("name_px", 14)), (_label_of(str(v["id"]))[1] as Color) * dim, 4)
		# 体力のバー（数字は出さない）
		_bar(c["bar"], float(v["ratio"]), v["color"], Color(str(pc.get("bar_back", "#14202a"))))
