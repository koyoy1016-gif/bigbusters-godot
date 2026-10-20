extends RefCounted
## 版91：戦いのカメラの置き方（高さ・角度・画角）。data/prototype_stick.json の camera_rig。
## 前（版90まで）は、たて画面で画角を「横 78°」にしていたので、たての画角が 110° 近くになり、
## 画面の下の白線がとても太く、上の建物が大きくかたむいて見えた（広角のゆがみ）。
## 版91：画角を「たて」で決めて（たて 70°）、そのぶんカメラを少し遠くへ。見える横の広さ（view_width_m）は、画面の形から距離を計算して保つ。
## 見下ろす角度（pitch_deg）は 31°（前は 50°）：交差点の先の、建物・看板・空が画面の上に見える（写真の見え方に近い）。

## 画面の大きさ → {fov, keep_height, offset（見る点からカメラへ）, look_h（見る点の高さ）, dist, portrait}
static func rig_for(cfg: Dictionary, screen: Vector2) -> Dictionary:
	var portrait := screen.y > screen.x
	var all: Dictionary = cfg.get("camera_rig", {})
	var r: Dictionary = all.get("portrait" if portrait else "landscape", {})
	if r.is_empty():
		return {}
	var fov := float(r.get("fov", 60.0))
	var aspect := screen.x / maxf(screen.y, 1.0)
	var half_h := atan(tan(deg_to_rad(fov) * 0.5) * aspect)  # 横の画角の半分
	var dist := clampf(float(r.get("view_width_m", 24.0)) * 0.5 / maxf(tan(half_h), 0.01), float(r.get("min_dist_m", 10.0)), float(r.get("max_dist_m", 40.0)))
	var pitch := deg_to_rad(float(r.get("pitch_deg", 32.0)))
	return {
		"portrait": portrait,
		"fov": fov,
		"keep_height": true,
		"dist": dist,
		"offset": Vector3(0.0, dist * sin(pitch), dist * cos(pitch)),
		"look_h": float(r.get("look_height_m", 0.0)),
	}


## 画面のゆれ（強い攻撃）。前は毎フレームでたらめに動かしていた（背景がガタガタはねる）。
## 版91：2つの波を重ねた、なめらかなゆれ（だんだん小さく）。t：ゆれ始めからの秒、left：のこりの割合（1→0）
static func shake_offset(cfg: Dictionary, t: float, amp: float, left: float) -> Vector3:
	var all: Dictionary = cfg.get("camera_rig", {})
	var hz: Array = all.get("shake_hz", [17.0, 23.0])
	var a := amp * left * left
	var w1 := TAU * float(hz[0])
	var w2 := TAU * float(hz[1])
	return Vector3(sin(t * w1) * 0.8 + sin(t * w2 + 1.3) * 0.2, (sin(t * w2) * 0.6 + sin(t * w1 + 2.1) * 0.4) * 0.5, 0.0) * a


## ばねのように、なめらかについていく（クリティカルダンピング）。戻り値 [新しい位置, 新しい速さ]。smooth_sec：だいたい追いつくまでの秒
static func smooth_damp(cur: Vector3, goal: Vector3, vel: Vector3, smooth_sec: float, delta: float) -> Array:
	var omega := 2.0 / maxf(smooth_sec, 0.0001)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + change * omega) * delta
	var nv := (vel - temp * omega) * e
	var out := goal + (change + temp) * e
	return [out, nv]
