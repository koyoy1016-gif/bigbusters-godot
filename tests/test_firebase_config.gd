extends SceneTree
## 実行: godot --headless --path . --script res://tests/test_firebase_config.gd

const PATH := "res://data/firebase_config.json"
const FORBIDDEN_KEYS := ["private_key", "private_key_id", "client_secret", "client_email", "type"]
const FORBIDDEN_TEXT := ["BEGIN PRIVATE KEY", "BEGIN RSA PRIVATE KEY", "service_account"]

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("OK   ", msg)
	else:
		print("FAIL ", msg)
		failures += 1


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	check(text != "", "設定ファイルがある")
	var cfg: Variant = JSON.parse_string(text)
	check(cfg is Dictionary, "JSONとして読める")
	if cfg is Dictionary:
		check(cfg.get("projectId") == "bigbusters-new", "projectId")
		var url: String = str(cfg.get("databaseURL", ""))
		check(url == "https://bigbusters-new-default-rtdb.asia-southeast1.firebasedatabase.app", "databaseURL")
		check(not url.ends_with("/"), "databaseURLの末尾に / がない")
		check(cfg.has("apiKey"), "項目 apiKey がある")
		var api_key: String = str(cfg.get("apiKey", ""))
		check(api_key != "", "apiKeyが空でない")
		check(api_key.begins_with("AIza"), "apiKeyの形（AIza で始まる）")
		check(api_key.length() == 39, "apiKeyの長さが39文字")
		check(api_key == api_key.strip_edges() and not api_key.contains(" "), "apiKeyに空白がない")
		check(cfg.get("authDomain") == "bigbusters-new.firebaseapp.com", "authDomain")
		check(cfg.get("storageBucket") == "bigbusters-new.firebasestorage.app", "storageBucket")
		check(cfg.get("messagingSenderId") == "1062674695019", "messagingSenderId")
		check(cfg.get("appId") == "1:1062674695019:web:dc986e36a6860ad0b5822e", "appId")
		for key in FORBIDDEN_KEYS:
			check(not cfg.has(key), "秘密情報の項目 %s がない" % key)
	for word in FORBIDDEN_TEXT:
		check(not text.contains(word), "「%s」が含まれない" % word)

	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	check(gitignore.contains("*firebase-adminsdk*.json"), ".gitignore がサービスアカウントのファイルを除外する")

	print("失敗: ", failures)
	quit(1 if failures > 0 else 0)
