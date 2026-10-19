extends RefCounted
## キャラクターのデータ（data/characters.json）を読む・調べる。画面を持たない計算だけ。
## モデル（glTF）のファイルがまだないキャラは、箱の見た目で出る（has_model が false）。

const PATH := "res://data/characters.json"
const STAT_KEYS := ["hp", "move_speed", "attack_power", "attack_cooldown_sec", "attack_reach"]


static func load_config(path: String = PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## id のキャラ。なければ {}
static func find(cfg: Dictionary, id: String) -> Dictionary:
	for c in cfg.get("characters", []):
		if str(c.get("id", "")) == id:
			return c
	return {}


## モデルのファイルが、実際に読めるか
static func has_model(character: Dictionary) -> bool:
	var path := str(character.get("model", ""))
	return path != "" and ResourceLoader.exists(path)


## 動作（idle, run, jump, attack, down）に対応する、モデルの中のアニメ名。なければ ""
static func animation_for(character: Dictionary, action: String) -> String:
	var map: Variant = character.get("animations", {})
	return str(map.get(action, "")) if map is Dictionary else ""


## いまの状態から、動作を選ぶ。優先：ダウン > ジャンプ > こうげき > 走る > 待つ
static func pick_action(downed: bool, airborne: bool, attacking: bool, moving: bool) -> String:
	if downed:
		return "down"
	if airborne:
		return "jump"
	if attacking:
		return "attack"
	if moving:
		return "run"
	return "idle"


## データの誤りを探す。誤りの文のリスト（空なら問題なし）
static func validate(cfg: Dictionary) -> Array:
	var errors: Array = []
	var actions: Array = cfg.get("actions", [])
	var budgets: Dictionary = cfg.get("budgets", {})
	var ids := {}
	for c in cfg.get("characters", []):
		var id := str(c.get("id", ""))
		if id == "":
			errors.append("idがない")
			continue
		if ids.has(id):
			errors.append(id + "：idが重なっている")
		ids[id] = true
		for key in ["name", "kind", "tri_budget", "animations"]:
			if not c.has(key):
				errors.append(id + "：" + key + "がない")
		var kind := str(c.get("kind", ""))
		if budgets.has(kind) and float(c.get("tri_budget", 0)) > float(budgets[kind]):
			errors.append(id + "：面の数の予算が、種類の上限（" + str(budgets[kind]) + "）を超えている")
		var stats: Variant = c.get("stats", null)
		if not (stats is Dictionary):
			errors.append(id + "：statsがない")
		else:
			for key in STAT_KEYS:
				if not stats.has(key) or float(stats[key]) <= 0.0:
					errors.append(id + "：stats の " + key + " がない、または0以下")
		var anims: Variant = c.get("animations", {})
		if anims is Dictionary:
			for a in actions:
				if not anims.has(a):
					errors.append(id + "：動作 " + str(a) + " のアニメ名がない")
	var hero := str(cfg.get("player_character", ""))
	if hero != "" and not ids.has(hero):
		errors.append("player_character（" + hero + "）が、キャラの一覧にない")
	return errors
