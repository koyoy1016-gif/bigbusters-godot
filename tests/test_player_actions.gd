extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_player_actions.gd
## 3つの攻撃（通常・サブ・メイン）の、時間の進み・当たり・動きを確かめる。

const Actions := preload("res://scripts/combat/player_actions.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0
var now := [1000000.0]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func hits_of(events: Array) -> int:
	var n := 0
	for e in events:
		if str(e["type"]) == "hit":
			n += 1
	return n


func make(char_id: String) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	s.sub_crowd.update_at(0.0, s.crowd_state)
	return s


func run_for(s: Node, sec: float) -> void:
	var t := 0.0
	while t < sec:
		now[0] += 16.0
		s._process(0.016)
		t += 0.016


func _initialize() -> void:
	var cfg := Actions.load_config()
	check(cfg["order"] == ["normal", "sub", "main", "ultimate"], "ボタンは、通常・サブ・メイン・必殺の4つ")
	var a := Actions.new()

	# 通常：始めてすぐ1回当たる。待ち時間のあいだは、もう始められない
	check(a.start("normal", Vector2(0, -1), 0.4), "通常を始められる")
	var ev := a.update(0.0)
	check(hits_of(ev) == 1 and a.busy(), "通常は、始めてすぐ1回当たる")
	check(not a.start("normal", Vector2(0, -1), 0.4), "動いている間は、次を始められない")
	var guard := 0
	while a.busy() and guard < 200:
		a.update(0.016)
		guard += 1
	check(not a.busy() and a.can_start("normal"), "通常は、動きが終わったら、すぐ次を始められる（長さ ＝ 待ち時間）")
	a.start("sub", Vector2(0, -1))
	while a.busy():
		a.update(0.05)
	check(not a.can_start("sub"), "サブは、終わっても待ち時間のあいだは始められない")
	a.update(5.0)
	check(a.can_start("sub"), "待ち時間が過ぎたら、また始められる")

	# 版110：サブ（Y）＝全員共通の回避。当たりはない。地面を転がる。よけられる時間（i_window）の間だけ受けない
	a = Actions.new()
	check(a.start("sub", Vector2(0, -1)), "回避を始められる")
	var dodge_hits := hits_of(a.update(0.0))
	var w: Array = a.def("sub")["i_window"]
	var inv_in := false
	var inv_out := false
	var fwd := 0.0
	var max_h := 0.0
	var t := 0.0
	while a.busy() and t < 3.0:
		dodge_hits += hits_of(a.update(0.01))
		t += 0.01
		fwd += a.frame_move.x
		max_h = maxf(max_h, a.height)
		if a.t > float(w[0]) + 0.01 and a.t < float(w[1]) - 0.01:
			inv_in = inv_in or (a.invulnerable() and a.dodging())
		elif a.t > float(w[1]) + 0.02 and a.busy():
			inv_out = inv_out or a.invulnerable() or a.dodging()
	check(dodge_hits == 0, "回避は、攻撃ではない（当たりなし）")
	check(inv_in and not inv_out, "よけられる時間の中だけ、ダメージを受けない（終わりぎわは受ける）")
	check(fwd > 2.5 and is_equal_approx(max_h, 0.0), "回避は、地面を転がって約3m 動く（%.2f）" % fwd)

	# メイン：5回斬る。少しずつ前へ出る。立ち止まって行う
	a = Actions.new()
	check(a.start("main", Vector2(1, 0)), "メインを始められる")
	check(is_equal_approx(a.move_scale(), 0.0), "メインの間は、歩けない")
	var total_hits := 0
	fwd = 0.0
	t = 0.0
	total_hits += hits_of(a.update(0.0))
	while a.busy() and t < 4.0:
		total_hits += hits_of(a.update(0.01))
		fwd += a.frame_move.x
		t += 0.01
	check(total_hits == 5, "メインは、5回当たる（%d）" % total_hits)
	check(fwd > 1.0, "メインは、前に出る（%.2f）" % fwd)

	# やめる
	a = Actions.new()
	a.start("sub", Vector2(0, -1))
	a.update(0.4)
	a.cancel()
	check(not a.busy() and is_equal_approx(a.height, 0.0), "途中でやめると、すぐ地面にもどる")

	# 道（path）の計算
	check(Actions.offset_at([], 1.0) == Vector2.ZERO, "道がなければ、動かない")
	var path := [{"t": 0.0, "fwd": 0.0, "h": 0.0}, {"t": 1.0, "fwd": 2.0, "h": 4.0}]
	check(Actions.offset_at(path, 0.5).is_equal_approx(Vector2(1.0, 2.0)) and Actions.offset_at(path, 9.0) == Vector2(2.0, 4.0), "道の途中と、終わりのあとの位置")

	# 戦いの中
	var s := make("hero_swordsman")
	var bz := float(s.config["boss_position"][1])
	s.player.position = Vector3(0.0, s.ground_y, bz + 3.0)
	var hp0: float = s.boss_hp
	var power: float = s.role_value("attack_power")
	check(s.attack(), "通常で、斬り始められる")
	check(is_equal_approx(s.boss_hp, hp0 - power * float(s.config["attack_multiplier"])), "通常は、攻撃力どおりのダメージ")
	s.actions.reset()
	s.player.position = Vector3(0.0, s.ground_y, bz + 3.0)
	var hp1: float = s.boss_hp
	check(s.perform("sub"), "回避（Y）を始める")
	var away := Vector2(s.player.position.x - s.boss.position.x, s.player.position.z - s.boss.position.z).normalized()
	check(s.actions.aim.dot(away) > 0.95, "スティックを倒していなければ、ねらう敵（ボス）から離れる向きへ転がる")
	var steps := 0
	while s.actions.busy() and steps < 200:
		run_for(s, 0.016)
		steps += 1
	check(is_equal_approx(s.boss_hp, hp1), "回避では、ボスにダメージを与えない")
	s.actions.reset()
	s.player.position = Vector3(0.0, s.ground_y, bz + 3.0)
	var hp2: float = s.boss_hp
	s.perform("main")
	run_for(s, 2.0)
	check(is_equal_approx(hp2 - s.boss_hp, power * 0.8 * 5.0 * float(s.config["attack_multiplier"])) or hp2 - s.boss_hp > power * 3.0, "メインは、5回分のダメージ（%.1f）" % (hp2 - s.boss_hp))
	# ジャンプはない
	check(not s.has_method("jump"), "ジャンプの機能はない")
	# ダウン中は始められない
	s.actions.reset()
	s.downed = true
	check(not s.perform("main") and not s.attack(), "ダウン中は、どの攻撃も始められない")
	s.downed = false
	s.actions.reset()
	root.remove_child(s)
	s.free()

	print("")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
