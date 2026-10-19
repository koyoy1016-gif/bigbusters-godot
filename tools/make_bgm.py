#!/usr/bin/env python3
"""メニュー用のBGMを計算で作る（自作・CC0扱い）。22050Hz・モノラル・16bit の WAV を assets/audio/bgm/ に書く。
8小節（120BPMで16秒）の短いループ。最後が最初につながるように作る。
使い方: python3 tools/make_bgm.py"""
import wave
from pathlib import Path
import numpy as np

SR = 22050
BPM = 120
BEAT = 60.0 / BPM
out = Path(__file__).resolve().parent.parent / "assets" / "audio" / "bgm"
out.mkdir(parents=True, exist_ok=True)

# 和音ごとの根音（MIDI番号）。Am・F・C・G・Am・F・G・Am
ROOTS = [45, 41, 48, 43, 45, 41, 43, 45]

# メロディ（MIDI番号, 拍）。1小節ごとに4拍。A短調ペンタトニック中心
MELODY_BARS = [
    [(76, 1), (72, 0.5), (69, 0.5), (72, 1), (74, 1)],
    [(76, 2), (72, 1), (69, 1)],
    [(72, 1), (76, 1), (79, 2)],
    [(79, 1), (76, 1), (74, 2)],
    [(81, 1), (79, 1), (76, 1), (72, 1)],
    [(72, 2), (69, 1), (72, 1)],
    [(74, 1), (79, 1), (76, 2)],
    [(69, 2), (72, 1), (69, 1)],
]


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def tone(freq, dur, wave_kind="square", release=0.06):
    n = int(SR * dur)
    t = np.arange(n) / SR
    if wave_kind == "square":
        # 角のある音を、少しやわらげる
        s = np.tanh(2.0 * np.sin(2 * np.pi * freq * t))
    else:
        s = np.sin(2 * np.pi * freq * t)
    env = np.ones(n)
    na = max(1, int(0.008 * SR))
    env[:na] = np.linspace(0, 1, na)
    nr = min(n, int(release * SR))
    env[n - nr:] *= np.linspace(1, 0, nr)
    return s * env


def kick(dur=0.18):
    n = int(SR * dur)
    t = np.arange(n) / SR
    f = 110 * np.exp(-t * 18) + 40
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * np.exp(-t * 14)


def hat(rng, dur=0.05):
    n = int(SR * dur)
    t = np.arange(n) / SR
    return rng.standard_normal(n) * np.exp(-t * 90) * 0.5


def place(buf, sig, start_sec):
    i = int(round(start_sec * SR))
    end = min(len(buf), i + len(sig))
    buf[i:end] += sig[: end - i]


def main():
    total_sec = 8 * 4 * BEAT
    total_n = int(round(total_sec * SR))
    buf = np.zeros(total_n)
    rng = np.random.default_rng(1019)

    # 旋律
    beat_pos = 0.0
    for bar in MELODY_BARS:
        for note, beats in bar:
            sig = tone(midi_hz(note), beats * BEAT * 0.92, "square")
            place(buf, sig * 0.22, beat_pos * BEAT)
            beat_pos += beats

    # ベース（各拍、根音。少し低いサイン波）
    for bar_i, root in enumerate(ROOTS):
        for b in range(4):
            start = (bar_i * 4 + b) * BEAT
            sig = tone(midi_hz(root), BEAT * 0.9, "sine", release=0.04)
            place(buf, sig * 0.28, start)

    # ドラム：キックは1拍目と3拍目、ハイハットは8分音符ごと
    kick_sig = kick()
    for bar_i in range(8):
        for b in (0, 2):
            place(buf, kick_sig * 0.45, (bar_i * 4 + b) * BEAT)
        for e in range(8):
            place(buf, hat(rng) * (0.5 if e % 2 else 0.8) * 0.12, (bar_i * 8 + e) * BEAT / 2)

    # 大きさをそろえる（ピークを 0.6 まで）
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf = buf / peak * 0.6
    pcm = (buf * 32767).astype("<i2")

    path = out / "menu.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("書いた:", path, "長さ(秒):", round(total_n / SR, 3), "バイト:", path.stat().st_size)


if __name__ == "__main__":
    main()
