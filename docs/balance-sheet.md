# 数字の一覧表（自動で作った読み物）

`python3 tools/balance_table.py` で作り直す。**数字を直すのは `data/characters.json`・`data/skills.json`・`data/prototype_stick.json`。この表は直さない。**

## キャラ（ふつうのこうげき）

| キャラ | 役職 | HP | 足の速さ | 攻撃力 | 待ち時間(秒) | 届く距離 | 1秒あたりの火力 | ボスを倒す時間(1人・秒) |
|---|---|---|---|---|---|---|---|---|
| けんし（hero_swordsman） | ファイター | 100 | 7 | 12 | 0.35 | 2 | 34.3 | 9 |
| はやて（sprinter） | ファイター | 70 | 10 | 8 | 0.25 | 2 | 32.0 | 9 |
| こぶし（brawler） | ファイター | 90 | 8 | 10 | 0.3 | 2 | 33.3 | 9 |
| じゅうし（gunner） | シューター | 70 | 6 | 9 | 0.3 | 7 | 30.0 | 10 |
| ばくだん（bomber） | シューター | 75 | 5 | 11 | 0.6 | 6 | 18.3 | 16 |
| まほう（mage） | シューター | 65 | 5.5 | 12 | 0.5 | 7 | 24.0 | 12 |
| たて（guardian） | ガーディアン | 160 | 5 | 7 | 0.5 | 2 | 14.0 | 21 |
| よびだし（summoner） | サポート | 80 | 6 | 6 | 0.4 | 5 | 15.0 | 20 |
| いやし（healer） | サポート | 85 | 6 | 5 | 0.4 | 5 | 12.5 | 24 |

※ 火力は、立ち止まってボスに当て続けたときの理想値（動く時間・避ける時間は入っていない）。

## 技（Xボタン）

| 技 | 種類 | 待ち時間(秒) | 倍率 | その他 |
|---|---|---|---|---|
| 斬る | arc | 4 | 2.5 | radius=3.5, half_angle_deg=70.0 |
| ダッシュ | dash | 3 | - | distance=5.0, duration_sec=0.2 |
| 射撃 | line | 3 | 3.0 | length=14.0, half_width=0.6, pierce=False |
| 魔法 | line | 4 | 2.5 | length=10.0, half_width=1.2, pierce=True |
| 投げ | lob | 5 | 3.0 | throw_distance=6.0, delay_sec=0.7, radius=3.2 |
| バリア | guard | 8 | - | duration_sec=3.0, damage_taken_multiplier=0.2 |
| 回復 | heal | 8 | - | heal=30.0 |
| 召喚 | summon | 12 | 0.8 | duration_sec=8.0, hit_interval_sec=0.5 |

## ボス・全体

- ボスの体力：300
- ダメージの倍率（全体）：1
- ボスがおこる時間：45 秒
- 戦いの制限時間などは `data/prototype_stick.json` を見る
