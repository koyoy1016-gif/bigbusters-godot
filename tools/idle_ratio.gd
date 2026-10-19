extends SceneTree
## ボスが「攻撃も歩きもしていない（立ち止まっている）」時間の割合を測る（AI3人つきの戦いを早送り）。
## godot --headless --path . --script res://tools/idle_ratio.gd -- [秒]
const SCENE := "res://scenes/prototype/stick_prototype.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := float(args[0]) if args.size() > 0 else 60.0
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.ai_enabled = true
	root.add_child(s)
	await process_frame
	var now := [5000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.sfx = null
	s.start_round()
	var dt := 1.0 / 30.0
	var frames := 0
	var idle := 0
	var attacking := 0
	var longest := 0.0
	var run := 0.0
	var t := 0.0
	while t < secs:
		t += dt
		now[0] = s.round_start_ms + t * 1000.0
		s.my_hp = 100.0
		s.downed = false
		s._process(dt)
		if not s.round_active():
			break
		frames += 1
		var atk: bool = not s.current_attack.is_empty()
		if atk:
			attacking += 1
		var still: bool = not atk and s.motion.speed_now < 0.4 and not s.boss_model.is_staggering()
		if still:
			if OS.get_cmdline_user_args().has("log"):
				var na: Dictionary = s._next_attack(s.awake_schedule if s.boss_model.is_awake() else s.attack_schedule, t)
				print("still t=%.2f next=%s spd=%.2f awake=%s" % [t, str(na.get("kind", "-")), s.motion.speed_now, str(s.boss_model.is_awake())])
			idle += 1
			run += dt
			longest = maxf(longest, run)
		else:
			run = 0.0
	print("IDLE frames=%d 攻撃中=%.0f%% 立ち止まり=%.0f%% いちばん長い立ち止まり=%.2f秒" % [frames, 100.0 * attacking / frames, 100.0 * idle / frames, longest])
	quit()
