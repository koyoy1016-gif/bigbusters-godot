extends SceneTree
## ボスの姿（平常→60%でよろける→覚醒）の確認
var fails := 0
func check(name: String, ok: bool) -> void:
	print(("OK   " if ok else "FAIL ") + name)
	if not ok: fails += 1
func _init() -> void:
	var BM := load("res://scripts/boss/boss_model.gd")
	var cfg: Dictionary = BM.load_config()
	var m: Node3D = BM.new()
	root.add_child(m)
	m.build(cfg, StandardMaterial3D.new())
	check("はじめは平常の姿", not m.is_awake() and not m.is_staggering())
	check("肌は紫", m.skin_color().is_equal_approx(Color(str(cfg["skin_normal"]))))
	m.update_form(0.7, 0.1)
	check("70%ではよろけない", not m.is_staggering())
	m.update_form(0.59, 0.1)
	check("60%を切るとよろける", m.is_staggering() and not m.is_awake())
	for i in 40: m.update_form(0.58, 0.1)
	check("起き上がると覚醒（赤い肌）", m.is_awake() and not m.is_staggering() and m.skin_color().is_equal_approx(Color(str(cfg["skin_awake"]))))
	m.reset_form()
	check("リセットで平常にもどる", not m.is_awake())
	m.update_form(0.45, 0.1)
	check("50%以下で始まれば、すぐ覚醒", m.is_awake())
	m.reset_form()
	m.set_flash(true)
	check("点滅を出せる", m.is_flashing() and (m.skin as StandardMaterial3D).emission_energy_multiplier > 0.0)
	m.set_flash(false)
	check("点滅を消せる", not m.is_flashing() and (m.skin as StandardMaterial3D).emission_energy_multiplier == 0.0)
	check("点滅で材質の種類は変わらない（光る設定は入れたまま、明るさだけ変える）", (m.skin as StandardMaterial3D).emission_enabled)
	print("失敗: ", fails)
	quit()
