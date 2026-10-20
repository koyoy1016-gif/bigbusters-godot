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


func _draw_overlay() -> void:
	var screen := b.overlay.size
	var fs := int(b.config["ui_font_size"])
	var text_color := Color(str(b.config["text_color"]))
	var button_text := Color(str(b.config["button_text_color"]))
	var r := float(b.config["stick_radius_px"])
	var c := _stick_center(screen)
	b.overlay.draw_circle(c, r, Color(str(b.config["stick_base_color"])))
	b.overlay.draw_circle(c + b.stick_vec * r, r * 0.4, Color(str(b.config["stick_knob_color"])))

	var br := float(b.config["button_radius_px"])
	var held := b._me_held()
	for id in b.actions.ids():
		var bc := _button_center(str(id), screen)
		var color := str(b.config["button_pressed_color"]) if float(b.button_flash.get(id, 0.0)) > 0.0 else (str(b.config["button_cooldown_color"]) if b.actions.cooldown_left(str(id)) > 0.0 or b.actions.busy() or held else str(b.config["button_color"]))
		var label := str(b.actions.def(str(id)).get("label", id))
		var is_ult := str(id) == "ultimate"
		if is_ult and not held:
			if b.gauge.is_ready():
				var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
				color = str(b.config["button_pressed_color"]) if float(b.button_flash.get(id, 0.0)) > 0.0 else str(b.config["ultimate_ready_color"])
				b.overlay.draw_circle(bc, br + 4.0 + 6.0 * pulse, Color(str(b.config["ultimate_ring_color"])).darkened(0.1))
			elif b.actions.busy():
				color = str(b.config["button_cooldown_color"])
		if held:
			label = "×"  # 版70：つかまれている間は、どのボタンも効かない
		b.overlay.draw_circle(bc, br, Color(color))
		if is_ult and not b.gauge.is_ready():
			b.overlay.draw_arc(bc, br + 6.0, -PI * 0.5, -PI * 0.5 + TAU * b.gauge.ratio(), 40, Color(str(b.config["ultimate_ring_color"])), 7.0)
		_draw_centered(bc, label, button_text)

	b.overlay.draw_string(b.font, Vector2(16, fs * 1.4), (str(b.config["hint_portrait"]) if is_portrait(screen) else str(b.config["hint"])) + "   " + str(b.config["build_label"]) + str(b.config["build_id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var bp: Array = _layout("bossbar_pos", screen)
	var bs: Array = _layout("bossbar_size", screen)
	var bar_rect := Rect2(Vector2(screen.x * bp[0], screen.y * bp[1]), Vector2(screen.x * bs[0], maxf(10.0, screen.y * bs[1])))
	b.overlay.draw_rect(bar_rect, Color(str(b.config["bossbar_back_color"])))
	var frac := b.boss_hp_ratio()
	var second := b.phase.phase != BossPhase.NORMAL
	b.overlay.draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * frac, bar_rect.size.y)), Color(str(b.config["bossbar_color_awake"] if second else b.config["bossbar_color"])))
	# 第1形態の間は、右はしに「第2形態がある」ことを示す小さな印
	if not second:
		b.overlay.draw_rect(Rect2(bar_rect.position + Vector2(bar_rect.size.x - 6.0, 0.0), Vector2(6.0, bar_rect.size.y)), Color(str(b.config["bossbar_color_awake"])))
	var hp_text := str(b.config["boss_hp_label_awake"] if second else b.config["boss_hp_label"]) + "  " + str(ceili(b.boss_hp)) + " / " + str(int(b.phase.max_hp()))
	b.overlay.draw_string(b.font, Vector2(16, fs * 2.9), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var my_text := str(b.config["role_label"]) + "：" + str(b.role().get("name", "")) + (("（" + str(b.role()["character_name"]) + "）") if b.role().has("character_name") else "") + "  " + str(b.config["player_hp_label"]) + "  " + str(ceili(b.my_hp)) + " / " + str(ceili(b.role_value("hp")))
	if b.downed:
		my_text += "  " + str(b.config["down_text"])
	b.overlay.draw_string(b.font, Vector2(16, fs * 4.4), my_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
	var team := build_team_text()
	var next_line := 5.9
	if team != "":
		b.overlay.draw_string(b.font, Vector2(16, fs * next_line), team, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
		next_line += 1.5
	b.overlay.draw_string(b.font, Vector2(16, fs * next_line), b.build_room_text(b.net_state, b.room_code, b.net_active, b.config), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

	if b._start_button_visible():
		var sc := _start_center(screen)
		b.overlay.draw_circle(sc, float(b.config["start_radius_px"]), Color(str(b.config["button_color"])))
		_draw_centered(sc, str(b.config["restart_label"]) if b.round_count > 0 else str(b.config["start_label"]), button_text)
	if b.won or b.lost:
		var result := str(b.config["win_text"]) if b.won else str(b.config["lose_text"])
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.22), result, text_color, 2.0)
		var lines := b.build_result_lines()
		for i in lines.size():
			_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.22 + fs * (2.2 + 1.5 * i)), str(lines[i]), text_color)
	if b.is_enraged() and int(Time.get_ticks_msec() / 400) % 2 == 0:
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.12), str(b.config["enrage_text"]), Color(str(b.config["enrage_color"])), 1.4)
	if float(b.phase_text["left"]) > 0.0 and str(b.phase_text["text"]) != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.3), str(b.phase_text["text"]), Color(str(b.config.get("bossbar_color_awake", "#ffffff"))), 1.8)
	# 版84：自分が倒れている時：起こしてもらえる のこり時間・起こしてもらっている進み
	var rs: String = b.revive_sys.my_status() if b.get("revive_sys") != null else ""
	if rs != "":
		_draw_centered(Vector2(screen.x * 0.5, screen.y * 0.56), rs, Color("#c8ffd8"), 1.2)
	_draw_reticle()
	_draw_damage_numbers(screen)
	_draw_banner(screen)


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
	var fs := int(float(b.config["ui_font_size"]) * 2.4 * pop)
	var text := str(b.banner["text"])
	var w := b.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var back := Color(str(b.config["banner_back_color"]))
	back.a *= alpha
	b.overlay.draw_rect(Rect2(Vector2(0.0, center.y - fs * 0.9), Vector2(screen.x, fs * 1.8)), back)
	var col := Color(str(b.config["banner_color"]))
	col.a = alpha
	b.overlay.draw_string(b.font, center + Vector2(-w * 0.5 + 3.0, fs * 0.35 + 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha))
	b.overlay.draw_string(b.font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
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
## なかまの名前のあとに付ける、キャラの印（共有されていれば「サポート（いやし）」の形。まだなら空）
func _char_tag(slot: String) -> String:
	var def := b.char_def_of(slot)
	if def.is_empty():
		return ""
	return " " + str(def.get("role", "")) + "（" + str(def.get("name", "")) + "）"


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
	for it in dn.items:
		var w: Vector3 = it["world"]
		if b.camera.is_position_behind(w):
			continue
		var kc: Dictionary = dn.kind_cfg(str(it["kind"]))
		var lk: Dictionary = dn.look(it)
		var px := maxi(int(dc.get("min_px", 18)), int(base * float(kc.get("size", 1.0)) * float(lk["scale"])))
		var text := str(it["text"])
		var sz := _dmg_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var p := b.camera.unproject_position(w) + Vector2(float(it["dx"]) + float(lk["shake"]), float(it["dy"]) - float(lk["rise"]))
		p = DamageNumbers.keep_on_screen(p, screen, sz * 0.5, float(dc.get("margin_px", 12.0)))
		var a := float(lk["alpha"])
		# 強い攻撃：出た瞬間の、短い衝撃線
		if float(lk["burst"]) > 0.0:
			var bcol := Color(str(kc.get("burst_color", "#fff3b0")))
			bcol.a = a * float(lk["burst"])
			for i in 8:
				var ang := TAU * i / 8.0 + 0.2
				var dir := Vector2(cos(ang), sin(ang))
				var r0 := sz.x * 0.45 + 6.0
				var r1 := r0 + 26.0 * (1.2 - float(lk["burst"]))
				b.overlay.draw_line(p + dir * r0, p + dir * r1, bcol, 4.0)
		var at := p + Vector2(-sz.x * 0.5, sz.y * 0.32)
		var oc := Color(str(kc.get("outline", "#2b1606")))
		oc.a = a
		var fc := Color(str(kc.get("color", "#fff6c8")))
		fc.a = a
		b.overlay.draw_string_outline(_dmg_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(dc.get("outline_px", 9)), oc)
		b.overlay.draw_string(_dmg_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, fc)


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


## 触れた場所にある、攻撃ボタンの id。なければ ""
func _button_at(pos: Vector2, screen: Vector2) -> String:
	for id in b.actions.ids():
		if pos.distance_to(_button_center(str(id), screen)) <= float(b.config["button_radius_px"]):
			return str(id)
	return ""


func _stick_input(pos: Vector2, screen: Vector2) -> Vector2:
	return StickMath.stick_vector(pos, _stick_center(screen), float(b.config["stick_radius_px"]), float(b.config["stick_dead_zone"]))


## 必殺技の名前を、画面の真ん中に出す。who：使った人の表示（空なら出さない）
func _show_banner(text: String, who: String, seconds: float) -> void:
	b.banner = {"text": text, "who": who, "left": seconds, "total": seconds}
