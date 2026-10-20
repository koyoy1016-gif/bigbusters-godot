extends RefCounted
## 版105（軽量化）：見た目（技の光・当たりの火花・輪・粒など）の材質を、使いまわす。
## 新しい材質は、はじめて使う時の準備が重い（PC で 1つ 0.4〜0.8 ms。スマホのブラウザでは、その数倍）。
## 前は、技や当たりのたびに材質を 2〜6 こ新しく作っていて、その1コマが長くなっていた（カクつきの原因。docs/version105.md）。
## 見た目が消える時（queue_free）に材質を返してもらい、同じ種類（key）の次の見た目で使う。
## 色・すけ具合など、使っている間に変わる所は、使う側（skill_fx.gd）が取り出す時に元にもどす。

const MAX_PER_KEY := 24  ## 1つの種類で、とっておく数の上限
static var _free: Dictionary = {}  ## key → [材質]
static var made := 0  ## 新しく作った数（テスト・測る用）
static var reused := 0  ## 使いまわした数


## 使い終わった材質があれば、それを返す（なければ null。呼ぶ側が作って mark する）
static func take(key: String) -> Material:
	var arr: Array = _free.get(key, [])
	if arr.is_empty():
		return null
	reused += 1
	return arr.pop_back()


## 新しく作った材質に、種類の印を付ける（返せるように）
static func mark(m: Material, key: String) -> Material:
	m.set_meta("fx_pool_key", key)
	made += 1
	return m


static func give(m: Material) -> void:
	if m == null or not m.has_meta("fx_pool_key"):
		return
	var key := str(m.get_meta("fx_pool_key"))
	var arr: Array = _free.get(key, [])
	if arr.size() < MAX_PER_KEY and not arr.has(m):
		arr.append(m)
		_free[key] = arr


## root が消される時（queue_free）に、root と下の見た目の材質を返す。付けかえ（いったん外して別の所へ）では返さない
static func track(root: Node) -> void:
	root.tree_exiting.connect(func() -> void:
		if root.is_queued_for_deletion():
			release_tree(root))


static func release_tree(root: Node) -> void:
	var list: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		list.append(root)
	for g in list:
		give((g as GeometryInstance3D).material_override)


## とっておいた数（テスト用）
static func free_count(key: String = "") -> int:
	if key != "":
		return (_free.get(key, []) as Array).size()
	var n := 0
	for k in _free:
		n += (_free[k] as Array).size()
	return n
