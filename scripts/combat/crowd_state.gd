extends RefCounted
## サブ敵の体力と復活。画面を持たない計算だけ。時間は「戦いが始まってからの秒数」。
## サブ敵の体力は、いまは自分の画面の中だけで数える（通信しない）。ダメージの計算は damage.gd の関数を使う。

const Damage := preload("res://scripts/combat/damage.gd")

var max_hp := 20.0
var hp := PackedFloat32Array()
var respawn_at := PackedFloat32Array()
var kills := 0


func reset(count: int, hp_value: float) -> void:
	max_hp = hp_value
	hp = PackedFloat32Array()
	respawn_at = PackedFloat32Array()
	hp.resize(count)
	respawn_at.resize(count)
	hp.fill(hp_value)
	respawn_at.fill(0.0)
	kills = 0


func count() -> int:
	return hp.size()


func is_alive(i: int) -> bool:
	return i >= 0 and i < hp.size() and hp[i] > 0.0


## 復活の時間が来た敵を、体力を満タンにして戻す
func refresh(t: float) -> void:
	for i in hp.size():
		if hp[i] <= 0.0 and t >= respawn_at[i]:
			hp[i] = max_hp


## i 番目に damage を与える。倒れたら true（復活は respawn_sec 秒後）
func hit(i: int, damage: float, t: float, respawn_sec: float) -> bool:
	if not is_alive(i):
		return false
	hp[i] = Damage.apply_damage(hp[i], damage)
	if hp[i] <= 0.0:
		respawn_at[i] = t + respawn_sec
		kills += 1
		return true
	return false


## from（床の上の位置）から reach 以内にいる、生きているいちばん近い敵の番号。いなければ -1
func nearest_alive(positions: PackedVector3Array, from: Vector3, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in mini(positions.size(), hp.size()):
		if not is_alive(i):
			continue
		var d := Vector2(positions[i].x - from.x, positions[i].z - from.z).length()
		if d <= reach and d < best_d:
			best = i
			best_d = d
	return best
