extends SceneTree
## 効果音（ファイル、間隔、戦いからの呼び出し）のテスト

const Sfx := preload("res://scripts/audio/sfx.gd")
const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0


func check(ok: bool, name: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", name)


func _init() -> void:
	var cfg := Sfx.load_config()
	var total_bytes := 0
	for name in cfg["sounds"]:
		var def: Dictionary = cfg["sounds"][name]
		var st := load(str(def["file"])) as AudioStream
		check(st != null, "音が読める: " + name)
		if st != null:
			check(st.get_length() > 0.03 and st.get_length() < 3.0, "音の長さが短い: " + name)
		total_bytes += FileAccess.get_file_as_bytes(str(def["file"])).size()
	check(total_bytes < 1000000, "効果音の合計は1MB未満：" + str(total_bytes))
	for kind in cfg["attack_sounds"]:
		check(cfg["sounds"].has(cfg["attack_sounds"][kind]), "攻撃の音が定義にある: " + kind)
	check(Sfx.gap_ok(1.0, -1.0, 0.5) and not Sfx.gap_ok(1.2, 1.0, 0.5) and Sfx.gap_ok(1.6, 1.0, 0.5), "同じ音の間隔")
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	var now := [7000000.0]
	s.clock_ms = func() -> float: return now[0]
	s.start_round()
	var sfx: Node = s.sfx
	sfx._ensure_pool()
	check(sfx != null and sfx.pool.size() == int(cfg["pool_size"]), "鳴らす回路がある")
	sfx.played = []
	s.player.position = Vector3(0.0, s.ground_y, s.boss.position.z + 3.0)
	check(s.attack() and sfx.played.has("slash") and sfx.played.has("hit"), "こうげきで音が鳴る")
	s.actions.reset()
	s.perform("sub")
	check(sfx.played.has("jump"), "サブ（跳ぶ攻撃）で、跳ぶ音が鳴る")
	sfx.played = []
	var t0: float = s.round_start_ms
	var first: Dictionary = s.attack_schedule[0]
	now[0] = t0 + float(first["start"]) * 1000.0 + 200.0
	s.combat_update(0.016)
	check(sfx.played.has(str(cfg["attack_sounds"][str(first["kind"])])), "攻撃の始まりで、予告の音が鳴る（" + str(first["kind"]) + "）")
	for a in s.attack_schedule:
		if str(a["kind"]) == "grab":
			sfx.played = []
			now[0] = t0 + float(a["start"]) * 1000.0 + 50.0
			s.combat_update(0.016)
			check(sfx.played.has("grab_warn"), "つかみの始まりで、予告の音が鳴る")
			break
	sfx.muted = true
	check(not sfx.play("hit"), "ミュートにすると鳴らない")
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
