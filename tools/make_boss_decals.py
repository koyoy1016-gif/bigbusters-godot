#!/usr/bin/env python3
"""ボスの模様の画像を計算で描く（自作・CC0扱い）。assets/textures/boss/ に書く。
- tiger.png：スカジャンの背中のトラの顔（図形の組み合わせで描いた自作の図案）
- yoi.png：はちまきの「酔」（同梱の Noto Sans JP で書く）
- sake.png：酒びんのラベルの「酒」
使い方: python3 tools/make_boss_decals.py"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "textures" / "boss"
FONT = ROOT / "assets" / "fonts" / "NotoSansJP-Regular-subset.ttf"
OUT.mkdir(parents=True, exist_ok=True)


def tiger(size=256):
    s = 4  # 大きく描いてから縮める（ふちをなめらかに）
    W = size * s
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = W / 2, W / 2 + 10 * s
    orange = (232, 138, 36, 255)
    dark = (25, 18, 20, 255)
    white = (246, 240, 228, 255)
    # 金の丸い縁どり
    d.ellipse([8 * s, 8 * s, W - 8 * s, W - 8 * s], fill=(214, 168, 60, 255))
    d.ellipse([16 * s, 16 * s, W - 16 * s, W - 16 * s], fill=(30, 30, 40, 255))
    # 耳
    for sx in (-1, 1):
        ex = cx + sx * 70 * s
        d.ellipse([ex - 30 * s, cy - 100 * s, ex + 30 * s, cy - 40 * s], fill=orange, outline=dark, width=4 * s)
        d.ellipse([ex - 15 * s, cy - 85 * s, ex + 15 * s, cy - 55 * s], fill=(240, 200, 170, 255))
    # 顔
    d.ellipse([cx - 92 * s, cy - 80 * s, cx + 92 * s, cy + 78 * s], fill=orange, outline=dark, width=5 * s)
    # しま模様
    for sx in (-1, 1):
        for k in range(3):
            y = cy - 50 * s + k * 26 * s
            x0 = cx + sx * 92 * s
            x1 = cx + sx * (60 - k * 6) * s
            d.polygon([(x0, y - 6 * s), (x1, y + 2 * s), (x0, y + 10 * s)], fill=dark)
    for k in range(3):
        y = cy - 72 * s + k * 14 * s
        w = (26 - k * 6) * s
        d.polygon([(cx - w, y), (cx + w, y), (cx, y + 10 * s)], fill=dark)
    # ほお・口のまわり（白）
    d.ellipse([cx - 62 * s, cy + 2 * s, cx + 2 * s, cy + 66 * s], fill=white)
    d.ellipse([cx - 2 * s, cy + 2 * s, cx + 62 * s, cy + 66 * s], fill=white)
    # 目（きつい、黄色）
    for sx in (-1, 1):
        ex = cx + sx * 38 * s
        d.polygon([(ex - sx * 26 * s, cy - 26 * s), (ex + sx * 22 * s, cy - 18 * s), (ex - sx * 6 * s, cy - 6 * s)], fill=(250, 214, 60, 255), outline=dark)
        d.ellipse([ex - 5 * s, cy - 22 * s, ex + 5 * s, cy - 10 * s], fill=dark)
    # 鼻
    d.polygon([(cx - 16 * s, cy - 2 * s), (cx + 16 * s, cy - 2 * s), (cx, cy + 14 * s)], fill=(60, 30, 30, 255))
    # 開いた口（赤）と牙
    d.ellipse([cx - 36 * s, cy + 18 * s, cx + 36 * s, cy + 72 * s], fill=(180, 30, 40, 255), outline=dark, width=3 * s)
    for sx in (-1, 1):
        fx = cx + sx * 20 * s
        d.polygon([(fx - 7 * s, cy + 22 * s), (fx + 7 * s, cy + 22 * s), (fx, cy + 44 * s)], fill=white)
        d.polygon([(fx - 6 * s, cy + 68 * s), (fx + 6 * s, cy + 68 * s), (fx, cy + 52 * s)], fill=white)
    return im.resize((size, size), Image.LANCZOS)


def kanji(ch, size=128, fg=(20, 16, 20, 255), bg=(246, 242, 232, 255), ring=None):
    s = 4
    W = size * s
    im = Image.new("RGBA", (W, W), bg)
    d = ImageDraw.Draw(im)
    if ring:
        d.ellipse([10 * s, 10 * s, W - 10 * s, W - 10 * s], outline=ring, width=6 * s)
    font = ImageFont.truetype(str(FONT), int(W * (0.52 if ring else 0.68)))
    box = d.textbbox((0, 0), ch, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((W - w) / 2 - box[0], (W - h) / 2 - box[1]), ch, font=font, fill=fg)
    return im.resize((size, size), Image.LANCZOS)


def main():
    tiger().save(OUT / "tiger.png")
    kanji("酔", ring=(20, 16, 20, 255)).save(OUT / "yoi.png")
    kanji("酒").save(OUT / "sake.png")
    for f in ("tiger.png", "yoi.png", "sake.png"):
        print("書いた:", OUT / f, (OUT / f).stat().st_size, "バイト")


if __name__ == "__main__":
    main()
