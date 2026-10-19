extends RefCounted
## 版78：キャラごとの攻撃の「効果」と「見た目」をまとめる部品（プレイヤーとAIの味方の両方）。
## 効果（data/char_actions.json の effects）：
##   speed_mode：しばらく、動く速さと攻撃の速さ（待ち時間の減り）が mult 倍（スピードファイター）
##   dome     ：しばらく、敵も味方も「攻撃力 attack_mult 倍」「受けるダメージ taken_mult 倍」（アーマーの全体防御強化）
##   heal     ：まわり radius の味方の体力を amount 回復（乱数・クリティカルなし）
##   revive   ：まわり radius の倒れた味方を、体力 hp_ratio で起こす
##   time_stop：ボスを sec 秒止める（続けて使うと、ボスの耐性で短くなる）。通信中は使わない（画面ごとに、ずれるため）
##   summon   ：ぬいぐるみなどを count 体呼ぶ。ボスへ歩き、interval 秒ごとに multiplier 倍のダメージ（本体の攻撃力には足さない）
## 状態の変数は、まとめ役（stick_prototype.gd）の skill_* にある。

const Damage := preload("res://scripts/combat/damage.gd")
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
const SkillHits := preload("res://scripts/combat/skill_hits.gd")
const BodyBuilder := preload("res://scripts/characters/body_builder.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）


func _init(main: StickPrototype) -> void:
	b = main


func reset() -> void:
	for f in b.skill_fx:
		if is_instance_valid(f["node"]):
			(f["node"] as Node).queue_free()
	for u in b.skill_summons:
		if is_instance_valid(u.get("node")):
			(u["node"] as Node).queue_free()
	b.skill_fx = []
	b.skill_summons = []
	b.skill_speed = {}
	b.skill_dome_left = 0.0
	b.skill_dome_slot = ""
	b.skill_dome_cfg = {}
	b.skill_time_stop_left = 0.0
	b.skill_time_stop_resist_until = -999.0
	b.skill_log = []


## 枠 slot の動く速さ・攻撃の速さの倍率（超高速モード）
func speed_mult(slot: String) -> float:
	var s: Dictionary = b.skill_speed.get(slot, {})
	return float(s.get("mult", 1.0)) if float(s.get("left", 0.0)) > 0.0 else 1.0


## ボスに与えるダメージの倍率（ドームの間：味方の攻撃力↓ × ボスの受けるダメージ↓）
func dealt_mult() -> float:
	if b.skill_dome_left <= 0.0:
		return 1.0
	return float(b.skill_dome_cfg.get("attack_mult", 0.5)) * float(b.skill_dome_cfg.get("taken_mult", 0.5))


## 味方が受けるダメージの倍率（ドームの間：ボスの攻撃力↓ × 味方の受けるダメージ↓）
func taken_mult() -> float:
	return dealt_mult()


func boss_frozen() -> bool:
	return b.skill_time_stop_left > 0.0


## 枠の、床の上の位置
func pos_of(slot: String) -> Vector2:
	if slot == b._my_slot() or slot == "":
		return Vector2(b.player.position.x, b.player.position.z)
	if b.ai_allies.has(slot):
		return b.ai_allies[slot]["pos"]
	return Vector2(b.player.position.x, b.player.position.z)


## 効果を起こす。slot：使った人。ap：使った人の攻撃力（呼び出しのダメージに使う）
func apply_effect(slot: String, spec: Dictionary, aim: Vector2, ap: float) -> void:
	var kind := str(spec.get("type", ""))
	var origin := pos_of(slot)
	b.skill_log.append(kind)
	match kind:
		"speed_mode":
			b.skill_speed[slot] = {"left": float(spec.get("sec", 6.0)), "mult": float(spec.get("mult", 1.75))}
			spawn_fx({"kind": "aura", "color": str(spec.get("color", "#5fd6ff")), "radius": 1.1, "life": float(spec.get("sec", 6.0)), "alpha": 0.22},
				slot, aim, Vector3.INF, slot)
		"dome":
			b.skill_dome_left = float(spec.get("sec", 6.0))
			b.skill_dome_slot = slot
			b.skill_dome_cfg = spec
			spawn_fx({"kind": "dome", "color": str(spec.get("color", "#7fb4ff")), "radius": float(spec.get("radius", 4.5)),
				"life": float(spec.get("sec", 6.0)), "alpha": 0.3}, slot, aim, Vector3.INF, slot)
		"heal":
			var r := float(spec.get("radius", 6.0))
			var amt := float(spec.get("amount", 40.0))
			if origin.distance_to(pos_of(b._my_slot())) <= r and not b.downed:
				b._set_my_hp(minf(b.role_value("hp"), b.my_hp + amt))
			for s in b.ai_allies:
				var a: Dictionary = b.ai_allies[s]
				if not bool(a["downed"]) and origin.distance_to(a["pos"]) <= r:
					a["hp"] = minf(float(a["max_hp"]), float(a["hp"]) + amt)
			spawn_fx({"kind": "ring", "color": str(spec.get("color", "#7dffa8")), "radius": r, "life": 0.6}, slot, aim)
		"revive":
			var r2 := float(spec.get("radius", 8.0))
			var ratio := float(spec.get("hp_ratio", 0.5))
			if b.downed and origin.distance_to(pos_of(b._my_slot())) <= r2:
				b.downed = false
				b._set_my_hp(b.role_value("hp") * ratio)
			for s in b.ai_allies:
				var a2: Dictionary = b.ai_allies[s]
				if bool(a2["downed"]) and origin.distance_to(a2["pos"]) <= r2:
					a2["downed"] = false
					a2["hp"] = float(a2["max_hp"]) * ratio
			spawn_fx({"kind": "pillar", "color": str(spec.get("color", "#fff2a8")), "radius": 1.4, "tall": 9.0, "life": 1.0}, slot, aim)
		"time_stop":
			if b.net_active:
				return
			var sec := float(spec.get("sec", 3.0))
			if b._round_t() < b.skill_time_stop_resist_until:
				sec *= float(spec.get("resist_mult", 0.5))
			b.skill_time_stop_left = sec
			b.skill_time_stop_resist_until = b._round_t() + sec + float(spec.get("resist_sec", 20.0))
			spawn_fx({"kind": "clock", "color": str(spec.get("color", "#b9a8ff")), "radius": float(b.config["boss_size"]) * 0.75, "life": sec, "alpha": 0.25},
				slot, aim, Vector3(b.boss.position.x, b.ground_y, b.boss.position.z), "@boss")
		"summon":
			var n := int(spec.get("count", 5))
			var maxn := int(spec.get("max_active", n))
			# 同じ人の呼び出しは、同時に maxn 体まで（古い物から消える）
			var mine: Array = b.skill_summons.filter(func(u: Dictionary) -> bool: return str(u["owner"]) == slot)
			while mine.size() + n > maxn and not mine.is_empty():
				var old: Dictionary = mine.pop_front()
				old["life"] = 0.0
			for i in n:
				var ang := TAU * float(i) / float(maxi(n, 1)) + 0.4
				var p := origin + Vector2(cos(ang), sin(ang)) * float(spec.get("spread", 1.2))
				var u := {"owner": slot, "pos": p, "life": float(spec.get("sec", 10.0)), "next": float(spec.get("first", 0.4)) + 0.1 * i,
					"interval": float(spec.get("interval", 1.0)), "mult": float(spec.get("multiplier", 0.6)), "ap": ap,
					"speed": float(spec.get("speed", 5.0)), "reach": float(spec.get("reach", 1.0)), "unit": str(spec.get("unit", "plush")),
					"hop": float(i) * 0.37, "node": null}
				u["node"] = _make_unit(u, i)
				b.skill_summons.append(u)


## 見た目を出す。at：出す所（INF なら使った人の足もと）。follow：ついていく枠（"@boss" はボス）
func spawn_fx(spec: Dictionary, slot: String, aim: Vector2, at: Vector3 = Vector3.INF, follow: String = "") -> void:
	if not b.is_inside_tree():
		b.skill_fx_log.append(str(spec.get("kind", "")))
		return
	var o2 := pos_of(slot)
	var from := Vector3(o2.x, b.ground_y, o2.y)
	var to := at if at != Vector3.INF else from
	var h := float(spec.get("height", 1.3))
	var node := SkillFx.make(spec, from, to, h)
	b.add_child(node)
	b.skill_fx.append({"node": node, "follow": follow})
	b.skill_fx_log.append(str(spec.get("kind", "")))


## 攻撃の動きの見た目（fx_events）：ねらう所を決めて出す
func action_fx(slot: String, spec: Dictionary, aim: Vector2) -> void:
	var o := pos_of(slot)
	var bxz := Vector2(b.boss.position.x, b.boss.position.z)
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	var side := SkillHits.side_vec(n) * float(spec.get("side", 0.0))
	var target: Vector2
	match str(spec.get("at", "front")):
		"boss":
			target = bxz
		"self":
			target = o
		"hit":
			target = SkillHits.center(spec.get("hit", {}), o, n, bxz)
		_:
			target = o + side + n * float(spec.get("dist", spec.get("length", 3.0)))
	var s := spec.duplicate()
	if str(spec.get("kind", "")) in ["beam", "slash"]:
		var e := SkillHits.beam_ends({"length": float(spec.get("length", 10.0)), "side": float(spec.get("side", 0.0))}, o, n)
		target = e[1]
		var o3 := Vector3((e[0] as Vector2).x, b.ground_y, (e[0] as Vector2).y)
		if not b.is_inside_tree():
			b.skill_fx_log.append("beam")
			return
		var node := SkillFx.make(s, o3, Vector3(target.x, b.ground_y, target.y), float(spec.get("height", 1.3)))
		b.add_child(node)
		b.skill_fx.append({"node": node, "follow": ""})
		b.skill_fx_log.append("beam")
		return
	spawn_fx(s, slot, aim, Vector3(target.x, b.ground_y, target.y), slot if str(spec.get("kind", "")) == "aura" else "")


## 毎コマ：時間、呼び出し、見た目
func update(delta: float) -> void:
	for slot in b.skill_speed.keys():
		var s: Dictionary = b.skill_speed[slot]
		s["left"] = maxf(0.0, float(s["left"]) - delta)
	b.skill_dome_left = maxf(0.0, b.skill_dome_left - delta)
	b.actions.cd_rate = speed_mult(b._my_slot())
	for slot in b.ai_allies:
		var a: Dictionary = b.ai_allies[slot]
		a["speed_mult"] = speed_mult(str(slot))
		var acts: Variant = a["actions"]
		acts.cd_rate = a["speed_mult"]
	_update_summons(delta)
	var keep: Array = []
	for f in b.skill_fx:
		var node: Node3D = f["node"]
		if not is_instance_valid(node):
			continue
		var follow := Vector3.INF
		var fs := str(f["follow"])
		if fs == "@boss":
			follow = Vector3(b.boss.position.x, b.ground_y, b.boss.position.z)
		elif fs != "":
			var p := pos_of(fs)
			follow = Vector3(p.x, b.ground_y, p.y)
		if SkillFx.tick(node, delta, follow):
			keep.append(f)
		else:
			node.queue_free()
	b.skill_fx = keep


func _update_summons(delta: float) -> void:
	var bxz := Vector2(b.boss.position.x, b.boss.position.z)
	var br := float(b.config["boss_size"]) * 0.5
	var keep: Array = []
	var dealt_mine := 0.0
	for u in b.skill_summons:
		u["life"] = float(u["life"]) - delta
		if float(u["life"]) <= 0.0 or not b.round_active():
			if is_instance_valid(u.get("node")):
				(u["node"] as Node).queue_free()
			continue
		var p: Vector2 = u["pos"]
		var to := bxz - p
		var stand := br + float(u["reach"]) * 0.8
		if to.length() > stand:
			p += to.normalized() * minf(float(u["speed"]) * delta, to.length() - stand)
			u["pos"] = p
		u["next"] = float(u["next"]) - delta
		if float(u["next"]) <= 0.0 and to.length() <= br + float(u["reach"]) + 0.3 and b.boss.visible and not b.phase.invulnerable():
			u["next"] = float(u["interval"])
			var dmg := Damage.damage_amount(float(u["ap"]), float(b.config["attack_multiplier"]) * float(u["mult"]) * dealt_mult())
			var owner := str(u["owner"])
			if owner == b._my_slot():
				b.my_hits += dmg
				dealt_mine += dmg
			elif b.ai_hits.has(owner):
				b.ai_hits[owner] = float(b.ai_hits[owner]) + dmg
				(b.ai_allies[owner] as Dictionary)["hits"] = float(b.ai_allies[owner]["hits"]) + dmg
			b._show_damage(dmg, "summon", p)
			u["bump"] = 0.2
		u["bump"] = maxf(0.0, float(u.get("bump", 0.0)) - delta)
		var node: Node3D = u.get("node")
		if is_instance_valid(node):
			u["hop"] = float(u["hop"]) + delta
			node.position = Vector3(p.x, b.ground_y + absf(sin(float(u["hop"]) * 9.0)) * 0.18, p.y)
			if to.length() > 0.01:
				node.rotation.y = atan2(to.x, to.y)
			var lean := float(u.get("bump", 0.0)) * 2.5
			node.rotation.x = lean
		keep.append(u)
	b.skill_summons = keep
	if dealt_mine > 0.0:
		b._recompute_boss_hp()
		if b.net_active:
			b.bridge.send_hits(b.my_hits)


## 呼び出した物の見た目（data/character_looks.json の units。部品を、そのまま並べた小さな形）
func _make_unit(u: Dictionary, i: int) -> Node3D:
	if not b.is_inside_tree():
		return null
	var looks := BodyBuilder.load_looks()
	var units: Dictionary = (looks.get("summoner", {}) as Dictionary).get("units", {})
	var kinds: Array = (units.get(str(u["unit"]), {}) as Dictionary).get("variants", [])
	var root := Node3D.new()
	root.name = "Summon"
	if kinds.is_empty():
		return root
	var parts: Array = kinds[i % kinds.size()]
	for part in parts:
		var mesh := BodyBuilder.make_part_mesh(part)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = BodyBuilder.part_transform(part)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.scale = Vector3.ONE * float((units.get(str(u["unit"]), {}) as Dictionary).get("scale", 1.0))
	root.add_to_group("styled")
	b.add_child(root)
	return root
