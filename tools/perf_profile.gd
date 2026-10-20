extends SceneTree
## 版101：スクリプトの関数ごとの時間を測る（Godot の「スクリプトのプロファイラー」を使う。測るだけ）。
## godot --headless -d --path . --script res://tools/perf_profile.gd -- 場面(battle/lobby) コマ数 > 出力.txt
##   （-d：画面に結果を書く「その場のデバッガー」。結果は「ACCUMULATED」の後に、関数ごとの total（中で呼んだ物もふくむ）・self（その関数だけ）・回数）
## battle：ロビー → 戦い（AI の味方とボスが自由に戦う）の、決めたコマ数の間だけ測る。
## lobby：ロビーで、決めたコマ数の間だけ測る（編成を入れかえて、前に来たキャラの動きもふくめる）。
## 1コマ＝1/60 秒で進める（この環境の速さに左右されないように）。

const SCENE := "res://scenes/game_flow.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "battle"
	var frames := int(args[1]) if args.size() > 1 else 600
	Engine.physics_ticks_per_second = 60
	seed(12345)
	var sim := [1.0e7]  # ゲームの中の時計（ミリ秒）
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 30:
		await process_frame
	if mode == "battle":
		flow.play()
		for i in 5:
			await process_frame
		flow.battle.clock_ms = func() -> float: return float(sim[0])  # ゲームの中の時計も 1コマ＝1/60 秒で進める
		flow.battle.start_round()
		for i in 30:
			await process_frame
			sim[0] = float(sim[0]) + 1000.0 / 60.0
	var t0 := Time.get_ticks_usec()
	EngineDebugger.profiler_enable("scripts", true)
	for i in frames:
		await process_frame
		sim[0] = float(sim[0]) + 1000.0 / 60.0
	EngineDebugger.profiler_enable("scripts", false)
	print("PROFILE_DONE mode=%s frames=%d wall_ms=%.1f" % [mode, frames, (Time.get_ticks_usec() - t0) / 1000.0])
	quit(0)
