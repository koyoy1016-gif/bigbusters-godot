#!/usr/bin/env python3
"""版79：技で飛ぶ物・出る物（小物）の形を、data/props.json に書く。scripts/fx/skill_fx.gd が、名前で作る。
座標は小物の中（原点が中心、+Z が飛ぶ向き、+Y が上）。部品の書き方は tools/make_looks.py と同じ（bone は使わない）。
使い方: python3 tools/make_props.py
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_looks import box, sph, rod, tube, torus, extrude, loft, circle2d, heart2d, wing2d, clean  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
B = "root"


def star2d(r_out, r_in, n=5, rot=90.0):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + 180.0 * i / n)
        pts.append([r * math.cos(a), r * math.sin(a)])
    return pts


def glow(d, e=1.6):
    d["emission"] = e
    d["tex"] = "none"
    return d


# ---------------------------------------------------------------- ボンバー：プレゼントの爆弾
def present(body, ribbon, size=0.34, fuse=True):
    h = size / 2
    p = [box(B, (0, 0, 0), (size, size * 0.9, size), body, rough=0.55, tex="none"),
         # ふた（少し大きい）
         box(B, (0, h * 0.9 - 0.02, 0), (size * 1.06, size * 0.16, size * 1.06), body, rough=0.5, tex="none"),
         # リボン（十字）
         box(B, (0, 0.005, 0), (size * 1.08, size * 0.92, size * 0.16), ribbon, rough=0.35, tex="none"),
         box(B, (0, 0.005, 0), (size * 0.16, size * 0.92, size * 1.08), ribbon, rough=0.35, tex="none"),
         # 上のちょうちょ結び（2つの輪と結び目と、たれ）
         sph(B, (-size * 0.17, h + 0.03, 0), size * 0.15, ribbon, squash=(1.3, 0.7, 0.55), rot=(0, 0, 20), segs=10, rough=0.35, tex="none"),
         sph(B, (size * 0.17, h + 0.03, 0), size * 0.15, ribbon, squash=(1.3, 0.7, 0.55), rot=(0, 0, -20), segs=10, rough=0.35, tex="none"),
         sph(B, (0, h + 0.015, 0), size * 0.07, ribbon, segs=8, rough=0.35, tex="none"),
         box(B, (-size * 0.08, h - 0.01, size * 0.1), (size * 0.08, size * 0.2, 0.01), ribbon, rot=(20, 0, 15), tex="none"),
         box(B, (size * 0.08, h - 0.01, size * 0.1), (size * 0.08, size * 0.2, 0.01), ribbon, rot=(20, 0, -15), tex="none"),
         # 名札（白い札とひも）
         box(B, (size * 0.38, h * 0.2, size * 0.42), (size * 0.22, size * 0.14, 0.008), "#f7f2e6", rot=(0, 30, -12), tex="none"),
         ]
    if fuse:
        p.append(tube(B, [(0, h + 0.04, -0.02), (0.03, h + 0.12, -0.04), (0.06, h + 0.17, 0.0)], 0.012, 0.009, "#3a2a1a", smooth=True, steps=5, segs=6))
        p.append(glow(sph(B, (0.06, h + 0.19, 0.0), 0.035, "#ffd65a", segs=8), 3.0))
        p.append(glow(extrude(B, (0.06, h + 0.19, 0.0), star2d(0.07, 0.025, 6), 0.004, "#fff2a0"), 2.5))
    return p


# ---------------------------------------------------------------- ガンナー：弾・砲口の光
def bullet():
    """版80：ビームに見えないよう、尾を短くし、金色の薬きょう形の「弾」をはっきり見せる（まわりに薄い光）"""
    return [glow(rod(B, (0, 0, -0.13), (0, 0, 0.07), 0.07, 0.07, "#f2b84a", segs=12), 1.5),          # 弾の胴（金色）
            glow(rod(B, (0, 0, 0.07), (0, 0, 0.2), 0.07, 0.012, "#ff7a2a", segs=12), 2.0),            # とがった先（赤だいだい）
            glow(rod(B, (0, 0, -0.14), (0, 0, -0.1), 0.075, 0.075, "#b8742a", segs=12), 1.0),        # おしりの帯
            glow(sph(B, (0, 0, 0.02), 0.13, "#ffd36a", squash=(1, 1, 1.6), segs=10), 1.8) | {"alpha": 0.3},   # まわりの光
            glow(rod(B, (0, 0, -0.38), (0, 0, -0.14), 0.006, 0.05, "#ffe08a", segs=8), 1.6) | {"alpha": 0.5}]  # 短い尾


def cannon_shell():
    """版80：ガンナーの必殺技の大きな砲弾（帯と、だいだいの光）"""
    return [glow(rod(B, (0, 0, -0.2), (0, 0, 0.1), 0.11, 0.11, "#d9a23a", segs=14), 1.4),
            glow(rod(B, (0, 0, 0.1), (0, 0, 0.3), 0.11, 0.02, "#ff5a1a", segs=14), 2.0),
            glow(torus(B, (0, 0, -0.05), 0.115, 0.018, "#ffe08a", rot=(90, 0, 0), segs=16), 2.2),
            glow(torus(B, (0, 0, -0.15), 0.115, 0.018, "#ffe08a", rot=(90, 0, 0), segs=16), 2.2),
            glow(sph(B, (0, 0, 0.02), 0.2, "#ff9a3a", squash=(1, 1, 1.5), segs=12), 1.8) | {"alpha": 0.32},
            glow(rod(B, (0, 0, -0.6), (0, 0, -0.2), 0.01, 0.09, "#ffb347", segs=10), 1.6) | {"alpha": 0.5}]


def muzzle_flash():
    return [glow(extrude(B, (0, 0, 0), star2d(0.32, 0.1, 8, 0), 0.01, "#ffd36a"), 3.0),
            glow(extrude(B, (0, 0, 0.01), star2d(0.18, 0.06, 6, 15), 0.01, "#fff6d0"), 3.0),
            glow(rod(B, (0, 0, 0), (0, 0, 0.45), 0.14, 0.01, "#ff8a3a", segs=10), 2.0),
            glow(sph(B, (0, 0, 0.05), 0.16, "#fff2b0", segs=10), 2.6) | {"alpha": 0.7}]


# ---------------------------------------------------------------- 魔法使い：魔法の玉・大きな玉・メテオ・魔法陣
def magic_orb(core, shell, r=0.2):
    p = [glow(sph(B, (0, 0, 0), r * 0.62, "#ffffff", segs=12), 2.5),
         glow(sph(B, (0, 0, 0), r, core, segs=14), 1.8),
         glow(torus(B, (0, 0, 0), r * 1.35, r * 0.07, shell, rot=(70, 0, 20), segs=20), 2.0),
         glow(torus(B, (0, 0, 0), r * 1.5, r * 0.06, shell, rot=(-50, 40, 0), segs=20), 2.0)]
    for i in range(5):
        a = 2 * math.pi * i / 5
        p.append(glow(extrude(B, (r * 1.7 * math.cos(a), r * 1.7 * math.sin(a) * 0.6, r * 0.4 * math.sin(a)), star2d(r * 0.28, r * 0.11), 0.01, "#fff6c8"), 2.5))
    return p


def crescent2d(r, thick, n=20):
    outer = [[r * math.cos(math.pi * (0.25 + 1.5 * i / n)), r * math.sin(math.pi * (0.25 + 1.5 * i / n))] for i in range(n + 1)]
    ri = r * 0.8
    inner = [[thick + ri * math.cos(math.pi * (0.25 + 1.5 * (n - i) / n)), ri * math.sin(math.pi * (0.25 + 1.5 * (n - i) / n))] for i in range(n + 1)]
    return outer + inner


def magic_big():
    p = magic_orb("#9a5cff", "#e6c8ff", 0.42)
    p.append(glow(extrude(B, (0, 0, 0.47), crescent2d(0.2, 0.08), 0.02, "#ffe27a"), 2.2))
    return p


def meteor():
    p = [sph(B, (0, 0, 0), 0.75, "#5a3a2a", segs=14, rough=0.95, tex="none")]
    for i, (x, y, z, r) in enumerate([(0.5, 0.3, 0.2, 0.32), (-0.45, 0.35, -0.1, 0.3), (0.1, -0.55, 0.3, 0.3), (-0.2, 0.1, 0.62, 0.25), (0.3, -0.2, -0.55, 0.28)]):
        p.append(sph(B, (x, y, z), r, "#6b4630", segs=10, rough=0.95, tex="none"))
    p.append(glow(sph(B, (0, 0, 0), 0.95, "#ff6a1a", segs=16), 1.2) | {"alpha": 0.45})
    p.append(glow(rod(B, (0, 0, -0.4), (0, 0, -2.6), 0.85, 0.05, "#ffb347", segs=12), 1.8) | {"alpha": 0.5})
    return p


def magic_circle(color="#b98aff"):
    p = [glow(torus(B, (0, 0, 0), 1.0, 0.02, color, segs=40), 2.2),
         glow(torus(B, (0, 0, 0), 0.82, 0.012, color, segs=36), 2.2),
         glow(torus(B, (0, 0, 0), 0.4, 0.012, color, segs=24), 2.2),
         glow(extrude(B, (0, 0.01, 0), star2d(0.8, 0.33, 5), 0.005, color, rot=(90, 0, 0)), 1.6) | {"alpha": 0.55}]
    for i in range(12):
        a = 2 * math.pi * i / 12
        p.append(glow(box(B, (0.91 * math.cos(a), 0, 0.91 * math.sin(a)), (0.05, 0.005, 0.08), color, rot=(0, -math.degrees(a), 0)), 2.0))
    return p


# ---------------------------------------------------------------- エンジェル：ハートの矢・光の羽根
def heart_arrow():
    p = [rod(B, (0, 0, -0.55), (0, 0, 0.25), 0.014, 0.014, "#d8ae4a", segs=6, metallic=0.6),
         glow(extrude(B, (0, 0, 0.3), heart2d(0.11), 0.03, "#ff5a78", rot=(90, 0, 0)), 1.4),
         glow(extrude(B, (0, 0, 0.3), heart2d(0.11), 0.03, "#ff5a78", rot=(90, 90, 0)), 1.4)]
    for a in (0, 120, 240):
        p.append(extrude(B, (0, 0, -0.5), [[0, 0], [0.06, 0.04], [0.07, 0.14], [0.0, 0.12]], 0.004, "#fff6f0", rot=(90, a, 0), double=True))
    p.append(glow(rod(B, (0, 0, -1.1), (0, 0, -0.5), 0.004, 0.03, "#ffd0dc", segs=6), 1.5) | {"alpha": 0.6})
    return p


# ---------------------------------------------------------------- ボンバー：花火の玉 / ファイター：こぶしの衝撃
def firework_shell(color):
    return [rod(B, (0, 0, -0.18), (0, 0, 0.18), 0.12, 0.12, color, segs=12, rough=0.5, tex="none"),
            sph(B, (0, 0, 0.2), 0.12, color, segs=10, tex="none"),
            glow(extrude(B, (0, 0, 0.0), star2d(0.08, 0.03), 0.25, "#fff3a0"), 1.4),
            glow(rod(B, (0, 0, -0.9), (0, 0, -0.2), 0.02, 0.1, "#ffd36a", segs=8), 2.0) | {"alpha": 0.6}]


def plush_bear(fur, bow, k=1.0):
    p = [sph(B, (0, 0.0, 0), 0.07 * k, fur, squash=(1, 1.1, 0.9), segs=10, rough=1.0, tex="cloth"),
         sph(B, (0, 0.11 * k, 0.01), 0.06 * k, fur, segs=10, rough=1.0, tex="cloth")]
    for sx in (1, -1):
        p.append(sph(B, (0.045 * k * sx, 0.155 * k, 0), 0.022 * k, fur, segs=8))
        p.append(sph(B, (0.022 * k * sx, 0.122 * k, 0.05 * k), 0.008 * k, "#111111", segs=6))
    p.append(sph(B, (0, 0.095 * k, 0.055 * k), 0.022 * k, "#d8b48a", squash=(1.2, 0.9, 0.8), segs=8))
    p.append(sph(B, (0, 0.06 * k, 0.05 * k), 0.02 * k, bow, squash=(1.6, 0.8, 0.6), segs=8))
    return p


def present_box(body, ribbon, size=0.5):
    """開くプレゼントの、箱（ふたなし）"""
    h = size / 2
    return [box(B, (0, h * 0.9, 0), (size, size * 0.9, size), body, rough=0.55, tex="none"),
            box(B, (0, h * 0.9, 0), (size * 1.02, size * 0.92, size * 0.16), ribbon, rough=0.35, tex="none"),
            box(B, (0, h * 0.9, 0), (size * 0.16, size * 0.92, size * 1.02), ribbon, rough=0.35, tex="none")]


def present_lid(body, ribbon, size=0.5):
    """開くプレゼントの、ふた（ちょうちょ結びつき）"""
    y = size * 0.9 + 0.03
    return [box(B, (0, y, 0), (size * 1.08, size * 0.16, size * 1.08), body, rough=0.5, tex="none"),
            box(B, (0, y, 0), (size * 1.1, size * 0.17, size * 0.17), ribbon, tex="none"),
            box(B, (0, y, 0), (size * 0.17, size * 0.17, size * 1.1), ribbon, tex="none"),
            sph(B, (-size * 0.17, y + 0.09, 0), size * 0.15, ribbon, squash=(1.3, 0.7, 0.55), rot=(0, 0, 20), segs=10, tex="none"),
            sph(B, (size * 0.17, y + 0.09, 0), size * 0.15, ribbon, squash=(1.3, 0.7, 0.55), rot=(0, 0, -20), segs=10, tex="none"),
            sph(B, (0, y + 0.07, 0), size * 0.07, ribbon, segs=8, tex="none")]


def jack_spring():
    """びっくり箱の中身：バネと、道化の顔（赤い鼻・帽子）"""
    pts = []
    for i in range(41):
        a = i * 0.6
        pts.append((0.09 * math.cos(a), 0.35 + 0.022 * i, 0.09 * math.sin(a)))
    p = [tube(B, pts, 0.014, 0.014, "#c8ccd4", segs=6, metallic=0.8, rough=0.3)]
    y = 1.35
    p += [sph(B, (0, y, 0), 0.17, "#f8f4ee", segs=14, tex="none"),
          sph(B, (0, y - 0.01, 0.16), 0.04, "#e02020", segs=8, tex="none"),
          sph(B, (0.06, y + 0.05, 0.14), 0.025, "#1a1a1a", segs=6),
          sph(B, (-0.06, y + 0.05, 0.14), 0.025, "#1a1a1a", segs=6),
          tube(B, [(-0.07, y - 0.07, 0.13), (0, y - 0.11, 0.155), (0.07, y - 0.07, 0.13)], 0.012, 0.012, "#d42a2a", smooth=True, steps=5, segs=5),
          sph(B, (0, y + 0.12, 0), 0.15, "#3d9a4a", squash=(1.05, 0.6, 1.05), segs=12, tex="none")]
    for x, col in ((0.12, "#e8b62c"), (-0.12, "#6a3c9a")):
        p.append(tube(B, [(x * 0.4, y + 0.18, 0), (x * 1.3, y + 0.3, 0), (x * 1.6, y + 0.15, 0.02)], 0.06, 0.015, col, smooth=True, steps=6, segs=8))
        p.append(sph(B, (x * 1.6, y + 0.13, 0.02), 0.03, "#d9a83a", metallic=0.8, segs=8))
    return p


def plush_bunny(k=1.6):
    p = [sph(B, (0, 0.0, 0), 0.068 * k, "#f4efe9", squash=(1, 1.15, 0.9), segs=10, rough=1.0, tex="cloth"),
         sph(B, (0, 0.115 * k, 0.01), 0.058 * k, "#f4efe9", segs=10, rough=1.0, tex="cloth")]
    for sx in (1, -1):
        p.append(rod(B, (0.02 * k * sx, 0.155 * k, 0), (0.035 * k * sx, 0.285 * k, -0.01), 0.018 * k, 0.014 * k, "#f4efe9", squash=(1, 0.5), segs=8))
        p.append(rod(B, (0.02 * k * sx, 0.165 * k, 0.006), (0.035 * k * sx, 0.275 * k, -0.002), 0.01 * k, 0.008 * k, "#f2b6c6", squash=(1, 0.4), segs=6))
        p.append(sph(B, (0.022 * k * sx, 0.127 * k, 0.05 * k), 0.008 * k, "#1a1a1a", segs=6))
    p.append(sph(B, (0, 0.06 * k, 0.05 * k), 0.02 * k, "#e46a9a", squash=(1.6, 0.8, 0.6), segs=8))
    return p


def heal_orb():
    return [glow(sph(B, (0, 0, 0), 0.13, "#ffffff", segs=10), 2.5),
            glow(sph(B, (0, 0, 0), 0.22, "#5fe08a", segs=12), 1.8) | {"alpha": 0.55},
            glow(extrude(B, (0, 0, 0.0), [[-0.03, 0.1], [0.03, 0.1], [0.03, 0.03], [0.1, 0.03], [0.1, -0.03], [0.03, -0.03], [0.03, -0.1], [-0.03, -0.1],
                                       [-0.03, -0.03], [-0.1, -0.03], [-0.1, 0.03], [-0.03, 0.03]], 0.02, "#e8fff0"), 2.5),
            glow(rod(B, (0, 0, -0.7), (0, 0, -0.1), 0.01, 0.12, "#9dffb8", segs=8), 1.6) | {"alpha": 0.5}]


PROPS = {
    "present_box": present_box("#e6343a", "#ffd84a"),
    "present_lid": present_lid("#e6343a", "#ffd84a"),
    "jack_spring": jack_spring(),
    "plush_bunny": plush_bunny(),
    "plush_bear2": plush_bear("#a9784a", "#c8302b", 1.6),
    "bullet_small": [glow(rod(B, (0, 0, -0.08), (0, 0, 0.06), 0.03, 0.035, "#ffb347", segs=8), 2.2),
                     glow(rod(B, (0, 0, -0.35), (0, 0, -0.08), 0.006, 0.03, "#ffd36a", segs=6), 1.6) | {"alpha": 0.6}],
    "heal_orb": heal_orb(),
    "present_pink": present("#d65aa0", "#ffd84a"),
    "present_green": present("#3d9a4a", "#e6343a"),
    "present_blue": present("#3f6fd1", "#f2f2f2"),
    "present_big": present("#e6343a", "#ffd84a", size=0.5),
    "bullet": bullet(),
    "cannon_shell": cannon_shell(),
    "muzzle_flash": muzzle_flash(),
    "magic_orb": magic_orb("#b07aff", "#f0dcff"),
    "magic_big": magic_big(),
    "meteor": meteor(),
    "magic_circle": magic_circle(),
    "magic_circle_gold": magic_circle("#ffd36a"),
    "heart_arrow": heart_arrow(),
    "firework_red": firework_shell("#e6343a"),
    "firework_blue": firework_shell("#3f6fd1"),
    "firework_gold": firework_shell("#e8b62c"),
    "plush_bear": plush_bear("#7a5232", "#2f5fb0", 1.6),
}


def main():
    out = {"_memo": "版79：技の小物（tools/make_props.py が作る。手で書きかえない）。scripts/fx/skill_fx.gd が名前で作る。原点が中心、+Z が飛ぶ向き",
           "props": {k: clean(v) for k, v in PROPS.items()}}
    (ROOT / "data/props.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print("props", len(PROPS))


if __name__ == "__main__":
    main()
