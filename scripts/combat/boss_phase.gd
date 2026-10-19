extends RefCounted
## ボスの体力の2段階制。画面を持たない（テストしやすい）。
## 第1形態（normal）：最大 max1。0 になったら、倒れて覚醒する演出（fall、trans_sec 秒）。この間は無敵で、攻撃もしない。
## 第2形態（awake）：演出が終わったときに、体力を max2 まで全回復して始まる（第1形態とは別の体力）。0 になったら完全に倒した（dead）。
## 体力は「みんなが与えたダメージの合計（total）」から計算する（通信で合計だけを送る、いまの仕組みのまま）。
## 第2形態の体力 = max2 −（total − 覚醒が始まったときの total）。演出中に当たったダメージは数えない。

const NORMAL := "normal"
const FALL := "fall"
const AWAKE := "awake"
const DEAD := "dead"

var max1 := 4000.0
var max2 := 4000.0
var trans_sec := 3.4  ## 倒れてから覚醒するまで（ボスのモデルの stagger_sec と同じ）
var refill_sec := 1.2  ## 演出の最後の、この秒で、体力の表示が 0 から満タンまで増える
var phase := NORMAL
var trans_t := 0.0
var awake_base := 0.0  ## 第2形態が始まったときの total


func reset(m1: float, m2: float, trans: float, refill: float) -> void:
	max1 = m1
	max2 = m2
	trans_sec = trans
	refill_sec = minf(refill, trans)
	phase = NORMAL
	trans_t = 0.0
	awake_base = 0.0


## 合計ダメージが変わったとき。起きたこと（"" / "fall"＝第1形態の体力が0 / "dead"＝完全に倒した）を返す
func on_total(total: float) -> String:
	if phase == NORMAL and total >= max1:
		phase = FALL
		trans_t = 0.0
		return FALL
	if phase == AWAKE and total - awake_base >= max2:
		phase = DEAD
		return DEAD
	return ""


## 1コマ進める。起きたこと（"" / "awake"＝覚醒の演出が終わり、第2形態が始まった）を返す
func tick(delta: float, total: float) -> String:
	if phase != FALL:
		return ""
	trans_t += delta
	if trans_t >= trans_sec:
		phase = AWAKE
		awake_base = total
		return AWAKE
	return ""


## いまの形態の体力（表示用）。演出の最後で、0 から max2 まで増えていくように見せる
func hp(total: float) -> float:
	match phase:
		NORMAL:
			return maxf(0.0, max1 - total)
		FALL:
			var k := clampf((trans_t - (trans_sec - refill_sec)) / maxf(refill_sec, 0.01), 0.0, 1.0)
			return max2 * k * k * (3.0 - 2.0 * k)
		AWAKE:
			return maxf(0.0, max2 - (total - awake_base))
	return 0.0


## いまの形態の最大体力（表示用）
func max_hp() -> float:
	return max1 if phase == NORMAL else max2


## ボスにダメージが入らないか（倒れて覚醒する演出の間と、倒したあと）
func invulnerable() -> bool:
	return phase == FALL or phase == DEAD


## 攻撃してよいか
func can_attack() -> bool:
	return phase == NORMAL or phase == AWAKE


func is_awake() -> bool:
	return phase == AWAKE
