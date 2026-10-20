extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v93.gd
## 版93：ロビーのキャラの動きを、それぞれの A攻撃（戦いの normal）に。
## 版94（ユーザーの指示で変更）：ふだんは静止。前に持ってこられた時だけ A攻撃を1回して静止にもどる。後ろへ行ったら静止。
## 確かめること：
##   1. 対応：9人すべて、戦いの A攻撃と同じ動き（anim と speed）。別のキャラの動きを使い回していない
##   2. 出した時：前も後ろも静止（はじめて出した時は攻撃しない）
##   3. 前に持ってくると：そのキャラの A攻撃を1回 → 静止にもどる（くり返さない）。後ろは静止（9人とも）
##   4. 後ろへ行ったら、すぐ静止（攻撃の途中でも）。かわりに前に来た人は自分の A攻撃
##   5. 作り直さない：入れかえ・同じ編成をもう一度でも、キャラの形・再生係を作り直さない。つなぎ（signal）は1つだけ
##   6. 場所：くり返しても、キャラの場所（holder）とキャラの形の場所は動かない。骨の腰の位置も、最初と最後でほぼ同じ
##   7. 戦いの処理は呼ばない：ロビーは動きを流すだけ（当たり・音・光の関数を呼ばない）
##   8. 動きがないキャラ：待ちの動きのまま・エラーなし・記録される
##   9. ロビーに入りなおす（作り直す）：また正しく動く

const LobbyStage := preload("res://scripts/flow/lobby_stage.gd")
const CharacterData := preload("res://scripts/characters/character_data.gd")
const Actions := preload("res://scripts/combat/player_actions.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func unit_of(st: Node, id: String) -> Dictionary:
	for u in st.units:
		if str(u["id"]) == id:
			return u
	return {}


## そのキャラの A攻撃の動きの名前（再生係の中の名前）
func attack_anim(def: Dictionary) -> String:
	var acts: Dictionary = Actions.config_for(str(def["id"]))["actions"]
	return CharacterData.animation_for(def, str(acts["normal"]["steps"][0]["anim"]))


func _initialize() -> void:
	var chars := CharacterData.load_config()
	var ids: Array = []
	for c in chars["characters"]:
		ids.append(str(c["id"]))
	var st: Node3D = LobbyStage.new()
	st.setup(chars)
	root.add_child(st)

	# ---- 1. 対応 ----
	var anims := {}
	var all_ok := true
	for id in ids:
		var def := CharacterData.find(chars, id)
		var a: Dictionary = st.attack_for(id)
		var acts: Dictionary = Actions.config_for(id)["actions"]
		var want: Dictionary = acts["normal"]["steps"][0]
		var ok: bool = str(a.get("anim", "")) == str(want["anim"]) and is_equal_approx(float(a.get("speed", 0.0)), float(want["speed"]))
		all_ok = all_ok and ok
		anims[id] = attack_anim(def)
		print("     %s：%s（%s）→ 動き %s・速さ %.1f" % [id, str(acts["normal"].get("name", "")), str(acts["normal"].get("label", "")), anims[id], float(a.get("speed", 0.0))])
	check(all_ok, "9人すべて、戦いの A攻撃と同じ動き・速さ（char_actions.json・剣士は actions.json の normal）")
	var uniq := {}
	for id in anims:
		uniq[anims[id]] = true
	check(uniq.size() == ids.size(), "動きは全員ちがう（別のキャラの動きを使い回していない。%d 種類）" % uniq.size())

	# ---- 2. 出した時：みんな静止（版94） ----
	var still_ok := true
	var groups := [ids.slice(0, 4), ids.slice(4, 8), [ids[8], ids[0], ids[1], ids[2]]]
	var first_g := true
	for g in groups:
		st.set_team(g)
		st.finish()
		for id in g:
			var u := unit_of(st, id)
			var v: Node = u.get("view")
			var p: AnimationPlayer = v.get("player")
			var front: bool = int(u["slot"]) == 0
			# 2回目からの編成では、新しく前に来た人は A攻撃をしてよい（自分の動きなら）
			var ok: bool = not p.is_playing() and str(v.get("current_action")) == "idle"
			if not ok and front and not first_g:
				ok = p.current_animation == str(anims[id])
			if not ok:
				still_ok = false
				print("     動いている：", id, " ", p.current_animation, " ", v.get("current_action"))
		first_g = false
	check(still_ok, "ロビーに出した時は、前も後ろも静止（9人。はじめて出した時は攻撃しない）。後ろは、いつも静止")

	# ---- 3. 前に持ってくると、そのキャラの A攻撃を1回 → 静止（9人とも） ----
	var once_ok := true
	for id in ids:
		var others: Array = []
		for k in ids:
			if k != id and others.size() < 3:
				others.append(k)
		var cur_main := str(st.units[0]["id"])
		if cur_main == id:
			# いま前にいる人は、いったん後ろへ
			st.set_team([others[0], id, others[1], others[2]])
			st.finish()
		st.set_team([id] + others)
		st.finish()
		var u := unit_of(st, id)
		var v: Node = u["view"]
		var p: AnimationPlayer = v.get("player")
		var attacking: bool = p.is_playing() and str(v.get("current_action")) == "step" and p.current_animation == str(anims[id])
		# 動きを最後まで進める → 静止にもどる（くり返さない）
		for i in 90:
			p.advance(1.0 / 60.0)
		var back_still: bool = not p.is_playing() and str(v.get("current_action")) == "idle"
		for i in 60:
			p.advance(1.0 / 60.0)
		var stays: bool = not p.is_playing() and str(v.get("current_action")) == "idle"
		if not (attacking and back_still and stays):
			once_ok = false
			print("     ずれ：", id, " 攻撃=", attacking, " 静止にもどる=", back_still, " そのまま=", stays)
		# 後ろの人は静止のまま
		for w in st.units:
			if int(w["slot"]) != 0:
				var vv: Node = w["view"]
				if (vv.get("player") as AnimationPlayer).is_playing():
					once_ok = false
					print("     後ろが動いている：", w["id"])
	check(once_ok, "前に持ってこられた時だけ、そのキャラの A攻撃を1回 → 静止にもどる（くり返さない）。後ろは静止（9人）")

	# ---- 4. 後ろへ行ったら、すぐ静止 ----
	var front: String = str(st.units[0]["id"])
	var back1: String = str(st.units[1]["id"])
	st.set_team([back1, front, str(st.units[2]["id"]), str(st.units[3]["id"])])
	st.finish()
	var uf := unit_of(st, front)
	var vf: Node = uf["view"]
	var ub := unit_of(st, back1)
	var vb: Node = ub["view"]
	check(not (vf.get("player") as AnimationPlayer).is_playing() and str(vf.get("current_action")) == "idle", "前から後ろへ行ったキャラは、すぐ静止")
	check(str(vb.get("current_action")) == "step" and (vb.get("player") as AnimationPlayer).current_animation == str(anims[back1]), "かわりに前に来たキャラは、自分の A攻撃（%s）。ほかのキャラの動きにならない" % str(anims[back1]))
	# 攻撃の途中で、後ろへもどされても、すぐ静止
	st.set_team([front, back1, str(st.units[2]["id"]), str(st.units[3]["id"])])
	st.finish()
	check(not (vb.get("player") as AnimationPlayer).is_playing() and str(vb.get("current_action")) == "idle", "攻撃の途中で後ろへもどされても、すぐ静止")
	st.step(3.0)

	# ---- 5. 作り直さない ----
	var built0: int = st.built_count
	var team5: Array = []
	for u in st.units:
		team5.append(str(u["id"]))
	st.set_team([team5[1], team5[0], team5[2], team5[3]])
	st.finish()
	st.set_team(team5)
	st.finish()
	check(st.built_count == built0, "入れかえても、キャラの形を作り直さない（%d）" % st.built_count)
	st.set_team(team5)
	st.finish()
	var one_view := true
	var one_conn := true
	for u in st.units:
		var holder: Node3D = u["holder"]
		var n_views := 0
		for c in holder.get_children():
			if c.get_script() != null and c.has_method("play_step"):
				n_views += 1
		one_view = one_view and n_views == 1
		var v: Node = u["view"]
		var p: AnimationPlayer = v.get("player")
		one_conn = one_conn and p.animation_finished.get_connections().size() == 1
	check(st.built_count == built0 and one_view, "同じ編成をもう一度：作り直さず、キャラの形は1人に1つ")
	check(one_conn, "動きが終わった合図のつなぎは、1人に1つだけ（二重にならない）")

	# ---- 6. 場所 ----
	var holder_ok := true
	var view_ok := true
	var hips_ok := true
	var max_drift := 0.0
	var max_move := 0.0
	var max_hand := 0.0
	for u in st.units:
		var holder: Node3D = u["holder"]
		var before := holder.position
		var v: Node3D = u["view"]
		var vpos := v.position
		var p: AnimationPlayer = v.get("player")
		for i in 90:
			p.advance(1.0 / 60.0)
		st.step(1.0 / 60.0)
		holder_ok = holder_ok and holder.position.is_equal_approx(before)
		view_ok = view_ok and v.position.is_equal_approx(vpos)
		# 腰（root の骨）の位置：動きのデータを、最初・途中・最後で読む（画面のない所では骨の形が更新されないため、データで調べる）
		var an: Animation = p.get_animation(str(anims[str(u["id"])]))
		var L := an.length
		for ti in an.get_track_count():
			var path := str(an.track_get_path(ti))
			if an.track_get_type(ti) == Animation.TYPE_POSITION_3D and path.ends_with(":root"):
				var a0: Vector3 = an.position_track_interpolate(ti, 0.0)
				var a1: Vector3 = an.position_track_interpolate(ti, L)
				var drift := Vector2(a1.x - a0.x, a1.z - a0.z).length() * v.scale.x
				for k in 7:
					var q: Vector3 = an.position_track_interpolate(ti, L * k / 6.0)
					max_move = maxf(max_move, Vector2(q.x - a0.x, q.z - a0.z).length() * v.scale.x)
				max_drift = maxf(max_drift, drift)
				hips_ok = hips_ok and drift < 0.35
			elif an.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
				var r0: Quaternion = an.rotation_track_interpolate(ti, 0.0)
				for k in 7:
					max_hand = maxf(max_hand, rad_to_deg(r0.angle_to(an.rotation_track_interpolate(ti, L * k / 6.0))))
	check(holder_ok and view_ok, "くり返しても、キャラの場所は動かない（ロビーの中でずれない）")
	check(max_hand > 5.0, "（測り方の確かめ：攻撃の動きで、腕などの骨は %.0f° まで回る＝データを読めている）" % max_hand)
	check(hips_ok, "動きの最初と最後で、腰の位置はほぼ同じ（いちばん大きくて %.2f m。動きの途中では %.2f m まで動く。くり返しでワープしない）" % [max_drift, max_move])

	# ---- 7. 戦いの処理は呼ばない ----
	var src := FileAccess.get_file_as_string("res://scripts/flow/lobby_stage.gd")
	check(not src.contains("Actions.new") and not src.contains("perform(") and not src.contains("_resolve_hit") and not src.contains("play_sfx") and not src.contains("_spark"), "ロビーは動きを流すだけ（技の実行・当たり・音・光の関数を呼ばない）")
	check(src.contains("play_step(") and src.contains("Actions.config_for(id)"), "戦いと同じ設定（Actions.config_for）と、同じ再生の関数（play_step）を使う")

	# ---- 8. 動きがないキャラ ----
	var fake: Dictionary = CharacterData.find(chars, ids[1]).duplicate(true)
	fake["id"] = "no_attack_test"
	var anims_map: Dictionary = fake.get("animations", {})
	anims_map = anims_map.duplicate()
	for k in anims_map.keys():
		if str(k).ends_with("_A"):
			anims_map.erase(k)
	fake["animations"] = anims_map
	var cv: Node3D = preload("res://scripts/characters/character_view.gd").new()
	root.add_child(cv)
	cv.setup(fake)
	st.attack_cache["no_attack_test"] = {"anim": "Nothing_A", "speed": 1.0}
	var played: bool = st.play_attack(cv, "no_attack_test")
	check(not played and str(cv.get("current_action")) == "idle" and st.unsupported.has("no_attack_test"), "A攻撃の動きがないキャラは、静止のまま（記録される・エラーなし）")
	cv.queue_free()
	st.unsupported.erase("no_attack_test")
	check(st.unsupported.is_empty(), "いまのキャラ9人に、動きがないキャラはいない")

	# ---- 9. 入りなおす ----
	st.queue_free()
	await process_frame
	var st2: Node3D = LobbyStage.new()
	st2.setup(chars)
	root.add_child(st2)
	st2.set_team([ids[5], ids[6], ids[7], ids[8]])
	st2.finish()
	var ok2 := true
	for u in st2.units:
		var v: Node = u["view"]
		ok2 = ok2 and not (v.get("player") as AnimationPlayer).is_playing()
	st2.set_team([ids[6], ids[5], ids[7], ids[8]])
	st2.finish()
	var v6: Node = unit_of(st2, ids[6])["view"]
	ok2 = ok2 and (v6.get("player") as AnimationPlayer).current_animation == str(anims[ids[6]]) and (v6.get("player") as AnimationPlayer).is_playing()
	check(ok2, "ロビーに入りなおしても、静止・前に来たら正しい A攻撃")
	st2.queue_free()

	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
