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
		out["spin"] = float(att.get("spin", 0.0)) * (w if not bool(att.get("full_spin", false)) else 1.0)
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
static func arm_out_t(mv: Dictionary) -> float:
	return float(mv.get("sword_arm_out", 0.45))


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
			# 横振り：バットを持ち上げながら、体を右へひねって（ため）→ バットを腰の高さに下ろし、体ごと一気に右から左へなぎはらう
			# フェイント（feint_sec）：ためたあと、一度ふりかけて止め、もう一度ためてから本当に振る
			var f0 := float(k.get("feint_sec", 0.0))
			if f0 <= 0.0:
				return _hswing(an, u, float(k["windup_sec"]), float(k["swing_sec"]), 1.0, mv, _fade(u, dur))
			var w0 := float(k["feint_at"])
			var ue := u if u < w0 else (w0 if u < w0 + f0 else u - f0)
			var hs := _hswing(an, ue, w0, float(k["swing_sec"]), 1.0, mv, _fade(u, dur))
			if u >= w0 and u < w0 + f0:
				var twitch := sin(PI * (u - w0) / f0)
				hs["spin"] = float(hs["spin"]) + deg_to_rad(float(mv.get("hswing_coil_deg", 95.0)) * 0.6 * twitch * twitch)
			return hs
		Attacks.BAT_V:
			# 縦振り：頭の上へふりかぶって、ためる → 前へたたきつける（当たる瞬間に、バットの先が前の地面に来る）
			var w2 := float(k["windup_sec"])
			var ct2 := BossAnim.remap(u, [[0.0, 0.0], [w2 - 0.16, 0.25, "linear"], [w2, float(mv.get("sword_ground", 0.47))], [w2 + 0.4, float(mv.get("sword_ground", 0.47)) + 0.04], [dur, 1.35]])
			var ln := BossAnim.remap(u, [[0.0, 0.0], [w2 - 0.16, -8.0, "linear"], [w2, 8.0], [w2 + 0.4, 8.0], [dur, 0.0]])
			var fix := deg_to_rad(float(mv.get("bat_v_turn_deg", 0.0))) * smoothstep(0.0, w2, u)
			return {"pose": an.sample("Sword_Attack", ct2), "weight": _fade(u, dur), "spin": fix, "deltas": {"spine05": BossAnim.lean(ln)}}
		Attacks.WALK_SWING:
			# 歩きながら振る：足は歩き、上半身で横振り（右から左）を何回も。振るたびに、また右へひねってためる
			var n := int(k["swings"])
			var tele := float(k["tele_sec"])
			var i := 0
			for j in n:
				if u >= Attacks.swing_time(j, k) - tele:
					i = j
			var lu := u - (Attacks.swing_time(i, k) - tele)
			var hs := _hswing(an, lu, tele, float(k["hit_sec"]), 1.0, mv, _fade(u, dur))
			# 前の振りの終わりから、なめらかにつなぐ（いきなり構えにもどらない）
			var blend_sec := float(mv.get("swing_link_sec", 0.18))
			if i > 0 and lu < blend_sec:
				var prev := _hswing(an, lu + float(k["every_sec"]), tele, float(k["hit_sec"]), 1.0, mv, 1.0)
				var f := smoothstep(0.0, blend_sec, lu)
				hs["pose"] = an.blend(prev["pose"], hs["pose"], f)
				hs["spin"] = lerpf(float(prev["spin"]), float(hs["spin"]), f)
				var pd: Dictionary = prev["deltas"]
				var cd: Dictionary = hs["deltas"]
				for key in cd:
					cd[key] = Basis((pd[key] as Basis).get_rotation_quaternion().slerp((cd[key] as Basis).get_rotation_quaternion(), f))
			# 低く振る（歩きながらでも、腰の高さを通る）
			(hs["deltas"] as Dictionary)["spine03"] = BossAnim.lean(float(mv.get("walk_swing_lean_deg", 22.0)))
			hs["only"] = an.torso
			# 歩きの脚・根はそのままなので、腰のひねりが足りない分を、体ごとの回転で足す（振りの道を、横振りとそろえる）
			hs["spin"] = float(hs["spin"]) + deg_to_rad(float(mv.get("walk_swing_turn_deg", 60.0))) * _fade(u, dur)
			return hs
		Attacks.BAT_SPIN:
			# 回転斬り：ふりかぶって、腕を横にのばしたところで止め、体ごと何回も回る → バットを地面に突き立てて、すき
			var wind := float(k["windup_sec"])
			var finish := float(k.get("finish_sec", 0.0))
			var active_end := dur - float(k["recover_sec"]) - finish
			if u >= active_end + 0.15 and finish > 0.0:
				var fk := smoothstep(active_end + 0.15, active_end + 0.45, u)
				var plant := an.blend(an.sample("Sword_Attack", arm_out_t(mv)), an.sample("Sword_Attack", float(mv.get("sword_ground", 0.45))), fk)
				var spin_t0 := active_end - wind
				var turns0 := maxf(1.0, roundf(float(k["spin_deg_per_sec"]) * spin_t0 / 360.0))
				return {"pose": plant, "weight": _fade(u, dur), "spin": turns0 * TAU, "full_spin": true,
					"deltas": {"spine05": BossAnim.lean(22.0 * fk), "spine03": BossAnim.lean(10.0 * fk), "head": BossAnim.lean(-12.0 * fk)}}
			var arm_out := float(mv.get("sword_arm_out", 0.4))
			var ct4 := BossAnim.remap(u, [[0.0, 0.0], [wind * 0.6, 0.25], [wind, arm_out], [active_end, arm_out], [dur, 0.0]])
			var spin_t := active_end - wind
			var turns := maxf(1.0, roundf(float(k["spin_deg_per_sec"]) * spin_t / 360.0))
			var p := clampf((u - wind) / maxf(spin_t, 0.01), 0.0, 1.0)
			var lean_out := 12.0 * sin(PI * p)
			return {"pose": an.sample("Sword_Attack", ct4), "weight": _fade(u, dur), "spin": turns * TAU * smoothstep(0.0, 1.0, p), "full_spin": true,
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
			return {"pose": an.sample("Jump_Start", ct5), "weight": _fade(u, dur), "spin": twist + TAU * (p5 * p5 * (3.0 - 2.0 * p5)), "full_spin": true, "whip": whip,
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
		Attacks.THRUST:
			# 前方突き：バットを腰で前へ構え、体をうしろへひねって引く（ため）→ 一気に前へ突き出す → のびたまま止まる（すき）
			var w8 := float(k["windup_sec"])
			var level := float(mv.get("sword_level", 0.45))
			var tw8 := BossAnim.remap(u, [[0.0, 0.0], [w8 - 0.1, float(mv.get("thrust_pull_deg", 25.0)), "linear"], [w8, float(mv.get("thrust_yaw_deg", 12.0))], [w8 + 0.5, float(mv.get("thrust_yaw_deg", 12.0))], [dur, 0.0]])
			var reach8 := BossAnim.remap(u, [[0.0, 0.0], [w8 - 0.1, 12.0, "linear"], [w8, 30.0], [w8 + 0.5, 30.0], [dur, 0.0]])
			var ln8 := BossAnim.remap(u, [[0.0, 0.0], [w8 - 0.1, -8.0, "linear"], [w8 + float(k["hit_sec"]), 20.0], [w8 + 0.5, 20.0], [dur, 0.0]])
			return {"pose": an.sample("Sword_Attack", level), "weight": _fade(u, dur), "spin": deg_to_rad(tw8 * 0.5),
				"deltas": {"spine02": BossAnim.yaw(tw8 * 0.5), "upperarm01.R": BossAnim.fwd(reach8), "spine05": BossAnim.lean(ln8)}}
		Attacks.BAT_THROW:
			# バット投げ：頭の上へふりかぶる（ため）→ 前へ投げる → 手を前へのばしたまま待つ → もどってきたバットを受けとる
			var w9 := float(k["windup_sec"])
			var catch := w9 + float(k["out_sec"]) + float(k["back_sec"])
			var ct9 := BossAnim.remap(u, [[0.0, 0.0], [w9 - 0.15, 0.25, "linear"], [w9 + 0.1, float(mv.get("sword_hit", 0.47))], [w9 + 0.4, 0.62], [catch - 0.2, 0.62], [catch, 0.45], [dur, 0.0]])
			var tw9 := BossAnim.remap(u, [[0.0, 0.0], [w9 - 0.15, 30.0, "linear"], [w9 + 0.1, -20.0], [catch, 0.0]])
			return {"pose": an.sample("Sword_Attack", ct9), "weight": _fade(u, dur), "deltas": {"spine02": BossAnim.yaw(tw9), "spine05": BossAnim.lean(BossAnim.remap(u, [[0.0, 0.0], [w9 - 0.15, -10.0], [w9 + 0.1, 15.0], [catch, 5.0], [dur, 0.0]]))}}
		Attacks.SPIN_CHARGE:
			# 回転突進：しゃがんでバットを横へ（ため）→ 回りながら走る（体の回りは、道の計算から）→ 止まって、ふらふら（すき）
			var w10 := float(k["windup_sec"])
			var run_end := w10 + float(k["run_sec"])
			var arm := an.sample("Sword_Attack", arm_out_t(mv))
			if u < w10:
				var crouch_p := an.sample("Jump_Start", float(mv.get("crouch_t", 0.3)) * smoothstep(0.0, w10 * 0.6, u))
				return {"pose": an.blend(crouch_p, arm, 0.6, an.upper), "weight": _fade(u, dur)}
			if u < run_end:
				return {"pose": arm, "weight": _fade(u, dur), "deltas": {"spine05": BossAnim.lean(12.0)}}
			var dz := smoothstep(run_end, run_end + 0.3, u) * (1.0 - smoothstep(dur - 0.4, dur, u))
			var sway := sin((u - run_end) * 7.0)
			return {"pose": base, "weight": _fade(u, dur), "deltas": {"spine05": BossAnim.roll(14.0 * sway * dz) * BossAnim.lean(10.0 * dz), "head": BossAnim.roll(-18.0 * sway * dz),
				"upperarm01.L": BossAnim.raise_side("L", 25.0 * dz), "upperarm01.R": BossAnim.raise_side("R", 25.0 * dz)}}
		Attacks.JUMP_SLAM:
			# ジャンプ落下：しゃがむ（ため）→ 跳ぶ（ひざを曲げて、バットを頭の上へ）→ 落ちる → 着地でしゃがみこむ（すき）→ 立ち上がる
			var cr := float(k["crouch_sec"])
			var land := cr + float(k["air_sec"])
			if u < cr:
				return {"pose": an.sample("Jump_Start", float(mv.get("crouch_t", 0.3)) * smoothstep(0.0, cr, u)), "weight": _fade(u, dur)}
			if u < land:
				var air := an.sample("Jump", 0.35)
				var up := an.sample("Sword_Attack", 0.25)
				return {"pose": an.blend(air, up, 1.0, an.upper), "weight": 1.0}
			var rec := BossAnim.remap(u, [[land, 0.3], [land + 0.6, 0.3], [dur, 0.0]])
			var down := an.blend(an.sample("Jump_Start", rec), an.sample("Sword_Attack", float(mv.get("sword_ground", 0.45))), 1.0, an.upper)
			return {"pose": down, "weight": _fade(u, dur), "deltas": {"spine05": BossAnim.lean(18.0 * (1.0 - smoothstep(land + 0.6, dur, u)))}}
		Attacks.SAKE_RAIN, Attacks.SAKE_DROP, Attacks.FIRE_FEST:
			# 酒瓶を投げる：左手の一升瓶を、うしろ下へ引いて（ため）→ 下から上へ一気にふり上げて放る → 下ろす
			# 火祭りは、瓶のあとにライターも同じように放る。最後はライターをしまって、構え直す
			var times: Array = []
			if kind == Attacks.SAKE_RAIN:
				for t in int(k["throws"]):
					times.append(Attacks.sake_throw_time(t, k))
			else:
				for i in int(k["bottles"]):
					times.append(float(k["first_sec"]) + float(i) * float(k["every_sec"]))
				if kind == Attacks.FIRE_FEST:
					times.append(float(k["lighter_throw_sec"]))
			var arm := 0.0
			var lean_b := 0.0
			var short := float(k.get("every_sec", 1.0)) < 0.5
			for t0 in times:
				var lt := u - float(t0)
				var pre := 0.2 if short else 0.45
				if lt > -pre and lt < 0.9:
					arm = BossAnim.remap(lt, [[-pre, 0.0], [-pre * 0.3, -45.0, "linear"], [0.0, 160.0], [0.3, 140.0], [0.9, 0.0]])
					lean_b = BossAnim.remap(lt, [[-pre, 0.0], [-pre * 0.3, 10.0, "linear"], [0.0, -14.0], [0.9, 0.0]])
			return {"pose": base, "weight": _fade(u, dur),
				"deltas": {"upperarm01.L": BossAnim.fwd(arm) * BossAnim.raise_side("L", 15.0), "lowerarm01.L": BossAnim.fwd(clampf(arm * 0.15, 0.0, 30.0)),
					"spine05": BossAnim.lean(lean_b), "head": BossAnim.lean(-0.1 * maxf(arm, 0.0))}}
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
			return {"pose": base, "weight": 1.0, "spin": turns7 * TAU * smoothstep(0.0, 1.0, p7), "full_spin": true,
				"deltas": {"upperarm01.L": BossAnim.raise_side("L", 80.0 * open), "upperarm01.R": BossAnim.raise_side("R", 80.0 * open),
					"lowerarm01.L": BossAnim.raise_side("L", 10.0 * open), "lowerarm01.R": BossAnim.raise_side("R", 10.0 * open), "spine05": BossAnim.lean(10.0 * open)}}
		Attacks.FLYER_STORM:
			# 酒の大雨：両腕を高く上げて、空へ酒をまく
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


## 横振りの動き（lu：振りの始まりからの秒、wind：ための秒、swing：振りぬく秒、dir：1 で右から左、-1 で左から右）
## 体のひねりは、足もと（体ごと）・腰・胸に分ける。バットの先は、ひねりの角度＋もとの向き（ほぼ正面）を通る
static func _hswing(an: BossAnim, lu: float, wind: float, swing: float, dir: float, mv: Dictionary, w: float) -> Dictionary:
	var level := float(mv.get("sword_level", 0.45))
	var raise := an.sample("Sword_Attack", BossAnim.remap(lu, [[0.0, 0.0], [wind * 0.6, 0.25]]))
	var low := an.sample("Sword_Attack", level)
	var pose := an.blend(raise, low, smoothstep(wind * 0.5, wind, lu))
	var coil := -float(mv.get("hswing_coil_deg", 95.0)) * dir
	var finish := float(mv.get("hswing_finish_deg", 85.0)) * dir
	var tw := BossAnim.remap(lu, [[0.0, 0.0], [wind, coil, "linear"], [wind + swing, finish], [wind + swing + 0.45, finish * 0.6]])
	return {"pose": pose, "weight": w, "spin": deg_to_rad(tw * 0.5),
		"deltas": {"spine05": BossAnim.yaw(tw * 0.25), "spine02": BossAnim.yaw(tw * 0.25)}}
