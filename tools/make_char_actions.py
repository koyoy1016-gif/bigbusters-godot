#!/usr/bin/env python3
"""版79：8人の味方の、キャラごとの攻撃（A＝通常・Y＝サブ・X＝メイン・必殺）と、その動き（アニメ）を作る。
書き出す物：
  data/char_actions.json  ：攻撃の時刻・当たりの形・ダメージの倍率・飛ぶ物・見た目・効果（scripts/combat/player_actions.gd が読む）
  （characters.json の built_anims と animations には、tools/make_looks.py が、ここの all_anims() を書きこむ）
  docs/char-actions-v79.md：ダメージの表（剣士との比べ）
ダメージ = キャラの攻撃力（characters.json の stats.attack_power）× 倍率。剣士の基準（22.5・58.5・18×5・346.5）は変えない。
飛ぶ物（hits の proj）：銃弾・魔法・プレゼント・矢は、発射口（sockets）から出て飛び、当たった時にダメージ（scripts/combat/projectiles.gd）。

版79の動き：「姿勢（ポーズ）」を時刻に並べて作る（pose_anim）。腕・脚の骨を、モデルの中の向きへ向ける（anim_compose.gd の aim）。
  向きは「その側の外が +x」（左腕は +X、右腕は −X がそと）、前が +z、上が +y。
  脚を曲げた分、腰を下げる（低いほうの足首が床にくるように、anim_compose.gd が毎コマ計算する。lift は「さらに上げる量」）。
  どの技も「ため（予備動作）→ 打つ（インパクト）→ 止め → もどり」の順に作る。
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWORD = {"A": 22.5, "Y": 58.5, "X": 90.0, "ULT": 346.5, "A_cd": 0.35, "Y_cd": 4.0, "X_cd": 6.0}

# 役と色（必殺技のオーラ・当たった時の火花）。剣士・アタッカー＝黄、ファイター＝赤、スピード・シールド＝青、ヒーラー＝緑
META = {
    "brawler": {"role": "ファイター", "aura": "#ff3b2f", "spark": "#ff6a3a"},
    "sprinter": {"role": "スピード", "aura": "#3fb8ff", "spark": "#7fdcff"},
    "gunner": {"role": "アタッカー", "aura": "#ffd24a", "spark": "#ffd24a"},
    "bomber": {"role": "アタッカー", "aura": "#ffd24a", "spark": "#ffb347"},
    "mage": {"role": "アタッカー", "aura": "#ffd24a", "spark": "#d9a8ff"},
    "guardian": {"role": "シールド", "aura": "#4f9bff", "spark": "#9fd0ff"},
    "summoner": {"role": "アタッカー", "aura": "#ffd24a", "spark": "#ffd24a"},
    "healer": {"role": "ヒーラー", "aura": "#4fe08a", "spark": "#9dffb8"},
}
_CUR = {"id": ""}


# ------------------------------------------------------------------ 基本の部品
def seg(anim, a, b, dur, **kw):
    d = {"anim": anim, "from": a, "to": b, "dur": dur}
    d.update(kw)
    return d


def hold(anim, t, dur, **kw):
    return seg(anim, t, t, dur, **kw)


def path(*pts):
    return [{"t": t, "fwd": f, "h": h} for t, f, h in pts]


def act(label, dur, cd, hits, steps, *, name="", move=0.0, aim=True, path_=None, fx=None, effects=None, i_frames=False,
        stop=True, radius_scale=1.0, cleave=True, sweep=False, marks=None, from_cd=False, banner=1.6, note=""):
    d = {"label": label, "name": name or label, "cooldown_sec": cd, "duration_sec": dur, "move_scale": move, "aim_boss": aim,
         "cleave": cleave, "radius_scale": radius_scale, "hits": hits, "steps": steps, "path": path_ or [], "stop_at_boss": stop}
    if from_cd:
        d["duration_from_cooldown"] = True
    effects = list(effects or [])
    if label == "必殺":
        d["banner_sec"] = banner
        # 版79：必殺技の間、役の色の光（オーラ）で体を包む
        m = META[_CUR["id"]]
        effects.insert(0, {"t": 0.0, "type": "aura", "color": m["aura"], "sec": round(dur, 2), "radius": 1.1, "alpha": 0.22})
    if fx:
        d["fx_events"] = fx
    if effects:
        d["effects"] = effects
    if i_frames:
        d["i_frames"] = True
    if sweep:
        d["sweep_hit"] = True
    if marks:
        d["marks"] = marks
    if note:
        d["note"] = note
    return d


def hit(t, mult, **shape):
    d = {"t": round(t, 3), "multiplier": round(mult, 4)}
    d.update(shape)
    return d


def step(t, anim, speed=1.0):
    return [{"t": t, "anim": anim, "speed": speed}]


# 強い攻撃の手ごたえ：[一瞬止める秒, 画面のゆれ, カメラの寄り]（剣士の必殺技は 0.09・0.32）
IMPACT_S = [0.04, 0.16, 0.0]
IMPACT_M = [0.06, 0.24, 0.04]
IMPACT_ULT = [0.09, 0.34, 0.1]


def proj(mode, frm, *, speed, prop, scale=1.0, size=0.2, rng=16.0, radius=0.2, aim_h=0.45, color="#ffffff", **kw):
    d = {"mode": mode, "from": frm, "speed": speed, "prop": prop, "scale": scale, "size": size, "range": rng, "radius": radius,
         "aim_h": aim_h, "color": color, "life": kw.pop("life", max(1.5, rng / max(speed, 1.0) * 1.6))}
    d.update(kw)
    return d


MUZZLE = {"prop": "muzzle_flash", "scale": 0.9, "life": 0.07}


# ------------------------------------------------------------------ 版79：姿勢（ポーズ）の部品
LIMBS = {"armL": ("upperarm01.L", "lowerarm01.L"), "armR": ("upperarm01.R", "lowerarm01.R"),
         "legL": ("upperleg01.L", "lowerleg01.L"), "legR": ("upperleg01.R", "lowerleg01.R")}
THIGH, SHIN = 0.537, 0.463  # 脚の長さを1とした、もも・すねの長さ


def nrm(v):
    l = math.sqrt(sum(x * x for x in v)) or 1.0
    return [round(x / l, 4) for x in v]


def own(v, limb):
    """その側の外が +x の向きを、モデルの向きに直す（右は x が反対）"""
    v = nrm(v)
    return [-v[0], v[1], v[2]] if limb.endswith("R") else v


def leg_h(leg):
    """脚の、腰から足首までの高さ（脚の長さ＝1）"""
    th, sh = nrm(leg[0]), nrm(leg[1])
    return THIGH * -th[1] + SHIN * -sh[1]


# 腕（上腕、前腕）
HANG = ((0.15, -1, 0.0), (0.1, -1, 0.12))
GUARD = ((0.35, -0.75, 0.55), (-0.45, 0.72, 0.55))
GUARD_LO = ((0.3, -0.85, 0.45), (-0.4, 0.5, 0.75))
JAB = ((-0.08, 0.1, 1), (-0.12, 0.1, 1))
CROSS = ((-0.3, 0.08, 1), (-0.32, 0.06, 1))
PULL = ((0.32, -0.6, -0.72), (-0.25, 0.45, 0.85))
UPPERCUT = ((0.08, -0.25, 0.95), (-0.12, 0.95, 0.3))
WIND = ((0.5, 0.15, -0.85), (0.1, 0.85, -0.5))
GIANT = ((-0.06, 0.14, 1), (-0.06, 0.12, 1))
SKY = ((0.18, 1, 0.08), (0.08, 1, 0.12))
SKY_FWD = ((0.08, 0.72, 0.68), (0.02, 0.62, 0.78))
FWD = ((0.0, 0.08, 1), (0.0, 0.08, 1))
FWD_LO = ((0.06, -0.42, 0.9), (0.03, -0.3, 0.95))
GROUND = ((0.1, -0.75, 0.65), (0.05, -0.85, 0.5))
OUT = ((1, 0.08, 0.1), (1, 0.12, 0.12))
OUT_LO = ((0.85, -0.5, 0.12), (0.75, -0.6, 0.2))
WIDE_UP = ((0.7, 0.7, 0.12), (0.55, 0.82, 0.05))
BACK = ((0.15, -0.8, -0.6), (0.1, -0.65, -0.75))
OVER = ((0.22, 0.9, -0.38), (0.0, 0.35, -0.94))
THROW = ((0.0, 0.32, 1.0), (0.0, 0.05, 1.0))
FOLLOW = ((-0.12, -0.45, 0.9), (-0.18, -0.7, 0.7))
HUG = ((0.12, -1, 0.25), (-0.55, 0.12, 0.83))
CHEST = ((0.12, -0.6, 0.8), (-0.85, 0.3, 0.45))
PRAY = ((0.22, -0.72, 0.65), (-0.78, 0.42, 0.48))
FIST_UP = ((0.25, 0.25, 0.95), (0.0, 1.0, 0.15))

# 脚（もも、すね）
STAND = ((0.06, -1, 0.0), (0.04, -1, -0.03))
FIGHT_F = ((0.12, -0.97, 0.22), (0.06, -1, -0.06))
FIGHT_B = ((0.1, -0.97, -0.2), (0.08, -0.95, -0.3))
LUNGE_F = ((0.08, -0.82, 0.57), (0.04, -1, -0.04))
LUNGE_B = ((0.08, -0.9, -0.43), (0.06, -0.9, -0.43))
WIDE = ((0.32, -0.95, 0.0), (0.28, -0.96, -0.02))
SQUAT = ((0.25, -0.55, 0.8), (0.1, -0.97, -0.25))
CROUCH_F = ((0.12, -0.7, 0.7), (0.05, -0.99, -0.12))
CROUCH_B = ((0.12, -0.85, -0.25), (0.06, -0.6, -0.8))
KNEE_UP = ((0.04, -0.15, 0.99), (0.0, -1.0, 0.1))
KICK = ((0.0, 0.05, 1.0), (0.0, 0.12, 1.0))
TUCK = ((0.1, -0.35, 0.94), (0.02, -0.95, -0.3))
KNEEL_F = ((0.1, -0.08, 1.0), (0.05, -1, 0.02))
KNEEL_B = ((0.1, -1, 0.06), (0.05, -0.05, -1.0))
MARCH_UP = ((0.04, -0.6, 0.8), (0.0, -1.0, 0.0))


def P(armL=None, armR=None, legL=None, legR=None, spine=None, low=None, head=None, lift=0.0, air=False, plant=""):
    """1つの姿勢。spine：胸（spine03）のひねり [前へ倒す, ひねり, 横へ倒す]、low：腰の上（spine01）、head：頭。
    lift：さらに上げる（脚の長さ＝1。うく・跳ぶ）。air・plant：書いておくだけ（腰の高さは、低いほうの足が床にくるよう自動）"""
    return {"armL": armL, "armR": armR, "legL": legL, "legR": legR, "spine": spine, "low": low, "head": head, "lift": lift,
            "air": air, "plant": plant}


def mix(base, **kw):
    """姿勢 base の一部を変えた物"""
    d = dict(base)
    d.update(kw)
    return d


def pose_anim(keys, base=("Walk", 0.36), loop=False, legs=(STAND, STAND), extra_offsets=None):
    """姿勢を時刻に並べた動き。keys：[(秒, 姿勢)]。姿勢に脚がなければ legs（キャラの立ち方）"""
    keys = sorted(keys, key=lambda k: k[0])
    total = keys[-1][0]
    aim = {}
    for limb, (b1, b2) in LIMBS.items():
        is_leg = limb.startswith("leg")
        vals = []
        for t, p in keys:
            v = p.get(limb)
            if v is None and is_leg:
                v = legs[0] if limb == "legL" else legs[1]
            vals.append(v)
        if all(v is None for v in vals):
            continue
        first = next(v for v in vals if v is not None)
        k1, k2, last = [], [], first
        for (t, p), v in zip(keys, vals):
            w = 1.0 if v is not None else 0.0
            if v is not None:
                last = v
            u = v if v is not None else last
            k1.append([round(t, 3), own(u[0], limb), w])
            k2.append([round(t, 3), own(u[1], limb), w])
        aim[b1] = k1
        aim[b2] = k2
    offs = {}
    for key, bone in (("spine", "spine03"), ("low", "spine01"), ("head", "head")):
        if any(p.get(key) for _, p in keys):
            offs[bone] = [[round(t, 3), list(p.get(key) or [0, 0, 0])] for t, p in keys]
    if extra_offsets:
        offs.update(extra_offsets)
    # 腰の高さ：低いほうの足首が床にくるように、anim_compose.gd が毎コマ計算する（lift_units: leg_abs）。ここは「さらに上げる量」だけ
    lift = [[round(t, 3), round(float(p.get("lift", 0.0)), 4)] for t, p in keys]
    # 床につく足（"LR" 両足・"L"・"R"・"" 決めない＝跳ぶ）。足を上げ始める所から、片足にする
    modes = ["" if p.get("air") else (p.get("plant") or "LR") for _, p in keys]
    plant = []
    for i, (t, _) in enumerate(keys):
        a = modes[i]
        b = modes[i + 1] if i + 1 < len(modes) else a
        m = a if a == b else (b if a == "LR" else (a if b == "LR" else ""))
        plant.append([round(t, 3), m])
    spec = {"segments": [hold(base[0], base[1], round(total, 3))], "aim": aim, "root_lift": lift, "lift_units": "leg_abs", "plant": plant,
            "blend": 0.0}
    if offs:
        spec["offsets"] = offs
    if loop:
        spec["loop"] = True
    return spec


def tremble(t0, t1, amp=2.0, period=0.08, bone_axis=2):
    """ためている間の、小さなふるえ（胸の横へのゆれ）"""
    out, t, s = [], t0, 1
    while t <= t1 + 1e-6:
        e = [0, 0, 0]
        e[bone_axis] = amp * s
        out.append([round(t, 3), e])
        s = -s
        t += period
    return out


# ------------------------------------------------------------------ ファイター（赤）
def brawler():
    st = (FIGHT_F, FIGHT_B)  # 左足が前の、ボクシングの構え
    ready = P(GUARD, GUARD, spine=[8, -12, 0], head=[-6, 10, 0])
    A = pose_anim([
        (0.0, ready),
        (0.04, mix(ready, armL=GUARD_LO, spine=[6, 4, 0])),                      # ため：少し引く
        (0.09, mix(ready, armL=JAB, spine=[14, -32, 0], legL=((0.12, -0.9, 0.42), (0.06, -1, -0.05)))),  # 打つ：左ジャブ
        (0.16, mix(ready, armL=JAB, spine=[14, -30, 0], legL=((0.12, -0.9, 0.42), (0.06, -1, -0.05)))),
        (0.3, ready)], base=("Walk", 0.36), legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.08, mix(ready, legL=CROUCH_F, legR=CROUCH_B, spine=[24, -8, 0])),       # ため：しずむ
        (0.2, mix(ready, legL=LUNGE_F, legR=LUNGE_B, spine=[28, -6, 0], armL=GUARD_LO, armR=BACK)),  # 踏みこむ
        (0.3, mix(ready, legL=((0.1, -0.97, 0.15), (0.05, -1, -0.08)), legR=KNEE_UP, spine=[-4, 10, 0], armR=OUT_LO, plant="L")),  # ひざを上げる
        (0.38, mix(ready, legL=((0.1, -0.99, 0.05), (0.05, -1, -0.04)), legR=KICK, spine=[-22, 20, 0], armL=GUARD, armR=BACK, plant="L")),  # 前げり
        (0.5, mix(ready, legL=((0.1, -0.99, 0.05), (0.05, -1, -0.04)), legR=KICK, spine=[-20, 18, 0], armL=GUARD, armR=BACK, plant="L")),
        (0.62, mix(ready, legR=KNEE_UP, spine=[0, 6, 0], plant="L")),
        (0.75, ready)], legs=st)
    xk = [(0.0, ready), (0.18, mix(ready, legL=LUNGE_F, legR=LUNGE_B, spine=[16, 0, 0]))]
    for i in range(20):
        t = 0.27 + 0.1 * i
        left = i % 2 == 0
        tw = -24 if left else 24
        xk.append((t - 0.045, mix(ready, armL=GUARD, armR=GUARD, legL=LUNGE_F, legR=LUNGE_B, spine=[16, tw * 0.3, 0])))
        if i == 19:
            xk.append((t, mix(ready, armR=GIANT, armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[22, 34, 0])))
        else:
            xk.append((t, mix(ready, armL=JAB if left else PULL, armR=PULL if left else CROSS, legL=LUNGE_F, legR=LUNGE_B, spine=[18, tw, 0])))
    xk += [(2.3, mix(ready, armR=GIANT, armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[22, 34, 0])), (2.4 + 0.15, ready)]
    X = pose_anim(xk, legs=st)
    wind = mix(ready, armR=WIND, armL=((0.2, -0.3, 0.95), (-0.3, 0.6, 0.75)), legL=CROUCH_F, legR=CROUCH_B, spine=[-6, -38, 0], head=[-10, 20, 0])
    U = pose_anim([
        (0.0, ready),
        (0.28, wind), (0.72, mix(wind, spine=[-8, -42, 0])),                        # ためる（ふるえる）
        (0.84, mix(ready, armR=((0.2, 0.1, 0.95), (0.0, 0.3, 0.95)), armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[14, -6, 0])),  # 踏みこむ
        (0.9, mix(ready, armR=GIANT, armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[24, 30, 0], head=[-10, -10, 0])),  # 打つ
        (1.2, mix(ready, armR=GIANT, armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[22, 28, 0])),
        (1.6, ready)], legs=st, extra_offsets={"spine02": tremble(0.3, 0.7, 2.5)})
    anims = {"Brawler_A": A, "Brawler_Y": Y, "Brawler_X": X, "Brawler_Ult": U}
    hit_fx = {"size": 0.7}
    acts = {
        "normal": act("A", 0.3, 0.3, [hit(0.09, 1.2, fx=hit_fx)], step(0.0, "Brawler_A"), from_cd=True, aim=False, stop=False, cleave=False,
                      name="ジャブ", note="すばやい左ジャブ。待ち時間はキャラの attack_cooldown_sec（0.3秒）"),
        "sub": act("Y", 0.75, 4.0, [hit(0.38, 3.6, impact=IMPACT_S, fx={"kind": "blast", "color": "#ff8a4a", "radius": 1.2, "life": 0.22, "at": "front", "dist": 1.7, "size": 1.0})],
                   step(0.0, "Brawler_Y"), path_=path((0.0, 0.0, 0.0), (0.08, 0.0, 0.0), (0.3, 2.8, 0.0), (0.75, 3.0, 0.0)), i_frames=True,
                   radius_scale=1.4, name="ダッシュキック", note="しずんでから前へ踏みこみ、右足で前げり。踏みこむ間は無敵"),
        "main": act("X", 2.55, 7.0, [hit(0.27 + 0.1 * i, 0.38, fx=hit_fx) for i in range(19)] +
                    [hit(2.17, 1.6, impact=IMPACT_S, fx={"kind": "blast", "color": "#ff6a3a", "radius": 1.6, "life": 0.25, "at": "front", "dist": 1.8, "size": 1.2})],
                    step(0.0, "Brawler_X"), path_=path((0.0, 0.0, 0.0), (0.2, 0.4, 0.0), (2.2, 1.2, 0.0), (2.55, 1.2, 0.0)), radius_scale=1.25,
                    name="20連パンチ", note="左右の拳を交互に19発、最後に右の大きな1発。1発ずつ計算する。2秒以上その場に立つので、反撃を受けやすい"),
        "ultimate": act("必殺", 1.6, 0.0, [hit(0.9, 23.0, impact=IMPACT_ULT, fx={"kind": "blast", "color": "#ff5a2e", "radius": 3.0, "life": 0.45, "at": "front", "dist": 1.8, "size": 1.6})],
                        step(0.0, "Brawler_Ult"), i_frames=True, radius_scale=2.0, name="ギガトンブロー",
                        path_=path((0.0, 0.0, 0.0), (0.72, -0.3, 0.0), (0.88, 2.6, 0.0), (1.6, 2.6, 0.0)),
                        fx=[{"t": 0.3, "kind": "ring", "color": "#ff5a3a", "radius": 1.6, "life": 0.45, "at": "self"},
                            {"t": 0.9, "kind": "ring", "color": "#ff9a5a", "radius": 6.0, "life": 0.5, "at": "front", "dist": 1.8},
                            {"t": 0.9, "kind": "beam", "color": "#ff4a2a", "width": 0.45, "life": 0.22, "length": 7.0, "from": "fist_R"}],
                        note="赤いオーラで力をためて（腕を大きく引き、ふるえる）、踏みこんで渾身の右ストレート。拳の先に衝撃波"),
    }
    return acts, anims


# ------------------------------------------------------------------ スピードファイター（青）
def sprinter():
    st = (((0.1, -0.95, 0.25), (0.05, -0.98, -0.15)), ((0.1, -0.95, -0.12), (0.08, -0.85, -0.5)))
    ready = P(GUARD_LO, GUARD_LO, spine=[14, -8, 0])
    A = pose_anim([
        (0.0, ready),
        (0.03, mix(ready, spine=[12, 6, 0])),
        (0.07, mix(ready, armL=JAB, spine=[20, -30, 0], legL=LUNGE_F, legR=LUNGE_B)),
        (0.13, mix(ready, armL=JAB, spine=[20, -28, 0], legL=LUNGE_F, legR=LUNGE_B)),
        (0.25, ready)], legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.1, mix(ready, legL=SQUAT, legR=SQUAT, armL=BACK, armR=BACK, spine=[28, 0, 0])),      # しずむ
        (0.2, mix(ready, legL=STAND, legR=STAND, armL=OUT_LO, armR=OUT_LO, spine=[-6, 0, 0], lift=0.06)),  # ふっと消える
        (0.4, ready)], legs=st)
    X = pose_anim([
        (0.0, ready),
        (0.18, mix(ready, armL=CHEST, armR=CHEST, legL=CROUCH_F, legR=CROUCH_B, spine=[22, 0, 0], head=[15, 0, 0])),  # 腕を組んで、ためる
        (0.35, mix(ready, armL=OUT_LO, armR=OUT_LO, legL=WIDE, legR=WIDE, spine=[-12, 0, 0], head=[-12, 0, 0])),     # 気を放つ
        (0.55, mix(ready, armL=OUT_LO, armR=OUT_LO, legL=WIDE, legR=WIDE, spine=[-10, 0, 0])),
        (0.7, ready)], legs=st)
    uk = [(0.0, ready), (0.2, mix(ready, legL=LUNGE_F, legR=LUNGE_B, armL=BACK, armR=BACK, spine=[32, 0, 0]))]
    moves = []
    for i in range(8):
        t = 0.4 + 0.25 * i
        k = i % 4
        if k == 0:
            p = mix(ready, armL=JAB, armR=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[20, -30, 0])
        elif k == 1:
            p = mix(ready, armR=CROSS, armL=PULL, legL=LUNGE_F, legR=LUNGE_B, spine=[20, 30, 0])
        elif k == 2:
            p = mix(ready, legR=KICK, legL=((0.1, -0.99, 0.05), (0.05, -1, -0.04)), armL=GUARD, armR=BACK, spine=[-18, 20, 0], plant="L")
        else:
            p = mix(ready, armL=UPPERCUT, armR=PULL, legL=CROUCH_F, legR=CROUCH_B, spine=[-8, -20, 0])
        moves.append((t, p))
        uk.append((t - 0.08, mix(ready, legL=CROUCH_F, legR=CROUCH_B, spine=[18, 0, 0])))
        uk.append((t, p))
        uk.append((t + 0.06, p))
    uk.append((2.4, ready))
    U = pose_anim(uk, legs=st)
    anims = {"Sprinter_A": A, "Sprinter_Y": Y, "Sprinter_X": X, "Sprinter_Ult": U}
    acts = {
        "normal": act("A", 0.25, 0.25, [hit(0.07, 1.0, fx={"size": 0.55})], step(0.0, "Sprinter_A"), from_cd=True, aim=False, stop=False, cleave=False,
                      name="高速ジャブ"),
        "sub": act("Y", 0.4, 8.0, [], step(0.0, "Sprinter_Y"), stop=False, aim=False, name="バニッシュ",
                   effects=[{"t": 0.18, "type": "vanish", "sec": 3.0, "speed": 1.3, "bonus": 1.5, "color": "#5fd6ff"}],
                   fx=[{"t": 0.18, "kind": "ring", "color": "#5fd6ff", "radius": 1.8, "life": 0.35, "at": "self"}],
                   note="姿が消える（青い残像と粒）。3秒、ボスの攻撃に当たらず、1.3倍の速さで動ける。攻撃すると現れ、その技のダメージが1.5倍"),
        "main": act("X", 0.7, 15.0, [], step(0.0, "Sprinter_X"), effects=[{"t": 0.35, "type": "speed_mode", "sec": 6.0, "mult": 1.75, "color": "#5fd6ff"}],
                    fx=[{"t": 0.35, "kind": "ring", "color": "#5fd6ff", "radius": 3.0, "life": 0.4, "at": "self"},
                        {"t": 0.35, "kind": "rise", "color": "#8fe8ff", "life": 0.8, "at": "self"}], aim=False, stop=False,
                    name="超高速モード", note="6秒、動く速さと攻撃の速さ（待ち時間の減り・通常攻撃の間かく）が1.75倍"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(0.4 + 0.25 * i, 3.5, shape="self", radius=4.5, impact=IMPACT_ULT if i == 7 else None,
                                               fx={"kind": "slash", "color": "#7fdcff", "width": 0.1, "life": 0.18, "length": 4.5, "at": "boss", "size": 0.9})
                                           for i in range(8)],
                        step(0.0, "Sprinter_Ult"), i_frames=True, stop=True, name="迅雷乱舞",
                        path_=path((0.0, 0.0, 0.0), (0.2, 0.0, 0.0), (0.32, 6.0, 0.0), (2.4, 6.0, 0.0)),
                        effects=[{"t": 0.3 + 0.5 * k, "type": "afterimage", "color": "#5fd6ff"} for k in range(4)],
                        note="一瞬で敵の前へ。青い残像を残しながら、ジャブ・ストレート・けり・アッパーで8回打つ（まわり4.5m）"),
    }
    for h in acts["ultimate"]["hits"]:
        if h.get("impact") is None:
            h.pop("impact", None)
    return acts, anims


# ------------------------------------------------------------------ ガンナー（黄）
def gunner():
    st = (((0.2, -0.98, 0.1), (0.14, -0.99, -0.03)), ((0.2, -0.98, -0.08), (0.14, -0.98, -0.1)))
    AIM = ((0.06, -0.06, 1), (0.04, 0.0, 1))
    LOW = ((0.25, -0.85, 0.45), (0.12, -0.55, 0.82))
    KICKUP = ((0.06, 0.12, 1), (0.04, 0.4, 0.92))
    JOIN = ((-0.22, -0.02, 1), (-0.3, 0.0, 1))
    ready = P(LOW, LOW, spine=[4, 0, 0])
    aimp = P(AIM, AIM, spine=[2, 0, 0])
    A = pose_anim([
        (0.0, ready),
        (0.035, mix(aimp, armR=LOW, spine=[2, -10, 0])),
        (0.06, mix(aimp, armL=KICKUP, armR=LOW, spine=[-4, -10, 0])),     # 左の大砲：反動
        (0.12, mix(aimp, spine=[2, 10, 0])),
        (0.16, mix(aimp, armR=KICKUP, spine=[-4, 10, 0])),                # 右の大砲：反動
        (0.3, mix(aimp, spine=[2, 0, 0]))], legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.1, mix(aimp, legL=SQUAT, legR=SQUAT, spine=[18, 0, 0])),
        (0.25, mix(aimp, legL=TUCK, legR=TUCK, spine=[-12, 0, 0], air=True, lift=0.0)),
        (0.3, mix(aimp, armL=KICKUP, legL=TUCK, legR=TUCK, spine=[-16, -8, 0], air=True)),
        (0.38, mix(aimp, armR=KICKUP, legL=TUCK, legR=TUCK, spine=[-16, 8, 0], air=True)),
        (0.46, mix(aimp, armL=KICKUP, armR=KICKUP, legL=TUCK, legR=TUCK, spine=[-18, 0, 0], air=True)),
        (0.62, mix(aimp, legL=SQUAT, legR=SQUAT, spine=[14, 0, 0])),       # 着地
        (0.8, ready)], legs=st)
    brace = mix(aimp, legL=LUNGE_F, legR=LUNGE_B, spine=[10, 0, 0])
    xk = [(0.0, ready), (0.22, mix(brace, armL=((0.08, 0.1, 1), (0.05, 0.15, 1)), armR=((0.08, 0.1, 1), (0.05, 0.15, 1))))]
    for i in range(6):
        t = 0.35 + 0.2 * i
        xk.append((t, mix(brace, spine=[6, 0, 0])))
        xk.append((t + 0.1, mix(brace, spine=[11, 0, 0])))
    xk += [(1.6, ready)]
    X = pose_anim(xk, legs=st)
    U = pose_anim([
        (0.0, ready),
        (0.4, mix(brace, armL=JOIN, armR=JOIN, legL=CROUCH_F, legR=CROUCH_B, spine=[14, 0, 0])),   # 大砲を合わせる
        (0.55, mix(brace, armL=JOIN, armR=JOIN, legL=CROUCH_F, legR=CROUCH_B, spine=[4, 0, 0])),
        (2.2, mix(brace, armL=JOIN, armR=JOIN, legL=CROUCH_F, legR=CROUCH_B, spine=[2, 0, 0])),
        (2.4, ready)], legs=st, extra_offsets={"spine02": tremble(0.55, 2.2, 1.5, 0.06, 0)})
    anims = {"Gunner_A": A, "Gunner_Y": Y, "Gunner_X": X, "Gunner_Ult": U}
    bullet = lambda frm: proj("straight", frm, speed=48.0, prop="bullet", scale=1.0, size=0.14, rng=18.0, radius=0.3, muzzle=MUZZLE, aim_h=0.42)
    beam = {"kind": "beam", "color": "#ffcf3a", "width": 0.16, "life": 1.1, "length": 14.0}
    acts = {
        "normal": act("A", 0.3, 0.3, [hit(0.05, 0.5, proj=bullet("muzzle_L"), fx={"size": 0.45}),
                                      hit(0.15, 0.5, proj=bullet("muzzle_R"), fx={"size": 0.45})], step(0.0, "Gunner_A"),
                      from_cd=True, stop=False, name="ダブルショット", note="左右の腕の大砲から1発ずつ（銃口の光・光る弾・当たった所の火花。ダメージは当たった時）"),
        "sub": act("Y", 0.8, 4.5, [hit(0.3 + 0.08 * k, 0.9, side=s, proj=bullet("muzzle_L" if k != 1 else "muzzle_R"), fx={"size": 0.6})
                                   for k, s in enumerate((-0.9, 0.0, 0.9))], step(0.0, "Gunner_Y"), i_frames=True, stop=False,
                   path_=path((0.0, 0.0, 0.0), (0.1, 0.0, 0.0), (0.45, -3.2, 0.9), (0.62, -3.4, 0.0), (0.8, -3.4, 0.0)), name="バックステップ射撃",
                   note="後ろへ跳びながら、扇の形に3発。跳んでいる間は無敵"),
        "main": act("X", 1.6, 7.0, [hit(0.35 + 0.2 * i, 0.5, shape="beam", length=14.0, half_width=0.55, side=s)
                                   for i in range(6) for s in (-0.35, 0.35)], step(0.0, "Gunner_X"),
                    fx=[dict(beam, t=0.3, frm="muzzle_L"), dict(beam, t=0.3, frm="muzzle_R")], stop=False,
                    name="ダブルビーム", note="両腕の砲口から2本のビーム。1本ずつ当たりを調べる。6回ずつ、つらぬく"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(0.6 + 0.17 * i, 2.3, shape="beam", length=18.0, half_width=1.4, impact=IMPACT_ULT if i in (0, 9) else None)
                                           for i in range(10)],
                        step(0.0, "Gunner_Ult"), i_frames=True, stop=False, name="フルバースト",
                        fx=[dict(beam, t=0.55, width=0.42, life=1.7, length=18.0, color="#ffb02a", frm="muzzle_L"),
                            dict(beam, t=0.55, width=0.42, life=1.7, length=18.0, color="#ffb02a", frm="muzzle_R"),
                            {"t": 0.4, "kind": "spark", "color": "#ffe27a", "size": 1.0, "life": 0.3, "frm": "muzzle_L", "at": "socket"},
                            {"t": 0.4, "kind": "spark", "color": "#ffe27a", "size": 1.0, "life": 0.3, "frm": "muzzle_R", "at": "socket"}],
                        note="2つの大砲を前で合わせて、太いビームを2本（10回当たる）"),
    }
    for a in acts.values():
        for h in a["hits"]:
            if h.get("impact", 0) is None:
                h.pop("impact")
        for f in a.get("fx_events", []):
            if "frm" in f:
                f["from"] = f.pop("frm")
    return acts, anims


# ------------------------------------------------------------------ ボンバー（黄）
def bomber():
    st = (((0.1, -0.99, 0.05), (0.06, -1, -0.02)), ((0.1, -0.99, -0.03), (0.06, -1, -0.03)))
    HOLD = ((0.5, -0.75, 0.35), (0.45, -0.1, 0.9))
    ready = P(HOLD, HOLD, spine=[0, 0, 0])
    A = pose_anim([
        (0.0, ready),
        (0.1, mix(ready, armL=OVER, armR=OUT_LO, legL=((0.12, -0.92, 0.35), (0.06, -1, -0.03)), spine=[-14, 24, 0], head=[-8, -12, 0])),  # ふりかぶる
        (0.2, mix(ready, armL=THROW, armR=OUT_LO, legL=LUNGE_F, legR=LUNGE_B, spine=[14, -18, 0])),   # 投げる
        (0.32, mix(ready, armL=FOLLOW, armR=OUT_LO, legL=LUNGE_F, legR=LUNGE_B, spine=[18, -22, 0])),
        (0.6, ready)], legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.13, mix(ready, armL=GROUND, armR=GROUND, legL=SQUAT, legR=SQUAT, spine=[40, 0, 0], head=[-15, 0, 0])),   # 足もとに置く
        (0.3, mix(ready, armL=OUT_LO, armR=OUT_LO, legL=SQUAT, legR=SQUAT, spine=[20, 0, 0])),
        (0.45, mix(ready, armL=WIDE_UP, armR=WIDE_UP, legL=TUCK, legR=TUCK, spine=[-10, 0, 0], air=True)),           # 後ろへ跳ぶ
        (0.75, mix(ready, armL=OUT_LO, armR=OUT_LO, legL=SQUAT, legR=SQUAT, spine=[18, 0, 0])),
        (0.95, ready)], legs=st)
    X = pose_anim([
        (0.0, ready),
        (0.16, mix(ready, armL=BACK, armR=BACK, legL=SQUAT, legR=SQUAT, spine=[28, 0, 0])),        # 大きな箱を下から
        (0.35, mix(ready, armL=SKY_FWD, armR=SKY_FWD, legL=STAND, legR=STAND, spine=[-12, 0, 0], lift=0.04)),   # 放り上げる
        (0.6, mix(ready, armL=WIDE_UP, armR=WIDE_UP, spine=[-8, 0, 6], head=[-10, 0, 0])),          # ばんざい（道化）
        (0.8, mix(ready, armL=WIDE_UP, armR=WIDE_UP, spine=[-8, 0, -6])),
        (1.1, ready)], legs=st)
    uk = [(0.0, ready), (0.3, mix(ready, armL=SKY, armR=SKY, legL=SQUAT, legR=SQUAT, spine=[-6, 0, 0]))]
    for k in range(6):
        t = 0.6 + 0.2 * k
        left = k % 2 == 0
        uk.append((t - 0.08, mix(ready, armL=OVER if left else SKY, armR=SKY if left else OVER, spine=[-14, 0, 0], lift=0.02)))
        uk.append((t, mix(ready, armL=SKY_FWD if left else SKY, armR=SKY if left else SKY_FWD, spine=[-4, 0, 0])))
    uk += [(2.0, mix(ready, armL=WIDE_UP, armR=WIDE_UP)), (2.4, ready)]
    U = pose_anim(uk, legs=st)
    anims = {"Bomber_A": A, "Bomber_Y": Y, "Bomber_X": X, "Bomber_Ult": U}
    boom = lambda r, c="#ff9030": {"kind": "blast", "color": c, "radius": r, "life": 0.35}
    pres = lambda frm, prop, **kw: proj("arc", frm, speed=kw.pop("speed", 13.0), prop=prop, scale=kw.pop("scale", 1.0), rng=kw.pop("rng", 12.0),
                                        arc=kw.pop("arc", 2.4), spin=kw.pop("spin", 7.0), **kw)
    acts = {
        "normal": act("A", 0.6, 0.6, [hit(0.2, 1.0, proj=pres("hand_L", "present_pink", blast=2.0), fx=boom(2.0))], step(0.0, "Bomber_A"),
                      from_cd=True, stop=False, name="プレゼント投げ",
                      note="プレゼントの爆弾を、放物線で投げる（12m まで）。落ちた所で爆発（半径2m＝ダメージの範囲）"),
        "sub": act("Y", 0.95, 5.0, [hit(0.15, 3.0, proj=pres("hand_L", "present_green", land_at="self", arc=0.6, speed=6.0, on_land="present",
                                                             open_sec=0.55, boom_sec=1.1, blast=3.0))],
                   step(0.0, "Bomber_Y"), i_frames=True, stop=False, path_=path((0.0, 0.0, 0.0), (0.3, 0.0, 0.0), (0.6, -3.5, 0.9), (0.75, -3.6, 0.0), (0.95, -3.6, 0.0)),
                   name="置きプレゼント＆バックジャンプ",
                   note="足もとにプレゼントを置いて、後ろへ跳ぶ（跳んでいる間は無敵）。箱がゆれ、ふたが飛び、バネの道化が飛び出して爆発（半径3m）"),
        "main": act("X", 1.1, 7.0, [hit(0.35, 6.0, proj=pres("hand_L", "present_big", scale=1.1, arc=3.6, speed=11.0, on_land="present",
                                                             open_sec=0.45, boom_sec=1.0, blast=3.5), impact=IMPACT_M)], step(0.0, "Bomber_X"), stop=False,
                    name="びっくりプレゼント",
                    note="大きなプレゼントを放り上げる。落ちると、ゆれて、ふたが飛び、中からバネの道化と紙ふぶき、そして爆発（半径3.5m）"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(0.6 + 0.2 * k, 3.4, side=(k % 3 - 1) * 1.2,
                                               proj=pres("hand_L" if k % 2 == 0 else "hand_R", ["firework_red", "firework_gold", "firework_blue"][k % 3],
                                                         scale=1.6, arc=7.0, speed=14.0, rng=22.0, blast=3.5, spin=0.0),
                                               fx=boom(3.5, ["#ff5a3a", "#ffd23a", "#5ad1ff"][k % 3]), impact=IMPACT_ULT if k == 5 else None)
                                           for k in range(6)],
                        step(0.0, "Bomber_Ult"), i_frames=True, stop=False, name="大花火",
                        fx=[{"t": 0.3, "kind": "pillar", "color": "#ffd23a", "radius": 0.4, "tall": 10.0, "life": 0.6, "at": "self"}],
                        note="花火の玉を6つ、空高く打ち上げる。ボスの所に落ちて、赤・金・青に開く（半径3.5m ずつ）"),
    }
    for a in acts.values():
        for h in a["hits"]:
            if "impact" in h and h["impact"] is None:
                h.pop("impact")
            if "fx" in h and h["fx"].get("kind") == "blast":
                h["fx"]["confetti"] = a["label"] == "必殺"
    return acts, anims


# ------------------------------------------------------------------ 魔法使い（黄。魔法はむらさき）
def mage():
    st = (((0.04, -1, 0.06), (0.0, -1, -0.12)), ((0.04, -1, -0.01), (0.03, -1, -0.02)))
    STAFF = ((0.42, -0.9, 0.08), (0.45, -0.42, 0.78))       # 左手でつえ（立てて持つ）
    REST_R = ((0.12, -1, 0.15), (-0.55, -0.15, 0.82))
    THRUST = ((0.12, -0.25, 0.96), (0.05, 0.12, 1))         # つえの先を前へ
    STAFF_UP = ((0.3, 0.88, 0.35), (0.12, 0.96, 0.25))       # つえを高くかかげる
    PALM = ((0.25, -0.1, 0.96), (0.15, 0.15, 0.98))          # 右手の手のひらを前へ
    ready = P(STAFF, REST_R, spine=[0, 0, -3])
    A = pose_anim([
        (0.0, ready),
        (0.08, mix(ready, armL=((0.4, -0.6, -0.2), (0.4, 0.1, 0.6)), armR=OUT_LO, spine=[-4, 10, 0])),   # 引く
        (0.17, mix(ready, armL=THRUST, armR=OUT_LO, spine=[10, -18, 0], legL=((0.06, -0.9, 0.4), (0.02, -1, -0.04)))),  # 突き出す（撃つ）
        (0.3, mix(ready, armL=THRUST, armR=OUT_LO, spine=[8, -16, 0], legL=((0.06, -0.9, 0.4), (0.02, -1, -0.04)))),
        (0.5, ready)], legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.25, mix(ready, armL=STAFF_UP, armR=PALM, legL=WIDE, legR=WIDE, spine=[-10, 0, 0], head=[-12, 0, 0])),   # ためる
        (1.05, mix(ready, armL=STAFF_UP, armR=PALM, legL=WIDE, legR=WIDE, spine=[-12, 0, 0], head=[-12, 0, 0])),
        (1.2, mix(ready, armL=THRUST, armR=OUT_LO, legL=LUNGE_F, legR=LUNGE_B, spine=[16, -14, 0])),            # 放つ
        (1.4, mix(ready, armL=THRUST, armR=OUT_LO, legL=LUNGE_F, legR=LUNGE_B, spine=[14, -12, 0])),
        (1.6, ready)], legs=st, extra_offsets={"spine02": tremble(0.3, 1.0, 1.2, 0.07)})
    X = pose_anim([
        (0.0, ready),
        (0.3, mix(ready, armL=STAFF_UP, armR=SKY, spine=[-14, 0, 0], head=[-18, 0, 0], lift=0.06, air=True)),
        (0.8, mix(ready, armL=STAFF_UP, armR=SKY, spine=[-14, 0, 0], head=[-18, 0, 0], lift=0.06, air=True)),
        (1.0, ready)], legs=st)
    U = pose_anim([
        (0.0, ready),
        (0.35, mix(ready, armL=STAFF_UP, armR=WIDE_UP, spine=[-18, 0, 0], head=[-22, 0, 0], lift=0.12, air=True)),   # 空へ呼びかける
        (1.3, mix(ready, armL=STAFF_UP, armR=WIDE_UP, spine=[-20, 0, 0], head=[-24, 0, 0], lift=0.14, air=True)),
        (1.5, mix(ready, armL=THRUST, armR=PALM, legL=LUNGE_F, legR=LUNGE_B, spine=[16, -10, 0])),               # 敵を指す
        (1.9, mix(ready, armL=THRUST, armR=PALM, legL=LUNGE_F, legR=LUNGE_B, spine=[14, -10, 0])),
        (2.2, ready)], legs=st)
    anims = {"Mage_A": A, "Mage_Y": Y, "Mage_X": X, "Mage_Ult": U}
    acts = {
        "normal": act("A", 0.5, 0.5, [hit(0.17, 1.0, proj=proj("homing", "staff_tip", speed=17.0, prop="magic_orb", scale=1.1, rng=16.0, radius=0.35,
                                                               turn_deg=140.0, aim_h=0.5), fx={"size": 0.7, "color": "#d9a8ff"})],
                      step(0.0, "Mage_A"), from_cd=True, stop=False,
                      fx=[{"t": 0.17, "kind": "spark", "color": "#d9a8ff", "size": 0.5, "life": 0.2, "from": "staff_tip", "at": "socket"}],
                      name="マジックショット", note="つえの先から、むらさきの魔法の玉。ゆるく敵を追いかける（1秒に140度まで曲がる）"),
        "sub": act("Y", 1.6, 6.0, [hit(1.2, 4.0, proj=proj("homing", "staff_tip", speed=12.0, prop="magic_big", scale=1.3, rng=18.0, radius=0.7,
                                                            turn_deg=90.0, aim_h=0.5), impact=IMPACT_S, fx={"size": 1.3, "color": "#c08bff"})],
                   step(0.0, "Mage_Y"),
                   fx=[{"t": 0.2, "kind": "prop", "prop": "magic_circle", "scale": 1.5, "life": 1.0, "at": "self", "y": 0.06},
                       {"t": 0.25, "kind": "rise", "color": "#c9a2ff", "life": 0.9, "at": "self"},
                       {"t": 1.2, "kind": "spark", "color": "#e6c8ff", "size": 0.9, "life": 0.25, "from": "staff_tip", "at": "socket"}],
                   stop=False, name="チャージ魔法", note="足もとに魔法陣。0.95秒ためてから、大きな魔法の玉（ゆっくり追いかける）"),
        "main": act("X", 1.0, 18.0, [], step(0.0, "Mage_X"), stop=False,
                    effects=[{"t": 0.55, "type": "time_stop", "sec": 3.0, "resist_sec": 20.0, "resist_mult": 0.5, "color": "#b9a8ff"}],
                    fx=[{"t": 0.5, "kind": "ring", "color": "#b9a8ff", "radius": 8.0, "life": 0.6, "at": "self"},
                        {"t": 0.3, "kind": "prop", "prop": "magic_circle", "scale": 2.2, "life": 0.7, "at": "self", "y": 0.06}],
                    name="時間停止", note="ボスを3秒止める（攻撃も止まる。味方は普通に攻撃できる）。止めて20秒以内にまた使うと、ボスの耐性で半分（1.5秒）"),
        "ultimate": act("必殺", 2.2, 0.0, [hit(1.3, 19.0, proj=proj("straight", "@sky", speed=24.0, prop="meteor", scale=2.2, rng=40.0, radius=1.6, aim_h=0.3,
                                                                    life=3.0), impact=IMPACT_ULT,
                                               fx={"kind": "blast", "color": "#ff7a2a", "radius": 4.5, "life": 0.6, "size": 2.0, "big": True})],
                        step(0.0, "Mage_Ult"), i_frames=True, stop=False, name="メテオ",
                        fx=[{"t": 0.3, "kind": "prop", "prop": "magic_circle_gold", "scale": 3.0, "life": 1.3, "at": "target", "y": 0.08}],
                        note="空へ呼びかけ、大きな火の玉（いん石）を、敵の上から落とす。当たった所で大爆発（半径4.5m の見た目）"),
    }
    return acts, anims


# ------------------------------------------------------------------ アーマー（青）
def guardian():
    st = (WIDE, WIDE)
    SHIELD = ((0.25, -0.35, 0.9), (0.05, 0.2, 1.0))           # 盾（左腕）を前に
    SHIELD_HI = ((0.15, -0.05, 1), (-0.2, 0.35, 0.92))
    SHIELD_UP = ((0.18, 0.72, 0.68), (0.0, 1.0, 0.3))
    MACE = ((0.22, -0.95, 0.2), (0.1, -0.55, 0.83))            # 右手の棍棒
    SMASH = ((0.0, -0.25, 0.97), (0.0, -0.72, 0.7))
    ready = P(SHIELD, MACE, spine=[6, 0, 0])
    A = pose_anim([
        (0.0, ready),
        (0.13, mix(ready, armR=OVER, spine=[-10, -18, 0], head=[-6, 8, 0])),                       # ふりかぶる
        (0.26, mix(ready, armR=SMASH, legL=LUNGE_F, legR=LUNGE_B, spine=[24, 14, 0])),           # 振り下ろす
        (0.36, mix(ready, armR=SMASH, legL=LUNGE_F, legR=LUNGE_B, spine=[22, 12, 0])),
        (0.5, ready)], legs=st)
    yk = [(0.0, ready), (0.1, mix(ready, armL=SHIELD_HI, legL=CROUCH_F, legR=CROUCH_B, spine=[24, 0, 0]))]
    for k, t in enumerate((0.18, 0.26, 0.34)):
        a, b = (LUNGE_F, LUNGE_B) if k % 2 == 0 else (LUNGE_B, LUNGE_F)
        yk.append((t, mix(ready, armL=SHIELD_HI, legL=a, legR=b, spine=[26, 0, 0])))
    yk += [(0.42, mix(ready, armL=SHIELD_HI, legL=LUNGE_F, legR=LUNGE_B, spine=[30, -8, 0])),
           (0.58, mix(ready, armL=SHIELD_HI, legL=LUNGE_F, legR=LUNGE_B, spine=[26, -6, 0])), (0.8, ready)]
    Y = pose_anim(yk, legs=st)
    X = pose_anim([
        (0.0, ready),
        (0.3, mix(ready, armL=SHIELD_UP, armR=SKY, spine=[-12, 0, 0], head=[-10, 0, 0])),        # 盾と棍棒をかかげる
        (0.48, mix(ready, armL=SHIELD_HI, armR=GROUND, legL=SQUAT, legR=SQUAT, spine=[30, 0, 0])),  # 地面をたたいて、膜を張る
        (0.75, mix(ready, armL=SHIELD_HI, armR=GROUND, legL=SQUAT, legR=SQUAT, spine=[28, 0, 0])),
        (1.0, ready)], legs=st)
    U = pose_anim([
        (0.0, ready),
        (0.35, mix(ready, armR=OVER, armL=SHIELD_UP, legL=SQUAT, legR=SQUAT, spine=[-6, -10, 0])),   # しずんで、ふりかぶる
        (0.6, mix(ready, armR=SKY, armL=SHIELD_UP, legL=TUCK, legR=TUCK, spine=[-14, -6, 0], air=True)),   # 跳ぶ
        (0.88, mix(ready, armR=GROUND, armL=SHIELD_HI, legL=SQUAT, legR=SQUAT, spine=[38, 6, 0])),  # 地面をたたく
        (1.25, mix(ready, armR=GROUND, armL=SHIELD_HI, legL=SQUAT, legR=SQUAT, spine=[34, 4, 0])),
        (1.8, ready)], legs=st)
    anims = {"Guardian_A": A, "Guardian_Y": Y, "Guardian_X": X, "Guardian_Ult": U}
    acts = {
        "normal": act("A", 0.5, 0.5, [hit(0.26, 1.4, fx={"size": 0.8})], step(0.0, "Guardian_A"), from_cd=True, aim=False, stop=False, cleave=False,
                      radius_scale=1.2, name="棍棒", note="とげ鉄球の棍棒を、ふりかぶって振り下ろす"),
        "sub": act("Y", 0.8, 5.0, [hit(0.42, 3.0, impact=IMPACT_S, fx={"kind": "blast", "color": "#7fb4ff", "radius": 1.4, "life": 0.25, "at": "front", "dist": 1.5, "size": 1.0})],
                   step(0.0, "Guardian_Y"), i_frames=True, radius_scale=1.3, name="シールドチャージ",
                   path_=path((0.0, 0.0, 0.0), (0.1, 0.0, 0.0), (0.42, 3.5, 0.0), (0.8, 3.6, 0.0)), note="盾を前に、体当たり。走っている間は無敵"),
        "main": act("X", 1.0, 20.0, [], step(0.0, "Guardian_X"), stop=False, aim=False,
                    effects=[{"t": 0.48, "type": "dome", "sec": 6.0, "radius": 5.0, "attack_mult": 0.5, "taken_mult": 0.5, "color": "#4f9bff"}],
                    fx=[{"t": 0.48, "kind": "ring", "color": "#9fd0ff", "radius": 5.0, "life": 0.5, "at": "self"}],
                    name="シールドドーム", note="青い半透明の膜（半径5m・6秒）。膜の中の味方は受けるダメージが減り、攻撃が当たると膜に波紋。膜の中からの攻撃は弱くなる"),
        "ultimate": act("必殺", 1.8, 0.0, [hit(0.88, 32.0, shape="self", radius=6.0, impact=IMPACT_ULT,
                                               fx={"kind": "blast", "color": "#7fb4ff", "radius": 6.0, "life": 0.5, "at": "self", "size": 1.6})],
                        step(0.0, "Guardian_Ult"), i_frames=True, stop=False, name="アースクエイク",
                        path_=path((0.0, 0.0, 0.0), (0.35, 0.0, 0.0), (0.62, 0.4, 1.4), (0.88, 0.6, 0.0), (1.8, 0.6, 0.0)),
                        effects=[{"t": 0.88, "type": "dome", "sec": 8.0, "radius": 7.0, "attack_mult": 0.5, "taken_mult": 0.5, "color": "#4f9bff"}],
                        fx=[{"t": 0.88, "kind": "ring", "color": "#9fd0ff", "radius": 8.0, "life": 0.6, "at": "self"}],
                        note="跳び上がって、棍棒で地面をたたく（まわり6m）。そのまま大きな守りの膜（半径7m・8秒）を張る"),
    }
    return acts, anims


# ------------------------------------------------------------------ おもちゃの兵隊（黄）
def summoner():
    st = (STAND, STAND)
    ready = P(HUG, HUG)
    POINT = ((0.08, 0.15, 1), (0.04, 0.18, 1))
    A = pose_anim([
        (0.0, ready),
        (0.1, mix(ready, armR=BACK, spine=[-6, -14, 0])),                  # 後ろへ引く
        (0.18, mix(ready, armR=THROW, spine=[12, 10, 0], legL=((0.06, -0.9, 0.4), (0.02, -1, -0.04)))),   # 下から投げる
        (0.26, mix(ready, armR=FOLLOW, spine=[12, 10, 0], legL=((0.06, -0.9, 0.4), (0.02, -1, -0.04)))),
        (0.4, ready)], legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.2, mix(ready, armR=POINT, spine=[6, 10, 0])),                  # 前を指して、命令
        (0.6, mix(ready, armR=POINT, spine=[6, 10, 0])),
        (0.8, ready)], legs=st)
    X = pose_anim([
        (0.0, ready),
        (0.2, mix(ready, armR=SKY, legL=MARCH_UP, spine=[-8, 0, 0], plant="R")),     # 片足を上げて、手を高く
        (0.32, mix(ready, armR=SKY, spine=[-8, 0, 0])),                               # 足ぶみ
        (0.45, mix(ready, armR=POINT, legL=LUNGE_F, legR=LUNGE_B, spine=[14, 8, 0])),  # 「進め！」
        (0.85, mix(ready, armR=POINT, legL=LUNGE_F, legR=LUNGE_B, spine=[12, 8, 0])),
        (1.0, ready)], legs=st)
    uk = [(0.0, ready)]
    for k, t in enumerate((0.25, 0.45, 0.65, 0.85)):
        uk.append((t, mix(ready, armL=SKY, armR=SKY, legL=MARCH_UP if k % 2 == 0 else STAND, legR=STAND if k % 2 == 0 else MARCH_UP,
                          plant="R" if k % 2 == 0 else "L", spine=[-8, 0, 0])))
    uk += [(1.1, mix(ready, armL=POINT, armR=POINT, legL=LUNGE_F, legR=LUNGE_B, spine=[16, 0, 0])),
           (1.45, mix(ready, armL=POINT, armR=POINT, legL=LUNGE_F, legR=LUNGE_B, spine=[14, 0, 0])), (1.6, ready)]
    U = pose_anim(uk, legs=st)
    # 呼び出す小さい兵隊（summoner_mini）の動き：右の前腕に、おもちゃの銃
    PORT = ((0.12, -1, 0.1), (-0.45, 0.72, 0.52))       # 銃を胸の前で、斜めに立てる
    LARM = ((0.12, -1, 0.0), (0.08, -1, 0.1))
    AIMR = ((0.15, -0.3, 0.94), (-0.04, 0.02, 1))        # 銃をかまえる
    SUPPORT = ((0.05, -0.55, 0.83), (-0.65, 0.05, 0.76))  # 左手を銃にそえる
    mini_ready = P(LARM, PORT)
    MI = pose_anim([(0.0, mini_ready), (1.0, mix(mini_ready, spine=[2, 0, 0])), (2.0, mini_ready)], loop=True)
    MM = pose_anim([
        (0.0, mix(mini_ready, legL=MARCH_UP, armL=((0.12, -0.8, -0.6), (0.1, -0.8, -0.6)), plant="R")),
        (0.15, mix(mini_ready, lift=0.0)),
        (0.3, mix(mini_ready, legR=MARCH_UP, armL=((0.1, -0.75, 0.66), (0.08, -0.7, 0.71)), plant="L")),
        (0.45, mix(mini_ready, lift=0.0)),
        (0.6, mix(mini_ready, legL=MARCH_UP, armL=((0.12, -0.8, -0.6), (0.1, -0.8, -0.6)), plant="R"))], loop=True)
    shoot = P(SUPPORT, AIMR, legL=FIGHT_F, legR=FIGHT_B, spine=[4, -6, 0])
    MS = pose_anim([
        (0.0, mini_ready),
        (0.08, shoot),
        (0.12, mix(shoot, armR=((0.15, -0.15, 0.98), (-0.04, 0.3, 0.95)), spine=[-2, -6, 0])),   # 反動
        (0.28, shoot), (0.45, shoot)])
    anims = {"Toy_A": A, "Toy_Y": Y, "Toy_X": X, "Toy_Ult": U, "Mini_Idle": MI, "Mini_March": MM, "Mini_Shoot": MS}
    acts = {
        "normal": act("A", 0.4, 0.4, [hit(0.18, 1.3, proj=proj("arc", "hand_R", speed=12.0, prop="plush_bear", scale=0.55, rng=10.0, arc=1.8, blast=1.2, spin=9.0),
                                      fx={"kind": "blast", "color": "#ffd0e0", "radius": 1.2, "life": 0.22})], step(0.0, "Toy_A"),
                      from_cd=True, stop=False, name="ぬいぐるみ投げ", note="小さなくまのぬいぐるみを投げる（10m まで、落ちた所の半径1.2m）"),
        "sub": act("Y", 0.8, 10.0, [], step(0.0, "Toy_Y"), stop=False,
                   effects=[{"t": 0.3, "type": "summon", "unit": "plush", "count": 2, "sec": 8.0, "interval": 0.8, "multiplier": 0.6, "speed": 5.5,
                             "reach": 1.0, "max_active": 9, "spread": 1.8}],
                   fx=[{"t": 0.3, "kind": "ring", "color": "#f2b6c6", "radius": 2.0, "life": 0.4, "at": "self"}],
                   name="ぬいぐるみの突撃", note="ぬいぐるみを2体呼ぶ（8秒。敵へ跳ねて行き、0.8秒ごとにたたく）"),
        "main": act("X", 1.0, 16.0, [], step(0.0, "Toy_X"), stop=False,
                    effects=[{"t": 0.45, "type": "summon", "unit": "soldier", "count": 3, "sec": 10.0, "interval": 0.9, "multiplier": 0.55, "speed": 4.5,
                              "reach": 1.0, "max_active": 9, "spread": 2.2}],
                    fx=[{"t": 0.45, "kind": "ring", "color": "#ffd24a", "radius": 3.0, "life": 0.5, "at": "self"}],
                    name="兵隊よ、進め！", note="小さいおもちゃの兵隊を3人呼ぶ（10秒）。重ならずに並び、立ち上がり、敵へ行進して、小さな弾を撃つ。本体の攻撃力には足さない"),
        "ultimate": act("必殺", 1.6, 0.0, [], step(0.0, "Toy_Ult"), i_frames=True, stop=False, name="おもちゃの大行進",
                        effects=[{"t": 1.1, "type": "summon", "unit": "soldier", "count": 6, "sec": 9.0, "interval": 0.7, "multiplier": 0.5, "speed": 5.0,
                                  "reach": 1.0, "max_active": 12, "spread": 2.8},
                                 {"t": 1.15, "type": "summon", "unit": "plush", "count": 3, "sec": 9.0, "interval": 0.6, "multiplier": 0.5, "speed": 6.5,
                                  "reach": 1.1, "max_active": 12, "spread": 1.6}],
                        fx=[{"t": 1.1, "kind": "ring", "color": "#ffd24a", "radius": 5.0, "life": 0.6, "at": "self"},
                            {"t": 1.1, "kind": "confetti", "life": 1.2, "at": "self"}],
                        note="兵隊6人とぬいぐるみ3体の大行進（9秒）"),
    }
    return acts, anims


# ------------------------------------------------------------------ エンジェル（緑）
def healer():
    st = (((0.03, -1, 0.1), (0.0, -0.9, -0.45)), ((0.04, -1, 0.02), (0.02, -1, -0.1)))
    BOW_IDLE = ((0.3, -0.9, 0.2), (0.25, -0.7, 0.65))
    R_IDLE = ((0.25, -0.95, 0.15), (0.2, -0.6, 0.75))
    BOW_OUT = ((0.05, 0.12, 1), (0.03, 0.12, 1))            # 弓の腕をのばす
    DRAW = ((0.35, 0.12, -0.93), (-0.62, 0.12, 0.78))         # 弦を引く（右手はあごの横）
    LOOSE = ((0.45, 0.15, -0.88), (0.5, 0.2, -0.85))          # 放した後、手が後ろへ
    ready = P(BOW_IDLE, R_IDLE, lift=0.12, air=True)
    A = pose_anim([
        (0.0, ready),
        (0.08, mix(ready, armL=BOW_OUT, armR=((0.2, -0.1, 0.97), (0.0, 0.1, 1)), spine=[2, -20, 0])),   # 弓をかまえる
        (0.17, mix(ready, armL=BOW_OUT, armR=DRAW, spine=[0, -30, 0])),                                # 引く
        (0.2, mix(ready, armL=BOW_OUT, armR=LOOSE, spine=[-2, -30, 0])),                               # 放つ
        (0.3, mix(ready, armL=BOW_OUT, armR=LOOSE, spine=[-2, -28, 0])),
        (0.4, ready)], base=("Walk", 0.36), legs=st)
    Y = pose_anim([
        (0.0, ready),
        (0.25, mix(ready, armL=PRAY, armR=PRAY, spine=[8, 0, 0], head=[12, 0, 0], lift=0.16)),       # 胸の前で、手を合わせる
        (0.45, mix(ready, armL=FWD, armR=FWD, spine=[-4, 0, 0], lift=0.18)),                           # 前へ押し出す
        (0.6, mix(ready, armL=FWD, armR=FWD, spine=[-4, 0, 0], lift=0.18)),
        (0.8, ready)], legs=st)
    X = pose_anim([
        (0.0, ready),
        (0.3, mix(ready, armL=WIDE_UP, armR=WIDE_UP, spine=[-14, 0, 0], head=[-14, 0, 0], lift=0.3)),
        (1.1, mix(ready, armL=WIDE_UP, armR=WIDE_UP, spine=[-16, 0, 0], head=[-16, 0, 0], lift=0.32)),
        (1.4, ready)], legs=st)
    U = pose_anim([
        (0.0, ready),
        (0.35, mix(ready, armL=PRAY, armR=PRAY, spine=[10, 0, 0], head=[18, 0, 0], lift=0.3)),
        (0.8, mix(ready, armL=SKY, armR=SKY, spine=[-18, 0, 0], head=[-20, 0, 0], lift=0.45)),
        (1.3, mix(ready, armL=SKY, armR=SKY, spine=[-20, 0, 0], head=[-22, 0, 0], lift=0.45)),
        (1.5, mix(ready, armL=FWD, armR=FWD, spine=[8, 0, 0], lift=0.3)),
        (1.8, mix(ready, armL=FWD, armR=FWD, spine=[6, 0, 0], lift=0.25)),
        (2.0, ready)], legs=st)
    anims = {"Angel_A": A, "Angel_Y": Y, "Angel_X": X, "Angel_Ult": U}
    acts = {
        "normal": act("A", 0.4, 0.4, [hit(0.2, 1.4, proj=proj("straight", "bow", speed=36.0, prop="heart_arrow", scale=1.4, rng=16.0, radius=0.3, aim_h=0.5),
                                      fx={"size": 0.6, "color": "#ff8aa8"})], step(0.0, "Angel_A"),
                      from_cd=True, stop=False, name="ハートの矢", note="金の弓で、ハートの矢を射る（16m まで。当たった時にダメージ）"),
        "sub": act("Y", 0.8, 6.0, [], step(0.0, "Angel_Y"), stop=False, aim=False,
                   effects=[{"t": 0.45, "type": "heal_shot", "amount": 40.0, "speed": 14.0, "prop": "heal_orb", "from": "hand_R"}],
                   name="いやしの光", note="いちばん減っている味方（味方をタップすれば、その味方）へ、回復の光を飛ばす（40回復）"),
        "main": act("X", 1.4, 25.0, [], step(0.0, "Angel_X"), stop=False, aim=False,
                    effects=[{"t": 0.6, "type": "heal_dome", "sec": 6.0, "radius": 5.0, "per_sec": 8.0, "revive_after": 2.0, "hp_ratio": 0.5, "color": "#4fe08a"}],
                    fx=[{"t": 0.6, "kind": "ring", "color": "#9dffb8", "radius": 5.0, "life": 0.5, "at": "self"}],
                    name="いやしのドーム", note="緑の半透明の膜（半径5m・6秒）。中の味方は1秒に8回復。倒れた味方は、2秒で体力50%で起きる"),
        "ultimate": act("必殺", 2.0, 0.0, [hit(1.55, 40.0, shape="blast", at_boss=True, max_dist=20.0, radius=3.5, impact=IMPACT_ULT,
                                               fx={"kind": "pillar", "color": "#c8ffd8", "radius": 3.0, "tall": 12.0, "life": 0.8})],
                        step(0.0, "Angel_Ult"), i_frames=True, stop=False, aim=True, name="エンジェルレイ",
                        effects=[{"t": 1.0, "type": "heal", "amount": 999.0, "radius": 99.0, "color": "#9dffb8"},
                                 {"t": 1.0, "type": "revive", "radius": 99.0, "hp_ratio": 0.5, "color": "#9dffb8"}],
                        note="緑の光で、味方全員を全回復（倒れた味方も起こす）。そして、ボスに光の柱を落とす"),
    }
    return acts, anims


CHARS = {"brawler": brawler, "sprinter": sprinter, "gunner": gunner, "bomber": bomber, "mage": mage, "guardian": guardian,
         "summoner": summoner, "healer": healer}
NAMES = {"brawler": "ファイター", "sprinter": "スピードファイター", "gunner": "ガンナー", "bomber": "ボンバー", "mage": "魔法使い",
         "guardian": "アーマー", "summoner": "おもちゃの兵隊", "healer": "エンジェル"}


def build(cid):
    _CUR["id"] = cid
    return CHARS[cid]()


# ------------------------------------------------------------------ 版79：キャラごとの待ちの姿勢（くり返す）
DOWN_L = [0.08, -1.0, 0.04]
LEG_STRAIGHT = {"upperleg01.L": [[0.0, [0.03, -1.0, 0.0], 1.0]], "lowerleg01.L": [[0.0, [0.02, -1.0, -0.03], 1.0]],
                "upperleg01.R": [[0.0, [-0.03, -1.0, 0.0], 1.0]], "lowerleg01.R": [[0.0, [-0.02, -1.0, -0.03], 1.0]]}


def breathe(period=2.4, amp=2.0, bob=0.006, extra=None):
    """息をする：胸が少し上下し、体が少し上下する（くり返しの1周 period 秒）"""
    n = 4
    spine = [[period * i / n, [amp * (1 if i % 2 else 0), 0, 0]] for i in range(n + 1)]
    lift = [[period * i / n, bob * (1 if i % 2 else 0) - bob * 0.5] for i in range(n + 1)]
    d = {"offsets": {"spine01": spine}, "root_lift": lift}
    if extra:
        d["offsets"].update(extra)
    return d


def idle_anim(base, period, aim, offsets=None, lift=None, amp=2.0, bob=0.006):
    b = breathe(period, amp, bob, offsets)
    spec = {"segments": [hold(base[0], base[1], period)], "loop": True, "aim": aim, "offsets": b["offsets"], "root_lift": lift or b["root_lift"],
            "blend": 0.0}
    return spec


def idles():
    W = ("Walk", 0.36)
    out = {}
    # ファイター：ボクシングの構えで、軽く弾む
    out["brawler"] = {"Brawler_Idle": {"segments": [hold("Punch", 0.03, 0.8)], "loop": True, "blend": 0.0,
                                       "root_lift": [[0.0, 0.0], [0.2, -0.035], [0.4, 0.0], [0.6, -0.035], [0.8, 0.0]],
                                       "offsets": {"spine03": [[0.0, [0, 6, 0]], [0.4, [0, -6, 0]], [0.8, [0, 6, 0]]]}}}
    # スピードファイター：前かがみで、つま先で小きざみに弾む（走り出す前）
    out["sprinter"] = {"Sprinter_Idle": {"segments": [hold("Idle", 0.3, 0.6)], "loop": True, "blend": 0.0,
                                         "root_lift": [[0.0, 0.0], [0.15, -0.025], [0.3, 0.0], [0.45, -0.025], [0.6, 0.0]],
                                         "offsets": {"spine03": [[0.0, [10, 0, 0]], [0.6, [10, 0, 0]]]}}}
    # ガンナー：足を開いて立ち、両腕の大砲を、少し下に向けて前に構える
    gun = [0.12, -0.55, 0.82]
    out["gunner"] = {"Gunner_Idle": idle_anim(("Idle", 0.3), 2.6, {"upperarm01*": [[0.0, [0.25, -0.85, 0.45], 1.0]], "lowerarm01*": [[0.0, gun, 1.0]]},
                                              amp=1.5, bob=0.008)}
    # ボンバー：プレゼントを両手にかかえて、ぴょこぴょこ弾む（道化）
    out["bomber"] = {"Bomber_Idle": idle_anim(W, 1.0, dict({"upperarm01*": [[0.0, [0.5, -0.75, 0.35], 1.0]], "lowerarm01*": [[0.0, [0.45, -0.1, 0.9], 1.0]]},
                                                            **LEG_STRAIGHT),
                                              offsets={"spine03": [[0.0, [0, 0, 5]], [0.5, [0, 0, -5]], [1.0, [0, 0, 5]]]},
                                              lift=[[0.0, 0.0], [0.25, 0.045], [0.5, 0.0], [0.75, 0.045], [1.0, 0.0]])}
    # 魔法使い：すっと立ち、左手でつえを持ち、右手は胸の前（片ひざを少し曲げる）
    out["mage"] = {"Mage_Idle": idle_anim(W, 3.0, {
        "upperarm01.L": [[0.0, [0.42, -0.9, 0.08], 1.0]], "lowerarm01.L": [[0.0, [0.45, -0.42, 0.78], 1.0]],
        "upperarm01.R": [[0.0, [-0.12, -1.0, 0.15], 1.0]], "lowerarm01.R": [[0.0, [0.55, -0.15, 0.82], 1.0]],
        "upperleg01.L": [[0.0, [-0.02, -1.0, 0.06], 1.0]], "lowerleg01.L": [[0.0, [0.0, -1.0, -0.12], 1.0]],
        "upperleg01.R": [[0.0, [-0.04, -1.0, -0.01], 1.0]], "lowerleg01.R": [[0.0, [-0.03, -1.0, -0.02], 1.0]]},
        offsets={"spine03": [[0.0, [0, 0, -3]], [3.0, [0, 0, -3]]]}, amp=1.5, bob=0.004)}
    # アーマー：足を大きく開き、盾を前に構え、ゆっくり息をする
    out["guardian"] = {"Guardian_Idle": idle_anim(("Idle", 0.3), 3.2, {"upperarm01.L": [[0.0, [0.25, -0.35, 0.9], 1.0]],
                                                                       "lowerarm01.L": [[0.0, [0.05, 0.2, 1.0], 1.0]]}, amp=2.5, bob=0.012)}
    # おもちゃの兵隊：気をつけの姿勢で、ぬいぐるみを胸にだく
    out["summoner"] = {"Toy_Idle": idle_anim(W, 2.0, dict({"upperarm01*": [[0.0, [0.12, -1.0, 0.25], 1.0]],
                                                            "lowerarm01*": [[0.0, [-0.55, 0.12, 0.83], 1.0]]}, **LEG_STRAIGHT), amp=1.0, bob=0.004)}
    # エンジェル：少しうき上がり、片ひざを曲げて、ゆっくり上下する。弓を左手に
    out["healer"] = {"Angel_Idle": idle_anim(W, 3.0, {
        "upperarm01.L": [[0.0, [0.3, -0.9, 0.2], 1.0]], "lowerarm01.L": [[0.0, [0.25, -0.7, 0.65], 1.0]],
        "upperarm01.R": [[0.0, [-0.25, -0.95, 0.15], 1.0]], "lowerarm01.R": [[0.0, [-0.2, -0.6, 0.75], 1.0]],
        "upperleg01.L": [[0.0, [0.03, -1.0, 0.1], 1.0]], "lowerleg01.L": [[0.0, [0.0, -0.9, -0.45], 1.0]],
        "upperleg01.R": [[0.0, [-0.04, -1.0, 0.02], 1.0]], "lowerleg01.R": [[0.0, [-0.02, -1.0, -0.1], 1.0]]},
        lift=[[0.0, 0.12], [1.5, 0.18], [3.0, 0.12]], amp=1.5)}
    return out


IDLE_KEYS = {"brawler": "Brawler_Idle", "sprinter": "Sprinter_Idle", "gunner": "Gunner_Idle", "bomber": "Bomber_Idle", "mage": "Mage_Idle",
             "guardian": "Guardian_Idle", "summoner": "Toy_Idle", "healer": "Angel_Idle"}


# ------------------------------------------------------------------ 版79：勝った・負けた（全員。剣士も）
def common_anims():
    stand = P(HANG, HANG)
    win = pose_anim([
        (0.0, mix(stand, armL=WIDE_UP, armR=FIST_UP, spine=[-8, 0, 0], head=[-12, 0, 0])),
        (0.3, mix(stand, armL=WIDE_UP, armR=WIDE_UP, spine=[-12, 0, 0], head=[-15, 0, 0], legL=TUCK, legR=TUCK, air=True, lift=0.12)),
        (0.6, mix(stand, armL=FIST_UP, armR=WIDE_UP, spine=[-8, 0, 0], head=[-12, 0, 0])),
        (0.9, mix(stand, armL=WIDE_UP, armR=WIDE_UP, spine=[-12, 0, 0], head=[-15, 0, 0], legL=TUCK, legR=TUCK, air=True, lift=0.12)),
        (1.2, mix(stand, armL=WIDE_UP, armR=FIST_UP, spine=[-8, 0, 0], head=[-12, 0, 0]))], loop=True)
    knee = mix(stand, legL=KNEEL_F, legR=KNEEL_B, armL=((0.1, -0.9, 0.42), (0.0, -0.6, 0.8)), armR=((0.12, -0.95, 0.2), (0.05, -1, 0.1)),
               spine=[32, 0, 0], head=[25, 0, 0])
    lose = pose_anim([(0.0, knee), (1.0, mix(knee, spine=[35, 0, 0], head=[28, 0, 0])), (2.0, knee)], loop=True)
    return {"Win_Pose": win, "Lose_Pose": lose}


COMMON_KEYS = {"win": "Win_Pose", "lose": "Lose_Pose", "walk": "Walk"}


def all_anims():
    out = {}
    idl = idles()
    com = common_anims()
    for cid in CHARS:
        acts, anims = build(cid)
        out[cid] = dict(anims)
        out[cid].update(idl.get(cid, {}))
        out[cid].update(com)
    out["hero_swordsman"] = dict(com)
    return out


def anim_overrides():
    """キャラの動作（idle など）を、キャラ専用の動きに置きかえる"""
    out = {cid: dict({"idle": name}, **COMMON_KEYS) for cid, name in IDLE_KEYS.items()}
    out["hero_swordsman"] = dict(COMMON_KEYS)
    return out


def total(a, ap):
    return sum(h["multiplier"] for h in a.get("hits", [])) * ap


def main():
    chars = json.loads((ROOT / "data/characters.json").read_text(encoding="utf-8"))
    stats = {c["id"]: c["stats"] for c in chars["characters"]}
    data = {"_memo": "版79：キャラごとの攻撃（tools/make_char_actions.py が作る。手で書きかえない）。actions.json の同じ名前の動きを、キャラの分で置きかえる。"
                     "ダメージ = キャラの攻撃力 × 倍率。剣士は actions.json のまま。hits の proj は飛ぶ物（当たった時にダメージ）。_meta は役と色",
            "characters": {}}
    rows = []
    for cid in CHARS:
        acts, anims = build(cid)
        data["characters"][cid] = dict({"_meta": META[cid]}, **acts)
        ap = float(stats[cid]["attack_power"])
        for key, lab in (("normal", "A"), ("sub", "Y"), ("main", "X"), ("ultimate", "必殺")):
            a = acts[key]
            hs = a.get("hits", [])
            effs = ", ".join(e["type"] for e in a.get("effects", []))
            one = hs[0]["multiplier"] * ap if hs else 0.0
            cd = float(stats[cid]["attack_cooldown_sec"]) if key == "normal" else a["cooldown_sec"]
            shape = ("飛ぶ物（%s）" % hs[0]["proj"]["mode"]) if hs and "proj" in hs[0] else (hs[0].get("shape", "melee") if hs else "-")
            rows.append((NAMES[cid], META[cid]["role"], lab, a["name"], len(hs), one, total(a, ap), cd, a["duration_sec"], shape, effs))
    (ROOT / "data/char_actions.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    md = ["# キャラごとの攻撃（版79）", "",
          "tools/make_char_actions.py が作る表。ダメージ = 攻撃力 × 倍率（四捨五入しない値）。ゲージ制の必殺技は待ち時間 0。",
          "飛ぶ物（銃弾・魔法・プレゼント・矢・いん石）は、当たった時にダメージが入る。呼び出し（ぬいぐるみ・兵隊）は、1回ごとに 攻撃力×倍率。",
          "剣士（基準・変えない）：A 単純斬り 22.5（0.35秒）／Y かわし斬り 58.5（4秒）／X 五段斬り 18×5＝90（6秒）／必殺 切り捨て御免 346.5", "",
          "| キャラ | 役 | ボタン | 技 | 当たる回数 | 1回 | 合計 | 待ち時間（秒） | 長さ（秒） | 当たりの形 | 効果 |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append("| %s | %s | %s | %s | %d | %.2f | %.2f | %.2f | %.2f | %s | %s |" % r)
    (ROOT / "docs/char-actions-v79.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print("chars", list(data["characters"]))


if __name__ == "__main__":
    main()
