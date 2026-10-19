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


def rod(bone, a, b, r0, r1, color, mirror=False, segs=12, squash=(1, 1), **kw):
    d = {"bone": bone, "shape": "rod", "from": list(a), "to": list(b), "r0": r0, "r1": r1, "segs": segs, "squash": list(squash)}
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
        "idle_speed": 1.1,
        "attack_speed": 2.0,
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
        "idle_speed": 1.25,
        "attack_speed": 2.2,
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
    parts.append(box("spine01", (0, 1.45, -0.15), (0.2, 0.22, 0.06), OLIVE_D, metallic=0.3, tex="steel"))
    # 首の黒い襟（服と首のすき間をふさぐ）
    parts.append(loft("neck01", [((0, 1.63, 0.0), 0.085, 0.09), ((0, 1.7, 0.015), 0.07, 0.072)], BLACK, segs=16, caps=False))
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
            region("skin", groups=["upperarm", "forearm", "hand"]),
            # 黒い服の、胸と腹の筋（少し明るい線）
            region("#2c2f34", groups=["chest", "belly"], x_abs=[0.0, 0.012], nz=[0.4, 1.0], y=[1.15, 1.45]),
            region("#2c2f34", groups=["belly"], y=[1.27, 1.29], nz=[0.4, 1.0]),
            region("#2c2f34", groups=["belly"], y=[1.19, 1.21], nz=[0.4, 1.0]),
        ],
        "hide": [region(groups=["forearm", "hand"], mesh=["suit"])],
        "shells": [
            # 緑のズボン（ゆったり）と、ぶ厚いくつ
            region(OLIVE, groups=["hips", "thigh", "shin"], y=[0.1, 1.06], mesh=["suit"], offset=0.01, puff={"thigh": 1.1, "shin": 1.12},
                   hide_under=True, rough=0.75),
            region(OLIVE_D, groups=["foot"], mesh=["shoes"], offset=0.012, puff={"foot": [1.3, 1.2]}, hide_under=True, rough=0.6),
        ],
        "parts": parts,
    }


# ============================================================== ボンバー（ばくだん）
def bomber():
    RED = "#c8302b"
    YEL = "#e8b62c"
    GRN = "#3d8a3f"
    BLU = "#2f5cab"
    PUR = "#6a3c9a"
    WHITE = "#f2efe6"
    BROWN = "#6b4a2b"
    GOLD = "#d9a83a"
    parts = []
    # 道化の帽子：頭の帽子と、3本の垂れた角（緑・紫・黄）と先の鈴
    parts.append(sph("head", (0, 1.9, 0.02), 0.118, GRN, squash=(1.05, 0.75, 1.05), segs=16, rough=0.7))
    parts.append(loft("head", [((0, 1.865, 0.03), 0.118, 0.122), ((0, 1.895, 0.03), 0.12, 0.124)], GOLD, segs=18, caps=False, double=True,
                      metallic=0.6, rough=0.4))
    horns = [((0.07, 1.95, 0.0), (0.2, 2.06, 0.02), (0.27, 1.95, 0.05), PUR),
             ((-0.07, 1.95, 0.0), (-0.2, 2.06, 0.02), (-0.27, 1.95, 0.05), YEL),
             ((0.0, 1.97, -0.04), (0.02, 2.1, -0.16), (0.05, 1.98, -0.27), RED)]
    for a, c, b, col in horns:
        parts.append(tube("head", [a, c, b], 0.07, 0.014, col, smooth=True, steps=8, segs=10, rough=0.7))
        parts.append(sph("head", b, 0.028, GOLD, metallic=0.8, rough=0.3))
    # もじゃもじゃの髪（帽子の下の横から、赤・緑・青）
    for side in (1, -1):
        for k, col in enumerate([RED, GRN, BLU, RED]):
            y = 1.88 - 0.03 * k
            parts.append(tube("head", [(0.09 * side, y, -0.01), (0.15 * side, y + 0.01, -0.03 - 0.01 * k), (0.19 * side, y - 0.03, -0.05)],
                              0.03, 0.008, col, smooth=True, steps=4, segs=7))
    # 赤い鼻
    parts.append(sph("head", (0, 1.825, 0.15), 0.024, "#e02020", rough=0.3))
    # 大きなひだの襟（白、波うつ）
    rings = []
    for i in range(3):
        y = 1.655 - i * 0.012
        rings.append(((0, y, 0.02), 0.13 + i * 0.045, 0.12 + i * 0.04))
    parts.append(loft("spine01", rings, WHITE, segs=24, caps=False, double=True, rough=0.85))
    for i in range(12):
        a = 2 * math.pi * i / 12
        parts.append(sph("spine01", (0.19 * math.sin(a), 1.635, 0.02 + 0.175 * math.cos(a)), 0.045, WHITE, squash=(1, 0.45, 1), segs=8))
    # 胸のボタン
    for k in range(4):
        parts.append(sph("spine01", (0.0, 1.55 - k * 0.09, 0.17 - k * 0.004), 0.016, GOLD, metallic=0.7, rough=0.3))
    # 斜めのたすきと、腰の袋2つ・大きな袋
    parts.append(rod("spine01", (0.17, 1.58, 0.12), (-0.18, 1.08, 0.16), 0.022, 0.022, BROWN, squash=(1, 0.4), segs=6))
    for x in (0.13, -0.15):
        parts.append(box("spine05", (x, 1.02, 0.17), (0.09, 0.09, 0.05), BROWN, rot=(0, 25 * (1 if x > 0 else -1), 0), tex="leather"))
    parts.append(sph("spine05", (-0.22, 0.92, 0.0), 0.12, "#7a5a36", squash=(0.8, 1.0, 0.9), rough=0.9, tex="cloth"))
    # 手にもつプレゼントの爆弾（左手：ピンク、右手：緑）と、火花の導火線
    for side, col, rib in ((1, "#c04a8c", "#e8c547"), (-1, GRN, "#c8302b")):
        w = [WRIST_L[0] * side, WRIST_L[1], WRIST_L[2]]
        fd = [FOREARM_DIR[0] * side, FOREARM_DIR[1], FOREARM_DIR[2]]
        c = add(add(w, fd, 0.12), [0, 0.08, 0])
        bone = "wrist.L" if side > 0 else "wrist.R"
        parts.append(box(bone, c, (0.17, 0.15, 0.17), col, rot=(0, 20 * side, 0), rough=0.6))
        parts.append(box(bone, c, (0.175, 0.155, 0.035), rib, rot=(0, 20 * side, 0), rough=0.5))
        parts.append(box(bone, c, (0.035, 0.155, 0.175), rib, rot=(0, 20 * side, 0), rough=0.5))
        parts.append(tube(bone, [add(c, [0, 0.055, 0]), add(c, [0.02 * side, 0.1, 0.0]), add(c, [0.04 * side, 0.13, 0.02])], 0.007, 0.005,
                          "#3a2a1a", smooth=True, steps=4, segs=5))
        parts.append(sph(bone, add(c, [0.04 * side, 0.14, 0.02]), 0.025, "#ffd65a", segs=8, emission=2.5, tex="none"))
    # 左右ちがいのくつ（赤と青）のつま先
    parts.append(sph("foot.L", (0.215, 0.05, 0.16), 0.07, RED, squash=(1, 0.65, 1.3), rough=0.5))
    parts.append(sph("foot.R", (-0.215, 0.05, 0.16), 0.07, BLU, squash=(1, 0.65, 1.3), rough=0.5))
    return {
        "name": "ボンバー",
        "ref": "docs/ref/chars/IMG_0398.jpeg",
        "attack_anim": "Punch",
        "height": 0.97,
        "keep": ["eyebrow001", "eyelashes01", "low-poly"],
        "skin": "#f6efe8",
        "head_scale": 1.05,
        "bulk": {"chest": [1.08, 1.12], "belly": [1.1, 1.15], "upperarm": 1.05, "forearm": 1.05},
        "paint": [
            # つぎはぎの上着（ひし形）
            region(groups=["chest", "belly", "hips", "upperarm", "forearm", "neck"], stripes={"axis": "diamond", "period": 0.11,
                   "colors": [RED, GRN, BLU, YEL]}, rough=0.75),
            # 白い手袋
            region(WHITE, groups=["hand"], rough=0.6),
            # 道化の顔：白い顔に、赤い大きな口、目のまわりの青
            region("#f8f6f2", groups=["head"], mesh=["body"], rough=0.6, tex="none"),
            region("#d42a2a", groups=["head"], mesh=["body"], y=[1.73, 1.775], x_abs=[0.0, 0.05], nz=[0.3, 1.0], z=[0.07, 0.3], tex="none"),
            region("#4a72c8", groups=["head"], mesh=["body"], y=[1.84, 1.875], x_abs=[0.02, 0.055], nz=[0.4, 1.0], z=[0.08, 0.3], tex="none"),
            # 茶色のベルト
            region(BROWN, groups=["hips", "belly"], y=[1.05, 1.11], tex="leather"),
        ],
        "hide": [],
        "shells": [
            # ぶかぶかの縦じまズボン（赤と黄）
            region(groups=["hips", "thigh", "shin"], y=[0.12, 1.05], mesh=["suit"], offset=0.02, puff={"thigh": 1.55, "shin": 1.7, "hips": [1.15, 1.2]},
                   hide_under=True, stripes={"axis": "x", "period": 0.06, "colors": [RED, YEL]}, rough=0.7),
            # 足首をしぼる帯
            region(RED, groups=["shin"], y=[0.1, 0.16], mesh=["suit"], offset=0.012, puff={"shin": 1.05}, rough=0.7),
            # くつ（左は赤、右は青）
            region(RED, groups=["foot"], mesh=["shoes"], side="L", offset=0.012, puff={"foot": [1.3, 1.2]}, hide_under=True, rough=0.5),
            region(BLU, groups=["foot"], mesh=["shoes"], side="R", offset=0.012, puff={"foot": [1.3, 1.2]}, hide_under=True, rough=0.5),
        ],
        "parts": parts,
    }


def crescent2d(r, thick, n=20):
    """三日月の形（外の円と、ずらした内の円の差）"""
    outer = [[r * math.cos(math.pi * (0.25 + 1.5 * i / n)), r * math.sin(math.pi * (0.25 + 1.5 * i / n))] for i in range(n + 1)]
    ri = r * 0.8
    inner = [[thick + ri * math.cos(math.pi * (0.25 + 1.5 * (n - i) / n)), ri * math.sin(math.pi * (0.25 + 1.5 * (n - i) / n))] for i in range(n + 1)]
    return outer + inner


def wing2d(s):
    """小さな羽（外へ広がる3枚の羽根）"""
    return [[0, 0], [s * 0.35, s * 0.55], [s * 0.8, s * 0.75], [s * 0.7, s * 0.5], [s * 1.0, s * 0.45], [s * 0.75, s * 0.25],
            [s * 0.95, s * 0.1], [s * 0.5, s * 0.05]]


def staff(bone, x, z, color, top_y=2.0):
    """魔法使いのつえ（下から上まで、手を通る縦の棒）。上に金の三日月・光る玉・白い羽"""
    ps = [rod(bone, (x, 0.0, z), (x, top_y, z), 0.016, 0.018, color, segs=8, rough=0.5)]
    ps.append(rod(bone, (x, 0.0, z), (x, 0.08, z), 0.02, 0.02, "#d9a83a", segs=8, metallic=0.8, rough=0.3))
    for y in (top_y - 0.35, top_y - 0.2):
        ps.append(torus(bone, (x, y, z), 0.022, 0.006, "#d9a83a", segs=10, metallic=0.8, rough=0.3))
    ps.append(extrude(bone, (x, top_y + 0.12, z), crescent2d(0.12, 0.05), 0.02, "#d9a83a", rot=(0, 0, 90), metallic=0.85, rough=0.25))
    ps.append(sph(bone, (x, top_y + 0.11, z), 0.068, "#b9a8ff", segs=14, emission=1.3, rough=0.1, tex="none"))
    for side in (1, -1):
        ps.append(extrude(bone, (x + 0.05 * side, top_y + 0.0, z), [[p[0] * side, p[1]] for p in wing2d(0.16)], 0.01, "#f4f2f8"))
    ps.append(sph(bone, (x - 0.03, top_y - 0.1, z + 0.02), 0.022, "#8a5cc0", squash=(1.4, 0.7, 0.7)))
    ps.append(sph(bone, (x + 0.03, top_y - 0.1, z + 0.02), 0.022, "#8a5cc0", squash=(1.4, 0.7, 0.7)))
    return ps


def long_hair(color, length_y=1.05, width=0.15, depth=0.1, waves=True):
    """背中まで届く長い髪（頭の骨につく）：頭の上の帽子形と、後ろの幕と、横の房"""
    ps = [sph("head", (0, 1.88, 0.0), 0.122, color, squash=(1.05, 0.95, 1.08), segs=16, rough=0.7),
          sph("head", (0, 1.915, 0.035), 0.112, color, squash=(1.05, 0.85, 1.05), segs=16, rough=0.7)]
    rings = []
    n = 6
    for i in range(n + 1):
        t = i / n
        y = 1.9 - (1.9 - length_y) * t
        w = width * (0.85 + 0.45 * t)
        rings.append(((0, y, -0.06 - 0.06 * t), w, depth * (1.0 - 0.3 * t)))
    ps.append(loft("head", rings, color, segs=16, arc=(180, 360), caps=False, double=True, rough=0.7))
    for side in (1, -1):
        for k in range(3):
            x0 = (0.09 + 0.02 * k) * side
            pts = [(x0, 1.86 - 0.03 * k, 0.02 - 0.04 * k), (x0 + 0.06 * side, 1.6, -0.02 - 0.04 * k), (x0 + 0.04 * side, length_y + 0.12, -0.05 - 0.03 * k)]
            ps.append(tube("head", pts, 0.035, 0.012, color, smooth=True, steps=8, segs=8, squash=0.7, rough=0.7))
    # 背中の波うつ房
    for k in range(-2, 3):
        x0 = 0.05 * k
        ps.append(tube("head", [(x0, 1.8, -0.1), (x0 * 1.3 + 0.03, 1.45, -0.17), (x0 * 1.4, length_y + 0.05, -0.14)], 0.04, 0.015, color,
                       smooth=True, steps=8, segs=8, squash=0.6, rough=0.7))
    # 前髪
    for k in range(-3, 4):
        ps.append(tube("head", [(0.03 * k, 1.97, 0.06), (0.032 * k, 1.93, 0.12), (0.03 * k, 1.875, 0.135)], 0.025, 0.006, color,
                       smooth=True, steps=4, segs=6, squash=0.6, rough=0.7))
    return ps


# ============================================================== 魔法使い（まほう）
def mage():
    PUR = "#5d2f91"
    PUR_D = "#3c1d66"
    LAV = "#a98ad6"
    LAV_L = "#cbb6ea"
    GOLD = "#d9a83a"
    HAIR = "#a49cc2"
    parts = long_hair(HAIR, length_y=1.0, width=0.16)
    # とんがり帽子：つば・本体（先が後ろへ折れる）・帯・リボン・三日月
    parts.append(loft("head", [((0, 1.975, 0.02), 0.36, 0.34), ((0, 1.982, 0.02), 0.13, 0.13)], PUR, segs=28, caps=False, double=True))
    parts.append(torus("head", (0, 1.975, 0.02), 0.355, 0.008, GOLD, squash=(1, 1, 0.95), segs=24, metallic=0.7, rough=0.35))
    cone = [((0, 1.98, 0.02), 0.13, 0.13), ((0, 2.1, 0.0), 0.1, 0.1), ((0, 2.2, -0.03), 0.07, 0.07), ((0.0, 2.28, -0.09), 0.045, 0.045),
            ((0.0, 2.3, -0.17), 0.025, 0.025), ((0.0, 2.27, -0.23), 0.01, 0.01)]
    parts.append(loft("head", cone, PUR, segs=16))
    parts.append(loft("head", [((0, 1.985, 0.02), 0.132, 0.132), ((0, 2.03, 0.015), 0.125, 0.125)], LAV, segs=16, caps=False, double=True))
    parts.append(extrude("head", (0.0, 2.02, 0.15), crescent2d(0.045, 0.02), 0.012, GOLD, rot=(0, 0, 0), metallic=0.85, rough=0.25))
    parts.append(sph("head", (-0.1, 2.01, 0.09), 0.03, LAV, squash=(1.5, 0.8, 0.6)))
    parts.append(sph("head", (-0.05, 2.01, 0.11), 0.03, LAV, squash=(1.5, 0.8, 0.6)))
    parts.append(extrude("head", (0.0, 2.26, -0.24), crescent2d(0.03, 0.012), 0.01, GOLD, rot=(0, 90, 0), metallic=0.85, rough=0.25))
    # 首のチョーカー
    parts.append(loft("neck01", [((0, 1.705, 0.012), 0.058, 0.062), ((0, 1.72, 0.015), 0.056, 0.06)], PUR_D, segs=14, caps=False))
    # ふくらんだ袖（肩の下）と、広がる袖口（ひだつき）
    sh = add(SHOULDER_L, UPPERARM_DIR, 0.07)
    parts.append(sph("upperarm01.L", sh, 0.085, LAV, squash=(1.0, 0.85, 1.0), mirror=True, rough=0.8))
    ea = add(ELBOW_L, FOREARM_DIR, 0.08)
    eb = add(WRIST_L, FOREARM_DIR, 0.0)
    parts.append(loft("lowerarm01.L", [(tuple(ea), 0.05, 0.05), (tuple(add(ea, FOREARM_DIR, 0.08)), 0.07, 0.07), (tuple(eb), 0.11, 0.11)],
                      PUR, segs=14, side=(0, 1, 0), caps=False, double=True, mirror=True))
    parts.append(loft("lowerarm01.L", [(tuple(add(eb, FOREARM_DIR, -0.005)), 0.112, 0.112), (tuple(add(eb, FOREARM_DIR, 0.03)), 0.125, 0.125)],
                      LAV_L, segs=14, side=(0, 1, 0), caps=False, double=True, mirror=True))
    # 腰の大きなリボン
    parts.append(sph("spine05", (-0.06, 1.17, 0.14), 0.05, PUR_D, squash=(1.5, 0.9, 0.5)))
    parts.append(sph("spine05", (0.06, 1.17, 0.14), 0.05, PUR_D, squash=(1.5, 0.9, 0.5)))
    parts.append(sph("spine05", (0.0, 1.17, 0.155), 0.025, PUR_D))
    # スカート：内側（明るい紫、ひだのすそ）と外側（濃い紫、前があく、金のふち）
    inner = [((0, 1.12, 0.0), 0.15, 0.12), ((0, 0.95, 0.0), 0.24, 0.21), ((0, 0.7, 0.0), 0.34, 0.3), ((0, 0.45, 0.0), 0.42, 0.38)]
    parts.append(loft("spine05", inner, LAV, segs=24, caps=False, double=True, rough=0.8))
    parts.append(loft("spine05", [((0, 0.46, 0.0), 0.425, 0.385), ((0, 0.4, 0.0), 0.46, 0.42)], LAV_L, segs=24, caps=False, double=True))
    outer = [((0, 1.1, 0.0), 0.165, 0.135), ((0, 0.95, -0.01), 0.26, 0.23), ((0, 0.72, -0.02), 0.37, 0.33), ((0, 0.5, -0.03), 0.45, 0.41)]
    parts.append(loft("spine05", outer, PUR, segs=24, arc=(-40, 220), caps=False, double=True, rough=0.75))
    parts.append(loft("spine05", [((0, 0.505, -0.03), 0.452, 0.412), ((0, 0.49, -0.03), 0.455, 0.415)], GOLD, segs=24, arc=(-40, 220),
                      caps=False, double=True, metallic=0.6, rough=0.4))
    for i in range(14):
        a = math.radians(-30 + 240 * i / 13)
        rr = 0.3 + 0.12 * ((i * 7) % 5) / 4
        y = 0.88 - 0.4 * ((i * 3) % 7) / 6
        k = (1.1 - y) / 0.6
        rx = 0.165 + (0.45 - 0.165) * min(k, 1.0)
        parts.append(sph("spine05", (rx * math.cos(a) * 1.01, y, rx * 0.91 * math.sin(a) * 1.01), 0.008, "#f2d675", segs=6, emission=0.8, tex="none"))
    # 左手のつえ
    parts += staff("wrist.L", WRIST_L[0] + 0.03, WRIST_L[2] + 0.02, PUR_D, top_y=1.95)
    return {
        "name": "魔法使い",
        "ref": "docs/ref/chars/IMG_0400.jpeg",
        "attack_anim": "Spell",
        "height": 0.92,
        "keep": ["eyebrow004", "eyelashes01", "low-poly"],
        "skin": "#ffe9dc",
        "head_scale": 1.12,
        "bulk": {"neck": 0.82, "chest": [0.86, 0.86], "belly": [0.8, 0.8], "hips": [1.0, 1.0],
                 "upperarm": 0.78, "forearm": 0.78, "hand": 0.9, "thigh": 0.88, "shin": 0.82},
        "paint": [
            # ドレスの胴（明るい紫の前、ひもは濃い紫）と、肩から上は肌
            region(PUR, groups=["chest", "belly", "hips", "upperarm"], rough=0.75),
            region(LAV, groups=["chest", "belly"], nz=[0.35, 1.0], x_abs=[0.0, 0.1], y=[1.1, 1.53]),
            region(PUR_D, groups=["chest", "belly"], nz=[0.35, 1.0], x_abs=[0.0, 0.012], y=[1.15, 1.5]),
            region("skin", groups=["chest", "neck", "upperarm"], y=[1.535, 1.8]),
            region("skin", groups=["upperarm"], mesh=["body"]),
            # 脚（紫のタイツ）
            region(PUR_D, groups=["thigh", "shin", "hips"], y=[0.0, 1.05], rough=0.6),
        ],
        "hide": [region(groups=["forearm", "hand"], mesh=["suit"])],
        "shells": [
            # 紫のブーツ（足首まで）
            region(PUR, groups=["foot", "shin"], y=[0.0, 0.2], offset=0.01, puff={"foot": [1.1, 1.05], "shin": 1.08}, hide_under=True, rough=0.5),
        ],
        "parts": parts,
    }


def heater2d(w, h):
    """騎士の盾の形（上は平ら、下はとがる）"""
    pts = [[-w / 2, h * 0.45], [w / 2, h * 0.45]]
    n = 10
    for i in range(1, n + 1):
        t = i / n
        pts.append([w / 2 * (1 - t ** 1.6), h * 0.45 - h * t])
    for i in range(n - 1, 0, -1):
        t = i / n
        pts.append([-w / 2 * (1 - t ** 1.6), h * 0.45 - h * t])
    return pts


def spikes_on_sphere(bone, c, r, color, n=10, length=0.05):
    ps = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(1 - y * y)
        a = golden * i
        d = (rr * math.cos(a), y, rr * math.sin(a))
        ps.append(rod(bone, add(c, d, r * 0.9), add(c, d, r + length), 0.018, 0.001, color, segs=6, metallic=0.7, rough=0.35))
    return ps


# ============================================================== アーマー（たて）
def guardian():
    STEEL = "#59606b"
    STEEL_D = "#3c424b"
    GOLD = "#c9a240"
    FUR = "#7d6c58"
    BLACK = "#1c1d22"
    BLUE = "#26437e"
    parts = []
    # かぶと：頭のおおい・金のふち・てっぺんのとげ・鼻あて
    parts.append(sph("head", (0, 1.9, 0.02), 0.128, STEEL_D, squash=(1.0, 0.85, 1.05), segs=16, metallic=0.7, rough=0.35, tex="steel"))
    parts.append(torus("head", (0, 1.87, 0.025), 0.125, 0.012, GOLD, squash=(1.0, 1.0, 1.06), segs=18, metallic=0.8, rough=0.3))
    parts.append(rod("head", (0, 1.99, 0.0), (0, 2.08, -0.01), 0.025, 0.002, STEEL_D, segs=8, metallic=0.7))
    for a in (-60, -30, 30, 60):
        r = math.radians(a)
        parts.append(rod("head", (0.1 * math.sin(r), 1.96, 0.1 * math.cos(r) * 0.3 - 0.02), (0.15 * math.sin(r), 2.02, 0.12 * math.cos(r) * 0.3 - 0.03),
                         0.014, 0.001, STEEL_D, segs=6, metallic=0.7))
    parts.append(box("head", (0, 1.83, 0.155), (0.022, 0.09, 0.02), STEEL_D, metallic=0.7, rough=0.35))
    parts.append(sph("head", (0.115, 1.81, 0.04), 0.04, STEEL_D, squash=(0.4, 1.3, 1.0), mirror=True, metallic=0.7))
    # 毛皮のえり（首から肩へ、もこもこ）
    for i in range(16):
        a = 2 * math.pi * i / 16
        parts.append(sph("spine01", (0.2 * math.sin(a), 1.66 + 0.02 * math.cos(2 * a), 0.0 + 0.16 * math.cos(a) - 0.02), 0.07, FUR,
                         squash=(1.2, 0.8, 1.2), segs=8, rough=1.0))
    # 肩当て（丸い大きな板、金のふち、小さなとげ）
    sh = add(SHOULDER_L, UPPERARM_DIR, 0.06)
    parts.append(sph("upperarm01.L", add(sh, [0.02, 0.03, 0]), 0.13, STEEL, squash=(1.0, 0.8, 1.05), mirror=True, segs=14, metallic=0.7, rough=0.35, tex="steel"))
    parts.append(torus("upperarm01.L", add(sh, [0.02, -0.02, 0]), 0.12, 0.01, GOLD, rot=(0, 0, -20), mirror=True, metallic=0.8, rough=0.3))
    parts.append(rod("upperarm01.L", add(sh, [0.08, 0.1, 0]), add(sh, [0.12, 0.16, 0]), 0.02, 0.001, STEEL_D, mirror=True, segs=6, metallic=0.7))
    # 胸のライオンの紋章・腰の留め金
    parts.append(extrude("spine01", (0, 1.45, 0.215), circle2d(0.055, 16), 0.015, GOLD, metallic=0.8, rough=0.3))
    parts.append(extrude("spine05", (0, 1.12, 0.215), circle2d(0.045, 16, 1.2, 1.0), 0.015, GOLD, metallic=0.8, rough=0.3))
    # くさりのすそ（腰から、ももの中ほどまで）
    parts.append(loft("spine05", [((0, 1.1, 0.0), 0.25, 0.22), ((0, 0.95, 0.0), 0.29, 0.25), ((0, 0.8, 0.0), 0.31, 0.27)], "#585e66",
                      segs=20, caps=False, double=True, metallic=0.6, rough=0.5, tex="steel"))
    for x in (0.16, -0.16):
        parts.append(box("spine05", (x, 0.96, 0.17), (0.15, 0.2, 0.03), STEEL, rot=(-10, 0, 8 if x > 0 else -8), metallic=0.7, tex="steel"))
    # 黒いマント（背中、地面の近くまで）
    cape = [((0, 1.66, -0.04), 0.23, 0.12), ((0, 1.3, -0.07), 0.27, 0.15), ((0, 0.9, -0.08), 0.3, 0.16), ((0, 0.55, -0.08), 0.32, 0.17)]
    parts.append(loft("spine03", cape, BLACK, segs=18, arc=(15, 165), caps=False, double=True, rough=0.9))
    # 右手のとげ鉄球の棍棒
    wr = [-WRIST_L[0], WRIST_L[1], WRIST_L[2]]
    fd = [-FOREARM_DIR[0], FOREARM_DIR[1], FOREARM_DIR[2]]
    grip_a = add(wr, [0, -1, 0], -0.08)
    grip_b = add(wr, [0, -1, 0], 0.42)
    parts.append(rod("wrist.R", add(grip_a, fd, 0.06), add(grip_b, fd, 0.06), 0.022, 0.026, "#4a3424", segs=8, tex="leather"))
    mace_c = add(add(grip_b, fd, 0.06), [0, -1, 0], 0.07)
    parts.append(sph("wrist.R", mace_c, 0.09, STEEL_D, segs=12, metallic=0.75, rough=0.35, tex="steel"))
    parts += spikes_on_sphere("wrist.R", mace_c, 0.09, STEEL_D, n=12, length=0.06)
    # 左腕の盾（青に金のふちとライオン）
    mid = add(ELBOW_L, FOREARM_DIR, 0.13)
    sc = add(mid, [0.06, 0.02, 0.12])
    parts.append(extrude("lowerarm01.L", sc, heater2d(0.46, 0.58), 0.03, GOLD, rot=(0, 15, 0), metallic=0.8, rough=0.3))
    parts.append(extrude("lowerarm01.L", add(sc, [0.002, 0, 0.012]), heater2d(0.4, 0.52), 0.03, BLUE, rot=(0, 15, 0), rough=0.5))
    parts.append(extrude("lowerarm01.L", add(sc, [0.004, 0.02, 0.026]), circle2d(0.1, 18, 1.0, 1.1), 0.02, GOLD, rot=(0, 15, 0), metallic=0.85, rough=0.3))
    parts.append(extrude("lowerarm01.L", add(sc, [0.006, 0.0, 0.034]), circle2d(0.05, 12, 1.0, 1.2), 0.02, "#a8812e", rot=(0, 15, 0), metallic=0.8))
    return {
        "name": "アーマー",
        "idle_speed": 0.8,
        "attack_speed": 1.3,
        "ref": "docs/ref/chars/IMG_0401.jpeg",
        "attack_anim": "Sword_Attack",
        "height": 0.9,
        "keep": ["eyebrow001", "eyelashes01", "low-poly"],
        "skin": "#e6b08a",
        "head_scale": 1.1,
        "bulk": {"neck": 1.5, "chest": [1.5, 1.4], "belly": [1.48, 1.4], "hips": [1.3, 1.25],
                 "upperarm": 1.6, "forearm": 1.6, "thigh": 1.6, "shin": 1.5},
        "paint": [
            region(STEEL, metallic=0.7, rough=0.35, tex="steel"),
            # 顔は肌（ひげは茶色）
            region("skin", groups=["head"], mesh=["body"]),
            region("#5a3a28", groups=["head"], mesh=["body"], y=[1.68, 1.775], z=[0.0, 0.3], nz=[-0.3, 1.0], rough=0.95),
            region("#5a3a28", groups=["head"], mesh=["body"], y=[1.775, 1.79], x_abs=[0.02, 0.06], z=[0.1, 0.3], rough=0.95),
            # 胸板の段（濃い線）
            region(STEEL_D, groups=["chest", "belly"], y=[1.3, 1.32], metallic=0.7, tex="steel"),
            region(STEEL_D, groups=["belly"], y=[1.2, 1.22], metallic=0.7, tex="steel"),
            # 金のふち（胸の中心・腰）
            region(GOLD, groups=["chest", "belly"], x_abs=[0.0, 0.01], nz=[0.4, 1.0], y=[1.2, 1.55], metallic=0.8, rough=0.3),
            region("#4a3424", groups=["hips", "belly"], y=[1.08, 1.15], tex="leather"),
            region(STEEL_D, groups=["hand"], metallic=0.7, tex="steel"),
        ],
        "hide": [],
        "shells": [
            region(STEEL_D, groups=["foot"], mesh=["shoes"], offset=0.015, puff={"foot": [1.35, 1.25]}, hide_under=True, metallic=0.7, tex="steel"),
        ],
        "parts": parts,
    }


def teddy(bone, c, fur, bow, scale=1.0):
    """くまのぬいぐるみ（体・頭・耳・鼻・目・リボン）。c は体の中心"""
    k = scale
    ps = [sph(bone, c, 0.07 * k, fur, squash=(1.0, 1.1, 0.9), segs=10, rough=1.0, tex="cloth")]
    h = add(c, [0, 0.11 * k, 0.01])
    ps.append(sph(bone, h, 0.06 * k, fur, segs=10, rough=1.0, tex="cloth"))
    for sx in (1, -1):
        ps.append(sph(bone, add(h, [0.045 * k * sx, 0.045 * k, -0.005]), 0.022 * k, fur, segs=8, rough=1.0))
        ps.append(sph(bone, add(h, [0.022 * k * sx, 0.012 * k, 0.052 * k]), 0.008 * k, "#111111", segs=6))
        ps.append(sph(bone, add(c, [0.07 * k * sx, -0.03 * k, 0.03 * k]), 0.026 * k, fur, segs=8, rough=1.0))
    ps.append(sph(bone, add(h, [0, -0.015 * k, 0.055 * k]), 0.022 * k, "#d8b48a", squash=(1.2, 0.9, 0.8), segs=8))
    ps.append(sph(bone, add(h, [0, -0.008 * k, 0.074 * k]), 0.008 * k, "#1a1a1a", segs=6))
    ps.append(sph(bone, add(c, [-0.022 * k, 0.06 * k, 0.05 * k]), 0.018 * k, bow, squash=(1.4, 0.8, 0.6), segs=8))
    ps.append(sph(bone, add(c, [0.022 * k, 0.06 * k, 0.05 * k]), 0.018 * k, bow, squash=(1.4, 0.8, 0.6), segs=8))
    return ps


def bunny(bone, c, fur, inner, bow, scale=1.0):
    k = scale
    ps = [sph(bone, c, 0.068 * k, fur, squash=(1.0, 1.15, 0.9), segs=10, rough=1.0, tex="cloth")]
    h = add(c, [0, 0.115 * k, 0.01])
    ps.append(sph(bone, h, 0.058 * k, fur, segs=10, rough=1.0, tex="cloth"))
    for sx in (1, -1):
        ps.append(rod(bone, add(h, [0.02 * k * sx, 0.04 * k, 0]), add(h, [0.035 * k * sx, 0.17 * k, -0.01]), 0.018 * k, 0.014 * k, fur,
                      squash=(1.0, 0.5), segs=8))
        ps.append(rod(bone, add(h, [0.02 * k * sx, 0.05 * k, 0.006]), add(h, [0.035 * k * sx, 0.16 * k, -0.002]), 0.01 * k, 0.008 * k, inner,
                      squash=(1.0, 0.4), segs=6))
        ps.append(sph(bone, add(h, [0.022 * k * sx, 0.012 * k, 0.05 * k]), 0.008 * k, "#1a1a1a", segs=6))
    ps.append(sph(bone, add(h, [0, -0.01 * k, 0.057 * k]), 0.008 * k, "#e58aa6", segs=6))
    ps.append(sph(bone, add(c, [-0.022 * k, 0.065 * k, 0.05 * k]), 0.02 * k, bow, squash=(1.4, 0.8, 0.6), segs=8))
    ps.append(sph(bone, add(c, [0.022 * k, 0.065 * k, 0.05 * k]), 0.02 * k, bow, squash=(1.4, 0.8, 0.6), segs=8))
    return ps


# ============================================================== おもちゃの兵隊（よびだし）
def summoner():
    RED = "#c3262d"
    BLACK = "#15161a"
    GOLD = "#d4a838"
    WHITE = "#ece7dc"
    parts = []
    # 筒形の軍帽（赤）：黒いつば・金の帯・前の金の飾り・上の黒いふち
    parts.append(loft("head", [((0, 1.9, 0.02), 0.108, 0.118), ((0, 2.02, 0.015), 0.112, 0.122), ((0, 2.1, 0.01), 0.116, 0.126)], RED, segs=18))
    parts.append(loft("head", [((0, 2.095, 0.01), 0.118, 0.128), ((0, 2.11, 0.01), 0.118, 0.128)], BLACK, segs=18, caps=False, double=True))
    parts.append(loft("head", [((0, 1.9, 0.02), 0.11, 0.12), ((0, 1.925, 0.02), 0.111, 0.121)], BLACK, segs=18, caps=False, double=True))
    parts.append(loft("head", [((0, 1.925, 0.02), 0.111, 0.121), ((0, 1.94, 0.02), 0.112, 0.122)], GOLD, segs=18, caps=False, double=True, metallic=0.8))
    parts.append(extrude("head", (0, 1.9, 0.13), [[-0.09, 0], [0.09, 0], [0.07, 0.06], [-0.07, 0.06]], 0.012, BLACK, rot=(-80, 0, 0), metallic=0.3, rough=0.2))
    parts.append(extrude("head", (0, 2.03, 0.14), [[0, 0.07], [0.025, 0.0], [0.0, -0.04], [-0.025, 0.0]], 0.02, GOLD, metallic=0.8, rough=0.3))
    parts.append(sph("head", (0, 1.965, 0.14), 0.016, GOLD, metallic=0.8, rough=0.3))
    # 金の肩章（房つき）
    sh = add(SHOULDER_L, UPPERARM_DIR, 0.0)
    parts.append(box("upperarm01.L", add(sh, [0.0, 0.055, 0]), (0.12, 0.02, 0.1), GOLD, rot=(0, 0, -25), mirror=True, metallic=0.8, rough=0.3))
    for i in range(6):
        z = -0.04 + 0.016 * i
        parts.append(rod("upperarm01.L", add(sh, [0.06, 0.03, z]), add(sh, [0.085, -0.02, z]), 0.007, 0.007, GOLD, mirror=True, segs=5, metallic=0.7))
    # 黒い襟・黒い袖口・ベルトの留め金
    parts.append(loft("neck01", [((0, 1.63, 0.0), 0.075, 0.082), ((0, 1.7, 0.012), 0.065, 0.07)], BLACK, segs=14, caps=False))
    parts.append(box("spine05", (0, 1.075, 0.19), (0.07, 0.05, 0.02), "#c9ccd1", metallic=0.9, rough=0.25))
    # 上着のすそ（腰からももの上まで、金のふち）
    parts.append(loft("spine05", [((0, 1.07, 0.0), 0.2, 0.17), ((0, 0.95, 0.0), 0.22, 0.19), ((0, 0.88, 0.0), 0.225, 0.195)], RED, segs=20,
                      arc=(-80, 260), caps=False, double=True))
    parts.append(loft("spine05", [((0, 0.885, 0.0), 0.226, 0.196), ((0, 0.875, 0.0), 0.227, 0.197)], GOLD, segs=20, arc=(-80, 260),
                      caps=False, double=True, metallic=0.7))
    # ブーツの外側の金ボタン
    for k in range(6):
        y = 0.12 + 0.065 * k
        parts.append(sph("lowerleg01.L", (0.23 - 0.07 * (y - 0.12) / 0.4 + 0.0, y, 0.01), 0.011, GOLD, mirror=True, segs=6, metallic=0.8))
    # 胸にだいたぬいぐるみ（くま2つ・うさぎ1つ）
    parts += teddy("spine01", (0.15, 1.36, 0.25), "#7a5232", "#2f5fb0", scale=1.4)
    parts += teddy("spine01", (-0.15, 1.36, 0.25), "#7a5232", "#2f5fb0", scale=1.4)
    parts += bunny("spine01", (0.0, 1.4, 0.29), "#f4efe9", "#f2b6c6", "#e46a9a", scale=1.4)
    return {
        "name": "おもちゃの兵隊",
        "ref": "docs/ref/chars/IMG_0404.jpeg",
        "attack_anim": "Spell",
        "height": 1.0,
        "keep": ["eyebrow001", "eyelashes01", "low-poly", "short04"],
        "skin": "#f4d6c4",
        "tint_short04": "#4a3226",
        "head_scale": 0.98,
        "bulk": {"neck": 0.95, "chest": [1.02, 1.0], "belly": [0.95, 0.95], "upperarm": 1.0, "forearm": 0.98, "thigh": 0.98, "shin": 0.96},
        "paint": [
            region(RED, groups=["chest", "belly", "upperarm", "forearm", "neck"], rough=0.7),
            region(BLACK, groups=["forearm"], y=[0.0, 1.27], rough=0.6),
            region(GOLD, groups=["chest", "belly"], x_abs=[0.0, 0.012], nz=[0.4, 1.0], y=[1.08, 1.62], metallic=0.7, rough=0.35),
            # 白いズボンと、外側の金の線
            region(WHITE, groups=["hips", "thigh", "shin"], y=[0.0, 1.0], rough=0.75),
            region(RED, groups=["hips", "belly"], y=[1.0, 1.3], rough=0.7),
            region(BLACK, groups=["hips", "belly"], y=[1.05, 1.1], rough=0.4),
            region(GOLD, groups=["thigh", "shin"], rx_out=[0.975, 1.0], y=[0.5, 0.95], metallic=0.6, rough=0.4),
            region("skin", groups=["hand"]),
            region("skin", groups=["neck"], mesh=["body"], y=[1.7, 1.8]),
        ],
        "hide": [region(groups=["forearm", "hand"], mesh=["suit"])],
        "shells": [
            # ひざ下までの黒い長ぐつ
            region(BLACK, groups=["shin", "foot"], y=[0.0, 0.5], offset=0.01, puff={"shin": 1.12, "foot": [1.15, 1.1]}, hide_under=True,
                   metallic=0.2, rough=0.25),
        ],
        "parts": parts,
    }


# ============================================================== エンジェル（いやし）
def healer():
    WHITE = "#f7f3ee"
    CREAM = "#efe6da"
    GOLD = "#d8ae4a"
    RED = "#d9505a"
    HAIR = "#d8c49a"
    parts = long_hair(HAIR, length_y=1.08, width=0.15)
    # 天使の輪（光る金）と、頭の小さな羽・白い花
    parts.append(torus("head", (0, 2.08, 0.0), 0.09, 0.008, "#ffd56a", segs=20, emission=1.6, tex="none"))
    for sx in (1, -1):
        parts.append(extrude("head", (0.1 * sx, 1.93, 0.0), [[p[0] * sx, p[1]] for p in wing2d(0.09)], 0.01, WHITE, rot=(0, 0, 0)))
    parts.append(sph("head", (0.1, 1.9, 0.07), 0.026, WHITE, squash=(1, 1, 0.5), segs=8))
    parts.append(sph("head", (0.1, 1.9, 0.085), 0.01, "#f2c94c", segs=6))
    # 背中の大きな白い羽（左右。羽根の形を3枚重ねる）
    for sx in (1, -1):
        for k, (sc, dy, dz) in enumerate([(0.55, 0.0, -0.17), (0.45, -0.05, -0.19), (0.34, -0.1, -0.21)]):
            parts.append(extrude("spine01", (0.05 * sx, 1.47 + dy, dz), [[p[0] * sx, p[1] - sc * 0.3] for p in wing2d(sc)], 0.02,
                                 WHITE if k != 1 else CREAM, rot=(0, -25 * sx, 10 * sx), rough=0.9, double=True))
    # 胸のリボン（赤）・胸のふち（金）
    parts.append(sph("spine01", (-0.03, 1.58, 0.12), 0.022, RED, squash=(1.4, 0.8, 0.6), segs=8))
    parts.append(sph("spine01", (0.03, 1.58, 0.12), 0.022, RED, squash=(1.4, 0.8, 0.6), segs=8))
    # ふくらんだ袖（ひじから先、白いベル）
    ea = add(ELBOW_L, UPPERARM_DIR, -0.06)
    eb = add(ELBOW_L, FOREARM_DIR, 0.14)
    parts.append(loft("upperarm02.L", [(tuple(ea), 0.06, 0.06), (tuple(add(ea, UPPERARM_DIR, 0.05)), 0.08, 0.08), (tuple(ELBOW_L), 0.075, 0.075)],
                      WHITE, segs=12, side=(0, 1, 0), caps=False, double=True, mirror=True))
    parts.append(loft("lowerarm01.L", [(tuple(add(ELBOW_L, FOREARM_DIR, 0.02)), 0.06, 0.06), (tuple(eb), 0.1, 0.1)], WHITE, segs=12,
                      side=(0, 1, 0), caps=False, double=True, mirror=True))
    # 3段のふわふわの短いスカート（金のふち）
    tiers = [(1.12, 0.92, 0.17, 0.3), (1.0, 0.85, 0.2, 0.36), (0.93, 0.79, 0.24, 0.41)]
    for top, bot, rt, rb in tiers:
        parts.append(loft("spine05", [((0, top, 0.0), rt, rt * 0.86), ((0, (top + bot) / 2, 0.0), (rt + rb) / 2 * 1.05, (rt + rb) / 2 * 0.92),
                                      ((0, bot, 0.0), rb, rb * 0.88)], WHITE, segs=24, caps=False, double=True, rough=0.85))
        parts.append(loft("spine05", [((0, bot + 0.004, 0.0), rb * 1.003, rb * 0.883), ((0, bot - 0.006, 0.0), rb * 1.01, rb * 0.89)], GOLD, segs=24,
                          caps=False, double=True, metallic=0.6, rough=0.4))
    # 背中の矢筒（金と白、ハートの矢）
    parts.append(rod("spine01", (0.06, 1.18, -0.17), (0.12, 1.55, -0.2), 0.045, 0.05, CREAM, segs=10))
    parts.append(torus("spine01", (0.12, 1.55, -0.2), 0.05, 0.007, GOLD, rot=(0, 0, -9), metallic=0.7))
    for k in range(3):
        tip = (0.1 + 0.03 * k, 1.66, -0.21)
        parts.append(rod("spine01", (0.11 + 0.02 * k, 1.5, -0.2), tip, 0.005, 0.005, GOLD, segs=5))
        parts.append(extrude("spine01", tip, heart2d(0.03), 0.012, RED, rot=(0, 90, 180)))
    # 手の金の弓とハートの矢（左手）
    w = WRIST_L
    parts.append(tube("wrist.L", [add(w, [0.03, 0.3, 0.08]), add(w, [0.12, 0.0, 0.1]), add(w, [0.03, -0.3, 0.08])], 0.011, 0.011, GOLD,
                      smooth=True, steps=8, segs=6, metallic=0.75, rough=0.3))
    parts.append(rod("wrist.L", add(w, [0.03, 0.3, 0.08]), add(w, [0.03, -0.3, 0.08]), 0.002, 0.002, "#f4e9c8", segs=4))
    parts.append(rod("wrist.L", add(w, [0.02, 0.0, 0.08]), add(w, [-0.3, 0.0, 0.12]), 0.005, 0.005, RED, segs=5))
    parts.append(extrude("wrist.L", add(w, [-0.32, 0.0, 0.12]), heart2d(0.035), 0.012, RED, rot=(0, 0, 90)))
    # ブーツの赤いリボン・金のかかと
    parts.append(sph("lowerleg02.L", (0.2, 0.25, 0.07), 0.018, RED, squash=(1.5, 0.8, 0.6), mirror=True, segs=8))
    parts.append(rod("foot.L", (0.205, 0.07, -0.06), (0.205, 0.0, -0.06), 0.02, 0.014, GOLD, mirror=True, segs=8, metallic=0.7))
    return {
        "name": "エンジェル",
        "ref": "docs/ref/chars/IMG_0405.jpeg",
        "attack_anim": "Spell",
        "height": 0.9,
        "keep": ["eyebrow004", "eyelashes01", "low-poly"],
        "skin": "#fff0e6",
        "head_scale": 1.14,
        "bulk": {"neck": 0.8, "chest": [0.86, 0.86], "belly": [0.8, 0.8], "hips": [0.98, 0.98],
                 "upperarm": 0.76, "forearm": 0.76, "hand": 0.88, "thigh": 0.88, "shin": 0.8},
        "paint": [
            # 胸までの白いドレス（肩は出す）・金のふち・白いニーハイ
            region(WHITE, groups=["chest", "belly", "hips"], rough=0.8),
            region("skin", groups=["chest", "neck", "upperarm"], y=[1.55, 1.8]),
            region(GOLD, groups=["chest"], y=[1.535, 1.555], metallic=0.6, rough=0.4),
            region(GOLD, groups=["chest", "belly"], x_abs=[0.0, 0.01], nz=[0.4, 1.0], y=[1.15, 1.54], metallic=0.6, rough=0.4),
            region("skin", groups=["upperarm", "forearm", "hand"]),
            region(WHITE, groups=["thigh", "shin", "foot"], y=[0.0, 0.78], rough=0.7),
            region("skin", groups=["thigh", "hips"], y=[0.78, 1.0]),
        ],
        "hide": [region(groups=["forearm", "hand"], mesh=["suit"])],
        "shells": [
            # ニーハイのふち（ひだ）と、白いヒールのブーツ
            region(CREAM, groups=["thigh"], y=[0.74, 0.79], offset=0.01, puff={"thigh": 1.08}, rough=0.9),
            region(WHITE, groups=["foot", "shin"], y=[0.0, 0.28], offset=0.01, puff={"foot": [1.08, 1.05], "shin": 1.1}, hide_under=True, rough=0.4),
        ],
        "parts": parts,
    }


LOOKS = {
    "brawler": brawler,
    "sprinter": sprinter,
    "gunner": gunner,
    "bomber": bomber,
    "mage": mage,
    "guardian": guardian,
    "summoner": summoner,
    "healer": healer,
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
            # 前もって作った形（tools/bake_looks.gd が作る）。作り直すときは、bake_looks.gd を回す
            c["model"] = "res://assets/models/chars/%s.scn" % c["id"]
            c["model_scale"] = round(1.95 * float(lk.get("height", 1.0)), 4)
            c["anim_library"] = "res://assets/anims/hero_ual.res"
            c["procedural_anims"] = True
            atk = lk.get("attack_anim", "Punch")
            c["animations"] = {"idle": "Idle", "run": lk.get("run_anim", "Run"), "jump": "Jump", "attack": atk, "down": "Death",
                               "swing": atk, "jump_start": "Jump_Start", "land": "Jump_Land", "roll": "Roll", "charge": "Spell", "hit": "Hit"}
            c["anim_oneshot"] = ["attack"]
            # 自然に見える速さ：走りの動きは、移動の速さに合わせる（剣士：7.0m/秒で 1.1倍、体の大きさでも変える）。
            # 重いキャラはゆっくり待ち、軽いキャラは速く待つ（idle_speed）
            mv = float(c["stats"]["move_speed"])
            run = 1.1 * (mv / 7.0) * (1.95 / c["model_scale"])
            if lk.get("run_anim") == "Sprint":
                run *= 0.72  # 全力の走り（Sprint）は、1歩が大きい
            c["anim_speeds"] = {"run": round(max(0.75, min(run, 1.6)), 3), "idle": lk.get("idle_speed", 1.0),
                                "attack": lk.get("attack_speed", 1.6)}
    (ROOT / "data/characters.json").write_text(json.dumps(chars, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("looks", list(looks))


if __name__ == "__main__":
    main()
