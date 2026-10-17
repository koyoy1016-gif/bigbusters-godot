extends RefCounted
## 合言葉（数字だけの文字列）の検査と、部屋のデータの場所の組み立て。
## 通信はしない。桁数・人数の上限は data/network.json から読む。

const CONFIG_PATH := "res://data/network.json"
const ROOMS_ROOT := "rooms"


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


## 半角の数字 0〜9 だけで、ちょうど digits 桁なら true（空白、符号、小数点、全角の数字は不可）
static func is_valid_code(code: String, digits: int) -> bool:
	if digits <= 0 or code.length() != digits:
		return false
	for i in code.length():
		var c := code.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return true


## 合言葉から、部屋のデータの場所（例：rooms/1234）を作る。合言葉が不正なら空の文字列
static func room_path(code: String, digits: int) -> String:
	if not is_valid_code(code, digits):
		return ""
	return "%s/%s" % [ROOMS_ROOT, code]
