extends SceneTree
## 版105：戦いで「1コマだけ長い」コマ（引っかかり）を見つけ、その時に何が起きたかを記録する（測るだけ）。
## godot --headless --fixed-fps 60 --path . --script res://tools/perf_spikes.gd -- 出力.json [コマ数] [回数]
## 画面なし・1コマ＝1/60 秒（ゲームの時計も）。AI の味方とボスが自由に戦う。決まった種で、毎回ほぼ同じ戦い。
## 毎コマ：1コマの時間・そのコマで新しくできたノード（名前・種類）・ノードの数。長いコマ（まん中の4倍以上）を、できた物といっしょに出す。
## 戦いを何回かくり返し（回数）、2回目以降にも長いコマが出るか（はじめてだけか）も見る。

const SCENE := "res://scenes/game_flow.tscn"

var added: Array = []


func _on_added(n: Node) -> void:
	added.append(n)


func label_of(n: Node) -> String:
	var p := n.get_parent()
	var s := str(n.name)
	if p != null:
		s = str(p.name) + "/" + s
	return s + "(" + n.get_class() + ")"


func run_battle(flow: Node, frames: int, sim: Array) -> Dictionary:
	flow.play()
	for i in 5:
		await process_frame
	var b: Node = flow.battle
	b.clock_ms = func() -> float: return float(sim[0])
	b.start_round()
	for i in 10:
		await process_frame
		sim[0] = float(sim[0]) + 1000.0 / 60.0
	var ft := []
	var rows := []
	var last := Time.get_ticks_usec()
	added.clear()
	for i in frames:
		await process_frame
		sim[0] = float(sim[0]) + 1000.0 / 60.0
		var t := Time.get_ticks_usec()
		var dt := (t - last) / 1000.0
		ft.append(dt)
		var kinds := {}
		for n in added:
			if is_instance_valid(n):
				var k := label_of(n)
				kinds[k] = int(kinds.get(k, 0)) + 1
		rows.append({"f": i, "ms": snappedf(dt, 0.01), "new": added.size(), "what": kinds, "attack": str(b.current_attack.get("kind", "")) if b.current_attack is Dictionary else ""})
		added.clear()
		last = Time.get_ticks_usec()
	var sorted := ft.duplicate()
	sorted.sort()
	var med: float = sorted[sorted.size() / 2]
	var spikes := []
	for r in rows:
		if float(r["ms"]) >= med * 4.0:
			spikes.append(r)
	spikes.sort_custom(func(x, y): return float(x["ms"]) > float(y["ms"]))
	flow.goto("lobby")
	for i in 20:
		await process_frame
	return {"median_ms": snappedf(med, 0.001), "p99_ms": snappedf(float(sorted[int(sorted.size() * 0.99)]), 0.01), "max_ms": snappedf(float(sorted[-1]), 0.01), "spikes": spikes.slice(0, 25), "spike_count": spikes.size()}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var frames := int(args[1]) if args.size() > 1 else 3600
	var runs := int(args[2]) if args.size() > 2 else 2
	seed(4242)
	var sim := [1.0e7]
	node_added.connect(_on_added)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(flow)
	await process_frame
	flow.goto("lobby")
	for i in 30:
		await process_frame
	var report := {}
	for r in runs:
		report["run%d" % r] = await run_battle(flow, frames, sim)
		print("SPIKES run", r, " median ", report["run%d" % r]["median_ms"], " p99 ", report["run%d" % r]["p99_ms"], " max ", report["run%d" % r]["max_ms"], " count ", report["run%d" % r]["spike_count"])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	quit(0)
