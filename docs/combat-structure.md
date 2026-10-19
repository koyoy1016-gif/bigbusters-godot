# 戦いのコードの分け方（版46〜）

「当たり判定やダメージのコードがごちゃごちゃになる」のを防ぐため、役目ごとに1つずつの部品に分けた。
新しい攻撃や技を足すときは、まず「どの部品の仕事か」を見る。

| 役目 | 場所 | 持つもの |
|---|---|---|
| 数値（当たる時刻、倍率、待ち時間、体の動き） | `data/actions.json` | 数字だけ。コードには書かない（CLAUDE.md ルール3） |
| 攻撃の時間の進み | `scripts/combat/player_actions.gd` | 画面もダメージも持たない。「いま当たった」「アニメを切り替える」という出来事を返すだけ |
| 当たりの範囲 | `scripts/combat/hit_area.gd`（形そのものは `skills.gd`） | 届くか、だけを調べる |
| ダメージの計算 | `scripts/combat/damage.gd` の `damage_amount` | ここだけ（CLAUDE.md ルール4） |
| 出来事を受けて、ボス・サブ敵に当てる | `stick_prototype.gd` の `_resolve_hit` | 当たりの結果を体力に反映する、ここ1か所 |
| 見た目のアニメ | `character_view.gd` の `play_step` | 出来事の「anim」を受けて流す |
| ボスの攻撃 | `boss_attacks.gd` + `data/boss_attacks.json` | プレイヤーの攻撃とは別。時刻だけで決まる |

## 3つの攻撃（全キャラ共通の構成）
- 通常（つうじょう）：1回斬る。待ち時間はキャラの `attack_cooldown_sec`。
- サブ（Y）：敵に向かって跳びながら斬って、下がってくる。空中にいる間は、「ジャンプでよけられる」ボスの攻撃を受けない。
- メイン（X）：素早く5回斬る。少しずつ前に出る。
- ジャンプのボタン・機能は無い。

## 新しい攻撃の足し方
1. `data/actions.json` の `actions` に、id・数値・`hits`・`steps`・`path` を書く。`order` に id を足す。
2. `data/prototype_stick.json` に `<id>_center_frac`（と `_portrait`）を足す。
3. キャラの `animations` に、`steps` の `anim` 名（例 `swing`）が指すアニメ名を書く（なければ `attack` で代用）。
4. `tests/test_player_actions.gd` にテストを足す。

## 置いてある（いまは使っていない）もの
旧Xの技（ダッシュ・射撃・魔法・投げ・バリア・回復・召喚）の計算は、`scripts/combat/skills.gd` の形の関数と
`data/skills.json`、`data/characters.json` の `skill` に残してある。ボタンへの配線は外した（版46より前のコミットにある）。
メイン攻撃の「付け足しの効果」として戻す場合は、`actions.json` に効果を足す形で作り直す。
