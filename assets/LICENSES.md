# 素材とライセンス

使った素材は、ここに記録する。

## フォント

| ファイル | 元のフォント | ライセンス | 入手先 | 備考 |
|---|---|---|---|---|
| `assets/fonts/NotoSansJP-Regular-subset.ttf` | Noto Sans JP Regular（Copyright 2014-2021 Adobe。Reserved Font Name 'Source'） | SIL Open Font License 1.1（再配布・同梱OK）。全文は `assets/fonts/NotoSansJP-OFL.txt` | npmパッケージ `@expo-google-fonts/noto-sans-jp` 0.4.4（`400Regular/NotoSansJP_400Regular.ttf`）。元はGoogle Fonts | 軽くするため、文字を絞った版（ASCII、ひらがな、カタカナ、JIS X 0208の漢字、記号。約6,970字、約2.1MB）。ヒンティングと字形の切り替え機能（GSUBなど）は外した |

- フォントを改変（文字の絞り込み）したので、ファイル名に Reserved Font Name の 'Source' を使っていない
- フォント単体を売ることはしない（OFLの条件）。ゲームに同梱するのは問題ない
- 必要な文字が増えたときは、文字を足して作り直す（作り方は `NOTES.md` の作業ログ）

## 3Dモデル

| ファイル | 内容 | ライセンス | 入手先 | 備考 |
|---|---|---|---|---|
| `assets/models/hero_swordsman.glb`（と、取り込み時に出る `hero_swordsman_*.png`） | 剣士（体・髪・眉・まつ毛・目・服・靴） | CC0（下の素材はMakeHumanの「system assets CC0」の配布物）。**未確認**：各素材ごとのライセンス表示は、配布ページの説明（CC0と書かれたzip名）による。素材ごとのファイルの表記は見ていない | Blender 5.2.2 LTS＋MPFB 2.0.18（アドオンはGPL。作ったキャラは対象外とされている）で、ユーザーが作成 | 使った素材：体（basemesh、Young asian male肌）、髪 short04、眉 eyebrow001/004、まつ毛 eyelashes01、目 low-poly（brown_eye）、服 male_casualsuit06、靴 shoes01。Tシャツの「MakeHuman」ロゴと隅の透かし文字は、画像を塗りつぶして消した。テクスチャは縮小（肌・服1024、ほか512） |

## 自作の部品（コードで作る形）

| 内容 | ライセンス | 備考 |
|---|---|---|
| 侍の装備（袴・着物・帯・鎧・籠手・草摺・結び髪・刀・鞘・足袋ぐつ）`data/attachments.json`（`tools/make_samurai.py` で作る） | 自作（権利の問題なし） | 箱・円柱・球の組み合わせ。他の作品の形は使っていない |
