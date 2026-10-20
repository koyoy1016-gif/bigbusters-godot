#!/usr/bin/env python3
"""版89：渋谷のマップの看板の絵（自作）を、1枚の画像（512×512）にまとめて作る → assets/maps/shibuya/signs.png
店名・ロゴは、すべてゲームの中だけの自作（本物のお店・ブランドに似せない）。字は Noto Sans CJK（SIL OFL）で描く。
並び（tools/plateau_to_glb.py の ATLAS と同じ）:
  縦長の看板（建物の角から横に出る看板）  64×256 を 8つ（y=0〜255）
  横長の看板（かべ・屋上）              128×64  を 4つ（y=256〜319）
  店の前の帯                          64×32  を 16（y=320〜383。8つ×2段）
  大画面の絵                         128×64  を 8つ（y=384〜511。4つ×2段）※ 大画面のシェーダーが、順に切りかえて映す
使い方: python3 tools/make_signs.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "maps" / "shibuya" / "signs.png"
FONT_B = "/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc"
FONT_R = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"


def font(size, black=True):
    try:
        return ImageFont.truetype(FONT_B if black else FONT_R, size, index=0)
    except OSError:
        return ImageFont.truetype(str(ROOT / "assets" / "fonts" / "NotoSansJP-Regular-subset.ttf"), size)


def center_text(d, box, text, size, fill, black=True, stroke=0, stroke_fill=None, vertical=False):
    x0, y0, x1, y1 = box
    if vertical:
        chars = list(text)
        f = font(size, black)
        hs = [f.getbbox(c) for c in chars]
        total = sum((b[3] - b[1]) for b in hs) + (len(chars) - 1) * size * 0.12
        y = (y0 + y1) / 2 - total / 2
        for c, b in zip(chars, hs):
            w = b[2] - b[0]
            d.text(((x0 + x1) / 2 - w / 2 - b[0], y - b[1]), c, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
            y += (b[3] - b[1]) + size * 0.12
        return
    f = font(size, black)
    b = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
    w, h = b[2] - b[0], b[3] - b[1]
    while w > (x1 - x0) * 0.92 and size > 6:
        size -= 1
        f = font(size, black)
        b = d.textbbox((0, 0), text, font=f, stroke_width=stroke)
        w, h = b[2] - b[0], b[3] - b[1]
    d.text(((x0 + x1) / 2 - w / 2 - b[0], (y0 + y1) / 2 - h / 2 - b[1]), text, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)


# 縦長の看板（店の種類の言葉と、自作の店名）
VERTICAL = [
    ("カラオケ", "#e8304a", "#ffffff"), ("らーめん", "#ffd23a", "#c0161e"), ("くすり", "#1f6fd8", "#ffffff"), ("古着屋", "#111318", "#ffe14a"),
    ("焼肉", "#ff6a1a", "#ffffff"), ("書店", "#ffffff", "#1d3f8f"), ("ゲーム", "#7a2cf0", "#7fffd4"), ("めがね", "#13a35a", "#ffffff"),
]
# 横長の看板（屋上・かべ）
WIDE = [
    ("BIG BUSTERS", "#0e1526", "#ffb84d", "ボス たいじ 4人で！"), ("ねじまき珈琲", "#5a3a22", "#ffe9c8", "COFFEE & BAKE"),
    ("ソラまど電機", "#ffffff", "#1a62d1", "スマホ・ゲーム・家電"), ("まんぷく横丁", "#c0161e", "#ffe14a", "やきとり・おでん・ラーメン"),
]
# 店の前の帯（短い言葉）
FASCIA = [
    ("OPEN", "#16a34a", "#fff"), ("SALE", "#e11d48", "#fff"), ("24h", "#1d4ed8", "#fff"), ("カフェ", "#7c4a2a", "#ffe9c8"),
    ("くすり", "#facc15", "#1d4ed8"), ("100円", "#f97316", "#fff"), ("まんが", "#111827", "#fde047"), ("古着", "#0f766e", "#fff"),
    ("ホテル", "#4c1d95", "#fff"), ("スイーツ", "#f9a8d4", "#831843"), ("ATM", "#0369a1", "#fff"), ("BAR", "#000", "#f472b6"),
    ("靴", "#e5e7eb", "#111"), ("花", "#16a34a", "#fef08a"), ("占い", "#581c87", "#fbcfe8"), ("ゲーム", "#2563eb", "#fde047"),
]


def vertical_sign(img, x, y, w, h, text, bg, fg):
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=bg)
    d.rectangle([x + 2, y + 2, x + w - 3, y + h - 3], outline=fg, width=2)
    d.rectangle([x + 6, y + 8, x + w - 7, y + 22], fill=fg)
    d.rectangle([x + 6, y + h - 23, x + w - 7, y + h - 9], fill=fg)
    center_text(d, (x + 4, y + 26, x + w - 4, y + h - 26), text, 40 if len(text) <= 3 else 36, fg, vertical=True)


def wide_sign(img, x, y, w, h, title, bg, fg, sub):
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=bg)
    d.rectangle([x, y + h - 14, x + w - 1, y + h - 1], fill=fg)
    center_text(d, (x + 4, y + 2, x + w - 4, y + h - 16), title, 26, fg, stroke=1, stroke_fill=bg)
    center_text(d, (x + 4, y + h - 14, x + w - 4, y + h - 1), sub, 10, bg, black=False)


def fascia(img, x, y, w, h, text, bg, fg):
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=bg)
    center_text(d, (x + 3, y + 2, x + w - 3, y + h - 2), text, 20, fg)


def screen_frame(img, x, y, w, h, k):
    """大画面の絵（自作）。k：0〜7"""
    d = ImageDraw.Draw(img)
    pals = [("#ff4d6d", "#4361ee"), ("#06d6a0", "#118ab2"), ("#ffd166", "#ef476f"), ("#7b2ff7", "#f107a3"),
            ("#00b4d8", "#0077b6"), ("#ff9f1c", "#2ec4b6"), ("#e63946", "#1d3557"), ("#80ffdb", "#5390d9")]
    a, b = pals[k % len(pals)]
    for i in range(h):
        t = i / (h - 1)
        ca = tuple(int(int(a[j:j + 2], 16) * (1 - t) + int(b[j:j + 2], 16) * t) for j in (1, 3, 5))
        d.line([(x, y + i), (x + w - 1, y + i)], fill=ca)
    if k == 0:
        center_text(d, (x, y + 4, x + w, y + h - 18), "BIG BUSTERS", 24, "#ffffff", stroke=2, stroke_fill="#1a1a2e")
        center_text(d, (x, y + h - 20, x + w, y + h - 2), "4人で ボスを たおせ！", 12, "#fff3b0")
    elif k == 1:
        # ボスの かげ（自作のボス）と「ボス出現！」
        d.ellipse([x + 14, y + 10, x + 50, y + 46], fill="#1a1a2e")
        d.polygon([(x + 20, y + 14), (x + 16, y + 2), (x + 28, y + 12)], fill="#1a1a2e")
        d.polygon([(x + 44, y + 14), (x + 48, y + 2), (x + 36, y + 12)], fill="#1a1a2e")
        d.rectangle([x + 18, y + 40, x + 46, y + 62], fill="#1a1a2e")
        center_text(d, (x + 52, y + 6, x + w - 4, y + 36), "ボス出現！", 20, "#ffffff", stroke=2, stroke_fill="#7a0010")
        center_text(d, (x + 52, y + 36, x + w - 4, y + 58), "スクランブル交差点", 11, "#ffe14a")
    elif k == 2:
        center_text(d, (x, y + 2, x + w, y + h - 2), "SALE 50%", 28, "#ffffff", stroke=2, stroke_fill="#7a0010")
    elif k == 3:
        for i in range(6):
            d.ellipse([x + 8 + i * 20, y + 20 + (i % 2) * 10, x + 22 + i * 20, y + 34 + (i % 2) * 10], fill="#ffffff")
        center_text(d, (x, y + 44, x + w, y + h - 2), "NEW MUSIC", 14, "#ffffff")
    elif k == 4:
        center_text(d, (x, y + 4, x + w, y + h - 22), "しぶや", 26, "#ffffff", stroke=2, stroke_fill="#023e8a")
        center_text(d, (x, y + h - 22, x + w, y + h - 2), "★ SCRAMBLE ★", 12, "#caf0f8")
    elif k == 5:
        d.ellipse([x + w / 2 - 22, y + 6, x + w / 2 + 22, y + 50], fill="#ffbf69")
        d.ellipse([x + w / 2 - 12, y + 16, x + w / 2 - 4, y + 26], fill="#1a1a2e")
        d.ellipse([x + w / 2 + 4, y + 16, x + w / 2 + 12, y + 26], fill="#1a1a2e")
        d.arc([x + w / 2 - 12, y + 22, x + w / 2 + 12, y + 40], 20, 160, fill="#1a1a2e", width=3)
        center_text(d, (x, y + 48, x + w, y + h - 1), "ねこ まつり", 12, "#ffffff")
    elif k == 6:
        center_text(d, (x, y + 2, x + w, y + h - 2), "4 vs BOSS", 24, "#ffffff", stroke=2, stroke_fill="#000000")
    else:
        center_text(d, (x, y + 2, x + w, y + h - 2), "ソラまど", 26, "#ffffff", stroke=2, stroke_fill="#023e8a")


def main():
    img = Image.new("RGBA", (512, 512), (0, 0, 0, 255))
    for i, (t, bg, fg) in enumerate(VERTICAL):
        vertical_sign(img, i * 64, 0, 64, 256, t, bg, fg)
    for i, (t, bg, fg, sub) in enumerate(WIDE):
        wide_sign(img, i * 128, 256, 128, 64, t, bg, fg, sub)
    for i, (t, bg, fg) in enumerate(FASCIA):
        fascia(img, (i % 8) * 64, 320 + (i // 8) * 32, 64, 32, t, bg, fg)
    for k in range(8):
        screen_frame(img, (k % 4) * 128, 384 + (k // 4) * 64, 128, 64, k)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(OUT, optimize=True)
    print("書いた:", OUT, OUT.stat().st_size, "B")


if __name__ == "__main__":
    main()
