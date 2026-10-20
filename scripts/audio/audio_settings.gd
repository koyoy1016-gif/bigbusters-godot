extends RefCounted
## 版85：音の大きさの設定（音楽・効果音。0〜1）。この端末だけに残す（クラウドのセーブには入れない。端末ごとにちがうので）。
## はじめの値は data/bgm.json の user_default。

const KEYS := ["music", "sfx"]


static func defaults(bgm_cfg: Dictionary) -> Dictionary:
	var d: Dictionary = bgm_cfg.get("user_default", {})
	return {"music": clampf(float(d.get("music", 0.8)), 0.0, 1.0), "sfx": clampf(float(d.get("sfx", 1.0)), 0.0, 1.0)}


static func load_settings(path: String, bgm_cfg: Dictionary) -> Dictionary:
	var data := defaults(bgm_cfg)
	if path == "" or not FileAccess.file_exists(path):
		return data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for k in KEYS:
			var v: Variant = parsed.get(k, null)
			if v is float or v is int:
				data[k] = clampf(float(v), 0.0, 1.0)
	return data


static func write_settings(path: String, data: Dictionary) -> bool:
	if path == "":
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var out := {}
	for k in KEYS:
		out[k] = snappedf(clampf(float(data.get(k, 1.0)), 0.0, 1.0), 0.01)
	file.store_string(JSON.stringify(out))
	return true
