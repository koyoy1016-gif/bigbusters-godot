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
	b.overlay.draw_circle(c, r, _cc("stick_base_color"))
	b.overlay.draw_circle(c + b.stick_vec * r, r * 0.4, _cc("stick_knob_color"))

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
	if b.won or b.lost:
		var result := str(b.config["win_text"]) if b.won else str(b.config["lose_text"])
		var ry := maxf(screen.y * 0.22, hud_bottom + fs * 2.2)  # 版92：体力の表示の下に
		_draw_centered(Vector2(screen.x * 0.5, ry), result, text_color, 2.0)
		var lines := b.build_result_lines()
		for i in lines.size():
			_draw_centered(Vector2(screen.x * 0.5, ry + fs * (2.2 + 1.5 * i)), str(lines[i]), text_color)
	if b.is_enraged() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_draw_centered(Vector2(screen.x * 0.5, maxf(screen.y * 0.12, hud_bottom + fs * 1.4)), str(b.config["enrage_text"]), _cc("enrage_color"), 1.4)  # 版92：体力の表示の下に
	if float(b.phase_text["left"]) > 0.0 and str(b.phase_text["text"]) != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.3), str(b.phase_text["text"]), _cc("bossbar_color_awake", "#ffffff"), 1.8)
	# 版84：自分が倒れている時：起こしてもらえる のこり時間・起こしてもらっている進み
	var rs: String = b.revive_sys.my_status() if b.get("revive_sys") != null else ""
	if rs != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.56), rs, Color("#c8ffd8"), 1.2)
	_draw_reticle()
	_draw_dodge_text()
	_draw_damage_numbers(screen)
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
		var ready := not held and not b.actions.busy() and cd_left <= 0.0 and (not is_ult or b.gauge.is_ready())
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
		b.overlay.draw_string_outline(b.font, Vector2(rect.get_center().x - lw * 0.5, ly), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx, 6, Color(0, 0, 0, 0.8))
		b.overlay.draw_string(b.font, Vector2(rect.get_center().x - lw * 0.5, ly), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, lpx, tc)
		var nm := str(b.actions.def(key).get("name", ""))
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


## 必殺技の名前（使った瞬間にはね上がり、少しあとに消える）
func _draw_banner(screen: Vector2) -> void:
	var left := float(b.banner["left"])
	if left <= 0.0:
		return
	var total := maxf(0.01, float(b.banner["total"]))
	var age := total - left
	var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.25)
	var alpha := clampf(left / 0.4, 0.0, 1.0)
	var center := Vector2(screen.x * 0.5, screen.y * (float(b.config["banner_y_portrait"]) if is_portrait(screen) else float(b.config["banner_y"])))
	# 版99：文字の大きさを毎コマ変えると、大きさごとに文字の絵が作られてメモリが増える。
	# 決まった数段の大きさ（text_pop_levels）で描いて、あとは拡大・縮小（draw_set_transform）ではね上がりを出す
	var settled := int(float(b.config["ui_font_size"]) * 2.4)
	var lv := pop_text(settled, pop, text_pop_levels())
	var fs := float(settled) * pop  # 画面での文字の大きさ（前と同じ）
	var text := str(b.banner["text"])
	var w := b.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv["px"])).x * float(lv["k"])
	var back := _cc("banner_back_color")
	back.a *= alpha
	b.overlay.draw_rect(Rect2(Vector2(0.0, center.y - fs * 0.9), Vector2(screen.x, fs * 1.8)), back)
	var col := _cc("banner_color")
	col.a = alpha
	_scaled_string(b.font, center + Vector2(-w * 0.5 + 3.0, fs * 0.35 + 3.0), text, lv, Color(0, 0, 0, alpha))
	_scaled_string(b.font, center + Vector2(-w * 0.5, fs * 0.35), text, lv, col)
	var who := str(b.banner["who"])
	if who != "":
		var fs2 := int(float(b.config["ui_font_size"]) * 0.9)
		var w2 := b.font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		b.overlay.draw_string(b.font, center + Vector2(-w2 * 0.5, fs * 0.95 + fs2 * 0.4), who, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, alpha))


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
func _show_banner(text: String, who: String, seconds: float) -> void:
	b.banner = {"text": text, "who": who, "left": seconds, "total": seconds}
