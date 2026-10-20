#!/usr/bin/env python3
"""版85：BGM を計算で作る（自作・CC0扱い）。32000Hz・ステレオ。ffmpeg で Ogg Vorbis にして assets/audio/bgm/ に書く。
曲：lobby（ロビー・夕方の街・96BPM）／battle（戦い＝ボスの第1形態・148BPM）／awake（覚醒・164BPM）／win（勝ち・短い）／lose（負け・短い）。
ループする曲は、はみ出した音（余韻）を頭にもどして足すので、つなぎ目が自然。
使い方: python3 tools/make_music.py   （ffmpeg が必要）"""
import subprocess
import wave
from pathlib import Path
import numpy as np

SR = 32000
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "bgm"
rng = np.random.default_rng(85)


def mf(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def tt(n):
    return np.arange(n) / SR


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.1, hold=None):
    """n：全体の長さ（release をふくむ）。hold：鳴らしている長さ（秒）"""
    e = np.zeros(n)
    na = max(1, int(a * SR))
    nd = max(1, int(d * SR))
    nh = int((hold if hold is not None else n / SR - r) * SR)
    nh = max(na + 1, min(nh, n))
    e[:na] = np.linspace(0, 1, na)
    k = min(nd, max(0, nh - na))
    e[na:na + k] = np.linspace(1, s, k) if k > 0 else e[na:na + k]
    e[na + k:nh] = s
    nr = n - nh
    if nr > 0:
        e[nh:] = s * np.exp(-np.linspace(0, 6, nr))
    return e


def additive(f, n, harm, vib=0.0, vib_rate=5.5, detune=0.0):
    """倍音を足して作る音（ナイキストより上は入れない）。harm：[(倍数, 大きさ)]"""
    t = tt(n)
    ph = 2 * np.pi * f * t
    if vib > 0:
        ph = ph + (vib * f / vib_rate) * np.sin(2 * np.pi * vib_rate * t) * np.clip(t / 0.25, 0, 1)
    x = np.zeros(n)
    for k, amp in harm:
        if f * k * (1 + detune) < SR * 0.45:
            x += amp * np.sin(ph * k * (1 + detune))
    return x


def saw_h(nh=16, roll=1.0):
    return [(k, 1.0 / (k ** roll)) for k in range(1, nh + 1)]


def sq_h(nh=15):
    return [(k, 1.0 / k) for k in range(1, nh + 1, 2)]


# ---------------------------------------------------------------- 楽器
def ep(f, dur):
    n = int((dur + 0.6) * SR)
    t = tt(n)
    x = additive(f, n, [(1, 1.0), (2, 0.35), (3, 0.12), (4, 0.06)])
    bell = np.sin(2 * np.pi * f * 3.98 * t) * np.exp(-t * 18) * 0.25
    trem = 1 + 0.12 * np.sin(2 * np.pi * 4.8 * t)
    return (x + bell) * adsr(n, 0.004, 0.6, 0.35, 0.5, hold=dur) * trem


def pad(f, dur):
    n = int((dur + 1.0) * SR)
    x = additive(f, n, saw_h(8, 1.4), detune=0.004) + additive(f, n, saw_h(8, 1.4), detune=-0.004)
    return x * adsr(n, 0.35, 0.3, 0.8, 0.9, hold=dur) * 0.5


def bass(f, dur, bright=0.6):
    n = int((dur + 0.12) * SR)
    x = additive(f, n, [(1, 1.0), (2, 0.5 * bright), (3, 0.25 * bright), (4, 0.12 * bright), (5, 0.06 * bright)])
    return x * adsr(n, 0.004, 0.15, 0.75, 0.08, hold=dur)


def dist_bass(f, dur):
    n = int((dur + 0.1) * SR)
    x = additive(f, n, saw_h(10, 1.1))
    return np.tanh(x * 2.2) * adsr(n, 0.003, 0.1, 0.8, 0.07, hold=dur) * 0.8


def lead(f, dur, kind="brass"):
    n = int((dur + 0.25) * SR)
    if kind == "brass":
        x = additive(f, n, saw_h(14, 1.25), vib=0.006)
        e = adsr(n, 0.03, 0.15, 0.85, 0.18, hold=dur)
        # 吹きはじめ、少し明るく
        bright = additive(f, n, [(5, 0.12), (6, 0.08), (7, 0.05)]) * np.exp(-tt(n) * 9)
        return (x + bright) * e
    if kind == "flute":
        x = additive(f, n, [(1, 1.0), (2, 0.12), (3, 0.05)], vib=0.005) + rng.standard_normal(n) * 0.01
        return x * adsr(n, 0.05, 0.1, 0.9, 0.2, hold=dur)
    x = additive(f, n, sq_h(13), vib=0.004)
    return x * adsr(n, 0.01, 0.1, 0.7, 0.12, hold=dur)


def bell(f, dur):
    n = int((dur + 1.4) * SR)
    t = tt(n)
    x = np.sin(2 * np.pi * f * t + 1.6 * np.exp(-t * 3) * np.sin(2 * np.pi * f * 3.5 * t))
    return x * np.exp(-t * 2.6) * adsr(n, 0.002, 0.1, 1.0, 0.1, hold=dur + 1.3)


def choir(f, dur):
    n = int((dur + 0.6) * SR)
    x = sum(additive(f, n, [(1, 1.0), (2, 0.5), (3, 0.6), (4, 0.15), (5, 0.25)], vib=0.007, detune=d) for d in (-0.006, 0.0, 0.006))
    return x * adsr(n, 0.08, 0.2, 0.8, 0.4, hold=dur) * 0.4


def stab(f, dur):
    n = int((dur + 0.08) * SR)
    x = additive(f, n, saw_h(12, 1.0), detune=0.003) + additive(f * 1.4983, n, saw_h(10, 1.0)) * 0.7
    return x * adsr(n, 0.002, 0.08, 0.4, 0.05, hold=dur)


def kick(power=1.0):
    n = int(0.42 * SR)
    t = tt(n)
    f = 45 + 120 * np.exp(-t * 28)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5)
    click = rng.standard_normal(n) * np.exp(-t * 400) * 0.3
    return (x + click) * power


def snare(power=1.0, rim=False):
    n = int(0.25 * SR)
    t = tt(n)
    if rim:
        x = np.sin(2 * np.pi * 820 * t) * np.exp(-t * 60) + rng.standard_normal(n) * np.exp(-t * 90) * 0.4
        return x * 0.6 * power
    nz = rng.standard_normal(n)
    nz = nz - np.convolve(nz, np.ones(6) / 6, mode="same")  # 高いところだけ
    x = nz * np.exp(-t * 16) * 0.9 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 22) * 0.6
    return x * power


def hat(open_=False, power=1.0):
    n = int((0.22 if open_ else 0.05) * SR)
    t = tt(n)
    nz = rng.standard_normal(n)
    nz = nz - np.convolve(nz, np.ones(3) / 3, mode="same")
    return nz * np.exp(-t * (12 if open_ else 80)) * 0.35 * power


def tom(f=110, power=1.0):
    n = int(0.5 * SR)
    t = tt(n)
    ff = f * (1 + 0.6 * np.exp(-t * 18))
    x = np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * 6.5)
    return (x + rng.standard_normal(n) * np.exp(-t * 60) * 0.2) * power


def crash(power=1.0):
    n = int(2.2 * SR)
    t = tt(n)
    nz = rng.standard_normal(n)
    nz = nz - np.convolve(nz, np.ones(4) / 4, mode="same")
    return nz * np.exp(-t * 2.2) * 0.35 * power


# ---------------------------------------------------------------- 曲の組み立て
class Song:
    def __init__(self, bpm, bars, tail=2.5):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.len = int(bars * 4 * self.beat * SR)
        self.buf = np.zeros((self.len + int(tail * SR), 2))
        self.verb = np.zeros_like(self.buf)

    def at(self, bar, beat):
        return int((bar * 4 + beat) * self.beat * SR)

    def add(self, x, pos, gain=1.0, pan=0.0, rev=0.15):
        end = min(pos + len(x), len(self.buf))
        if pos >= end:
            return
        seg = x[:end - pos] * gain
        l = np.cos((pan + 1) * np.pi / 4)
        r = np.sin((pan + 1) * np.pi / 4)
        self.buf[pos:end, 0] += seg * l
        self.buf[pos:end, 1] += seg * r
        if rev > 0:
            self.verb[pos:end, 0] += seg * l * rev
            self.verb[pos:end, 1] += seg * r * rev

    def render(self, loop=True, master=0.9):
        # かんたんな残響（遅れた音を何回か、左右で少しずらして足す）
        wet = np.zeros_like(self.buf)
        for i, (dl, g) in enumerate([(0.029, 0.6), (0.047, 0.5), (0.071, 0.42), (0.113, 0.33), (0.167, 0.25), (0.241, 0.18), (0.353, 0.12)]):
            d = int(dl * SR)
            ch = i % 2
            wet[d:, ch] += self.verb[:-d, ch] * g
            wet[d + int(0.011 * SR):, 1 - ch] += self.verb[:-(d + int(0.011 * SR)), 1 - ch] * g * 0.8
        x = self.buf + wet
        if loop:
            tail = x[self.len:]
            x = x[:self.len].copy()
            x[:len(tail)] += tail  # 余韻を頭へ（つなぎ目が自然）
        x = np.tanh(x * 1.1)
        x = x / (np.max(np.abs(x)) + 1e-9) * master
        if not loop:
            x[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))[:, None]
        return x


def chord_notes(root, kind):
    iv = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "7sus4": [0, 5, 7, 10], "m": [0, 3, 7], "M": [0, 4, 7], "5": [0, 7, 12]}[kind]
    return [root + i for i in iv]


# ---------------------------------------------------------------- ロビー
def lobby():
    s = Song(96, 16)
    prog = [(58, "maj7"), (57, "m7"), (55, "m7"), (60, "7sus4"), (53, "maj7"), (50, "m7"), (55, "m7"), (60, "7"),
            (58, "maj7"), (57, "7"), (50, "m7"), (48, "m7"), (58, "maj7"), (60, "7"), (53, "maj7"), (53, "maj7")]
    for bar, (root, kind) in enumerate(prog):
        notes = chord_notes(root, kind)
        for beat, dur in [(0, 1.3), (1.5, 0.4), (2.5, 1.2)]:
            for k, m in enumerate(notes):
                s.add(ep(mf(m + 12 if m < 55 else m), dur * s.beat), s.at(bar, beat), 0.09, pan=-0.3 + 0.2 * k, rev=0.35)
        s.add(pad(mf(notes[0] + 12), 4 * s.beat), s.at(bar, 0), 0.05, pan=0.0, rev=0.5)
        s.add(pad(mf(notes[2] + 12), 4 * s.beat), s.at(bar, 0), 0.04, pan=0.4, rev=0.5)
        b = root - 24 if root - 24 >= 26 else root - 12
        for beat, m, dur in [(0, b, 0.9), (1.5, b, 0.4), (2, b + 7, 0.9), (3.5, b + 12 if bar % 2 else b + 5, 0.4)]:
            s.add(bass(mf(m), dur * s.beat, 0.5), s.at(bar, beat), 0.32, rev=0.05)
        for beat in range(4):
            if beat in (0, 2) or (beat == 3 and bar % 4 == 3):
                s.add(kick(0.8), s.at(bar, beat + (0.5 if beat == 3 else 0)), 0.5, rev=0.0)
            if beat in (1, 3):
                s.add(snare(0.8, rim=True), s.at(bar, beat), 0.35, pan=0.15, rev=0.25)
        for e in range(8):
            sw = 0.06 if e % 2 else 0.0
            s.add(hat(power=0.9 if e % 2 == 0 else 0.6), s.at(bar, e * 0.5 + sw), 0.22, pan=0.35, rev=0.1)
    # 旋律（後半はベル、前半は笛で静かに）
    mel = [
        [(0, 77, 1.5), (1.5, 76, 0.5), (2, 74, 1.0), (3, 72, 1.0)], [(0, 72, 1.0), (1, 74, 0.5), (1.5, 76, 2.0)],
        [(0, 74, 1.5), (1.5, 72, 0.5), (2, 70, 2.0)], [(0, 72, 3.0)],
        [(0, 81, 1.5), (1.5, 79, 0.5), (2, 77, 1.0), (3, 76, 1.0)], [(0, 74, 1.0), (1, 76, 0.5), (1.5, 77, 2.0)],
        [(0, 79, 1.0), (1, 77, 1.0), (2, 74, 2.0)], [(0, 72, 2.0), (2.5, 74, 0.5), (3, 76, 1.0)],
        [(0, 77, 1.0), (1, 81, 1.0), (2, 79, 1.0), (3, 77, 0.5), (3.5, 76, 0.5)], [(0, 76, 1.5), (1.5, 73, 0.5), (2, 76, 2.0)],
        [(0, 74, 1.0), (1, 77, 1.0), (2, 81, 1.5), (3.5, 79, 0.5)], [(0, 79, 2.0), (2, 77, 1.0), (3, 75, 1.0)],
        [(0, 74, 1.0), (1, 77, 1.0), (2, 82, 1.5), (3.5, 81, 0.5)], [(0, 79, 1.0), (1, 76, 1.0), (2, 72, 2.0)],
        [(0, 77, 2.0), (2, 76, 1.0), (3, 72, 1.0)], [(0, 77, 3.5)]]
    for bar, notes in enumerate(mel):
        for beat, m, dur in notes:
            if bar < 8:
                s.add(lead(mf(m), dur * s.beat, "flute"), s.at(bar, beat), 0.10, pan=-0.15, rev=0.45)
            else:
                s.add(bell(mf(m), dur * s.beat), s.at(bar, beat), 0.13, pan=-0.1, rev=0.5)
                s.add(lead(mf(m - 12), dur * s.beat, "flute"), s.at(bar, beat), 0.05, pan=0.2, rev=0.4)
    return s.render(True, 0.85)


# ---------------------------------------------------------------- 戦い（ボスの第1形態）
def battle(bpm=148, key=50, intense=False):
    s = Song(bpm, 16, tail=2.0)
    # i - VI - VII - V を2回、iv - VI - VII - i、VI - VII - V - V
    rel = [(0, "m"), (-4, "M"), (-2, "M"), (-5, "M"), (0, "m"), (-4, "M"), (-2, "M"), (-5, "M"),
           (5, "m"), (-4, "M"), (-2, "M"), (0, "m"), (-4, "M"), (-2, "M"), (-5, "M"), (-5, "M")]
    for bar, (r, kind) in enumerate(rel):
        root = key + r
        bnote = root - 12 if root - 12 >= 33 else root
        # ベース：8分で、オクターブを行き来する
        for e in range(8):
            m = bnote + (12 if e % 2 else 0) if not intense else bnote + (12 if e in (3, 7) else 0)
            f = dist_bass if intense else bass
            s.add(f(mf(m), 0.45 * s.beat) if intense else bass(mf(m), 0.45 * s.beat, 0.9), s.at(bar, e * 0.5), 0.3 if not intense else 0.26, rev=0.03)
        # パワーコード：裏拍で切る
        for e in range(8):
            if e % 2 == 1 or (intense and e in (0, 4)):
                for m in chord_notes(root + 12, "5"):
                    s.add(stab(mf(m), 0.3 * s.beat), s.at(bar, e * 0.5), 0.05, pan=-0.45 if m % 2 else 0.45, rev=0.15)
        # 太鼓
        for beat in range(4):
            s.add(kick(1.0), s.at(bar, beat), 0.55, rev=0.0)
            if beat in (1, 3):
                s.add(snare(1.0), s.at(bar, beat), 0.42, pan=0.1, rev=0.3)
            if intense:
                s.add(tom(70 if beat % 2 == 0 else 90, 0.9), s.at(bar, beat + 0.5), 0.3, pan=-0.3, rev=0.25)
        for e in range(16):
            s.add(hat(open_=(e % 8 == 6), power=1.0 if e % 4 == 0 else 0.6), s.at(bar, e * 0.25), 0.16, pan=0.4, rev=0.05)
        if bar % 8 == 7:
            for k, b2 in enumerate([2.0, 2.5, 3.0, 3.25, 3.5, 3.75]):
                s.add(tom(140 - k * 14, 1.0), s.at(bar, b2), 0.35, pan=-0.5 + k * 0.2, rev=0.3)
        if bar % 8 == 0:
            s.add(crash(0.9), s.at(bar, 0), 0.4, pan=0.2, rev=0.2)
        # アルペジオ（16分。小さく）
        arp = chord_notes(root + 24, "m" if kind == "m" else "M")
        for e in range(16):
            m = arp[[0, 1, 2, 1][e % 4]] + (12 if (e // 4) % 2 and intense else 0)
            s.add(lead(mf(m), 0.22 * s.beat, "square"), s.at(bar, e * 0.25), 0.035, pan=0.5 if e % 2 else -0.5, rev=0.2)
        if intense:
            for m in chord_notes(root + 12, "m" if kind == "m" else "M"):
                s.add(choir(mf(m), 3.8 * s.beat), s.at(bar, 0), 0.06, pan=0.0, rev=0.5)
    # 旋律（勇ましい金管）
    k = key + 12
    mel = [
        [(0, 0, 1.5), (1.5, 2, 0.5), (2, 3, 1.0), (3, 5, 1.0)], [(0, 7, 2.0), (2, 5, 1.0), (3, 3, 1.0)],
        [(0, 5, 1.5), (1.5, 3, 0.5), (2, 2, 1.0), (3, 0, 1.0)], [(0, 2, 2.0), (2, -3, 2.0)],
        [(0, 0, 1.5), (1.5, 2, 0.5), (2, 3, 1.0), (3, 7, 1.0)], [(0, 12, 2.0), (2, 10, 1.0), (3, 8, 1.0)],
        [(0, 10, 1.0), (1, 7, 1.0), (2, 5, 1.0), (3, 7, 1.0)], [(0, 4, 3.0), (3, 7, 1.0)],
        [(0, 8, 1.5), (1.5, 7, 0.5), (2, 5, 1.0), (3, 3, 1.0)], [(0, 5, 1.0), (1, 3, 1.0), (2, 0, 2.0)],
        [(0, 2, 1.0), (1, 3, 1.0), (2, 5, 1.0), (3, 7, 1.0)], [(0, 10, 2.0), (2, 12, 2.0)],
        [(0, 12, 1.5), (1.5, 10, 0.5), (2, 8, 1.0), (3, 7, 1.0)], [(0, 10, 1.5), (1.5, 8, 0.5), (2, 7, 2.0)],
        [(0, 7, 1.0), (1, 4, 1.0), (2, 2, 1.0), (3, 4, 1.0)], [(0, 7, 3.0)]]
    for bar, notes in enumerate(mel):
        for beat, d, dur in notes:
            s.add(lead(mf(k + d), dur * s.beat, "brass"), s.at(bar, beat), 0.085 if not intense else 0.08, pan=-0.05, rev=0.3)
            if intense:
                s.add(lead(mf(k + d + 12), dur * s.beat, "square"), s.at(bar, beat), 0.025, pan=0.3, rev=0.3)
    return s.render(True, 0.88)


# ---------------------------------------------------------------- 勝ち・負け
def win():
    s = Song(140, 3, tail=3.0)
    for i, m in enumerate([60, 64, 67, 72, 76, 79]):
        s.add(lead(mf(m), 0.16, "brass"), int(i * 0.09 * SR), 0.12, pan=-0.3 + i * 0.12, rev=0.3)
    hit = int(0.62 * SR)
    for m in [48, 60, 64, 67, 72, 76]:
        s.add(lead(mf(m), 2.2, "brass"), hit, 0.08, rev=0.45)
        s.add(choir(mf(m + 12), 2.4), hit, 0.05, rev=0.6)
    s.add(kick(1.2), hit, 0.6, rev=0.0)
    s.add(crash(1.2), hit, 0.5, rev=0.3)
    s.add(tom(90, 1.0), int(0.45 * SR), 0.4)
    s.add(tom(120, 1.0), int(0.53 * SR), 0.4)
    for i, m in enumerate([84, 88, 91, 96, 91, 96]):
        s.add(bell(mf(m), 0.3), hit + int((0.15 + i * 0.12) * SR), 0.06, pan=0.4 - i * 0.15, rev=0.6)
    x = s.render(False, 0.9)
    return x[:int(4.6 * SR)]


def lose():
    s = Song(70, 3, tail=3.0)
    for i, (m, d) in enumerate([(76, 0.5), (74, 0.5), (72, 0.5), (71, 0.6), (69, 1.8)]):
        s.add(lead(mf(m), d, "flute"), int(sum([0.55, 0.55, 0.55, 0.65][:i]) * SR), 0.12, rev=0.5)
    for m in [45, 52, 57, 60, 64]:
        s.add(pad(mf(m), 3.4), 0, 0.06, rev=0.6)
    s.add(tom(60, 1.0), int(2.25 * SR), 0.5, rev=0.3)
    x = s.render(False, 0.8)
    x = x[:int(4.6 * SR)]
    x[-int(1.2 * SR):] *= np.linspace(1, 0, int(1.2 * SR))[:, None]
    return x


def write(name, x, quality=4):
    OUT.mkdir(parents=True, exist_ok=True)
    tmp = OUT / (name + ".tmp.wav")
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    dst = OUT / (name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", str(quality), str(dst)], check=True)
    tmp.unlink()
    print(name, "%.1f 秒" % (len(x) / SR), "%d KB" % (dst.stat().st_size // 1024))


if __name__ == "__main__":
    write("lobby", lobby())
    write("battle", battle())
    write("awake", battle(164, 52, True))
    write("win", win())
    write("lose", lose())
