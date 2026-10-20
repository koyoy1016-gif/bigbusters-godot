#!/usr/bin/env python3
"""効果音を計算で作る（自作・CC0扱い）。24000Hz・モノラル。assets/audio/sfx/ に書く。
短い音（0.45秒まで）は WAV、長い音は Ogg Vorbis（ファイルを小さくする。ffmpeg が必要）。
版85：ほぼ全部を作り直した（フィルターを scipy に。当たりの「芯」と「キレ」を分けて重ねる）。新しい音も足した。
使い方: python3 tools/make_sfx.py"""
import subprocess
import wave
from pathlib import Path
import numpy as np
from scipy import signal

SR = 24000
OGG_FROM_SEC = 0.45
rng = np.random.default_rng(2085)
out = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"
out.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------- 部品
def n_of(d):
    return int(SR * d)


def t(d):
    return np.arange(n_of(d)) / SR


def noise(n):
    return rng.standard_normal(n)


def _sos(kind, f, order=2):
    nyq = SR / 2
    if isinstance(f, (list, tuple)):
        w = [min(max(x / nyq, 1e-4), 0.999) for x in f]
    else:
        w = min(max(f / nyq, 1e-4), 0.999)
    return signal.butter(order, w, btype=kind, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x)


def sweep_bp(x, f0, f1, q=1.6, steps=24):
    """中心の高さが f0 → f1 に動く帯域フィルター（区切って、なめらかにつなぐ）"""
    n = len(x)
    y = np.zeros(n)
    edges = np.linspace(0, n, steps + 1).astype(int)
    win_len = max(2, (edges[1] - edges[0]) * 2)
    for i in range(steps):
        fc = f0 * (f1 / f0) ** (i / max(1, steps - 1))
        lo, hi = fc / (1 + 1 / q), fc * (1 + 1 / q)
        a, b2 = max(0, edges[i] - win_len // 4), min(n, edges[i + 1] + win_len // 4)
        seg = bp(x[max(0, a - 400):b2], lo, min(hi, SR * 0.45))[a - max(0, a - 400):]
        w = np.ones(b2 - a)
        fade = min(win_len // 4, len(w) // 2)
        if fade > 0:
            w[:fade] = np.linspace(0, 1, fade)
            w[-fade:] = np.linspace(1, 0, fade)
        y[a:b2] += seg[:b2 - a] * w
    return y


def dec(n, rate):
    """指数で消える（rate：1秒で e^-rate）"""
    return np.exp(-np.arange(n) / SR * rate)


def att(n, sec):
    e = np.ones(n)
    k = max(1, min(n, n_of(sec)))
    e[:k] = np.linspace(0, 1, k)
    return e


def hump(n, peak=0.3, p=1.0):
    """0 → 1 → 0 の山。peak：山の位置（0〜1）"""
    u = np.linspace(0, 1, n)
    e = np.where(u < peak, u / max(peak, 1e-6), (1 - u) / max(1 - peak, 1e-6))
    return np.clip(e, 0, 1) ** p


def tone(f0, f1, d, curve=1.0):
    """f0 → f1 に音程が変わるサイン波（curve>1 で早く下がる）"""
    n = n_of(d)
    u = np.linspace(0, 1, n) ** (1 / curve)
    f = f0 * (f1 / f0) ** u if f0 > 0 and f1 > 0 else np.linspace(f0, f1, n)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def fm_bell(f, d, ratio=3.5, index=2.2, decay=4.0):
    tt = t(d)
    e = np.exp(-tt * decay)
    return np.sin(2 * np.pi * f * tt + index * e * np.sin(2 * np.pi * f * ratio * tt)) * e


def saw(f, d, nh=20):
    tt = t(d)
    ph = 2 * np.pi * np.cumsum(np.full(len(tt), f) if np.isscalar(f) else f) / SR
    x = np.zeros(len(tt))
    f_max = f if np.isscalar(f) else np.max(f)
    for k in range(1, nh + 1):
        if f_max * k > SR * 0.45:
            break
        x += np.sin(ph * k) / k
    return x


def pluck(f, d, damp=0.996):
    """弦をはじいた音（Karplus-Strong）"""
    n = n_of(d)
    p = max(2, int(SR / f))
    buf = noise(p) * 0.8
    y = np.zeros(n)
    for i in range(n):
        y[i] = buf[i % p]
        buf[i % p] = damp * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return y


def crackle(d, rate=60, decay=8.0):
    """ぱちぱち（ばらばらの小さなはじけ）"""
    n = n_of(d)
    x = np.zeros(n)
    k = int(rate * d)
    for _ in range(k):
        i = rng.integers(0, max(1, n - 200))
        L = rng.integers(40, 160)
        x[i:i + L] += noise(L) * dec(L, 900) * rng.uniform(0.3, 1.0)
    return hp(x, 1500) * dec(n, decay)


def verb(x, mix=0.25, room=0.6):
    """かんたんな残響（くし形フィルター4つ＋全域通過2つ）"""
    n = len(x)
    pad = np.concatenate([x, np.zeros(n_of(0.6 * room + 0.2))])
    acc = np.zeros(len(pad))
    for dl, g in [(0.0297, 0.77), (0.0371, 0.75), (0.0411, 0.73), (0.0437, 0.71)]:
        d = n_of(dl * (0.6 + room))
        y = np.zeros(len(pad))
        for i in range(0, len(pad), d):
            seg = pad[i:i + d].copy()
            if i >= d:
                seg += y[i - d:i - d + len(seg)] * g * room / 0.6 * 0.95
            y[i:i + len(seg)] = seg
        acc += y
    for dl, g in [(0.005, 0.7), (0.0017, 0.7)]:
        d = n_of(dl)
        b = np.zeros(d + 1)
        b[0], b[-1] = -g, 1
        a = np.zeros(d + 1)
        a[0], a[-1] = 1, -g
        acc = signal.lfilter(b, a, acc)
    acc = lp(acc, 6000)
    return pad * (1 - mix) + acc * mix * 0.35


def fit(x, d):
    n = n_of(d)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*parts):
    n = max(len(p) for p in parts)
    y = np.zeros(n)
    for p in parts:
        y[:len(p)] += p
    return y


def at(x, sec, total):
    """x を sec 秒の所に置いた、total 秒の音"""
    y = np.zeros(n_of(total))
    i = n_of(sec)
    k = min(len(x), len(y) - i)
    if k > 0:
        y[i:i + k] += x[:k]
    return y


def save(name, x, gain=0.85, sat=0.0):
    if sat > 0:
        x = np.tanh(x * (1 + sat)) / np.tanh(1 + sat)
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    f = min(len(x) // 4, n_of(0.004))
    x[-f:] *= np.linspace(1, 0, f)
    x[:8] *= np.linspace(0, 1, 8)
    as_ogg = len(x) / SR > OGG_FROM_SEC
    wav_path = out / (name + ".wav")
    ogg_path = out / (name + ".ogg")
    tmp = out / (name + ".tmp.wav") if as_ogg else wav_path
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    if as_ogg:
        # Ogg にすると、とがった音の山が、もとより高くなることがある（1.0 をこえると割れる）。もどして測り、こえたら下げて作り直す
        vol = 1.0
        for _ in range(4):
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-af", "volume=%.4f" % vol, "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)], check=True)
            raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(ogg_path), "-f", "f32le", "-ac", "1", "-"], capture_output=True, check=True).stdout
            peak = float(np.max(np.abs(np.frombuffer(raw, dtype=np.float32))))
            if peak <= 0.97:
                break
            vol *= 0.93 / peak
        tmp.unlink()
        _drop(wav_path)
    else:
        _drop(ogg_path)
    made.append((name, "ogg" if as_ogg else "wav", len(x) / SR))


def _drop(p):
    for q in (p, Path(str(p) + ".import")):
        if q.exists():
            q.unlink()


made = []

# ================================================================ 自分の攻撃
# 斬る：空気を切る「しゅっ」（高さが上がるノイズ）＋うすい金属の「しゃりん」
n = n_of(0.24)
sw = sweep_bp(noise(n), 900, 5200, q=1.4) * hump(n, 0.35, 1.3)
ring = (np.sin(2 * np.pi * 3150 * t(0.24)) + 0.6 * np.sin(2 * np.pi * 4730 * t(0.24))) * dec(n, 30) * att(n, 0.03) * 0.12
save("slash", sw + ring)

# 当たり：「ぱしっ」（キレ）＋「どすっ」（芯）＋「ざくっ」（中の音）
n = n_of(0.22)
click = hp(noise(n), 2500) * dec(n, 260)
body = tone(190, 58, 0.22, 1.8) * dec(n, 16)
crunch = bp(noise(n), 500, 2600) * dec(n, 45) * 0.8
save("hit", click * 0.7 + body + crunch, 0.9, sat=0.8)

# 強い当たり（技・必殺技）：低くて長い「ずどん」＋ざらつき＋余韻
n = n_of(0.55)
sub = tone(130, 34, 0.55, 2.2) * dec(n, 7)
crack = hp(noise(n), 1800) * dec(n, 120) * 0.8
grit = bp(noise(n), 250, 1600) * dec(n, 11) * 0.7
tail = lp(noise(n), 500) * dec(n, 5) * att(n, 0.05) * 0.4
save("heavy", sub * 1.1 + crack + grit + tail, 0.92, sat=1.0)

# 銃（おもちゃっぽい「ぱん」）
n = n_of(0.16)
pop = hp(noise(n), 900) * dec(n, 90)
zap = tone(1300, 260, 0.16, 2.5) * dec(n, 40) * 0.5
thump = np.sin(2 * np.pi * 95 * t(0.16)) * dec(n, 35) * 0.7
save("shot", pop + zap + thump, 0.8, sat=0.6)

# 大砲：「どーん」
n = n_of(0.6)
boomb = tone(95, 30, 0.6, 2.0) * dec(n, 6.5)
blast = lp(noise(n), 900) * dec(n, 9)
crk = hp(noise(n), 2000) * dec(n, 70) * 0.6
save("cannon", boomb + blast * 0.9 + crk, 0.92, sat=1.2)

# 魔法をうつ：上がる「ひゅいーん」＋きらきら
n = n_of(0.42)
rise = np.sin(2 * np.pi * np.cumsum(np.linspace(500, 1500, n) * (1 + 0.04 * np.sin(2 * np.pi * 22 * t(0.42)))) / SR)
rise *= hump(n, 0.25, 1.0) * 0.6
glit = crackle(0.42, 50, 4.0) * 0.6
air = sweep_bp(noise(n), 1500, 4500) * hump(n, 0.3) * 0.3
save("magic", rise + glit + air, 0.75)

# 魔法が当たる：鐘の和音＋はじけ＋下がるきらきら
n = n_of(0.6)
chord = sum(fm_bell(f, 0.6, 3.5, 1.8, 6.0) for f in (1046.5, 1318.5, 1568.0)) / 3
burst = bp(noise(n), 800, 3000) * dec(n, 25) * 0.6
sparkle = sweep_bp(noise(n), 7000, 2500, q=3) * dec(n, 6) * 0.35
save("magic_hit", chord + burst + sparkle + tone(220, 80, 0.6) * dec(n, 18) * 0.5, 0.8)

# 爆発（プレゼント・花火の大きいもの）
n = n_of(0.75)
xb = noise(n)
xb = sweep_bp(xb, 2800, 260, q=0.9) * dec(n, 5.0)
sub = tone(80, 28, 0.75, 2.0) * dec(n, 6.0)
save("boom", xb * 1.2 + sub + crackle(0.75, 80, 5.0) * 0.5 + hp(noise(n), 2500) * dec(n, 60) * 0.5, 0.92, sat=1.0)

# 花火・ぽんっ
n = n_of(0.42)
p1 = tone(600, 140, 0.42, 3) * dec(n, 30)
save("pop", p1 + hp(noise(n), 1200) * dec(n, 70) * 0.8 + crackle(0.42, 90, 5.0) * 0.8, 0.8)

# 回復：やさしい上がる3音
seg = 0.07
x = mix(*[at(fm_bell(f, 0.45, 2.0, 0.6, 5.0), i * seg, 0.65) for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0))])
save("heal", verb(x, 0.35, 0.5), 0.6)

# 技：きらっ（短いアルペジオ＋高いシャラン）
x = mix(*[at(fm_bell(f, 0.4, 3.0, 1.2, 7.0), i * 0.035, 0.55) for i, f in enumerate((880, 1318.5, 1760, 2637))])
x = x + at(hp(noise(n_of(0.4)), 5000) * hump(n_of(0.4), 0.15) * 0.35, 0.02, 0.55)
save("skill", verb(x, 0.25, 0.4), 0.65)

# ジャンプ：「ふわっ」
n = n_of(0.2)
save("jump", sweep_bp(noise(n), 400, 1900, q=2.0) * hump(n, 0.4) + tone(280, 620, 0.2) * dec(n, 14) * 0.25, 0.55)

# 必殺技：ためて放つ「きゅいーん…どん」
n = n_of(0.8)
charge = np.sin(2 * np.pi * np.cumsum(np.linspace(300, 2100, n)) / SR) * np.linspace(0.1, 1.0, n) ** 2 * 0.35
charge = charge * np.clip((n_of(0.33) - np.arange(n)) / n_of(0.012), 0, 1)
boom2 = at(tone(140, 40, 0.48, 2.0) * dec(n_of(0.48), 7) + hp(noise(n_of(0.48)), 1500) * dec(n_of(0.48), 40) * 0.7, 0.32, 0.8)
air2 = at(sweep_bp(noise(n_of(0.48)), 4000, 600) * dec(n_of(0.48), 5) * 0.6, 0.32, 0.8)
save("ultimate", charge + boom2 + air2, 0.9, sat=0.8)

# ================================================================ 自分が受ける
# ダメージ：にぶい「どっ」
n = n_of(0.3)
x = tone(160, 52, 0.3, 1.8) * dec(n, 12) + lp(noise(n), 500) * dec(n, 25) * 0.7 + bp(saw(110, 0.3), 300, 900) * dec(n, 14) * 0.25
save("hurt", x, 0.9, sat=0.6)
# 投げられて着地：「どさっ」
n = n_of(0.38)
x = tone(110, 38, 0.38, 2) * dec(n, 9) + lp(noise(n), 420) * dec(n, 14) * 0.8 + bp(noise(n), 1500, 4000) * dec(n, 60) * 0.3
save("thud", x, 0.92, sat=0.7)
# つかまれた：「ぐしゃっ」
n = n_of(0.35)
save("grab", lp(noise(n), 800) * dec(n, 10) + tone(130, 48, 0.35) * dec(n, 9) + crackle(0.35, 40, 9) * 0.4, 0.9, sat=0.6)
# 助けた／抜けた：「ぱきん」
n = n_of(0.3)
save("free", fm_bell(1200, 0.3, 2.76, 2.5, 12) * 0.8 + hp(noise(n), 2500) * dec(n, 80) * 0.6 + tone(900, 400, 0.3) * dec(n, 18) * 0.3, 0.75)
# 連打：「ぽこ」
save("mash", np.sin(2 * np.pi * np.cumsum(np.linspace(760, 520, n_of(0.05))) / SR) * dec(n_of(0.05), 70), 0.5)
# 倒れた（自分・味方）：下がる音＋「どさ」
n = n_of(0.6)
fall = tone(520, 150, 0.6, 1.5) * dec(n, 5) * 0.5
fall = lp(saw(np.linspace(260, 75, n), 0.6), 1200) * dec(n, 5) * 0.4 + fall
save("down", fall + at(lp(noise(n_of(0.3)), 400) * dec(n_of(0.3), 14), 0.22, 0.6) * 0.8, 0.8)
# 起きた（蘇生）：上がるきらきら＋明るい和音
x = mix(*[at(fm_bell(f, 0.7, 2.0, 0.8, 4.0), i * 0.06, 1.1) for i, f in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5))])
x = x + at(sum(np.sin(2 * np.pi * f * t(0.8)) for f in (523.25, 659.25, 783.99)) * att(n_of(0.8), 0.05) * dec(n_of(0.8), 3.5) * 0.25, 0.3, 1.1)
x = x + sweep_bp(noise(n_of(1.1)), 600, 6000, q=2) * hump(n_of(1.1), 0.3, 1.5) * 0.35
save("revive", verb(x, 0.35, 0.6), 0.75)

# ================================================================ ボス
# 足音：重い「ずしん」
n = n_of(0.42)
x = tone(64, 33, 0.42, 2) * dec(n, 9) + lp(noise(n), 260) * dec(n, 16) * 0.8 + bp(noise(n), 700, 2200) * dec(n, 70) * 0.25
save("boss_step", x, 0.95, sat=1.2)
# 覚醒の雄たけび：「ぐおおお」（低いのこぎり波を、母音っぽく2か所でしぼる＋ゆれ）
d = 1.5
n = n_of(d)
f0 = 78 + 14 * np.sin(np.linspace(0, np.pi, n)) + 3 * np.sin(2 * np.pi * 7 * t(d)) + lp(noise(n), 20) * 8
src = saw(f0, d, 40) + 0.3 * saw(f0 * 1.5, d, 30)
v = bp(src, 260, 520) * 1.0 + bp(src, 800, 1300) * 0.7 + bp(src, 2200, 3000) * 0.25
breath = bp(noise(n), 400, 2500) * 0.35
env = att(n, 0.18) * np.clip(1.25 - np.linspace(0, 1, n) ** 2 * 1.25, 0, 1)
save("roar", np.tanh((v + breath) * 3.0) * env + tone(55, 35, d) * env * 0.4, 0.92)
# つかみの予告：うなり
d = 0.9
n = n_of(d)
f0 = 70 + 8 * np.sin(2 * np.pi * 4 * t(d))
save("grab_warn", np.tanh(bp(saw(f0, d, 30), 150, 700) * 3) * att(n, 0.12) * np.clip(1.2 - np.linspace(0, 1, n), 0, 1), 0.8)
# 台風：うなる風
d = 2.0
n = n_of(d)
w = sweep_bp(noise(n), 300, 900, q=1.2, steps=30) + sweep_bp(noise(n), 900, 400, q=3, steps=30) * 0.5
am = 0.65 + 0.35 * np.sin(2 * np.pi * 3.2 * t(d))
save("whoosh", w * am * np.sin(np.linspace(0, np.pi, n)) ** 1.4, 0.8)
# 投げる（チラシ・酒）：「ぱさっ」
n = n_of(0.14)
save("throw", bp(noise(n), 2000, 7000) * hump(n, 0.15, 1.5), 0.5)
# 嵐：「ごごご」
d = 1.2
n = n_of(d)
save("storm", lp(noise(n), 380) * att(n, 0.3) * np.clip(1.3 - np.linspace(0, 1, n), 0, 1) * 1.4 + tone(70, 100, d) * att(n, 0.3) * dec(n, 1.5) * 0.4 + crackle(d, 30, 1.0) * 0.3, 0.85, sat=0.8)
# なぎはらい：「ぶおん」
d = 0.8
n = n_of(d)
save("sweep", sweep_bp(noise(n), 300, 1400, q=1.3) * hump(n, 0.45, 1.2) * 1.3 + tone(110, 70, d) * hump(n, 0.45) * 0.5, 0.85)
# 勝ち・負け（音楽がない時の短い合図。音楽がある時は、曲の方を鳴らす）
x = mix(*[at(fm_bell(f, 0.5, 2.0, 0.7, 3.0), i * 0.11, 0.9) for i, f in enumerate((523.25, 659.25, 783.99, 1046.5))])
save("win", verb(x, 0.3, 0.5), 0.6)
x = mix(*[at(np.sin(2 * np.pi * f * t(0.32)) * dec(n_of(0.32), 6) * att(n_of(0.32), 0.01), i * 0.2, 1.0) for i, f in enumerate((392.0, 329.6, 261.6, 196.0))])
save("lose", verb(x, 0.25, 0.5), 0.6)

# ================================================================ メニュー・ガチャ
# ボタン：やわらかい「ぽこっ」
n = n_of(0.07)
save("click", np.sin(2 * np.pi * np.cumsum(np.linspace(1250, 700, n)) / SR) * dec(n, 70) + hp(noise(n), 4000) * dec(n, 400) * 0.25, 0.5)
# 引きしぼる：弓のきしみ（周期のある小さなはじけ）
d = 0.35
n = n_of(d)
imp = np.zeros(n)
pos = 0.0
k = 0
while pos < d:
    i = n_of(pos)
    if i < n - 30:
        imp[i:i + 30] += noise(30) * dec(30, 800)
    pos += 1 / (38 + 30 * pos / d) * rng.uniform(0.85, 1.15)
    k += 1
creak = signal.lfilter([1], [1, -1.6 * np.cos(2 * np.pi * 1100 / SR), 0.86], imp)
save("pull", creak * att(n, 0.05) * hump(n, 0.6, 0.6) + pluck(196, d, 0.999) * 0.08, 0.6)
# 強さの目もり：「こつ」
n = n_of(0.06)
save("pull_tick", bp(noise(n), 1500, 3500) * dec(n, 120) + np.sin(2 * np.pi * 1600 * t(0.06)) * dec(n, 90) * 0.6, 0.5)
# 飛び出す：弦の「びゅん」＋風
d = 0.55
n = n_of(d)
save("launch", pluck(98, d, 0.995) * 0.9 + sweep_bp(noise(n), 3500, 500, q=1.5) * hump(n, 0.15, 1.2) * 0.9 + tone(240, 90, d) * dec(n, 10) * 0.3, 0.85)
# ガチャの鬼を斬った：「ざしゅ」＋「ちりん」
n = n_of(0.4)
save("gacha_hit", hp(noise(n), 2500) * dec(n, 200) * 0.7 + tone(170, 60, 0.4) * dec(n, 18) + bp(noise(n), 600, 2400) * dec(n, 40) * 0.6 + at(fm_bell(1975.5, 0.32, 2.0, 0.8, 9.0), 0.06, 0.4) * 0.5, 0.85, sat=0.4)
# 結果：レア度ごとに、だんだん豪華に
x = mix(at(fm_bell(783.99, 0.5, 2.0, 0.8, 5.0), 0.0, 0.6), at(fm_bell(1046.5, 0.5, 2.0, 0.8, 5.0), 0.08, 0.6))
save("reveal_n", verb(x, 0.25, 0.4), 0.55)
x = mix(*[at(fm_bell(f, 0.6, 2.0, 1.0, 4.0), i * 0.08, 0.95) for i, f in enumerate((783.99, 987.77, 1174.66, 1567.98))])
save("reveal_r", verb(x, 0.3, 0.5), 0.65)
x = mix(*[at(fm_bell(f, 0.8, 3.0, 1.4, 3.2), i * 0.07, 1.4) for i, f in enumerate((659.25, 830.61, 987.77, 1318.51, 1661.22, 1975.53))])
x = x + at(tone(150, 50, 0.5) * dec(n_of(0.5), 8) + lp(noise(n_of(0.5)), 900) * dec(n_of(0.5), 10) * 0.5, 0.0, 1.4) * 0.8
x = x + at(sweep_bp(noise(n_of(1.0)), 3000, 9000, q=3) * dec(n_of(1.0), 3) * 0.3, 0.42, 1.4)
save("reveal_sr", verb(x, 0.35, 0.6), 0.75)
d = 2.3
chord = sum(saw(f, 1.9, 12) for f in (261.63, 329.63, 392.0, 523.25, 659.25)) / 5
chord = lp(chord, 2600) * att(n_of(1.9), 0.25) * dec(n_of(1.9), 1.3)
x = at(chord, 0.35, d) * 0.7
x = x + at(tone(110, 38, 0.8) * dec(n_of(0.8), 4.5) * 1.2 + lp(noise(n_of(0.8)), 700) * dec(n_of(0.8), 6) * 0.6, 0.35, d)
x = x + mix(*[at(fm_bell(f, 0.9, 3.0, 1.6, 2.8), 0.35 + i * 0.06, d) for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0, 2637.0, 3136.0))]) * 0.8
x = x + at(sweep_bp(noise(n_of(0.35)), 400, 5000, q=2) * np.linspace(0, 1, n_of(0.35)) ** 2 * 0.5, 0.0, d)
x = x + at(crackle(1.6, 70, 2.0) * 0.5, 0.4, d)
save("reveal_ssr", verb(x, 0.35, 0.8), 0.85)
# コイン：「ちゃりん」
x = mix(at(fm_bell(1567.98, 0.3, 2.0, 1.2, 10), 0.0, 0.42), at(fm_bell(2093.0, 0.35, 2.0, 1.2, 8), 0.06, 0.42))
save("coin", x, 0.6)

total = 0
for name, ext, sec in made:
    total += (out / (name + "." + ext)).stat().st_size
    print("%-11s %s %.2f秒 %6d B" % (name, ext, sec, (out / (name + "." + ext)).stat().st_size))
print("合計 %d B（%d 個）" % (total, len(made)))
