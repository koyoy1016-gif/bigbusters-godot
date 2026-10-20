extends SceneTree
## 戦いの画面の写真を撮る（見た目の確認用）。xvfb-run ... --script res://tools/shot_battle.gd -- 出力.png 画質 [awake]
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
const Quality := preload("res://scripts/core/quality.gd")
const StyleFx := preload("res://scripts/characters/style_fx.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://shot.png"
	var qname := args[1] if args.size() > 1 else "high"
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	var qcfg := Quality.load_config()
	Quality.apply(qname, qcfg, root, get_nodes_in_group("sun"))
	StyleFx.set_outline(root, bool(qcfg["presets"][qname].get("outline", false)))
	if s.has_method("set_map_quality"):
		s.set_map_quality(qname)
	s.start_round()
	if args.size() > 2 and args[2] == "awake":
		s.boss_model._apply_form("awake")
	for i in 40:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out)
	quit(0)
