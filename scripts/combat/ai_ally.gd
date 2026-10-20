extends RefCounted
## AIの味方。画面を持たない計算だけ（テストしやすい）。
## 位置は世界の座標 (x, z)。ボスの当たり場所（hazards）は boss_attacks.gd と同じ形。
## 版71：ボスの攻撃を見て、よける・攻める・下がるを決める（数値は data/ai_allies.json の tactics）。
##   ctx["forecast"]：いまの攻撃の、これから当たる場所と時刻 [{dt: 何秒後, h: 当たり}]（stick_prototype が、攻撃の中の秒を先へ進めて調べる）。
##   ctx["forecast_age"]：forecast を作ってからの秒。ctx["next_attack_in"]：ボスの次の攻撃が始まるまでの秒。
##   ①考える（reaction_sec ごと）：いまの場所に、これから当たる物（threat）があるか。
##     ・あれば：Y（かわし斬り）の跳んでいる間に全部当たり、どれもジャンプでよけられるなら、Y でよける。
##       走って外へ出られるなら走る（両方できれば prefer_dodge の確率で Y）。Y がまだ早いなら、ちょうどよい時刻まで待って Y。
##     ・なければ：次に危なくなるまでの秒（すき）を出す。すきが長いほど、長い攻撃（五段斬り）を使う。短ければ、すぐ終わる攻撃だけ。
##   ②体力が low_hp より少ないとき・当たった直後（regroup_sec）は「用心」：すきが careful_window より短ければ、離れて待つ。
##   ③必殺技は動いている間は無敵なので、ゲージがたまって届けば使う。
##   見まちがい：考えるたびに skill の確率で正しく読む（読めなければ、そのときは何もしない）

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const Damage := preload("res://scripts/combat/damage.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
const SkillHits := preload("res://scripts/combat/skill_hits.gd")
const Gauge := preload("res://scripts/combat/ultimate_gauge.gd")
const HitArea := preload("res://scripts/combat/hit_area.gd")
const DODGE_HEIGHT := 0.5  ## これより高く跳んでいれば、「ジャンプでよけられる」攻撃は当たらない


static func load_config(path: String = "res://data/ai_allies.json") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## def：キャラの定義（characters.json の1件）。index：0〜2（立つ位置の角度を決める）
static func make(def: Dictionary, index: int, spawn: Vector2) -> Dictionary:
	var st: Dictionary = def.get("stats", {})
	return {
		"id": str(def.get("id", "")), "index": index, "pos": spawn, "hp": float(st.get("hp", 100.0)), "max_hp": float(st.get("hp", 100.0)),
		"downed": false, "hits": 0.0, "height": 0.0, "stun": 0.0, "flash": 0.0, "stats": st.duplicate(), "face": Vector2(0, -1),
		"decided": {}, "think": 0.0, "think_attack": 0.0, "evade": Vector2.ZERO,
		"window": 99.0, "hold": false, "regroup": 0.0, "hp_prev": float(st.get("hp", 100.0)), "dodges": 0, "evades": 0, "mode": "",
		"actions": Actions.new(Actions.config_for(str(def.get("id", "")))), "out_events": [], "speed_mult": 1.0, "gauge": Gauge.new(Actions.load_config()), "events": [], "banner": "", "name": str(def.get("name", "")),
	}


static func is_airborne(a: Dictionary) -> bool:
	return float(a["height"]) > DODGE_HEIGHT


## 動作中のキャラの、アニメ・向き・高さ。prototype が見た目に使う
static func act(a: Dictionary) -> Actions:
	return a["actions"]


## 予告や当たりの中にいるか／近づいているか。いたら、逃げる向き（なければ ZERO）
static func evade_dir(pos: Vector2, hazards: Array, margin: float, me: String) -> Vector2:
	var best := Vector2.ZERO
	var best_depth := 0.0
	for h in hazards:
		var target := str(h["target"])
		if target != "" and target != me:
			continue
		if str(h.get("style", "")) == "safe":
			continue  # 酒の大雨の安全地帯（よける物ではない。入る所）
		var e := Attacks.escape_of(h, pos.x, pos.y, margin)
		var depth := float(e["depth"])
		var dir: Vector2 = e["dir"]
		if depth > best_depth:
			best_depth = depth
			best = dir
	return best


## 1コマ進める。戻り値：ボスに与えたダメージ（なければ 0）
## ctx：{boss: Vector2, boss_radius, bounds, hazards, cfg（ai_allies.json）, attack_multiplier, rng: RandomNumberGenerator, can_hit_boss: bool, drop_damage}
## できごと：a["events"]（このコマで流すアニメ）、a["banner"]（必殺技を使った瞬間だけ、技名が入る）
static func step(a: Dictionary, delta: float, ctx: Dictionary) -> float:
	a["flash"] = maxf(0.0, float(a["flash"]) - delta)
	a["stun"] = maxf(0.0, float(a["stun"]) - delta)
	a["kb_guard"] = maxf(0.0, float(a.get("kb_guard", 0.0)) - delta)
	a["events"] = []
	a["banner"] = ""
	a["hit_events"] = []  # 版75：このコマでボスに当たった一撃ずつ [{dmg, action}]（ダメージの数字に使う）
	a["out_events"] = []  # 版78：見た目（fx）と効果（effect）。battle_ai_team が出す
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var actions := act(a)
	var was_busy := actions.busy()
	var dealt := 0.0
	var boss: Vector2 = ctx["boss"]
	var half := float(ctx["bounds"])
	var evs := actions.update(delta)
	if was_busy:
		var pos0: Vector2 = a["pos"]
		var dfwd := actions.frame_move.x
		if bool(actions.def(actions.active).get("stop_at_boss", false)):
			dfwd = HitArea.clip_forward(pos0, actions.aim, dfwd, boss, float(ctx["boss_radius"]) + float(actions.cfg.get("stop_margin", 0.9)))
		var p1 := pos0 + actions.aim * dfwd
		a["pos"] = Vector2(clampf(p1.x, -half, half), clampf(p1.y, -half, half))
		a["height"] = actions.height
	for ev in evs:
		match str(ev["type"]):
			"hit":
				dealt += _resolve_hit(a, ev, ctx)
			"anim":
				(a["events"] as Array).append(ev)
			"fx", "effect":
				(a["out_events"] as Array).append(ev)
			"mark":
				if str(ev["name"]) == "landed":
					a["hp"] = maxf(0.0, float(a["hp"]) - float(ctx.get("drop_damage", 0.0)))
					a["flash"] = 0.15
					if float(a["hp"]) <= 0.0:
						a["downed"] = true
	# 版71：当たった直後は、少しのあいだ用心する（立て直し）。すき（window）は時間とともに減る（動いている間も）
	var tac: Dictionary = cfg.get("tactics", {})
	if float(a["hp"]) < float(a.get("hp_prev", a["hp"])) - 0.001:
		a["regroup"] = float(tac.get("regroup_sec", 1.5))
	a["hp_prev"] = float(a["hp"])
	a["regroup"] = maxf(0.0, float(a.get("regroup", 0.0)) - delta)
	a["window"] = float(a.get("window", 99.0)) - delta
	if bool(a["downed"]) or bool(a.get("held", false)):
		actions.cancel()
		a["height"] = 0.0
		return _flush(a, dealt)
	if float(a["stun"]) > 0.0 or actions.busy():
		return _flush(a, dealt)
	a["height"] = 0.0
	var speed := float(st.get("move_speed", 6.0)) * float(a.get("speed_mult", 1.0))  # 版78：超高速モード
	var pos: Vector2 = a["pos"]
	# 考える間隔（反応の遅れ）
	a["think"] = float(a["think"]) - delta
	if float(a["think"]) <= 0.0:
		a["think"] = float(cfg["reaction_sec"])
		if _think(a, ctx):
			return _flush(a, dealt)  # Y でよけ始めた
	var ev2: Vector2 = a["evade"]
	var moved := Vector2.ZERO
	var reach := float(st.get("attack_reach", 2.0)) + float(ctx["boss_radius"])
	# 版84：倒れた仲間の輪へ行き、中で待つ（よける方が先。起こしている間は攻撃しない）
	var rv: Variant = (ctx.get("revive_at", {}) as Dictionary).get(str(ctx.get("slot", "")))
	a["reviving"] = rv is Vector2
	if ev2 != Vector2.ZERO:
		moved = ev2 * speed * float(cfg["evade_speed_factor"]) * delta
	elif rv is Vector2:
		var to_r: Vector2 = (rv as Vector2) - pos
		if to_r.length() > 0.25:
			moved = to_r.normalized() * minf(speed * delta, to_r.length())
			a["face"] = to_r.normalized()
	else:
		var ang := deg_to_rad(float((cfg["approach_angles_deg"] as Array)[int(a["index"]) % (cfg["approach_angles_deg"] as Array).size()]))
		var stand := reach * float(cfg["stand_factor"])
		if bool(a.get("hold", false)):
			stand = reach + float(tac.get("safe_gap", 2.5))  # 用心：届かない所で待つ
		var want := boss + Vector2(sin(ang), cos(ang)) * stand
		var to := want - pos
		if to.length() > 0.3:
			moved = to.normalized() * minf(speed * delta, to.length())
		a["face"] = (boss - pos).normalized() if (boss - pos).length() > 0.01 else a["face"]
	if moved != Vector2.ZERO:
		pos = Vector2(clampf(pos.x + moved.x, -half, half), clampf(pos.y + moved.y, -half, half))
		a["pos"] = pos
	# こうげき：届くところにいて、よけなくてよく、待っていないときだけ（どの攻撃を使うかは、すきの長さで決める）
	if bool(ctx.get("can_hit_boss", true)) and ev2 == Vector2.ZERO and not bool(a.get("hold", false)) and not bool(a.get("reviving", false)) and (boss - pos).length() <= reach:
		_choose_attack(a, ctx, delta)
	return _flush(a, dealt)


## 版71：これから当たる物のうち、pos にいたら当たる物 [{dt, h}]（ねらいが自分か全員、ダメージがある、安全地帯ではない）
static func threats_at(pos: Vector2, forecast: Array, age: float, margin: float, me: String) -> Array:
	var out: Array = []
	for f in forecast:
		var h: Dictionary = f["h"]
		var target := str(h.get("target", ""))
		if target != "" and target != me:
			continue
		if str(h.get("style", "")) == "safe" or (float(h.get("power", 0.0)) <= 0.0 and not bool(h.get("grab", false))):
			continue
		var dt := float(f["dt"]) - age
		if dt < -0.05:
			continue
		if float(Attacks.escape_of(h, pos.x, pos.y, margin)["depth"]) <= 0.0:
			continue
		out.append({"dt": maxf(dt, 0.0), "h": h})
	return out


## 版71：いちばん早く当たる時刻（なければ 99）
static func first_dt(threats: Array) -> float:
	var best := 99.0
	for th in threats:
		best = minf(best, float(th["dt"]))
	return best


## 版71：Y（かわし斬り）の跳ぶ高さが DODGE_HEIGHT をこえている時間 [始め, 終わり]（秒）。跳ばなければ []
static func airborne_span(actions: Actions) -> Array:
	var d := actions.def("sub")
	var path: Array = d.get("path", [])
	var dur := float(d.get("duration_sec", 1.0))
	var t0 := -1.0
	var t1 := -1.0
	var x := 0.0
	while x <= dur:
		if Actions.offset_at(path, x).y > DODGE_HEIGHT + 0.1:
			if t0 < 0.0:
				t0 = x
			t1 = x
		x += 0.02
	return [t0, t1] if t0 >= 0.0 else []


## 版71：いま Y を始めると、threats の中で Y の間（duration）に当たる物を、全部跳んでよけられるか。
## 1つもなければ false（よける物がない）
static func dodge_covers(actions: Actions, threats: Array) -> bool:
	var span := airborne_span(actions)
	if span.is_empty():
		return false
	var dur := float(actions.def("sub").get("duration_sec", 1.0))
	var any := false
	for th in threats:
		var dt := float(th["dt"])
		if dt > dur:
			continue  # 着地のあとの当たりは、次に考える
		any = true
		if not bool((th["h"] as Dictionary).get("jumpable", false)):
			return false
		if dt < float(span[0]) or dt > float(span[1]):
			return false
	return any


## 版71：threats から外へ出る向き（深いほど重く）と、出るまでの距離（m）
static func escape_plan(pos: Vector2, threats: Array, margin: float) -> Dictionary:
	var sum := Vector2.ZERO
	var far := 0.0
	for th in threats:
		var h: Dictionary = th["h"]
		var e := Attacks.escape_of(h, pos.x, pos.y, margin)
		var depth := float(e["depth"])
		if depth <= 0.0:
			continue
		var dist := depth - 100.0 if str(h["shape"]) == "rain" else depth
		far = maxf(far, dist)
		sum += (e["dir"] as Vector2) * maxf(dist, 0.1)
	return {"dir": sum.normalized() if sum.length() > 0.001 else Vector2.ZERO, "dist": far}


## 版71：考える。Y でよけ始めたら true。a["evade"]（走る向き）・a["window"]（すき）・a["hold"]（離れて待つ）・a["mode"] を決める
static func _think(a: Dictionary, ctx: Dictionary) -> bool:
	var cfg: Dictionary = ctx["cfg"]
	var tac: Dictionary = cfg.get("tactics", {})
	var rng: RandomNumberGenerator = ctx["rng"]
	var actions := act(a)
	var pos: Vector2 = a["pos"]
	var me := str(ctx.get("slot", ""))
	var st: Dictionary = a["stats"]
	var speed := float(st.get("move_speed", 6.0)) * float(cfg["evade_speed_factor"])
	var forecast: Array = ctx.get("forecast", [])
	var age := float(ctx.get("forecast_age", 0.0))
	var threats := threats_at(pos, forecast, age, float(tac.get("threat_margin", 0.5)), me)
	# いま当たっている物（予告の外から来る物も）からは、まず離れる
	var now_dir := evade_dir(pos, ctx["hazards"], float(cfg["evade_margin"]), me)
	if rng.randf() >= float(tac.get("skill", 1.0)):
		return false  # 読みそこねた：いまの動きのまま
	a["hold"] = false
	if not threats.is_empty():
		var eta := first_dt(threats)
		a["window"] = eta
		var plan := escape_plan(pos, threats, float(tac.get("threat_margin", 0.5)))
		var can_run := float(plan["dist"]) / maxf(speed, 0.1) < eta - 0.05 and (plan["dir"] as Vector2) != Vector2.ZERO
		var y_ready := actions.can_start("sub")
		var can_dodge := y_ready and dodge_covers(actions, threats)
		if can_dodge and (not can_run or rng.randf() < float(tac.get("prefer_dodge", 0.5))):
			if _start(a, "sub", ctx):
				a["dodges"] = int(a.get("dodges", 0)) + 1
				a["mode"] = "dodge"
				a["evade"] = Vector2.ZERO
				return true
		if can_run or not y_ready:
			a["evade"] = plan["dir"] if (plan["dir"] as Vector2) != Vector2.ZERO else now_dir
			a["evades"] = int(a.get("evades", 0)) + 1
			a["mode"] = "evade"
			return false
		# 走っても間に合わない：Y でよけられる時刻になるまで待つ（ジャンプでよけられる物だけなら）
		var all_jump := true
		for th in threats:
			if not bool((th["h"] as Dictionary).get("jumpable", false)):
				all_jump = false
		var span := airborne_span(actions)
		if all_jump and not span.is_empty() and eta > float(span[1]):
			a["evade"] = Vector2.ZERO
			a["mode"] = "wait_dodge"
			a["think"] = clampf(eta - (float(span[0]) + float(span[1])) * 0.5, float(tac.get("dodge_think_min", 0.03)), float(cfg["reaction_sec"]))
			return false
		a["evade"] = plan["dir"] if (plan["dir"] as Vector2) != Vector2.ZERO else now_dir
		a["evades"] = int(a.get("evades", 0)) + 1
		a["mode"] = "evade"
		return false
	# 当たる物がない：すき（次に危なくなるまでの秒）を出す
	a["evade"] = now_dir
	var window := minf(float(tac.get("forecast_sec", 2.0)), float(ctx.get("next_attack_in", 99.0)) + float(tac.get("next_warn_sec", 0.45)))
	a["window"] = window
	var careful := float(a["hp"]) < float(a["max_hp"]) * float(tac.get("low_hp", 0.35)) or float(a.get("regroup", 0.0)) > 0.0
	a["hold"] = careful and window < float(tac.get("careful_window", 1.2)) and not (a["gauge"] as Gauge).is_ready()
	a["mode"] = "hold" if bool(a["hold"]) else "attack"
	return false


## 版71：攻撃 id を始めてから、動けるようになるまでの秒
static func lock_sec(a: Dictionary, id: String) -> float:
	if id == "normal":
		return float((a["stats"] as Dictionary).get("attack_cooldown_sec", 0.4))
	return float(act(a).def(id).get("duration_sec", 1.0))


## 始めた攻撃がその場で当たった分（通常攻撃）を、戻り値に足す
static func _flush(a: Dictionary, dealt: float) -> float:
	var extra := float(a.get("pending_hit", 0.0))
	a["pending_hit"] = 0.0
	return dealt + extra


## どの攻撃を使うか決める。必殺技がためてあれば必殺技、そうでなければ、ときどきメイン・サブ、あとは通常
static func _choose_attack(a: Dictionary, ctx: Dictionary, delta: float) -> void:
	var cfg: Dictionary = ctx["cfg"]
	var actions := act(a)
	var rng: RandomNumberGenerator = ctx["rng"]
	if bool(cfg.get("ai_ultimate", true)) and (a["gauge"] as Gauge).is_ready():
		if _start(a, "ultimate", ctx):
			return
	# 版71：すき（window）の中で終わる攻撃だけを使う。すきが長いときに、長い攻撃（メイン）を使う
	var margin := float((cfg.get("tactics", {}) as Dictionary).get("commit_margin", 0.15))
	var window := float(a.get("window", 99.0))
	var careful := float(a["hp"]) < float(a["max_hp"]) * float((cfg.get("tactics", {}) as Dictionary).get("low_hp", 0.35))
	a["think_attack"] = float(a["think_attack"]) - delta
	if float(a["think_attack"]) <= 0.0:
		a["think_attack"] = float(cfg["attack_think_sec"])
		if actions.can_start("main") and window >= lock_sec(a, "main") + margin and rng.randf() < float(cfg["use_main_chance"]) and _start(a, "main", ctx):
			return
		# Y は、よけるために残しておきたいので、攻めに使うのは体力に余裕があって、すきが長いときだけ
		if not careful and actions.can_start("sub") and window >= lock_sec(a, "sub") + margin and rng.randf() < float(cfg["use_sub_chance"]) and _start(a, "sub", ctx):
			return
	if window >= lock_sec(a, "normal") + margin:
		_start(a, "normal", ctx)


## id の攻撃を、ボスに向かって始める。始められたら true
static func _start(a: Dictionary, id: String, ctx: Dictionary) -> bool:
	var actions := act(a)
	if not actions.can_start(id):
		return false
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var cooldown := float(st.get("attack_cooldown_sec", 0.4)) / float(a.get("speed_mult", 1.0)) if id == "normal" else float(actions.def(id).get("cooldown_sec", 1.0)) * float(cfg["ai_cooldown_scale"])
	if id == "ultimate":
		if not (a["gauge"] as Gauge).consume():
			return false
		a["banner"] = str(actions.def(id).get("name", ""))
	if bool(actions.def(id).get("sweep_hit", false)):
		a["ult_from"] = a["pos"]  # 版72b・78：駆けぬけた道で当たりを調べる（必殺技・ダッシュ技）
	var boss: Vector2 = ctx["boss"]
	var to := boss - (a["pos"] as Vector2)
	var aim := to if to.length() > 0.01 else (a["face"] as Vector2)
	a["face"] = aim.normalized()
	var ok := actions.start(id, aim, cooldown if id != "ultimate" else -1.0)
	if ok:
		var first := actions.update(0.0)
		for ev in first:
			if str(ev["type"]) == "hit":
				pass
			elif str(ev["type"]) == "anim":
				(a["events"] as Array).append(ev)
			elif str(ev["type"]) in ["fx", "effect"]:
				(a["out_events"] as Array).append(ev)
		# 始めてすぐ当たる攻撃（通常）は、ここで当てる
		for ev in first:
			if str(ev["type"]) == "hit":
				a["pending_hit"] = float(a.get("pending_hit", 0.0)) + _resolve_hit(a, ev, ctx)
	return ok


## 当たったか調べて、ダメージを返す（ゲージもたまる）
static func _resolve_hit(a: Dictionary, ev: Dictionary, ctx: Dictionary) -> float:
	if not bool(ctx.get("can_hit_boss", true)):
		return 0.0
	var cfg: Dictionary = ctx["cfg"]
	var st: Dictionary = a["stats"]
	var pos: Vector2 = a["pos"]
	var reach := HitArea.reach_of(float(st.get("attack_reach", 2.0)), float(ev["radius_scale"])) + float(ctx["boss_radius"])
	# 版78：ビーム・爆発・まわりの当たり。当たった所の見た目は、battle_ai_team が出す
	var hspec: Dictionary = ev.get("hit", {})
	if hspec.has("proj"):
		# 版79：飛ぶ物：撃つだけ。当たった時のダメージは battle_skills.gd が数える
		var st0: Dictionary = a["stats"]
		var cfg0: Dictionary = ctx["cfg"]
		var d0 := Damage.damage_amount(float(st0.get("attack_power", 10.0)), float(ctx["attack_multiplier"]) * float(ev["multiplier"]) * float(cfg0["damage_scale"])
			* (float(st0.get("ultimate_scale", 1.0)) if str(ev.get("action", "")) == "ultimate" else 1.0))
		(a["out_events"] as Array).append({"type": "proj", "hit": hspec, "dmg": d0, "action": str(ev.get("action", ""))})
		return 0.0
	if hspec.has("fx"):
		(a["out_events"] as Array).append({"type": "hitfx", "hit": hspec})
	if SkillHits.shape_of(hspec) != "melee":
		if not SkillHits.hits(hspec, pos, act(a).aim, 0.0, ctx["boss"], float(ctx["boss_radius"])):
			return 0.0
	elif bool(act(a).def(str(ev.get("action", ""))).get("sweep_hit", false)):
		# 版72b：駆けぬけながら斬る：始めた所から今の所までの道の、どこかから届けば当たる
		if not HitArea.hits_sweep(a.get("ult_from", pos), pos, ctx["boss"], reach, 0.0):
			return 0.0
	elif (ctx["boss"] as Vector2).distance_to(pos) > reach:
		return 0.0
	var ult_scale := float(st.get("ultimate_scale", 1.0)) if str(ev.get("action", "")) == "ultimate" else 1.0  # 版74：剣士の必殺技は0.7倍
	var dmg := Damage.damage_amount(float(st.get("attack_power", 10.0)), float(ctx["attack_multiplier"]) * float(ev["multiplier"]) * float(cfg["damage_scale"]) * ult_scale)
	a["hits"] = float(a["hits"]) + dmg
	if a.has("hit_events"):
		(a["hit_events"] as Array).append({"dmg": dmg, "action": str(ev.get("action", ""))})
	a["hit_n"] = int(a.get("hit_n", 0)) + 1  # 版69：当たった回数（ボスの怒りを数える）
	(a["gauge"] as Gauge).charge(dmg * float(st.get("gauge_rate", 1.0)))  # 版74：剣士だけ30%速くたまる
	return dmg


## ボスの当たりを受ける。受けたダメージの合計を返す。done：すでに当たった印（キー → true）
static func take_hazards(a: Dictionary, slot: String, hazards: Array, done: Dictionary, multiplier: float) -> float:
	if bool(a["downed"]) or bool(a.get("held", false)) or act(a).invulnerable() or float(a.get("kb_guard", 0.0)) > 0.0 or bool(a.get("vanished", false)):
		return 0.0
	var total := 0.0
	var pos: Vector2 = a["pos"]
	for h in hazards:
		if not bool(h["active"]):
			continue
		var target := str(h["target"])
		if target != "" and target != slot:
			continue
		var key := "%s:%s:%d" % [slot, h["id"], int(h["tick"])]
		if done.has(key):
			continue
		if bool(h["jumpable"]) and is_airborne(a):
			continue
		if not Attacks.inside(h, pos.x, pos.y):
			continue
		done[key] = true
		var dmg := Damage.damage_amount(float(h["power"]), multiplier)
		total += dmg
		a["flash"] = 0.15
		if h.has("stun"):
			a["stun"] = maxf(float(a["stun"]), float(h["stun"]))
		if bool(h.get("grab", false)):
			a["held"] = true
		elif str(h.get("kb", "none")) != "none" and act(a).has_action(str(h["kb"])):
			# ふっ飛ぶ（転んで起き上がるまで、と少しの間は当たらない）
			var acts := act(a)
			var dir := Attacks.knock_dir(h, pos.x, pos.y)
			acts.start(str(h["kb"]), dir, 0.0, true)
			a["face"] = -dir
			a["kb_guard"] = float(acts.def(str(h["kb"])).get("duration_sec", 0.5)) + float(acts.cfg.get("kb_guard_sec", 0.6))
			break
	if total > 0.0:
		a["hp"] = maxf(0.0, float(a["hp"]) - total)
		if float(a["hp"]) <= 0.0:
			a["downed"] = true
	return total
