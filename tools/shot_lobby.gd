extends SceneTree
## 版81：ロビーの写真を撮る（見た目の確認用）。
## xvfb-run -a -s "-screen 0 1280x1280x24" godot --rendering-driver opengl3 --resolution 648x1152 --path . --script res://tools/shot_lobby.gd -- 出力.png [画面の名前] [回す回数]
## 画面の名前：lobby（ふつう）・picker（ステージを選ぶ）・room（へや）・formation（編成）・start（はじめの画面）・guest（ゲストの確かめ）・profile（プロフィール）・iconpick（アイコンを選ぶ）
## 版82：顔の絵ができるまで待つ（4つめの数：待つコマ数）
const SCENE := "res://scenes/game_flow.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var mode := args[1] if args.size() > 1 else "lobby"
	var turns := int(args[2]) if args.size() > 2 else 0
	var wait := int(args[3]) if args.size() > 3 else 70
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	for i in 3:
		await process_frame
	flow.goto("start" if mode in ["start", "guest"] else "lobby")
	for i in turns:
		flow.lobby_ui.rotate_team(1)
	for i in 70:
		await process_frame
	match mode:
		"picker":
			flow.lobby_ui.open_stage_picker()
		"room":
			flow.event("room")
		"formation", "formation2":
			flow.event("formation")
			if mode == "formation2":
				for k in 3:
					await process_frame
				(flow.panels["formation"].find_child("Scroll", true, false) as ScrollContainer).scroll_vertical = 760
		"guest":
			flow.start_ui.ask_guest()
		"gacha", "gacha_aim", "gacha_dash", "gacha_result", "gacha_odds":
			flow.save["coins"] = 500
			flow.event("gacha")
			for k in 20:
				await process_frame
			var ui: RefCounted = flow.gacha_ui
			var hp: Vector2 = ui.stage.hero_screen_point()
			if mode == "gacha_odds":
				ui.open_odds()
			elif mode != "gacha":
				ui.grab(hp)
				ui.drag(hp + Vector2(-20, 280))
				if mode in ["gacha_dash", "gacha_result"]:
					for k in 8:
						await process_frame
					ui.release(hp + Vector2(-20, 280))
					var n := 5 if mode == "gacha_dash" else 200
					for k in n:
						await process_frame
		"profile", "iconpick":
			flow.event("account")
			if mode == "iconpick":
				flow.profile_ui.open_picker()
	for i in wait:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("SHOT ", out, " team=", flow.lobby_ui.team())
	quit(0)
