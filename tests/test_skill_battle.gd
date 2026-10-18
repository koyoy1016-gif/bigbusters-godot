extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_skill_battle.gd
## 戦いの中でのXの技（斬る・ダッシュ・射撃・魔法・投げ・バリア・回復・召喚）を確かめる。

const SCENE := "res://scenes/prototype/stick_prototype.tscn"
var failures := 0
var now := [1000000.0]


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func make(char_id: String) -> Node:
	var s: Node = (load(SCENE) as PackedScene).instantiate()
	s.selected_character = char_id
	root.add_child(s)
	if s.get_node_or_null("Boss") == null:
		s._ready()
	s.clock_ms = func() -> float: return now[0]
	s.start_round()
	s.sub_crowd.update_at(0.0, s.crowd_state)
	return s


func done(s: Node) -> void:
	root.remove_child(s)
	s.free()


func _initialize() -> void:
	# 斬る（けんし）：ボスの前で、前を向いて使う
	var s := make("hero_swordsman")
	check(s.skill_name() == "斬る", "けんしの技は、斬る")
	var bz := float(s.config["boss_position"][1])
	s.player.position = Vector3(0.0, s.ground_y, bz + 3.0)
	s.facing = Vector2(0, -1)
	var hp0: float = s.boss_hp
	check(s.use_skill(), "技が使える")
	check(is_equal_approx(s.boss_hp, hp0 - s.role_value("attack_power") * 2.5), "斬る：ボスに攻撃力×2.5")
	check(not s.use_skill() and s.skill_cooldown > 0.0, "待ち時間のあいだは、もう一度は使えない")
	s._skill_update(10.0)
	s.facing = Vector2(0, 1)
	var hp1: float = s.boss_hp
	check(s.use_skill() and s.boss_hp == hp1, "うしろ向きなら、ボスに当たらない")
	s.downed = true
	s._skill_update(10.0)
	check(not s.use_skill(), "ダウン中は使えない")
	done(s)

	# ダッシュ（はやて）：動く。ダッシュ中はダメージを受けない
	s = make("sprinter")
	s.player.position = Vector3(0.0, s.ground_y, 5.0)
	s.facing = Vector2(1, 0)
	check(s.use_skill() and s.dash_left > 0.0, "ダッシュできる")
	var x0: float = s.player.position.x
	s._skill_update(0.1)
	s._skill_update(0.1)
	check(s.player.position.x > x0 + 4.0, "ダッシュで、向きに進む（" + str(s.player.position.x - x0) + "）")
	s.dash_left = 0.1
	var hp_d: float = s.my_hp
	s._take_damage(50.0)
	check(s.my_hp == hp_d, "ダッシュ中は、ダメージを受けない")
	s.dash_left = 0.0
	s._take_damage(10.0)
	check(is_equal_approx(s.my_hp, hp_d - 10.0), "ダッシュが終われば、受ける")
	done(s)

	# 射撃（じゅうし）：遠くから、まっすぐ当たる
	s = make("gunner")
	s.player.position = Vector3(0.0, s.ground_y, bz + 10.0)
	s.facing = Vector2(0, -1)
	var hp2: float = s.boss_hp
	check(s.use_skill() and is_equal_approx(s.boss_hp, hp2 - s.role_value("attack_power") * 3.0), "射撃：遠くからボスに当たる")
	s._skill_update(10.0)
	s.facing = Vector2(1, 0)
	var hp3: float = s.boss_hp
	s.use_skill()
	check(s.boss_hp == hp3, "向きがちがえば、当たらない")
	done(s)

	# 魔法（まほう）：つらぬく（サブ敵とボスの両方）
	s = make("mage")
	var sub: Vector2 = s._crowd_xz(0)
	s.player.position = Vector3(sub.x, s.ground_y, sub.y + 3.0)
	s.facing = Vector2(0, -1)
	var shp: float = s.crowd_state.hp[0]
	s.use_skill()
	check(s.crowd_state.hp[0] < shp, "魔法：サブ敵に当たる")
	done(s)

	# 投げ（ばくだん）：少し遅れて爆発
	s = make("bomber")
	s.player.position = Vector3(0.0, s.ground_y, bz + 9.0)
	s.facing = Vector2(0, -1)
	var hp4: float = s.boss_hp
	s.use_skill()
	check(not s.bomb.is_empty() and s.boss_hp == hp4, "投げ：すぐには爆発しない")
	s._skill_update(1.0)
	check(s.bomb.is_empty() and s.boss_hp < hp4, "少しあとで爆発し、ボスに当たる")
	done(s)

	# バリア（たて）：ダメージが減る
	s = make("guardian")
	s.use_skill()
	var hp5: float = s.my_hp
	s._take_damage(50.0)
	check(is_equal_approx(s.my_hp, hp5 - 10.0), "バリア：ダメージが2割になる")
	s._skill_update(10.0)
	var hp6: float = s.my_hp
	s._take_damage(50.0)
	check(is_equal_approx(s.my_hp, hp6 - 50.0), "バリアが切れたら、元に戻る")
	done(s)

	# 回復（いやし）
	s = make("healer")
	s.my_hp = 10.0
	s.use_skill()
	check(is_equal_approx(s.my_hp, 40.0), "回復：体力が増える")
	s._skill_update(20.0)
	s.my_hp = s.role_value("hp") - 5.0
	s.use_skill()
	check(s.my_hp == s.role_value("hp"), "回復は、体力の上限をこえない")
	done(s)

	# 召喚（よびだし）：一定間隔でボスにダメージ（自分の合計ダメージに数える）
	s = make("summoner")
	s.use_skill()
	var hp7: float = s.boss_hp
	s._skill_update(0.6)
	check(s.boss_hp < hp7 and s.my_hits > 0.0, "召喚：味方が、ボスにダメージを与える（自分の合計に数える）")
	s._skill_update(20.0)
	var hp8: float = s.boss_hp
	s._skill_update(1.0)
	check(s.boss_hp == hp8, "時間が切れたら、止まる")
	done(s)
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
