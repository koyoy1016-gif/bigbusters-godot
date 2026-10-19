#!/usr/bin/env python3
"""侍（hero_swordsman）の装備の部品を、data/attachments.json の items に書き込む。
座標は「モデル座標」（体の前が +Z、上が +Y、キャラの左が +X）。骨は、動きについていく先。
使い方: python3 tools/make_samurai.py"""
import json
from pathlib import Path

INDIGO = "#1f2f5a"
DEEP = "#16213f"
ARMOR = "#26345f"
WHITE = "#f1efe8"
RED = "#b8262a"
BLACK = "#16161c"
STEEL = "#d8dde3"


def rod(a, b, r0, r1, color, squash=(1, 1), metallic=0.0, rough=0.85):
    return {"shape": "rod", "from": list(a), "to": list(b), "r0": r0, "r1": r1, "squash": list(squash), "color": color, "metallic": metallic, "roughness": rough}


def box(c, size, rot, color, metallic=0.0, rough=0.8):
    return {"shape": "box", "center": list(c), "size": list(size), "rotation_deg": list(rot), "color": color, "metallic": metallic, "roughness": rough}


def sph(c, r, color, squash=(1, 1, 1), metallic=0.0, rough=0.8):
    return {"shape": "sphere", "center": list(c), "r": r, "squash": list(squash), "color": color, "metallic": metallic, "roughness": rough}


def mirror(p):
    """左右を反転した部品（x の符号を逆にする）"""
    q = json.loads(json.dumps(p))
    for k in ("from", "to", "center"):
        if k in q:
            q[k][0] = -q[k][0]
    if "rotation_deg" in q:
        q["rotation_deg"][1] = -q["rotation_deg"][1]
        q["rotation_deg"][2] = -q["rotation_deg"][2]
    return q


def item(bone, parts):
    return {"bone": bone, "space": "model", "parts": parts}


items = {}

# ---- 着物（藍）と白い襟 ----
items["sam_kimono_chest"] = item("spine01", [
    rod((0, 1.40, 0.015), (0, 1.66, 0.015), 0.19, 0.2, INDIGO, squash=(1.0, 0.8)),
    box((0.05, 1.52, 0.176), (0.04, 0.26, 0.012), (0, 0, -10), WHITE),
    box((-0.05, 1.52, 0.176), (0.04, 0.26, 0.012), (0, 0, 10), WHITE),
])
items["sam_kimono_waist"] = item("spine03", [
    rod((0, 1.10, 0.02), (0, 1.42, 0.02), 0.19, 0.195, INDIGO, squash=(1.0, 0.86)),
])
# ---- 帯（白）と赤いひも ----
items["sam_obi"] = item("spine05", [
    rod((0, 1.14, 0.015), (0, 1.26, 0.015), 0.215, 0.215, WHITE, squash=(1.0, 0.88)),
    sph((0.0, 1.2, 0.2), 0.036, RED),
    rod((0.0, 1.19, 0.205), (0.03, 1.0, 0.21), 0.012, 0.01, RED),
    rod((0.0, 1.19, 0.205), (-0.03, 1.02, 0.21), 0.012, 0.01, RED),
])
# ---- 袴の腰まわり（前と後ろ。ジーンズが見えないように）----
items["sam_hakama_skirt"] = item("spine05", [
    rod((0, 0.98, 0.0), (0, 1.26, 0.0), 0.215, 0.2, DEEP, squash=(1.0, 0.82)),
])
# ---- 袴（濃い藍。すそが広がる）----
hakama_l = [
    rod((0.085, 1.22, 0.0), (0.16, 0.56, 0.02), 0.13, 0.125, DEEP),
]
hakama_l2 = [
    rod((0.16, 0.56, 0.02), (0.205, 0.13, 0.01), 0.125, 0.15, DEEP),
    rod((0.2, 0.17, 0.01), (0.205, 0.13, 0.01), 0.152, 0.152, WHITE),
]
items["sam_hakama_thigh_L"] = item("upperleg01.L", hakama_l)
items["sam_hakama_thigh_R"] = item("upperleg01.R", [mirror(p) for p in hakama_l])
items["sam_hakama_shin_L"] = item("lowerleg01.L", hakama_l2)
items["sam_hakama_shin_R"] = item("lowerleg01.R", [mirror(p) for p in hakama_l2])
# ---- 袖（広い藍）----
sleeve = [rod((0.22, 1.58, 0.013), (0.42, 1.35, 0.02), 0.085, 0.115, INDIGO)]
items["sam_sleeve_L"] = item("upperarm01.L", sleeve)
items["sam_sleeve_R"] = item("upperarm01.R", [mirror(p) for p in sleeve])
# ---- 籠手（前腕の鎧。赤い帯）----
kote = [
    rod((0.43, 1.34, 0.03), (0.555, 1.22, 0.215), 0.058, 0.046, ARMOR, metallic=0.3, rough=0.5),
    rod((0.47, 1.30, 0.075), (0.49, 1.275, 0.1), 0.062, 0.062, RED),
]
items["sam_kote_L"] = item("lowerarm01.L", kote)
items["sam_kote_R"] = item("lowerarm01.R", [mirror(p) for p in kote])
# ---- 胴（胸当て。濃い藍に赤いひも）----
items["sam_do"] = item("spine02", [
    rod((0, 1.36, 0.02), (0, 1.62, 0.02), 0.21, 0.225, ARMOR, squash=(1.0, 0.82), metallic=0.25, rough=0.5),
    box((0, 1.42, 0.195), (0.34, 0.022, 0.012), (0, 0, 0), RED),
    box((0, 1.50, 0.2), (0.36, 0.022, 0.012), (0, 0, 0), RED),
    box((0, 1.58, 0.198), (0.34, 0.022, 0.012), (0, 0, 0), RED),
    box((0, 1.51, 0.205), (0.02, 0.26, 0.012), (0, 0, 0), RED),
])
# ---- 袖の鎧（肩）----
sode = [
    box((0.3, 1.66, 0.012), (0.2, 0.016, 0.17), (0, 0, -28), ARMOR, metallic=0.25, rough=0.5),
    box((0.312, 1.645, 0.012), (0.2, 0.012, 0.175), (0, 0, -28), RED),
]
items["sam_sode_L"] = item("clavicle.L", sode)
items["sam_sode_R"] = item("clavicle.R", [mirror(p) for p in sode])
# ---- 草摺（腰のまわりの垂れ。5まい）----
kusa = []
import math
for deg in (-70, -35, 0, 35, 70):
    a = math.radians(deg)
    x = math.sin(a) * 0.22
    z = math.cos(a) * 0.19 + 0.01
    kusa.append(box((x, 1.07, z), (0.085, 0.2, 0.012), (0, deg, 0), ARMOR, metallic=0.25, rough=0.5))
    kusa.append(box((x * 1.01, 0.965, z * 1.01), (0.085, 0.014, 0.014), (0, deg, 0), RED))
items["sam_kusazuri"] = item("spine05", kusa)
# ---- 足（黒い足袋ぐつ）----
boot = [rod((0.208, 0.16, 0.0), (0.212, 0.02, 0.0), 0.07, 0.072, BLACK, rough=0.6), rod((0.208, 0.06, 0.03), (0.213, 0.025, 0.2), 0.07, 0.05, BLACK, rough=0.6, squash=(1.0, 0.8))]
items["sam_boot_L"] = item("foot.L", boot)
items["sam_boot_R"] = item("foot.R", [mirror(p) for p in boot])
# ---- 髪：高い位置の結び髪（赤いひも）----
items["sam_ponytail"] = item("head", [
    sph((0, 1.94, -0.045), 0.045, BLACK),
    rod((0, 1.93, -0.06), (0, 1.74, -0.19), 0.036, 0.016, BLACK),
    rod((0, 1.76, -0.185), (0, 1.58, -0.205), 0.02, 0.006, BLACK),
    rod((0, 1.915, -0.052), (0, 1.89, -0.07), 0.05, 0.05, RED),
])
# ---- 長めの刀（手に持つ）。刃は 1.1m、鍔、赤い柄巻き ----
katana_parts = [
    {"shape": "cylinder", "size": [0.021, 0.24, 0.021], "offset": [0, -0.02, 0], "rotation_deg": [0, 0, 0], "color": INDIGO, "metallic": 0.0, "roughness": 0.9},
    {"shape": "cylinder", "size": [0.0225, 0.03, 0.0225], "offset": [0, -0.1, 0], "rotation_deg": [0, 0, 0], "color": RED, "metallic": 0.0, "roughness": 0.9},
    {"shape": "cylinder", "size": [0.0225, 0.03, 0.0225], "offset": [0, 0.0, 0], "rotation_deg": [0, 0, 0], "color": RED, "metallic": 0.0, "roughness": 0.9},
    {"shape": "cylinder", "size": [0.055, 0.012, 0.055], "offset": [0, 0.115, 0], "rotation_deg": [0, 0, 0], "color": BLACK, "metallic": 0.6, "roughness": 0.4},
    {"shape": "box", "size": [0.036, 1.1, 0.008], "offset": [0, 0.67, 0], "rotation_deg": [0, 0, 0], "color": STEEL, "metallic": 0.95, "roughness": 0.2},
]
items["katana_long"] = {"bone": "wrist.R", "parts": katana_parts, "offset": [0.0, 0.08, 0.0], "aim": [0.4, 0.235, 0.874]}
# ---- 腰の鞘（空）----
items["sam_saya"] = item("spine05", [
    rod((0.23, 1.17, 0.1), (0.3, 0.9, -0.45), 0.026, 0.024, BLACK, metallic=0.4, rough=0.35),
    rod((0.23, 1.17, 0.1), (0.233, 1.157, 0.075), 0.032, 0.032, RED),
])

GOLD = "#c9a227"
# ---- 鉢巻（白）と、前立て（金の三日月）：シルエットで侍と分かるように ----
items["sam_hachimaki"] = item("head", [
    rod((0, 1.885, 0.0), (0, 1.925, 0.0), 0.118, 0.118, WHITE, squash=(1.0, 1.06)),
    box((0, 1.905, 0.125), (0.05, 0.045, 0.01), (0, 0, 0), RED),
])
items["sam_maedate"] = item("head", [
    rod((0.0, 1.93, 0.128), (0.07, 2.06, 0.13), 0.014, 0.006, GOLD, metallic=0.8, rough=0.3),
    rod((0.0, 1.93, 0.128), (-0.07, 2.06, 0.13), 0.014, 0.006, GOLD, metallic=0.8, rough=0.3),
    sph((0.0, 1.935, 0.13), 0.022, GOLD, squash=(1, 1, 0.6), metallic=0.8, rough=0.3),
])
# ---- 首当て（のどわ）----
items["sam_nodowa"] = item("head", [
    rod((0, 1.66, 0.0), (0, 1.73, 0.0), 0.105, 0.085, ARMOR, squash=(1.0, 0.9), metallic=0.5, rough=0.4),
    rod((0, 1.725, 0.0), (0, 1.735, 0.0), 0.088, 0.088, RED),
])
# ---- 胸の紋（金）----
items["sam_mon"] = item("spine02", [
    sph((0, 1.51, 0.212), 0.04, GOLD, squash=(1, 1, 0.25), metallic=0.8, rough=0.3),
])
# ---- 袖の鎧を重ねる（2まい目、3まい目）----
sode2 = [
    box((0.325, 1.625, 0.012), (0.2, 0.014, 0.17), (0, 0, -34), ARMOR, metallic=0.4, rough=0.45),
    box((0.345, 1.595, 0.012), (0.2, 0.014, 0.17), (0, 0, -40), ARMOR, metallic=0.4, rough=0.45),
    box((0.337, 1.608, 0.012), (0.2, 0.01, 0.175), (0, 0, -37), GOLD, metallic=0.8, rough=0.3),
]
items["sam_sode2_L"] = item("clavicle.L", sode2)
items["sam_sode2_R"] = item("clavicle.R", [mirror(p) for p in sode2])
# ---- すね当て（鉄）----
sune = [
    rod((0.2, 0.46, 0.035), (0.2, 0.2, 0.035), 0.1, 0.085, STEEL, metallic=0.85, rough=0.3),
    rod((0.2, 0.46, 0.035), (0.2, 0.455, 0.035), 0.108, 0.108, RED),
    rod((0.2, 0.2, 0.035), (0.2, 0.195, 0.035), 0.09, 0.09, GOLD, metallic=0.8, rough=0.3),
]
items["sam_suneate_L"] = item("lowerleg01.L", sune)
items["sam_suneate_R"] = item("lowerleg01.R", [mirror(p) for p in sune])
# ---- 大腿の当て（はいだて）----
hai = [rod((0.15, 1.0, 0.04), (0.17, 0.66, 0.04), 0.1, 0.095, ARMOR, metallic=0.4, rough=0.45),
       rod((0.17, 0.665, 0.04), (0.17, 0.655, 0.04), 0.1, 0.1, GOLD, metallic=0.8, rough=0.3)]
items["sam_haidate_L"] = item("upperleg01.L", hai)
items["sam_haidate_R"] = item("upperleg01.R", [mirror(p) for p in hai])

p = Path(__file__).resolve().parent.parent / "data" / "attachments.json"
d = json.loads(p.read_text(encoding="utf8"))
d["items"].update(items)
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf8")
print("書き込みました：", ", ".join(items))
