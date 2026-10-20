extends RefCounted
## 版82：持っているキャラと、編成（メイン＋なかま3人）の決まり（画面を持たない計算だけ。テストしやすい）。
## 情報は data/character_profiles.json（レア度・説明・防御・覚醒・はじめに持っているキャラ）。

const PROFILES_PATH := "res://data/character_profiles.json"
const TEAM_SIZE := 4


static func load_profiles(path: String = PROFILES_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return parsed if parsed is Dictionary else {}


static func profile(profiles: Dictionary, id: String) -> Dictionary:
	return (profiles.get("characters", {}) as Dictionary).get(id, {})


static func rarity(profiles: Dictionary, id: String) -> String:
	return str(profile(profiles, id).get("rarity", "N"))


## 持っているキャラ。保存になければ、はじめのキャラ（＋いま使っているキャラ。前から遊んでいる人が、使っていたキャラを失わないように）。
## 知らないID はのぞく。並びは、キャラの一覧（all_ids）の順
static func owned_list(saved: Array, profiles: Dictionary, all_ids: Array, current: String = "") -> Array:
	var want := {}
	if saved.is_empty():
		for id in profiles.get("starter_owned", []):
			want[str(id)] = true
		if current != "":
			want[current] = true
	else:
		for id in saved:
			want[str(id)] = true
	var out: Array = []
	for id in all_ids:
		if want.has(str(id)):
			out.append(str(id))
	return out


## 編成をなおす：持っているキャラだけ・同じキャラは1回だけ・4人まで。足りなければ、持っているキャラで埋める
static func fix_team(team: Array, owned: Array) -> Array:
	var out: Array = []
	for id in team:
		var s := str(id)
		if owned.has(s) and not out.has(s) and out.size() < TEAM_SIZE:
			out.append(s)
	for id in owned:
		if out.size() >= TEAM_SIZE:
			break
		if not out.has(str(id)):
			out.append(str(id))
	return out


## 枠 slot に、キャラ id を入れる。ほかの枠にいれば、入れかえる（同じキャラが2人にならない）
static func assign(team: Array, slot: int, id: String) -> Array:
	var out := team.duplicate()
	if slot < 0 or slot >= out.size():
		return out
	var at := out.find(id)
	if at == slot:
		return out
	if at >= 0:
		out[at] = out[slot]
	out[slot] = id
	return out


## 枠 a と枠 b を入れかえる
static func swap(team: Array, a: int, b: int) -> Array:
	var out := team.duplicate()
	if a < 0 or b < 0 or a >= out.size() or b >= out.size() or a == b:
		return out
	var t: Variant = out[a]
	out[a] = out[b]
	out[b] = t
	return out
