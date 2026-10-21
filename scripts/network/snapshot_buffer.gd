extends RefCounted
## 版107：ほかの人の位置を、サーバーの時刻つきでためて、「少し前の時刻」の位置を、となりの2つの記録の間でなめらかにつないで求める
## （スナップショット補間）。
## 前は、届いた位置へ毎コマ少しずつ近づけていた。届く間隔は通信でばらつく（0.05〜0.3秒）ので、速くなったり遅くなったりして、
## カクカク動いて見えた。いまは、送った人の時刻（サーバーの時計）でならべ、一定の遅れ（delay_ms）だけ前を見せるので、
## 送った人の動きと同じ速さで、なめらかに動く。
## 遅れ：「前の記録の送った時刻から、次の記録が届くまで」（＝記録がとぎれる一番長い時間）を覚えておき、その多め（quantile）の値にする
## （data/prototype_stick.json の net_interp）。これより短いと、見せる時刻が最後の記録を追いこして、のばす（先読み）ことが多くなる。
## 記録が足りない時（届くのが遅れた時）は、最後の速さで少しだけ先へのばし（extrap_ms まで）、それ以上はその場で止める。
## 遅れて届いた記録で、見せていた位置がずれた時は、ぱっと飛ばさず、ずれ（correction）を少しずつ消す。
## 大きく飛んだ時（snap_dist より遠い：戦いの始まりで最初の位置へもどる など）は、すべらせずに、そのまま飛ぶ。

const MAX_SAMPLES := 40
const LAG_KEEP := 30

var samples: Array = []  ## [{"t": サーバーの時刻(ms), "p": Vector2}]（古い順）
var lags: Array = []  ## 前の記録の送った時刻から、次の記録が届くまで（ms）
var delay_ms := 150.0  ## いま使っている遅れ
var correction := Vector2.ZERO  ## 見せる位置のずれ（少しずつ 0 にする）
var snap_dist := 0.1  ## これより遠く飛んだら、すべらせない（位置と同じ単位）
var quantile := 0.9  ## 遅れに使う、とぎれる時間の多めの値（0.9 ＝ 10回に9回は、のばさずにすむ）

var _settled := false
var _want := -1.0  ## とぎれる時間から決めた遅れ（記録が増えた時だけ計算しなおす）
var _last_rt := -1.0
var _last_extrap := 0.0


## 位置を1つ足す。t：送った時刻（サーバーの時計）、arrival：受け取った時刻（サーバーの時計）。
## 送った時刻が、受け取った時刻とかけはなれていたら（古い版の画面・時計のくるい）、受け取った時刻を使う。
## 同じか古い時刻の記録は捨てる（同じ位置を何回も読むため）。足したら true
func push(t: float, p: Vector2, arrival: float, max_skew_ms: float = 3000.0) -> bool:
	var tt := t
	if absf(arrival - t) > max_skew_ms:
		tt = arrival
	if not samples.is_empty() and tt <= float(samples[-1]["t"]):
		return false
	var track := _last_rt >= 0.0 and not samples.is_empty()
	var before := _raw(_last_rt, _last_extrap, p) if track else Vector2.ZERO
	if not samples.is_empty():
		lags.append(maxf(0.0, arrival - float(samples[-1]["t"])))
		if lags.size() > LAG_KEEP:
			lags.pop_front()
		_want = -1.0
	samples.append({"t": tt, "p": p})
	if samples.size() > MAX_SAMPLES:
		samples.pop_front()
	if track:
		var jump := before - _raw(_last_rt, _last_extrap, p)
		if (jump + correction).length() < snap_dist:
			correction += jump  # 見せていた位置から、ぱっと飛ばない
		else:
			correction = Vector2.ZERO
	return true


## 遅れを決めなおす：とぎれる時間の多め（quantile）の値（min〜max の間）。
## 急に変えると、見せる時刻がとんで、動きが飛ぶので、1秒に rate_ms までずつ近づける。deadband_ms より小さい差なら変えない
## （delta：前のコマからの秒。0 ならすぐ合わせる）
func update_delay(send_interval_ms: float, min_ms: float, max_ms: float, delta: float = 0.0, rate_ms: float = 30.0, deadband_ms: float = 15.0) -> float:
	if _want < 0.0:
		_want = send_interval_ms * 2.0
		if not lags.is_empty():
			var s := lags.duplicate()
			s.sort()
			_want = float(s[int(round((s.size() - 1) * quantile))])
	var want := clampf(_want, min_ms, max_ms)
	if not _settled or delta <= 0.0:
		delay_ms = want
		_settled = lags.size() >= 3
	elif absf(want - delay_ms) > deadband_ms:
		delay_ms = move_toward(delay_ms, want, rate_ms * delta)
	return delay_ms


func is_empty() -> bool:
	return samples.is_empty()


## render_t（サーバーの時計）の位置（ずれ correction をふくむ）。記録がなければ fallback
func sample(render_t: float, extrap_ms: float, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if samples.is_empty():
		return fallback
	_last_rt = render_t
	_last_extrap = extrap_ms
	return _raw(render_t, extrap_ms, fallback) + correction


## ずれを少しずつ消す（1秒に per_sec の割合で）
func ease_correction(delta: float, per_sec: float) -> void:
	correction *= exp(-per_sec * delta)
	if correction.length_squared() < 1.0e-10:
		correction = Vector2.ZERO


func _raw(render_t: float, extrap_ms: float, fallback: Vector2) -> Vector2:
	var n := samples.size()
	if n == 0:
		return fallback
	if render_t <= float(samples[0]["t"]):
		return samples[0]["p"]
	var last: Dictionary = samples[n - 1]
	if render_t >= float(last["t"]):
		if n < 2:
			return last["p"]
		var prev: Dictionary = samples[n - 2]
		var dt := float(last["t"]) - float(prev["t"])
		var step: Vector2 = (last["p"] as Vector2) - (prev["p"] as Vector2)
		if dt <= 0.0 or step.length() >= snap_dist:
			return last["p"]
		return (last["p"] as Vector2) + step / dt * minf(render_t - float(last["t"]), extrap_ms)
	# 2つの記録の間（新しい方から探す。ふつうは最後の近く）
	var i := n - 2
	while i > 0 and float(samples[i]["t"]) > render_t:
		i -= 1
	var a: Dictionary = samples[i]
	var b: Dictionary = samples[i + 1]
	var k := clampf((render_t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.001), 0.0, 1.0)
	if ((b["p"] as Vector2) - (a["p"] as Vector2)).length() >= snap_dist:
		return b["p"] if k >= 0.5 else a["p"]  # 大きく飛んだ所は、すべらせない
	return (a["p"] as Vector2).lerp(b["p"], k)


## 古い記録を捨てる（render_t より keep_ms 以上前で、補間に使わない物）
func trim(render_t: float, keep_ms: float = 1000.0) -> void:
	while samples.size() > 2 and float(samples[1]["t"]) < render_t - keep_ms:
		samples.pop_front()
