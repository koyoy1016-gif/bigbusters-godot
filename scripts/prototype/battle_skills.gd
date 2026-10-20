extends RefCounted
## 版78・79：キャラごとの攻撃の「効果」「飛ぶ物」「見た目」をまとめる部品（プレイヤーとAIの味方の両方）。
## 飛ぶ物（projectiles.gd）：銃弾・魔法の玉・爆弾・矢などは、発射口（つえの先・砲口・手）から出て飛び、当たった時にダメージを出す。
## 効果（data/char_actions.json の effects）：
##   speed_mode：しばらく、動く速さと攻撃の速さが mult 倍（スピードファイター）
##   vanish    ：消える（青い残像・粒）。消えている間は、ボスの攻撃に当たらず、速く動ける。攻撃すると現れ、最初の一撃が bonus 倍
##   dome      ：青い半透明の守りの膜（アーマー）。膜の中の味方は、受けるダメージ taken 倍。膜の中から撃つと、攻撃力 attack 倍
##               （もとの「敵を含めた全員の攻撃力50%低下・被ダメージ50%軽減」を、膜の見える範囲だけにした）
##   heal_dome ：緑の半透明の回復の膜（エンジェル）。中の味方が、1秒に per_sec 回復。倒れた味方は revive_after 秒で起きる
##   heal / heal_shot：まわりの味方を回復／いちばん減っている味方（またはタップした味方）へ、回復の光を飛ばす
##   revive    ：まわりの倒れた味方を起こす
##   time_stop ：ボスを sec 秒止める（続けると耐性で短くなる）。通信中は使わない
##   summon    ：呼び出す（unit：plush＝ぬいぐるみ、soldier＝小さい兵隊）。敵へ歩き、近づいて攻撃・小さな弾を撃つ。時間で退場
##   aura      ：必殺技の色の光で体を包む（剣士・アタッカー＝黄、ファイター＝赤、スピード・シールド＝青、ヒーラー＝緑）
## 状態の変数は、まとめ役（stick_prototype.gd）の skill_* にある。

const Damage := preload("res://scripts/combat/damage.gd")
const SkillFx := preload("res://scripts/fx/skill_fx.gd")
const SkillHits := preload("res://scripts/combat/skill_hits.gd")
const Projectiles := preload("res://scripts/combat/projectiles.gd")
const BodyBuilder := preload("res://scripts/characters/body_builder.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const CharacterView := preload("res://scripts/characters/character_view.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")

var b: StickPrototype  ## まとめ役（stick_prototype.gd）


func _init(main: StickPrototype) -> void:
	b = main


func reset() -> void:
	for f in b.skill_fx:
		if is_instance_valid(f["node"]):
			(f["node"] as Node).queue_free()
	for list in [b.skill_summons, b.skill_projs, b.skill_gimmicks, b.skill_ghosts]:
		for u in list:
			if u.get("node") != null and is_instance_valid(u.get("node")):
				(u["node"] as Node).queue_free()
	b.skill_fx = []
	b.skill_summons = []
	b.skill_projs = []
	b.skill_gimmicks = []
	b.skill_ghosts = []
	b.skill_speed = {}
	b.skill_vanish = {}
	b.skill_domes = []
	b.skill_time_stop_left = 0.0
	b.skill_time_stop_resist_until = -999.0
	b.skill_log = []
	_show_slot(b._my_slot(), true)


# ---------------------------------------------------------------- 状態

## 枠 slot の動く速さ・攻撃の速さの倍率（超高速モード・消えている間）
func speed_mult(slot: String) -> float:
	var m := 1.0
	var s: Dictionary = b.skill_speed.get(slot, {})
	if float(s.get("left", 0.0)) > 0.0:
		m *= float(s.get("mult", 1.0))
	var v: Dictionary = b.skill_vanish.get(slot, {})
	if float(v.get("left", 0.0)) > 0.0:
		m *= float(v.get("speed", 1.0))
	return m


func is_vanished(slot: String) -> bool:
	return float((b.skill_vanish.get(slot, {}) as Dictionary).get("left", 0.0)) > 0.0


## 守りの膜（dome）の中か。中なら、その膜の設定。なければ {}
func dome_at(p: Vector2, kind: String = "dome") -> Dictionary:
	for d in b.skill_domes:
		if str(d["kind"]) == kind and float(d["left"]) > 0.0 and p.distance_to(d["pos"]) <= float(d["radius"]):
			return d
	return {}


## slot の攻撃の倍率（守りの膜の中から撃つと下がる。ボスも膜の中なら、さらに下がる）。slot が "" なら、いまの自分
func dealt_mult(slot: String = "") -> float:
	var who := slot if slot != "" else b._my_slot()
	var d := dome_at(pos_of(who))
	if d.is_empty():
		return 1.0
	var m := float(d.get("attack_mult", 0.5))
	var bxz := Vector2(b.boss.position.x, b.boss.position.z)
	if bxz.distance_to(d["pos"]) <= float(d["radius"]) + float(b.config["boss_size"]) * 0.5:
		m *= float(d.get("taken_mult", 0.5))
	return m


## slot が受けるダメージの倍率（守りの膜の中なら、ボスの攻撃力↓ × 受けるダメージ↓）
func taken_mult(slot: String = "") -> float:
	var who := slot if slot != "" else b._my_slot()
	var d := dome_at(pos_of(who))
	if d.is_empty():
		return 1.0
	return float(d.get("attack_mult", 0.5)) * float(d.get("taken_mult", 0.5))


func boss_frozen() -> bool:
	return b.skill_time_stop_left > 0.0


## 枠の、床の上の位置
func pos_of(slot: String) -> Vector2:
	if slot == b._my_slot() or slot == "":
		return Vector2(b.player.position.x, b.player.position.z)
	if b.ai_allies.has(slot):
		return b.ai_allies[slot]["pos"]
	return Vector2(b.player.position.x, b.player.position.z)


func pos3_of(slot: String) -> Vector3:
	var p := pos_of(slot)
	var h := 0.0
	if b.ai_allies.has(slot) and slot != b._my_slot():
		h = float(b.ai_allies[slot].get("height", 0.0))
	elif slot == b._my_slot() or slot == "":
		h = b.player.position.y - b.ground_y
	return Vector3(p.x, b.ground_y + h, p.y)


func view_of(slot: String) -> Node3D:
	if slot == b._my_slot() or slot == "":
		return b.char_view
	return b.other_views.get(slot, null)


func aim_of(slot: String) -> Vector2:
	if slot == b._my_slot() or slot == "":
		return b.actions.aim
	if b.ai_allies.has(slot):
		return (b.ai_allies[slot]["actions"] as Actions).aim
	return Vector2(0, -1)


## 発射口の世界の位置。わからなければ、足もとから手の高さ・少し前
func socket(slot: String, name: String, aim: Vector2) -> Vector3:
	var v := view_of(slot)
	if v != null and v.has_method("socket_position") and name != "":
		var p: Vector3 = v.socket_position(name)
		if p != Vector3.INF and p.y > -1.0:
			return p
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	return pos3_of(slot) + Vector3(n.x * 0.5, 1.3, n.y * 0.5)


## ねらう敵（円柱）。自分はターゲットロック（なければボス）、AIはボス
func target_of(slot: String) -> Dictionary:
	if slot == b._my_slot() or slot == "":
		return b.target_info()
	return b.boss_info()


# ---------------------------------------------------------------- ダメージ

## 敵にダメージを与える（飛ぶ物が当たった時・呼び出した物の攻撃）。tgt：target_of の形。at：当たった所
func deal(slot: String, dmg: float, action: String, at: Vector3, tgt: Dictionary, spark: Dictionary = {}) -> float:
	if tgt.is_empty():
		return 0.0
	_spark(slot, at, spark)
	if str(tgt.get("kind", "boss")) == "sub":
		var i := int(tgt.get("index", -1))
		if i >= 0 and b.crowd_state.is_alive(i):
			b.crowd_state.hit(i, dmg, b._round_t(), float(b.config["sub_enemy_respawn_sec"]))
		return dmg
	if not b.boss.visible or b.phase.invulnerable() or dmg <= 0.0:
		return 0.0
	b.hit_flash = float(b.config["hit_flash_sec"])
	if slot == b._my_slot() or slot == "":
		b._damage_boss(dmg)
		b.rage.add_hit(b._round_t(), b._dist_to_boss_surface(pos_of(slot)))
	elif b.ai_allies.has(slot):
		var a: Dictionary = b.ai_allies[slot]
		a["hits"] = float(a["hits"]) + dmg
		b.ai_hits[slot] = float(b.ai_hits.get(slot, 0.0)) + dmg
		(a["gauge"]).charge(dmg * float((a["stats"] as Dictionary).get("gauge_rate", 1.0)))
		b.rage.add_hit(b._round_t(), b._dist_to_boss_surface(a["pos"]))
		b._recompute_boss_hp()
	b._show_damage(dmg, action, Vector2(at.x, at.z) + (Vector2(at.x, at.z) - Vector2(b.boss.position.x, b.boss.position.z)).normalized() * 3.0)
	return dmg


## キャラの役の色（火花・オーラ）。data/char_actions.json の _meta、なければ黄
func role_color(slot: String, key: String = "spark") -> String:
	var cid := ""
	if slot == b._my_slot() or slot == "":
		cid = b.my_char_id()
	elif b.ai_allies.has(slot):
		cid = str(b.ai_allies[slot].get("id", ""))
	var meta: Dictionary = Actions.meta_for(cid)
	return str(meta.get(key, "#ffd24a"))


## 強い攻撃が当たった手ごたえ（自分の技だけ）：一瞬止める・画面のゆれ・カメラの寄り。hit の impact：[秒, ゆれ, 寄り]
func _impact(slot: String, hspec: Dictionary) -> void:
	if not hspec.has("impact") or (slot != b._my_slot() and slot != ""):
		return
	b._impact(hspec["impact"])


func _spark(slot: String, at: Vector3, spec: Dictionary) -> void:
	var s := spec.duplicate()
	if not s.has("color"):
		s["color"] = role_color(slot)
	s["kind"] = "spark"
	if not s.has("life"):
		s["life"] = 0.35
	spawn_at(s, at, at)


# ---------------------------------------------------------------- 飛ぶ物

## 飛ぶ物を撃つ。hspec：hits の1つ（proj を持つ）。dmg：当たった時のダメージ（撃つ時に決める）
func fire(slot: String, hspec: Dictionary, dmg: float, aim: Vector2, action: String) -> void:
	var ps: Dictionary = hspec.get("proj", {})
	var tgt := target_of(slot)
	var sky := str(ps.get("from", "")) == "@sky"
	var from := socket(slot, "" if sky else str(ps.get("from", "")), aim)
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	# 横へずらす（3つ投げる・2本撃つ）
	var side := SkillHits.side_vec(n) * float(hspec.get("side", 0.0))
	var target: Vector3
	if not tgt.is_empty() and Vector2(float(tgt["x"]), float(tgt["z"])).distance_to(pos_of(slot)) <= float(ps.get("range", 25.0)) + float(tgt["r"]):
		var c := Vector3(float(tgt["x"]), float(tgt.get("y0", 0.0)) + float(tgt["h"]) * float(ps.get("aim_h", 0.45)), float(tgt["z"]))
		if str(ps.get("mode", "")) == "arc":
			# 敵の、こちら側の足もとに落とす
			var d2 := Vector2(c.x, c.z) - pos_of(slot)
			var land := Vector2(c.x, c.z) - d2.normalized() * float(tgt["r"]) * float(ps.get("land_in", 0.6))
			c = Vector3(land.x, b.ground_y, land.y)
		target = c + Vector3(side.x, 0, side.y)
	else:
		var flat := pos_of(slot) + n * float(ps.get("range", 12.0)) * (0.6 if str(ps.get("mode", "")) == "arc" else 1.0)
		target = Vector3(flat.x, b.ground_y + (0.0 if str(ps.get("mode", "")) == "arc" else 1.3), flat.y) + Vector3(side.x, 0, side.y)
	if str(ps.get("land_at", "")) == "self":
		# 足もとに置く（ボンバーの置きプレゼント）：少し前に落とす
		var me := pos_of(slot) + n * 0.7
		target = Vector3(me.x, b.ground_y, me.y)
	if sky:
		# 空から落とす（魔法使いのメテオ）：ねらう所の、うしろ上の高い所から
		from = target + Vector3(-n.x * 5.0, float(ps.get("sky_height", 16.0)), -n.y * 5.0)
	ps = ps.duplicate()
	ps["ground"] = b.ground_y
	var p := Projectiles.make(ps, from, target, slot, dmg, action)
	p["hit"] = hspec
	p["tgt_kind"] = str(tgt.get("kind", "boss"))
	p["tgt_index"] = int(tgt.get("index", -1))
	p["node"] = _proj_node(ps, from)
	b.skill_projs.append(p)
	b.skill_log.append("fire")
	if ps.has("muzzle") and not sky:
		var mz: Dictionary = (ps["muzzle"] as Dictionary).duplicate()
		mz["kind"] = "prop"
		_spawn_oriented(mz, from, from + Vector3(n.x, 0, n.y))


## 回復の光を、味方へ飛ばす（いちばん減っている味方。タップで味方を選んでいれば、その味方）
func heal_shot(slot: String, spec: Dictionary) -> void:
	var to := _heal_target(slot)
	var from := socket(slot, str(spec.get("from", "")), aim_of(slot))
	var ps := {"mode": "homing", "speed": float(spec.get("speed", 14.0)), "turn_deg": 360.0, "radius": 0.4, "range": 40.0, "life": 3.0,
		"prop": str(spec.get("prop", "")), "color": "#7dffa8", "size": 0.25, "aim_h": 0.5}
	var tp := pos3_of(to) + Vector3(0, 1.0, 0)
	var p := Projectiles.make(ps, from, tp, slot, 0.0, "heal")
	p["heal"] = float(spec.get("amount", 40.0))
	p["heal_to"] = to
	p["node"] = _proj_node(ps, from)
	b.skill_projs.append(p)
	b.skill_log.append("heal_shot")


func _heal_target(slot: String) -> String:
	if b.ally_lock != "" and (b.ally_lock == b._my_slot() or b.ai_allies.has(b.ally_lock)):
		return b.ally_lock
	var best := slot
	var best_r := 2.0
	var cands: Array = [b._my_slot()]
	cands.append_array(b.ai_allies.keys())
	for s in cands:
		var r := _hp_ratio(str(s))
		if r < best_r and r >= 0.0:
			best_r = r
			best = str(s)
	return best


func _hp_ratio(slot: String) -> float:
	if slot == b._my_slot():
		return -1.0 if b.downed else b.my_hp / maxf(b.role_value("hp"), 1.0)
	var a: Dictionary = b.ai_allies.get(slot, {})
	if a.is_empty() or bool(a.get("downed", false)):
		return -1.0
	return float(a["hp"]) / maxf(float(a["max_hp"]), 1.0)


func _heal(slot: String, amount: float) -> void:
	if slot == b._my_slot():
		if not b.downed:
			b._set_my_hp(minf(b.role_value("hp"), b.my_hp + amount))
	elif b.ai_allies.has(slot):
		var a: Dictionary = b.ai_allies[slot]
		if not bool(a["downed"]):
			a["hp"] = minf(float(a["max_hp"]), float(a["hp"]) + amount)


func _proj_node(ps: Dictionary, from: Vector3) -> Node3D:
	if not b.is_inside_tree():
		return null
	var spec := {"kind": "orb", "prop": str(ps.get("prop", "")), "scale": float(ps.get("scale", 1.0)), "color": str(ps.get("color", "#ffffff")),
		"radius": float(ps.get("size", 0.18)), "life": 99.0}
	var n := SkillFx.make(spec, from, from, 0.0)
	n.position = from
	b.add_child(n)
	return n


func _update_projs(delta: float) -> void:
	var keep: Array = []
	for p in b.skill_projs:
		var tgt: Dictionary
		if p.has("heal_to"):
			var hp3 := pos3_of(str(p["heal_to"]))
			tgt = {"x": hp3.x, "z": hp3.z, "r": 0.5, "h": 2.0, "y0": hp3.y}
		else:
			tgt = b.boss_info() if str(p.get("tgt_kind", "boss")) == "boss" else b.sub_info(int(p.get("tgt_index", -1)))
		var res := Projectiles.step(p, delta, tgt)
		var node: Node3D = p.get("node")
		if node != null and is_instance_valid(node):
			node.position = p["pos"]
			var v: Vector3 = p["vel"]
			if v.length() > 0.01:
				var spin := float((p["spec"] as Dictionary).get("spin", 0.0))
				node.basis = Basis.looking_at(-v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.FORWARD)
				if spin != 0.0:
					node.rotate_object_local(Vector3.FORWARD, spin * float(p["t"]))
		if res == "":
			keep.append(p)
			continue
		var at: Vector3 = p["pos"]
		var hspec: Dictionary = p.get("hit", {})
		var ps: Dictionary = p["spec"]
		match res:
			"hit":
				_impact(str(p["owner"]), hspec)
				if p.has("heal_to"):
					_heal(str(p["heal_to"]), float(p["heal"]))
					var hp := pos3_of(str(p["heal_to"]))
					spawn_at({"kind": "ring", "color": "#7dffa8", "radius": 1.6, "life": 0.6}, hp, hp)
					spawn_at({"kind": "rise", "color": "#9dffb8", "life": 1.0}, hp, hp)
					b.skill_log.append("healed")
				else:
					var sp := Projectiles.surface_point(at, tgt)
					deal(str(p["owner"]), float(p["dmg"]), str(p["action"]), sp, tgt, hspec.get("fx", {}))
			"land":
				var blast := float(ps.get("blast", 0.0))
				if hspec.has("fx"):
					var fx: Dictionary = (hspec["fx"] as Dictionary).duplicate()
					spawn_at(fx, at, at)
					if bool(fx.get("confetti", false)):
						spawn_at({"kind": "confetti", "life": 1.2}, at, at)
				if str(ps.get("on_land", "")) == "present":
					_start_present(p, at)
				elif blast > 0.0 and Projectiles.blast_hits(at, blast, tgt):
					_impact(str(p["owner"]), hspec)
					deal(str(p["owner"]), float(p["dmg"]), str(p["action"]), Projectiles.surface_point(at + Vector3(0, 1.0, 0), tgt), tgt, {"size": 1.0})
			"miss":
				spawn_at({"kind": "smoke", "life": 0.6}, at, at)
		if node != null and is_instance_valid(node):
			node.queue_free()
	b.skill_projs = keep


# ---------------------------------------------------------------- ボンバー：びっくりプレゼント

## プレゼントが落ちた：少しして、ふたが飛び、中からバネの道化が飛び出し、紙ふぶきと一緒に爆発する
func _start_present(p: Dictionary, at: Vector3) -> void:
	var g := {"kind": "present", "pos": at, "t": 0.0, "owner": p["owner"], "dmg": p["dmg"], "action": p["action"], "spec": p["spec"], "hit": p.get("hit", {}),
		"tgt_kind": p.get("tgt_kind", "boss"), "tgt_index": p.get("tgt_index", -1), "stage": 0, "node": null, "lid": null, "jack": null}
	if b.is_inside_tree():
		var root := Node3D.new()
		root.position = at
		var box := MeshInstance3D.new()
		box.mesh = SkillFx.prop_mesh("present_box")
		box.scale = Vector3.ONE * 1.4
		root.add_child(box)
		var lid := MeshInstance3D.new()
		lid.mesh = SkillFx.prop_mesh("present_lid")
		lid.scale = Vector3.ONE * 1.4
		root.add_child(lid)
		var jack := MeshInstance3D.new()
		jack.mesh = SkillFx.prop_mesh("jack_spring")
		jack.scale = Vector3.ONE * 0.01
		root.add_child(jack)
		root.add_to_group("styled")
		b.add_child(root)
		g["node"] = root
		g["lid"] = lid
		g["jack"] = jack
	b.skill_gimmicks.append(g)
	b.skill_log.append("present")


func _update_gimmicks(delta: float) -> void:
	var keep: Array = []
	for g in b.skill_gimmicks:
		g["t"] = float(g["t"]) + delta
		var t := float(g["t"])
		var ps: Dictionary = g["spec"]
		var open_t := float(ps.get("open_sec", 0.45))
		var boom_t := float(ps.get("boom_sec", 0.95))
		var lid: Node3D = g.get("lid")
		var jack: Node3D = g.get("jack")
		if int(g["stage"]) == 0 and t < open_t and lid != null and is_instance_valid(lid):
			# ゆれて、ふたがカタカタ
			(g["node"] as Node3D).rotation.z = sin(t * 40.0) * 0.06
		if int(g["stage"]) == 0 and t >= open_t:
			g["stage"] = 1
			spawn_at({"kind": "confetti", "life": 1.4}, g["pos"], g["pos"])
		if int(g["stage"]) >= 1 and lid != null and is_instance_valid(lid):
			var k := t - open_t
			lid.position = Vector3(0.4 * k, 2.6 * k - 4.0 * k * k + 0.0, 0.0)
			lid.rotation = Vector3(k * 6.0, 0, k * 4.0)
		if int(g["stage"]) >= 1 and jack != null and is_instance_valid(jack):
			var k2 := clampf((t - open_t) / 0.25, 0.0, 1.0)
			var bounce := 1.0 + 0.25 * sin((t - open_t) * 30.0) * (1.0 - k2)
			jack.scale = Vector3(1.4, 1.4 * k2 * bounce, 1.4)
		if int(g["stage"]) == 1 and t >= boom_t:
			g["stage"] = 2
			var at: Vector3 = g["pos"]
			var blast := float(ps.get("blast", 3.5))
			spawn_at({"kind": "blast", "color": "#ff7a2a", "radius": blast, "life": 0.45}, at, at + Vector3(0, 0.5, 0))
			spawn_at({"kind": "ring", "color": "#ffd84a", "radius": blast * 1.3, "life": 0.5}, at, at)
			var tgt: Dictionary = b.boss_info() if str(g["tgt_kind"]) == "boss" else b.sub_info(int(g["tgt_index"]))
			if Projectiles.blast_hits(at, blast, tgt):
				_impact(str(g["owner"]), g.get("hit", {}))
				deal(str(g["owner"]), float(g["dmg"]), str(g["action"]), Projectiles.surface_point(at + Vector3(0, 1.0, 0), tgt), tgt, {"size": 1.2, "color": "#ffb347"})
			if g["node"] != null and is_instance_valid(g["node"]):
				(g["node"] as Node).queue_free()
			g["node"] = null
			continue
		keep.append(g)
	b.skill_gimmicks = keep


# ---------------------------------------------------------------- 効果

## 効果を起こす。slot：使った人。ap：使った人の攻撃力（呼び出しのダメージに使う）
func apply_effect(slot: String, spec: Dictionary, aim: Vector2, ap: float) -> void:
	var kind := str(spec.get("type", ""))
	var origin := pos_of(slot)
	b.skill_log.append(kind)
	match kind:
		"speed_mode":
			b.skill_speed[slot] = {"left": float(spec.get("sec", 6.0)), "mult": float(spec.get("mult", 1.75))}
			spawn_fx({"kind": "aura", "color": str(spec.get("color", "#5fd6ff")), "radius": 1.0, "life": float(spec.get("sec", 6.0)), "alpha": 0.08},
				slot, aim, Vector3.INF, slot)
		"vanish":
			b.skill_vanish[slot] = {"left": float(spec.get("sec", 3.0)), "speed": float(spec.get("speed", 1.3)), "bonus": float(spec.get("bonus", 1.5)),
				"trail": 0.0}
			_ghost_burst(slot, Color(str(spec.get("color", "#5fd6ff"))), false)
			spawn_at({"kind": "rise", "color": "#8fe8ff", "life": 0.6}, pos3_of(slot), pos3_of(slot))
			_show_slot(slot, false)
		"afterimage":
			_ghost_burst(slot, Color(str(spec.get("color", "#5fd6ff"))), false)
		"aura":
			spawn_fx({"kind": "aura", "color": str(spec.get("color", "#ffd24a")), "radius": float(spec.get("radius", 1.0)),
				"life": float(spec.get("sec", 1.6)), "alpha": float(spec.get("alpha", 0.16))}, slot, aim, Vector3.INF, slot)
		"dome", "heal_dome":
			var d := spec.duplicate()
			d["kind"] = kind
			d["pos"] = origin
			d["left"] = float(spec.get("sec", 6.0))
			d["radius"] = float(spec.get("radius", 5.0))
			d["owner"] = slot
			d["revived"] = {}
			d["t"] = 0.0
			var col := str(spec.get("color", "#5aa0ff" if kind == "dome" else "#5fe08a"))
			var fxk := "dome" if kind == "dome" else "heal_dome"
			var node := spawn_fx({"kind": fxk, "color": col, "radius": d["radius"], "life": d["left"], "alpha": 0.14 if kind == "dome" else 0.12},
				slot, aim, Vector3(origin.x, b.ground_y, origin.y))
			d["node"] = node
			b.skill_domes.append(d)
		"heal":
			var r := float(spec.get("radius", 6.0))
			var amt := float(spec.get("amount", 40.0))
			for s in _allies():
				if origin.distance_to(pos_of(s)) <= r:
					_heal(s, amt)
					spawn_at({"kind": "rise", "color": "#9dffb8", "life": 0.9}, pos3_of(s), pos3_of(s))
			spawn_fx({"kind": "ring", "color": str(spec.get("color", "#7dffa8")), "radius": r, "life": 0.6}, slot, aim)
		"heal_shot":
			heal_shot(slot, spec)
		"revive":
			var r2 := float(spec.get("radius", 8.0))
			var ratio := float(spec.get("hp_ratio", 0.5))
			_revive_in(origin, r2, ratio)
			spawn_fx({"kind": "pillar", "color": str(spec.get("color", "#9dffb8")), "radius": 1.4, "tall": 9.0, "life": 1.0}, slot, aim)
		"time_stop":
			if b.net_active:
				return
			var sec := float(spec.get("sec", 3.0))
			if b._round_t() < b.skill_time_stop_resist_until:
				sec *= float(spec.get("resist_mult", 0.5))
			b.skill_time_stop_left = sec
			b.skill_time_stop_resist_until = b._round_t() + sec + float(spec.get("resist_sec", 20.0))
			spawn_fx({"kind": "clock", "color": str(spec.get("color", "#b98aff")), "radius": float(b.config["boss_size"]) * 0.75, "life": sec, "alpha": 0.2},
				slot, aim, Vector3(b.boss.position.x, b.ground_y, b.boss.position.z), "@boss")
		"summon":
			_summon(slot, spec, ap)


func _allies() -> Array:
	var out: Array = [b._my_slot()]
	out.append_array(b.ai_allies.keys())
	return out


func _revive_in(origin: Vector2, r: float, ratio: float) -> void:
	if b.downed and origin.distance_to(pos_of(b._my_slot())) <= r:
		b.downed = false
		b._set_my_hp(b.role_value("hp") * ratio)
		spawn_at({"kind": "rise", "color": "#fff2a8", "life": 1.0}, pos3_of(b._my_slot()), pos3_of(b._my_slot()))
	for s in b.ai_allies:
		var a: Dictionary = b.ai_allies[s]
		if bool(a["downed"]) and origin.distance_to(a["pos"]) <= r:
			a["downed"] = false
			a["hp"] = float(a["max_hp"]) * ratio
			spawn_at({"kind": "rise", "color": "#fff2a8", "life": 1.0}, pos3_of(str(s)), pos3_of(str(s)))


## 消えている人が攻撃を始めた：姿を現す（残像が集まる）。最初の一撃のボーナスを返す
func on_attack_start(slot: String) -> float:
	if not is_vanished(slot):
		return 1.0
	var v: Dictionary = b.skill_vanish[slot]
	v["left"] = 0.0
	_appear(slot)
	return float(v.get("bonus", 1.0))


func _appear(slot: String) -> void:
	_show_slot(slot, true)
	_ghost_burst(slot, Color("#5fd6ff"), true)
	spawn_at({"kind": "ring", "color": "#5fd6ff", "radius": 1.6, "life": 0.4}, pos3_of(slot), pos3_of(slot))


func _show_slot(slot: String, on: bool) -> void:
	var v := view_of(slot)
	if v != null and is_instance_valid(v):
		v.visible = on


# ---------------------------------------------------------------- 残像（スピードファイター）

## 残像を3つ：消える時は外へ広がりながら薄く、現れる時は外から集まる
func _ghost_burst(slot: String, col: Color, gather: bool) -> void:
	var v := view_of(slot)
	if v == null or not v.is_inside_tree():
		b.skill_log.append("ghost")
		return
	var parts := UltFx.bake_ghost(v)
	b.skill_log.append("ghost")
	if parts.is_empty():
		return
	var base := v.global_transform
	var n := aim_of(slot).normalized()
	var side := SkillHits.side_vec(n if n.length() > 0.1 else Vector2(0, -1))
	var offs := [Vector3(side.x, 0, side.y) * 1.2, Vector3(-side.x, 0, -side.y) * 1.2, Vector3(-n.x, 0, -n.y) * 1.4]
	for o in offs:
		var g := _ghost_node(parts, base, col)
		var start: Vector3 = base.origin + (o if gather else Vector3.ZERO)
		var end: Vector3 = base.origin + (Vector3.ZERO if gather else o)
		g.global_position = start
		b.skill_ghosts.append({"node": g, "t": 0.0, "life": 0.35, "from": start, "to": end})


func _ghost_node(parts: Array, base: Transform3D, col: Color) -> Node3D:
	var root := Node3D.new()
	b.add_child(root)
	root.global_transform = base
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pt in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pt[0]
		mi.transform = pt[1]
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	root.set_meta("mat", mat)
	return root


func _update_ghosts(delta: float) -> void:
	var keep: Array = []
	for g in b.skill_ghosts:
		g["t"] = float(g["t"]) + delta
		var k := clampf(float(g["t"]) / float(g["life"]), 0.0, 1.0)
		var node: Node3D = g["node"]
		if node == null or not is_instance_valid(node):
			continue
		node.global_position = (g["from"] as Vector3).lerp(g["to"], smoothstep(0.0, 1.0, k))
		var mat: StandardMaterial3D = node.get_meta("mat")
		mat.albedo_color.a = 0.5 * (1.0 - k)
		if k >= 1.0:
			node.queue_free()
			continue
		keep.append(g)
	b.skill_ghosts = keep


# ---------------------------------------------------------------- 呼び出し（おもちゃの兵隊）

## 呼び出す。unit：plush（ぬいぐるみ：跳ねて近づき、たたく）・soldier（小さい兵隊：行進して近づき、小さな弾を撃つ）。
## 重ならないように、使った人のまわりに輪のように出し、それぞれ少しずつちがう時刻で動く
func _summon(slot: String, spec: Dictionary, ap: float) -> void:
	var n := int(spec.get("count", 3))
	var maxn := int(spec.get("max_active", n))
	var mine: Array = b.skill_summons.filter(func(u: Dictionary) -> bool: return str(u["owner"]) == slot)
	while mine.size() + n > maxn and not mine.is_empty():
		var old: Dictionary = mine.pop_front()
		old["life"] = 0.0
	var origin := pos_of(slot)
	var aim := aim_of(slot).normalized()
	if aim.length() < 0.1:
		aim = Vector2(0, -1)
	var base_ang := atan2(aim.y, aim.x)
	for i in n:
		var ang := base_ang + (float(i) - (n - 1) * 0.5) * (PI * 0.9 / maxf(n - 1, 1))
		var spread := float(spec.get("spread", 1.6))
		var p := origin + Vector2(cos(ang), sin(ang)) * spread
		var u := {"owner": slot, "pos": p, "life": float(spec.get("sec", 10.0)), "age": 0.0, "delay": 0.12 * i,
			"next": float(spec.get("first", 0.8)) + 0.23 * i, "interval": float(spec.get("interval", 1.0)) * (1.0 + 0.08 * (i % 3)),
			"mult": float(spec.get("multiplier", 0.6)), "ap": ap, "speed": float(spec.get("speed", 5.0)) * (0.92 + 0.08 * (i % 3)),
			"reach": float(spec.get("reach", 1.0)), "unit": str(spec.get("unit", "plush")), "slot_i": i, "n": n,
			"hop": float(i) * 0.37, "node": null, "view": null, "state": ""}
		u["node"] = _make_unit(u, i)
		b.skill_summons.append(u)
		spawn_at({"kind": "smoke", "life": 0.6, "color": "#fff3d8"}, Vector3(p.x, b.ground_y, p.y), Vector3(p.x, b.ground_y, p.y))


func _make_unit(u: Dictionary, i: int) -> Node3D:
	if not b.is_inside_tree():
		return null
	var root := Node3D.new()
	root.name = "Summon"
	b.add_child(root)
	root.add_to_group("styled")
	if str(u["unit"]) == "soldier":
		var def: Dictionary = CharacterData.find(b.characters_cfg if not b.characters_cfg.is_empty() else CharacterData.load_config(), "summoner").duplicate(true)
		var mini: Dictionary = def.get("mini", {})
		def["model"] = str(mini.get("model", "res://assets/models/chars/summoner_mini.scn"))
		def["animations"] = mini.get("animations", def.get("animations", {}))
		def["anim_speeds"] = mini.get("anim_speeds", {})
		def["anim_oneshot"] = ["attack"]
		def["built_anims"] = mini_built(def)
		var v: Node3D = CharacterView.new()
		if v.setup(def):
			v.scale = Vector3.ONE * float(mini.get("scale", 0.85))
			root.add_child(v)
			u["view"] = v
			# 出てきた兵隊は、ねている姿勢から立ち上がる（たおれる動きを、後ろから速く流す）
			v.play_step("down", -float(mini.get("stand_speed", 2.4)), true)
			u["stand"] = true
		else:
			v.free()
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = SkillFx.prop_mesh(["plush_bear", "plush_bunny", "plush_bear2"][i % 3])
		root.add_child(mi)
	root.scale = Vector3.ONE * 0.01
	return root


## 小さい兵隊が使う動きだけ（作る数を減らす）
static func mini_built(def: Dictionary) -> Dictionary:
	var out := {}
	var all: Dictionary = def.get("built_anims", {})
	for k in (def.get("animations", {}) as Dictionary).values():
		if all.has(str(k)):
			out[str(k)] = all[str(k)]
	return out


## 版79：戦いの始めに、小さい兵隊の動きを前もって作っておく（はじめて呼んだ時に止まらないように）
func warm_mini() -> void:
	var def: Dictionary = CharacterData.find(b.characters_cfg if not b.characters_cfg.is_empty() else CharacterData.load_config(), "summoner").duplicate(true)
	var mini: Dictionary = def.get("mini", {})
	if mini.is_empty():
		return
	def["model"] = str(mini.get("model", ""))
	def["animations"] = mini.get("animations", {})
	def["built_anims"] = mini_built(def)
	var v: Node3D = CharacterView.new()
	if v.setup(def):
		b.skill_log.append("warm_mini")
	v.free()


func _update_summons(delta: float) -> void:
	var keep: Array = []
	for u in b.skill_summons:
		u["life"] = float(u["life"]) - delta
		u["age"] = float(u["age"]) + delta
		var node: Node3D = u.get("node")
		if float(u["life"]) <= 0.0 or not b.round_active():
			if node != null and is_instance_valid(node):
				spawn_at({"kind": "smoke", "life": 0.5, "color": "#fff3d8"}, node.position, node.position)
				node.queue_free()
			continue
		var tgt: Dictionary = target_of(str(u["owner"]))
		var p: Vector2 = u["pos"]
		var soldier := str(u["unit"]) == "soldier"
		var age := float(u["age"]) - float(u["delay"])
		var pop := clampf(age / 0.3, 0.0, 1.0)
		var moving := false
		var to := Vector2.ZERO
		if not tgt.is_empty() and age > (0.6 if soldier else 0.35):  # 兵隊は、立ち上がってから動く
			var c := Vector2(float(tgt["x"]), float(tgt["z"]))
			# 敵のまわりに、並んで立つ（それぞれ少しずつちがう角度）
			var dir0 := (p - c).normalized() if (p - c).length() > 0.01 else Vector2(0, 1)
			var ang := atan2(dir0.y, dir0.x) + (float(u["slot_i"]) - float(u["n"]) * 0.5) * 0.12
			var stand := float(tgt["r"]) + float(u["reach"]) * (0.8 if not soldier else 3.5)
			var goal := c + Vector2(cos(ang), sin(ang)) * stand
			to = c - p
			if p.distance_to(goal) > 0.15:
				var stepv := (goal - p).normalized() * minf(float(u["speed"]) * delta, p.distance_to(goal))
				p += stepv
				u["pos"] = p
				moving = true
			u["next"] = float(u["next"]) - delta
			var in_reach := (p - c).length() <= float(tgt["r"]) + (float(u["reach"]) + 0.4 if not soldier else float(u["reach"]) * 4.0 + 0.6)
			if float(u["next"]) <= 0.0 and in_reach and not b.phase.invulnerable():
				u["next"] = float(u["interval"])
				var dmg := Damage.damage_amount(float(u["ap"]), float(b.config["attack_multiplier"]) * float(u["mult"]) * dealt_mult(str(u["owner"])))
				if soldier:
					# 小さな弾を撃つ（当たった時にダメージ）
					var from := Vector3(p.x, b.ground_y + 0.75, p.y) + Vector3(to.normalized().x, 0, to.normalized().y) * 0.5
					var sv: Node3D = u.get("view")
					if sv != null and is_instance_valid(sv) and sv.has_method("socket_position"):
						var mp: Vector3 = sv.socket_position("muzzle")
						if mp != Vector3.INF and mp.y > b.ground_y - 0.5:
							from = mp
					var ps := {"mode": "straight", "speed": 28.0, "radius": 0.12, "range": 14.0, "prop": "bullet_small", "aim_h": 0.35, "ground": b.ground_y}
					var cc := Vector3(c.x, float(tgt.get("y0", 0.0)) + float(tgt["h"]) * 0.35, c.y)
					var pr := Projectiles.make(ps, from, cc, str(u["owner"]), dmg, "summon")
					pr["hit"] = {"fx": {"size": 0.35}}
					pr["tgt_kind"] = str(tgt.get("kind", "boss"))
					pr["tgt_index"] = int(tgt.get("index", -1))
					pr["node"] = _proj_node(ps, from)
					b.skill_projs.append(pr)
					spawn_at({"kind": "prop", "prop": "muzzle_flash", "scale": 0.35, "life": 0.08}, from, from)
					if u.get("view") != null and is_instance_valid(u["view"]):
						(u["view"] as Node).play_step("attack", 1.0)
				else:
					deal(str(u["owner"]), dmg, "summon", Vector3(p.x, b.ground_y + 0.6, p.y) + Vector3(to.normalized().x, 0, to.normalized().y) * 0.3, tgt,
						{"size": 0.4, "color": "#ffd0e0"})
					u["bump"] = 0.2
		u["bump"] = maxf(0.0, float(u.get("bump", 0.0)) - delta)
		if node != null and is_instance_valid(node):
			u["hop"] = float(u["hop"]) + delta
			var y := b.ground_y
			if not soldier:
				y += absf(sin(float(u["hop"]) * 9.0)) * 0.22 if moving else 0.0
			node.position = Vector3(p.x, y, p.y)
			if to.length() > 0.01:
				node.rotation.y = atan2(to.x, to.y)
			node.rotation.x = float(u.get("bump", 0.0)) * 2.5 if not soldier else 0.0
			# 出る時：小さく出て、ぴょんと大きくなる（おもちゃらしく）
			var sc := pop * (1.0 + 0.25 * sin(pop * PI)) if pop < 1.0 else 1.0
			if float(u["life"]) < 0.3:
				sc *= float(u["life"]) / 0.3
			node.scale = Vector3.ONE * maxf(sc, 0.01)
			var v: Node3D = u.get("view")
			if v != null and is_instance_valid(v):
				var st := "run" if moving else "idle"
				var ap2: AnimationPlayer = (v as Node).get("player")
				var busy_step := str((v as Node).get("current_action")) == "step" and ap2 != null and ap2.is_playing()
				if not busy_step:
					(v as Node).play_action(st)  # 同じ動きなら何もしない
					u["state"] = st
		keep.append(u)
	b.skill_summons = keep


# ---------------------------------------------------------------- 見た目

## 見た目を出す。at：出す所（INF なら使った人の足もと）。follow：ついていく枠（"@boss" はボス）
func spawn_fx(spec: Dictionary, slot: String, aim: Vector2, at: Vector3 = Vector3.INF, follow: String = "") -> Node3D:
	b.skill_fx_log.append(str(spec.get("kind", "")))
	if not b.is_inside_tree():
		return null
	var from := pos3_of(slot)
	var to := at if at != Vector3.INF else from
	var h := float(spec.get("height", 1.3))
	var node := SkillFx.make(spec, from, to, h)
	b.add_child(node)
	b.skill_fx.append({"node": node, "follow": follow})
	return node


## 決まった所に、見た目を出す（from→to の向き）
func spawn_at(spec: Dictionary, from: Vector3, to: Vector3) -> Node3D:
	b.skill_fx_log.append(str(spec.get("kind", "")))
	if not b.is_inside_tree():
		return null
	var node := SkillFx.make(spec, from, to, 0.0)
	b.add_child(node)
	b.skill_fx.append({"node": node, "follow": ""})
	return node


func _spawn_oriented(spec: Dictionary, at: Vector3, toward: Vector3) -> void:
	var n := spawn_at(spec, at, at)
	if n != null:
		n.position = at
		var d := toward - at
		if d.length() > 0.01:
			n.basis = Basis.looking_at(-d.normalized(), Vector3.UP)
			n.scale = Vector3.ONE * float(spec.get("scale", 1.0))


## 攻撃の動きの見た目（fx_events）：ねらう所を決めて出す。from：発射口の名前（あれば、そこから）
func action_fx(slot: String, spec: Dictionary, aim: Vector2) -> void:
	var o := pos_of(slot)
	var tgt := target_of(slot)
	var bxz := Vector2(float(tgt.get("x", b.boss.position.x)), float(tgt.get("z", b.boss.position.z)))
	var n := aim.normalized() if aim.length() > 0.001 else Vector2(0, -1)
	var side := SkillHits.side_vec(n) * float(spec.get("side", 0.0))
	var target: Vector2
	match str(spec.get("at", "front")):
		"boss", "target":
			target = bxz
		"self":
			target = o
		"hit":
			target = SkillHits.center(spec.get("hit", {}), o, n, bxz)
		_:
			target = o + side + n * float(spec.get("dist", spec.get("length", 3.0)))
	var s := spec.duplicate()
	var kind := str(spec.get("kind", ""))
	if kind in ["beam", "slash"]:
		var e := SkillHits.beam_ends({"length": float(spec.get("length", 10.0)), "side": float(spec.get("side", 0.0))}, o, n)
		var start := Vector3((e[0] as Vector2).x, b.ground_y, (e[0] as Vector2).y)
		var endp := Vector3((e[1] as Vector2).x, b.ground_y, (e[1] as Vector2).y)
		var h := float(spec.get("height", 1.3))
		if spec.has("from"):
			var sp := socket(slot, str(spec["from"]), aim)
			start = sp
			endp = Vector3(endp.x, sp.y, endp.z)
			h = 0.0
			s["tilt"] = true
		b.skill_fx_log.append(kind)
		if not b.is_inside_tree():
			return
		var node := SkillFx.make(s, start, endp, h)
		b.add_child(node)
		b.skill_fx.append({"node": node, "follow": ""})
		return
	if kind == "prop" and spec.has("from"):
		var sp2 := socket(slot, str(spec["from"]), aim)
		_spawn_oriented(s, sp2, sp2 + Vector3(n.x, 0, n.y))
		return
	if spec.has("from"):
		var sp3 := socket(slot, str(spec["from"]), aim)
		spawn_at(s, sp3, sp3 if str(spec.get("at", "")) == "socket" else Vector3(target.x, b.ground_y, target.y))
		return
	spawn_fx(s, slot, aim, Vector3(target.x, b.ground_y, target.y), slot if kind == "aura" else "")


## 守りの膜に、攻撃が当たった（中の味方 slot がダメージを受けた）：当たった向きに、青い波紋
func on_hazard_hit(slot: String, from_xz: Vector2) -> void:
	var d := dome_at(pos_of(slot))
	if d.is_empty():
		return
	var c := Vector3((d["pos"] as Vector2).x, b.ground_y, (d["pos"] as Vector2).y)
	var dir := Vector3(from_xz.x - c.x, 0.0, from_xz.y - c.z)
	if dir.length() < 0.01:
		dir = Vector3(0, 0, 1)
	var at := c + dir.normalized() * float(d["radius"]) * 0.9 + Vector3(0, 1.6, 0)
	spawn_at({"kind": "ripple", "color": "#9fd0ff", "radius": 1.4, "life": 0.45}, c + Vector3(0, 1.6, 0), at)
	var node: Node3D = d.get("node")
	if node != null and is_instance_valid(node):
		node.set_meta("pulse", 1.0)


# ---------------------------------------------------------------- 毎コマ

func update(delta: float) -> void:
	for slot in b.skill_speed.keys():
		var s: Dictionary = b.skill_speed[slot]
		s["left"] = maxf(0.0, float(s["left"]) - delta)
	for slot in b.skill_vanish.keys():
		var v: Dictionary = b.skill_vanish[slot]
		if float(v["left"]) <= 0.0:
			continue
		v["left"] = maxf(0.0, float(v["left"]) - delta)
		# 消えている間：動くと、うすい青の残像がときどき残る
		v["trail"] = float(v.get("trail", 0.0)) - delta
		if float(v["trail"]) <= 0.0:
			v["trail"] = 0.18
			spawn_at({"kind": "rise", "color": "#8fe8ff", "life": 0.5}, pos3_of(str(slot)), pos3_of(str(slot)))
		if float(v["left"]) <= 0.0:
			_appear(str(slot))
	b.actions.cd_rate = speed_mult(b._my_slot())
	for slot in b.ai_allies:
		var a: Dictionary = b.ai_allies[slot]
		a["speed_mult"] = speed_mult(str(slot))
		a["vanished"] = is_vanished(str(slot))
		var acts: Variant = a["actions"]
		acts.cd_rate = a["speed_mult"]
	_update_domes(delta)
	_update_projs(delta)
	_update_gimmicks(delta)
	_update_summons(delta)
	_update_ghosts(delta)
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
			follow = pos3_of(fs)
		if SkillFx.tick(node, delta, follow):
			keep.append(f)
		else:
			node.queue_free()
	b.skill_fx = keep


func _update_domes(delta: float) -> void:
	var keep: Array = []
	for d in b.skill_domes:
		d["left"] = float(d["left"]) - delta
		d["t"] = float(d["t"]) + delta
		if float(d["left"]) <= 0.0:
			continue
		if str(d["kind"]) == "heal_dome":
			var per := float(d.get("per_sec", 6.0)) * delta
			for s in _allies():
				if (pos_of(s) as Vector2).distance_to(d["pos"]) <= float(d["radius"]):
					_heal(s, per)
			if float(d["t"]) >= float(d.get("revive_after", 2.0)) and not bool((d["revived"] as Dictionary).get("done", false)):
				d["revived"]["done"] = true
				_revive_in(d["pos"], float(d["radius"]), float(d.get("hp_ratio", 0.5)))
		keep.append(d)
	b.skill_domes = keep
