extends SceneTree
## 版81：ロビーの写真を撮る（見た目の確認用）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_lobby.gd -- 出力.png [画面の名前] [回す回数]
## 画面の名前：lobby（ふつう）・picker（ステージを選ぶ）・room（へや）・formation（編成）
const SCENE := "res://scenes/game_flow.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var mode := args[1] if args.size() > 1 else "lobby"
	var turns := int(args[2]) if args.size() > 2 else 0
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	for i in 3:
		await process_frame
	flow.goto("lobby")
	for i in turns:
		flow.lobby_ui.rotate_team(1)
	for i in 70:
		await process_frame
	match mode:
		"picker":
			flow.lobby_ui.open_stage_picker()
		"room":
			flow.event("room")
		"formation":
			flow.event("formation")
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " team=", flow.lobby_ui.team())
	quit(0)
