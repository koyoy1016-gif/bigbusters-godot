#!/usr/bin/env python3
"""版85：BGM を計算で作る（自作・CC0扱い）。32000Hz・ステレオ。ffmpeg で Ogg Vorbis にして assets/audio/bgm/ に書く。
曲：lobby（ロビー・夕方の街・96BPM）／battle（ボス戦・第1形態・150BPM。版86で作り直し）／awake（覚醒・166BPM）／win（勝ち・短い）／lose（負け・短い）。
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


# ---------------------------------------------------------------- 戦い（ボス戦）
# 版86：ボス戦らしく作り直した。ニ短調（覚醒はホ短調）。フリギアの♭2（ミ♭）とナポリの和音（E♭）で、こわさと緊張を出す。
# 低い弦の16分のきざみ（ずっと続く）・大太鼓（和太鼓のような低い太鼓）・低い金管の「ぶおっ」・暗い合唱・鐘。
# 24小節のループ：A（8小節：きざみ＋太鼓＋合唱）→ B（8小節：金管の主旋律）→ C（8小節：静かになって、また盛り上がる）
def brass2(f, dur, bright=1.0):
    """低い金管：吹きはじめに明るくなり（倍音がふえる）、少しにごらせる"""
    n = int((dur + 0.22) * SR)
    t = tt(n)
    b = 2.0 + (6.0 * bright) * np.clip(t / 0.08, 0, 1) * np.exp(-np.clip(t - 0.08, 0, None) * 2.5) + 2.5 * bright
    x = np.zeros(n)
    ph = 2 * np.pi * f * t + (0.006 * f / 5.0) * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.3, 0, 1)
    for k in range(1, 26):
        if f * k > SR * 0.45:
            break
        x += np.sin(ph * k) * np.exp(-(k - 1) / b) / k ** 0.6
    x2 = additive(f * 1.003, n, saw_h(10, 1.3)) * 0.25
    e = adsr(n, 0.025, 0.2, 0.75, 0.18, hold=dur)
    return np.tanh((x + x2) * 0.9) * e


def str_stab(f, dur):
    """弦のきざみ（短く、少しざらつく）"""
    n = int((dur + 0.06) * SR)
    x = additive(f, n, saw_h(14, 1.15), detune=0.004) + additive(f, n, saw_h(14, 1.15), detune=-0.004)
    x += rng.standard_normal(n) * 0.02 * np.exp(-tt(n) * 60)
    return x * adsr(n, 0.004, 0.06, 0.55, 0.04, hold=dur)


def taiko(f=58, power=1.0, decay=4.5):
    """和太鼓のような低い太鼓：皮の「どん」＋胴の響き"""
    n = int(1.1 * SR)
    t = tt(n)
    ff = f * (1 + 0.5 * np.exp(-t * 25))
    body = np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t * decay)
    over = np.sin(2 * np.pi * np.cumsum(ff * 2.3) / SR) * np.exp(-t * decay * 2.2) * 0.3
    skin = rng.standard_normal(n) * np.exp(-t * 45) * 0.35
    return np.tanh((body + over + skin) * 1.6) * power


def anvil(f=1480, power=1.0):
    """金属をたたく「かーん」（小節の頭のアクセント）"""
    n = int(0.9 * SR)
    t = tt(n)
    x = sum(np.sin(2 * np.pi * f * r * t) * np.exp(-t * d) * a for r, d, a in [(1.0, 5, 1.0), (2.76, 8, 0.5), (5.4, 14, 0.3), (8.93, 20, 0.15)])
    return x * power


def riser(dur):
    """だんだん上がって大きくなる「ざーっ」（区切りの前）"""
    n = int(dur * SR)
    u = np.linspace(0, 1, n)
    nz = rng.standard_normal(n)
    # 高い所だけ通す（だんだん下の方まで）
    out = np.zeros(n)
    seg = n // 16
    for i in range(16):
        a, b = i * seg, min(n, (i + 1) * seg + 200)
        k = max(2, int(14 - i * 0.8))
        s_ = nz[a:b] - np.convolve(nz[a:b], np.ones(k) / k, mode="same")
        out[a:b] += s_ * np.hanning(b - a) * 1.6
    tone_ = np.sin(2 * np.pi * np.cumsum(220 * 2 ** (u * 2)) / SR) * 0.25
    return (out * 0.5 + tone_) * u ** 2.2


def boss_battle(bpm=150, key=50, intense=False):
    bars = 24
    s = Song(bpm, bars, tail=2.5)
    D = key
    # 和音（D からの半音の差・種類）
    A_prog = [(0, "m"), (0, "m"), (-4, "M"), (-5, "M"), (0, "m"), (5, "m"), (1, "M"), (-5, "M")]          # Dm Dm B♭ A | Dm Gm E♭ A
    B_prog = [(5, "m"), (0, "m"), (1, "M"), (-4, "M"), (5, "m"), (-5, "M"), (0, "m"), (-5, "M")]          # Gm Dm E♭ B♭ | Gm A Dm A
    C_prog = [(0, "m"), (0, "m"), (1, "M"), (1, "M"), (0, "m"), (1, "M"), (-2, "M"), (-5, "M")]           # Dm Dm E♭ E♭ | Dm E♭ C A
    prog = A_prog + B_prog + C_prog
    # 低い弦のきざみ（1小節＝16分音符16個。根音からの差。12＝1オクターブ上、1＝♭2）
    ost = [0, 0, 12, 0, 1, 0, 12, 0, 0, 0, 12, 0, 3, 1, 0, -2]
    for bar, (r, kind) in enumerate(prog):
        sec = "A" if bar < 8 else ("B" if bar < 16 else "C")
        cb = bar - 16  # C の中の小節
        root = D + r - 12  # 低い根音（D3 あたり）
        if root < 45:
            root += 12
        quiet = sec == "C" and cb < 4
        # --- きざみ（低い弦＋ひずんだベース） ---
        for e in range(16):
            off = ost[e]
            if kind == "M" and off == 3:
                off = 4  # 長調の和音の上では、長3度
            if kind == "M" and off == 1 and r != -5:
                off = 0  # ♭2 は、短調の和音と A（属和音）の上だけ（にごりすぎない）
            m = root + off
            acc = 1.0 if e % 4 == 0 else 0.7
            s.add(str_stab(mf(m), 0.09 * s.beat * 2.2), s.at(bar, e * 0.25), (0.05 if quiet else 0.085) * acc, pan=-0.35, rev=0.12)
            s.add(str_stab(mf(m + 12), 0.09 * s.beat * 2.2), s.at(bar, e * 0.25), (0.025 if quiet else 0.04) * acc, pan=0.35, rev=0.12)
            if e % 2 == 0 and not quiet:
                s.add(dist_bass(mf(root - 12 + (0 if off in (0, 12) else off % 12)), 0.4 * s.beat), s.at(bar, e * 0.25), 0.16 if not intense else 0.19, rev=0.02)
        # --- 太鼓 ---
        if quiet:
            for b2 in (0, 2.5):
                s.add(taiko(52, 1.0), s.at(bar, b2), 0.5, pan=-0.2, rev=0.4)
        else:
            for beat in range(4):
                s.add(kick(1.1), s.at(bar, beat), 0.5, rev=0.0)
                if beat in (1, 3):
                    s.add(snare(1.1), s.at(bar, beat), 0.4, pan=0.08, rev=0.35)
            # 和太鼓：1拍目と、3拍目の裏
            s.add(taiko(55, 1.0), s.at(bar, 0), 0.55, pan=-0.25, rev=0.35)
            s.add(taiko(70, 0.8), s.at(bar, 2.5), 0.45, pan=0.25, rev=0.35)
            if intense:
                s.add(taiko(62, 0.8), s.at(bar, 1.5), 0.38, pan=0.4, rev=0.3)
                s.add(taiko(48, 0.9), s.at(bar, 3.5), 0.42, pan=-0.4, rev=0.3)
            for e in range(8 if not intense else 16):
                step = 0.5 if not intense else 0.25
                s.add(hat(power=0.9 if e % 2 == 0 else 0.55), s.at(bar, e * step), 0.1, pan=0.45, rev=0.05)
        # 区切り（4小節ごと）：金属の「かーん」と、低い「どーん」
        if bar % 4 == 0 and not quiet:
            s.add(anvil(1480 if not intense else 1660, 1.0), s.at(bar, 0), 0.06, pan=0.3, rev=0.5)
        if bar % 8 == 0:
            s.add(crash(1.0), s.at(bar, 0), 0.38, pan=-0.15, rev=0.3)
            s.add(taiko(40, 1.2, 2.5), s.at(bar, 0), 0.6, rev=0.5)
        # --- 暗い合唱（1小節の長い和音） ---
        cn = chord_notes(D + r, "m" if kind == "m" else "M")
        for k, m in enumerate(cn):
            mm = m if m >= 57 else m + 12
            s.add(choir(mf(mm), 3.9 * s.beat), s.at(bar, 0), (0.05 if sec != "C" else 0.065) * (1.25 if intense else 1.0), pan=-0.3 + 0.3 * k, rev=0.55)
        # --- 低い金管の「ぶおっ」（A と C の、小節の頭と裏） ---
        if sec in ("A", "C") and not quiet:
            for b2, d in [(0, 0.9), (1.5, 0.4), (2.5, 1.2)] if bar % 2 == 0 else [(0, 1.8), (3.0, 0.8)]:
                for m in (root, root + 7, root + 12):
                    s.add(brass2(mf(m), d * s.beat, 0.9), s.at(bar, b2), 0.035, pan=-0.1 if m == root else 0.2, rev=0.3)
        # --- C の後半：盛り上がり（スネアの連打がだんだん細かく・ざーっと上がる・太鼓のまわし） ---
        if sec == "C" and cb >= 4:
            sub = 0.5 if cb == 4 else (0.25 if cb < 7 else 0.125)
            nn = int(4 / sub)
            for i in range(nn):
                p = (cb - 4 + i / nn) / 4.0
                s.add(snare(0.5 + 0.6 * p), s.at(bar, i * sub), 0.16 + 0.22 * p, pan=0.1, rev=0.25)
        if sec == "C" and cb == 4:
            s.add(riser(4 * 4 * s.beat), s.at(bar, 0), 0.22, rev=0.2)
        if sec == "C" and cb == 7:
            for k2, b2 in enumerate([2.0, 2.5, 3.0, 3.25, 3.5, 3.75]):
                s.add(taiko(90 - k2 * 8, 1.0), s.at(bar, b2), 0.45, pan=-0.5 + k2 * 0.2, rev=0.3)
    # --- 主旋律（B：低い金管＋高い弦のかさね）と、A・C の高い弦ののばし ---
    melB = [
        [(0, 74, 1.5), (1.5, 72, 0.5), (2, 70, 1.0), (3, 67, 1.0)],
        [(0, 69, 2.0), (2, 74, 1.0), (3, 77, 1.0)],
        [(0, 79, 1.5), (1.5, 77, 0.5), (2, 75, 1.0), (3, 70, 1.0)],
        [(0, 74, 2.0), (2, 70, 1.0), (3, 74, 1.0)],
        [(0, 79, 1.5), (1.5, 77, 0.5), (2, 74, 1.0), (3, 70, 1.0)],
        [(0, 73, 1.5), (1.5, 76, 0.5), (2, 81, 2.0)],
        [(0, 77, 1.0), (1, 76, 1.0), (2, 74, 1.0), (3, 69, 1.0)],
        [(0, 73, 2.0), (2, 76, 1.0), (3, 69, 1.0)]]
    sh = key - 50  # 覚醒の時は、まとめて上げる
    for i, notes in enumerate(melB):
        bar = 8 + i
        for b2, m, d in notes:
            s.add(brass2(mf(m - 12 + sh), d * s.beat, 1.1), s.at(bar, b2), 0.11, pan=-0.05, rev=0.35)
            s.add(lead(mf(m + sh), d * s.beat, "brass"), s.at(bar, b2), 0.035 if not intense else 0.05, pan=0.25, rev=0.4)
    # A と C の前半：高い弦の、こわい のばし（D → D → D → C♯ …。E♭ の和音の上だけ E♭）
    top = {0: 74, 1: 74, 2: 74, 3: 73, 4: 74, 5: 74, 6: 75, 7: 73, 16: 74, 17: 74, 18: 75, 19: 75}
    for bar in top:
        s.add(pad(mf(top[bar] + 12 + sh), 3.9 * s.beat), s.at(bar, 0), 0.035, pan=0.4, rev=0.6)
    return s.render(True, 0.9)


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
    # Ogg にすると、山が少し高くなることがある（1.0 をこえると割れる）。もどして測り、こえたら下げて作り直す
    vol = 1.0
    for _ in range(4):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-af", "volume=%.4f" % vol, "-c:a", "libvorbis", "-q:a", str(quality), str(dst)], check=True)
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(dst), "-f", "f32le", "-"], capture_output=True, check=True).stdout
        peak = float(np.max(np.abs(np.frombuffer(raw, dtype=np.float32))))
        if peak <= 0.97:
            break
        vol *= 0.94 / peak
    tmp.unlink()
    print(name, "%.1f 秒" % (len(x) / SR), "%d KB" % (dst.stat().st_size // 1024))


if __name__ == "__main__":
    write("lobby", lobby())
    write("battle", boss_battle(150, 50, False))
    write("awake", boss_battle(166, 52, True))
    write("win", win())
    write("lose", lose())
