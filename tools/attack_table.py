#!/usr/bin/env python3
"""ボスの攻撃のバランス表（Markdown）を data/boss_attacks.json から作って、標準出力に出す。
使い方: python3 tools/attack_table.py
時間は attack_speed をかけたあとの秒（実際のゲームの秒）。巨大酒瓶ライドは ride_* から計算（いちばん長いとき）。削除した攻撃（ai.forms が空）は出さない。"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = json.load(open(os.path.join(ROOT, "data", "boss_attacks.json"), encoding="utf-8"))
sp = float(d.get("attack_speed", 1.0))
NAMES = {"bat_h": "横振り", "bat_v": "縦振り＋衝撃波", "bat_spin": "回転斬り", "tail_spin": "しっぽ回し", "walk_swing": "歩きながら振る",
         "grab": "つかみ投げ", "thrust": "前方突き", "bat_throw": "バット投げ", "spin_charge": "回転突進", "jump_slam": "ジャンプ落下",
         "typhoon": "台風", "sake_drop": "酒瓶落とし", "fire_fest": "火祭り（必殺）", "bottle_ride": "巨大酒瓶ライド（必殺）",
         "flyer_storm": "酒の大雨（必殺）", "hand_sweep": "大きな手（必殺）",
         "jump_move": "移動ジャンプ落下"}


def ride_total(k):
    """いちばん長いとき（boss_attacks.gd の ride_total と同じ計算）。実際は道によって短い"""
    half = float(k.get("stage_half", 15.0))
    longest = (2.0 * (half + k["lane_spread"]) + 2.0 * (k["offscreen"] + k["half_len"])) * 2 ** 0.5
    per = longest / (k["ride_speed"] * k["speed_min"]) + k["ride_switch"]
    return k["ride_intro"] + k["ride_tele"] + per * k["passes_max"] + k["ride_outro"] + k["ride_recover"]


def sec(k, key):
    if key not in k:
        return None
    return float(k[key]) / sp if key not in d.get("speed_exempt", []) else float(k[key])


print("| 攻撃 | 平常の重み | 覚醒の重み | 長さ（秒） | 予告・ため（秒） | ダメージ | ふっ飛び | 使ったあと待つ（秒） | 必殺 |")
print("|---|---|---|---|---|---|---|---|---|")
for kind, k in d["kinds"].items():
    ai = k.get("ai", {})
    forms = ai.get("forms", {})
    if not forms:
        continue
    dur = ride_total(k) if kind == "bottle_ride" else sec(k, "duration")
    tele = None
    for key in ("windup_sec", "crouch_sec", "tele_sec"):
        if key in k:
            tele = sec(k, key)
            break
    if kind == "bottle_ride":
        tele = k["ride_tele"]
    power = k.get("power", "")
    if kind == "fire_fest":
        power = "%s（火 %s）" % (power, k.get("fire_power"))
    if kind == "bottle_ride":
        power = "%s（投げた瓶 %s×%d本／突入）" % (power, k.get("throw_power"), k.get("bottles_per_pass"))
    print("| %s | %s | %s | %.1f | %s | %s | %s | %s | %s |" % (
        NAMES.get(kind, kind), forms.get("normal", "-"), forms.get("awake", "-"), dur,
        "%.2f" % tele if tele is not None else "-", power, k.get("knockback", "-"),
        ai.get("cooldown_sec", "-"), "○" if ai.get("ultimate") else ""))
