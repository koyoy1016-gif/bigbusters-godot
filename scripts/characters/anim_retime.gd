extends RefCounted
## 版72：いまある動き（Animation）の時間をのばしたり縮めたりして、新しい動きを作る（新しい素材はいらない）。
## map：[[新しい秒, 元の秒], ...]（新しい秒の小さい順）。間はまっすぐつなぐ。
## tremble：{from, to, amp, hz}。from〜to 秒の間、元の秒を amp 秒ほど小さくゆらす（力をためて、ふるえる）。
## 例：剣士の必殺技（data/characters.json の built_anims）：Sword_Attack から「構え→ため→踏み込み→斬り→構え直し」を作る。

const FPS := 30.0


## 新しい秒 t のときの、元の秒
static func source_time(map: Array, t: float, tremble: Dictionary = {}) -> float:
	if map.is_empty():
		return t
	var src := float((map[0] as Array)[1])
	if t <= float((map[0] as Array)[0]):
		src = float((map[0] as Array)[1])
	elif t >= float((map[map.size() - 1] as Array)[0]):
		src = float((map[map.size() - 1] as Array)[1])
	else:
		for i in range(1, map.size()):
			var b: Array = map[i]
			if t <= float(b[0]):
				var a: Array = map[i - 1]
				var k := (t - float(a[0])) / maxf(0.0001, float(b[0]) - float(a[0]))
				src = lerpf(float(a[1]), float(b[1]), k)
				break
	if not tremble.is_empty() and t >= float(tremble.get("from", 0.0)) and t <= float(tremble.get("to", 0.0)):
		src += sin(t * TAU * float(tremble.get("hz", 12.0))) * float(tremble.get("amp", 0.0))
	return maxf(0.0, src)


## 新しい動きの長さ（map のいちばん後ろの、新しい秒）
static func length_of(map: Array) -> float:
	return float((map[map.size() - 1] as Array)[0]) if not map.is_empty() else 0.0


## src の、回転・位置・大きさの線を、map で時間を変えて写した、新しい動き
static func build(src: Animation, map: Array, tremble: Dictionary = {}) -> Animation:
	var out := Animation.new()
	var len := length_of(map)
	out.length = len
	out.loop_mode = Animation.LOOP_NONE
	var frames := maxi(1, int(ceil(len * FPS)))
	for ti in src.get_track_count():
		var ty := src.track_get_type(ti)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		var nt := out.add_track(ty)
		out.track_set_path(nt, src.track_get_path(ti))
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		for f in frames + 1:
			var t := minf(float(f) / FPS, len)
			var s := source_time(map, t, tremble)
			match ty:
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(nt, t, src.rotation_track_interpolate(ti, s))
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, t, src.position_track_interpolate(ti, s))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(nt, t, src.scale_track_interpolate(ti, s))
	return out
