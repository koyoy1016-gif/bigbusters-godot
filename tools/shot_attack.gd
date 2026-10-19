extends SceneTree
## ボスの攻撃の途中を撮る（見た目の確認用）。AI3人つき。戦いの時間を早送りして、攻撃 kind が始まってから u 秒の画面を撮る。
## xvfb-run -a -s "-screen 0 648x1152x24" godot --path . --rendering-driver opengl3 --resolution 648x1152 --script res://tools/shot_attack.gd -- 出力の頭 kind u1,u2,... [awake]
## 出力：<出力の頭>_<kind>_<u>.png
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Quality := preload("res://scripts/core/quality.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "user://atk"
	var kind := args[1] if args.size() > 1 else "bat_h"
	var us: Array = []
	for x in (args[2] if args.size() > 2 else "0.5").split(","):
		us.append(float(x))
	var awake := args.size() > 3 and args[3] == "awake"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	var qcfg := Quality.load_config()
	Quality.apply("high", qcfg, root, get_nodes_in_group("sun"))
	StyleFx.set_outline(root, true)
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	if awake:
		s.my_hits = float(s.config["boss_hp"]) * 0.55
		s._recompute_boss_hp()
		s.boss_model._apply_form("awake")
		s.awake_from_t = 0.0
	var sched: Array = s.awake_schedule if awake else s.attack_schedule
	var a: Dictionary = {}
	for x in sched:
		if str(x["kind"]) == kind:
			a = x
			break
	if a.is_empty():
		print("NO ATTACK ", kind)
		quit(1)
		return
	var t := 0.0
	var dt := 1.0 / 30.0
	for u in us:
		var goal := float(a["start"]) + float(u)
		while t < goal:
			t += dt
			now[0] = s.round_start_ms + t * 1000.0
			s.my_hp = 100.0
			s.downed = false
			s._process(dt)
		for i in 3:
			await process_frame
		var out := "%s_%s_%.2f.png" % [prefix, kind, float(u)]
		root.get_texture().get_image().save_png(out)
		print("SHOT ", out)
	quit(0)
