extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_pages_workflow.gd
## GitHub Pages 公開のワークフローの、設定の読み合わせ（実際の動作はGitHub上で確かめる）。

const WORKFLOW := "res://.github/workflows/pages.yml"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(WORKFLOW)
	check(text != "", "ワークフローのファイルがある")

	var triggers := text.substr(text.find("\non:"), text.find("\npermissions:") - text.find("\non:"))
	check(triggers.contains("- claude/happy-planck-pg17gs"), "作業ブランチへのプッシュで動く")
	check(not triggers.contains("- main") and not triggers.contains("- master"), "main では動かない")

	var version := "4.7.2"
	check(text.contains('GODOT_VERSION: "%s"' % version), "Godot %s を使う" % version)
	check(text.contains("releases/download/%s-stable" % version), "ダウンロード元のバージョンが一致する")
	check(text.contains("sha512sum -c"), "ダウンロードしたファイルの検証（SHA512）をしている")
	check(text.contains("actions/cache@"), "キャッシュを使う")
	check(text.contains("web_nothreads_"), "スレッドなしのテンプレートを使う")
	check(text.contains("tests/test_*.gd"), "全テストを実行する")
	check(text.contains("exit $failed"), "テストが失敗したら止まる")

	# 書き出しのプリセット名が、export_presets.cfg にある
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	for name in ["Web", "Web (Firebase check)"]:
		check(presets.contains('name="%s"' % name), "プリセット「%s」がある" % name)
		check(text.contains('--export-release "%s"' % name), "ワークフローがプリセット「%s」を書き出す" % name)
	check(text.contains("site/firebase_check/index.html"), "確認用は /firebase_check/ の下に置く")
	check(text.contains("actions/deploy-pages@") and text.contains("actions/upload-pages-artifact@"), "GitHub Pages に公開する")
	# 書き出し結果を、プロジェクトの中に置かない（素材として読み込まれるのを避ける）
	check(not text.contains('"$PWD/site') and text.contains("$RUNNER_TEMP/site"), "書き出し先はプロジェクトの外")

	# 秘密情報を、ワークフローに書いていない
	for word in ["AIza", "private_key", "ghp_", "github_pat_", "PRIVATE KEY"]:
		check(not text.contains(word), "ワークフローに「%s」が含まれない" % word)
	check(not text.contains("secrets."), "ワークフローがsecretsを使っていない（公開してよい値だけで動く）")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
