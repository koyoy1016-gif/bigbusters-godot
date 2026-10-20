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
	check(not bool(low["shadow"]) and float(low["target_3d_pixels"]) < float(high["target_3d_pixels"]) and int(low["msaa"]) <= int(high["msaa"]), "「低」は、「高」より軽い設定")
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
	vp.size = Vector2i(1290, 2796)  # iPhone の画面くらいの画素数（約360万）
	Quality.apply("high", cfg, vp, [light])
	var hi_px := 1290.0 * 2796.0 * vp.scaling_3d_scale * vp.scaling_3d_scale
	check(light.shadow_enabled and vp.msaa_3d == Viewport.MSAA_2X and Engine.max_fps == 0, "「高」を当てはめると、影あり・MSAA 2倍・FPSの制限なし（画面の更新に合わせる）")
	check(absf(hi_px - float(high["target_3d_pixels"])) / float(high["target_3d_pixels"]) < 0.05, "「高」：iPhoneの画面では、3Dを目安の画素数で描く：" + str(int(hi_px)))
	Quality.apply("low", cfg, vp, [light])
	var lo_px := 1290.0 * 2796.0 * vp.scaling_3d_scale * vp.scaling_3d_scale
	check(not light.shadow_enabled and vp.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 0, "「低」を当てはめると、影なし・MSAAなし・FPSの制限なし")
	check(lo_px < hi_px and absf(lo_px - float(low["target_3d_pixels"])) / float(low["target_3d_pixels"]) < 0.05, "「低」は「高」より少ない画素で描く：" + str(int(lo_px)))
	vp.size = Vector2i(640, 360)
	Quality.apply("high", cfg, vp, [light])
	check(is_equal_approx(vp.scaling_3d_scale, float(high["scale_3d"])), "小さな画面では、細かさを上げすぎない（上限は scale_3d）")
	check(is_equal_approx(Quality.scale_for(1.0e9, low), float(low["min_scale_3d"])), "とても大きな画面でも、下限より粗くしない")
	var PerfOverlay := load("res://scripts/core/perf_overlay.gd")
	var txt: String = PerfOverlay.build_text(58.6, 41.2, 80, Vector2i(540, 1170), "low")
	check(txt.contains("FPS 59") and txt.contains("41 ms") and txt.contains("80") and txt.contains("540x1170"), "重さの表示（?perf=1）に、FPS・いちばん長い1コマ・描画の回数・3Dの大きさが出る：" + txt.replace("\n", " / "))
	var txt2: String = PerfOverlay.build_text(58.6, 41.2, 80, Vector2i(540, 1170), "low", 49.4, 173.4)
	var txt3: String = PerfOverlay.build_text(58.6, 41.2, 80, Vector2i(540, 1170), "low", 49.4, 0.0)
	check(txt2.contains("がぞう 49 MB") and txt2.contains("メモリ 173 MB") and txt3.contains("がぞう 49 MB") and not txt3.contains("メモリ") and not txt.contains("がぞう"), "版100：画像のメモリ・ゲームのメモリ（数えられる時だけ）も出せる：" + txt2.replace("\n", " / "))
	var txt4: String = PerfOverlay.build_text(41.0, 88.0, 130, Vector2i(456, 987), "low", 49.4, 0.0, 7, 4.25, 6.1)
	check(txt4.contains("おそい 7") and txt4.contains("しょりさいだい 4.2 ms") and txt4.contains("びょうがCPU 6.1 ms") and not txt.contains("おそい") and not txt.contains("しょり"), "版101・103：おそいコマの数・しょりさいだい・びょうがCPU も出せる（渡さなければ出さない）：" + txt4.replace("\n", " / "))
	# 版102：重さの表示の字は、日本語の字が入った文字の形で出す（前はかなが □ になっていた）
	var jf := load("res://assets/fonts/NotoSansJP-Regular-subset.ttf") as Font
	var missing := ""
	for ch in txt4 + txt2:
		if ch != "\n" and ch != " " and not jf.has_char(ch.unicode_at(0)):
			missing += ch
	var gsrc := FileAccess.get_file_as_string("res://scripts/flow/game_flow.gd")
	var psrc := FileAccess.get_file_as_string("res://scripts/core/perf_overlay.gd")
	check(missing == "" and gsrc.contains("perf_overlay.font = font") and psrc.contains("add_theme_font_override(\"font\", font)"), "重さの表示は、日本語の字が入った文字の形で出す（使う字はすべて入っている）" + ("" if missing == "" else "：ない字 " + missing))
	Quality.apply("zzz", cfg, null, [])
	check(Engine.max_fps == 0, "壊れた名前は、既定（低）になる。描画の設定がなくても落ちない")
	Engine.max_fps = 0
	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
