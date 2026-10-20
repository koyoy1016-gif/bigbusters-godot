extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v87.gd
## 版87：編成の操作。
## 確かめること：
##   1. スクロール：くわしい情報・能力のバー・枠・カードの、どこを押して上へ動かしても、下へスクロールできる（押したボタンは反応しない）
##   2. 長押しで持ち上げる：カードを長押し → 絵が指につく → 枠の上で離すと入る。キャラが入っている枠なら入れかわる。保存（メイン・なかま）も同じになる
##   3. 枠どうし：枠を長押しして別の枠で離すと、2人が入れかわる（メインも）
##   4. 枠の外で離すと、元にもどる。長押しの前に動かしたら、持ち上げない（スクロール）。短く押すと、今までのタップ
##   5. 持っていないキャラは、持ち上げられない（お知らせ）
##   6. 本物の入力（マウス・タッチの出来事）でも、長押し→動かす→離すで入れかわる
##   7. ロビーでキャラ（メインも）をタップすると、そのキャラの枠を選んだ編成の画面が開く

const SCENE := "res://scenes/game_flow.tscn"
const Flow := preload("res://scripts/flow/game_flow.gd")
const SaveData := preload("res://scripts/flow/save_data.gd")
const TEMP_SAVE := "user://test_v87_save.json"
const TEMP_AI := "user://test_v87_ai.json"
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## 指で押して動かす（タッチから作られるマウスの出来事を、画面に直接わたす。画面なしのテストでも届くように push_input の「画面の中の座標」で）
func touch_drag(sc: ScrollContainer, start: Vector2, dy: float) -> void:
	var t := InputEventMouseButton.new()
	t.button_index = MOUSE_BUTTON_LEFT
	t.pressed = true
	t.position = start
	t.global_position = start
	root.push_input(t, true)
	await process_frame
	var p: Vector2 = start
	for k in 12:
		var d := InputEventMouseMotion.new()
		d.relative = Vector2(0, dy / 12.0)
		p += d.relative
		d.position = p
		d.global_position = p
		d.button_mask = MOUSE_BUTTON_MASK_LEFT
		d.velocity = Vector2(0, dy * 4.0)
		root.push_input(d, true)
		await process_frame
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = p
	r.global_position = p
	root.push_input(r, true)
	for k in 3:
		await process_frame


func stop_controls(n: Node, out: Array) -> void:
	if n is Control and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP and not (n is Slider or n is ScrollBar or n is ScrollContainer):
		out.append(n.name)
	for c in n.get_children():
		stop_controls(c, out)


func _initialize() -> void:
	DirAccess.remove_absolute(TEMP_SAVE)
	DirAccess.remove_absolute(TEMP_AI)
	var flow: Node = (load(SCENE) as PackedScene).instantiate()
	flow.config = Flow.load_config()
	flow.config["save_path"] = TEMP_SAVE
	flow.config["ai_picks_path"] = TEMP_AI
	flow.config["audio_settings_path"] = "user://test_v87_audio.json"
	root.add_child(flow)
	await process_frame
	await process_frame
	flow.goto("lobby")
	await process_frame
	flow.goto("formation")
	for i in 4:
		await process_frame
	var fu: RefCounted = flow.formation_ui
	var sc: ScrollContainer = fu.scroll

	# ---- 1. スクロール ----
	var stops: Array = []
	stop_controls(sc, stops)
	check(stops.is_empty(), "スクロールの中に、押して動かすのを止める部品がない %s" % str(stops.slice(0, 5)))
	check(sc.get_v_scroll_bar().max_value > sc.size.y + 200.0, "中身が画面より長い（%d / %d）" % [int(sc.get_v_scroll_bar().max_value), int(sc.size.y)])
	var places := {"枠": center(fu.slot_buttons[1]), "くわしい情報": Vector2(sc.size.x * 0.5, sc.size.y * 0.55), "能力": Vector2(sc.size.x * 0.5, sc.size.y * 0.78)}
	var t0: Array = fu.team()
	for k in places:
		sc.scroll_vertical = 0
		await process_frame
		await touch_drag(sc, places[k], -360.0)
		check(sc.scroll_vertical > 150, "%s を押して上へ動かすと、下へスクロール（%d）" % [k, sc.scroll_vertical])
	check(fu.team() == t0 and fu.armed_slot < 0, "スクロールしても、押したボタン（枠）は反応しない")
	sc.scroll_vertical = 0
	await process_frame
	fu.refresh()
	await process_frame

	# ---- 2. カードを長押しして、枠へ ----
	var owned: Array = flow.owned
	var t: Array = fu.team()
	var outsider := ""
	for id in owned:
		if not t.has(id):
			outsider = str(id)
	var pick := outsider if outsider != "" else str(t[2])
	var card: Control = fu.card_buttons[pick]
	fu.pointer_down("card", pick, center(card))
	fu.tick(0.2)
	check(not fu.dragging, "0.2秒では、まだ持ち上げない")
	fu.tick(0.2)
	check(fu.dragging and fu.ghost != null and fu.ghost.is_inside_tree() and card.modulate.a < 0.5, "長押し（0.35秒）で持ち上がる（絵が出る・元のカードはうすく）")
	var s1: Vector2 = center(fu.slot_buttons[1])
	fu.pointer_move(s1)
	check(fu.hover_slot == 1 and fu.slot_buttons[1].scale.x > 1.0, "枠の上に来ると、その枠が大きく光る")
	check(fu.ghost.get_global_rect().get_center().y < s1.y, "絵は、指より少し上（指で隠れない）")
	var before: Array = fu.team()
	fu.pointer_up(s1)
	var after: Array = fu.team()
	var want: Array = before.duplicate()
	var at := want.find(pick)
	if at >= 0:
		want[at] = want[1]
	want[1] = pick
	check(after == want and not fu.dragging and fu.ghost == null, "枠の上で離すと入る（%s → なかま1）" % pick)
	check(SaveData.load_ai_picks(TEMP_AI) == after.slice(1) and str(flow.selected_character) == str(after[0]), "保存（なかま・メイン）も同じになる")
	check(fu.selected_slot == 1 and fu.focus_id == pick, "入れた枠と、そのキャラを選んだ状態になる")

	# 入っているキャラの枠へ：入れかわる
	t = fu.team()
	var a_id := str(t[3])
	fu.pointer_down("card", a_id, center(fu.card_buttons[a_id]))
	fu.tick(0.4)
	fu.pointer_move(center(fu.slot_buttons[0]))
	fu.pointer_up(center(fu.slot_buttons[0]))
	check(fu.team()[0] == a_id and fu.team()[3] == t[0], "キャラが入っている枠に置くと、2人が入れかわる（なかま3 ⇔ メイン）")
	check(str(flow.selected_character) == a_id and SaveData.load_save(TEMP_SAVE)["character"] == a_id, "メインが変わると、保存のメインも変わる")

	# ---- 3. 枠どうし ----
	t = fu.team()
	fu.pointer_down("slot", 0, center(fu.slot_buttons[0]))
	fu.tick(0.4)
	check(fu.dragging, "枠も長押しで持ち上がる")
	fu.pointer_move(center(fu.slot_buttons[2]))
	fu.pointer_up(center(fu.slot_buttons[2]))
	check(fu.team()[0] == t[2] and fu.team()[2] == t[0], "枠を別の枠へ：2人が入れかわる")

	# ---- 4. 外で離す・動かした・短く押す ----
	t = fu.team()
	fu.pointer_down("slot", 1, center(fu.slot_buttons[1]))
	fu.tick(0.4)
	fu.pointer_move(Vector2(10, 10))
	fu.pointer_up(Vector2(10, 10))
	check(fu.team() == t and fu.drag_log.back().begins_with("cancel"), "枠の外で離すと、元にもどる（変わらない）")
	fu.pointer_down("card", pick, center(fu.card_buttons[pick]))
	fu.pointer_move(center(fu.card_buttons[pick]) + Vector2(0, -40))
	fu.tick(0.5)
	check(not fu.dragging, "長押しの前に動かしたら、持ち上げない（スクロール）")
	fu.pointer_up(center(fu.card_buttons[pick]) + Vector2(0, -40))
	check(fu.team() == t and fu.armed_slot < 0, "動かして離しても、タップにはならない")
	fu.pointer_down("slot", 3, center(fu.slot_buttons[3]))
	fu.tick(0.1)
	fu.pointer_up(center(fu.slot_buttons[3]))
	check(fu.armed_slot == 3 and fu.selected_slot == 3, "短く押すと、今までのタップ（枠を選んで、入れかえ待ち）")
	fu.tap_slot(3)

	# ---- 5. 持っていないキャラ ----
	var locked := ""
	for c in flow.characters_cfg.get("characters", []):
		if not owned.has(str(c["id"])):
			locked = str(c["id"])
	if locked != "":
		fu.pointer_down("card", locked, center(fu.card_buttons[locked]))
		fu.tick(0.5)
		check(not fu.dragging and flow.toast_label.text == str(flow.config["formation_set_locked"]), "持っていないキャラは持ち上げられない（お知らせ）")
		fu.pointer_up(center(fu.card_buttons[locked]))
	else:
		check(true, "（持っていないキャラがいないので、とばす）")

	# ---- 6. 本物の入力 ----
	fu.refresh()
	await process_frame
	t = fu.team()
	var src: Control = fu.slot_buttons[1]
	var dst: Control = fu.slot_buttons[3]
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = center(src)
	mb.global_position = mb.position
	root.push_input(mb, true)
	await process_frame
	fu.tick(0.4)  # 長押しの時間（画面なしのテストでは、時間を進める）
	await process_frame
	for k in 6:
		var mm := InputEventMouseMotion.new()
		mm.position = center(src).lerp(center(dst), float(k + 1) / 6.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm, true)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = center(dst)
	up.global_position = up.position
	root.push_input(up, true)
	await process_frame
	await process_frame
	check(fu.team()[1] == t[3] and fu.team()[3] == t[1], "本物の入力：長押し→動かす→離すで、なかま1となかま3が入れかわる")

	# ---- 7. ロビーからキャラをタップ ----
	flow.goto("lobby")
	for i in 3:
		await process_frame
	flow.lobby_stage.finish()
	await process_frame
	var p0: Vector2 = flow.lobby_stage.screen_point(0)
	t = fu.team()
	check(flow.lobby_ui.gesture(p0, p0 + Vector2(2, 2)) == "pick" and flow.state == "formation" and fu.selected_slot == 0 and fu.armed_slot == 0 and fu.focus_id == str(t[0]),
		"ロビーでメインをタップすると、メインの枠を選んだ編成の画面")
	check(fu.team() == t and fu.hint_label.text == str(flow.config["formation_hint_armed"]), "チームは変わらない・「入れかえる 枠か キャラを タップ」")

	flow.queue_free()
	for p in [TEMP_SAVE, TEMP_AI, "user://test_v87_audio.json"]:
		DirAccess.remove_absolute(p)
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
