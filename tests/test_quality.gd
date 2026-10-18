extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_quality.gd
## 画質の切り替え（quality.gd）を確かめる。

const Quality := preload("res://scripts/core/quality.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var cfg := Quality.load_config()
	check(cfg.has("presets") and cfg["presets"].has("low") and cfg["presets"].has("high"), "「低」「高」の2つがある")
	check(cfg["default"] == "low", "既定は「低」（iPhoneを基準）")
	check(Quality.resolve("high", cfg) == "high" and Quality.resolve("zzz", cfg) == "low" and Quality.resolve("", cfg) == "low", "名前の解決：正しければそれ、ほかは既定")
	check(Quality.next_preset("low", cfg) == "high" and Quality.next_preset("high", cfg) == "low", "次の画質は、ぐるっと回る")
	check(Quality.next_preset("zzz", cfg) == "low" or Quality.next_preset("zzz", cfg) == "high", "壊れた名前でも、どれかになる")
	check(Quality.label_of("low", cfg) == "ひくい" and Quality.label_of("high", cfg) == "たかい", "画面に出す名前")
	var low: Dictionary = cfg["presets"]["low"]
	var high: Dictionary = cfg["presets"]["high"]
	check(not bool(low["shadow"]) and int(low["max_fps"]) <= int(high["max_fps"]) and float(low["scale_3d"]) <= float(high["scale_3d"]) and int(low["msaa"]) <= int(high["msaa"]), "「低」は、「高」より軽い設定")
	var font := load("res://assets/fonts/NotoSansJP-Regular-subset.ttf") as Font
	var ok := true
	for k in cfg["presets"]:
		for ch in str(cfg["presets"][k]["label"]):
			if not font.has_char(ch.unicode_at(0)):
				ok = false
	check(ok, "名前の文字が、フォントにある")

	var vp := SubViewport.new()
	root.add_child(vp)
	var light := DirectionalLight3D.new()
	root.add_child(light)
	Quality.apply("high", cfg, vp, [light])
	check(light.shadow_enabled and vp.msaa_3d == Viewport.MSAA_2X and is_equal_approx(vp.scaling_3d_scale, 1.0) and Engine.max_fps == 60, "「高」を当てはめると、影あり・MSAA 2倍・60fps")
	Quality.apply("low", cfg, vp, [light])
	check(not light.shadow_enabled and vp.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(vp.scaling_3d_scale, 0.8) and Engine.max_fps == 30, "「低」を当てはめると、影なし・MSAAなし・30fps")
	Quality.apply("zzz", cfg, null, [])
	check(Engine.max_fps == 30, "壊れた名前は、既定（低）になる。描画の設定がなくても落ちない")
	Engine.max_fps = 0
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
