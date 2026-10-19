extends RefCounted
## 作風（docs/art-style.md）を、材質に当てはめる。段のついた陰影、縁の光、質感の模様、輪郭線。
## 輪郭線は画質「高」だけ（outline_on）。切りかえは set_outline で、場面の全部のモデルを回って付け外しする。

const CONFIG_PATH := "res://data/art_style.json"
const OUTLINE_SHADER := "res://shaders/outline.gdshader"

static var outline_on := false
static var _cfg: Dictionary = {}
static var _outline_cache := {}
static var _tex_cache := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_cfg = parsed if parsed is Dictionary else {}
	return _cfg


## 質感の名前（cloth など）の画像。なければ null
static func texture(name_text: String) -> Texture2D:
	var cfg := config()
	var paths: Dictionary = cfg.get("textures", {})
	if not paths.has(name_text):
		return null
	if not _tex_cache.has(name_text):
		_tex_cache[name_text] = load(str(paths[name_text])) as Texture2D
	return _tex_cache[name_text]


## 材質の色から、質感の名前を決める（金属っぽければ steel、そうでなければ cloth）
static func texture_for(metallic: float, hint: String = "") -> String:
	if hint != "":
		return hint
	return "steel" if metallic >= float(config().get("metal_threshold", 0.3)) else "cloth"


## 材質に作風を当てはめる。tex は質感の名前（空なら模様なし）
static func style_material(mat: StandardMaterial3D, tex: String = "") -> void:
	var cfg := config()
	if bool(cfg.get("toon", true)):
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.rim_enabled = float(cfg.get("rim", 0.0)) > 0.0
	mat.rim = float(cfg.get("rim", 0.0))
	mat.rim_tint = float(cfg.get("rim_tint", 0.5))
	if tex != "":
		var t := texture(tex)
		if t != null:
			mat.albedo_texture = t
			mat.uv1_triplanar = true
			var s := float(cfg.get("texture_scale", 5.0))
			mat.uv1_scale = Vector3(s, s, s)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func outline_material(width: float) -> ShaderMaterial:
	var key := snappedf(width, 0.0001)
	if not _outline_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(OUTLINE_SHADER) as Shader
		m.set_shader_parameter("line_color", Color(str(config().get("outline_color", "#0b0d1c"))))
		m.set_shader_parameter("width", width)
		_outline_cache[key] = m
	return _outline_cache[key]


## 材質に、輪郭線の「次の描画」をつける（outline_on のときだけ）。ふとさは width
static func apply_outline(mat: Material, width: float) -> void:
	if mat == null:
		return
	mat.next_pass = outline_material(width) if outline_on else null


## 場面の下のモデルを回って、輪郭線を付け外しする（画質の切りかえ用）。boss_width は、メタ "outline_boss" をもつ物に使う
static func set_outline(root: Node, on: bool) -> int:
	outline_on = on
	return _walk(root)


static func _walk(node: Node) -> int:
	var n := 0
	var cfg := config()
	if node is MeshInstance3D and _styled(node):
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var w := float(cfg.get("outline_width_boss", 0.05)) if _in_boss(mi) else float(cfg.get("outline_width", 0.014))
			if mi.mesh is PrimitiveMesh:
				var pm := mi.mesh as PrimitiveMesh
				if pm.material != null and pm.material is StandardMaterial3D:
					apply_outline(pm.material, w)
					n += 1
			else:
				for i in mi.mesh.get_surface_count():
					var sm := mi.mesh.surface_get_material(i)
					if sm is StandardMaterial3D:
						apply_outline(sm, w)
						n += 1
	for c in node.get_children():
		n += _walk(c)
	return n


## キャラ・ボスの下にある物だけに、輪郭線をつける（床や柱には付けない）
static func _styled(node: Node) -> bool:
	var p := node
	while p != null:
		if p.is_in_group("styled"):
			return true
		p = p.get_parent()
	return false


static func _in_boss(node: Node) -> bool:
	var p := node
	while p != null:
		if p.name == "Boss" or p.has_meta("outline_boss"):
			return true
		p = p.get_parent()
	return false
