extends SceneTree
## 版101：戦いの1コマの CPU の時間（スクリプト＋エンジンの中の仕事。描く仕事はふくまない）を測る（測るだけ）。
## godot --headless --fixed-fps 60 --path . --script res://tools/perf_cpu.gd -- 出力.json [場面 battle/lobby] [コマ数] [止める物]
##   --fixed-fps 60：1コマ＝1/60 秒で進める（ゲームの中の時間がこの機械の速さに左右されない）。画面なしなので、コマとコマの間に待ちがなく、
##   1コマの壁の時計の時間＝その1コマの CPU の仕事（スクリプト・動きの再生・骨の計算・当たりなど）。
## 止める物（くらべる用。「,」で区切る）：anim（キャラの動きの再生を止める）・hud（画面の字とバーを描かない）・boss（ボスの形の計算を止める）
## 決まった種（seed）で始めるので、毎回ほぼ同じ戦いになる。

const SCENE := "res://scenes/game_flow.tscn"


func pct(arr: Array, p: float) -> float:
	var a := arr.duplicate()
	a.sort()
	return float(a[clampi(int(a.size() * p), 0, a.size() - 1)])


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var mode := args[1] if args.size() > 1 else "battle"
	var frames := int(args[2]) if args.size() > 2 else 900
	var off: Array = (args[3] if args.size() > 3 else "").split(",", false)
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
		var b: Node = flow.battle
		b.clock_ms = func() -> float: return float(sim[0])  # ゲームの中の時計も 1コマ＝1/60 秒で進める（ボスの攻撃の時間がこの機械の速さに左右されない）
		b.start_round()
		if off.has("hud"):
			b.overlay.visible = false
		if off.has("anim"):
			for ap in b.find_children("*", "AnimationPlayer", true, false):
				(ap as AnimationPlayer).callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if off.has("boss"):
			b.boss_model.set_process(false)
			b.set_meta("perf_no_boss_pose", true)
		for i in 30:
			await process_frame
			sim[0] = float(sim[0]) + 1000.0 / 60.0
	var ft := []
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		sim[0] = float(sim[0]) + 1000.0 / 60.0
		var t := Time.get_ticks_usec()
		ft.append((t - last) / 1000.0)
		last = t
	var sum := 0.0
	for v in ft:
		sum += v
	var rep := {"mode": mode, "off": off, "frames": frames, "avg_ms": snappedf(sum / frames, 0.001), "p50_ms": snappedf(pct(ft, 0.5), 0.001), "p95_ms": snappedf(pct(ft, 0.95), 0.001), "max_ms": snappedf(pct(ft, 1.0), 0.001)}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(rep))
	f.close()
	print("CPU ", rep)
	quit(0)
