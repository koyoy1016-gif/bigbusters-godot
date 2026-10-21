extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v108.gd
## 版108（覚醒が重い）。
## 1. 覚醒の攻撃（巨大酒瓶ライド・酒の大雨・酒瓶落とし・チラシ）の、同じ入力なら同じ答えになる計算を覚えておく（boss_attacks.gd の memo）。
##    覚えた答えは、毎回計算した答えと同じ（当たり場所の一覧が、攻撃の全部の時刻で同じ）。設定や番号が変われば、計算しなおす。速くなる。
## 2. 覚醒・ボスの攻撃・倒れた時だけ出る見た目を、戦いの始まりに、見えない所で1回描く（写し。scripts/fx/draw_warm.gd）。
##    写しは、元と同じ材質・同じ形。地面の下・カメラの前。元は隠れたまま。3コマで消える。
## 3. 覚醒・勝ち・負けの曲を、戦いの前に読みこむ。

const Attacks := preload("res://scripts/combat/boss_attacks.gd")
const DrawWarm := preload("res://scripts/fx/draw_warm.gd")
const BgmPlayer := preload("res://scripts/audio/bgm.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func ctx_of(n: int, rs: float) -> Dictionary:
	return {"boss": Vector2(1.5, -2.0), "yaw": 0.4, "members": ["p1", "p2", "p3", "p4"], "positions": {"p1": Vector2(3, 4), "p2": Vector2(-5, 1)},
		"locked": null, "round_start_ms": rs, "bounds": 15.0, "target": Vector2(2.0, 6.0), "curve": 0.0, "area": 13.0, "n": n}


## 攻撃の全部の時刻の、当たり場所の一覧（memo を使う／毎回消して計算しなおす）
func all_hazards(kind: String, n: int, rs: float, cfg: Dictionary, fresh: bool) -> Array:
	var a := {"n": n, "kind": kind, "start": 0.0, "feint": 0.0}
	var k: Dictionary = cfg["kinds"][kind]
	var dur := Attacks.attack_duration(kind, k, n, rs)
	var out: Array = []
	var u := 0.0
	while u < dur + 0.5:
		if fresh:
			Attacks.memo_clear()
		out.append(Attacks.hazards(a, u, cfg, ctx_of(n, rs)))
		u += 1.0 / 30.0
	return out


func _initialize() -> void:
	var cfg := Attacks.load_config()
	# ---- 1. 覚えておく計算 ----
	for kind in ["bottle_ride", "flyer_storm", "sake_drop", "flyers", "fire_fest"]:
		var same := true
		for n in [1, 4, 23]:
			for rs in [1.0e7, 3.3e9]:
				Attacks.memo_clear()
				var memo := all_hazards(kind, n, rs, cfg, false)
				var fresh := all_hazards(kind, n, rs, cfg, true)
				same = same and memo == fresh and memo.size() > 10
		check(same, "%s：覚えた答えの当たり場所は、毎回計算した答えと、攻撃の全部の時刻で同じ（番号3つ×開始時刻2つ）" % kind)
	var rk: Dictionary = cfg["kinds"]["bottle_ride"]
	Attacks.memo_clear()
	var c1 := ctx_of(3, 1.0e7)
	var p1 := Attacks.ride_plan(rk, c1)
	var h0 := Attacks.memo_hits
	var p1b := Attacks.ride_plan(rk, c1)
	check(is_same(p1, p1b) and Attacks.memo_hits == h0 + 1, "同じ入力の2回めは、覚えた答えを使う（計算しない）")
	var p2 := Attacks.ride_plan(rk, ctx_of(4, 1.0e7))
	var p3 := Attacks.ride_plan(rk, ctx_of(3, 2.0e7))
	check(p2 != p1 and p3 != p1, "攻撃の番号・戦いの開始時刻がちがえば、別の答え")
	var rk2 := rk.duplicate()
	rk2["passes_min"] = 2
	rk2["passes_max"] = 2
	check(Attacks.ride_plan(rk2, c1).size() == 2 and p1.size() >= int(rk["passes_min"]), "設定の値が変われば、計算しなおす（突入の数 %d → 2）" % p1.size())
	var th1 := Attacks.ride_throws(p1[0], rk, c1)
	var rk3 := rk.duplicate()
	rk3["bottles_per_pass"] = 3
	check(Attacks.ride_throws(p1[0], rk3, c1).size() == 3 and th1.size() == int(rk["bottles_per_pass"]), "投げる瓶の数が変われば、計算しなおす")
	var fk: Dictionary = cfg["kinds"]["flyer_storm"]
	var fk2 := fk.duplicate()
	fk2["safe_count"] = 1
	var a7 := {"n": 7, "kind": "flyer_storm"}
	check(Attacks.storm_safe(a7, fk2, c1).size() == 1 and Attacks.storm_safe(a7, fk, c1).size() == int(fk["safe_count"]), "安全地帯の数が変われば、計算しなおす")
	var sk: Dictionary = cfg["kinds"]["sake_drop"]
	var sb1 := Attacks.sake_bottles({"n": 2, "kind": "sake_drop"}, sk, c1)
	var c_moved := c1.duplicate()
	c_moved["target"] = Vector2(-6.0, -6.0)
	var sb2 := Attacks.sake_bottles({"n": 2, "kind": "sake_drop"}, sk, c_moved)
	check((sb1[0]["to"] as Vector2) != (sb2[0]["to"] as Vector2), "酒瓶：ねらう所が変われば、落ちる所も変わる（前と同じ）")
	# 速さ（巨大酒瓶ライドの全部の時刻）
	var t0 := Time.get_ticks_usec()
	all_hazards("bottle_ride", 5, 4.0e7, cfg, true)
	var t1 := Time.get_ticks_usec()
	Attacks.memo_clear()
	all_hazards("bottle_ride", 5, 4.0e7, cfg, false)
	var t2 := Time.get_ticks_usec()
	var slow := float(t1 - t0)
	var fast := float(t2 - t1)
	print("     巨大酒瓶ライドの当たり場所（全部の時刻）：毎回計算 %.1f ms → 覚える %.1f ms" % [slow / 1000.0, fast / 1000.0])
	check(fast * 2.0 < slow, "覚えておくと、2倍以上速い（%.1f 倍）" % (slow / maxf(fast, 1.0)))
	var src := FileAccess.get_file_as_string("res://scripts/combat/boss_attacks.gd")
	check(src.contains("MEMO_MAX") and src.contains("_memo.clear()"), "覚えておく数には上限がある（ふえつづけない）")

	# ---- 2. 見えない所で1回描く ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = "hero_swordsman"
	s.ai_picks = ["healer", "gunner", "brawler"]
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.skills.prewarm_fx()
	var nodes: Array = s.skills.prewarm_nodes.duplicate()
	var warm: Array = []
	for n in nodes:
		if (n as Node).has_meta("draw_warm") or (n as Node).has_meta("warm_temp"):
			warm.append(n)
	var names := {}
	for n in warm:
		names[str((n as Node).name)] = true
	var want := ["Warm_SakeRain", "Warm_Body", "Warm_Spray", "Warm_Lighter", "Warm_BossShadow", "Warm_OniAwake", "Warm_SakeSpray", "WarmHazard_mat", "WarmHazard_zmat", "WarmReviveZone"]
	var missing := []
	for w in want:
		if not names.has(w):
			missing.append(w)
	check(missing.is_empty() and warm.size() >= 16, "ボスの攻撃・覚醒・倒れた時の見た目の写しを %d こ出す（足りない：%s）" % [warm.size(), str(missing)])
	# 写しは、元と同じ材質（新しい材質を作らない）
	var shares := true
	var rain_copy: CPUParticles3D = null
	for n in warm:
		if str((n as Node).name) == "Warm_SakeRain":
			rain_copy = n
	shares = rain_copy != null and rain_copy.mesh == s._rain_fx.mesh
	var awake_src: MeshInstance3D = s.boss_model.awake_items
	var awake_copy: MeshInstance3D = null
	for n in warm:
		if str((n as Node).name) == "Warm_" + str(awake_src.name):
			awake_copy = n
	shares = shares and awake_copy != null and awake_copy.mesh == awake_src.mesh and awake_copy.skin == null
	check(shares, "写しは、元と同じ形・同じ材質（酒の雨・覚醒の小物。骨なしで写す）")
	# 見えない所：地面の下・カメラの前
	var cam: Transform3D = s.camera.global_transform
	var hidden := true
	for n in nodes:
		var p: Vector3 = (n as Node3D).global_position
		hidden = hidden and p.y < float(s.ground_y) - 5.0 and (cam.affine_inverse() * p).z < 0.0
	check(hidden, "写しは、カメラの前の地面の下（見えない所）")
	# 深さを無視する数字（蘇生の輪の上）は、すきとおる色で描く
	var label_ok := false
	for n in warm:
		if str((n as Node).name) == "WarmReviveZone":
			for c in (n as Node).get_children():
				if c is Label3D:
					label_ok = is_zero_approx((c as Label3D).modulate.a) and (c as Label3D).text != ""
	check(label_ok, "地面を通して見える数字は、すきとおる色（描くけれど、見えない）")
	# 元は隠れたまま
	var originals_hidden: bool = not s._rain_fx.emitting and not s._ride_bottle.visible and not awake_src.visible and not (s.attack_fx._lighter as Node3D).visible
	check(originals_hidden, "元の見た目（雨・巨大酒瓶・覚醒の小物・ライター）は、隠れたまま")
	for i in 4:
		s.skills.prewarm_step()
	await process_frame
	await process_frame
	var gone := true
	for n in nodes:
		gone = gone and not is_instance_valid(n)
	check(gone and is_instance_valid(s._rain_fx) and is_instance_valid(awake_src), "3コマで写しは消え、元は残る")
	var draw_src := FileAccess.get_file_as_string("res://scripts/prototype/battle_skills.gd")
	check(draw_src.contains("b.attack_fx.prewarm_sources()") and draw_src.contains("b.boss_model.prewarm_sources()") and draw_src.contains("b.revive_sys.prewarm_source()"),
			"戦いの始まりの先出し（prewarm_fx）に、ボスの攻撃・覚醒・蘇生の見た目が入っている")
	s.queue_free()
	await process_frame

	# ---- 3. 曲を先に読みこむ ----
	var bgm := BgmPlayer.new()
	root.add_child(bgm)
	await process_frame
	var nload := bgm.preload_tracks(["battle", "awake", "win", "lose"])
	check(nload == 4 and bgm.streams.has("awake") and bgm.streams.has("win"), "覚醒・勝ち・負けの曲を、先に読みこむ（%d 曲）" % nload)
	var flow_src := FileAccess.get_file_as_string("res://scripts/flow/game_flow.gd")
	check(flow_src.contains("bgm.preload_tracks([\"battle\", \"awake\", \"win\", \"lose\"])"), "戦いを作る時に、曲を読みこむ")
	bgm.queue_free()
	await process_frame
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
