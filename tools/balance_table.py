#!/usr/bin/env python3
"""data/*.json から、キャラ・技・ボスの数字の一覧表（docs/balance-sheet.md）を作る。
数字を直すのは data/*.json。この表は、直したあとに実行し直して、見比べるための読み物。
使い方: python3 tools/balance_table.py"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
chars = json.loads((root / "data" / "characters.json").read_text())["characters"]
skills = json.loads((root / "data" / "skills.json").read_text())
cfg = json.loads((root / "data" / "prototype_stick.json").read_text())
mult = float(cfg.get("attack_multiplier", 1.0))
boss_hp = float(cfg["boss_hp"])

lines = ["# 数字の一覧表（自動で作った読み物）", "",
         "`python3 tools/balance_table.py` で作り直す。**数字を直すのは `data/characters.json`・`data/skills.json`・`data/prototype_stick.json`。この表は直さない。**", "",
         "## キャラ（ふつうのこうげき）", "",
         "| キャラ | 役職 | HP | 足の速さ | 攻撃力 | 待ち時間(秒) | 届く距離 | 1秒あたりの火力 | ボスを倒す時間(1人・秒) |",
         "|---|---|---|---|---|---|---|---|---|"]
for c in chars:
    s = c.get("stats", {})
    if not s:
        continue
    dps = float(s["attack_power"]) * mult / float(s["attack_cooldown_sec"])
    lines.append("| %s（%s） | %s | %g | %g | %g | %g | %g | %.1f | %.0f |" % (
        c["name"], c["id"], c["role"], s["hp"], s["move_speed"], s["attack_power"],
        s["attack_cooldown_sec"], s["attack_reach"], dps, boss_hp / dps if dps > 0 else 0))
lines += ["", "※ 火力は、立ち止まってボスに当て続けたときの理想値（動く時間・避ける時間は入っていない）。", "",
          "## 技（Xボタン）", "", "| 技 | 種類 | 待ち時間(秒) | 倍率 | その他 |", "|---|---|---|---|---|"]
for name, d in skills.items():
    if not isinstance(d, dict):
        continue
    other = ", ".join("%s=%s" % (k, v) for k, v in d.items() if k not in ("kind", "cooldown_sec", "multiplier", "fx_color", "fx_sec"))
    lines.append("| %s | %s | %g | %s | %s |" % (name, d.get("kind", ""), d.get("cooldown_sec", 0), d.get("multiplier", "-"), other))
lines += ["", "## ボス・全体", "",
          "- ボスの体力：%g" % boss_hp,
          "- ダメージの倍率（全体）：%g" % mult,
          "- ボスがおこる時間：%g 秒" % float(cfg.get("enrage_after_sec", 0)),
          "- 戦いの制限時間などは `data/prototype_stick.json` を見る", ""]
(root / "docs" / "balance-sheet.md").write_text("\n".join(lines))
print("docs/balance-sheet.md を作りました")
