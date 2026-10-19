extends RefCounted
## ボスの動きの組み立て（振り付け）。画面を持たない（姿勢を計算して返すだけ）。
## 土台：待ち（Idle）と歩き（Walk）を、歩く速さでまぜる。歩きの進みは、歩いた道のりで決める（足がすべらない）。
## 攻撃：攻撃が始まってからの秒 u で、動き素材の時刻を決める（boss_attacks.gd の予告・当たりの時刻と、振る瞬間が合う）。
##   - 横振り・縦振り・歩きながら振る：剣士の「Sword_Attack」（ふりかぶって、横から前へ斬りおろす）
##   - つかみ：左手の「Punch」でのばして、体を前へかがめる → 持ち上げる → うしろへ引いて、前へ投げる
##   - 回転斬り：Sword_Attack の「腕を横にのばした」ところで止めて、体ごと回る
##   - しっぽ回し：Jump_Start の「しゃがむ」ところで止めて、1回まわる
##   - チラシ：左手の「Spell」で、投げる腕をふる。台風：両腕を横に広げて回る。必殺技：両腕を上げる／前へかざす
##   - よろけ：Death で倒れ、Death を逆に流して起き上がる
## 足し算の回転（ひねり・前かがみ）は boss_anim.gd の add で書く（モデルの座標・度）。
## 数値（動き素材の時刻など）は data/boss_model.json の moves

const BossAnim := preload("res://scripts/boss/boss_anim.gd")
const Attacks := preload("res://scripts/combat/boss_attacks.gd")


## st：{clock, walk_dist, walk_speed, kind（攻撃の種類。なければ ""）, u, k（攻撃の設定）, grab（{} か {phase: "hold"/"throw", t, throw_sec, release_sec}）,
##      flinch（0〜1）, awake, stagger_t, stagger_sec, stagger_swap_sec, aim_yaw（つかみの手を向ける角度）, aim_reach（0〜1）}
## 戻り値：{pose, spin（体ごと回る角度）, whip（しっぽをのばす具合）}
static func build_pose(an: BossAnim, st: Dictionary, cfg: Dictionary) -> Dictionary:
	var mv: Dictionary = cfg.get("moves", {})
	var clock := float(st.get("clock", 0.0))
	# ---- 土台：待ち＋歩き ----
	var idle := an.sample("Idle", clock * float(mv.get("idle_speed", 0.9)))
	var cycle := float(mv.get("walk_cycle_m", 3.6))
	var walk_t := float(st.get("walk_dist", 0.0)) / maxf(cycle, 0.1) * an.clip_len("Walk")
	var walk := an.sample("Walk", walk_t)
	var walk_w := clampf(float(st.get("walk_speed", 0.0)) / float(mv.get("walk_full_speed", 1.6)), 0.0, 1.0)
	var base := an.blend(idle, walk, walk_w)
	var out := {"pose": base, "spin": 0.0, "whip": 0.0}
	var deltas := {}
	var off := Vector3.ZERO
	var stagger := float(st.get("stagger_t", -1.0))
	if stagger >= 0.0:
		# よろけ：倒れる → しばらく倒れたまま → 起き上がる（倒れる動きを逆に流す）
		var fall := float(mv.get("death_fall", 1.25))
		var swap := float(st.get("stagger_swap_sec", 2.2))
		var total := float(st.get("stagger_sec", 3.4))
		var ct := fall
		if stagger < fall:
			ct = stagger
		elif stagger > swap:
			ct = fall * (1.0 - clampf((stagger - swap) / maxf(total - swap, 0.1), 0.0, 1.0))
		out["pose"] = an.sample("Death", ct)
		return out
	var kind := str(st.get("kind", ""))
	var grab: Dictionary = st.get("grab", {})
	if kind != "" or not grab.is_empty():
		var att := _attack(an, kind, float(st.get("u", 0.0)), st.get("k", {}), st, mv, base)
		var w := float(att.get("weight", 1.0))
		var only: Dictionary = att.get("only", {})
		out["pose"] = an.blend(base, att["pose"], w, only)
		out["spin"] = float(att.get("spin", 0.0))
		out["whip"] = float(att.get("whip", 0.0))
		var ad: Dictionary = att.get("deltas", {})
		for key in ad:
			deltas[key] = _scale_delta(ad[key], w)
		off += (att.get("offset", Vector3.ZERO) as Vector3) * w
	# ---- 覚醒：前かがみで、ゆらゆら（酔っ払い）。腕を少し広げる ----
	if bool(st.get("awake", false)):
		var sway := sin(clock * 1.3)
		_mul(deltas, "spine05", BossAnim.lean(float(mv.get("awake_lean", 14.0))) * BossAnim.roll(sway * 5.0))
		_mul(deltas, "spine03", BossAnim.lean(6.0))
		_mul(deltas, "head", BossAnim.lean(-14.0) * BossAnim.roll(-sway * 4.0))
		_mul(deltas, "upperarm01.L", BossAnim.raise_side("L", 14.0))
		_mul(deltas, "upperarm01.R", BossAnim.raise_side("R", 14.0))
	# ---- ダメージを受けた瞬間：上半身を少しのけぞらせる ----
	var fl := float(st.get("flinch", 0.0))
	if fl > 0.0:
		_mul(deltas, "spine03", BossAnim.lean(-float(mv.get("flinch_deg", 9.0)) * fl))
		_mul(deltas, "head", BossAnim.lean(-6.0 * fl))
	out["pose"] = an.add(out["pose"], deltas, off)
	return out


static func _mul(d: Dictionary, bone: String, b: Basis) -> void:
	d[bone] = b * (d[bone] as Basis) if d.has(bone) else b


## 回転を w の割合だけかける（0 で回さない）
static func _scale_delta(b: Basis, w: float) -> Basis:
	if w >= 1.0:
		return b
	return Basis(Quaternion.IDENTITY.slerp(b.get_rotation_quaternion(), clampf(w, 0.0, 1.0)))


## 攻撃のはじめと終わりで、土台の動きと、なめらかにまぜる割合
static func _fade(u: float, dur: float, fin: float = 0.14, fout: float = 0.3) -> float:
	return smoothstep(0.0, fin, u) * (1.0 - smoothstep(dur - fout, dur, u))


static func _attack(an: BossAnim, kind: String, u: float, k: Dictionary, st: Dictionary, mv: Dictionary, base: Dictionary) -> Dictionary:
	var grab: Dictionary = st.get("grab", {})
	if not grab.is_empty():
		return _grab_held(an, grab, st, mv)
	var dur := float(k.get("duration", 1.0))
	var hit := float(mv.get("sword_hit", 0.47))  # Sword_Attack で、刃が前を通る時刻
	match kind:
		Attacks.BAT_H:
			# 横振り：ゆっくり横へふりかぶる（ため）→ 一気に横から前へ → 余韻
			var w := float(k["windup_sec"])
			var sw := float(k["swing_sec"])
			var ct := BossAnim.remap(u, [[0.0, 0.0], [w * 0.55, 0.26], [w, hit - 0.08, "linear"], [w + sw, hit + 0.06], [w + sw + 0.3, 0.68], [dur, 1.3]])
			var tw := BossAnim.remap(u, [[0.0, 0.0], [w, 35.0, "linear"], [w + sw, -40.0], [dur, 0.0]])
			return {"pose": an.sample("Sword_Attack", ct), "weight": _fade(u, dur), "deltas": {"spine02": BossAnim.yaw(tw), "spine05": BossAnim.yaw(tw * 0.5)}}
		Attacks.BAT_V:
			# 縦振り：頭の上へふりかぶって、ためる → 前へたたきつける（当たる瞬間に、刃が前を通る）
			var w2 := float(k["windup_sec"])
			var ct2 := BossAnim.remap(u, [[0.0, 0.0], [w2 - 0.14, 0.25, "linear"], [w2, hit + 0.03], [w2 + 0.35, 0.66], [dur, 1.35]])
			var ln := BossAnim.remap(u, [[0.0, 0.0], [w2 - 0.14, -8.0, "linear"], [w2, 18.0], [w2 + 0.35, 18.0], [dur, 0.0]])
			return {"pose": an.sample("Sword_Attack", ct2), "weight": _fade(u, dur), "deltas": {"spine05": BossAnim.lean(ln)}}
		Attacks.WALK_SWING:
			# 歩きながら振る：足は歩き、上半身だけ Sword_Attack を何回も
			var n := int(k["swings"])
			var tele := float(k["tele_sec"])
			var i := 0
			for j in n:
				if u >= Attacks.swing_time(j, k) - tele:
					i = j
			var lu := u - (Attacks.swing_time(i, k) - tele)
			var ct3 := BossAnim.remap(lu, [[0.0, 0.12], [tele - 0.08, hit - 0.08, "linear"], [tele + float(k["hit_sec"]), hit + 0.08], [tele + 0.45, 0.62]])
			var side := 1.0 if i % 2 == 0 else -1.0
			var tw3 := BossAnim.remap(lu, [[0.0, 0.0], [tele - 0.08, 30.0 * side, "linear"], [tele + float(k["hit_sec"]), -30.0 * side], [tele + 0.45, 0.0]])
			return {"pose": an.sample("Sword_Attack", ct3), "weight": _fade(u, dur), "only": an.upper, "deltas": {"spine02": BossAnim.yaw(tw3)}}
		Attacks.BAT_SPIN:
			# 回転斬り：ふりかぶって、腕を横にのばしたところで止め、体ごと何回も回る
			var wind := float(k["windup_sec"])
			var active_end := dur - float(k["recover_sec"])
			var arm_out := float(mv.get("sword_arm_out", 0.4))
			var ct4 := BossAnim.remap(u, [[0.0, 0.0], [wind * 0.6, 0.25], [wind, arm_out], [active_end, arm_out], [dur, 0.0]])
			var spin_t := active_end - wind
			var turns := maxf(1.0, roundf(float(k["spin_deg_per_sec"]) * spin_t / 360.0))
			var p := clampf((u - wind) / maxf(spin_t, 0.01), 0.0, 1.0)
			var lean_out := 12.0 * sin(PI * p)
			return {"pose": an.sample("Sword_Attack", ct4), "weight": _fade(u, dur), "spin": turns * TAU * smoothstep(0.0, 1.0, p),
				"deltas": {"spine05": BossAnim.roll(-lean_out), "upperarm01.R": BossAnim.raise_side("R", 25.0 * smoothstep(0.0, wind, u))}}
		Attacks.TAIL_SPIN:
			# しっぽ回し：しゃがんで、反対へひねる（ため）→ 一気に1回まわる
			var w5 := float(k["windup_sec"])
			var sweep := float(k["sweep_sec"])
			var crouch := float(mv.get("crouch_t", 0.3))
			var ct5 := BossAnim.remap(u, [[0.0, 0.0], [w5, crouch], [w5 + sweep, crouch], [dur, 0.0]])
			var p5 := clampf((u - w5) / sweep, 0.0, 1.0)
			var twist := -0.6 * smoothstep(0.0, w5, u) * (1.0 - p5)
			var whip := smoothstep(0.0, w5 * 0.8, u) * (1.0 - smoothstep(w5 + sweep, dur, u))
			return {"pose": an.sample("Jump_Start", ct5), "weight": _fade(u, dur), "spin": twist + TAU * (p5 * p5 * (3.0 - 2.0 * p5)), "whip": whip,
				"deltas": {"spine05": BossAnim.lean(18.0 * whip)}}
		Attacks.GRAB:
			# つかみ：ねらう人のほうへ体を向け、左手をのばしながら、前へかがむ。つかめなければ、手をもどす
			var f := float(k["follow_sec"])
			var hf := f + float(k["lock_sec"])
			var reach := float(mv.get("punch_reach", 0.3))
			var ct6 := BossAnim.remap(u, [[0.0, 0.0], [f, 0.08], [hf, reach], [hf + 0.4, reach], [hf + 1.1, 0.85]])
			var bend := BossAnim.remap(u, [[0.0, 0.0], [f, 10.0], [hf, float(mv.get("grab_bend_deg", 42.0))], [hf + 0.4, float(mv.get("grab_bend_deg", 42.0))], [hf + 1.2, 0.0]])
			var ay := float(st.get("aim_yaw", 0.0))
			return {"pose": an.sample("Punch", ct6), "weight": _fade(u, dur),
				"deltas": {"spine05": BossAnim.lean(bend * 0.6) * BossAnim.yaw(rad_to_deg(ay) * 0.5), "spine03": BossAnim.lean(bend * 0.4) * BossAnim.yaw(rad_to_deg(ay) * 0.5),
					"upperarm01.L": BossAnim.fwd(-15.0 * smoothstep(f, hf, u))}}
		Attacks.FLYERS:
			# チラシ：左手で、次々に投げる（腕をうしろへ引いて、前へふる）
			var count := int(k["count"])
			var s0 := float(k["start_sec"])
			var gap := float(k["spread_sec"]) / float(maxi(count - 1, 1))
			var ph := clampf((u - s0 + gap * 0.5) / gap, -1.0, float(count))
			var swing := sin(fposmod(ph, 1.0) * TAU) if u > s0 - gap * 0.5 and u < s0 + float(k["spread_sec"]) + gap * 0.5 else 0.0
			return {"pose": an.sample("Spell", 0.25), "weight": _fade(u, dur),
				"deltas": {"upperarm01.L": BossAnim.fwd(25.0 * swing), "spine02": BossAnim.yaw(-12.0 * swing)}}
		Attacks.TYPHOON:
			var wind7 := float(k["windup_sec"])
			var end7 := dur - float(k["recover_sec"])
			var spin_t7 := end7 - wind7
			var turns7 := roundf(float(k["spin_deg_per_sec"]) * spin_t7 / 360.0)
			var p7 := clampf((u - wind7) / maxf(spin_t7, 0.01), 0.0, 1.0)
			var open := smoothstep(0.0, wind7, u) * (1.0 - smoothstep(end7, dur, u))
			return {"pose": base, "weight": 1.0, "spin": turns7 * TAU * smoothstep(0.0, 1.0, p7),
				"deltas": {"upperarm01.L": BossAnim.raise_side("L", 80.0 * open), "upperarm01.R": BossAnim.raise_side("R", 80.0 * open),
					"lowerarm01.L": BossAnim.raise_side("L", 10.0 * open), "lowerarm01.R": BossAnim.raise_side("R", 10.0 * open), "spine05": BossAnim.lean(10.0 * open)}}
		Attacks.FLYER_STORM:
			var up := smoothstep(0.0, 0.5, u) * (1.0 - smoothstep(dur - 0.5, dur, u))
			var shake := sin(u * 14.0) * 8.0 * up
			return {"pose": base, "weight": 1.0, "deltas": {"upperarm01.L": BossAnim.raise_side("L", 150.0 * up + shake), "upperarm01.R": BossAnim.raise_side("R", 150.0 * up - shake),
				"head": BossAnim.lean(-20.0 * up), "spine05": BossAnim.lean(-8.0 * up)}}
		Attacks.HAND_SWEEP:
			var up2 := smoothstep(0.0, 0.4, u) * (1.0 - smoothstep(dur - 0.5, dur, u))
			return {"pose": an.sample("Spell", 0.25), "weight": _fade(u, dur), "deltas": {"upperarm01.R": BossAnim.fwd(70.0 * up2), "spine05": BossAnim.lean(8.0 * up2)}}
	return {"pose": base, "weight": 0.0}


## つかんだあと：持ち上げて（にげる連打の間、ゆさぶる）→ うしろへ引いて、前へ投げる
static func _grab_held(an: BossAnim, grab: Dictionary, st: Dictionary, mv: Dictionary) -> Dictionary:
	var reach := float(mv.get("punch_reach", 0.3))
	var pose := an.sample("Punch", reach)
	var t := float(grab.get("t", 0.0))
	var lift := smoothstep(0.0, float(mv.get("grab_lift_sec", 0.35)), t)
	var bend := float(mv.get("grab_bend_deg", 42.0)) * (1.0 - lift)
	var arm := 75.0 * lift
	var shake := sin(t * 18.0) * 6.0 * lift
	var tw := 0.0
	var lean_extra := 0.0
	if str(grab.get("phase", "hold")) == "throw":
		# 投げ：うしろへ大きく引く（ため）→ 前へふりぬく（手をはなす）→ 余韻
		var tt := float(grab.get("throw_t", 0.0))
		var rel := float(grab.get("release_sec", 0.3))
		var total := float(grab.get("throw_sec", 0.55))
		arm = BossAnim.remap(tt, [[0.0, 75.0], [rel * 0.6, 150.0, "linear"], [rel, 40.0], [total, -10.0]])
		tw = BossAnim.remap(tt, [[0.0, 0.0], [rel * 0.6, -35.0, "linear"], [rel, 25.0], [total, 10.0]])
		lean_extra = BossAnim.remap(tt, [[0.0, 0.0], [rel * 0.6, -10.0, "linear"], [rel, 20.0], [total, 8.0]])
		shake = 0.0
	return {"pose": pose, "weight": 1.0,
		"deltas": {"spine05": BossAnim.lean(bend * 0.6 + lean_extra) * BossAnim.yaw(tw), "spine03": BossAnim.lean(bend * 0.4) * BossAnim.yaw(tw * 0.6),
			"upperarm01.L": BossAnim.fwd(arm + shake)}}
