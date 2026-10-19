#!/usr/bin/env python3
"""質感の画像（256x256、つなぎ目なし、明るさ 0.8〜1.0 の灰色）を assets/textures/ に作る。色は材質の色が掛かる。
使い方: python3 tools/make_textures.py   （自作・CC0 扱い。固定の種なので、毎回同じ画像）"""
import numpy as np
from pathlib import Path
from PIL import Image

N = 256
rng = np.random.default_rng(20261019)
out = Path(__file__).resolve().parent.parent / "assets" / "textures"
out.mkdir(parents=True, exist_ok=True)


def tile_noise(scale):
    """つなぎ目のない、なめらかなノイズ（0〜1）。FFTで低い周波数だけ残す"""
    w = rng.standard_normal((N, N))
    f = np.fft.fft2(w)
    fy = np.fft.fftfreq(N)[:, None]
    fx = np.fft.fftfreq(N)[None, :]
    r = np.sqrt(fx ** 2 + fy ** 2) * N
    f *= np.exp(-(r / scale) ** 2)
    a = np.real(np.fft.ifft2(f))
    a = (a - a.min()) / (a.max() - a.min())
    return a


def save(name, a, lo=0.78, hi=1.0):
    a = np.clip(a, 0, 1)
    v = lo + (hi - lo) * a
    img = Image.fromarray((v * 255).astype(np.uint8), "L").convert("RGB")
    img.save(out / name, optimize=True)


# 布：たて糸とよこ糸の織り目
x = np.arange(N)
warp = (np.sin(x[None, :] * 2 * np.pi / 8) * 0.5 + 0.5)
weft = (np.sin(x[:, None] * 2 * np.pi / 8) * 0.5 + 0.5)
weave = 0.5 * warp + 0.5 * weft
weave = np.where(((x[:, None] // 8 + x[None, :] // 8) % 2) == 0, warp, weft)
save("cloth.png", 0.6 * weave + 0.4 * tile_noise(30))

# 金属：横のブラシ目と、細い傷
streak = tile_noise(40)
b = np.zeros((N, N))
for i in range(N):
    b[i, :] = rng.random()
b = np.roll(b, 0, axis=0)
blur = np.real(np.fft.ifft2(np.fft.fft2(b) * np.exp(-((np.fft.fftfreq(N)[None, :] * N) / 6.0) ** 2)))
blur = (blur - blur.min()) / (blur.max() - blur.min())
steel = 0.5 * blur + 0.5 * streak
for _ in range(40):
    y = rng.integers(0, N)
    x0 = rng.integers(0, N)
    ln = rng.integers(10, 60)
    for k in range(ln):
        steel[(y + k // 6) % N, (x0 + k) % N] *= 0.55
save("steel.png", steel, lo=0.7)

# 肌：ざらっとしたムラ
save("skin.png", 0.65 * tile_noise(18) + 0.35 * tile_noise(70) + 0.08 * rng.standard_normal((N, N)), lo=0.8)

# 革：しわ
l = tile_noise(10)
save("leather.png", 1 - np.abs(l - 0.5) * 2, lo=0.75)
print("ok")
