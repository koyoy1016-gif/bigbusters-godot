extends RefCounted
## 版84：戦いの中の蘇生（決まりは scripts/combat/revive.gd、見た目はここ）。
## 倒れた所に、床の輪（shaders/revive_zone.gdshader：白いふち・うすい中・ななめのしま・緑の進みの弧・白ののこり時間の弧）と、
## 上に「のこり秒」の字。中に味方がいる間は、緑の光の粒がのぼる。起きた時は、緑と白の光の柱。時間が少ないと点めつ。
## 自分も、AIの味方も、起こせる・起こされる。AIの味方は、いちばん近い1人が起こしに行く（よける方が先）。
## 通信中のほかの人とは、まだ共有しない（自分の画面とAIの味方だけ）。

const Revive := preload("res://scripts/combat/revive.gd")
const ZONE_SHADER := preload("res://shaders/revive_zone.gdshader")
const SkillFx := preload("res://scripts/fx/skill_fx.gd")

var b: Node
var logic: RefCounted
var nodes: Dictionary = {}  # slot → {root, mat, label}
var was_down: Dictionary = {}  # slot → 前のコマで倒れていたか
var log: Array = []  # テスト用（down・revive・expire）


func _init(main: Node) -> void:
	b = main
	logic = Revive.new({})


func cfg() -> Dictionary:
	return b.config.get("revive", {})


func reset() -> void:
	logic = Revive.new(cfg())
	for s in nodes:
		var n: Dictionary = nodes[s]
		if is_instance_valid(n["root"]):
			(n["root"] as Node).queue_free()
	nodes = {}
	was_down = {}
	log = []


func zone_radius() -> float:
	return logic.radius(float(b.config.get("player_size", 1.0)))


func _my_pos() -> Vector2:
	return Vector2(b.player.position.x, b.player.position.z)


## 毎コマ（戦いの中）：倒れた人に輪を作り、味方が中にいれば進め、4秒で起こす
func update(delta: float) -> void:
	if logic.cfg.is_empty():
		logic.cfg = cfg()
	if not b.round_active():
		return
	var me := str(b._my_slot())
	var alive := {}
	var downs := {}
	if b.downed:
		downs[me] = _my_pos()
	else:
		alive[me] = _my_pos()
	for slot in b.ai_allies:
		var a: Dictionary = b.ai_allies[slot]
		if bool(a["downed"]):
			downs[str(slot)] = a["pos"]
		else:
			alive[str(slot)] = a["pos"]
	# 倒れた瞬間に、輪を作る
	for s in downs:
		if not bool(was_down.get(s, false)):
			if logic.on_down(s, downs[s]):
				log.append("down:" + s)
				_make_zone(s, downs[s])
				b.audio.play("down")  # 版85：倒れた音
	# ほかの方法で起きた人の輪は消す
	for s in logic.zones.keys():
		if not downs.has(s):
			logic.clear(s)
			_remove_zone(s, false)
	was_down = {}
	for s in downs:
		was_down[s] = true
	var res: Dictionary = logic.update(delta, alive, zone_radius())
	for s in res["revived"]:
		_revive(str(s))
	for s in res["expired"]:
		log.append("expire:" + str(s))
		_remove_zone(str(s), false)
	_update_visuals(delta)


## AIの味方に渡す：{AIの枠: 起こしに行く輪の位置}
func ai_targets() -> Dictionary:
	var pos := {}
	for slot in b.ai_allies:
		var a: Dictionary = b.ai_allies[slot]
		if not bool(a["downed"]) and not bool(a.get("held", false)):
			pos[str(slot)] = a["pos"]
	return Revive.assign(logic.zones, pos)


func _revive(slot: String) -> void:
	var r: float = logic.hp_ratio()
	if slot == str(b._my_slot()):
		if not b.downed:
			return
		b.downed = false
		b._set_my_hp(maxf(1.0, b.role_value("hp") * r))
		b.kb_guard_left = float(cfg().get("guard_sec", 1.5))
		if b.char_view != null:
			b.char_view.play_action("idle")
	elif b.ai_allies.has(slot):
		var a: Dictionary = b.ai_allies[slot]
		if not bool(a["downed"]):
			return
		a["downed"] = false
		a["hp"] = maxf(1.0, float(a["max_hp"]) * r)
		a["kb_guard"] = float(cfg().get("guard_sec", 1.5))
	was_down.erase(slot)
	log.append("revive:" + slot)
	_remove_zone(slot, true)
	b.audio.play("revive")  # 版85：起きた音（上がるきらきら）


# ---------------------------------------------------------------- 見た目

func _make_zone(slot: String, pos: Vector2) -> void:
	if not b.is_inside_tree():
		return
	var v := _zone_visual()
	var root: Node3D = v["root"]
	root.name = "ReviveZone_" + slot
	root.position = Vector3(pos.x, b.ground_y + 0.04, pos.y)
	b.add_child(root)
	# 出る時：少し大きく出て、すっと合う
	root.scale = Vector3.ONE * 1.4
	root.create_tween().tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	nodes[slot] = {"root": root, "mat": v["mat"], "label": v["label"], "rise_t": 0.0}


## 蘇生の輪の見た目（輪の面と、上の数字）。{root, mat, label}
func _zone_visual() -> Dictionary:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var r := zone_radius()
	pm.size = Vector2(r * 2.0, r * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = ZONE_SHADER
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var label := Label3D.new()
	label.font = b.font
	label.font_size = 72
	label.outline_size = 16
	label.pixel_size = 0.018
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 4.2, 0)
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0.05, 0.1, 0.08, 0.9)
	root.add_child(label)
	return {"root": root, "mat": mat, "label": label}


## 版108：はじめて倒れた時の準備（輪のシェーダー・数字の描き方）を、戦いの始まりにすませるための見た目。
## 数字は地面を通して見える（深さを無視）ので、色をすきとおらせる（描くけれど、見えない）
func prewarm_source() -> Node3D:
	var v := _zone_visual()
	var label: Label3D = v["label"]
	label.text = "0123456789"
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)
	var root: Node3D = v["root"]
	root.name = "WarmReviveZone"
	root.set_meta("warm_temp", true)
	return root


func _remove_zone(slot: String, revived: bool) -> void:
	var n: Dictionary = nodes.get(slot, {})
	nodes.erase(slot)
	if n.is_empty() or not is_instance_valid(n["root"]):
		return
	var root: Node3D = n["root"]
	if revived and b.is_inside_tree():
		var at := root.position
		b.skills.spawn_at({"kind": "pillar", "color": "#bfffd8", "radius": 1.2, "tall": 9.0, "life": 0.7}, at, at)
		b.skills.spawn_at({"kind": "ring", "color": "#7dffa8", "radius": zone_radius() * 1.8, "life": 0.6}, at, at)
		b.skills.spawn_at({"kind": "rise", "color": "#d8ffe6", "life": 1.2}, at, at)
	root.queue_free()


func _update_visuals(delta: float) -> void:
	for s in nodes:
		var n: Dictionary = nodes[s]
		var z: Dictionary = logic.zones.get(s, {})
		if z.is_empty() or not is_instance_valid(n["root"]):
			continue
		var mat: ShaderMaterial = n["mat"]
		var left: float = float(z["left"])
		mat.set_shader_parameter("progress", clampf(float(z["progress"]) / logic.hold_sec(), 0.0, 1.0))
		mat.set_shader_parameter("time_left", clampf(left / logic.window_sec(), 0.0, 1.0))
		mat.set_shader_parameter("blink", 1.0 if left < float(cfg().get("blink_sec", 5.0)) else 0.0)
		var label: Label3D = n["label"]
		if str(z["by"]) != "":
			label.text = str(b.config.get("revive_progress_text", "%.1f")) % maxf(0.0, logic.hold_sec() - float(z["progress"]))
			label.modulate = Color("#9dffb8")
			n["rise_t"] = float(n["rise_t"]) + delta
			if float(n["rise_t"]) >= 0.35:
				n["rise_t"] = 0.0
				var at: Vector3 = (n["root"] as Node3D).position
				b.skills.spawn_at({"kind": "rise", "color": "#9dffb8", "life": 0.8}, at, at)
		else:
			label.text = str(b.config.get("revive_left_text", "%d")) % ceili(left)
			label.modulate = Color(1, 0.55, 0.5) if left < float(cfg().get("blink_sec", 5.0)) else Color.WHITE


## 自分が倒れている時の、画面のまんなかの字（battle_hud.gd が描く）。なければ ""
func my_status() -> String:
	var me := str(b._my_slot())
	var z: Dictionary = logic.zones.get(me, {})
	if not b.downed:
		return ""
	if z.is_empty():
		return str(b.config.get("revive_gone_text", "")) if logic.expired.has(me) else ""
	if str(z["by"]) != "":
		return str(b.config.get("revive_me_progress", "")) % maxf(0.0, logic.hold_sec() - float(z["progress"]))
	return str(b.config.get("revive_me_wait", "")) % ceili(float(z["left"]))
