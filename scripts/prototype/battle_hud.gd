extends RefCounted
## 画面の文字・ボタン・スティック・体力バー・技名の帯・ダメージの数字・縦横の配置（描くだけ。ゲームの決まりは変えない）
## stick_prototype.gd（まとめ役。状態の変数はそちら）から分けた部品。本体の変数・関数は b. で使う。動きは分ける前と同じ。

const CameraRig := preload("res://scripts/prototype/camera_rig.gd")
const CONFIG_PATH := "res://data/prototype_stick.json"
const FIREBASE_CONFIG_PATH := "res://data/firebase_config.json"
const SLOTS := ["p1", "p2", "p3", "p4"]
const StickMath := preload("res://scripts/prototype/stick_math.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Pattern := preload("res://scripts/combat/boss_pattern.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const AiAlly := preload("res://scripts/combat/ai_ally.gd")
const SfxPlayer := preload("res://scripts/audio/sfx.gd")
const RoomCode := preload("res://scripts/network/room_code.gd")
const Bridge := preload("res://scripts/network/room_bridge.gd")
const Sync := preload("res://scripts/network/position_sync.gd")
const BossSync := preload("res://scripts/network/boss_sync.gd")
const BossModel := preload("res://scripts/boss/boss_model.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
const CheckScreen := preload("res://scripts/experiments/firebase_check.gd")
const Recorder := preload("res://scripts/combat/highlight_recorder.gd")
const CrowdState := preload("res://scripts/combat/crowd_state.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Logic := preload("res://scripts/flow/flow_logic.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const SubCrowd := preload("res://scripts/prototype/sub_enemy_crowd.gd")
const BossMotion := preload("res://scripts/combat/boss_motion.gd")
const BossPhase := preload("res://scripts/combat/boss_phase.gd")
const BossAI := preload("res://scripts/combat/boss_ai.gd")
const BossRage := preload("res://scripts/combat/boss_rage.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")
const BattleAttackFx := preload("res://scripts/prototype/battle_attack_fx.gd")
const WARNING_SHADER := preload("res://shaders/warning_zone.gdshader")
const BottleMesh := preload("res://scripts/boss/sake_bottle_mesh.gd")
const SakeField := preload("res://scripts/combat/sake_field.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）
## ---- 版75：与えたダメージの数字 ----
var _dmg_nums: RefCounted = null
var _dmg_font: FontVariation = null


func _init(main: StickPrototype) -> void:
	b = main


## 版102（軽量化）：設定の色（"#rrggbb" の文字）を、毎コマ読み直さない（1回読んだら覚える）。
## key が設定にない時は、key そのものを色の文字として読む（ボタンの色の名前を渡す所のため）
var _color_cache: Dictionary = {}


func _cc(key: String, def: String = "") -> Color:
	var c: Variant = _color_cache.get(key)
	if c == null:
		c = Color(str(b.config.get(key, def if def != "" else key)))
		_color_cache[key] = c
	return c


## ダメージの数字の種類ごとの色（覚える）
func _kc(kc: Dictionary, kind: String, field: String, def: String) -> Color:
	var key := "dn:" + kind + ":" + field
	var c: Variant = _color_cache.get(key)
	if c == null:
		c = Color(str(kc.get(field, def)))
		_color_cache[key] = c
	return c


func _draw_overlay() -> void:
	var screen := b.overlay.size
	var fs := int(b.config["ui_font_size"])
	var text_color := _cc("text_color")
	var button_text := _cc("button_text_color")
	var r := float(b.config["stick_radius_px"])
	var c := _stick_center(screen)
	# 版117：スティック（暗い円・うすい輪・4方向の小さな矢じり・動かしている時は、その向きの輪が自分の役職の色で光る）
	var stc: Dictionary = b.config.get("stick_style", {})
	var accent := _my_accent()
	var active := b.stick_vec.length() > 0.1
	b.overlay.draw_circle(c, r, Color(str(stc.get("base", "#0a0f1c66"))))
	b.overlay.draw_arc(c, r, 0.0, TAU, 48, Color(str(stc.get("ring", "#c8d4f080"))), 2.0, true)
	b.overlay.draw_arc(c, r * 0.62, 0.0, TAU, 40, Color(str(stc.get("inner_ring", "#c8d4f026"))), 1.5, true)
	for i in 4:
		var ang := PI * 0.5 * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var tip := c + dir * (r - 10.0)
		var side := Vector2(-dir.y, dir.x) * 7.0
		b.overlay.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + side, tip - dir * 9.0 - side]), Color(str(stc.get("chevron", "#c8d4f066"))))
	if active:
		var a0 := b.stick_vec.angle()
		b.overlay.draw_arc(c, r, a0 - 0.55, a0 + 0.55, 16, Color(accent.r, accent.g, accent.b, 0.9), 5.0, true)
	var kp := c + b.stick_vec * r
	var kr := r * 0.4
	b.overlay.draw_circle(kp, kr, Color(str(stc.get("knob", "#e8eefc"))) if active else Color(str(stc.get("knob_idle", "#c8d4f0b0"))))
	b.overlay.draw_arc(kp, kr, 0.0, TAU, 32, Color(accent.r, accent.g, accent.b, 0.95 if active else 0.5), 3.0, true)

	_draw_buttons(screen)

	# 版92：上の文字の行（説明・BOSS HP・やく/体力・なかま・通信）はやめた。体力は、画面に固定した新しい表示（battle_hp_hud.gd）
	# 版102：体力の表示は、自分の板（b.hp_hud.layer）に、見た目が変わった時だけ描く（ここでは描かない）
	var hud_bottom: float = float(b.hp_hud.layout(screen)["center_bottom"])
	# 版の数字（公開した版の確認用）：右下に小さく、うすく
	var vfs := int(fs * 0.5)
	var vtxt := str(b.config["build_label"]) + str(b.config["build_id"])
	var vw := b.font.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs).x
	b.overlay.draw_string(b.font, Vector2(screen.x - vw - 6.0, screen.y - 6.0), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, vfs, Color(1, 1, 1, float((b.config.get("hud", {}) as Dictionary).get("version_alpha", 0.45))))

	if b._start_button_visible():
		var sc := _start_center(screen)
		b.overlay.draw_circle(sc, float(b.config["start_radius_px"]), _cc("button_color"))
		_draw_centered(sc, str(b.config["restart_label"]) if b.round_count > 0 else str(b.config["start_label"]), button_text)
	# 版116：撃破・全滅は大きな見出し（_draw_headline_state）。見出しが消えたあと（画面の流れの外だけ）、前の字と結果の行
	var end_head := float(b.headline.get("left", 0.0)) > 0.0 and str(b.headline.get("kind", "")) in ["win", "lose"]
	if (b.won or b.lost) and not end_head and not b.flow_mode:
		var result := str(b.config["win_text"]) if b.won else str(b.config["lose_text"])
		var ry := maxf(screen.y * 0.22, hud_bottom + fs * 2.2)  # 版92：体力の表示の下に
		_draw_centered(Vector2(screen.x * 0.5, ry), result, text_color, 2.0)
		var lines := b.build_result_lines()
		for i in lines.size():
			_draw_centered(Vector2(screen.x * 0.5, ry + fs * (2.2 + 1.5 * i)), str(lines[i]), text_color)
	# 版116：前の「ボスが おこった」（始まって45秒からずっと点めつ）はやめた。怒りはボスの体力の表示の「激昂」と、大きな見出し
	if float(b.phase_text["left"]) > 0.0 and str(b.phase_text["text"]) != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.3), str(b.phase_text["text"]), _cc("bossbar_color_awake", "#ffffff"), 1.8)
	# 版84・116：自分が倒れている時の板（DOWN・のこり時間・起こしてもらっている進み）
	_draw_my_status(screen)
	_draw_reticle()
	_draw_dodge_text()
	_draw_damage_numbers(screen)
	_draw_enemy_attack(screen)  # 版112
	_draw_toast(screen)  # 版116
	_draw_enemy_intro(screen)
	_draw_awakening(screen)
	_draw_headline_state(screen, b.headline)  # 版116：ボス ダウン・激昂・撃破・全滅
	_draw_headline_state(screen, b.personal_cue)  # 版116：DOWN・復活！
	_draw_banner(screen)


## 版110：A・X・Y・必殺のボタン（右下に2×2・同じ大きさ・角ばった板）。中に大きく A／X／Y／必殺、その下に小さく技の名前。
## 押すと短く光ってふくらむ（button_flash）。使えない時は暗く、待ち時間の残りを上から暗い帯で。必殺はゲージを下からためる
func _draw_buttons(screen: Vector2) -> void:
	var bc: Dictionary = b.config.get("battle_buttons", {})
	var held := b._me_held()
	var accent := _my_accent()
	for id in b.actions.ids():
		var key := str(id)
		var rect := _button_rect(key, screen)
		var flash := float(b.button_flash.get(key, 0.0)) > 0.0
		var is_ult := key == "ultimate"
		var cd_left := b.actions.cooldown_left(key)
		var ready := not held and not b.downed and not b.actions.busy() and cd_left <= 0.0 and (not is_ult or b.gauge.is_ready())  # 版116：倒れている間も暗く
		var edge := accent
		if key == "sub":
			edge = _cc(str(bc.get("edge_sub", "#9fe8ff")))
		elif is_ult:
			edge = _cc(str(bc.get("edge_ultimate", "#ffd24a")))
		if flash:
			var k := float(bc.get("press_scale", 1.08))
			rect = Rect2(rect.get_center() - rect.size * k * 0.5, rect.size * k)
		var sk := float(bc.get("skew_px", 12.0))
		var poly := PackedVector2Array([rect.position + Vector2(sk, 0), Vector2(rect.end.x, rect.position.y), rect.end - Vector2(sk, 0), Vector2(rect.position.x, rect.end.y)])
		# 光（押した時・必殺技が使える時）
		if flash or (is_ult and ready):
			var pulse := 1.0 if flash else 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.012)
			for i in 3:
				var e := 3.0 + 3.0 * i
				var g := PackedVector2Array([poly[0] + Vector2(0, -e), poly[1] + Vector2(e, -e), poly[2] + Vector2(0, e), poly[3] + Vector2(-e, e)])
				b.overlay.draw_colored_polygon(g, Color(edge.r, edge.g, edge.b, 0.16 * pulse / float(i + 1)))
		b.overlay.draw_colored_polygon(poly, _cc(str(bc.get("fill" if ready or flash else "fill_disabled", "#0b0f1ce6"))))
		if flash:
			b.overlay.draw_colored_polygon(poly, Color(edge.r, edge.g, edge.b, 0.35))
		# 必殺技のゲージ（下からたまる）
		if is_ult and not b.gauge.is_ready():
			var fr := clampf(b.gauge.ratio(), 0.0, 1.0)
			var top := rect.end.y - rect.size.y * fr
			var clip := Geometry2D.intersect_polygons(poly, PackedVector2Array([Vector2(rect.position.x - sk, top), Vector2(rect.end.x + sk, top), Vector2(rect.end.x + sk, rect.end.y + 1), Vector2(rect.position.x - sk, rect.end.y + 1)]))
			for cp in clip:
				b.overlay.draw_colored_polygon(cp, Color(edge.r, edge.g, edge.b, 0.32))
		# 待ち時間の残り（上から暗い帯）
		var cd_total := float(b.actions.def(key).get("cooldown_sec", 0.0)) if key != "normal" else b.role_value("attack_cooldown_sec")
		if cd_left > 0.0 and cd_total > 0.0:
			var frac := clampf(cd_left / cd_total, 0.0, 1.0)
			var bottom := rect.position.y + rect.size.y * frac
			var shade := Geometry2D.intersect_polygons(poly, PackedVector2Array([Vector2(rect.position.x - sk, rect.position.y - 1), Vector2(rect.end.x + sk, rect.position.y - 1), Vector2(rect.end.x + sk, bottom), Vector2(rect.position.x - sk, bottom)]))
			for sp in shade:
				b.overlay.draw_colored_polygon(sp, _cc(str(bc.get("cooldown_shade", "#000000a0"))))
		var ec := edge if ready or flash else edge.darkened(0.55)
		var loop := poly.duplicate()
		loop.append(poly[0])
		b.overlay.draw_polyline(loop, ec, 3.0 if ready else 2.0, true)
		# 字：大きく A／X／Y／必殺、その下に小さく技の名前
		var letters: Dictionary = bc.get("letters", {})
		var letter := "×" if held else str(letters.get(key, key))
		var lpx := int(bc.get("letter_px_ultimate" if is_ult else "letter_px", 40))
		var npx := int(bc.get("name_px", 16))
		var tc := Color.WHITE if ready or flash else Color(1, 1, 1, 0.45)
		var lw := b.font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx).x
		var ly := rect.position.y + rect.size.y * 0.52
		# 版114：Y は、出始めに回避のある技。上に小さく「回避」
		if key == "sub" and not held and bool(b.actions.def(key).get("dodge", false)):
			var tag := str(bc.get("sub_tag", "回避"))
			var tpx := int(bc.get("sub_tag_px", 13))
			var tw := b.font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tpx).x
			var tp := Vector2(rect.get_center().x - tw * 0.5, rect.position.y + float(tpx) + 4.0)
			b.overlay.draw_string(b.font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tpx, Color(edge.r, edge.g, edge.b, tc.a))
		b.overlay.draw_string_outline(b.font, Vector2(rect.get_center().x - lw * 0.5, ly), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx, 6, Color(0, 0, 0, 0.8))
		b.overlay.draw_string(b.font, Vector2(rect.get_center().x - lw * 0.5, ly), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx, tc)
		var nx: String = b.actions.combo_next(key)  # 版111：続けて押せる間は、次の技の名前（兵隊の「ぬいぐるみ2体投げ」）
		var nm := str(b.actions.def(nx if nx != "" else key).get("name", ""))
		if nm != "" and not held:
			var px := npx
			var nw := b.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var room := rect.size.x - sk * 2.0 - 8.0
			if nw > room and nw > 0.0:
				px = maxi(10, int(float(px) * room / nw))  # 長い名前は、字を小さくして入れる（大きさは決まった数段）
				px = px - px % 2
				nw = b.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var ny := rect.end.y - rect.size.y * 0.16
			b.overlay.draw_string_outline(b.font, Vector2(rect.get_center().x - nw * 0.5, ny), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0, 0, 0, 0.8))
			b.overlay.draw_string(b.font, Vector2(rect.get_center().x - nw * 0.5, ny), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(tc.r, tc.g, tc.b, tc.a * 0.92))


## 自分のキャラの役職の色（ボタンのふち）。キャラがなければ白
func _my_accent() -> Color:
	var key := "accent:" + str(b.selected_character)
	var c: Variant = _color_cache.get(key)
	if c == null:
		var def: Dictionary = b.selected_def()
		c = Color(str(def.get("role_color", "#ffffff")))
		_color_cache[key] = c
	return c


## 版110：Y の回避に成功した時の「回避！」（自分の頭の上。短く）
func _draw_dodge_text() -> void:
	if float(b.dodge_text_left) <= 0.0 or b.camera == null or DisplayServer.get_name() == "headless":
		return
	var dc: Dictionary = b.config.get("dodge", {})
	var w := Vector3(b.player.position.x, b.ground_y + 4.2, b.player.position.z)
	if b.camera.is_position_behind(w):
		return
	var p := b.camera.unproject_position(w)
	var a := clampf(float(b.dodge_text_left) / 0.25, 0.0, 1.0)
	var col := Color(str(dc.get("color", "#bff4ff")))
	col.a = a
	_draw_centered(p, str(dc.get("text", "回避！")), col, 1.3)


## 版79：ロックした敵の、赤い照準（敵の体の中心。顔を隠さない大きさ。ロックした瞬間に、外から縮んで合う）。
## 近くの攻撃が届かない遠さなら、照準を少し暗くして、点線にする。回復の送り先の味方には、緑の小さな輪
func _draw_reticle() -> void:
	if b.camera == null or DisplayServer.get_name() == "headless":
		return
	if b.target_lock.is_locked():
		var ti: Dictionary = b.target_info()
		if not ti.is_empty():
			var c := Vector3(float(ti["x"]), float(ti["y0"]) + float(ti["h"]) * float(b.config.get("reticle_height_frac", 0.42)), float(ti["z"]))
			if not b.camera.is_position_behind(c):
				var p := b.camera.unproject_position(c)
				var base := clampf(b._screen_radius(c, float(ti["r"])) * 0.45, 26.0, 80.0)
				var k := clampf(b.target_lock.age / 0.18, 0.0, 1.0)
				var r := base * (1.0 + 1.2 * (1.0 - k))
				var far := Vector2(b.player.position.x, b.player.position.z).distance_to(Vector2(float(ti["x"]), float(ti["z"]))) - float(ti["r"]) > float(b.config.get("reticle_far_m", 14.0))
				var col := Color("#ff3030") if not far else Color("#ff8080")
				col.a = 0.95 * k + 0.05
				var rot := float(Time.get_ticks_msec()) * 0.0015
				# 外の輪（4つに切れた弧が回る）、中の点、上下左右の目印
				for i in 4:
					var a0 := rot + TAU * i / 4.0
					b.overlay.draw_arc(p, r, a0 + 0.15, a0 + TAU / 4.0 - 0.15, 10, Color(0, 0, 0, col.a * 0.6), 7.0)
					b.overlay.draw_arc(p, r, a0 + 0.15, a0 + TAU / 4.0 - 0.15, 10, col, 4.0)
				for i in 4:
					var dir := Vector2(cos(TAU * i / 4.0), sin(TAU * i / 4.0))
					b.overlay.draw_line(p + dir * (r - 10.0), p + dir * (r + 12.0), col, 4.0)
				b.overlay.draw_circle(p, 4.5, col)
	if b.ally_lock != "":
		var ap: Vector3 = b.skills.pos3_of(b.ally_lock) + Vector3(0, 2.3, 0)
		if not b.camera.is_position_behind(ap):
			var q := b.camera.unproject_position(ap)
			b.overlay.draw_arc(q, 14.0, 0, TAU, 20, Color("#5fe08a"), 4.0)


## 版112：必殺技の名前（画面のまん中に大きく）。役職の色の光・角ばった帯（左右からのびる）。
## 名前が画面に入らない時は、字を小さくする（拡大率だけ変える。文字の絵の大きさは決まった数段のまま）
func _draw_banner(screen: Vector2) -> void:
	var left := float(b.banner["left"])
	if left <= 0.0:
		return
	var L := banner_layout(screen)
	var lv: Dictionary = L["lv"]
	var fs: float = L["fs"]
	var w: float = L["w"]
	var center: Vector2 = L["center"]
	var age := float(b.banner["total"]) - left
	var alpha := clampf(left / 0.4, 0.0, 1.0)
	var rc: Color = b.banner.get("color", _cc("banner_color"))
	var uc: Dictionary = b.config.get("ult_banner", {})
	# 帯：斜めの暗い帯が、まんなかから左右へのびる。上下のふちに役職の色の線
	var grow := clampf(age / float(uc.get("open_sec", 0.16)), 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var hh := fs * 0.78
	var sk := hh * 0.7
	var half := (screen.x * 0.5 + sk) * grow
	var poly := PackedVector2Array([Vector2(center.x - half + sk, center.y - hh), Vector2(center.x + half + sk, center.y - hh),
		Vector2(center.x + half - sk, center.y + hh), Vector2(center.x - half - sk, center.y + hh)])
	var back := _cc("banner_back_color")
	back.a *= alpha
	b.overlay.draw_colored_polygon(poly, back)
	var edge := Color(rc.r, rc.g, rc.b, 0.9 * alpha)
	b.overlay.draw_line(poly[0], poly[1], edge, 3.0)
	b.overlay.draw_line(poly[3], poly[2], edge, 3.0)
	b.overlay.draw_line(poly[0] + Vector2(0, 6), poly[1] + Vector2(0, 6), Color(rc.r, rc.g, rc.b, 0.3 * alpha), 1.0)
	if grow < 0.98:
		return
	# 字：役職の色の光（太い縁取りをうすく2回）→ 黒い縁取り → 白っぽい字
	var at := center + Vector2(-w * 0.5, fs * 0.35)
	var glow := Color(rc.r, rc.g, rc.b, 0.22 * alpha)
	_scaled_string(b.font, at, str(b.banner["text"]), lv, Color(0, 0, 0, 0), int(uc.get("glow_px", 26)), glow)
	_scaled_string(b.font, at, str(b.banner["text"]), lv, Color(0, 0, 0, 0), int(uc.get("glow_px", 26)) / 2, Color(rc.r, rc.g, rc.b, 0.35 * alpha))
	var fill := Color.WHITE.lerp(rc, float(uc.get("fill_tint", 0.25)))
	fill.a = alpha
	_scaled_string(b.font, at, str(b.banner["text"]), lv, fill, int(uc.get("outline_px", 8)), Color(0, 0, 0, 0.85 * alpha))
	var who := str(b.banner["who"])
	if who != "":
		var fs2 := int(float(b.config["ui_font_size"]) * 0.9)
		var w2 := b.font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var wp := center + Vector2(-w2 * 0.5, hh + fs2 * 1.05)
		b.overlay.draw_string_outline(b.font, wp, who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 6, Color(0, 0, 0, 0.8 * alpha))
		b.overlay.draw_string(b.font, wp, who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(rc.r, rc.g, rc.b, alpha).lightened(0.25))


## 版112：必殺技の名前の大きさと場所。{lv（文字の絵の大きさ px と拡大率 k）, fs（画面での字の高さ）, w（字の幅）, center}
func banner_layout(screen: Vector2) -> Dictionary:
	var uc: Dictionary = b.config.get("ult_banner", {})
	var total := maxf(0.01, float(b.banner["total"]))
	var age := total - float(b.banner["left"])
	var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.25)
	var center := Vector2(screen.x * 0.5, screen.y * (float(b.config["banner_y_portrait"]) if is_portrait(screen) else float(b.config["banner_y"])))
	# 版99：文字の大きさを毎コマ変えると、大きさごとに文字の絵が作られてメモリが増える。
	# 決まった数段の大きさ（text_pop_levels）で描いて、あとは拡大・縮小（draw_set_transform）ではね上がりを出す
	var settled := int(float(b.config["ui_font_size"]) * float(uc.get("size_k", 2.4)))
	var lv := pop_text(settled, pop, text_pop_levels())
	var w := b.font.get_string_size(str(b.banner["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"])).x * float(lv["k"])
	var maxw := screen.x * float(uc.get("max_w_frac", 0.86))
	if w > maxw and w > 0.0:
		lv["k"] = float(lv["k"]) * maxw / w
		w = maxw
	return {"lv": lv, "fs": float(lv["px"]) * float(lv["k"]), "w": w, "center": center}


func _draw_centered(center: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	var fs := int(float(b.config["ui_font_size"]) * scale)
	var w := b.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	b.overlay.draw_string(b.font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## なかまの体力の一覧（この戦いに出ている、自分以外）
## なかまの名前のあとに付ける、キャラの印（版109：共有されていれば役職名「介護士」。まだなら空）
func _char_tag(slot: String) -> String:
	var def := b.char_def_of(slot)
	if def.is_empty():
		return ""
	return " " + str(def.get("name", ""))


func build_team_text() -> String:
	var fighters := BossSync.others_hp(b.net_state.get("hp", {}), str(b.net_state.get("slot", "")), b.net_state.get("members", []), b.round_start_ms)
	var text := ""
	for slot in fighters:
		text += "  " + str(slot) + _char_tag(str(slot)) + " " + str(ceili(float(fighters[slot])))
	for slot in b.ai_allies:
		text += "  " + str(slot) + _char_tag(str(slot)) + " " + str(ceili(float(b.ai_allies[slot]["hp"])))
	if text == "":
		return ""
	return str(b.config["team_label"]) + text


func damage_numbers() -> RefCounted:
	if _dmg_nums == null:
		_dmg_nums = DamageNumbers.new(b.config.get("damage_numbers", {}))
	return _dmg_nums


## 実際に与えたダメージ amount を、ボスの体の、当てた人（from：床の上の x, z）の側に出す。action：技の名前（強い技は大きく）
func _show_damage(amount: float, action: String, from: Vector2) -> void:
	var dc: Dictionary = b.config.get("damage_numbers", {})
	var kind := "strong" if (dc.get("strong_actions", []) as Array).has(action) else "normal"
	var bxz := Vector2(b.boss.position.x, b.boss.position.z)
	var to := from - bxz
	var side := to.normalized() * float(b.config["boss_size"]) * 0.5 * float(dc.get("toward", 0.6)) if to.length() > 0.01 else Vector2.ZERO
	damage_numbers().add(amount, Vector3(bxz.x + side.x, float(dc.get("height_m", 4.0)), bxz.y + side.y), kind)


func _draw_damage_numbers(screen: Vector2) -> void:
	var dn: RefCounted = damage_numbers()
	if dn.items.is_empty() or b.camera == null or b.font == null or DisplayServer.get_name() == "headless":
		return  # 画面のないテストでは描かない（数字の中身は damage_numbers() で調べる）
	var dc: Dictionary = b.config.get("damage_numbers", {})
	if _dmg_font == null:
		_dmg_font = FontVariation.new()
		_dmg_font.base_font = b.font
		_dmg_font.variation_embolden = float(dc.get("embolden", 0.9))  # 太い文字（いまの文字の形を太らせる）
	var base := float(b.config["ui_font_size"]) * float(dc.get("size_scale", 1.4))
	var levels := text_pop_levels()
	for it in dn.items:
		var w: Vector3 = it["world"]
		if b.camera.is_position_behind(w):
			continue
		var kc: Dictionary = dn.kind_cfg(str(it["kind"]))
		var lk: Dictionary = dn.look(it)
		# 版99：落ち着いた時の大きさ（種類ごとに1つ）× 決まった数段で描き、はね上がりは拡大・縮小で出す
		var settled := maxi(int(dc.get("min_px", 18)), int(base * float(kc.get("size", 1.0))))
		var lv := pop_text(settled, float(lk["scale"]), levels)
		var text := str(it["text"])
		var sz := _dmg_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"])) * float(lv["k"])
		var p := b.camera.unproject_position(w) + Vector2(float(it["dx"]) + float(lk["shake"]), float(it["dy"]) - float(lk["rise"]))
		p = DamageNumbers.keep_on_screen(p, screen, sz * 0.5, float(dc.get("margin_px", 12.0)))
		var a := float(lk["alpha"])
		# 強い攻撃：出た瞬間の、短い衝撃線
		if float(lk["burst"]) > 0.0:
			var bcol := _kc(kc, str(it["kind"]), "burst_color", "#fff3b0")
			bcol.a = a * float(lk["burst"])
			for i in 8:
				var ang := TAU * i / 8.0 + 0.2
				var dir := Vector2(cos(ang), sin(ang))
				var r0 := sz.x * 0.45 + 6.0
				var r1 := r0 + 26.0 * (1.2 - float(lk["burst"]))
				b.overlay.draw_line(p + dir * r0, p + dir * r1, bcol, 4.0)
		var at := p + Vector2(-sz.x * 0.5, sz.y * 0.32)
		var oc := _kc(kc, str(it["kind"]), "outline", "#2b1606")
		oc.a = a
		var fc := _kc(kc, str(it["kind"]), "color", "#fff6c8")
		fc.a = a
		_scaled_string(_dmg_font, at, text, lv, fc, int(dc.get("outline_px", 9)), oc)


## 版99：はね上がる文字の、描く大きさ。settled：落ち着いた時の大きさ（px）、scale：いまの倍率。
## levels（倍率の段）のうち、いまの倍率にいちばん近い段の大きさ px で描き、k 倍に拡大・縮小する（px × k ＝ settled × scale）。
## 描く大きさは「settled × 段」だけになるので、文字の絵（フォントのキャッシュ）が毎コマ増えない
static func pop_text(settled: int, scale: float, levels: Array) -> Dictionary:
	var best := 1.0
	var best_d := INF
	var s := maxf(scale, 0.01)
	for l in levels:
		var d := absf(log(s / maxf(float(l), 0.01)))
		if d < best_d:
			best_d = d
			best = float(l)
	var px := maxi(1, roundi(float(settled) * best))
	return {"px": px, "k": float(settled) * s / float(px)}


## 倍率の段（data/prototype_stick.json の hud.text_pop_levels）
func text_pop_levels() -> Array:
	return (b.config.get("hud", {}) as Dictionary).get("text_pop_levels", [1.0])


## 文字を、pop_text の大きさで描いて、左下の点 at から k 倍に広げる（outline > 0 なら縁取りも）
func _scaled_string(font: Font, at: Vector2, text: String, lv: Dictionary, color: Color, outline: int = 0, outline_color: Color = Color.BLACK) -> void:
	var k := float(lv["k"])
	b.overlay.draw_set_transform(at, 0.0, Vector2(k, k))
	if outline > 0:
		b.overlay.draw_string_outline(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"]), outline, outline_color)
	b.overlay.draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"]), color)
	b.overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _stick_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("stick_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


func _start_center(screen: Vector2) -> Vector2:
	var f: Array = _layout("start_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


## 配置の値。縦長の画面では、「…_portrait」があればそちらを使う
func _layout(key: String, screen: Vector2) -> Array:
	if is_portrait(screen) and b.config.has(key + "_portrait"):
		return b.config[key + "_portrait"]
	return b.config[key]


## 縦長の画面か
static func is_portrait(size: Vector2) -> bool:
	return size.y > size.x


## 縦横の向きを合わせる：基準の大きさ（文字・ボタンの大きさの元）、カメラの見え方を切り替える。向きが変わったときだけ動く
func apply_orientation(window_size: Vector2) -> void:
	var portrait := is_portrait(window_size)
	if portrait != b.portrait_mode:
		b.portrait_mode = portrait
		var base: Array = b.config["portrait_base_size"] if portrait else b.config["landscape_base_size"]
		var win := b.get_window()
		if win != null:
			win.content_scale_size = Vector2i(int(base[0]), int(base[1]))
		b.camera_rig_size = Vector2.ZERO
	# 版91：カメラの高さ・角度・画角（camera_rig.gd）。画面の形が変わった時だけ決めなおす
	if b.camera_rig_size.is_equal_approx(window_size):
		return
	b.camera_rig_size = window_size
	var rig := CameraRig.rig_for(b.config, window_size if window_size.x > 0.0 and window_size.y > 0.0 else Vector2(16, 9))
	if rig.is_empty():
		var off: Array = b.config["camera_offset_portrait"] if portrait else b.config["camera_offset"]
		b.camera_offset = Vector3(off[0], off[1], off[2])
		b.camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
		b.camera.fov = float(b.config["camera_fov_portrait"]) if portrait else float(b.config["camera_fov"])
		return
	b.camera_offset = rig["offset"]
	b.camera_look_h = float(rig["look_h"])
	b.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	b.camera.fov = float(rig["fov"])


## ボタンの中心（画面の割合は data/prototype_stick.json の「<id>_center_frac」。縦長なら「…_portrait」）
func _button_center(id: String, screen: Vector2) -> Vector2:
	var f: Array = _layout(id + "_center_frac", screen)
	return Vector2(screen.x * f[0], screen.y * f[1])


## 版110：ボタンの四角（同じ大きさ。battle_buttons.size。縦長なら size_portrait）
func _button_rect(id: String, screen: Vector2) -> Rect2:
	var bc: Dictionary = b.config.get("battle_buttons", {})
	var sz: Array = bc.get("size_portrait", [140, 104]) if is_portrait(screen) else bc.get("size", [130, 96])
	var size := Vector2(float(sz[0]), float(sz[1]))
	return Rect2(_button_center(id, screen) - size * 0.5, size)


## 触れた場所にある、攻撃ボタンの id。なければ ""（版110：四角の中。ふちから少し外まで押せる）
func _button_at(pos: Vector2, screen: Vector2) -> String:
	for id in b.actions.ids():
		if _button_rect(str(id), screen).grow(6.0).has_point(pos):
			return str(id)
	return ""


func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return StickMath.stick_vector(pos, _stick_center(screen), float(b.config["stick_radius_px"]), float(b.config["stick_dead_zone"]))


## 必殺技の名前を、画面の真ん中に出す。who：使った人の表示（空なら出さない）
func _show_banner(text: String, who: String, seconds: float, color: Color = Color(1.0, 0.89, 0.48)) -> void:
	b.banner = {"text": text, "who": who, "left": seconds, "total": seconds, "color": color}


## 版112：敵の登場（試合の始めに1回）。「ENEMY APPROACH」・敵の名前を大きく・役（BOSS）。線が左右からのび、暗い帯の上に出る
func _draw_enemy_intro(screen: Vector2) -> void:
	var ei: Dictionary = b.enemy_intro
	var left := float(ei.get("left", 0.0))
	if left <= 0.0:
		return
	var ec: Dictionary = b.config.get("enemy_intro", {})
	var age := float(ei["total"]) - left
	var a_in := clampf(age / 0.25, 0.0, 1.0)
	var alpha := minf(a_in, clampf(left / 0.45, 0.0, 1.0))
	var col := Color(str(ec.get("color", "#ff3b30")))
	var cy := screen.y * float(ec.get("y_frac_portrait" if is_portrait(screen) else "y_frac", 0.36))
	var cx := screen.x * 0.5
	var name_px := int(ec.get("name_px", 54))
	var title_px := int(ec.get("title_px", 24))
	var hh := float(name_px) * 1.45
	b.overlay.draw_rect(Rect2(0.0, cy - hh, screen.x, hh * 2.0), Color(0, 0, 0, 0.55 * alpha))
	var lw := screen.x * 0.5 * (1.0 - pow(1.0 - a_in, 3.0))
	var lc := Color(col.r, col.g, col.b, 0.95 * alpha)
	b.overlay.draw_line(Vector2(cx - lw, cy - hh), Vector2(cx + lw, cy - hh), lc, 3.0)
	b.overlay.draw_line(Vector2(cx - lw, cy + hh), Vector2(cx + lw, cy + hh), lc, 3.0)
	# ENEMY APPROACH（字の間をあける。はじめの少しの間、点めつ）
	var title := str(ec.get("title", "ENEMY APPROACH"))
	var blink := 1.0 if age > 0.6 or int(age * 12.0) % 2 == 0 else 0.35
	var tc := Color(col.r, col.g, col.b, alpha * blink).lightened(0.2)
	_spaced_string(Vector2(cx, cy - hh + float(title_px) * 1.05), title, title_px, float(ec.get("title_spacing", 6.0)), tc)
	# 敵の名前（大きく。少し右から入る）
	var nm := str(ei.get("name", ""))
	var nw := b.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px).x
	var slide := (1.0 - pow(1.0 - clampf((age - 0.1) / 0.3, 0.0, 1.0), 3.0))
	var np := Vector2(cx - nw * 0.5 + (1.0 - slide) * 60.0, cy + float(name_px) * 0.36)
	var na := alpha * slide
	b.overlay.draw_string_outline(b.font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, 20, Color(col.r, col.g, col.b, 0.25 * na))
	b.overlay.draw_string_outline(b.font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, 8, Color(0, 0, 0, 0.9 * na))
	b.overlay.draw_string(b.font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_px, Color(1, 1, 1, na))
	var role := str(ei.get("role", ""))
	if role != "":
		_spaced_string(Vector2(cx, cy + hh - float(title_px) * 0.95), role, title_px, 4.0, Color(1, 1, 1, 0.8 * na))


## 版112：ボスの覚醒（1回だけ）。画面のふちが赤く光り、「AWAKENING」が大きく出て落ち着き、その下に「覚醒」
func _draw_awakening(screen: Vector2) -> void:
	var aw: Dictionary = b.awaken_fx
	var left := float(aw.get("left", 0.0))
	if left <= 0.0:
		return
	var ac: Dictionary = b.config.get("awakening_fx", {})
	var age := float(aw["total"]) - left
	var alpha := minf(clampf(age / 0.12, 0.0, 1.0), clampf(left / 0.5, 0.0, 1.0))
	var col := Color(str(ac.get("color", "#ff2a6a")))
	# 画面のふち（4辺の帯。内側へうすく。脈うつ）
	var pulse := 0.6 + 0.4 * sin(age * 14.0)
	var ep := float(ac.get("edge_px", 80.0))
	if ep > 0.0:
		# 外は色・内は透明の、4辺の帯（頂点の色でぼかす）
		var co := Color(col.r, col.g, col.b, float(ac.get("edge_alpha", 0.42)) * alpha * pulse)
		var ci := Color(col.r, col.g, col.b, 0.0)
		var o := [Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)]
		var n := [Vector2(ep, ep), Vector2(screen.x - ep, ep), screen - Vector2(ep, ep), Vector2(ep, screen.y - ep)]
		for i in 4:
			var j := (i + 1) % 4
			b.overlay.draw_polygon(PackedVector2Array([o[i], o[j], n[j], n[i]]), PackedColorArray([co, co, ci, ci]))
	var cy := screen.y * float(ac.get("y_frac_portrait" if is_portrait(screen) else "y_frac", 0.32))
	var px := int(ac.get("title_px", 64))
	var title := str(ac.get("title", "AWAKENING"))
	var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.22)
	var lv := pop_text(px, pop, text_pop_levels())
	var w := b.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"])).x * float(lv["k"])
	var maxw := screen.x * 0.9
	if w > maxw:
		lv["k"] = float(lv["k"]) * maxw / w
		w = maxw
	var shake := Vector2(sin(age * 61.0), cos(age * 47.0)) * 4.0 * maxf(0.0, 1.0 - age / 0.6)
	var at := Vector2(screen.x * 0.5 - w * 0.5, cy) + shake
	_scaled_string(b.font, at, title, lv, Color(0, 0, 0, 0), 24, Color(col.r, col.g, col.b, 0.3 * alpha))
	_scaled_string(b.font, at, title, lv, Color(1.0, 0.92, 0.95, alpha), 8, Color(0.1, 0, 0.03, 0.9 * alpha))
	var sub := str(ac.get("sub", "覚醒"))
	var spx := int(ac.get("sub_px", 40))
	var sw := b.font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x
	var sp := Vector2(screen.x * 0.5 - sw * 0.5, cy + float(spx) * 1.35)
	var sa := alpha * clampf((age - 0.2) / 0.25, 0.0, 1.0)
	b.overlay.draw_string_outline(b.font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, 8, Color(0, 0, 0, 0.9 * sa))
	b.overlay.draw_string(b.font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, Color(col.r, col.g, col.b, sa).lightened(0.3))


## 版112：敵の攻撃の名前（右上。右から流れて入り、少しして消える。新しい攻撃が来たら、前の名前は消して入れかえる）
func _draw_enemy_attack(screen: Vector2) -> void:
	var ea: Dictionary = b.enemy_attack
	var left := float(ea.get("left", 0.0))
	if left <= 0.0:
		return
	var r := enemy_attack_rect(screen)
	var lc: Dictionary = b.config.get("enemy_attack_label", {})
	var age := float(ea["total"]) - left
	var slide := 1.0 - pow(1.0 - clampf(age / float(lc.get("slide_sec", 0.18)), 0.0, 1.0), 3.0)
	var alpha := clampf(left / 0.3, 0.0, 1.0)
	var off := (1.0 - slide) * (r.size.x + 20.0)
	var ult := bool(ea.get("ult", false))
	var col := Color(str(lc.get("ult_color" if ult else "color", "#ff5a3a")))
	var sk := r.size.y * 0.35
	var poly := PackedVector2Array([r.position + Vector2(sk + off, 0), Vector2(r.end.x + off, r.position.y), r.end + Vector2(off, 0), Vector2(r.position.x + off, r.end.y)])
	b.overlay.draw_colored_polygon(poly, Color(0.02, 0.03, 0.06, 0.82 * alpha))
	b.overlay.draw_colored_polygon(PackedVector2Array([poly[0], poly[0] + Vector2(6, 0), poly[3] + Vector2(6, 0), poly[3]]), Color(col.r, col.g, col.b, alpha))
	b.overlay.draw_line(poly[3], poly[2], Color(col.r, col.g, col.b, 0.8 * alpha), 2.0)
	var px := int(lc.get("px", 22))
	var cap_px := int(lc.get("caption_px", 12))
	var cap := str(lc.get("ult_caption" if ult else "caption", "ENEMY SKILL"))
	b.overlay.draw_string(b.font, Vector2(r.position.x + sk + 10.0 + off, r.position.y + float(cap_px) + 3.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_px, Color(col.r, col.g, col.b, 0.9 * alpha))
	var tp := Vector2(r.position.x + sk + 10.0 + off, r.end.y - 8.0)
	b.overlay.draw_string_outline(b.font, tp, str(ea["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px, 5, Color(0, 0, 0, 0.85 * alpha))
	b.overlay.draw_string(b.font, tp, str(ea["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 1, 1, alpha))


## 版112：敵の攻撃の名前の四角（右上。ボスの体力のバー・なかまの体力の列と重ならない所）
func enemy_attack_rect(screen: Vector2) -> Rect2:
	var lc: Dictionary = b.config.get("enemy_attack_label", {})
	var px := int(lc.get("px", 22))
	var cap_px := int(lc.get("caption_px", 12))
	var tw := b.font.get_string_size(str(b.enemy_attack.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var h := float(px + cap_px) + 16.0
	var w := tw + h * 0.35 + 26.0
	var L: Dictionary = b.hp_hud.layout(screen)
	var br: Rect2 = L["boss_rect"]
	var margin := float(lc.get("margin_px", 10.0))
	var right := screen.x - margin
	var top := br.position.y
	if right - w < br.end.x + margin:
		top = br.end.y + margin  # ボスのバーの右に入らない（たて画面）：バーの下
	var r := Rect2(Vector2(right - w, top), Vector2(w, h))
	var pr: Rect2 = L["party_rect"]
	if r.intersects(pr):
		r.position.y = pr.end.y + margin
	return r


## 字の間をあけて、まん中に描く（英字の見出し用。大きさは決まった数）
func _spaced_string(center: Vector2, text: String, px: int, spacing: float, color: Color) -> void:
	var total := 0.0
	var ws: Array = []
	for ch in text:
		var cw := b.font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		ws.append(cw)
		total += cw + spacing
	total -= spacing
	var x := center.x - total * 0.5
	var y := center.y + float(px) * 0.35
	var i := 0
	for ch in text:
		b.overlay.draw_string_outline(b.font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, Color(0, 0, 0, 0.8 * color.a))
		b.overlay.draw_string(b.font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		x += float(ws[i]) + spacing
		i += 1


## 版116：大きな見出しの演出（ボス ダウン・激昂・撃破・全滅。覚醒も同じ描き方）。
## st：{left, total, title, sub, color, edge（画面のふちを光らせるか）, band（暗い帯）, y_frac}。字の大きさは決まった数段で、拡大・縮小で動かす
func _draw_headline_state(screen: Vector2, st: Dictionary) -> void:
	var left := float(st.get("left", 0.0))
	if left <= 0.0:
		return
	var age := float(st["total"]) - left
	var alpha := minf(clampf(age / 0.12, 0.0, 1.0), clampf(left / 0.5, 0.0, 1.0))
	var col := Color(str(st.get("color", "#ffffff")))
	var pulse := 0.6 + 0.4 * sin(age * 14.0)
	var ep := float(st.get("edge_px", 0.0))
	if ep > 0.0:
		# 外は色・内は透明の、4辺の帯（頂点の色でぼかす）
		var co := Color(col.r, col.g, col.b, float(st.get("edge_alpha", 0.42)) * alpha * pulse)
		var ci := Color(col.r, col.g, col.b, 0.0)
		var o := [Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)]
		var n := [Vector2(ep, ep), Vector2(screen.x - ep, ep), screen - Vector2(ep, ep), Vector2(ep, screen.y - ep)]
		for i in 4:
			var j := (i + 1) % 4
			b.overlay.draw_polygon(PackedVector2Array([o[i], o[j], n[j], n[i]]), PackedColorArray([co, co, ci, ci]))
	var cy := screen.y * float(st.get("y_frac_portrait" if is_portrait(screen) else "y_frac", 0.32))
	var px := int(st.get("title_px", 64))
	var spx := int(st.get("sub_px", 36))
	if bool(st.get("band", false)):
		# 角ばった暗い帯（まん中から左右へのびる）・上下のふちに色の線
		var grow := 1.0 - pow(1.0 - clampf(age / 0.16, 0.0, 1.0), 3.0)
		var hh := float(px) * 0.75 + float(spx) * 0.9
		var sk := hh * 0.5
		var half := (screen.x * 0.5 + sk) * grow
		var c0 := Vector2(screen.x * 0.5, cy + float(spx) * 0.4)
		var poly := PackedVector2Array([Vector2(c0.x - half + sk, c0.y - hh), Vector2(c0.x + half + sk, c0.y - hh),
			Vector2(c0.x + half - sk, c0.y + hh), Vector2(c0.x - half - sk, c0.y + hh)])
		b.overlay.draw_colored_polygon(poly, Color(0.0, 0.0, 0.02, 0.62 * alpha))
		b.overlay.draw_line(poly[0], poly[1], Color(col.r, col.g, col.b, 0.9 * alpha), 3.0)
		b.overlay.draw_line(poly[3], poly[2], Color(col.r, col.g, col.b, 0.9 * alpha), 3.0)
	# 光の線（左右へ走る。はじめの0.5秒）
	if age < 0.5:
		var k := age / 0.5
		var lc := Color(col.r, col.g, col.b, (1.0 - k) * 0.8 * alpha)
		var lw := screen.x * (0.2 + 0.8 * k)
		b.overlay.draw_line(Vector2(screen.x * 0.5 - lw * 0.5, cy - float(px) * 0.95), Vector2(screen.x * 0.5 + lw * 0.5, cy - float(px) * 0.95), lc, 2.0)
	var title := str(st.get("title", ""))
	var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.22)
	var lv := pop_text(px, pop, text_pop_levels())
	var w := b.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"])).x * float(lv["k"])
	var maxw := screen.x * 0.9
	if w > maxw and w > 0.0:
		lv["k"] = float(lv["k"]) * maxw / w
		w = maxw
	var shake := Vector2(sin(age * 61.0), cos(age * 47.0)) * float(st.get("shake_px", 4.0)) * maxf(0.0, 1.0 - age / 0.6)
	var at := Vector2(screen.x * 0.5 - w * 0.5, cy) + shake
	_scaled_string(b.font, at, title, lv, Color(0, 0, 0, 0), 24, Color(col.r, col.g, col.b, 0.3 * alpha))
	var fill := Color.WHITE.lerp(col, float(st.get("fill_tint", 0.12)))
	fill.a = alpha
	_scaled_string(b.font, at, title, lv, fill, 8, Color(0.03, 0.0, 0.02, 0.9 * alpha))
	var sub := str(st.get("sub", ""))
	if sub != "":
		var sw := b.font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x
		var sp := Vector2(screen.x * 0.5 - sw * 0.5, cy + float(spx) * 1.35)
		var sa := alpha * clampf((age - 0.2) / 0.25, 0.0, 1.0)
		b.overlay.draw_string_outline(b.font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, 8, Color(0, 0, 0, 0.9 * sa))
		b.overlay.draw_string(b.font, sp, sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, Color(col.r, col.g, col.b, sa).lightened(0.3))


## 版116：自分が倒れている時の板（画面の下のまん中）。DOWN・待つ／起こしてもらっている／もう起きられない・のこり時間の帯
func _draw_my_status(screen: Vector2) -> void:
	if b.get("revive_sys") == null:
		return
	var info: Dictionary = b.revive_sys.my_status_info()
	if info.is_empty():
		return
	var rc: Dictionary = b.config.get("revive_ui", {})
	var mode := str(info["mode"])
	var col := Color(str(rc.get("color_" + mode, "#ff5a5a")))
	var w := minf(screen.x * 0.86, float(rc.get("width_px", 520.0)))
	var h := float(rc.get("height_px", 118.0))
	var cy := screen.y * float(rc.get("y_frac_portrait" if is_portrait(screen) else "y_frac", 0.6))
	var r := Rect2(Vector2(screen.x * 0.5 - w * 0.5, cy - h * 0.5), Vector2(w, h))
	var sk := 14.0
	var poly := PackedVector2Array([r.position + Vector2(sk, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(sk, 0), Vector2(r.position.x, r.end.y)])
	b.overlay.draw_colored_polygon(poly, Color(0.02, 0.02, 0.05, 0.82))
	b.overlay.draw_colored_polygon(PackedVector2Array([poly[0], poly[0] + Vector2(7, 0), poly[3] + Vector2(7, 0), poly[3]]), col)
	var loop := poly.duplicate()
	loop.append(poly[0])
	b.overlay.draw_polyline(loop, Color(col.r, col.g, col.b, 0.7), 2.0, true)
	# 見出し（DOWN／REVIVING／K.O.）と説明
	var head := str(rc.get("head_" + mode, "DOWN"))
	var hpx := int(rc.get("head_px", 34))
	var blink := 1.0 if mode != "wait" else 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.008)
	var hp := Vector2(r.position.x + sk + 22.0, r.position.y + float(hpx) + 8.0)
	b.overlay.draw_string_outline(b.font, hp, head, HORIZONTAL_ALIGNMENT_LEFT, -1, hpx, 6, Color(0, 0, 0, 0.9))
	b.overlay.draw_string(b.font, hp, head, HORIZONTAL_ALIGNMENT_LEFT, -1, hpx, Color(col.r, col.g, col.b, blink).lightened(0.15))
	var note := str(info.get("text", ""))
	var npx := int(rc.get("note_px", 20))
	var nw := b.font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, hpx).x
	b.overlay.draw_string(b.font, hp + Vector2(nw + 16.0, -4.0), note, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - hp.x - nw - 30.0, npx, Color(0.9, 0.93, 1.0))
	# 帯（待つ：のこり時間が減る／起こしてもらっている：たまる）と数字
	var bar := Rect2(Vector2(r.position.x + sk + 22.0, r.end.y - 34.0), Vector2(w - sk * 2.0 - 120.0, 14.0))
	b.overlay.draw_rect(bar, Color(1, 1, 1, 0.12))
	var frac := clampf(float(info.get("frac", 0.0)), 0.0, 1.0)
	if frac > 0.0:
		b.overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	var num := str(info.get("num", ""))
	if num != "":
		var mpx := int(rc.get("num_px", 30))
		var mp := Vector2(bar.end.x + 16.0, bar.end.y + 4.0)
		b.overlay.draw_string_outline(b.font, mp, num, HORIZONTAL_ALIGNMENT_LEFT, -1, mpx, 6, Color(0, 0, 0, 0.9))
		b.overlay.draw_string(b.font, mp, num, HORIZONTAL_ALIGNMENT_LEFT, -1, mpx, Color.WHITE)


## 版116：小さなお知らせ（仲間が倒れた・復活した）。画面の上のまん中・角ばった板・新しい物で入れかえ
func _draw_toast(screen: Vector2) -> void:
	var tc: Dictionary = b.toast_cue
	var left := float(tc.get("left", 0.0))
	if left <= 0.0 or str(tc.get("text", "")) == "":
		return
	var age := float(tc["total"]) - left
	var alpha := minf(clampf(age / 0.15, 0.0, 1.0), clampf(left / 0.3, 0.0, 1.0))
	var px := int(b.config.get("toast_px", 24))
	var text := str(tc["text"])
	var w := b.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 44.0
	var h := float(px) + 20.0
	var L: Dictionary = b.hp_hud.layout(screen)
	var y := maxf(float(L["center_bottom"]) + 10.0, screen.y * 0.16)
	var r := Rect2(Vector2(screen.x * 0.5 - w * 0.5, y), Vector2(w, h))
	var sk := h * 0.35
	var poly := PackedVector2Array([r.position + Vector2(sk, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(sk, 0), Vector2(r.position.x, r.end.y)])
	b.overlay.draw_colored_polygon(poly, Color(0.02, 0.03, 0.06, 0.8 * alpha))
	var col := Color(str(b.config.get("toast_color", "#9fe8ff")))
	b.overlay.draw_line(poly[3], poly[2], Color(col.r, col.g, col.b, 0.8 * alpha), 2.0)
	b.overlay.draw_string(b.font, Vector2(r.position.x + 22.0, r.end.y - 10.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 1, 1, alpha))
