extends SceneTree
## 版79：動きの、足の高さを調べる（床にうく・しずむを見つける）。
## godot --headless --path . --script res://tools/check_feet.gd -- キャラのid 動き [コマ数]
## 環境変数 EXTRA_ANIMS（JSON {名前: spec}）で、試しの動きも調べられる。足首（foot）の高さを、静止の高さとの差（m）で出す
const CV := preload("res://scripts/characters/character_view.gd")
const CD := preload("res://scripts/characters/character_data.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id := args[0]
	var n := int(args[2]) if args.size() > 2 else 8
	var def: Dictionary = CD.find(CD.load_config(), id).duplicate(true)
	var extra := OS.get_environment("EXTRA_ANIMS")
	if extra != "" and FileAccess.file_exists(extra):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(extra))
		if d is Dictionary:
			var ba: Dictionary = def.get("built_anims", {})
			ba.merge(d, true)
			def["built_anims"] = ba
	var v: Node3D = CV.new()
	root.add_child(v)
	v.setup(def)
	var sk: Skeleton3D = v.model.find_children("*", "Skeleton3D", true, false)[0]
	var fl := sk.find_bone("foot.L")
	var fr := sk.find_bone("foot.R")
	var rest_y := sk.get_bone_global_rest(fl).origin.y
	for an in args[1].split(","):
		var anim := CD.animation_for(def, an)
		if anim == "" or not v.player.has_animation(anim):
			anim = an
		if not v.player.has_animation(anim):
			print("NO ANIM ", anim)
			continue
		var len: float = v.player.get_animation(anim).length
		var line := "%s len=%.2f:" % [anim, len]
		for i in n:
			var t := len * float(i) / float(maxi(1, n - 1))
			v.player.play(anim)
			v.player.seek(minf(t, len - 0.001), true)
			v.player.pause()
			for k in 2:
				await process_frame
			sk.force_update_all_bone_transforms()
			var yl := sk.get_bone_global_pose(fl).origin.y - rest_y
			var yr := sk.get_bone_global_pose(fr).origin.y - rest_y
			line += " t%.2f[%+.2f %+.2f]" % [t, yl, yr]
		print(line)
	quit(0)
