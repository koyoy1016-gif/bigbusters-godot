extends RefCounted
## 画質の「低」「高」の切り替え（CLAUDE.md ルール9）。「低」は iPhone のブラウザを基準にする。
## 数値は data/quality.json。効果（FPSの違い）は、実機で未測定。画面の画素数に合わせて、3Dの細かさを決める（scale_for）。
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


## 3Dの細かさ（1.0＝画面と同じ）。画面の画素数 pixels が多いほど小さくして、3Dを描く画素数を target_3d_pixels 前後にそろえる。
## iPhone の画面は約360万画素あり、そのまま描くと重い（文字やボタンは別に、くっきり描かれる）
static func scale_for(pixels: float, p: Dictionary) -> float:
	var top := float(p.get("scale_3d", 1.0))
	var target := float(p.get("target_3d_pixels", 0.0))
	if target <= 0.0 or pixels <= 0.0:
		return top
	return clampf(sqrt(target / pixels), float(p.get("min_scale_3d", 0.3)), top)


## 描く先の画素数（ウィンドウなら本当の画素の数。スマホでは、画面の見た目の大きさより多い）
static func pixels_of(viewport: Viewport) -> float:
	if viewport is Window:
		var w := (viewport as Window).size
		return float(w.x * w.y)
	if viewport is SubViewport:
		var s := (viewport as SubViewport).size
		return float(s.x * s.y)
	return 0.0


## 画質を当てはめる。viewport：描画の設定（線のぎざぎざ・3Dの細かさ）、lights：影を出す光の一覧、戻り値は当てはめた設定
static func apply(name_text: String, cfg: Dictionary, viewport: Viewport, lights: Array) -> Dictionary:
	var key := resolve(name_text, cfg)
	var p: Dictionary = cfg["presets"][key]
	if p.has("shadow_size"):
		RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_size"]), true)
	if viewport != null:
		match int(p["msaa"]):
			2:
				viewport.msaa_3d = Viewport.MSAA_2X
			4:
				viewport.msaa_3d = Viewport.MSAA_4X
			_:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.scaling_3d_scale = scale_for(pixels_of(viewport), p)
	for l in lights:
		if l is Light3D:
			l.shadow_enabled = bool(p["shadow"])
		if l is DirectionalLight3D:
			# 影は1段（1回）で描くと軽い。段を増やすと、そのぶん体を何回も描く
			var dl := l as DirectionalLight3D
			match int(p.get("shadow_splits", 1)):
				2:
					dl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
				4:
					dl.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				_:
					dl.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			dl.directional_shadow_max_distance = float(p.get("shadow_distance", 45.0))
	Engine.max_fps = int(p["max_fps"])
	return p
