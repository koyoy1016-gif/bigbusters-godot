#!/usr/bin/env python3
"""8人の味方キャラの見た目（data/character_looks.json）を作る。キャラごとの関数が、参考画像を見て書いた形を返す。
座標は「モデル座標」（体の前が +Z、上が +Y、キャラの左が +X）。骨の静止の姿勢（Aポーズ）の上で書く。
体の高さは約1.97。主な骨の位置：頭 y1.80、首 y1.69、胸 spine01 y1.47、腰 spine05 y1.08、股 y1.07、ひざ y0.54、足首 y0.08。
肩 x±0.22 y1.58、ひじ x±0.42 y1.35、手首 x±0.56 y1.21 z0.23（Aポーズで手は少し前）。
使い方: python3 tools/make_looks.py   （data/character_looks.json を書き直し、data/characters.json の look を設定する）
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Aポーズの骨の位置（tools/measure_look.gd と、骨の静止の姿勢から）
WRIST_L = (0.563, 1.213, 0.227)
ELBOW_L = (0.416, 1.354, 0.017)
SHOULDER_L = (0.219, 1.581, 0.013)
HEAD = (0.0, 1.799, 0.048)


def add(a, b, k=1.0):
    return [a[i] + b[i] * k for i in range(3)]


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def norm(a):
    l = math.sqrt(sum(x * x for x in a)) or 1.0
    return [x / l for x in a]


FOREARM_DIR = norm(sub(WRIST_L, ELBOW_L))
UPPERARM_DIR = norm(sub(ELBOW_L, SHOULDER_L))


def mat(color, metallic=0.0, rough=0.8, emission=0.0, tex=""):
    d = {"color": color, "metallic": metallic, "roughness": rough}
    if emission:
        d["emission"] = emission
    if tex:
        d["tex"] = tex
    return d


def rod(bone, a, b, r0, r1, color, mirror=False, **kw):
    d = {"bone": bone, "shape": "rod", "from": list(a), "to": list(b), "r0": r0, "r1": r1}
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def sph(bone, c, r, color, squash=(1, 1, 1), mirror=False, segs=12, rot=(0, 0, 0), **kw):
    d = {"bone": bone, "shape": "sphere", "center": list(c), "r": r, "squash": list(squash), "segs": segs, "rotation_deg": list(rot)}
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def box(bone, c, size, color, rot=(0, 0, 0), mirror=False, **kw):
    d = {"bone": bone, "shape": "box", "center": list(c), "size": list(size), "rotation_deg": list(rot)}
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def loft(bone, rings, color, side=(1, 0, 0), segs=14, mirror=False, caps=True, arc=None, double=False, **kw):
    d = {"bone": bone, "shape": "loft", "rings": [[list(c), w, dd] for c, w, dd in rings], "side": list(side), "segs": segs, "caps": caps}
    if arc:
        d["arc_from"], d["arc_to"] = arc
    if double:
        d["double"] = True
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def tube(bone, pts, r0, r1, color, smooth=False, steps=6, squash=1.0, segs=8, mirror=False, **kw):
    d = {"bone": bone, "shape": "tube", "points": [list(p) for p in pts], "r0": r0, "r1": r1, "segs": segs, "squash": squash}
    if smooth:
        d["smooth"] = True
        d["steps"] = steps
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def torus(bone, c, R, r, color, rot=(0, 0, 0), squash=(1, 1, 1), segs=16, mirror=False, **kw):
    d = {"bone": bone, "shape": "torus", "center": list(c), "R": R, "r": r, "rotation_deg": list(rot), "squash": list(squash), "segs": segs}
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def extrude(bone, c, pts2d, depth, color, rot=(0, 0, 0), squash=(1, 1, 1), mirror=False, double=False, **kw):
    d = {"bone": bone, "shape": "extrude", "center": list(c), "points2d": [list(p) for p in pts2d], "depth": depth,
         "rotation_deg": list(rot), "squash": list(squash)}
    if double:
        d["double"] = True
    d.update(mat(color, **kw))
    if mirror:
        d["mirror"] = True
    return d


def region(color=None, **kw):
    d = dict(kw)
    if color:
        d["color"] = color
    return d


def circle2d(r, n=16, sx=1.0, sy=1.0):
    return [[r * sx * math.cos(2 * math.pi * i / n), r * sy * math.sin(2 * math.pi * i / n)] for i in range(n)]


def heart2d(s, n=24):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append([x * s / 16.0, y * s / 16.0])
    return pts


def ring_on_head(cy, rx, rz, cz=0.03):
    """頭のまわりの輪（loft を2つの輪で作る、帯）"""
    return [((0, cy - 0.018, cz), rx, rz), ((0, cy + 0.018, cz), rx, rz)]


# ============================================================== ファイター（こぶし）
def brawler():
    RED = "#a3161d"
    DARK_RED = "#6e1016"
    GOLD = "#d4a838"
    WRAP = "#d9c7a0"
    parts = []
    # はちまき（赤）と、後ろへなびく2本の帯
    parts.append(loft("head", ring_on_head(1.905, 0.098, 0.112, 0.035), RED, segs=18, caps=False, double=True))
    for side in (1, -1):
        parts.append(tube("head", [(0.035 * side, 1.905, -0.075), (0.12 * side, 1.88, -0.17), (0.22 * side, 1.62, -0.17)], 0.017, 0.007, RED,
                          smooth=True, squash=0.35))
        parts.append(tube("head", [(0.025 * side, 1.90, -0.08), (0.08 * side, 1.83, -0.18), (0.14 * side, 1.58, -0.17)], 0.015, 0.006, RED,
                          smooth=True, squash=0.35))
    # ボクシンググローブ（手の重ね着の上に、丸い拳）
    g = add(WRIST_L, FOREARM_DIR, 0.085)
    parts.append(sph("wrist.L", g, 0.082, DARK_RED, squash=(1.0, 1.05, 1.15), mirror=True, rough=0.45, tex="leather"))
    parts.append(rod("wrist.L", add(WRIST_L, FOREARM_DIR, -0.075), add(WRIST_L, FOREARM_DIR, 0.01), 0.056, 0.06, "#e8e4da",
                     mirror=True, rough=0.7))
    # ベルト：金の大きな飾り（前）と、横の丸い飾り
    parts.append(extrude("spine05", (0, 1.095, 0.205), circle2d(0.085, 24, 1.25, 1.0), 0.03, GOLD, metallic=0.85, rough=0.3))
    parts.append(extrude("spine05", (0, 1.095, 0.222), circle2d(0.05, 20), 0.012, "#8a1a1a", rough=0.5))
    parts.append(sph("spine05", (0, 1.095, 0.228), 0.026, GOLD, metallic=0.85, rough=0.3))
    for ang in (35, 70):
        a = math.radians(ang)
        parts.append(extrude("spine05", (0.19 * math.sin(a), 1.095, 0.19 * math.cos(a) - 0.0), circle2d(0.032, 16), 0.016, GOLD,
                             rot=(0, ang, 0), metallic=0.85, rough=0.3, mirror=True))
    return {
        "name": "ファイター",
        "attack_anim": "Punch",
        "ref": "docs/ref/chars/IMG_0392.jpeg",
        "keep": ["eyebrow001", "eyelashes01", "low-poly", "short04"],
        "skin": "#d99a6c",
        "tint_short04": "#2a2420",
        "head_scale": 0.97,
        "bulk": {"neck": 1.45, "chest": [1.42, 1.32], "belly": [1.22, 1.18], "hips": [1.18, 1.12],
                 "upperarm": 1.6, "forearm": 1.5, "thigh": 1.45, "shin": 1.38},
        "paint": [
            # ひげ（あご・ほお）
            region("#9a6a4c", groups=["head"], y=[1.705, 1.755], nz=[-0.2, 1.0], z=[0.02, 0.3], rough=0.95, mesh=["body"]),
        ],
        "hide": [
            # Tシャツの袖（腕は、もとの体の腕を使う）
            region(groups=["forearm", "hand"], mesh=["suit"]),
        ],
        "shells": [
            # 赤いトランクス（金のふち）
            region(RED, groups=["hips", "thigh", "belly"], y=[0.74, 1.06], offset=0.012, puff={"thigh": 1.12, "hips": [1.03, 1.03]},
                   hide_under=True, rough=0.35, tex="none"),
            # ベルト
            region(RED, groups=["hips", "belly"], y=[1.04, 1.16], offset=0.03, puff={"hips": [1.05, 1.05], "belly": [1.05, 1.05]},
                   hide_under=True, rough=0.5, tex="leather"),
            # 手（グローブの中身）
            region(DARK_RED, groups=["hand"], offset=0.012, puff={"hand": 1.6}, hide_under=True, rough=0.45, tex="leather"),
            # 足首の巻き布（素足）
            region(groups=["foot", "shin"], y=[0.07, 0.25], offset=0.008, puff={"shin": 1.06, "foot": 1.05}, hide_under=False,
                   stripes={"axis": "y", "period": 0.022, "colors": [WRAP, "#c4b088"]}, rough=0.95),
        ],
        "parts": parts,
    }


# ============================================================== スピードファイター（はやて）
def sprinter():
    NAVY = "#1c2541"
    DEEP = "#121a30"
    BLUE = "#2b4c9a"
    CYAN = "#3fd0ff"
    YEL = "#e8c547"
    HAIR = "#1d2c6e"
    parts = []
    # 目をおおう光るゴーグル（顔の前の弧）と、横の丸い留め具
    parts.append(loft("head", [((0, 1.835, 0.03), 0.098, 0.118), ((0, 1.875, 0.03), 0.1, 0.12)], CYAN, segs=20, arc=(15, 165),
                      caps=False, double=True, emission=1.6, rough=0.2, tex="none"))
    parts.append(sph("head", (0.097, 1.855, 0.03), 0.026, DEEP, squash=(0.6, 1, 1), mirror=True, metallic=0.6, rough=0.4))
    # とがった髪（後ろ上へはねる）
    spikes = [((0.0, 1.95, 0.06), (0.0, 2.09, 0.0)), ((0.05, 1.94, 0.04), (0.13, 2.06, -0.03)), ((-0.05, 1.94, 0.04), (-0.13, 2.06, -0.03)),
              ((0.0, 1.95, -0.02), (0.02, 2.08, -0.16)), ((0.06, 1.92, -0.04), (0.16, 1.99, -0.15)), ((-0.06, 1.92, -0.04), (-0.16, 1.99, -0.15)),
              ((0.0, 1.9, -0.07), (0.0, 1.95, -0.24)), ((0.08, 1.9, 0.0), (0.18, 1.96, 0.04)), ((-0.08, 1.9, 0.0), (-0.18, 1.96, 0.04)),
              ((0.03, 1.96, 0.09), (0.06, 2.05, 0.15)), ((-0.03, 1.96, 0.09), (-0.07, 2.04, 0.14))]
    for a, b in spikes:
        mid = [(a[i] + b[i]) / 2 + (0.02 if i == 1 else 0) for i in range(3)]
        parts.append(tube("head", [a, mid, b], 0.045, 0.004, HAIR, smooth=True, steps=4, segs=7, rough=0.6))
    parts.append(sph("head", (0, 1.9, 0.0), 0.105, HAIR, squash=(1.0, 0.8, 1.15), rough=0.6))
    # マフラー（首の輪と、後ろへなびく2本）
    parts.append(loft("neck01", [((0, 1.66, 0.0), 0.085, 0.085), ((0, 1.71, 0.01), 0.078, 0.08), ((0, 1.75, 0.015), 0.07, 0.074)], BLUE, segs=16))
    parts.append(torus("neck01", (0, 1.70, 0.008), 0.083, 0.006, YEL, rot=(0, 0, 0), segs=16))
    for k, (dx, dy) in enumerate([(0.0, 0.0), (0.06, -0.05)]):
        pts = [(0.03, 1.70, -0.07), (0.25 + dx, 1.70 + dy, -0.2), (0.55 + dx, 1.64 + dy, -0.22)]
        parts.append(tube("neck01", pts, 0.035, 0.03, BLUE, smooth=True, steps=8, squash=0.18, segs=8))
        parts.append(tube("neck01", [(p[0], p[1] + 0.012, p[2]) for p in pts], 0.012, 0.01, YEL, smooth=True, steps=8, squash=0.2, segs=6))
    # 肩あて（光る印つき）
    sh = add(SHOULDER_L, UPPERARM_DIR, 0.05)
    parts.append(sph("upperarm01.L", add(sh, [0.02, 0.02, 0], 1), 0.07, DEEP, squash=(1.0, 0.75, 1.0), mirror=True, metallic=0.4, rough=0.4))
    parts.append(extrude("upperarm01.L", add(sh, [0.06, 0.03, 0.0], 1), [[0, 0.03], [0.025, 0.01], [0.018, -0.03], [-0.018, -0.03], [-0.025, 0.01]],
                         0.006, CYAN, rot=(0, 90, 0), mirror=True, emission=1.5, tex="none"))
    # 前腕のひれ（外側に2枚）
    for k in (0.25, 0.6):
        c = add(ELBOW_L, FOREARM_DIR, 0.22 * k + 0.02)
        parts.append(extrude("lowerarm01.L", add(c, [0.04, 0.02, -0.02], 1), [[0, 0], [0.06, -0.01], [0, -0.03]], 0.008, DEEP,
                             rot=(0, -60, -40), mirror=True, metallic=0.5, rough=0.35))
    # 手首の輪
    parts.append(rod("wrist.L", add(WRIST_L, FOREARM_DIR, -0.06), add(WRIST_L, FOREARM_DIR, -0.02), 0.04, 0.041, DEEP, mirror=True, metallic=0.5))
    # 大きなくつ：ベルト2本、かかとの光
    for z, y in ((0.06, 0.1), (0.12, 0.075)):
        parts.append(box("foot.L", (0.205, y, z), (0.13, 0.03, 0.06), DEEP, rot=(-25, 0, 0), mirror=True, rough=0.6))
    parts.append(sph("foot.L", (0.205, 0.07, -0.085), 0.028, CYAN, squash=(1.2, 0.8, 0.6), mirror=True, emission=1.8, tex="none"))
    return {
        "name": "スピードファイター",
        "ref": "docs/ref/chars/IMG_0395.jpeg",
        "attack_anim": "Punch",
        "run_anim": "Sprint",
        "height": 1.03,
        "keep": [],
        "skin": "#d9b08c",
        "head_scale": 0.95,
        "bulk": {"neck": 0.95, "chest": [0.95, 0.92], "belly": [0.88, 0.88], "hips": [0.95, 0.95],
                 "upperarm": 0.9, "forearm": 0.92, "thigh": 0.9, "shin": 0.88},
        "paint": [
            region(NAVY, rough=0.55),
            # 口・鼻をおおうマスク（少し暗い）
            region(DEEP, groups=["head"], y=[1.68, 1.84], z=[0.04, 0.3], rough=0.5),
            # 光る線：脚の外側・前腕の外側・胸の2本・腰の黄色
            region(CYAN, groups=["thigh", "shin"], rx_out=[0.93, 1.0], y=[0.2, 1.0], emission=1.4, tex="none"),
            region(CYAN, groups=["forearm", "upperarm"], ny=[0.55, 1.0], emission=1.4, tex="none"),
            region(CYAN, groups=["chest", "belly"], x_abs=[0.085, 0.105], nz=[0.3, 1.0], y=[1.2, 1.55], emission=1.4, tex="none"),
            region(YEL, groups=["hips", "belly"], x_abs=[0.12, 0.15], nz=[0.2, 1.0], y=[1.0, 1.14], emission=0.6, tex="none"),
        ],
        "shells": [
            # ぶ厚いスニーカー（底は灰色）
            region(groups=["foot"], mesh=["shoes"], offset=0.012, puff={"foot": [1.35, 1.2]}, hide_under=True,
                   stripes={"axis": "y", "period": 0.035, "offset": 0.0, "colors": ["#555b66", DEEP, DEEP, DEEP, DEEP, DEEP, DEEP, DEEP]}, rough=0.6),
        ],
        "parts": parts,
    }


# ============================================================== ガンナー（じゅうし）
def gunner():
    BLACK = "#1b1d20"
    OLIVE = "#4b5338"
    OLIVE_D = "#353b29"
    GUN = "#3a3f33"
    RED = "#e0352b"
    parts = []
    # ヘルメット（顔まで黒）と、黒い目の板、あごの守り
    parts.append(sph("head", (0, 1.86, 0.025), 0.122, "#26292b", squash=(1.0, 1.0, 1.1), segs=16, metallic=0.3, rough=0.45))
    parts.append(loft("head", [((0, 1.80, 0.04), 0.103, 0.125), ((0, 1.86, 0.045), 0.112, 0.13)], "#0e0f11", segs=18, arc=(20, 160),
                      caps=False, double=True, metallic=0.5, rough=0.15))
    parts.append(loft("head", [((0, 1.73, 0.03), 0.085, 0.1), ((0, 1.79, 0.04), 0.1, 0.12)], "#26292b", segs=16, arc=(10, 170),
                      caps=False, double=True, metallic=0.3, rough=0.45))
    parts.append(sph("head", (0.115, 1.85, 0.02), 0.03, "#1a1c1e", squash=(0.5, 1, 1), mirror=True, metallic=0.4))
    # ヘルメットの後ろの、はちまきの帯（黒）
    for dy, dz in ((0.0, 0.0), (-0.03, 0.02)):
        parts.append(tube("head", [(0.02, 1.86 + dy, -0.11), (0.16, 1.88 + dy, -0.2 + dz), (0.34, 1.86 + dy, -0.22 + dz)], 0.016, 0.006,
                          "#141516", smooth=True, squash=0.3))
    # 腕の大砲（手首について動く）：本体・砲口・赤い光・持ち手の箱
    back = add(WRIST_L, FOREARM_DIR, -0.17)
    front = add(WRIST_L, FOREARM_DIR, 0.32)
    off = [0.0, -0.02, 0.0]
    parts.append(rod("wrist.L", add(back, off), add(front, off), 0.072, 0.075, GUN, mirror=True, segs=14, metallic=0.5, rough=0.5, tex="steel"))
    parts.append(rod("wrist.L", add(front, off), add(add(front, off), FOREARM_DIR, 0.05), 0.085, 0.085, "#2a2c2a", mirror=True, segs=14,
                     metallic=0.6, rough=0.4))
    parts.append(rod("wrist.L", add(add(front, off), FOREARM_DIR, 0.05), add(add(front, off), FOREARM_DIR, 0.055), 0.07, 0.07, "#0c0c0c",
                     mirror=True, segs=14))
    for k in (0.0, 0.1, 0.2):
        c = add(add(WRIST_L, FOREARM_DIR, k), [0.0, 0.055, 0.0])
        parts.append(box("wrist.L", c, (0.035, 0.025, 0.06), RED, rot=(35, 40, 0), mirror=True, emission=1.4, tex="none"))
    parts.append(box("wrist.L", add(add(WRIST_L, FOREARM_DIR, -0.08), [0.0, 0.07, 0.0]), (0.09, 0.05, 0.16), OLIVE_D, rot=(35, 40, 0),
                     mirror=True, metallic=0.4, tex="steel"))
    # 腕に沿う管（上腕の外側）
    for dz in (-0.02, 0.02):
        a = add(SHOULDER_L, UPPERARM_DIR, 0.05)
        b = add(ELBOW_L, [0, 0, 0], 1)
        parts.append(tube("upperarm01.L", [add(a, [0.05, 0.03, dz]), add([(a[i] + b[i]) / 2 for i in range(3)], [0.07, 0.0, dz]),
                                          add(b, [0.055, -0.01, dz])], 0.008, 0.008, "#2b2b2b", smooth=True, mirror=True))
    # 背中の箱と、肩ひも
    parts.append(box("spine01", (0, 1.43, -0.17), (0.26, 0.3, 0.09), OLIVE_D, metallic=0.3, tex="steel"))
    # 股の守り・ひざ当て・すね当て・ももの板
    parts.append(extrude("spine05", (0, 0.98, 0.15), [[-0.08, 0.06], [0.08, 0.06], [0.05, -0.08], [-0.05, -0.08]], 0.03, OLIVE,
                         rot=(-8, 0, 0), metallic=0.3, tex="steel"))
    parts.append(sph("lowerleg01.L", (0.165, 0.55, 0.1), 0.07, OLIVE_D, squash=(1, 1.1, 0.7), mirror=True, metallic=0.3, tex="steel"))
    parts.append(box("lowerleg01.L", (0.18, 0.33, 0.085), (0.12, 0.26, 0.04), OLIVE, rot=(-4, 0, 3), mirror=True, metallic=0.3, tex="steel"))
    parts.append(box("upperleg01.L", (0.145, 0.82, 0.11), (0.13, 0.22, 0.04), OLIVE, rot=(-6, 0, 4), mirror=True, metallic=0.3, tex="steel"))
    parts.append(box("upperleg01.L", (0.235, 0.86, 0.0), (0.04, 0.2, 0.13), OLIVE, rot=(0, 0, 4), mirror=True, metallic=0.3, tex="steel"))
    return {
        "name": "ガンナー",
        "ref": "docs/ref/chars/IMG_0397.jpeg",
        "attack_anim": "Spell",
        "height": 1.0,
        "keep": [],
        "skin": "#c98e6c",
        "head_scale": 1.0,
        "bulk": {"neck": 1.15, "chest": [1.1, 1.05], "belly": [1.0, 1.0], "hips": [1.05, 1.05],
                 "upperarm": 1.3, "forearm": 1.25, "thigh": 1.22, "shin": 1.18},
        "paint": [
            region(BLACK, rough=0.5),
            region("skin", groups=["upperarm", "forearm", "hand"], mesh=["body"]),
            # 黒い服の、胸と腹の筋（少し明るい線）
            region("#2c2f34", groups=["chest", "belly"], x_abs=[0.0, 0.012], nz=[0.4, 1.0], y=[1.15, 1.45]),
            region("#2c2f34", groups=["belly"], y=[1.27, 1.29], nz=[0.4, 1.0]),
            region("#2c2f34", groups=["belly"], y=[1.19, 1.21], nz=[0.4, 1.0]),
        ],
        "hide": [region(groups=["upperarm", "forearm", "hand"], mesh=["suit"])],
        "shells": [
            # 緑のズボン（ゆったり）と、ぶ厚いくつ
            region(OLIVE, groups=["hips", "thigh", "shin"], y=[0.1, 1.06], mesh=["suit"], offset=0.01, puff={"thigh": 1.1, "shin": 1.12},
                   hide_under=True, rough=0.75),
            region(OLIVE_D, groups=["foot"], mesh=["shoes"], offset=0.012, puff={"foot": [1.3, 1.2]}, hide_under=True, rough=0.6),
        ],
        "parts": parts,
    }


LOOKS = {
    "brawler": brawler,
    "sprinter": sprinter,
    "gunner": gunner,
}


def clean(d):
    if isinstance(d, dict):
        return {k: clean(v) for k, v in d.items() if v is not None and k != "not_"}
    if isinstance(d, list):
        return [clean(x) for x in d]
    if isinstance(d, float):
        return round(d, 4)
    return d


def main():
    looks = {k: clean(f()) for k, f in LOOKS.items()}
    out = {"_memo": "味方キャラの見た目（tools/make_looks.py が作る。手で書きかえない）。scripts/characters/body_builder.gd が使う。"
                    "土台は剣士と同じ体（MakeHuman CC0）と骨。参考画像は docs/ref/chars/。",
           "looks": looks}
    (ROOT / "data/character_looks.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    chars = json.loads((ROOT / "data/characters.json").read_text(encoding="utf-8"))
    for c in chars["characters"]:
        if c["id"] in looks:
            lk = looks[c["id"]]
            c["look"] = c["id"]
            # 土台は剣士と同じ体・骨・動き（hero_ual.res）。攻撃の動きだけ、キャラに合わせる
            c["model"] = "res://assets/models/hero_swordsman.glb"
            c["model_scale"] = round(1.95 * float(lk.get("height", 1.0)), 4)
            c["anim_library"] = "res://assets/anims/hero_ual.res"
            c["procedural_anims"] = True
            atk = lk.get("attack_anim", "Punch")
            c["animations"] = {"idle": "Idle", "run": lk.get("run_anim", "Run"), "jump": "Jump", "attack": atk, "down": "Death",
                               "swing": atk, "jump_start": "Jump_Start", "land": "Jump_Land", "roll": "Roll", "charge": "Spell", "hit": "Hit"}
            c["anim_oneshot"] = ["attack"]
    (ROOT / "data/characters.json").write_text(json.dumps(chars, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("looks", list(looks))


if __name__ == "__main__":
    main()
