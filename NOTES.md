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
- Firebase JS SDK の呼び出し確認（`JavaScriptBridge`）：**iPhone Safariで成功を確認した**（ユーザーのスクリーンショット：「Firebase OK（uWJEjQ）」。URLは trycloudflare.com のトンネル）
  - これで分かったこと：SDK（gstatic の 11.10.0）が読み込める／`head_include` が効く／機能タグ `firebase_check` で確認シーンから始まる／`JavaScriptBridge` の呼び出しと状態の読み取りが動く／匿名ログインが有効でuidが取れる／日本語表示も出る
  - まだ未確認：Android Chrome、横画面での表示、再読み込みで同じuidになるか（匿名ユーザーの保存）、機種とiOSのバージョン（スクリーンショットからは不明）。Firestore・Realtime Databaseのルールや読み書きは、まだ何も試していない
  - （以下は作成時の記録。「未確認」の①〜⑤のうち、①②③④は上のとおり確認できた。⑤はiPhone Safariで動いたので、少なくとも匿名ログインは通った）
  - 内容：Web版から匿名ログイン（`signInAnonymously`）を1回だけ呼び、画面に「Firebase OK（uidの先頭6文字）」または「Firebase NG：エラーの文字」を出す。合言葉の部屋・同期は未着手
  - 構成：シーン `scenes/experiments/firebase_check.tscn`、スクリプト `scripts/experiments/firebase_check.gd`、画面の文字・位置・時間切れの秒数・SDKのバージョンは `data/firebase_check.json`、設定値は `data/firebase_config.json`（`_memo` は渡さない）
  - SDKは書き出しの `head_include`（`export_presets.cfg` の preset.1）で読み込む。公式CDN `https://www.gstatic.com/firebasejs/11.10.0/`（バージョン固定）。ブラウザ側は `window.bbFirebase`（`signIn` と `state`）。Godotは `JavaScriptBridge.eval` で呼び、0.2秒ごとに `state` を読む（コールバック方式は使っていない）。15秒で終わらなければNG
  - 起動：既存の起動シーン（render_test）は変えていない。確認用に、書き出しプリセット「Web (Firebase check)」（機能タグ `firebase_check`、書き出し先 `web/firebase_check/index.html`）を足し、`project.godot` に `run/main_scene.firebase_check` を足した。このプリセットで書き出したときだけ確認シーンから始まる
  - 通常の書き出し（preset.0、render_test）は変えていない。どちらのプリセットも、スレッドなし
  - テスト：`tests/test_firebase_check.gd`（38項目合格）。偽のブラウザ側（差し替えた `js_eval`）で、成功・失敗・SDK未読み込み・時間切れの表示と、signInが1回だけ呼ばれることを確認。書き出し設定（スレッドなし、SDKの固定バージョン、設定値の直書きなし）と、起動シーンが変わっていないことも確認
  - ブラウザ側のJSは、Nodeで偽のSDKに差し替えて動作を確認した（成功・失敗・不正なJSON・2回呼んでも1回だけ。リポジトリにはテストとして入れていない）
  - **未確認**：①実際のブラウザでSDKが読み込めるか（この環境では gstatic に接続できず、`11.10.0` のファイルがあるかも未確認。npmには存在）②機能タグによる起動シーンの切り替えと `head_include` の書き出し（書き出しテンプレートがなく、実際の書き出しは未実施）③iPhone Safariで匿名ログインが通るか ④Authenticationで匿名が有効か（ユーザーから聞いただけ）⑤`getAuth` が使うIndexedDBなどが、iPhoneのSafariで使えるか
- 通信の試作 手順1-1（合言葉の関数・設定・ルール案）：作成済み。**画面とネットワークの接続は、まだ作っていない**
  - `data/network.json`：`code_digits: 4`、`max_players: 4`
  - `scripts/network/room_code.gd`：`is_valid_code(code, digits)`（半角の数字0〜9だけで、ちょうど桁数。全角・空白・符号・記号は不可）、`room_path(code, digits)`（`rooms/1234`。不正なら空の文字列）、`load_config()`
  - `firebase/database.rules.json`：ルールの**案**。**Firebaseには適用していない**（`firebase.json` もない）。設計の「4. 必要なルール案」と同じ内容
  - テスト：`tests/test_room_code.gd`（37項目合格：設定値、通る合言葉、通らない合言葉（全角・空白・記号など19種）、場所の組み立て）、`tests/test_room_rules.gd`（22項目合格：ルールの形、`network.json` の桁数・人数との一致、全体が拒否のままか、一覧が読めないか、など）。設定値をわざと変えると、失敗することも確認した
  - **ルールの動作そのもの（誰が書けるか、3人目が拒否されるか）は、Godotのテストでは確かめられない（未確認）**。コンソールのプレイグラウンドと、実機で確かめる
  - ルールの中の `2` と `{4}` は、ルールのファイルに直接書いてある。`network.json` を変えるときは、ルールも直す（テストが食い違いを見つける）
- GitHub Pages への自動公開（準備）：ワークフロー `.github/workflows/pages.yml` を作った。**GitHub上で実際に動かしたことは、まだない（未確認）**
  - 動く条件：`claude/happy-planck-pg17gs` へのプッシュ（main では動かない）。手動実行も可
  - 流れ：Godot 4.7.2（公式のGitHubリリース）とWeb用テンプレート（スレッドなしの2ファイル、約20MB）を取得（SHA512で検証）→ アセット読み込み → **全テストを実行（1つでも失敗したら、ここで止まり、公開しない）** → プリセット「Web」を `/` に、「Web (Firebase check)」を `/firebase_check/` に書き出し → GitHub Pages に公開
  - テンプレートの取得方法：**キャッシュ＋ダウンロード**。キャッシュ（`actions/cache`、キー `godot-4.7.2-web-nothreads-v1`）にあれば、それを使う。なければ、公式のテンプレート一式（約1.28GB）をダウンロードして、必要な2ファイルだけ取り出し、キャッシュに保存する（保存されるのは約20MB＋Godot本体）
  - この環境（GitHub Actionsではない）で、同じ手順を再現した結果：テンプレート一式のダウンロード約9秒、取り出し0.4秒、アセット読み込み約12秒、全テスト＋2回の書き出しで合計約25秒。**GitHub Actionsでの所要時間は未計測**
  - 書き出しの容量（スレッドなし）：`/` と `/firebase_check/` で、それぞれ wasm 約39.5MB（gzipすると約10MB）、pck 約1.6MB、js 約0.28MB。合計で約80MB（2つ分。1ページあたり約41MB）
  - 書き出し先はプロジェクトの外（`$RUNNER_TEMP/site`）。中に置くと、Godotが書き出し結果を素材として取り込んでしまうのを、再現で確認したため
  - 文法の確認：actionlint 1.7.12 でエラーなし。YAMLとしても読めることを確認
  - 実ブラウザでの確認（この環境のChromium、ソフトウェア描画）：書き出した `/` は render_test が動き、日本語も出る。`/firebase_check/` は機能タグで確認シーンから始まり、`window.bbFirebase` が読み込まれ、`signIn` が呼ばれた。この環境では gstatic に接続できないため「Firebase NG：Failed to fetch dynamically imported module…」と出た（期待どおりの失敗表示。成功は iPhone で確認済み）。これで、機能タグによる起動シーンの切り替えと `head_include` の書き出しも確認できた
  - テスト：`tests/test_pages_workflow.gd`（23項目合格）。ブランチの指定、main を含まないこと、プリセット名の一致、SHA512の検証、テスト失敗で止まること、秘密情報が書かれていないこと、などを確認
  - **公開のURL：未確認**。プロジェクトサイトの形式から推定すると `https://koyoy1016-gif.github.io/bigbusters-godot/`（確認用は `…/firebase_check/`）。実際のURLは、Actionsの「deploy」ジョブの結果に出る
  - **ユーザーがGitHubで設定する必要があること（私は設定できない）**：①リポジトリの Settings → Pages → Source を「GitHub Actions」にする ②Settings → Environments → `github-pages` → Deployment branches に `claude/happy-planck-pg17gs` を追加する（初期設定では、公開できるのは既定のブランチ（main）だけの可能性が高い。未確認）
  - リポジトリは**公開**（認証なしでURLが開けた）。プッシュした内容は誰でも見られる
- 公開前の安全確認（全履歴8コミット、全ブランチ）：秘密鍵、サービスアカウント、各種トークン、パスワードらしい文字列は**見つからなかった**。見つかったのは ①公開してよい `apiKey`（`AIza…`、1件）②テストの中の「禁止する言葉」の一覧（`private_key` など。値ではない）だけ。参考：`docs/bigbusters-summary-2026-10-17.md` の116行目に、ユーザーのWindowsのフォルダの場所（氏名を含む）が書いてある。秘密ではないが、リポジトリが公開なので、消すかどうかはユーザーが決める
- 作業ルール（`CLAUDE.md` のルール11）を変更した：テストが全部合格したら、`claude/happy-planck-pg17gs` に自動でコミットとプッシュしてよい（mainには入れない。1つでも失敗したら、しない）
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
1. （ユーザー）GitHubで、Pages の Source を「GitHub Actions」にし、`github-pages` 環境に `claude/happy-planck-pg17gs` を許可する。その後、Actions の実行結果（成功か、失敗ならエラーの文字、所要時間）を確認して、`NOTES.md` に書く。公開のURLを確定する
2. 公開されたURLを、iPhoneで開く。`/`（描画実験）と `/firebase_check/`（Firebase OK が出るか）を確認する
3. Android Chromeでも、同じ確認を行う。再読み込みして、uidが変わらないかも見る
4. 通信の試作の手順1-2：**済み**（プレイグラウンドの9項目のうち8項目が合格。残る1項目＝すでに人がいる枠への上書きは、プレイグラウンドでは再現できないので、実機の1-5で確かめる）
5. 描画実験の再計測：iPhoneで A・B を3回ずつ測って平均を出す。Android Chromeでも測る。前回との食い違い（FPS 60 と 39）の原因も見る
6. 差が出る条件を探す（箱を増やす、動く敵を増やすなど）

## 通信の試作の計画（手順1は設計済み。実装はまだ）

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

### 手順1：4桁の合言葉で部屋に入る（設計。コードはまだ書かない）

#### 方針
- 部屋は「最初の人が入った時に、できる」。部屋を作る専用の操作は置かない（作る・入るを1つにする）。参加者がゼロになると、Realtime Databaseは空のデータを自動で消すので、部屋も消える
- 人数の上限は、**ルール（サーバー側）で守る**。画面だけで止めても、守れたことにならない
- 人数の上限は4人（`data/network.json` の `max_players: 4`）。部屋の中に枠 `p1`〜`p4` を作り、空いている枠にだけ入れる。Realtime Databaseのルールは人数を数えられないので（`numChildren` は使えない）、枠の数で上限を守る。枠の数と `max_players` が一致することは、`tests/test_room_rules.gd` で確かめる
- 「部屋のメンバー」と「動きの位置」は、別の場所に分ける（手順2で位置を1秒10回書き込む。メンバーの一覧を見張っているところに混ぜると、10回/秒でそのたびに通知が来てしまう）

#### 1. 部屋のデータの形（Realtime Database）
```
rooms/
  {合言葉4桁}/                 例：1234
    players/
      {ユーザーID}/             匿名ログインのuid
        joinedAt: (サーバーの時刻)
```
- 手順2で足す予定（今回は作らない）：`rooms/{合言葉}/positions/{ユーザーID}`（x、y、z、時刻）
- 名前などの項目は、今は持たない（`joinedAt` だけ）。足すときは、ルールも変える
- `rooms` 全体の一覧は、読めないようにする（部屋の合言葉を一覧で盗み見られないため）

#### 2. 合言葉から部屋に入る流れ
1. 画面の数字ボタン（0〜9、消す、入る、出る）で、4桁を入力する（スマホの仮想キーボードを使わない。iPhoneのブラウザでの入力が不安定になりやすいため。未検証）
2. Godot側で、4桁の数字だけか検査する（`^[0-9]{4}$`）。違えば、通信しない
3. ログイン済みか見る（なければ、確認シーンと同じ匿名ログイン）
4. JS側 `joinRoom(code)`：
   1. `rooms/{code}/players` を1回読み、すでに2人で、自分がいなければ「満員」と表示して終わる（親切な表示のため。**最終的な判定は、ルール**）
   2. 自分の場所 `rooms/{code}/players/{uid}` に `onDisconnect().remove()` を先に登録する（接続が切れたら、サーバーが自分を消す）
   3. `rooms/{code}/players/{uid}` に `{ joinedAt: サーバー時刻 }` を書く。ルールで拒否されたら、「入れませんでした（満員か、ルールの問題）」と表示する
   4. `rooms/{code}/players` の変更を見張り、参加者のuidの一覧を `state` に反映する
5. Godotは、確認シーンと同じく、0.2秒ごとに `state` を読んで画面に出す（例：`部屋1234：2/2人 あなた:uWJEjQ 相手:xxxxxx`）
6. 「出る」：自分の場所を消し、見張りをやめ、`onDisconnect` を取り消す
- 同じ人が、再読み込みして同じ合言葉で入り直す：自分の場所を上書きするだけ（人数は増えない）
- 順番を、`onDisconnect` の登録 → 書き込み、にする理由：書き込んだあとに落ちても、残骸が残らないようにするため
- 手順3で追加する：切れたあとの再接続では、同じ部屋に入り直す（`onDisconnect` で消えているため）

#### 3. 同じ部屋に2人まで、の確認方法
- A（ルールの単体の確認）：Firebaseコンソールの「ルールのプレイグラウンド」で、「すでに2人いる部屋に、3人目のuidが書く」が**拒否**、「自分の場所を消す」「2人目が入る」が**許可**になることを見る。結果は `NOTES.md` に書く
- B（実機で3つの端末）：iPhone Safari、PCのChrome、PCのChromeのプライベートウィンドウ（または Android Chrome）で、同じ合言葉 `1234` に入る
  - 1人目：OK（1/2）、2人目：OK（2/2）、3人目：「満員」になる
  - 1人が「出る」と、3人目が入れる
  - タブを閉じる（または機内モード）と、一定時間でその人が一覧から消える（何秒かかるか記録する）
  - 注意：同じブラウザ（同じタブ・同じプロファイル）は、同じuidになる。3人を作るには、別のブラウザか、プライベートウィンドウを使う
- C（同時に入る競争）：2人が入っている部屋に、ほぼ同時に3人目と4人目が入ろうとして、どちらも拒否されることを見る。さらに、1人しかいない部屋に、ほぼ同時に2人が入ろうとして、合計が2人を超えないことを見る（ルールの人数判定は、書き込みごとに順番に行われるはず。**未検証**。実機で確かめる）
- 自動テスト（`godot --headless`）でできること：合言葉の検査、場所の文字列の組み立て、状態からの画面の文字、ルールのJSONファイルの形（読める、上限が `network.json` と一致、合言葉の形の検査がある）。**ルールの中身の動作は、Godotのテストでは確かめられない**
- 追加でできるかもしれないこと（未決・未確認）：Firebase Emulator Suite とルールの単体テスト。NodeとJavaが要り、この環境で動くか未確認。使うかは、手順1-2の前に決める

#### 4. 必要なルール案（ログイン済みの人だけ。未検証・未公開）
置き場所：`firebase/database.rules.json`（コンソールの「ルール」に貼って公開する。サービスアカウントやCLIの認証情報は使わない）
```
{
  "rules": {
    ".read": false,
    ".write": false,
    "rooms": {
      "$code": {
        ".validate": "$code.matches(/^[0-9]{4}$/)",
        ".read": "auth != null",
        "players": {
          "$uid": {
            ".write": "auth != null && auth.uid === $uid",
            ".validate": "!newData.exists() || (newData.hasChildren(['joinedAt']) && newData.child('joinedAt').val() === now && (data.exists() || data.parent().numChildren() < 2))",
            "joinedAt": { ".validate": "newData.isNumber()" },
            "$other": { ".validate": false }
          }
        }
      }
    }
  }
}
```
- 意味：ログイン済みの人だけが、`rooms/{4桁}` の中を読める。書けるのは、**自分のuidの場所だけ**（他人を追い出せない）。合言葉は数字4桁だけ。人数が2人以上の部屋に、新しいuidは書けない（すでにいる自分の場所の上書きは可）。余計な項目は書けない
- `2` はルールの中に直接書くので、上限を変えるときは、`network.json` と一緒に直す（テストで一致を確認）
- 手順2で、`positions` のルールを足す（自分のuidの場所だけ書ける、x・y・zは数値、など）
- 今のRealtime Databaseがロックモード（全部拒否）かは未確認。ルールを公開するまで、読み書きはすべて失敗する想定
- 本番に向けて、見直すこと：4桁の合言葉の安全性（1万通り）、匿名ログインのuidの扱い、部屋の数や書き込み回数の上限、Sparkプランの同時接続数などの上限（最新の無料枠は未確認）

#### 5. 作る順番（小さな単位。1つずつ依頼する。各単位でテストを実行し、報告してからコミットの確認を取る）
- **1-1 合言葉と場所の純粋な関数**：**済み**（`data/network.json`、`scripts/network/room_code.gd`、テスト。ルールのファイルの案 `firebase/database.rules.json` とそのテストも、1-1で作った）。参加者の場所（`rooms/{4桁}/players/{uid}`）の関数は、必要になる1-3で足す
- **1-2 ルールの公開と確認**：ユーザーが `firebase/database.rules.json` をコンソールの「ルール」に貼って公開し、プレイグラウンドで確認（上の3-A）。結果を `NOTES.md` に書く。ここでルールを公開するまで、1-3以降の実機確認はできない
- **1-3 ブラウザ側のJSとGodotの橋渡し**：**済み（コードのみ。実機では未確認）**。`head_include`（確認用の書き出し）に、DatabaseのSDK（`firebase-database.js`、11.10.0に固定）を足し、`joinRoom` / `leaveRoom` / `state` を作った。空いている枠（p1→p4の順）を探して、書き込み、切断時の削除を予約する。書き込みが権限で拒否されたら（取り合いで負けた）次の枠に入る。権限以外のエラーは失敗として表示する。Godot側は `scripts/network/room_bridge.gd`（薄い橋渡し）。テスト：`tests/test_room_bridge.gd`（Godot）、`tests/js/room_bridge.test.mjs`（Nodeの偽SDKで、8項目）
- **1-4 画面**：数字ボタンと状態表示のシーン（`scenes/experiments/` の下）、文字や位置は `data/` のJSON。書き出しプリセット（機能タグ）の追加。既存のシーンと起動シーンは変えない
- **1-5 実機確認**：上の3-B、3-C。結果（成功・失敗、かかった秒数、エラーの文字）を `NOTES.md` に記録する。**実機で確かめるまで、「できた」と書かない**

#### 6. 決めたこと（2026-10-18、ユーザーの指示で既定の案に決定）
1. 「入る（なければ作る）」の1つの操作でよいか。分けるなら、「作る」（ランダムな4桁を発行）と「入る」（4桁を入力）の2つになる。推奨：1つ（友達同士で、合言葉を決めて入る形に合う）
2. 数字ボタンの入力でよいか（推奨）。仮想キーボードを使う案もある（未検証）
3. ルールのテストに、Firebase Emulator Suite（NodeとJavaが必要）を使うか。使わない場合、ルールは、プレイグラウンドと実機の確認だけになる
4. 試作の上限は2人でよいか（最終形は4人）

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
- 2026-10-18：iPhone Safariで Firebase 確認シーンが「Firebase OK（uWJEjQ）」と表示されたことを、ユーザーのスクリーンショットで確認し、記録した。コードの変更なし。コミット・プッシュはまだ（この `NOTES.md` の更新のみ）
- 2026-10-18：通信の試作の手順1（4桁の合言葉の部屋）の設計を `NOTES.md` に書いた（データの形、入る流れ、2人までの確認方法、作る順番1-1〜1-5、ルール案）。コードは書いていない。ルール案は未検証・未公開。コミット・プッシュはまだ
- 2026-10-18：GitHub Pages への自動公開の準備。①全履歴の秘密情報の検索（見つからず）②`CLAUDE.md` ルール11の変更（テスト全合格なら自動コミット・プッシュ）③`.github/workflows/pages.yml` を作成（actionlintでエラーなし）。この環境で、テンプレートの取り出し・全テスト・2つの書き出し・実ブラウザの表示を再現して確認。テスト：firebase_check 38／firebase_config 23／pages_workflow 23／render_test 28（すべて合格、失敗0）。GitHub上での実行、公開のURL、Pagesの設定は未確認
- 2026-10-18：手順1-3（入り口のJSと橋渡し）を作成。決定：入室は「合言葉を入れると、入る（部屋は最初の人が入った時にできる）」、数字ボタンで入力（1-4で作る）、上限は4人（p1〜p4の枠）、Firebaseのエミュレータは、この環境からnpmとGoogleのストレージに接続できないため使わない。テスト：Godot 7本（合格）、Node 8項目（合格）。実機確認（1-5）は未実施。コミット・プッシュ済み
- 2026-10-18：人数の上限を枠の方式に変更（A1：参加時刻はアプリが送る数字をそのまま使う／B1：枠 p1〜p4）。ルールは `firebase/database.rules.json` が正（コンソールに公開する内容と同じ）。`NOTES.md` の手順1のルール案は古い版。`numChildren` はRealtime Databaseで使えず、コンソールでエラーになったため変更。Godotの6つのテストを、Godot 4.7.2 headless で実行して全合格（失敗0）。ルールの動作（誰が書けるか）は、Firebaseのプレイグラウンドで確かめる。エミュレータ版のテストは、この環境から npm と Google のストレージに接続できないため未作成
- 2026-10-18：通信の試作 手順1-1：合言葉の検査・部屋の場所の関数（`scripts/network/room_code.gd`）、`data/network.json`（4桁・2人）、ルールの案（`firebase/database.rules.json`、未適用）、テスト2つ（37項目・22項目）を追加。全6テスト合格（合計171項目、失敗0）。画面・ネットワーク接続は未着手。ルールの動作は未確認
