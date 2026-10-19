#!/usr/bin/env python3
"""版78：8人の味方の、キャラごとの攻撃（A＝通常・Y＝サブ・X＝メイン・必殺）と、その動き（アニメ）を作る。
書き出す物：
  data/char_actions.json  ：攻撃の時刻・当たりの形・ダメージの倍率・見た目・効果（scripts/combat/player_actions.gd が読む）
  （characters.json の built_anims と animations には、tools/make_looks.py が、ここの anims() を書きこむ）
  docs/char-actions-v78.md：ダメージの表（剣士との比べ）
ダメージ = キャラの攻撃力（characters.json の stats.attack_power）× 倍率。剣士の基準（22.5・58.5・18×5・346.5）は変えない。
動きの元は、剣士と同じ13この動き（Idle Run Sprint Walk Jump Jump_Start Jump_Land Punch Spell Sword_Attack Roll Hit Death）。
Punch と Spell は、左腕を前へ出す。Sword_Attack は右手で振る。骨のひねり（offsets）は左腕の値：
  z+ 腕を上げる、z− 下げる、x+ 体の前・内へ、x− 外へ（右腕は "*" で左右反対になる）。
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWORD = {"A": 22.5, "Y": 58.5, "X": 90.0, "ULT": 346.5, "A_cd": 0.35, "Y_cd": 4.0, "X_cd": 6.0}


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
    if label == "必殺":
        d["banner_sec"] = banner
    if note:
        d["note"] = note
    return d


def hit(t, mult, **shape):
    d = {"t": round(t, 3), "multiplier": mult}
    d.update(shape)
    return d


def step(t, anim, speed=1.0):
    return [{"t": t, "anim": anim, "speed": speed}]


# ------------------------------------------------------------------ ファイター
def brawler():
    rush = [hold("Punch", 0.02, 0.22)]
    for i in range(10):
        rush += [seg("Punch", 0.12, 0.27, 0.05), seg("Punch", 0.27, 0.12, 0.05),
                 seg("Punch", 0.12, 0.27, 0.05, mirror_arms=True), seg("Punch", 0.27, 0.12, 0.05, mirror_arms=True)]
    rush += [seg("Punch", 0.27, 0.6, 0.18)]
    anims = {
        "Brawler_A": {"segments": [seg("Punch", 0.05, 0.26, 0.09), hold("Punch", 0.26, 0.06), seg("Punch", 0.26, 0.6, 0.15)], "blend": 0.03},
        "Brawler_Y": {"segments": [seg("Punch", 0.0, 0.1, 0.2), seg("Punch", 0.1, 0.26, 0.14), hold("Punch", 0.26, 0.2), seg("Punch", 0.26, 0.7, 0.21)],
                      "offsets": {"upperarm01.L": [[0.0, [0, 0, -20]], [0.2, [0, 0, -25]], [0.3, [10, 0, 65]], [0.55, [10, 0, 60]], [0.75, [0, 0, 0]]],
                                  "spine03": [[0.0, [15, 0, 0]], [0.2, [20, 0, 0]], [0.32, [-15, 0, 0]], [0.75, [0, 0, 0]]]}, "blend": 0.04},
        "Brawler_X": {"segments": rush, "blend": 0.02},
        "Brawler_Ult": {"segments": [seg("Punch", 0.0, 0.08, 0.3), hold("Punch", 0.08, 0.45), seg("Punch", 0.08, 0.27, 0.12),
                                     hold("Punch", 0.27, 0.4), seg("Punch", 0.27, 0.86, 0.33)],
                        "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.6, [0, 40, 0]], [0.75, [0, 40, 0]], [0.87, [-10, -25, 0]], [1.3, [0, 0, 0]]]},
                        "blend": 0.05},
    }
    hit_fx = {"kind": "blast", "color": "#fff1c2", "radius": 0.7, "life": 0.14, "at": "front", "dist": 1.7, "height": 1.3}
    acts = {
        "normal": act("A", 0.3, 0.3, [hit(0.09, 1.2, fx=hit_fx)], step(0.0, "Brawler_A"), from_cd=True, aim=False, stop=False, cleave=False,
                      name="ジャブ", note="すばやいジャブ（左）。待ち時間はキャラの attack_cooldown_sec（0.3秒）"),
        "sub": act("Y", 0.75, 4.0, [hit(0.34, 3.6, fx={"kind": "blast", "color": "#ffb347", "radius": 1.3, "life": 0.25, "at": "front", "dist": 1.6})],
                   step(0.0, "Brawler_Y"), path_=path((0.0, 0.0, 0.0), (0.2, 0.2, 0.0), (0.34, 2.8, 0.25), (0.55, 3.0, 0.0), (0.75, 3.0, 0.0)),
                   radius_scale=1.4, name="ダッシュアッパー", note="前へ踏みこんで、下から突き上げる"),
        "main": act("X", 2.4, 7.0, [hit(0.27 + 0.1 * i, 0.42, fx=hit_fx) for i in range(20)], step(0.0, "Brawler_X"),
                    path_=path((0.0, 0.0, 0.0), (0.2, 0.3, 0.0), (2.2, 1.0, 0.0), (2.4, 1.0, 0.0)), radius_scale=1.25,
                    name="20連パンチ", note="左右の拳を交互に20発。1発ずつ計算する。2秒以上その場に立つので、反撃を受けやすい"),
        "ultimate": act("必殺", 1.6, 0.0, [hit(0.9, 23.0, fx={"kind": "blast", "color": "#ff9a2e", "radius": 3.0, "life": 0.45, "at": "front", "dist": 1.8})],
                        step(0.0, "Brawler_Ult"), i_frames=True, radius_scale=2.0, name="ギガトンブロー",
                        path_=path((0.0, 0.0, 0.0), (0.75, -0.3, 0.0), (0.88, 2.6, 0.0), (1.6, 2.6, 0.0)),
                        fx=[{"t": 0.0, "kind": "aura", "color": "#ffb347", "radius": 1.3, "life": 0.8, "alpha": 0.3},
                            {"t": 0.9, "kind": "ring", "color": "#ffd27a", "radius": 6.0, "life": 0.5, "at": "front", "dist": 1.8}],
                        note="力をためて、渾身の右ストレート"),
    }
    return acts, anims


# ------------------------------------------------------------------ スピードファイター
def sprinter():
    anims = {
        "Sprinter_A": {"segments": [seg("Punch", 0.08, 0.26, 0.07), hold("Punch", 0.26, 0.05), seg("Punch", 0.26, 0.55, 0.13)], "blend": 0.03},
        "Sprinter_Y": {"segments": [seg("Sprint", 0.0, 0.33, 0.12), seg("Sprint", 0.33, 0.66, 0.12), hold("Sprint", 0.66, 0.12),
                                    seg("Punch", 0.6, 0.86, 0.24)],
                       "offsets": {"spine03": [[0.0, [25, 0, 0]], [0.36, [30, 0, 0]], [0.6, [0, 0, 0]]]}, "blend": 0.04},
        "Sprinter_X": {"segments": [seg("Idle", 0.0, 0.3, 0.2), hold("Idle", 0.3, 0.3), seg("Idle", 0.3, 0.6, 0.2)],
                       "offsets": {"upperarm01*": [[0.0, [0, 0, 0]], [0.18, [-25, 0, -15]], [0.5, [-25, 0, -15]], [0.7, [0, 0, 0]]],
                                   "spine03": [[0.0, [0, 0, 0]], [0.2, [-15, 0, 0]], [0.5, [-15, 0, 0]], [0.7, [0, 0, 0]]]},
                       "root_lift": [[0.0, 0.0], [0.15, 0.06], [0.35, 0.0]], "blend": 0.05},
        "Sprinter_Ult": {"segments": [seg("Sprint", 0.0, 0.66, 0.25)] +
                         [s for i in range(8) for s in (seg("Punch", 0.12, 0.27, 0.06, mirror_arms=i % 2 == 1), seg("Punch", 0.27, 0.12, 0.06, mirror_arms=i % 2 == 1),
                                                       seg("Sprint", 0.0, 0.33, 0.1))] + [seg("Punch", 0.27, 0.86, 0.39)],
                         "blend": 0.03},
    }
    trail = {"kind": "slash", "color": "#5fd6ff", "width": 0.12, "life": 0.3, "alpha": 0.7, "height": 1.0}
    acts = {
        "normal": act("A", 0.25, 0.25, [hit(0.07, 1.0, fx={"kind": "blast", "color": "#a8ecff", "radius": 0.55, "life": 0.12, "at": "front", "dist": 1.6})],
                      step(0.0, "Sprinter_A"), from_cd=True, aim=False, stop=False, cleave=False, name="高速ジャブ"),
        "sub": act("Y", 0.6, 3.5, [hit(0.22, 3.5, fx={"kind": "blast", "color": "#5fd6ff", "radius": 1.0, "life": 0.2, "at": "front", "dist": 0.5})],
                   step(0.0, "Sprinter_Y"), path_=path((0.0, 0.0, 0.0), (0.22, 6.0, 0.0), (0.6, 6.0, 0.0)), stop=False, sweep=True, i_frames=True,
                   fx=[dict(trail, t=0.02, length=6.0, dist=3.0, at="front")], name="疾風ダッシュ",
                   note="6m を一気に駆けぬけて、通った道で当てる（ボスをすりぬける）。走っている間は無敵"),
        "main": act("X", 0.7, 15.0, [], step(0.0, "Sprinter_X"), effects=[{"t": 0.3, "type": "speed_mode", "sec": 6.0, "mult": 1.75, "color": "#5fd6ff"}],
                    fx=[{"t": 0.3, "kind": "ring", "color": "#5fd6ff", "radius": 3.0, "life": 0.4, "at": "self"}], aim=False, stop=False,
                    name="超高速モード", note="6秒、動く速さと攻撃の速さ（待ち時間の減り・通常攻撃の間かく）が1.75倍"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(0.4 + 0.25 * i, 3.5, shape="self", radius=4.0,
                                               fx={"kind": "blast", "color": "#a8ecff", "radius": 1.2, "life": 0.15, "at": "boss"}) for i in range(8)],
                        step(0.0, "Sprinter_Ult"), i_frames=True, stop=False, name="迅雷乱舞",
                        fx=[{"t": 0.3, "kind": "aura", "color": "#5fd6ff", "radius": 4.0, "life": 2.0, "alpha": 0.18, "at": "self"}],
                        note="目にもとまらぬ速さで、まわり4m の敵を8回打つ"),
    }
    return acts, anims


# ------------------------------------------------------------------ ガンナー
def gunner():
    aim = {"upperarm01*": [[0.0, [0, 0, 0]]]}
    anims = {
        "Gunner_A": {"segments": [hold("Spell", 0.1, 0.06, sym="L"), hold("Spell", 0.1, 0.24, sym="L")],
                     "offsets": {"upperarm01.L": [[0.0, [0, 0, 0]], [0.08, [0, 0, 12]], [0.3, [0, 0, 0]]]}, "blend": 0.03},
        "Gunner_Y": {"segments": [seg("Jump_Start", 0.3, 0.6, 0.2, arms_from={"anim": "Spell", "t": 0.1}),
                                  hold("Jump", 0.6, 0.35, arms_from={"anim": "Spell", "t": 0.1}),
                                  seg("Jump_Land", 0.0, 0.5, 0.25, arms_from={"anim": "Spell", "t": 0.1})],
                     "offsets": {"upperarm01.R": [[0.0, [0, 0, 0]]]}, "blend": 0.05},
        "Gunner_X": {"segments": [seg("Idle", 0.0, 0.2, 0.25, arms_from={"anim": "Spell", "t": 0.1}), hold("Spell", 0.1, 1.25, sym="L"),
                                  seg("Idle", 0.2, 0.4, 0.1)],
                     "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.3, [-8, 0, 0]], [1.5, [-8, 0, 0]], [1.6, [0, 0, 0]]],
                                 "upperarm01*": [[0.3, [0, 0, 0]], [0.35, [0, 0, 6]], [0.45, [0, 0, 0]], [0.55, [0, 0, 6]], [0.65, [0, 0, 0]],
                                                 [0.75, [0, 0, 6]], [0.85, [0, 0, 0]], [0.95, [0, 0, 6]], [1.05, [0, 0, 0]], [1.15, [0, 0, 6]], [1.3, [0, 0, 0]]]},
                     "blend": 0.06},
        "Gunner_Ult": {"segments": [seg("Idle", 0.0, 0.3, 0.4), hold("Spell", 0.1, 1.8, sym="L"), seg("Idle", 0.3, 0.6, 0.2)],
                       "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.5, [-12, 0, 0]], [2.2, [-12, 0, 0]], [2.4, [0, 0, 0]]]}, "blend": 0.08},
    }
    beam = {"kind": "beam", "color": "#ff4a3a", "width": 0.07, "life": 0.12, "length": 10.0, "height": 1.25}
    dbl = []
    for side in (-0.35, 0.35):
        dbl.append(dict(beam, t=0.3, width=0.16, life=1.1, length=14.0, side=side))
    acts = {
        "normal": act("A", 0.3, 0.3, [hit(0.06, 1.0, shape="beam", length=10.0, half_width=0.5, side=0.25)], step(0.0, "Gunner_A"),
                      fx=[dict(beam, t=0.05, side=0.25)], from_cd=True, stop=False, name="ショット", note="腕の大砲から1発（長さ10m の帯）"),
        "sub": act("Y", 0.8, 4.5, [hit(0.35, 2.6, shape="beam", length=12.0, half_width=0.7)], step(0.0, "Gunner_Y"),
                   fx=[dict(beam, t=0.34, width=0.12, life=0.18, length=12.0)], i_frames=True, stop=False,
                   path_=path((0.0, 0.0, 0.0), (0.4, -3.0, 0.9), (0.8, -3.2, 0.0)), name="バックステップ射撃",
                   note="後ろへ跳びながら撃つ。跳んでいる間は無敵"),
        "main": act("X", 1.6, 7.0, [hit(0.35 + 0.2 * i, 0.5, shape="beam", length=14.0, half_width=0.55, side=s)
                                   for i in range(6) for s in (-0.35, 0.35)], step(0.0, "Gunner_X"), fx=dbl, stop=False,
                    name="ダブルビーム", note="両腕から2本のビーム。1本ずつ当たりを調べる（同じ敵に2本とも当たる）。6回ずつ、つらぬく"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(0.55 + 0.17 * i, 2.3, shape="beam", length=18.0, half_width=1.4) for i in range(10)],
                        step(0.0, "Gunner_Ult"), i_frames=True, stop=False, name="フルバースト",
                        fx=[dict(beam, t=0.5, width=0.6, life=1.75, length=18.0, color="#ff6a2a"),
                            {"t": 0.1, "kind": "aura", "color": "#ff6a2a", "radius": 1.2, "life": 0.45, "alpha": 0.35}],
                        note="2つの大砲を合わせた、太いビーム（10回当たる）"),
    }
    return acts, anims


# ------------------------------------------------------------------ ボンバー
def bomber():
    throw = [seg("Punch", 0.0, 0.08, 0.12), seg("Punch", 0.08, 0.27, 0.12), seg("Punch", 0.27, 0.6, 0.2)]
    up = {"upperarm01.L": [[0.0, [0, 0, 10]], [0.12, [0, 0, 70]], [0.24, [0, 0, 25]], [0.44, [0, 0, 0]]]}
    anims = {
        "Bomber_A": {"segments": throw, "offsets": up, "blend": 0.03},
        "Bomber_Y": {"segments": [hold("Punch", 0.0, 0.08), seg("Jump_Start", 0.3, 0.6, 0.2), hold("Jump", 0.6, 0.4), seg("Jump_Land", 0.0, 0.5, 0.22)],
                     "offsets": {"upperarm01*": [[0.0, [0, 0, -30]], [0.1, [0, 0, -40]], [0.3, [0, 0, 20]], [0.9, [0, 0, 0]]]}, "blend": 0.05},
        "Bomber_X": {"segments": [seg("Punch", 0.0, 0.08, 0.1), seg("Punch", 0.08, 0.27, 0.1), seg("Punch", 0.27, 0.08, 0.1, mirror_arms=True),
                                  seg("Punch", 0.08, 0.27, 0.1, mirror_arms=True), seg("Punch", 0.27, 0.08, 0.1), seg("Punch", 0.08, 0.27, 0.1),
                                  seg("Punch", 0.27, 0.86, 0.6)],
                     "offsets": {"upperarm01*": [[0.0, [0, 0, 50]], [0.6, [0, 0, 50]], [0.9, [0, 0, 0]]]}, "blend": 0.03},
        "Bomber_Ult": {"segments": [seg("Idle", 0.0, 0.3, 0.3), hold("Idle", 0.3, 1.6), seg("Idle", 0.3, 0.8, 0.5)],
                       "offsets": {"upperarm01*": [[0.0, [0, 0, 0]], [0.3, [0, 0, 95]], [0.6, [0, 0, 80]], [0.75, [0, 0, 95]], [0.9, [0, 0, 80]],
                                                   [1.9, [0, 0, 80]], [2.3, [0, 0, 0]]],
                                   "spine03": [[0.0, [0, 0, 0]], [0.3, [-15, 0, 0]], [1.9, [-15, 0, 0]], [2.4, [0, 0, 0]]]},
                       "root_lift": [[0.0, 0.0], [0.3, 0.12], [0.5, 0.0]], "blend": 0.05},
    }
    orb = {"kind": "orb", "color": "#c04a8c", "radius": 0.13, "arc": 1.6, "height": 1.6, "at": "hit"}
    boom = {"kind": "blast", "color": "#ff9030", "life": 0.35}
    a_hit = {"shape": "blast", "at_boss": True, "max_dist": 7.0, "dist": 5.0, "radius": 2.0}
    acts = {
        "normal": act("A", 0.6, 0.6, [hit(0.52, 1.0, fx=dict(boom, radius=2.0), **a_hit)], step(0.0, "Bomber_A"),
                      fx=[dict(orb, t=0.12, life=0.4, hit=a_hit)], from_cd=True, stop=False, name="プレゼント投げ",
                      note="プレゼントの爆弾を投げる（7m まで、ボスの所で爆発、半径2m）"),
        "sub": act("Y", 0.95, 5.0, [hit(0.75, 3.0, shape="blast", dist=3.6, radius=3.0, fx=dict(boom, radius=3.0, color="#ff6a1a"))],
                   step(0.0, "Bomber_Y"), fx=[{"t": 0.05, "kind": "orb", "color": "#3d8a3f", "radius": 0.16, "arc": 0.0, "life": 0.7, "height": 0.2,
                                                "at": "self"}],
                   i_frames=True, stop=False, path_=path((0.0, 0.0, 0.0), (0.15, 0.0, 0.0), (0.55, -3.5, 0.9), (0.95, -3.6, 0.0)),
                   name="置き爆弾＆バックジャンプ", note="足もとに爆弾を置いて、後ろへ跳ぶ。跳んでいる間は無敵。置いた所が爆発（半径3m）"),
        "main": act("X", 1.2, 7.0, [hit(0.62 + 0.2 * k, 2.0, fx=dict(boom, radius=2.3), **dict(a_hit, side=s, radius=2.3))
                                   for k, s in enumerate((-1.3, 0.0, 1.3))], step(0.0, "Bomber_X"),
                    fx=[dict(orb, t=0.12 + 0.2 * k, life=0.5, hit=dict(a_hit, side=s)) for k, s in enumerate((-1.3, 0.0, 1.3))], stop=False,
                    name="3連プレゼント", note="左・まん中・右に3つ投げる。それぞれ半径2.3m。ボスが大きいので、3つとも当たることが多い"),
        "ultimate": act("必殺", 2.4, 0.0, [hit(1.0 + 0.2 * i, 3.4, shape="blast", at_boss=True, max_dist=20.0, radius=3.5, side=(i % 3 - 1) * 1.0,
                                               fx=dict(boom, radius=3.5, color=["#ff5a3a", "#ffd23a", "#5ad1ff"][i % 3])) for i in range(6)],
                        step(0.0, "Bomber_Ult"), i_frames=True, stop=False, name="大花火",
                        fx=[{"t": 0.3, "kind": "pillar", "color": "#ffd23a", "radius": 0.4, "tall": 10.0, "life": 0.6, "at": "self"}],
                        note="空へ打ち上げた花火が、ボスに6回ふりそそぐ"),
    }
    return acts, anims


# ------------------------------------------------------------------ 魔法使い
def mage():
    FWD = [0.0, 0.15, 1.0]
    UP = [0.1, 1.0, 0.15]
    REST = [-0.2, -1.0, 0.1]
    staff_up = [[0.0, [0.25, 0.1, 1.0], 0.0], [0.25, [0.25, 0.1, 1.0], 0.45], [0.9, [0.25, 0.1, 1.0], 0.45], [1.1, [0.25, 0.1, 1.0], 0.0]]
    anims = {
        "Mage_A": {"segments": [hold("Idle", 0.2, 0.5)],
                   "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.15, FWD, 1.0], [0.32, FWD, 1.0], [0.5, REST, 0.0]],
                           "lowerarm01.R": [[0.0, REST, 0.0], [0.15, FWD, 1.0], [0.32, FWD, 1.0], [0.5, REST, 0.0]]}},
        "Mage_Y": {"segments": [hold("Idle", 0.2, 1.6)],
                   "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [1.1, UP, 1.0], [1.25, FWD, 1.0], [1.45, FWD, 1.0], [1.6, REST, 0.0]],
                           "lowerarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [1.1, UP, 1.0], [1.25, FWD, 1.0], [1.45, FWD, 1.0], [1.6, REST, 0.0]]},
                   "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.3, [-10, 0, 0]], [1.1, [-10, 0, 0]], [1.3, [8, 0, 0]], [1.6, [0, 0, 0]]]}},
        "Mage_X": {"segments": [hold("Idle", 0.2, 1.0)],
                   "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [0.8, UP, 1.0], [1.0, REST, 0.0]],
                           "lowerarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [0.8, UP, 1.0], [1.0, REST, 0.0]],
                           "upperarm01.L": staff_up},
                   "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.25, [-12, 0, 0]], [0.8, [-12, 0, 0]], [1.0, [0, 0, 0]]]},
                   "root_lift": [[0.0, 0.0], [0.3, 0.08], [0.8, 0.08], [1.0, 0.0]]},
        "Mage_Ult": {"segments": [hold("Idle", 0.2, 2.2)],
                     "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.4, UP, 1.0], [1.6, FWD, 1.0], [1.9, FWD, 1.0], [2.2, REST, 0.0]],
                             "lowerarm01.R": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.4, UP, 1.0], [1.6, FWD, 1.0], [1.9, FWD, 1.0], [2.2, REST, 0.0]],
                             "upperarm01.L": [[0.0, [0.25, 0.1, 1.0], 0.0], [0.3, [0.25, 0.1, 1.0], 0.5], [1.9, [0.25, 0.1, 1.0], 0.5], [2.2, [0.25, 0.1, 1.0], 0.0]]},
                     "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.3, [-18, 0, 0]], [1.4, [-18, 0, 0]], [1.7, [8, 0, 0]], [2.2, [0, 0, 0]]]},
                     "root_lift": [[0.0, 0.0], [0.4, 0.15], [1.4, 0.15], [1.6, 0.0]]},
    }
    shot = {"shape": "blast", "at_boss": True, "max_dist": 9.0, "dist": 6.0, "radius": 1.0}
    big = {"shape": "blast", "at_boss": True, "max_dist": 10.0, "dist": 6.0, "radius": 2.4}
    acts = {
        "normal": act("A", 0.5, 0.5, [hit(0.3, 1.0, fx={"kind": "blast", "color": "#c070ff", "radius": 1.0, "life": 0.25}, **shot)], step(0.0, "Mage_A"),
                      fx=[{"t": 0.12, "kind": "orb", "color": "#c9a2ff", "radius": 0.12, "arc": 0.0, "life": 0.18, "height": 1.4, "at": "hit", "hit": shot}],
                      from_cd=True, stop=False, name="マジックショット", note="つえから魔法の玉（9m まで、半径1m）"),
        "sub": act("Y", 1.6, 6.0, [hit(1.32, 4.0, fx={"kind": "blast", "color": "#9a5cff", "radius": 2.4, "life": 0.45}, **big)], step(0.0, "Mage_Y"),
                   fx=[{"t": 0.15, "kind": "aura", "color": "#b9a8ff", "radius": 0.35, "life": 1.05, "alpha": 0.6, "height": 2.2, "at": "self"},
                       {"t": 1.18, "kind": "orb", "color": "#b9a8ff", "radius": 0.35, "arc": 0.5, "life": 0.14, "height": 2.0, "at": "hit", "hit": big}],
                   stop=False, name="チャージ魔法", note="1.1秒ためてから、大きな玉（半径2.4m）。ためている間は動けない"),
        "main": act("X", 1.0, 18.0, [], step(0.0, "Mage_X"), stop=False,
                    effects=[{"t": 0.55, "type": "time_stop", "sec": 3.0, "resist_sec": 20.0, "resist_mult": 0.5, "color": "#b9a8ff"}],
                    fx=[{"t": 0.5, "kind": "ring", "color": "#b9a8ff", "radius": 8.0, "life": 0.6, "at": "self"}],
                    name="時間停止", note="ボスを3秒止める（攻撃も止まる。味方は普通に攻撃できる）。止めて20秒以内にまた使うと、ボスの耐性で半分（1.5秒）"),
        "ultimate": act("必殺", 2.2, 0.0, [hit(1.62, 19.0, shape="blast", at_boss=True, max_dist=20.0, radius=4.5,
                                               fx={"kind": "blast", "color": "#8a4cff", "radius": 4.5, "life": 0.6})],
                        step(0.0, "Mage_Ult"), i_frames=True, stop=False, name="メテオ",
                        fx=[{"t": 0.3, "kind": "aura", "color": "#c9a2ff", "radius": 1.3, "life": 1.2, "alpha": 0.3, "at": "self"},
                            {"t": 1.25, "kind": "orb", "color": "#ff8a3a", "radius": 0.9, "arc": 9.0, "life": 0.37, "height": 6.0, "at": "boss"},
                            {"t": 1.62, "kind": "ring", "color": "#ffb36a", "radius": 7.0, "life": 0.6, "at": "boss"}],
                        note="空から大きな火の玉を落とす（半径4.5m）"),
    }
    return acts, anims


# ------------------------------------------------------------------ アーマー
def guardian():
    SH_F = [0.15, 0.2, 1.0]
    SH_UP = [0.15, 0.75, 0.8]
    REST_L = [0.2, -1.0, 0.1]
    anims = {
        "Guardian_A": {"segments": [seg("Sword_Attack", 0.12, 0.3, 0.14), seg("Sword_Attack", 0.3, 0.52, 0.14), seg("Sword_Attack", 0.52, 0.9, 0.22)],
                       "aim": {"upperarm01.L": [[0.0, SH_F, 1.0]], "lowerarm01.L": [[0.0, SH_F, 1.0]]}, "blend": 0.03},
        "Guardian_Y": {"segments": [seg("Run", 0.0, 0.46, 0.4), hold("Run", 0.46, 0.15), seg("Idle", 0.0, 0.3, 0.25)],
                       "aim": {"upperarm01.L": [[0.0, SH_F, 1.0], [0.55, SH_F, 1.0], [0.8, SH_F, 0.0]],
                               "lowerarm01.L": [[0.0, [0.0, 0.1, 1.0], 1.0], [0.55, [0.0, 0.1, 1.0], 1.0], [0.8, [0.0, 0.1, 1.0], 0.0]]},
                       "offsets": {"spine03": [[0.0, [20, 0, 0]], [0.5, [20, 0, 0]], [0.8, [0, 0, 0]]]}, "blend": 0.05},
        "Guardian_X": {"segments": [hold("Idle", 0.2, 1.0)],
                       "aim": {"upperarm01.L": [[0.0, REST_L, 0.0], [0.3, SH_UP, 1.0], [0.75, SH_UP, 1.0], [1.0, REST_L, 0.0]],
                               "lowerarm01.L": [[0.0, REST_L, 0.0], [0.3, [0.0, 1.0, 0.3], 1.0], [0.75, [0.0, 1.0, 0.3], 1.0], [1.0, REST_L, 0.0]]},
                       "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.3, [-10, 0, 0]], [0.75, [-10, 0, 0]], [1.0, [0, 0, 0]]]},
                       "root_lift": [[0.0, 0.0], [0.5, -0.05], [0.75, -0.05], [1.0, 0.0]]},
        "Guardian_Ult": {"segments": [seg("Sword_Attack", 0.0, 0.3, 0.55), seg("Sword_Attack", 0.3, 0.5, 0.35), hold("Sword_Attack", 0.5, 0.45),
                                      seg("Sword_Attack", 0.5, 1.53, 0.45)],
                         "aim": {"upperarm01.L": [[0.0, SH_F, 1.0]], "lowerarm01.L": [[0.0, SH_F, 1.0]]},
                         "root_lift": [[0.0, 0.0], [0.55, 0.0], [0.7, 0.5], [0.9, 0.0]], "blend": 0.05},
    }
    acts = {
        "normal": act("A", 0.5, 0.5, [hit(0.26, 1.4, fx={"kind": "blast", "color": "#d6dde6", "radius": 0.9, "life": 0.18, "at": "front", "dist": 1.8})],
                      step(0.0, "Guardian_A"), from_cd=True, aim=False, stop=False, cleave=False, radius_scale=1.2, name="棍棒",
                      note="とげ鉄球の棍棒を振り下ろす"),
        "sub": act("Y", 0.8, 5.0, [hit(0.38, 3.0, fx={"kind": "blast", "color": "#7fb4ff", "radius": 1.4, "life": 0.25, "at": "front", "dist": 1.5})],
                   step(0.0, "Guardian_Y"), i_frames=True, radius_scale=1.3, name="シールドチャージ",
                   path_=path((0.0, 0.0, 0.0), (0.4, 3.5, 0.0), (0.8, 3.6, 0.0)), note="盾を前に、体当たり。走っている間は無敵"),
        "main": act("X", 1.0, 20.0, [], step(0.0, "Guardian_X"), stop=False, aim=False,
                    effects=[{"t": 0.5, "type": "dome", "sec": 6.0, "radius": 5.0, "attack_mult": 0.5, "taken_mult": 0.5, "color": "#7fb4ff"}],
                    name="全体防御強化", note="6秒、ドームを張る。敵を含めた全員の攻撃力が50%低下し、受けるダメージが50%軽減（既存の指定のまま）"),
        "ultimate": act("必殺", 1.8, 0.0, [hit(0.9, 32.0, shape="self", radius=6.0, fx={"kind": "blast", "color": "#c8a46a", "radius": 6.0, "life": 0.5, "at": "self"})],
                        step(0.0, "Guardian_Ult"), i_frames=True, stop=False, name="アースクエイク",
                        path_=path((0.0, 0.0, 0.0), (0.55, 0.0, 0.0), (0.72, 0.4, 1.5), (0.9, 0.6, 0.0), (1.8, 0.6, 0.0)),
                        fx=[{"t": 0.9, "kind": "ring", "color": "#ffd27a", "radius": 8.0, "life": 0.6, "at": "self"}],
                        note="跳び上がって、棍棒で地面をたたく（まわり6m）"),
    }
    return acts, anims


# ------------------------------------------------------------------ おもちゃの兵隊
def summoner():
    FWD = [0.0, 0.25, 1.0]
    UP = [0.1, 1.0, 0.2]
    REST = [-0.2, -1.0, 0.1]
    anims = {
        "Toy_A": {"segments": [hold("Idle", 0.2, 0.4)],
                  "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.1, [0.0, 0.8, -0.4], 1.0], [0.2, FWD, 1.0], [0.4, REST, 0.0]],
                          "lowerarm01.R": [[0.0, REST, 0.0], [0.1, [0.0, 1.0, 0.0], 1.0], [0.2, FWD, 1.0], [0.4, REST, 0.0]]}},
        "Toy_Y": {"segments": [hold("Idle", 0.2, 0.8)],
                  "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.2, FWD, 1.0], [0.6, FWD, 1.0], [0.8, REST, 0.0]],
                          "lowerarm01.R": [[0.0, REST, 0.0], [0.2, FWD, 1.0], [0.6, FWD, 1.0], [0.8, REST, 0.0]]}},
        "Toy_X": {"segments": [hold("Idle", 0.2, 1.0)],
                  "aim": {"upperarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [0.45, UP, 1.0], [0.6, FWD, 1.0], [0.85, FWD, 1.0], [1.0, REST, 0.0]],
                          "lowerarm01.R": [[0.0, REST, 0.0], [0.25, UP, 1.0], [0.45, UP, 1.0], [0.6, FWD, 1.0], [0.85, FWD, 1.0], [1.0, REST, 0.0]]},
                  "root_lift": [[0.0, 0.0], [0.2, 0.08], [0.35, 0.0]]},
        "Toy_Ult": {"segments": [hold("Idle", 0.2, 1.6)],
                    "aim": {"upperarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.0, UP, 1.0], [1.2, FWD, 1.0], [1.45, FWD, 1.0], [1.6, REST, 0.0]],
                            "lowerarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.0, UP, 1.0], [1.2, FWD, 1.0], [1.45, FWD, 1.0], [1.6, REST, 0.0]]},
                    "root_lift": [[0.0, 0.0], [0.3, 0.1], [0.45, 0.0], [0.6, 0.1], [0.75, 0.0]]},
    }
    toss = {"shape": "blast", "at_boss": True, "max_dist": 6.0, "dist": 4.0, "radius": 1.0}
    acts = {
        "normal": act("A", 0.4, 0.4, [hit(0.34, 1.3, fx={"kind": "blast", "color": "#ffd0e0", "radius": 1.0, "life": 0.2}, **toss)], step(0.0, "Toy_A"),
                      fx=[{"t": 0.1, "kind": "orb", "color": "#7a5232", "radius": 0.14, "arc": 1.2, "life": 0.24, "height": 1.5, "at": "hit", "hit": toss}],
                      from_cd=True, stop=False, name="ぬいぐるみ投げ", note="小さなぬいぐるみを投げる（6m まで）"),
        "sub": act("Y", 0.8, 12.0, [], step(0.0, "Toy_Y"), stop=False,
                   effects=[{"t": 0.35, "type": "summon", "unit": "plush", "count": 2, "sec": 8.0, "interval": 0.8, "multiplier": 0.6, "speed": 5.5,
                             "reach": 1.0, "max_active": 7}],
                   fx=[{"t": 0.35, "kind": "ring", "color": "#f2b6c6", "radius": 2.0, "life": 0.4, "at": "self"}],
                   name="ぬいぐるみの突撃", note="ぬいぐるみを2体呼ぶ（8秒。0.8秒ごとに攻撃）"),
        "main": act("X", 1.0, 18.0, [], step(0.0, "Toy_X"), stop=False,
                    effects=[{"t": 0.45, "type": "summon", "unit": "plush", "count": 5, "sec": 10.0, "interval": 1.0, "multiplier": 0.6, "speed": 5.0,
                              "reach": 1.0, "max_active": 7}],
                    fx=[{"t": 0.45, "kind": "ring", "color": "#f2b6c6", "radius": 3.5, "life": 0.5, "at": "self"}],
                    name="ぬいぐるみ部隊", note="ぬいぐるみを5体呼ぶ（10秒。1秒ごとに攻撃）。本体の攻撃力には足さない。同時に7体まで"),
        "ultimate": act("必殺", 1.6, 0.0, [], step(0.0, "Toy_Ult"), i_frames=True, stop=False, name="ぬいぐるみ大行進",
                        effects=[{"t": 1.1, "type": "summon", "unit": "plush", "count": 12, "sec": 6.0, "interval": 0.5, "multiplier": 0.38, "speed": 7.0,
                                  "reach": 1.2, "max_active": 12, "spread": 2.0}],
                        fx=[{"t": 1.1, "kind": "ring", "color": "#ffd0e0", "radius": 5.0, "life": 0.6, "at": "self"}],
                        note="ぬいぐるみ12体の大行進（6秒、0.5秒ごとに攻撃）"),
    }
    return acts, anims


# ------------------------------------------------------------------ エンジェル
def healer():
    FWD = [0.0, 0.2, 1.0]
    UP = [0.15, 1.0, 0.25]
    UPF = [0.1, 0.7, 0.75]
    REST = [0.2, -1.0, 0.1]
    bow = {"upperarm01.L": [[0.0, REST, 0.0], [0.1, FWD, 1.0], [0.32, FWD, 1.0], [0.4, REST, 0.0]],
           "lowerarm01.L": [[0.0, REST, 0.0], [0.1, FWD, 1.0], [0.32, FWD, 1.0], [0.4, REST, 0.0]],
           "upperarm01.R": [[0.0, [-0.2, -1.0, 0.1], 0.0], [0.1, [0.0, 0.2, 1.0], 1.0], [0.19, [-0.3, 0.2, -0.2], 1.0], [0.32, [-0.3, 0.2, -0.2], 1.0], [0.4, [-0.2, -1.0, 0.1], 0.0]],
           "lowerarm01.R": [[0.0, [-0.2, -1.0, 0.1], 0.0], [0.1, [0.0, 0.2, 1.0], 1.0], [0.19, [0.8, 0.1, -0.4], 1.0], [0.32, [0.8, 0.1, -0.4], 1.0], [0.4, [-0.2, -1.0, 0.1], 0.0]]}
    anims = {
        "Angel_A": {"segments": [hold("Idle", 0.2, 0.4)], "aim": bow},
        "Angel_Y": {"segments": [hold("Idle", 0.2, 1.0)],
                    "aim": {"upperarm01*": [[0.0, REST, 0.0], [0.25, UPF, 1.0], [0.75, UPF, 1.0], [1.0, REST, 0.0]],
                            "lowerarm01*": [[0.0, REST, 0.0], [0.25, UPF, 1.0], [0.75, UPF, 1.0], [1.0, REST, 0.0]]},
                    "root_lift": [[0.0, 0.0], [0.3, 0.12], [0.75, 0.12], [1.0, 0.0]]},
        "Angel_X": {"segments": [hold("Idle", 0.2, 1.4)],
                    "aim": {"upperarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.1, UP, 1.0], [1.4, REST, 0.0]],
                            "lowerarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.1, UP, 1.0], [1.4, REST, 0.0]]},
                    "offsets": {"spine03": [[0.0, [0, 0, 0]], [0.3, [-15, 0, 0]], [1.1, [-15, 0, 0]], [1.4, [0, 0, 0]]]},
                    "root_lift": [[0.0, 0.0], [0.35, 0.25], [1.1, 0.25], [1.4, 0.0]]},
        "Angel_Ult": {"segments": [hold("Idle", 0.2, 2.0)],
                      "aim": {"upperarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.3, UP, 1.0], [1.5, FWD, 1.0], [1.8, FWD, 1.0], [2.0, REST, 0.0]],
                              "lowerarm01*": [[0.0, REST, 0.0], [0.3, UP, 1.0], [1.3, UP, 1.0], [1.5, FWD, 1.0], [1.8, FWD, 1.0], [2.0, REST, 0.0]]},
                      "root_lift": [[0.0, 0.0], [0.4, 0.4], [1.5, 0.4], [1.8, 0.0]]},
    }
    arrow = {"shape": "beam", "length": 11.0, "half_width": 0.35}
    acts = {
        "normal": act("A", 0.4, 0.4, [hit(0.2, 1.4, **arrow)], step(0.0, "Angel_A"),
                      fx=[{"t": 0.19, "kind": "beam", "color": "#ff7b8a", "width": 0.05, "life": 0.12, "length": 11.0, "height": 1.3}],
                      from_cd=True, stop=False, name="ハートの矢", note="金の弓で、ハートの矢を射る（11m の帯）"),
        "sub": act("Y", 1.0, 8.0, [], step(0.0, "Angel_Y"), stop=False, aim=False,
                   effects=[{"t": 0.5, "type": "heal", "amount": 40.0, "radius": 7.0, "color": "#7dffa8"}],
                   name="ヒール", note="まわり7m の味方を40回復（乱数・クリティカルなし）"),
        "main": act("X", 1.4, 25.0, [], step(0.0, "Angel_X"), stop=False, aim=False,
                    effects=[{"t": 0.8, "type": "revive", "radius": 10.0, "hp_ratio": 0.5}, {"t": 0.8, "type": "heal", "amount": 25.0, "radius": 10.0}],
                    name="天使の祈り", note="まわり10m の倒れた味方を、体力50%で起こす。立っている味方は25回復"),
        "ultimate": act("必殺", 2.0, 0.0, [hit(1.55, 40.0, shape="blast", at_boss=True, max_dist=20.0, radius=3.5,
                                               fx={"kind": "pillar", "color": "#fff2a8", "radius": 3.0, "tall": 12.0, "life": 0.8})],
                        step(0.0, "Angel_Ult"), i_frames=True, stop=False, aim=True, name="エンジェルレイ",
                        effects=[{"t": 1.0, "type": "heal", "amount": 999.0, "radius": 99.0, "color": "#fff2a8"}],
                        note="味方全員を全回復して、ボスに光の柱を落とす"),
    }
    return acts, anims


CHARS = {"brawler": brawler, "sprinter": sprinter, "gunner": gunner, "bomber": bomber, "mage": mage, "guardian": guardian,
         "summoner": summoner, "healer": healer}
NAMES = {"brawler": "ファイター", "sprinter": "スピードファイター", "gunner": "ガンナー", "bomber": "ボンバー", "mage": "魔法使い",
         "guardian": "アーマー", "summoner": "おもちゃの兵隊", "healer": "エンジェル"}


def anim_keys(anims):
    return {k: k for k in anims}


def all_anims():
    out = {}
    for cid, f in CHARS.items():
        acts, anims = f()
        out[cid] = anims
    return out


def total(a, ap):
    return sum(h["multiplier"] for h in a.get("hits", [])) * ap


def main():
    chars = json.loads((ROOT / "data/characters.json").read_text(encoding="utf-8"))
    stats = {c["id"]: c["stats"] for c in chars["characters"]}
    data = {"_memo": "版78：キャラごとの攻撃（tools/make_char_actions.py が作る。手で書きかえない）。actions.json の同じ名前の動きを、キャラの分で置きかえる。"
                     "ダメージ = キャラの攻撃力 × 倍率。剣士は actions.json のまま",
            "characters": {}}
    rows = []
    for cid, f in CHARS.items():
        acts, anims = f()
        data["characters"][cid] = acts
        ap = float(stats[cid]["attack_power"])
        for key, lab in (("normal", "A"), ("sub", "Y"), ("main", "X"), ("ultimate", "必殺")):
            a = acts[key]
            hs = a.get("hits", [])
            effs = ", ".join(e["type"] for e in a.get("effects", []))
            one = hs[0]["multiplier"] * ap if hs else 0.0
            cd = float(stats[cid]["attack_cooldown_sec"]) if key == "normal" else a["cooldown_sec"]
            shape = hs[0].get("shape", "melee") if hs else "-"
            rows.append((NAMES[cid], lab, a["name"], len(hs), one, total(a, ap), cd, a["duration_sec"], shape, effs))
    (ROOT / "data/char_actions.json").write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    md = ["# キャラごとの攻撃（版78）", "",
          "tools/make_char_actions.py が作る表。ダメージ = 攻撃力 × 倍率（四捨五入しない値）。ゲージ制の必殺技は待ち時間 0。",
          "剣士（基準・変えない）：A 単純斬り 22.5（0.35秒）／Y かわし斬り 58.5（4秒）／X 五段斬り 18×5＝90（6秒）／必殺 切り捨て御免 346.5", "",
          "| キャラ | ボタン | 技 | 当たる回数 | 1回 | 合計 | 待ち時間（秒） | 長さ（秒） | 当たりの形 | 効果 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append("| %s | %s | %s | %d | %.2f | %.2f | %.2f | %.2f | %s | %s |" % r)
    (ROOT / "docs/char-actions-v78.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print("chars", list(data["characters"]))


if __name__ == "__main__":
    main()
