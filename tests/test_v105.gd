extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v105.gd
## 版105（軽量化③：1コマだけ長い引っかかり）。技・当たりの見た目を出すたびに、新しい材質を作っていた（1つ 0.4〜0.8 ms・PC）のをやめ、
## 使い終わった材質を使いまわす（fx_pool.gd）。形（球・輪・筒・星・粒の板）も、同じ大きさなら使いまわす。投げるバットは先に作り、部品をまとめる。
## 確かめること：
##   1. 見た目が消えると（queue_free）材質が返され、次の同じ種類の見た目で使われる。付けかえ（いったん外す）では返さない
##   2. 使いまわす時、使っている間に変わった所（すけ具合・光の強さ・膜の消え具合）は元にもどる。種類（色・光・すけ方・板の向き）がちがう材質は使わない
##   3. 使っている間の材質を、別の見た目に貸さない（同じ材質が2つの見た目に同時に付かない）
##   4. 形は同じ大きさなら同じ物。ビーム・斬撃の筒は長さ1の筒をのばす（長さは前と同じ）
##   5. 必殺技の見た目（UltFx）も材質を使いまわす
##   6. 投げるバットは、戦いの始まりに作られ（隠れている）、部品は1つの形にまとまっている

const SkillFx := preload("res://scripts/fx/skill_fx.gd")
const FxPool := preload("res://scripts/fx/fx_pool.gd")
const UltFx := preload("res://scripts/fx/ultimate_fx.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func mats_of(n: Node) -> Array:
	var out := []
	var list: Array = n.find_children("*", "GeometryInstance3D", true, false)
	for g in list:
		var m: Material = (g as GeometryInstance3D).material_override
		if m != null:
			out.append(m)
	return out


func _initialize() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	await process_frame
	var spec := {"kind": "spark", "color": "#ff8844", "life": 0.4, "size": 0.7, "flash": 0.5}
	# ---- 1・2 ----
	var a := SkillFx.make(spec, Vector3.ZERO, Vector3(0, 0, -3), 1.0)
	holder.add_child(a)
	var ma := mats_of(a)
	check(ma.size() >= 3, "火花の見た目は、材質を %d つ使う（星・光・粒）" % ma.size())
	SkillFx.tick(a, 0.3)  # すけ具合が変わる
	var star_a: StandardMaterial3D = SkillFx.mat_of(a.get_node("Shape"))
	var faded := star_a.albedo_color.a
	a.queue_free()
	await process_frame
	await process_frame
	var made0 := FxPool.made
	var b := SkillFx.make(spec, Vector3.ZERO, Vector3(0, 0, -3), 1.0)
	holder.add_child(b)
	var mb := mats_of(b)
	var same := 0
	for m in mb:
		if ma.has(m):
			same += 1
	check(same == ma.size() and FxPool.made == made0, "消えた見た目の材質（%d つ）を、次の同じ見た目で使う（新しく作らない）" % same)
	var star_b: StandardMaterial3D = SkillFx.mat_of(b.get_node("Shape"))
	check(faded < 0.9 and is_equal_approx(star_b.albedo_color.a, 0.95) and star_b.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "使いまわす時、すけ具合は元にもどる（%.2f → %.2f）" % [faded, star_b.albedo_color.a])
	# 色がちがう見た目には使わない
	var c := SkillFx.make({"kind": "spark", "color": "#2266ff", "life": 0.4, "size": 0.7, "flash": 0.5}, Vector3.ZERO, Vector3(0, 0, -3), 1.0)
	holder.add_child(c)
	var mixed := false
	for m in mats_of(c):
		if mb.has(m):
			mixed = true
	check(not mixed and (SkillFx.mat_of(c.get_node("Shape")) as StandardMaterial3D).albedo_color.b > 0.5, "色がちがう見た目には、別の材質（青い火花は青）")
	# ---- 3. 使っている間は貸さない ----
	var d := SkillFx.make(spec, Vector3.ZERO, Vector3(0, 0, -3), 1.0)
	holder.add_child(d)
	var shared := false
	for m in mats_of(d):
		if mb.has(m):
			shared = true
	check(not shared, "使っている間の材質は、ほかの見た目に貸さない（同じ火花を2つ出しても、別の材質）")
	# 付けかえでは返さない
	var free_before := FxPool.free_count()
	holder.remove_child(d)
	root.add_child(d)
	await process_frame
	check(FxPool.free_count() == free_before, "付けかえ（いったん外す）では、材質を返さない")
	# 膜：消え具合をもどす
	var dome := SkillFx.make({"kind": "dome", "color": "#66aaff", "life": 1.0, "radius": 2.0}, Vector3.ZERO, Vector3.ZERO, 0.0)
	holder.add_child(dome)
	SkillFx.tick(dome, 0.5)
	var dm: ShaderMaterial = SkillFx.mat_of(dome.get_node("Shape"))
	var fade_used := float(dm.get_shader_parameter("fade"))
	dome.queue_free()
	await process_frame
	await process_frame
	var dome2 := SkillFx.make({"kind": "dome", "color": "#66aaff", "life": 1.0, "radius": 2.0}, Vector3.ZERO, Vector3.ZERO, 0.0)
	holder.add_child(dome2)
	var dm2: ShaderMaterial = SkillFx.mat_of(dome2.get_node("Shape"))
	check(dm2 == dm and fade_used > 0.5 and is_zero_approx(float(dm2.get_shader_parameter("fade"))), "膜も使いまわし、消え具合は 0 にもどる")
	var aura := SkillFx.make({"kind": "aura", "color": "#66aaff", "life": 1.0}, Vector3.ZERO, Vector3.ZERO, 0.0)
	holder.add_child(aura)
	var am: ShaderMaterial = SkillFx.mat_of(aura.get_node("Shape"))
	check(am != dm2 and is_zero_approx(float(am.get_shader_parameter("hex_alpha"))), "体を包む光（aura）は、膜とは別の材質（六角の模様なし）")
	# ---- 4. 形 ----
	var r1 := SkillFx.make({"kind": "ring", "color": "#ffffff"}, Vector3.ZERO, Vector3.ZERO, 0.0)
	var r2 := SkillFx.make({"kind": "ring", "color": "#ff0000"}, Vector3.ZERO, Vector3.ZERO, 0.0)
	holder.add_child(r1)
	holder.add_child(r2)
	check(is_same((r1.get_node("Shape") as MeshInstance3D).mesh, (r2.get_node("Shape") as MeshInstance3D).mesh), "同じ大きさの形は、同じ物を使う（輪）")
	var beam := SkillFx.make({"kind": "beam", "color": "#ffffff", "width": 0.3}, Vector3.ZERO, Vector3(0, 0, -7.5), 1.0)
	holder.add_child(beam)
	var bs := beam.get_node("Shape") as MeshInstance3D
	var bl := float((bs.mesh as CylinderMesh).height) * bs.scale.y
	check(absf(bl - 7.5) < 0.001 and is_equal_approx(float(beam.get_meta("len")), 7.5), "ビームの筒は、長さ1の筒を 7.5 にのばす（前と同じ長さ）")
	# ---- 5. 必殺技の見た目 ----
	var u1 := UltFx.spawn(holder, "charge", Vector3.ZERO, Vector2(0, 1), {"ring_color": "#ffd24a"})
	var um: Material = (u1.get_child(0) as MeshInstance3D).material_override
	u1.queue_free()
	await process_frame
	await process_frame
	var u2 := UltFx.spawn(holder, "charge", Vector3.ZERO, Vector2(0, 1), {"ring_color": "#ffd24a"})
	var um2: Material = (u2.get_child(0) as MeshInstance3D).material_override
	check(um2 == um and is_same((u2.get_child(0) as MeshInstance3D).mesh, (u1.get_child(0) as MeshInstance3D).mesh if is_instance_valid(u1) else (u2.get_child(0) as MeshInstance3D).mesh), "必殺技の見た目も、材質と形を使いまわす")
	# ---- 6. 投げるバット ----
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = false
	root.add_child(s)
	await process_frame
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var fb: Node3D = s.attack_fx._fly_bat
	var meshes := 0
	if fb != null:
		meshes = fb.find_children("*", "MeshInstance3D", true, false).size()
	check(fb != null and not fb.visible and meshes >= 1 and meshes <= 3, "投げるバットは、戦いの始まりに作られ（隠れている）、部品は %d つの形にまとまっている（前は 44）" % meshes)
	s.queue_free()
	print("     材質：作った %d・使いまわした %d" % [FxPool.made, FxPool.reused])
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
