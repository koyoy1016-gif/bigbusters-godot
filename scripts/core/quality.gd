extends RefCounted
## 画質の「低」「高」の切り替え（CLAUDE.md ルール9）。「低」は iPhone のブラウザを基準にする。
## 数値は data/quality.json。効果（FPSの違い）は、実機で未測定。
## 影を出す光は、グループ "sun" に入れておく。

const CONFIG_PATH := "res://data/quality.json"


static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## 名前が正しければそれ、そうでなければ既定（default）
static func resolve(name_text: String, cfg: Dictionary) -> String:
	var presets: Dictionary = cfg.get("presets", {})
	if presets.has(name_text):
		return name_text
	return str(cfg.get("default", "low"))


## 次の画質（order の順にぐるっと回る）
static func next_preset(current: String, cfg: Dictionary) -> String:
	var order: Array = cfg.get("order", [])
	if order.is_empty():
		return resolve(current, cfg)
	var i := order.find(current)
	return str(order[(i + 1) % order.size()])


## 画面に出す名前（ひくい／たかい）
static func label_of(name_text: String, cfg: Dictionary) -> String:
	var presets: Dictionary = cfg.get("presets", {})
	return str(presets.get(resolve(name_text, cfg), {}).get("label", ""))


## 画質を当てはめる。viewport：描画の設定（線のぎざぎざ・3Dの細かさ）、lights：影を出す光の一覧、戻り値は当てはめた設定
static func apply(name_text: String, cfg: Dictionary, viewport: Viewport, lights: Array) -> Dictionary:
	var key := resolve(name_text, cfg)
	var p: Dictionary = cfg["presets"][key]
	if viewport != null:
		match int(p["msaa"]):
			2:
				viewport.msaa_3d = Viewport.MSAA_2X
			4:
				viewport.msaa_3d = Viewport.MSAA_4X
			_:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.scaling_3d_scale = float(p["scale_3d"])
	for l in lights:
		if l is Light3D:
			l.shadow_enabled = bool(p["shadow"])
	Engine.max_fps = int(p["max_fps"])
	return p
