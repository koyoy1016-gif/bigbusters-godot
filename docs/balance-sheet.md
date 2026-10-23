# 数字の一覧表（自動で作った読み物）

`python3 tools/balance_table.py` で作り直す。**数字を直すのは `data/characters.json`・`data/skills.json`・`data/prototype_stick.json`。この表は直さない。**

## キャラ（ふつうのこうげき）

| キャラ | 役職 | HP | 足の速さ | 攻撃力 | 待ち時間(秒) | 届く距離 | 1秒あたりの火力 | ボスを倒す時間(1人・秒) |
|---|---|---|---|---|---|---|---|---|
| 剣士（hero_swordsman） | ファイター | 190 | 7 | 22.5 | 0.35 | 2 | 64.3 | 93 |
| 瞬（sprinter） | ファイター | 105 | 10 | 12 | 0.25 | 2 | 48.0 | 125 |
| 拳士（brawler） | ファイター | 135 | 8 | 15 | 0.3 | 2 | 50.0 | 120 |
| 銃士（gunner） | シューター | 105 | 6 | 13.5 | 0.3 | 7 | 45.0 | 133 |
| 奇術師（bomber） | シューター | 112.5 | 5 | 16.5 | 0.6 | 6 | 27.5 | 218 |
| 魔法師（mage） | シューター | 97.5 | 5.5 | 18 | 0.5 | 7 | 36.0 | 167 |
| 守護士（guardian） | ガーディアン | 240 | 5 | 10.5 | 0.5 | 2 | 21.0 | 286 |
| 兵隊（summoner） | サポート | 120 | 6 | 9 | 0.4 | 5 | 22.5 | 267 |
| 介護士（healer） | サポート | 127.5 | 6 | 7.5 | 0.4 | 5 | 18.8 | 320 |

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
| 回復 | heal | 8 | - | heal=45.0 |
| 召喚 | summon | 12 | 0.8 | duration_sec=8.0, hit_interval_sec=0.5 |

## ボス・全体

- ボスの体力：6000
- ダメージの倍率（全体）：1
- 戦いの制限時間などは `data/prototype_stick.json` を見る
