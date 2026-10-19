#!/usr/bin/env python3
"""ボス（鬼）の小物を、data/attachments.json の items に書き込む（名前は oni_ で始まる）。
体は剣士と同じ人型（MPFB の骨）。座標は「モデル座標」（体の前が +Z、上が +Y、キャラの左が +X。身長およそ2）。
ボスの大きさは data/boss_model.json の model_scale で決める。
使い方: python3 tools/make_oni.py"""
import json
import math
from pathlib import Path

HORN = "#d2bc8e"
RED = "#cc2230"
DARK = "#2a1626"
GOLD = "#e2b23a"
WHITE = "#f3efe6"
SLEEVE = "#e8dcc0"
RIB_RED = "#c42e3a"
BELT = "#1d1a24"
STUD = "#c8c8d2"
BAT = "#8e92a4"
SPIKE = "#d4d7e0"
GRIP = "#ebe7dc"
TOOTH = "#f6f2e6"
BOTTLE = "#3f7a44"
LABEL = "#f4f1ea"
JUG = "#c8955a"


def rod(a, b, r0, r1, color, squash=(1, 1), metallic=0.0, rough=0.85):
    return {"shape": "rod", "from": list(a), "to": list(b), "r0": r0, "r1": r1, "squash": list(squash), "color": color, "metallic": metallic, "roughness": rough}


def box(c, size, rot, color, metallic=0.0, rough=0.8):
    return {"shape": "box", "center": list(c), "size": list(size), "rotation_deg": list(rot), "color": color, "metallic": metallic, "roughness": rough}


def sph(c, r, color, squash=(1, 1, 1), metallic=0.0, rough=0.8):
    return {"shape": "sphere", "center": list(c), "r": r, "squash": list(squash), "color": color, "metallic": metallic, "roughness": rough}


def mirror(p):
    q = json.loads(json.dumps(p))
    for k in ("from", "to", "center"):
        if k in q:
            q[k][0] = -q[k][0]
    if "rotation_deg" in q:
        q["rotation_deg"][1] = -q["rotation_deg"][1]
        q["rotation_deg"][2] = -q["rotation_deg"][2]
    return q


def both(parts):
    out = []
    for p in parts:
        out.append(p)
        out.append(mirror(p))
    return out


def item(bone, parts):
    return {"bone": bone, "space": "model", "parts": parts}


items = {}

# ---- 頭：反った角、赤と黒のリーゼント、牙 ----
items["oni_horns"] = item("head", both([
    rod((0.075, 1.93, 0.05), (0.11, 2.03, 0.0), 0.028, 0.02, HORN, rough=0.5),
    rod((0.11, 2.03, 0.0), (0.12, 2.10, -0.08), 0.02, 0.004, HORN, rough=0.5),
]))
items["oni_hair"] = item("head", [
    sph((0.0, 1.955, -0.01), 0.112, DARK, squash=(1.0, 0.75, 1.05)),
    sph((0.0, 1.99, 0.05), 0.085, RED, squash=(0.85, 0.85, 1.5)),
    sph((0.0, 2.02, 0.13), 0.06, RED, squash=(0.9, 0.85, 1.25)),
    rod((0.0, 2.02, 0.17), (0.0, 1.99, 0.24), 0.045, 0.012, RED),
    sph((0.0, 1.97, -0.08), 0.075, RED, squash=(1.0, 1.0, 0.9)),
] + both([
    rod((0.1, 1.88, -0.02), (0.11, 1.80, -0.05), 0.03, 0.01, DARK),
]))
items["oni_fangs"] = item("jaw", both([
    rod((0.024, 1.765, 0.118), (0.022, 1.733, 0.126), 0.009, 0.001, TOOTH, rough=0.4),
]))
# ---- 胸：金のネックレス2本と南京錠 ----
neck = []
for i in range(9):
    t = i / 8.0
    x = -0.1 + 0.2 * t
    y = 1.6 - 0.09 * (1 - (2 * t - 1) ** 2)
    z = 0.075 + 0.06 * (1 - (2 * t - 1) ** 2)
    neck.append(sph((x, y, z), 0.013, GOLD, metallic=0.7, rough=0.3))
    neck.append(sph((x * 1.2, y - 0.05 - 0.04 * (1 - (2 * t - 1) ** 2), z + 0.02), 0.011, GOLD, metallic=0.7, rough=0.3))
neck.append(box((0.0, 1.43, 0.165), (0.05, 0.055, 0.02), (0, 0, 0), GOLD, metallic=0.7, rough=0.3))
items["oni_necklace"] = item("spine01", neck)
# ---- スカジャンの袖（白っぽい袖、赤白のリブ） ----
items["oni_sleeve_up_L"] = item("upperarm01.L", [rod((0.205, 1.6, 0.012), (0.42, 1.35, 0.018), 0.066, 0.058, SLEEVE)])
items["oni_sleeve_up_R"] = item("upperarm01.R", [mirror(rod((0.205, 1.6, 0.012), (0.42, 1.35, 0.018), 0.066, 0.058, SLEEVE))])
items["oni_sleeve_lo_L"] = item("lowerarm01.L", [
    rod((0.41, 1.36, 0.018), (0.53, 1.25, 0.17), 0.056, 0.048, SLEEVE),
    rod((0.52, 1.26, 0.155), (0.545, 1.24, 0.19), 0.052, 0.052, RIB_RED),
])
items["oni_sleeve_lo_R"] = item("lowerarm01.R", [mirror(p) for p in items["oni_sleeve_lo_L"]["parts"]])
items["oni_shoulder"] = item("spine01", both([
    sph((0.17, 1.6, 0.0), 0.072, SLEEVE, squash=(1.0, 0.8, 1.0)),
]) + [
    rod((0.0, 1.66, -0.07), (0.0, 1.66, 0.04), 0.13, 0.13, RIB_RED, squash=(1.05, 0.6)),
])
# ---- 腰：黒いベルトと銀の鋲、腰の鎖 ----
belt = [rod((0, 1.0, 0.0), (0, 1.06, 0.0), 0.185, 0.185, BELT, squash=(1.0, 0.75))]
for i in range(7):
    a = -0.9 + 0.3 * i
    belt.append(sph((0.185 * math.sin(a), 1.03, 0.14 * math.cos(a) + 0.005), 0.014, STUD, metallic=0.6, rough=0.3))
for i in range(7):
    t = i / 6.0
    belt.append(sph((0.12 + 0.07 * t, 0.98 - 0.12 * math.sin(t * math.pi), 0.13 - 0.02 * t), 0.012, STUD, metallic=0.6, rough=0.3))
items["oni_belt"] = item("spine05", belt)
# ---- 平常時：とげバット（右手。剣と同じ持ち方：骨の空間で +Y が先） ----
bat = [
    {"shape": "cylinder", "size": [0.026, 0.26, 0.026], "offset": [0, -0.02, 0], "rotation_deg": [0, 0, 0], "color": GRIP, "metallic": 0.0, "roughness": 0.9},
    {"shape": "cylinder", "size": [0.04, 0.04, 0.04], "offset": [0, 0.12, 0], "rotation_deg": [0, 0, 0], "color": GOLD, "metallic": 0.7, "roughness": 0.3},
    {"shape": "cylinder", "size": [0.042, 0.3, 0.042], "offset": [0, 0.28, 0], "rotation_deg": [0, 0, 0], "color": BAT, "metallic": 0.6, "roughness": 0.35},
    {"shape": "cylinder", "size": [0.058, 0.34, 0.058], "offset": [0, 0.58, 0], "rotation_deg": [0, 0, 0], "color": BAT, "metallic": 0.6, "roughness": 0.35},
    {"shape": "sphere", "size": [0.058, 0, 0], "offset": [0, 0.75, 0], "rotation_deg": [0, 0, 0], "color": BAT, "metallic": 0.6, "roughness": 0.35},
]
for i in range(6):
    y = 0.47 + 0.05 * i
    for k in range(4):
        a = k * 90.0 + (45.0 if i % 2 else 0.0)
        r = math.radians(a)
        bat.append({"shape": "box", "size": [0.016, 0.07, 0.016], "offset": [0.07 * math.cos(r), y, 0.07 * math.sin(r)], "rotation_deg": [90, 0, 0] if k % 2 else [0, 0, 90], "color": SPIKE, "metallic": 0.5, "roughness": 0.4})
items["oni_bat"] = {"bone": "wrist.R", "parts": bat, "offset": [0.0, 0.08, 0.0], "aim": [0.4, 0.235, 0.874]}
# ---- 覚醒：「酔」のはちまき、左手に一升瓶 ----
items["oni_band"] = item("head", [
    rod((0, 1.885, 0.0), (0, 1.925, 0.0), 0.122, 0.122, LABEL, squash=(1.0, 1.08)),
    box((0, 1.905, 0.132), (0.055, 0.04, 0.01), (0, 0, 0), RIB_RED),
    rod((0.0, 1.905, -0.125), (0.05, 1.85, -0.22), 0.018, 0.012, LABEL),
    rod((0.0, 1.905, -0.125), (-0.04, 1.84, -0.21), 0.018, 0.012, LABEL),
])
items["oni_bottle"] = {"bone": "wrist.L", "parts": [
    {"shape": "cylinder", "size": [0.055, 0.26, 0.055], "offset": [0, 0.1, 0], "rotation_deg": [0, 0, 0], "color": BOTTLE, "metallic": 0.1, "roughness": 0.3},
    {"shape": "cylinder", "size": [0.058, 0.09, 0.058], "offset": [0, 0.1, 0], "rotation_deg": [0, 0, 0], "color": LABEL, "metallic": 0.0, "roughness": 0.8},
    {"shape": "cylinder", "size": [0.022, 0.12, 0.022], "offset": [0, 0.28, 0], "rotation_deg": [0, 0, 0], "color": BOTTLE, "metallic": 0.1, "roughness": 0.3},
], "offset": [0.0, 0.06, 0.03], "aim": [0.0, -0.3, 1.0]}

GROUPS = {
    "common": ["oni_horns", "oni_hair", "oni_fangs", "oni_necklace", "oni_sleeve_up_L", "oni_sleeve_up_R", "oni_sleeve_lo_L", "oni_sleeve_lo_R", "oni_shoulder", "oni_belt"],
    "normal": ["oni_bat"],
    "awake": ["oni_band", "oni_bottle"],
}

path = Path(__file__).resolve().parent.parent / "data" / "attachments.json"
data = json.loads(path.read_text(encoding="utf-8"))
for k in [k for k in data["items"] if k.startswith("oni_")]:
    del data["items"][k]
data["items"].update(items)
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("oni items:", len(items), "groups:", json.dumps(GROUPS, ensure_ascii=False))
