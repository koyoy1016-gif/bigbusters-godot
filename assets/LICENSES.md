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

## 自作の質感（assets/textures/）
- cloth.png / steel.png / skin.png / leather.png：`tools/make_textures.py` が計算で作った画像（他の作品は使っていない）。CC0として扱う。

## 自作の効果音（assets/audio/sfx/）
- 15個の .wav：`tools/make_sfx.py` が、計算（ノイズと音程の変化）で作った。他の作品の音は使っていない。CC0として扱う。

## 自作のBGM（assets/audio/bgm/）
- `menu.wav`（16秒のループ）：`tools/make_bgm.py` が、計算（矩形波・サイン波・ノイズ）で作った。他の作品の曲・旋律は使っていない。CC0として扱う。

## 動きの素材（assets/anims/hero_ual.res）
- Quaternius「Universal Animation Library [Standard]」（https://quaternius.com/packs/universalanimationlibrary.html）。ライセンス：CC0 1.0（パブリックドメイン）。配布のzipの License.txt で確認済み（2026-10-19）。
- 元の動き（UAL1_Standard.glb）から、一部の動き（待ち・走り・ジャンプ・こうげき・たおれる・ダメージ・ころがり・技・パンチ）を、`tools/retarget_ual.gd` で主人公（MPFBの骨）に移して保存した。元のファイルは、リポジトリには入れていない。

## ボスの模様（assets/textures/boss/）
- tiger.png（スカジャンの背中のトラ）：`tools/make_boss_decals.py` が、丸・三角などの図形の組み合わせで描いた自作の図案。CC0として扱う。
- yoi.png・sake.png（「酔」「酒」の文字）：同じツールが、同梱の Noto Sans JP（SIL OFL 1.1、上の「フォント」の項）で書いた画像。

## 参考画像（ゲームには入れない）
- `docs/ref/boss_oni_reference.jpg`：ユーザーが用意したボスのデザインの参考画像。形と色を合わせるために見るだけで、ゲームの中では使っていない（書き出しにも入らない）。

## 2026-10-20 版77：味方8人のモデル
- `assets/models/chars/*.scn`（brawler・sprinter・gunner・bomber・mage・guardian・summoner・healer）：剣士の体（`hero_swordsman.glb`、MakeHuman の CC0 素材）と骨を土台に、Claude がコード（`scripts/characters/body_builder.gd`・`tools/make_looks.py`・`tools/bake_looks.gd`）で形と色を作った。新しい外の素材は使っていない。ライセンスは剣士の体と同じ（CC0）。見た目の参考は、ユーザーの画像（`docs/ref/chars/`）。
