#!/usr/bin/env python3
"""効果音を計算で作る（自作・CC0扱い）。22050Hz・モノラル・16bit の WAV を assets/audio/sfx/ に書く。
使い方: python3 tools/make_sfx.py"""
import wave
from pathlib import Path
import numpy as np

SR = 22050
rng = np.random.default_rng(1019)
out = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
out.mkdir(parents=True, exist_ok=True)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, d=0.1, sustain=0.0):
    e = np.ones(n)
    na = max(1, int(a * SR))
    e[:na] = np.linspace(0, 1, na)
    nd = int(d * SR)
    if nd > 0:
        k = np.exp(-np.linspace(0, 6, n - na))
        e[na:] = sustain + (1 - sustain) * k
    return e


def noise(n):
    return rng.standard_normal(n)


def lowpass(x, fc):
    a = np.exp(-2 * np.pi * fc / SR)
    y = np.zeros_like(x)
    p = 0.0
    for i, v in enumerate(x):
        p = (1 - a) * v + a * p
        y[i] = p
    return y


def highpass(x, fc):
    return x - lowpass(x, fc)


def sweep(f0, f1, d):
    tt = t(d)
    f = np.linspace(f0, f1, len(tt))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    x[-50:] *= np.linspace(1, 0, 50)
    with wave.open(str(out / (name + ".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


# 斬る：高めのノイズのしゅっ
n = int(0.22 * SR)
x = highpass(noise(n), 1500) * env(n, 0.01, 0.2)
x *= np.linspace(0.4, 1.0, n) ** 0.5
save("slash", x)
# 当たり：低い「どん」＋ノイズ
n = int(0.18 * SR)
x = sweep(220, 70, 0.18) * env(n, 0.002, 0.18) + 0.5 * lowpass(noise(n), 900) * env(n, 0.001, 0.08)
save("hit", x)
# 自分がダメージ：「ぶっ」と低く鈍い音
n = int(0.3 * SR)
x = sweep(160, 55, 0.3) * env(n, 0.002, 0.3) + 0.6 * lowpass(noise(n), 500) * env(n, 0.001, 0.12)
save("hurt", x)
# ジャンプ：上がるピッ
n = int(0.2 * SR)
x = sweep(300, 700, 0.2) * env(n, 0.005, 0.2)
save("jump", x, 0.6)
# 技：きらっとした音
n = int(0.45 * SR)
x = (sweep(500, 1200, 0.45) + 0.5 * sweep(750, 1800, 0.45)) * env(n, 0.01, 0.45)
save("skill", x, 0.6)
# つかみの予告：ボスのうなり
n = int(0.9 * SR)
x = (sweep(90, 60, 0.9) + 0.6 * sweep(135, 90, 0.9)) * env(n, 0.1, 0.9, 0.2)
save("grab_warn", x)
# つかんだ：ぐしゃっ
n = int(0.35 * SR)
x = lowpass(noise(n), 700) * env(n, 0.002, 0.3) + sweep(120, 50, 0.35) * env(n, 0.002, 0.3)
save("grab", x)
# 助けた／外れた：ぱきん
n = int(0.25 * SR)
x = sweep(900, 400, 0.25) * env(n, 0.001, 0.2) + highpass(noise(n), 2500) * env(n, 0.001, 0.05)
save("free", x, 0.7)
# 台風：うなる風（ゆっくり立ち上がる）
n = int(2.0 * SR)
w = lowpass(noise(n), 700)
am = 0.6 + 0.4 * np.sin(2 * np.pi * 5 * t(2.0))
x = w * am * np.sin(np.linspace(0, np.pi, n)) ** 1.5
save("whoosh", x, 0.8)
# チラシ：ぱさっ
n = int(0.12 * SR)
x = highpass(noise(n), 3000) * env(n, 0.002, 0.12)
save("throw", x, 0.5)
# 必殺技A：ごごご
n = int(1.2 * SR)
x = lowpass(noise(n), 400) * env(n, 0.3, 1.2, 0.3) + 0.5 * sweep(70, 100, 1.2) * env(n, 0.3, 1.2, 0.3)
save("storm", x)
# 必殺技B：ずばーん（なぎはらい）
n = int(0.8 * SR)
x = lowpass(noise(n), 1200) * np.sin(np.linspace(0, np.pi, n)) + 0.5 * sweep(120, 80, 0.8) * np.sin(np.linspace(0, np.pi, n))
save("sweep", x)
# 勝ち：上がる3音
parts = []
for f in (523, 659, 784, 1047):
    n = int(0.16 * SR)
    parts.append(np.sin(2 * np.pi * f * t(0.16)) * env(n, 0.005, 0.16, 0.2))
save("win", np.concatenate(parts), 0.6)
# 負け：下がる音
parts = []
for f in (392, 330, 262, 196):
    n = int(0.22 * SR)
    parts.append(np.sin(2 * np.pi * f * t(0.22)) * env(n, 0.005, 0.22, 0.3))
save("lose", np.concatenate(parts), 0.6)
# ボタン
n = int(0.06 * SR)
save("click", np.sin(2 * np.pi * 880 * t(0.06)) * env(n, 0.002, 0.06), 0.5)
print("ok")
