#!/usr/bin/env python3
"""参考画像（上）と、作ったモデルの8方向の画像（下）を、1枚に並べる（docs/ref/chars/<id>_compare.jpg）。
使い方: python3 tools/compare_look.py キャラのid 参考画像 モデルの画像"""
import sys
from PIL import Image

cid, ref, shot = sys.argv[1:4]
a = Image.open(ref).convert("RGB")
b = Image.open(shot).convert("RGB")
w = 1200
a = a.resize((w, int(a.height * w / a.width)))
b = b.resize((w, int(b.height * w / b.width)))
out = Image.new("RGB", (w, a.height + b.height), (255, 255, 255))
out.paste(a, (0, 0))
out.paste(b, (0, a.height))
out.save(f"docs/ref/chars/{cid}_compare.jpg", quality=72)
print("saved", f"docs/ref/chars/{cid}_compare.jpg", out.size)
