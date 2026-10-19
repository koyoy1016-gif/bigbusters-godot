extends RefCounted
## ボスの攻撃の選び方（重み付きランダム）。画面を持たない（テストしやすい）。
## 決まった順番はやめ、使える攻撃の中から、重みでくじ引きする。重みは data/boss_attacks.json の各攻撃の "ai"：
##   forms：{normal: 重み, awake: 重み}（0 や書いていない形態では使わない）
##   range：[近い, 遠い]（ねらう人までの距離 m がこの間なら、重みそのまま。外なら far_mult 倍）
##   cooldown_sec：一度使ったら、この秒は使わない
##   strong：強い攻撃（続くと重みを下げる）
##   ultimate：必殺技（覚醒のときだけ。ultimate_first_sec・ultimate_cooldown_sec を守る）
##   not_after：この攻撃のすぐあとには出さない攻撃
##   feint_chance：フェイント（ためを長くして、一度ふりかけてやめる）を入れる確率
## 共通の設定は data/boss_attacks.json の "ai"（history、repeat_mult、strong_streak_mult、fallback など）。
## くじの乱数は、戦いの開始の時刻と攻撃の番号から作る（同じ戦い・同じ状況なら同じ選び方）。
## 距離は、それぞれの画面で見えている位置を使う（通信中は、画面ごとに選び方がずれることがある：未確認）

const Attacks := preload("res://scripts/combat/boss_attacks.gd")

var cfg: Dictionary = {}
var round_start_ms := 0.0
var cur: Dictionary = {}  ## いまの攻撃 {n, kind, start, end, feint}
var nxt: Dictionary = {}  ## 次の攻撃（決まっていれば）{n, kind, start, feint}
var n := 0
var next_start := 0.0
var history: Array = []  ## 使った攻撃の種類（新しい順）
var last_end := {}  ## 攻撃の種類 → 最後に終わった時刻
var last_ult_end := -999.0
var awake_since := -1.0  ## 覚醒した時刻（第2形態の始まり）


func reset(config: Dictionary, start_ms: float) -> void:
	cfg = config
	round_start_ms = start_ms
	cur = {}
	nxt = {}
	n = 0
	next_start = float(cfg.get("first_delay_sec", 3.0))
	history = []
	last_end = {}
	last_ult_end = -999.0
	awake_since = -1.0


## いまの攻撃をやめ、次の攻撃を delay 秒後からにする（ボスが倒れたとき・覚醒したとき）
func interrupt(t: float, delay: float) -> void:
	cur = {}
	nxt = {}
	next_start = t + delay


## 覚醒した（第2形態が始まった）
func on_awake(t: float) -> void:
	awake_since = t
	interrupt(t, float((cfg.get("ai", {}) as Dictionary).get("after_awake_delay_sec", 0.8)))


## 1コマ進める。form："normal" / "awake"。dist_of：攻撃の番号 → ねらう人までの距離（m。わからなければ -1）を返す関数
func update(t: float, form: String, dist_of: Callable) -> void:
	if not cur.is_empty() and t >= float(cur["end"]):
		_finish(cur)
		cur = {}
	if cur.is_empty() and nxt.is_empty():
		nxt = choose(maxf(next_start, 0.0), form, dist_of)
	if cur.is_empty() and not nxt.is_empty() and t >= float(nxt["start"]):
		var k: Dictionary = cfg["kinds"][str(nxt["kind"])]
		cur = nxt.duplicate()
		cur["end"] = float(nxt["start"]) + float(k["duration"]) + float(nxt.get("feint", 0.0))
		nxt = {}


func current() -> Dictionary:
	return cur


func next_attack() -> Dictionary:
	return nxt


func _finish(a: Dictionary) -> void:
	var kind := str(a["kind"])
	history.push_front(kind)
	var keep := int((cfg.get("ai", {}) as Dictionary).get("history", 4))
	while history.size() > keep:
		history.pop_back()
	last_end[kind] = float(a["end"])
	if bool(_ai_of(kind).get("ultimate", false)):
		last_ult_end = float(a["end"])
	next_start = float(a["end"]) + float(cfg.get("gap_sec", 0.6))


func _ai_of(kind: String) -> Dictionary:
	return ((cfg["kinds"] as Dictionary).get(kind, {}) as Dictionary).get("ai", {})


## 次の攻撃を、くじで決める。使えるものがなければ、代わりの攻撃（fallback）
func choose(start: float, form: String, dist_of: Callable) -> Dictionary:
	n += 1
	var weights := candidate_weights(start, form, float(dist_of.call(n)))
	var rng := Attacks.rng_for(round_start_ms, n * 13 + 101)
	var kind := pick(weights, rng.randf())
	if kind == "":
		var fb: Dictionary = (cfg.get("ai", {}) as Dictionary).get("fallback", {})
		kind = str(fb.get(form, "bat_h"))
	var out := {"n": n, "kind": kind, "start": start, "feint": 0.0}
	var ai := _ai_of(kind)
	if float(ai.get("feint_chance", 0.0)) > 0.0 and rng.randf() < float(ai["feint_chance"]):
		out["feint"] = float(ai.get("feint_sec", 0.45))
	return out


## 攻撃の種類 → 重み（使えない攻撃は入らない）
func candidate_weights(start: float, form: String, dist: float) -> Dictionary:
	var g: Dictionary = cfg.get("ai", {})
	var out := {}
	var last := str(history[0]) if not history.is_empty() else ""
	var strong_streak := 0
	for h in history:
		if bool(_ai_of(str(h)).get("strong", false)):
			strong_streak += 1
		else:
			break
	for kind in cfg["kinds"]:
		var ai := _ai_of(str(kind))
		var forms: Dictionary = ai.get("forms", {})
		var w := float(forms.get(form, 0.0))
		if w <= 0.0:
			continue
		if last_end.has(kind) and start - float(last_end[kind]) < float(ai.get("cooldown_sec", 0.0)):
			continue
		if bool(ai.get("ultimate", false)):
			if form != "awake" or awake_since < 0.0 or start - awake_since < float(g.get("ultimate_first_sec", 10.0)) or start - last_ult_end < float(g.get("ultimate_cooldown_sec", 25.0)):
				continue
		if last != "" and (ai.get("not_after", []) as Array).has(last):
			continue
		var r: Array = ai.get("range", [0.0, 99.0])
		if dist >= 0.0 and (dist < float(r[0]) or dist > float(r[1])):
			w *= float(ai.get("far_mult", g.get("far_mult", 0.3)))
		if kind == last:
			w *= float(g.get("repeat_mult", 0.4))
		if bool(ai.get("strong", false)) and strong_streak >= int(g.get("strong_streak", 2)):
			w *= float(g.get("strong_streak_mult", 0.25))
		if w > 0.0:
			out[kind] = w
	return out


## 重みのくじ。u は 0〜1 の乱数。候補がなければ ""
static func pick(weights: Dictionary, u: float) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return ""
	var x := u * total
	var keys := weights.keys()
	keys.sort()  # 並び順を決めて、同じ乱数なら同じ結果に
	for k in keys:
		x -= float(weights[k])
		if x <= 0.0:
			return str(k)
	return str(keys[keys.size() - 1])
