# 引き継ぎメモ

更新：2026-10-18
このファイルは、作業の前に読み、作業の後に更新する。

## いまの状況
- Godotのプロジェクトを作成済み（Compatibility）。`main.tscn`、`.gitignore` もある
- GitHubに初回の保存済み：https://github.com/koyoy1016-gif/bigbusters-godot
- Firebase：プロジェクト `bigbusters-new` を作成済み。Realtime Databaseの場所は `asia-southeast1`（シンガポール）
  - 設定値の置き場所：`data/firebase_config.json`（公開してよい値だけ）
  - 記入済み：`projectId`、`databaseURL`、`authDomain`、`storageBucket`、`messagingSenderId`、`appId`、`apiKey`（7項目すべて。依頼の文面の値と1文字ずつ一致することをプログラムで確認。Firebaseの画面との照合は、ユーザーが貼った値のとおりで、こちらでは未確認）
  - 秘密鍵・サービスアカウントのファイルは入れない（`.gitignore` で `*firebase-adminsdk*.json`、`*service-account*.json`、`*serviceAccount*.json`、`.env` を除外）
  - テスト：`godot --headless --path . --script res://tests/test_firebase_config.gd`（全項目の値、`apiKey` が空でなく `AIza` で始まる39文字であること、秘密情報が入っていないことを確認。結果は作業ログ）
  - 決定：つなぎ方は案A（JavaScriptBridge）、ログインは匿名ログイン、4桁の合言葉は試作では許容（下の「通信の試作の計画」）
  - 未確認：Firestoreの場所、Realtime Databaseがロックモードか、Sparkプランのままか。Authenticationで匿名が有効なことは、ユーザーから聞いた（コンソールでの確認はしていない）
- Firebase JS SDK の呼び出し確認（`JavaScriptBridge`）：**コードは作ったが、iPhoneで確かめるまで、接続できたとは書かない**（実機・ブラウザでは未確認）
  - 内容：Web版から匿名ログイン（`signInAnonymously`）を1回だけ呼び、画面に「Firebase OK（uidの先頭6文字）」または「Firebase NG：エラーの文字」を出す。合言葉の部屋・同期は未着手
  - 構成：シーン `scenes/experiments/firebase_check.tscn`、スクリプト `scripts/experiments/firebase_check.gd`、画面の文字・位置・時間切れの秒数・SDKのバージョンは `data/firebase_check.json`、設定値は `data/firebase_config.json`（`_memo` は渡さない）
  - SDKは書き出しの `head_include`（`export_presets.cfg` の preset.1）で読み込む。公式CDN `https://www.gstatic.com/firebasejs/11.10.0/`（バージョン固定）。ブラウザ側は `window.bbFirebase`（`signIn` と `state`）。Godotは `JavaScriptBridge.eval` で呼び、0.2秒ごとに `state` を読む（コールバック方式は使っていない）。15秒で終わらなければNG
  - 起動：既存の起動シーン（render_test）は変えていない。確認用に、書き出しプリセット「Web (Firebase check)」（機能タグ `firebase_check`、書き出し先 `web/firebase_check/index.html`）を足し、`project.godot` に `run/main_scene.firebase_check` を足した。このプリセットで書き出したときだけ確認シーンから始まる
  - 通常の書き出し（preset.0、render_test）は変えていない。どちらのプリセットも、スレッドなし
  - テスト：`tests/test_firebase_check.gd`（38項目合格）。偽のブラウザ側（差し替えた `js_eval`）で、成功・失敗・SDK未読み込み・時間切れの表示と、signInが1回だけ呼ばれることを確認。書き出し設定（スレッドなし、SDKの固定バージョン、設定値の直書きなし）と、起動シーンが変わっていないことも確認
  - ブラウザ側のJSは、Nodeで偽のSDKに差し替えて動作を確認した（成功・失敗・不正なJSON・2回呼んでも1回だけ。リポジトリにはテストとして入れていない）
  - **未確認**：①実際のブラウザでSDKが読み込めるか（この環境では gstatic に接続できず、`11.10.0` のファイルがあるかも未確認。npmには存在）②機能タグによる起動シーンの切り替えと `head_include` の書き出し（書き出しテンプレートがなく、実際の書き出しは未実施）③iPhone Safariで匿名ログインが通るか ④Authenticationで匿名が有効か（ユーザーから聞いただけ）⑤`getAuth` が使うIndexedDBなどが、iPhoneのSafariで使えるか
- iPhoneのブラウザでの実験：実機で計測済み（`scenes/render_test.tscn`）
  - 地面・ライト1つ・回転する箱。A：個別300個／B：MultiMesh 300個。キー1／2か画面ボタンで切り替え。左上にFPSと描画回数
  - 数値は `data/render_test.json`。Web書き出し設定は `export_presets.cfg`（スレッドなし）
  - 最新の計測（iPhone 16 Plus、iOS 26.6、Safari。デバッグなしで書き出した版、**1回ずつ**）：
    - B（まとめて描画）：FPS 59、描画回数 12
    - A（個別300個）：FPS 39、描画回数 221
  - **結論：同じ種類の物は、まとめて描画する**（MultiMeshなど）。Aは描画回数が約18倍で、FPSも約2/3に下がった
  - ただし、計測は1回ずつ。**3回ずつの再計測が必要**（結果を確定するのは、その後）
  - 前回の計測（書き出しの条件は未記録）：FPS 60（A・Bとも）。描画回数は A 約226〜（動くと変わる）、B 17。今回のAの FPS 39 と食い違う。書き出し方（デバッグの有無）や測り方の違いの可能性があるが、原因は未確認
  - PC（参考）：描画回数 A 320、B 21
  - 日本語の表示：フォント同梱で正しく出るようになった（iPhoneで確認済み）
  - 日本語フォント：Noto Sans JP（SIL OFL 1.1）を軽くした版 `assets/fonts/NotoSansJP-Regular-subset.ttf`（約2.1MB）。ライセンスは `assets/LICENSES.md`。ラベルとボタンの文字サイズは32（`ui_font_size`）
  - テスト：`godot --headless --path . --script res://tests/test_render_test.gd`（28項目すべて合格）
  - 起動シーン（run/main_scene）は `scenes/render_test.tscn`
  - 未確認：Android Chromeでの計測、書き出し後の合計サイズ

## 決まっていること
- 2アプリ構成（アプリ1：友達用、通信あり／アプリ2：収益化用、1人＋AI3人、通信なし）
- 内容（ステージ、キャラ）は、2つのアプリで共通にする
- 通信：Firebase。アカウントとフレンドは Firestore、対戦中の同期は Realtime Database
- ログイン：ゲームが自動でIDを割り当て、本人がパスワードを設定する（Googleログインは使わない）
- 収益化：無料体験版（1ステージ）＋全ステージ解放の買い切り。ガチャは入れない
- 公開先：アプリ1はGitHub Pages（無料）。アプリ2はAndroid先行。ブラウザでの配布は、GitHub Pagesの規約が合わない可能性があるので、別の場所を考える
- 画質は「低」「高」の2段階にする
- 最初の公開版は5ステージ：北千住、上野、秋葉原の3駅＋電車内＋ホーム乗り換え
- 最終形は10ステージ、キャラ約100体（味方20、ボス7、街の人40、敵約33）。最初の公開版は約63体（ボス3、味方10、敵30、街の人20）

## 構想メモ（未決。まだ設計書には入れない）
- 舞台は、実在の駅周辺（北千住、上野、新宿、池袋、渋谷、秋葉原、銀座）。国土交通省のPLATEAUを元に、ミニチュア風に再現する
- 電車内、ホーム、乗り換えでも戦う。ボスを倒したあと、電車で次の駅へ向かう演出
- 敵は「結社」の手下で、各駅のボスを操る上位のボスがいる。街の住民そのものを敵にしない案（提案。未決）
- キャラはBlenderで自作（0円）。共通の骨格、パーツ、色替えで量産する。人型の動きはMixamoを使う
- 実在の店の看板、ロゴ、鉄道会社のデザイン、駅のメロディは、そのまま使わない

## 確認できていないこと（要確認）
- Firebaseの最新の無料枠
- PLATEAUの最新の利用規約、駅周辺の範囲、Godot 4.7.2での読み込み方法
- Google Playの有料解放の設定、購入の復元の方法
- iPhoneのブラウザのメモリの上限
- JavaScriptBridge経由でFirebase JS SDKを使う方法（Godot 4.7.2、スレッドなしのWeb書き出し）
- 4桁の合言葉の安全性（1万通りで当てられやすい。試作では許容、本番で見直す）
- 匿名ログインのユーザーIDの扱い（端末を変える・ブラウザのデータを消すとIDが変わる）
- 看板、ロゴ、商標、鉄道会社のデザインの扱い

## 次にやること
1. 確認用のWeb書き出し：プリセット「Web (Firebase check)」で `web/firebase_check/` に書き出し、HTTPSで公開（またはローカルサーバー）して、iPhone Safari と Android Chrome で開く。「Firebase OK（…）」が出るか見る。NGなら、エラーの文字を `NOTES.md` に書く
2. （1が通ったら）通信の試作の手順1：4桁の合言葉で部屋に入る。ルールを書いてテストしてから設定する
3. 描画実験の再計測：iPhoneで A・B を3回ずつ測って平均を出す。Android Chromeでも測る。前回との食い違い（FPS 60 と 39）の原因も見る
4. 差が出る条件を探す（箱を増やす、動く敵を増やすなど）

## 通信の試作の計画（まだ実装しない）

### 決定事項（ユーザーが決めた）
- **つなぎ方：案A**。`JavaScriptBridge` で、ブラウザ側のFirebase JS SDKを呼ぶ
  - 変更の通知（リスナー）が使えるので、1秒10回の同期に向く
  - JSのファイルを書き出しのHTMLに足す必要がある（HTMLシェルの設定）。PCのGodotエディタでは通信を試せず、ブラウザで確認する
  - 案B（`HTTPRequest` でREST API）は使わない
  - 未検証：Godot 4.7.2のWeb書き出し（スレッドなし）で、JavaScriptBridgeからSDKのコールバックを受ける方法。手順1の最初に小さく確かめる
- **ログイン：匿名ログイン**（Authenticationで匿名は有効）
  - 以前の方針「メール/パスワードだけオン（匿名はオフ）」から変更した。本番（アカウントとフレンド）では、ID＋パスワードのログインに戻すか、匿名から切り替える（「決まっていること」のログインの方針は、本番の話として残す）
  - 匿名ログインのユーザーIDで、ルールを書く（他人のデータを書き換えられないようにする）
- **4桁の合言葉：試作では許容し、本番で見直す**（1万通りで当てられやすい）
- **ルール**：テストモードにしない。書いてテストしてから設定する（CLAUDE.md ルール10）
- 数値（合言葉の桁数、同期の頻度、再接続の待ち時間など）は `data/network.json` に置く（CLAUDE.md ルール3）

### 手順1：4桁の合言葉で部屋に入る
- 作ること：4桁の数字を入力して、部屋に入る（部屋がなければ作る）。部屋ごとの参加者の一覧をデータベースに持つ
- データの形（案）：`rooms/{合言葉}/players/{ユーザーID}`
- 確認方法：2台で同じ合言葉を入れると、お互いの参加が画面に出る。違う合言葉では、別の部屋になる
- テスト：合言葉の検査（4桁の数字のみ）、データの形を作る関数（通信なしで確認できる部分）
- 注意：4桁は1万通りしかなく、当てられやすい。試作では許容するが、本番では見直す（NOTESの「確認できていないこと」に追加）。ルールで、他人の参加データを書き換えられないようにする
- 完了の目安：2台のスマホ（iPhone Safari、Android Chrome）で、同じ合言葉で入れる

### 手順2：2台で箱の位置を、約10回/秒で同期する
- 作ること：片方で動かした箱の位置を、もう片方に反映する。送る頻度は約10回/秒（100ミリ秒ごと）。動いていないときは送らない
- 送る内容：位置（x、y、z）と、送った時刻。受け取った側は、位置をなめらかに補間して表示する
- 確認方法：画面に「送信回数/秒」「受信回数/秒」を出して、約10になることを見る。2台で箱が同じように動く
- テスト：送信間隔の制御、補間の計算（通信なしで確認できる部分）
- 注意：通信量とFirebaseの無料枠（書き込み回数・転送量）。最新の無料枠は未確認。ダメージ計算は `scripts/combat/damage.gd` の1つの関数だけ（今回は戦闘なし）
- 完了の目安：2台で、箱の動きが目で見て遅れなく合う（遅延は数字で記録する）

### 手順3：接続状態の表示と、自動での再接続
- 作ること：画面に「接続中／接続済み／切断／再接続中」を出す。切れたら、待ち時間を少しずつ伸ばして自動で再接続する。戻ったら、同じ部屋に戻り、位置の同期を再開する
- 確認方法：機内モードのオン・オフ、Wi-Fiとモバイル回線の切り替えで、自動で戻る
- テスト：再接続の待ち時間の計算、状態の切り替え（通信なしで確認できる部分）
- 注意：Realtime Databaseの接続状態（`.info/connected`）を使う案。切断したときに、部屋の参加者の一覧から消える仕組み（`onDisconnect`）も、この手順で扱う
- 完了の目安：iPhoneとAndroidの両方で、切れても自動で戻る

## 作業ログ
- 2026-10-18：作業ルール（CLAUDE.md）と、このメモを作成
- 2026-10-18：描画実験シーンを作成（A個別300／B MultiMesh300、FPS・描画回数表示、Webスレッドなし設定、テスト追加）。ブランチ claude/happy-planck-pg17gs にプッシュ済み
- 2026-10-18：iPhone 16 Plus（iOS 26.6、Safari）の計測結果を記録（FPS 60、描画回数 A 約226〜／B 17、PC参考 A 320／B 21）。日本語が□になる課題に対し、Noto Sans JP（OFL）の軽量版を同梱（`assets/fonts/`、`assets/LICENSES.md`）。フォント作成：npm `@expo-google-fonts/noto-sans-jp` の400Regularを fonttools の `pyftsubset` で、ASCII＋かな＋JIS X 0208漢字に絞った。フォントの追加と、この記録は、ブランチ claude/happy-planck-pg17gs にプッシュ済み
- 2026-10-18：iPhoneの再計測（デバッグなしの書き出し、1回ずつ）を記録：B FPS 59／描画回数 12、A FPS 39／描画回数 221。結論は「同じ種類の物はまとめて描画する」。3回ずつの再計測が必要。日本語表示は直ったことを確認。「次にやること」の先頭を通信の試作に変更。コードの変更なし。コミット・プッシュはまだ
- 2026-10-18：通信の試作の準備（コードなし）。Firebaseの設定値の置き場所を `data/firebase_config.json` に決め、`projectId`、`databaseURL` を記入（他は空欄）。秘密情報を除外する `.gitignore` と、設定ファイルのテストを追加。通信の試作の計画（手順1：合言葉の部屋、手順2：10回/秒の同期、手順3：接続状態と再接続）を書いた。コミット・プッシュはまだ
- 2026-10-18：`data/firebase_config.json` に authDomain、storageBucket、messagingSenderId、appId を記入（apiKeyは値が渡されず空欄のまま）。決定事項を記録（案A：JavaScriptBridge、匿名ログイン、4桁の合言葉は試作で許容）。テストを更新。コミット・プッシュはまだ
- 2026-10-18：`apiKey` を `data/firebase_config.json` に記入。7項目すべてが依頼の値と一致、`apiKey` は39文字で `AIza` 始まり。テスト結果：`test_firebase_config.gd` 合格（失敗0）、`test_render_test.gd` 合格（失敗0）。ゲームのコードは変更なし。コミット・プッシュはまだ
- 2026-10-18：`JavaScriptBridge` で Firebase JS SDK を呼ぶ小さな確認を作成（匿名ログインを1回、結果を画面に表示）。シーン・スクリプトは experiments/ の下、文字などは `data/firebase_check.json`。SDKは `head_include` で gstatic の 11.10.0 を読み込む。確認用の書き出しプリセットを追加。テスト：`test_firebase_check.gd` 38合格／`test_firebase_config.gd` 23合格／`test_render_test.gd` 28合格（失敗0）。**iPhoneで確かめるまで、接続できたとは書かない**。Web書き出し・ブラウザでの動作は未実施。コミット・プッシュはまだ
