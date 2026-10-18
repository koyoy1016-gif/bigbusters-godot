extends RefCounted
## 遊んだ記録（コイン、倒した回数、画質の選び）の保存。ブラウザでは、そのブラウザの中に残る（消すと失われる）。
## 引き継ぎ（別の端末へ）は未対応（ログインの仕組みを入れるかは未決）。

const DEFAULTS := {"coins": 0, "wins": 0, "quality": "", "character": ""}


static func load_save(path: String) -> Dictionary:
	var data := DEFAULTS.duplicate()
	if not FileAccess.file_exists(path):
		return data
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		for key in ["coins", "wins"]:
			var v: Variant = parsed.get(key, null)
			if (v is float or v is int) and float(v) >= 0.0:
				data[key] = int(v)
		if parsed.get("quality", null) is String:
			data["quality"] = parsed["quality"]
		if parsed.get("character", null) is String:
			data["character"] = parsed["character"]
	return data


static func write_save(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"coins": int(data.get("coins", 0)), "wins": int(data.get("wins", 0)), "quality": str(data.get("quality", "")), "character": str(data.get("character", ""))}))
	return true
