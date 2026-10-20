extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_v99.gd
## 版99（軽量化 B-2）：ダメージの数字・必殺技の名前の「はね上がり」で、文字の大きさを毎コマ変えない。
## （文字の大きさが変わるたびに、その大きさの文字の絵（フォントのキャッシュ）が作られ、戦いの間メモリが増え続けていた）
## 確かめること：
##   1. 倍率の段は data/prototype_stick.json の hud.text_pop_levels
##   2. 画面での大きさは前と同じ（描く大きさ px × 拡大 k ＝ 落ち着いた大きさ × いまの倍率）
##   3. 落ち着いた時（倍率 1）は、そのままの大きさで描く（拡大・縮小しない＝くっきり）
##   4. 拡大・縮小は小さい（0.8〜1.25 倍）。文字の絵が大きくぼやけない
##   5. 描く大きさの種類が、前（はね上がりの間のすべての整数）より大きく減り、段の数以下になる

const DamageNumbers := preload("res://scripts/ui/damage_numbers.gd")
const BattleHud := preload("res://scripts/prototype/battle_hud.gd")
var failures := 0


func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		failures += 1


func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype_stick.json"))
	var levels: Array = (cfg.get("hud", {}) as Dictionary).get("text_pop_levels", [])
	check(levels.size() >= 2 and is_equal_approx(float(levels[0]), 1.0), "倍率の段は data（%s）・いちばん小さい段は 1（落ち着いた大きさ）" % str(levels))
	var dc: Dictionary = cfg["damage_numbers"]
	var dn = DamageNumbers.new(dc)
	var base := float(cfg["ui_font_size"]) * float(dc.get("size_scale", 1.4))
	var same := true
	var rest_ok := true
	var k_min := INF
	var k_max := -INF
	var old_sizes := {}
	var new_sizes := {}
	for kind in (dc["kinds"] as Dictionary).keys():
		var kc: Dictionary = dn.kind_cfg(kind)
		var settled := maxi(int(dc.get("min_px", 18)), int(base * float(kc.get("size", 1.0))))
		var olds := {}
		var news := {}
		for step in [1.0 / 60.0, 1.0 / 37.0, 1.0 / 23.0]:
			var it := {"kind": kind, "age": 0.0, "life": float(kc.get("life", dc.get("life", 0.65)))}
			while float(it["age"]) < float(it["life"]):
				var sc := float(dn.look(it)["scale"])
				var lv: Dictionary = BattleHud.pop_text(settled, sc, levels)
				same = same and absf(float(lv["px"]) * float(lv["k"]) - float(settled) * sc) < 0.01
				k_min = minf(k_min, float(lv["k"]))
				k_max = maxf(k_max, float(lv["k"]))
				olds[maxi(int(dc.get("min_px", 18)), int(base * float(kc.get("size", 1.0)) * sc))] = true
				news[int(lv["px"])] = true
				it["age"] = float(it["age"]) + step
		var rest: Dictionary = BattleHud.pop_text(settled, 1.0, levels)
		rest_ok = rest_ok and int(rest["px"]) == settled and is_equal_approx(float(rest["k"]), 1.0)
		print("     %s：落ち着いた大きさ %d px・前は %d 種類の大きさ → いまは %d 種類 %s" % [kind, settled, olds.size(), news.size(), str(news.keys())])
		check(news.size() <= levels.size() and news.size() < olds.size(), "%s：描く大きさの種類が減った（%d → %d）" % [kind, olds.size(), news.size()])
		for key in olds:
			old_sizes["%s:%d" % [kind, key]] = true
		for key in news:
			new_sizes["%s:%d" % [kind, key]] = true
	# 必殺技の名前：出た瞬間 1.6 倍 → 0.25 秒で 1 倍
	var bsettled := int(float(cfg["ui_font_size"]) * 2.4)
	var bolds := {}
	var bnews := {}
	var age := 0.0
	while age < 0.4:
		var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - age / 0.25)
		var lv: Dictionary = BattleHud.pop_text(bsettled, pop, levels)
		same = same and absf(float(lv["px"]) * float(lv["k"]) - float(bsettled) * pop) < 0.01
		k_min = minf(k_min, float(lv["k"]))
		k_max = maxf(k_max, float(lv["k"]))
		bolds[int(float(cfg["ui_font_size"]) * 2.4 * pop)] = true
		bnews[int(lv["px"])] = true
		age += 1.0 / 60.0
	print("     必殺技の名前：前は %d 種類 → いまは %d 種類" % [bolds.size(), bnews.size()])
	check(bnews.size() <= 2 and bnews.size() < bolds.size(), "必殺技の名前：描く大きさの種類が減った（%d → %d）" % [bolds.size(), bnews.size()])
	check(same, "画面での大きさは前と同じ（描く大きさ × 拡大 ＝ 落ち着いた大きさ × いまの倍率）")
	check(rest_ok, "落ち着いた時（倍率 1）は、そのままの大きさで描く（拡大・縮小なし）")
	check(k_min >= 0.8 and k_max <= 1.25, "拡大・縮小は小さい（%.2f〜%.2f 倍）" % [k_min, k_max])
	check(new_sizes.size() + bnews.size() <= 16, "ダメージの数字と必殺技の名前で、描く大きさは全部で %d 種類（前は %d 種類）" % [new_sizes.size() + bnews.size(), old_sizes.size() + bolds.size()])
	print("失敗: %d" % failures)
	quit(1 if failures > 0 else 0)
