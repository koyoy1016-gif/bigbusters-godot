#!/usr/bin/env python3
"""版88：PLATEAU（3D都市モデル・CityGML）から、戦いのマップの 3D（.glb）を作る。

使い方:
  python3 tools/plateau_to_glb.py --src <CityGML のフォルダ> [--map shibuya] [--cache <作業用フォルダ>] [--preview <上から見た図.png>]

  <CityGML のフォルダ> には、PLATEAU の udx から取り出した次のファイルを入れる（名前は PLATEAU のまま）:
    ????????_bldg_6697_op.gml（建物）・????????_tran_6697_op.gml（道路）・??????_dem_6697_op.gml（地形）
  数値（まん中の緯度経度・向き・半径・色など）は data/maps.json の maps.<map>.build。
  できるもの: maps.<map>.glb（例 assets/maps/shibuya/shibuya.glb）。元の CityGML はリポジトリに入れない。

やること:
  1. 読む：建物（LOD2 の壁・屋根・屋上の設備／なければ LOD1 の箱）、道路（LOD3 の車道・交差部・歩道・島）、地形（TIN の三角形）。
     大きいファイルでも、少しずつ読む。読んだ結果は --cache に保存して、2回目からは速く。
  2. 座標：緯度・経度・高さ（EPSG:6697）→ ゲームの座標（1=1m、上が +Y）。交差点のまん中を (0,0,0)。
     heading_deg だけ回して、画面の奥（-Z）を好きな方角に向ける。地形のまん中の高さを 0 にする。
  3. 戦いの場所のまわり（flat_half_m）は平らに（高さ 0）。外へ向かって、本物の高さへなめらかにもどす。
  4. 遠い建物は箱（LOD1）。半径より外は消す。色は頂点の色だけ（写真の模様は使わない：看板・広告を出さないため）。
  5. 交差点の横断歩道（しま）を、道路の形から作る（交差点に入る道の入り口ごと）。
  6. まとめて .glb に書く（Ground・Crosswalk・BldgNear・BldgFar の4つ）。上から見た図も作れる。
"""
import argparse
import glob
import hashlib
import json
import math
import os
import pickle
import struct
import sys
import time
from pathlib import Path

import numpy as np
from lxml import etree

try:
    import mapbox_earcut as earcut
except ImportError:
    sys.exit("mapbox_earcut がいる：pip install mapbox_earcut")

ROOT = Path(__file__).resolve().parent.parent
GML = "{http://www.opengis.net/gml}"
BLDG = "{http://www.opengis.net/citygml/building/2.0}"
TRAN = "{http://www.opengis.net/citygml/transportation/2.0}"
DEM = "{http://www.opengis.net/citygml/relief/2.0}"
SURF = {"WallSurface": "wall", "RoofSurface": "roof", "GroundSurface": "ground", "OuterCeilingSurface": "wall",
        "OuterFloorSurface": "roof", "ClosureSurface": "closure"}
READ_RADIUS = 650.0  # 読む時の広さ（m。まん中・向きを少し変えても読みなおさなくてよいように、広めに）


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- 座標

class Frame:
    """緯度・経度・高さ → ゲームの座標（x=東から回した向き、y=上、z）。"""

    def __init__(self, lat0, lon0, heading_deg, h0=0.0):
        self.lat0, self.lon0, self.h0 = lat0, lon0, h0
        phi = math.radians(lat0)
        self.mlat = 111132.92 - 559.82 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
        self.mlon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi) + 0.118 * math.cos(5 * phi)
        th = math.radians(heading_deg)
        self.c, self.s = math.cos(th), math.sin(th)

    def enu(self, a):
        """(n,3) 緯度 経度 高さ → 東(m)・高さ(m, 地面0)・南(m)（回す前）"""
        return np.stack([(a[:, 1] - self.lon0) * self.mlon, a[:, 2] - self.h0, -(a[:, 0] - self.lat0) * self.mlat], 1)

    def game(self, a):
        p = self.enu(a)
        x = p[:, 0] * self.c + p[:, 2] * self.s
        z = -p[:, 0] * self.s + p[:, 2] * self.c
        return np.stack([x, p[:, 1], z], 1)


def _ring(el):
    pl = el.find(".//" + GML + "posList")
    if pl is None or not pl.text:
        return None
    a = np.array(pl.text.split(), dtype=np.float64)
    if a.size < 9 or a.size % 3:
        return None
    return a.reshape(-1, 3)


def _polys(el):
    """el の中の gml:Polygon を [外の輪, 穴の輪…]（緯度 経度 高さ）のリストに"""
    out = []
    for poly in el.iter(GML + "Polygon"):
        ext = poly.find(GML + "exterior")
        if ext is None:
            continue
        r = _ring(ext)
        if r is None:
            continue
        rings = [r]
        for it in poly.findall(GML + "interior"):
            r2 = _ring(it)
            if r2 is not None:
                rings.append(r2)
        out.append(rings)
    return out


def _near(rings_list, lat0, lon0, radius):
    pts = np.concatenate([rr[0] for rr in rings_list])
    f = Frame(lat0, lon0, 0.0)
    e = f.enu(pts)
    return float(np.hypot(e[:, 0], e[:, 2]).min()) < radius


def _iter_objects(path, tags):
    for ev, el in etree.iterparse(path, events=("end",), tag=tags, huge_tree=True):
        yield el
        el.clear()
        while el.getprevious() is not None:
            del el.getparent()[0]


# ---------------------------------------------------------------- 読む

def read_buildings(path, lat0, lon0):
    out = []
    for el in _iter_objects(path, (BLDG + "Building",)):
        b = {"id": el.get(GML + "id") or "", "usage": el.findtext(BLDG + "usage") or "",
             "h": float(el.findtext(BLDG + "measuredHeight") or 0.0), "lod2": [], "lod1": [], "inst": []}
        for tag, kind in SURF.items():
            for s in el.iter(BLDG + tag):
                for ms in s.iter(BLDG + "lod2MultiSurface"):
                    b["lod2"] += [(kind, rr) for rr in _polys(ms)]
        for bi in el.iter(BLDG + "BuildingInstallation"):
            for g in bi.iter(BLDG + "lod2Geometry"):
                b["inst"] += _polys(g)
        for s in el.iter(BLDG + "lod1Solid"):
            b["lod1"] += _polys(s)
        allp = b["lod1"] or [rr for _, rr in b["lod2"]]
        if allp and _near(allp, lat0, lon0, READ_RADIUS):
            out.append(b)
    return out


def read_roads(path, lat0, lon0):
    out = []
    for el in _iter_objects(path, (TRAN + "Road", TRAN + "Track", TRAN + "Square")):
        r = {"id": el.get(GML + "id") or "", "areas": [], "lod1": []}
        for ms in el.iter(TRAN + "lod1MultiSurface"):
            r["lod1"] += _polys(ms)
        for tag in ("TrafficArea", "AuxiliaryTrafficArea"):
            for ta in el.iter(TRAN + tag):
                fn = ta.findtext(TRAN + "function") or ""
                for lod in ("lod3MultiSurface", "lod2MultiSurface"):
                    for ms in ta.findall(TRAN + lod):
                        r["areas"] += [(tag, fn, lod[:4], rr) for rr in _polys(ms)]
        allp = r["lod1"] or [rr for _, _, _, rr in r["areas"]]
        if allp and _near(allp, lat0, lon0, READ_RADIUS):
            out.append(r)
    return out


def read_dem(path, lat0, lon0, meshes):
    tris = []
    f = Frame(lat0, lon0, 0.0)
    for el in _iter_objects(path, (DEM + "ReliefFeature",)):
        if meshes and (el.findtext(GML + "name") or "") not in meshes:
            continue
        for pl in el.iter(GML + "posList"):
            a = np.array(pl.text.split(), dtype=np.float64).reshape(-1, 3)[:3]
            e = f.enu(a)
            if np.all(np.hypot(e[:, 0], e[:, 2]) < READ_RADIUS):
                tris.append(a)
    return np.array(tris)


def load_all(src, cache, b):
    lat0, lon0 = b["center_lat"], b["center_lon"]
    key = hashlib.sha1(("%s|%.6f|%.6f|%d" % (os.path.abspath(src), lat0, lon0, READ_RADIUS)).encode()).hexdigest()[:10]
    cp = Path(cache) / ("plateau_%s.pkl" % key) if cache else None
    if cp is not None and cp.exists():
        log("読みこみ済みを使う:", cp)
        return pickle.load(open(cp, "rb"))
    t = time.time()
    data = {"bldg": [], "tran": [], "dem": np.zeros((0, 3, 3))}
    for f in sorted(glob.glob(os.path.join(src, "*_bldg_6697*.gml"))):
        got = read_buildings(f, lat0, lon0)
        data["bldg"] += got
        log("建物", os.path.basename(f), len(got), "%.0f秒" % (time.time() - t))
    for f in sorted(glob.glob(os.path.join(src, "*_tran_6697*.gml"))):
        got = read_roads(f, lat0, lon0)
        data["tran"] += got
        log("道路", os.path.basename(f), len(got), "%.0f秒" % (time.time() - t))
    dems = []
    for f in sorted(glob.glob(os.path.join(src, "*_dem_6697*.gml"))):
        got = read_dem(f, lat0, lon0, set(b.get("dem_meshes", [])))
        if len(got):
            dems.append(got)
        log("地形", os.path.basename(f), len(got), "%.0f秒" % (time.time() - t))
    if dems:
        data["dem"] = np.concatenate(dems)
    if cp is not None:
        cp.parent.mkdir(parents=True, exist_ok=True)
        pickle.dump(data, open(cp, "wb"))
    return data


# ---------------------------------------------------------------- 形を作る

def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def newell(p):
    n = np.zeros(3)
    q = np.roll(p, -1, axis=0)
    n[0] = np.sum((p[:, 1] - q[:, 1]) * (p[:, 2] + q[:, 2]))
    n[1] = np.sum((p[:, 2] - q[:, 2]) * (p[:, 0] + q[:, 0]))
    n[2] = np.sum((p[:, 0] - q[:, 0]) * (p[:, 1] + q[:, 1]))
    L = np.linalg.norm(n)
    return n / L if L > 1e-12 else None


def triangulate(rings):
    """rings：ゲームの座標の輪（最初が外、あとは穴。最後の点は最初と同じ）→ (点, 三角形の番号, 法線)"""
    rs = [r[:-1] if len(r) > 1 and np.allclose(r[0], r[-1]) else r for r in rings]
    rs = [r for r in rs if len(r) >= 3]
    if not rs:
        return None
    n = newell(rs[0])
    if n is None:
        return None
    ax = int(np.argmax(np.abs(n)))
    keep = [i for i in range(3) if i != ax]
    pts = np.concatenate(rs)
    p2 = pts[:, keep].astype(np.float64)
    ends = np.cumsum([len(r) for r in rs]).astype(np.uint32)
    try:
        idx = earcut.triangulate_float64(p2, ends)
    except Exception:
        return None
    if len(idx) == 0:
        return None
    tri = idx.reshape(-1, 3)
    # 三角形の向きを、輪の向き（法線）に合わせる
    a, b, c = pts[tri[:, 0]], pts[tri[:, 1]], pts[tri[:, 2]]
    tn = np.cross(b - a, c - a)
    flip = (tn @ n) < 0
    tri[flip] = tri[flip][:, [0, 2, 1]]
    return pts, tri, n


class Mesh:
    """uv=True の形は、TEXCOORD_0 も書く（建物：u=建物の足もとの高さ・v=建物ごとの乱数。看板：絵の位置）"""

    def __init__(self, name, uv=False):
        self.name = name
        self.pos, self.nor, self.col, self.idx, self.uv = [], [], [], [], []
        self.has_uv = uv
        self.nv = 0
        self.ntri = 0

    def add(self, pts, tri, normal, rgba, uv=None):
        k = len(pts)
        self.pos.append(np.asarray(pts, np.float32))
        self.nor.append(np.tile(np.asarray(normal, np.float32), (k, 1)))
        self.col.append(np.tile(np.asarray(rgba, np.float32), (k, 1)))
        if self.has_uv:
            u = np.zeros((k, 2), np.float32) if uv is None else np.asarray(uv, np.float32)
            self.uv.append(np.tile(u, (k, 1)) if u.shape == (2,) else u)
        self.idx.append(np.asarray(tri).astype(np.uint32) + self.nv)
        self.nv += k
        self.ntri += len(tri)

    def arrays(self):
        if not self.pos:
            return None
        a = (np.concatenate(self.pos), np.concatenate(self.nor), np.concatenate(self.col), np.concatenate(self.idx).reshape(-1))
        return a + (np.concatenate(self.uv),) if self.has_uv else a


def flatten(p, b, drop=0.0):
    """戦いの場所のまわりを平らに（Chebyshev の距離で、flat_half_m の中は 0、外へなめらかに本物の高さ）"""
    half, blend = float(b["flat_half_m"]), float(b["flat_blend_m"])
    d = np.maximum(np.abs(p[:, 0]), np.abs(p[:, 2]))
    t = np.clip((d - half) / max(blend, 0.01), 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    q = p.copy()
    q[:, 1] = (p[:, 1] - drop) * t + (-drop * 0.3) * (1 - t)
    return q


def _rand(seed, k):
    h = int(hashlib.md5((seed + str(k)).encode()).hexdigest()[:8], 16)
    return h / 0xFFFFFFFF


# 建物の材質（頂点の色の a に入れる。シェーダー city_buildings.gdshader が見分ける）
MAT_A = {"roof": 0.0, "metal": 0.25, "punched": 0.5, "glass": 0.75, "ribbon": 1.0}


def place_building(bd, fr, b):
    """建物の足もと → (足もとの点, まん中 x, z, まん中からの距離, 上下の合わせ dy, 足もとの高さ（合わせたあと）)"""
    src = bd["lod1"] or [rr for _, rr in bd["lod2"]]
    foot = fr.game(np.concatenate([rr[0] for rr in src]))
    cx, cz = float(foot[:, 0].mean()), float(foot[:, 2].mean())
    # 建物ごとの高さの合わせ（平らにした所の近くでは、建物ごと上下させる。形はくずさない）
    base_real = float(foot[:, 1].min())
    base_flat = float(flatten(np.array([[cx, base_real, cz]]), b)[0, 1])
    return foot, cx, cz, math.hypot(cx, cz), base_flat - base_real, base_flat


def in_arena(foot, b):
    arena = float(b.get("check_half_m", 15.0)) + 2.0  # 戦いの場所（と、まわり2m）にかかる建物は出さない
    return bool(np.any((np.abs(foot[:, 0]) < arena) & (np.abs(foot[:, 2]) < arena)))


def building_material(bd, b):
    """建物ごとの材質と色（高さで、えらび方の割合を変える。写真の渋谷：高い建物はガラス、低い建物はタイル・パネルが多い）"""
    mc = b["materials"]
    h = float(bd["h"])
    group = "tall" if h >= float(mc["tall_m"]) else ("mid" if h >= float(mc["mid_m"]) else "low")
    r = _rand(bd["id"], 5)
    kind = "punched"
    acc = 0.0
    for k, w in mc["mix"][group].items():
        acc += float(w)
        if r < acc:
            kind = k
            break
    pal = [hex_rgb(c) for c in mc["colors"][kind]]
    wc = pal[int(_rand(bd["id"], 1) * len(pal)) % len(pal)] * (0.94 + 0.12 * _rand(bd["id"], 2))
    return kind, np.clip(wc, 0.0, 1.0)


def build_buildings(data, fr, b, stats):
    cols = b["colors"]
    roof = hex_rgb(cols["roof"])
    inst = hex_rgb(cols["install"])
    near, far = Mesh("BldgNear", uv=True), Mesh("BldgFar", uv=True)
    R, R2, RI = float(b["radius_m"]), float(b["lod2_radius_m"]), float(b["install_radius_m"])
    for bd in data["bldg"]:
        foot, cx, cz, dist, dy, base_y = place_building(bd, fr, b)
        if dist > R:
            continue
        if in_arena(foot, b):
            stats["inside_arena"] += 1
            continue
        kind_w, wc = building_material(bd, b)
        stats["mat_" + kind_w] = stats.get("mat_" + kind_w, 0) + 1
        bu = (base_y, _rand(bd["id"], 6))
        rc = roof * (0.85 + 0.25 * _rand(bd["id"], 3))
        use_lod2 = dist < R2 and bd["lod2"]
        target = near if dist < R2 else far
        items = []
        if use_lod2:
            items = [(k, rr) for k, rr in bd["lod2"] if k in ("wall", "roof")]
            if dist < RI:
                items += [("inst", rr) for rr in bd["inst"]]
        else:
            items = [("auto", rr) for rr in bd["lod1"]]
        for kind, rr in items:
            g = [fr.game(r) + [0.0, dy, 0.0] for r in rr]
            res = triangulate(g)
            if res is None:
                stats["bad_poly"] += 1
                continue
            pts, tri, n = res
            if kind == "auto":
                kind = "roof" if n[1] > 0.7 else ("ground" if n[1] < -0.7 else "wall")
                if kind == "ground":
                    continue
            # 面の向きは、データの輪の向き（外向き）をそのまま使う（調べたら、屋根の 99.9% が上向きで、そろっていた）。
            # 屋根で下を向いているものだけ、上向きに直す
            if kind == "roof" and n[1] < 0:
                n = -n
                tri = tri[:, [0, 2, 1]]
            if kind == "wall":
                rgba = (*wc, MAT_A[kind_w])  # 窓・ガラス・パネルを描く面
            elif kind == "roof":
                rgba = (*rc, MAT_A["roof"])
            else:
                rgba = (*(inst * (0.9 + 0.2 * _rand(bd["id"], 4))), MAT_A["metal"])
            target.add(pts, tri, n, rgba, bu)
        stats["bldg_near" if dist < R2 else "bldg_far"] += 1
    return near, far


ROAD_COL = {"1000": "road", "1020": "road_cross", "2000": "walk", "3000": "island"}
UP = (0.0, 1.0, 0.0)


def build_ground(data, fr, b, stats):
    """道路（LOD3：高さあり）と、地形（道路・建物でおおわれていない所だけ。駅前の広場など）"""
    import shapely
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    cols = b["colors"]
    road, terr = Mesh("Ground"), Mesh("Terrain")
    R = float(b["radius_m"])
    rp = []  # 道路の点（高さの補間用）
    for r in data["tran"]:
        for tag, fn, lod, rr in r["areas"]:
            if lod != "lod3":
                continue
            key = ROAD_COL.get(fn, "island" if tag == "AuxiliaryTrafficArea" else "road")
            gr = [fr.game(x) for x in rr]
            dmin = np.hypot(gr[0][:, 0], gr[0][:, 2]).min()
            if dmin > R:
                continue
            res = triangulate(gr)
            if res is None:
                stats["bad_poly"] += 1
                continue
            pts, tri, n = res
            if n[1] < 0:
                tri = tri[:, [0, 2, 1]]
            # 交差点の近くの大きな三角形は、細かく分けてから平らにする（大きいままだと、平らにした所の中が少しかたむくため）
            zone = float(b["flat_half_m"]) + float(b["flat_blend_m"])
            if dmin < zone * 1.5 + 60.0 and float(b.get("subdivide_m", 0.0)) > 0.0:
                pts, tri = subdivide(pts, tri, float(b["subdivide_m"]), zone)
            pts = flatten(pts, b)
            lift = 0.03 if key in ("walk", "island") else 0.0  # 歩道は少しだけ上（同じ高さで重ならないように）
            road.add(pts + [0.0, lift, 0.0], tri, UP, (*hex_rgb(cols[key]), 1.0))
            rp.append(pts)
            stats["road_tris"] += len(tri)
    # おおわれている所（道路の LOD2・建物の足もと）
    cover = []
    for r in data["tran"]:
        for tag, fn, lod, rr in r["areas"]:
            if lod == "lod2":
                e = fr.game(rr[0])[:, [0, 2]]
                if len(e) >= 4:
                    cover.append(Polygon(e).buffer(0))
    for bd in data["bldg"]:
        for rr in bd["lod1"]:
            e = fr.game(rr[0])
            if len(e) >= 4 and np.ptp(e[:, 1]) < 0.05:
                cover.append(Polygon(e[:, [0, 2]]).buffer(0))
                break
    covered = unary_union([c for c in cover if not c.is_empty]).buffer(0.4)
    shapely.prepare(covered)
    dem = data["dem"]
    if len(dem):
        pc = hex_rgb(cols["plaza"])
        drop = float(b["terrain_drop_m"])
        P = np.array([flatten(fr.game(t3), b, drop=drop) for t3 in dem])
        cxz = P[:, :, [0, 2]].mean(1)
        inside_r = np.hypot(P[:, :, 0], P[:, :, 2]).min(1) <= R
        hid = shapely.contains_xy(covered, cxz[:, 0], cxz[:, 1])
        for k in range(3):
            hid &= shapely.contains_xy(covered, P[:, k, 0], P[:, k, 2])
        keep = inside_r & ~hid
        for t3 in P[keep]:
            n = np.cross(t3[1] - t3[0], t3[2] - t3[0])
            t = np.array([[0, 1, 2]]) if n[1] >= 0 else np.array([[0, 2, 1]])
            terr.add(t3, t, UP, (*pc, 1.0))
        stats["terrain_tris"] = int(keep.sum())
        stats["terrain_hidden"] = int((inside_r & hid).sum())
    pts = np.concatenate(rp) if rp else np.zeros((1, 3))
    return road, terr, pts


def subdivide(pts, tri, max_edge, zone=1e9):
    """三角形の辺が max_edge より長いものを、4つに分けることをくり返す（点は重なってもよい。あとで weld でまとめる）。
    zone：まん中から ±zone m の四角に、かかっている三角形だけ分ける（平らにする所と、本物の高さへもどす所）"""
    P = [p for p in pts]
    out = [tuple(t) for t in tri]
    for _ in range(8):
        nxt = []
        split = False
        for a, b2, c in out:
            pa, pb, pc = P[a], P[b2], P[c]
            xs = (pa[0], pb[0], pc[0])
            zs = (pa[2], pb[2], pc[2])
            touch = min(xs) < zone and max(xs) > -zone and min(zs) < zone and max(zs) > -zone
            if not touch or max(np.linalg.norm(pa - pb), np.linalg.norm(pb - pc), np.linalg.norm(pc - pa)) <= max_edge:
                nxt.append((a, b2, c))
                continue
            split = True
            ab, bc, ca = len(P), len(P) + 1, len(P) + 2
            P += [(pa + pb) / 2, (pb + pc) / 2, (pc + pa) / 2]
            nxt += [(a, ab, ca), (ab, b2, bc), (ca, bc, c), (ab, bc, ca)]
        out = nxt
        if not split:
            break
    return np.array(P), np.array(out, dtype=np.int64)


def road_height(points):
    """道路の点から、(x, z) の高さを返す関数"""
    from scipy.interpolate import LinearNDInterpolator, NearestNDInterpolator
    u = np.unique(np.round(points, 2), axis=0)
    lin = LinearNDInterpolator(u[:, [0, 2]], u[:, 1])
    near = NearestNDInterpolator(u[:, [0, 2]], u[:, 1])

    def h(xz):
        v = lin(xz)
        bad = np.isnan(v)
        if bad.any():
            v[bad] = near(xz[bad])
        return v
    return h


def weld(arrs, decimals=3):
    """同じ位置・同じ色・同じ法線の点をまとめる（ファイルを小さく）"""
    pos, nor, col, idx = arrs
    key = np.concatenate([np.round(pos, decimals), np.round(nor, 2), np.round(col, 3)], 1)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return pos[first], nor[first], col[first], inv.reshape(-1)[idx].astype(np.uint32)


def up_tris(pts):
    """4つの点の四角を、上から見て表になる向きの三角形2つに"""
    n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
    return np.array([[0, 1, 2], [0, 2, 3]]) if n[1] > 0 else np.array([[0, 2, 1], [0, 3, 2]])


def down_tris(pts):
    """4つの点の四角を、下から見て表になる向きの三角形2つに"""
    n = np.cross(pts[1] - pts[0], pts[2] - pts[0])
    return np.array([[0, 1, 2], [0, 2, 3]]) if n[1] < 0 else np.array([[0, 2, 1], [0, 3, 2]])


# ---------------------------------------------------------------- 横断歩道

def build_crosswalks(data, fr, b, stats, height):
    """交差点（車道交差部 1020 のうち、まん中をふくむ形と、それにつながる形）の、道の入り口（車道 1000 とつながる所）にしまを作る。
    あわせて、むかい合う歩道の角どうしを結ぶ、ななめの横断歩道（スクランブル）も作る。
    PLATEAU に横断歩道のデータはないので、道路の形から作る（本物の位置と、少しちがうことがある）"""
    from shapely.geometry import Polygon, Point, LineString
    from shapely.ops import unary_union, linemerge
    cw = b["crosswalk"]
    col = hex_rgb(b["colors"]["crosswalk"])
    m = Mesh("Crosswalk")
    p1020, p1000 = [], []
    for r in data["tran"]:
        for tag, fn, lod, rr in r["areas"]:
            if lod != "lod2":
                continue
            e = fr.game(rr[0])[:, [0, 2]]
            if len(e) < 4 or np.hypot(e[:, 0], e[:, 1]).min() > 140:
                continue
            g = Polygon(e).buffer(0)
            if fn == "1020":
                p1020.append(g)
            elif fn == "1000":
                p1000.append(g)
    seed = [g for g in p1020 if g.contains(Point(0, 0))]
    if not seed:
        log("横断歩道：交差点の形が見つからない")
        return m, None
    cl = seed[0]
    rest = [g for g in p1020 if g is not seed[0]]
    grew = True
    while grew:
        grew = False
        for g in list(rest):
            if g.distance(cl) < 0.6 and g.centroid.distance(Point(0, 0)) < 70:
                cl = unary_union([cl, g]).buffer(0.3).buffer(-0.3)
                rest.remove(g)
                grew = True
    if cl.geom_type != "Polygon":
        cl = max(cl.geoms, key=lambda g: g.area)
    roads = unary_union(p1000).buffer(0.8)
    edge = cl.exterior
    mouths = linemerge(edge.intersection(roads)) if not edge.intersection(roads).is_empty else None
    walks = edge.difference(roads)
    stripe, gap, band, inset = float(cw["stripe_m"]), float(cw["gap_m"]), float(cw["band_m"]), float(cw["inset_m"])

    def bar(p0, along, across, w, l, lift=0.02):
        quad = np.array([p0, p0 + along * w, p0 + along * w + across * l, p0 + across * l])
        y = height(quad) + lift
        pts = np.stack([quad[:, 0], y, quad[:, 1]], 1)
        m.add(pts, up_tris(pts), UP, (*col, 1.0))

    made = []
    pieces = [] if mouths is None else (list(mouths.geoms) if hasattr(mouths, "geoms") else [mouths])
    for ln in pieces:
        if ln.length < float(cw["min_mouth_m"]):
            continue
        a, c = np.array(ln.coords[0]), np.array(ln.coords[-1])
        L = np.linalg.norm(c - a)
        if L < float(cw["min_mouth_m"]):
            continue
        u = (c - a) / L
        nrm = np.array([-u[1], u[0]])
        mid = (a + c) / 2
        inward = nrm if cl.contains(Point(*(mid + nrm * 1.5))) else -nrm
        s = 0.5
        while s + stripe <= L - 0.5:
            bar(a + u * s + inward * inset, u, inward, stripe, band)
            s += stripe + gap
        # 止まる線（車が交差点に入ってくる側の半分だけ。日本は左側を走るので、入ってくる向きの左がわ）
        left = np.array([inward[1], -inward[0]])
        sw, back = float(cw.get("stop_w_m", 0.45)), float(cw.get("stop_back_m", 2.0))
        if sw > 0.0:
            if u @ left > 0:
                s0, s1 = L / 2 + 0.3, L - 0.6
            else:
                s0, s1 = 0.6, L / 2 - 0.3
            if s1 - s0 > 1.5:
                bar(a + u * s0 - inward * back, u, inward, s1 - s0, sw)
                stats["stop_lines"] = stats.get("stop_lines", 0) + 1
        made.append({"a": a.tolist(), "c": c.tolist()})
        stats["crosswalks"] += 1
    # ななめ（むかい合う歩道の角どうし）
    corners = []
    wp = list(walks.geoms) if hasattr(walks, "geoms") else [walks]
    for w in wp:
        if w.length < 2.0:
            continue
        pt = w.interpolate(0.5, normalized=True)
        corners.append(np.array([pt.x, pt.y]))
    diag = []
    if len(corners) >= 4:
        best = []
        for i in range(len(corners)):
            for j in range(i + 1, len(corners)):
                A, B = corners[i], corners[j]
                ang = abs(math.degrees(math.atan2(A[1], A[0]) - math.atan2(B[1], B[0]))) % 360
                ang = min(ang, 360 - ang)
                d = LineString([A, B]).distance(Point(0, 0))
                if ang > 130 and d < 10.0:
                    best.append((d, i, j))
        best.sort()
        used = set()
        for d, i, j in best:
            if i in used or j in used:
                continue
            used |= {i, j}
            diag.append((corners[i], corners[j]))
            if len(diag) >= int(cw.get("diagonals", 2)):
                break
    dband = float(cw.get("diag_band_m", band))
    for A, B in diag:
        w = (B - A) / np.linalg.norm(B - A)
        side = np.array([-w[1], w[0]])
        L = np.linalg.norm(B - A)
        s = float(cw.get("diag_trim_m", 3.0))
        while s + stripe <= L - float(cw.get("diag_trim_m", 3.0)):
            bar(A + w * s - side * dband / 2, w, side, stripe, dband, 0.025)
            s += stripe + gap
        stats["diagonals"] += 1
    walk_lines = [np.array(w.coords).tolist() for w in wp if w.length >= 2.0]
    return m, {"outline": np.array(cl.exterior.coords).tolist(), "mouths": made, "corners": [c.tolist() for c in corners],
               "diagonals": [[A.tolist(), B.tolist()] for A, B in diag], "cross_center": [cl.centroid.x, cl.centroid.y],
               "walk_lines": walk_lines}


def build_lamps(info, b, stats, height):
    """版90：街灯（交差点の歩道の角に沿って）。柱（色だけ）と、光る頭（頂点の色 a=1）。
    下の地面の光の輪（LightPools）は、夜（覚醒）に明るくなる（シェーダー city_light_pool.gdshader）。数値は build.lamps"""
    from shapely.geometry import Polygon, Point, LineString
    lc = b["lamps"]
    lamps, pools = Mesh("Lamps"), Mesh("LightPools", uv=True)
    if not info:
        return lamps, pools
    cl = Polygon(info["outline"])
    pole_c = (*hex_rgb(lc["pole_color"]), 0.0)
    head_c = (1.0, 1.0, 1.0, 1.0)
    H, arm, every, outm = float(lc["pole_h_m"]), float(lc["arm_m"]), float(lc["every_m"]), float(lc["out_m"])
    pm = float(lc["pool_m"])
    placed = []
    for coords in info["walk_lines"]:
        ln = LineString(coords)
        n_l = max(1, int(round(ln.length / every)))
        for k in range(n_l):
            d = ln.length * (k + 0.5) / n_l
            pt = ln.interpolate(d)
            a = ln.interpolate(max(d - 0.5, 0.0))
            c = ln.interpolate(min(d + 0.5, ln.length))
            tv = np.array([c.x - a.x, c.y - a.y])
            if np.linalg.norm(tv) < 1e-6:
                continue
            tv /= np.linalg.norm(tv)
            nv = np.array([-tv[1], tv[0]])
            p0 = np.array([pt.x, pt.y])
            if cl.contains(Point(*(p0 + nv * 1.0))):
                nv = -nv  # 外（歩道）へ
            base = p0 + nv * outm
            if max(abs(base[0]), abs(base[1])) < float(lc["min_from_center_m"]):
                continue
            if base[1] > float(lc.get("max_z_m", 1e9)):
                continue  # カメラのがわ（手前）：戦いの場所の前をふさぐので立てない
            if any(np.linalg.norm(base - q) < every * 0.6 for q in placed):
                continue
            placed.append(base)
            y0 = float(height(base.reshape(1, 2))[0]) + 0.05
            inward = -nv
            # 柱
            P = np.array([base[0], y0 + H / 2, base[1]])
            box(lamps, P, np.array([inward[0], 0.0, inward[1]]), 0.09, 0.09, H / 2, pole_c)
            # うで（道のほうへ）
            A = np.array([base[0] + inward[0] * arm / 2, y0 + H - 0.1, base[1] + inward[1] * arm / 2])
            box(lamps, A, np.array([inward[0], 0.0, inward[1]]), arm / 2, 0.06, 0.06, pole_c)
            # 光る頭（下の面も見えるように、箱の横4面＋下の面）
            Hd = np.array([base[0] + inward[0] * arm, y0 + H - 0.25, base[1] + inward[1] * arm])
            box(lamps, Hd, np.array([inward[0], 0.0, inward[1]]), 0.35, 0.18, 0.1, head_c)
            av = np.array([inward[0], 0.0, inward[1]])
            bv = np.cross(YAXIS, av)
            lo = Hd - YAXIS * 0.1
            q = np.array([lo - av * 0.35 - bv * 0.18, lo + av * 0.35 - bv * 0.18, lo + av * 0.35 + bv * 0.18, lo - av * 0.35 + bv * 0.18])
            lamps.add(q, down_tris(q), (0.0, -1.0, 0.0), head_c)
            # 地面の光の輪
            g = np.array([Hd[0], Hd[2]])
            sq = np.array([g + [-pm / 2, -pm / 2], g + [pm / 2, -pm / 2], g + [pm / 2, pm / 2], g + [-pm / 2, pm / 2]])
            ys = height(sq) + float(lc["pool_lift_m"])
            pts = np.stack([sq[:, 0], ys, sq[:, 1]], 1)
            pools.add(pts, up_tris(pts), UP, (1.0, 1.0, 1.0, 1.0), np.array([[0, 0], [1, 0], [1, 1], [0, 1]], np.float32))
            stats["lamps"] = stats.get("lamps", 0) + 1
    return lamps, pools


def arena_flatness(arrs, half, step=0.5):
    """戦いの場所（±half）の床（道路の面）の高さを、細かい点で調べて、0 からのいちばん大きいずれを返す"""
    pos, nor, col, idx = arrs
    t = idx.reshape(-1, 3)
    P = pos[t]
    near = np.all(np.abs(P[:, :, [0, 2]]).max(axis=1) < half + 200, axis=1)
    P = P[near]
    lo = P[:, :, [0, 2]].min(1)
    hi = P[:, :, [0, 2]].max(1)
    worst = 0.0
    g = np.arange(-half, half + 1e-6, step)
    for x in g:
        for z in g:
            cand = np.where((lo[:, 0] <= x) & (hi[:, 0] >= x) & (lo[:, 1] <= z) & (hi[:, 1] >= z))[0]
            best = None
            for k in cand:
                a, b2, c = P[k][:, [0, 2]]
                v0, v1, v2 = c - a, b2 - a, np.array([x, z]) - a
                den = v0 @ v0 * (v1 @ v1) - (v0 @ v1) ** 2
                if abs(den) < 1e-12:
                    continue
                u = ((v1 @ v1) * (v2 @ v0) - (v0 @ v1) * (v2 @ v1)) / den
                w = ((v0 @ v0) * (v2 @ v1) - (v0 @ v1) * (v2 @ v0)) / den
                if u >= -1e-6 and w >= -1e-6 and u + w <= 1 + 1e-6:
                    y = P[k][0, 1] + u * (P[k][2, 1] - P[k][0, 1]) + w * (P[k][1, 1] - P[k][0, 1])
                    best = y if best is None else max(best, y)
            if best is not None:
                worst = max(worst, abs(best))
    return float(worst)


# ---------------------------------------------------------------- 看板・大画面（自作の絵。tools/make_signs.py が作る assets/maps/shibuya/signs.png）

ATLAS_PX = 512.0
ATLAS = {  # 種類: (左上 x, 左上 y, 幅, 高さ, 横の数)。make_signs.py の並びと同じ
    "vertical": (0, 0, 64, 256, 8, 8),
    "wide": (0, 256, 128, 64, 4, 4),
    "fascia": (0, 320, 64, 32, 8, 16),
}
YAXIS = np.array([0.0, 1.0, 0.0])


def atlas_uv(kind, k):
    x0, y0, w, h, per_row, n = ATLAS[kind]
    k = int(k) % n
    x = x0 + (k % per_row) * w
    y = y0 + (k // per_row) * h
    e = 1.0  # にじまないように 1 ピクセル内がわ
    return ((x + e) / ATLAS_PX, (y + e) / ATLAS_PX, (x + w - e) / ATLAS_PX, (y + h - e) / ATLAS_PX)


def quad(mesh, center, n, w, h, rgba, uv=None):
    """向き n（外向き・横）の、たて長方形。左下→右下→右上→左上。uv=(u0,v0,u1,v1)（v0 が上）"""
    right = np.cross(YAXIS, n)
    right /= np.linalg.norm(right)
    c = np.asarray(center, float)
    pts = np.array([c - right * w / 2 - YAXIS * h / 2, c + right * w / 2 - YAXIS * h / 2,
                    c + right * w / 2 + YAXIS * h / 2, c - right * w / 2 + YAXIS * h / 2])
    uvs = None
    if uv is not None:
        u0, v0, u1, v1 = uv
        uvs = np.array([[u0, v1], [u1, v1], [u1, v0], [u0, v0]])
    mesh.add(pts, np.array([[0, 1, 2], [0, 2, 3]]), n, rgba, uvs)


def box(mesh, c, a, ha, hb, hy, rgba):
    """細い柱・金具（色だけ）。a：横の向き（単位）。ha：a の向きの半分の長さ、hb：それと直角の半分、hy：高さの半分"""
    c = np.asarray(c, float)
    a = np.asarray(a, float)
    bv = np.cross(YAXIS, a)
    for n, off, w in ((a, ha, 2 * hb), (-a, ha, 2 * hb), (bv, hb, 2 * ha), (-bv, hb, 2 * ha)):
        quad(mesh, c + n * off, n, w, 2 * hy, rgba)


def wall_faces(bd, fr, dy, base_y, sc):
    """看板をつけられる壁（交差点のほうを向いている、たての面）を返す"""
    out = []
    for k, rr in bd["lod2"]:
        if k != "wall":
            continue
        g = fr.game(rr[0]) + [0.0, dy, 0.0]
        ring = g[:-1] if len(g) > 3 and np.allclose(g[0], g[-1]) else g
        if len(ring) < 3:
            continue
        nn = newell(ring)
        if nn is None or abs(nn[1]) > 0.2:
            continue
        n = np.array([nn[0], 0.0, nn[2]])
        n /= np.linalg.norm(n)
        t = np.cross(YAXIS, n)
        uu = ring @ t
        plane = float(np.mean(ring @ n))
        w = float(uu.max() - uu.min())
        y0, y1 = float(ring[:, 1].min()), float(ring[:, 1].max())
        if w < 2.5 or y1 - y0 < 3.0:
            continue
        # 面積（ニューウェル）と、外の四角の面積の比（1 に近いほど長方形）
        q = np.roll(ring, -1, axis=0)
        area = 0.5 * np.linalg.norm(np.sum(np.cross(ring, q), axis=0))
        rect = area / max(w * (y1 - y0), 1e-6)
        mid = t * (uu.min() + uu.max()) / 2 + n * plane
        d = math.hypot(mid[0], mid[2])
        facing = float(-(n[0] * mid[0] + n[2] * mid[2]) / max(d, 1e-6))
        if d > float(sc["radius_m"]) or facing < float(sc["facing_min"]):
            continue
        out.append({"n": n, "t": t, "u0": float(uu.min()), "u1": float(uu.max()), "plane": plane, "y0": y0, "y1": y1,
                    "w": w, "rect": rect, "dist": d, "facing": facing, "base": base_y, "used": []})
    return out


def wall_point(f, u, y, out=0.0):
    p = f["t"] * u + f["n"] * (f["plane"] + out)
    p[1] = y
    return p


def free(f, u0, u1, y0, y1):
    for a0, a1, b0, b1 in f["used"]:
        if u0 < a1 and u1 > a0 and y0 < b1 and y1 > b0:
            return False
    return True


def build_signs(data, fr, b, stats):
    """交差点のほうを向いた壁に、看板・大画面をつける（数・大きさ・高さは data/maps.json の build.signs）。
    写真の渋谷を参考にした置き方：1階の店の帯・角から横に出るたて長の看板・壁の横長の看板（重ねて）・屋上の看板・大きな画面。
    店名・ロゴはすべて自作（make_signs.py）。"""
    sc = b["signs"]
    signs, screens = Mesh("Signs", uv=True), Mesh("Screens", uv=True)
    white = (1.0, 1.0, 1.0, 1.0)
    frame_c = (*hex_rgb(sc["frame_color"]), 0.0)
    band_cols = [hex_rgb(c) for c in sc["fascia"]["band_colors"]]
    blds = []
    for bd in data["bldg"]:
        if not bd["lod2"]:
            continue
        foot, cx, cz, dist, dy, base_y = place_building(bd, fr, b)
        if dist > float(sc["radius_m"]) + 30.0 or in_arena(foot, b):
            continue
        faces = wall_faces(bd, fr, dy, base_y, sc)
        if faces:
            top = max(f["y1"] for f in faces)
            blds.append((bd, faces, base_y, top))
    # 1) 大画面：大きくて交差点によく見える壁から（1つの建物に1つ）
    cs = sc["screens"]
    cand = []
    for bd, faces, base_y, top in blds:
        for f in faces:
            if f["w"] >= float(cs["min_wall_w"]) and f["y1"] - base_y >= float(cs["min_wall_h"]) and f["rect"] >= 0.8 and f["facing"] >= 0.6:
                cand.append((f["w"] * min(f["y1"] - base_y, 40.0) * f["facing"] / max(f["dist"], 30.0), bd["id"], f))
    cand.sort(key=lambda x: -x[0])
    done = set()
    for score, bid, f in cand:
        if bid in done or len(done) >= int(cs["max"]):
            continue
        W = min(f["w"] * 0.85, float(cs["max_w"]))
        H = W / 2.0
        yc = f["base"] + (f["y1"] - f["base"]) * 0.62
        yc = min(max(yc, f["base"] + float(cs["min_bottom_m"]) + H / 2), f["y1"] - 1.0 - H / 2)
        uc = (f["u0"] + f["u1"]) / 2
        if yc - H / 2 < f["base"] + 4.5:
            continue
        quad(signs, wall_point(f, uc, yc, 0.12), f["n"], W + 0.8, H + 0.8, frame_c)
        k = len(done)
        quad(screens, wall_point(f, uc, yc, 0.22), f["n"], W, H, ((k % 8) / 8.0, _rand(bid, 9), 0.0, 1.0), (0.0, 0.0, 1.0, 1.0))
        f["used"].append((uc - W / 2 - 0.6, uc + W / 2 + 0.6, yc - H / 2 - 0.6, yc + H / 2 + 0.6))
        done.add(bid)
        stats["screens"] = stats.get("screens", 0) + 1
    # 2) 1階の店の帯（色の帯＋店名の板）
    fc = sc["fascia"]
    for bd, faces, base_y, top in blds:
        for i, f in enumerate(faces):
            if f["y0"] > f["base"] + 1.0 or f["y1"] < f["base"] + float(fc["y_m"]) + 1.0 or f["w"] < 3.5:
                continue
            seed = bd["id"] + "f%d" % i
            y = f["base"] + float(fc["y_m"])
            L = f["w"] - 0.6
            uc = (f["u0"] + f["u1"]) / 2
            bc = band_cols[int(_rand(seed, 1) * len(band_cols)) % len(band_cols)]
            quad(signs, wall_point(f, uc, y, 0.10), f["n"], L, float(fc["band_h_m"]), (*bc, 0.0))
            tw, th = float(fc["tile_w_m"]), float(fc["tile_h_m"])
            nt = max(1, int(L / float(fc["every_m"])))
            for j in range(nt):
                u = f["u0"] + 0.3 + (j + 0.5) * L / nt
                quad(signs, wall_point(f, u, y, 0.14), f["n"], min(tw, L / nt - 0.2), th, white,
                     atlas_uv("fascia", int(_rand(seed, 10 + j) * 16)))
                stats["fascia"] = stats.get("fascia", 0) + 1
            f["used"].append((f["u0"], f["u1"], y - 0.8, y + 0.8))
    # 3) 角から横に出る、たて長の看板（両面）
    vc = sc["vertical"]
    for bd, faces, base_y, top in blds:
        count = 0
        for i, f in enumerate(faces):
            seed = bd["id"] + "v%d" % i
            if count >= int(vc["max_per_bldg"]) or f["y1"] - f["base"] < float(vc["min_wall_h"]) or f["w"] < 4.0:
                continue
            if _rand(seed, 1) > float(vc["prob"]):
                continue
            H = float(vc["h_m"]) * (1.0 + 0.5 * _rand(seed, 2))
            W = H / 4.0
            yb = f["base"] + float(vc["bottom_m"]) + 2.0 * _rand(seed, 3)
            if yb + H > f["y1"] - 0.3:
                H = f["y1"] - 0.3 - yb
                W = H / 4.0
            if H < 3.0:
                continue
            side = f["u0"] + 0.4 if _rand(seed, 4) < 0.5 else f["u1"] - 0.4
            if not free(f, side - 0.5, side + 0.5, yb, yb + H):
                continue
            out = float(vc["gap_m"]) + W / 2
            c = wall_point(f, side, yb + H / 2, out)
            uv = atlas_uv("vertical", int(_rand(seed, 5) * 8))
            quad(signs, c, f["t"], W, H, white, uv)
            quad(signs, c, -f["t"], W, H, white, uv)
            # 壁へつなぐ金具
            box(signs, wall_point(f, side, yb + H * 0.85, out / 2), f["n"], out / 2, 0.04, 0.06, frame_c)
            f["used"].append((side - 0.6, side + 0.6, yb, yb + H))
            count += 1
            stats["vertical"] = stats.get("vertical", 0) + 1
    # 4) 壁の横長の看板（上へ重ねる。センター街の入り口のように）
    wc = sc["wide"]
    for bd, faces, base_y, top in blds:
        for i, f in enumerate(faces):
            seed = bd["id"] + "w%d" % i
            if f["w"] < 6.0 or f["y1"] - f["base"] < 10.0 or f["rect"] < 0.75 or _rand(seed, 1) > float(wc["prob"]):
                continue
            W = min(f["w"] * 0.7, float(wc["max_w_m"]))
            H = W / 2.0
            uc = f["u0"] + W / 2 + 0.6 + (f["w"] - W - 1.2) * _rand(seed, 2)
            y = f["base"] + float(wc["bottom_m"]) + H / 2
            n_st = 1 + int(_rand(seed, 3) * int(wc["max_stack"]))
            for j in range(n_st):
                if y + H / 2 > f["y1"] - 0.5:
                    break
                if free(f, uc - W / 2, uc + W / 2, y - H / 2, y + H / 2):
                    quad(signs, wall_point(f, uc, y, 0.16), f["n"], W, H, white, atlas_uv("wide", int(_rand(seed, 10 + j) * 4)))
                    f["used"].append((uc - W / 2, uc + W / 2, y - H / 2, y + H / 2))
                    stats["wide"] = stats.get("wide", 0) + 1
                y += H + 1.0
    # 5) 屋上の看板（低めの建物の、交差点を向いた壁の上）
    rcf = sc["roof"]
    nroof = 0
    for bd, faces, base_y, top in sorted(blds, key=lambda x: min(f["dist"] for f in x[1])):
        if nroof >= int(rcf["max"]) or top - base_y > float(rcf["max_bldg_h_m"]) or top - base_y < 6.0:
            continue
        f = max(faces, key=lambda f: f["w"] * f["facing"])
        seed = bd["id"] + "r"
        if f["y1"] < top - 0.5 or f["w"] < 7.0 or f["facing"] < 0.7 or _rand(seed, 1) > float(rcf["prob"]):
            continue
        W = min(f["w"] * 0.8, float(rcf["max_w_m"]))
        H = W / 2.0
        uc = (f["u0"] + f["u1"]) / 2
        yb = f["y1"] + float(rcf["lift_m"])
        c = wall_point(f, uc, yb + H / 2, -0.8)
        quad(signs, c, f["n"], W, H, white, atlas_uv("wide", int(_rand(seed, 2) * 4)))
        quad(signs, c - f["n"] * 0.05, -f["n"], W, H, frame_c)
        for s_ in (-0.35, 0.35):
            box(signs, wall_point(f, uc + W * s_, f["y1"] + float(rcf["lift_m"]) / 2 + 0.05, -0.85), f["n"], 0.12, 0.12, float(rcf["lift_m"]) / 2 + 0.05, frame_c)
        nroof += 1
        stats["roof_signs"] = stats.get("roof_signs", 0) + 1
    return signs, screens



def split_mesh(name, arrs, back_z, far_m):
    """版97：1つの形を「前（近い）」「前（遠い）＝_Far」「カメラの後ろ＝_Back」に分ける（遠いは重心の距離、後ろは3つの点すべての z）。
    戦いのカメラはいつも -Z を向くので、_Back は自動で描かれない（見えない所を描かない）。
    _Far は画質「低」では隠す（遠い所を描かない）。形は分けるだけで、点も色も変えない"""
    pos, nor, col, idx = arrs[:4]
    uv = arrs[4] if len(arrs) > 4 else None
    t = idx.reshape(-1, 3)
    c = pos[t].mean(axis=1)
    # 後ろ：3つの点がすべて back_z より後ろ（形の箱が、カメラの後ろにきちんと収まり、自動で描かれなくなる）
    back = pos[t][:, :, 2].min(axis=1) > back_z
    far = (~back) & (np.hypot(c[:, 0], c[:, 2]) >= far_m)
    near = ~(back | far)
    out = []
    for suffix, sel in (("", near), ("_Far", far), ("_Back", back)):
        if not sel.any():
            continue
        tt = t[sel]
        used, inv = np.unique(tt.reshape(-1), return_inverse=True)
        piece = (pos[used], nor[used], col[used], inv.astype(np.uint32))
        if uv is not None:
            piece = piece + (uv[used],)
        out.append((name + suffix, piece))
    return out

# ---------------------------------------------------------------- glb を書く

def write_glb(path, meshes, extras):
    bin_parts = []
    offset = 0
    views, accs, gmeshes, nodes, mats = [], [], [], [], []

    def add_view(data, target=None):
        nonlocal offset
        pad = (-offset) % 4
        if pad:
            bin_parts.append(b"\x00" * pad)
            offset += pad
        v = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        bin_parts.append(data)
        offset += len(data)
        return len(views) - 1

    for name, arrs in meshes:
        pos, nor, col, idx = arrs[:4]
        uv = arrs[4] if len(arrs) > 4 else None
        cu8 = np.clip(np.round(col * 255.0), 0, 255).astype(np.uint8)
        vp = add_view(pos.astype("<f4").tobytes(), 34962)
        vn = add_view(nor.astype("<f4").tobytes(), 34962)
        vc = add_view(cu8.tobytes(), 34962)
        big = pos.shape[0] > 65535
        vi = add_view(idx.astype("<u4" if big else "<u2").tobytes(), 34963)
        ap = len(accs)
        accs.append({"bufferView": vp, "componentType": 5126, "count": int(pos.shape[0]), "type": "VEC3",
                     "min": pos.min(0).astype(float).tolist(), "max": pos.max(0).astype(float).tolist()})
        accs.append({"bufferView": vn, "componentType": 5126, "count": int(pos.shape[0]), "type": "VEC3"})
        accs.append({"bufferView": vc, "componentType": 5121, "normalized": True, "count": int(pos.shape[0]), "type": "VEC4"})
        accs.append({"bufferView": vi, "componentType": 5125 if big else 5123, "count": int(idx.shape[0]), "type": "SCALAR"})
        attrs = {"POSITION": ap, "NORMAL": ap + 1, "COLOR_0": ap + 2}
        if uv is not None:
            vu = add_view(uv.astype("<f4").tobytes(), 34962)
            attrs["TEXCOORD_0"] = len(accs)
            accs.append({"bufferView": vu, "componentType": 5126, "count": int(pos.shape[0]), "type": "VEC2"})
        mats.append({"name": name + "Mat", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        gmeshes.append({"name": name, "primitives": [{"attributes": attrs, "indices": ap + 3, "material": len(mats) - 1}]})
        nodes.append({"name": name, "mesh": len(gmeshes) - 1})
    binary = b"".join(bin_parts)
    binary += b"\x00" * ((-len(binary)) % 4)
    gltf = {"asset": {"version": "2.0", "generator": "bigbusters tools/plateau_to_glb.py", "extras": extras},
            "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gmeshes,
            "materials": mats, "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(binary)}]}
    js = json.dumps(gltf, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(binary), 0x004E4942))
        f.write(binary)


# ---------------------------------------------------------------- 上から見た図

def preview(path, meshes, b, info, extent=140.0):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    fig, axs = plt.subplots(1, 2, figsize=(20, 10))
    for ax, ext in ((axs[0], extent), (axs[1], float(b["radius_m"]))):
        for name, arrs in meshes:
            pos, nor, col, idx = arrs[:4]
            t = idx.reshape(-1, 3)
            if name in ("Signs", "Screens", "LightPools"):
                continue
            if name.startswith("Bldg"):
                up = nor[t[:, 0], 1] > 0.5
                t = t[up]
                if not len(t):
                    continue
            sel = np.all(np.abs(pos[t][:, :, [0, 2]]) < ext * 1.1, axis=(1, 2))
            t = t[sel]
            if not len(t):
                continue
            polys = pos[t][:, :, [0, 2]]
            fc = col[t[:, 0], :3]
            if name.startswith("Bldg"):
                fc = fc * 0.8
            ax.add_collection(PolyCollection(polys, facecolors=fc, edgecolors="none"))
        h = float(b["flat_half_m"])
        ax.plot([-15, 15, 15, -15, -15], [-15, -15, 15, 15, -15], "r-", lw=1.5)
        ax.plot([-h, h, h, -h, -h], [-h, -h, h, h, -h], "r--", lw=0.8)
        if info and info.get("outline"):
            o = np.array(info["outline"])
            ax.plot(o[:, 0], o[:, 1], "y-", lw=0.8)
        ax.arrow(0, 0, 0, -ext * 0.25, color="c", width=ext * 0.004)
        ax.set_xlim(-ext, ext)
        ax.set_ylim(ext, -ext)
        ax.set_aspect("equal")
        ax.set_facecolor("#20222a")
        ax.set_title("game coords (camera looks toward -Z = up). half %.0f m" % ext)
    plt.tight_layout()
    plt.savefig(path, dpi=60)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--map", default="shibuya")
    ap.add_argument("--cache", default="")
    ap.add_argument("--preview", default="")
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    cfg = json.load(open(ROOT / "data" / "maps.json", encoding="utf-8"))
    mc = cfg["maps"][args.map]
    b = mc["build"]
    t0 = time.time()
    data = load_all(args.src, args.cache, b)
    # 地形のまん中の高さ（三角形の中の点の高さ）を 0 にする
    fr = Frame(b["center_lat"], b["center_lon"], float(b["heading_deg"]))
    h0 = 0.0
    if len(data["dem"]):
        e = fr.enu(data["dem"].reshape(-1, 3)).reshape(-1, 3, 3)
        for tri in e:
            a, c, d = tri[0][[0, 2]], tri[1][[0, 2]], tri[2][[0, 2]]
            v0, v1, v2 = d - a, c - a, -a
            den = v0 @ v0 * (v1 @ v1) - (v0 @ v1) ** 2
            if abs(den) < 1e-12:
                continue
            v = ((v1 @ v1) * (v2 @ v0) - (v0 @ v1) * (v2 @ v1)) / den
            w = ((v0 @ v0) * (v2 @ v1) - (v0 @ v1) * (v2 @ v0)) / den
            if v >= -1e-6 and w >= -1e-6 and v + w <= 1 + 1e-6:
                h0 = float(tri[0][1] + v * (tri[2][1] - tri[0][1]) + w * (tri[1][1] - tri[0][1]))
                break
    fr = Frame(b["center_lat"], b["center_lon"], float(b["heading_deg"]), h0)
    log("まん中の地面の高さ: %.2f m" % h0)
    stats = {k: 0 for k in ("inside_arena", "bad_poly", "bldg_near", "bldg_far", "road_tris", "terrain_tris", "terrain_hidden", "crosswalks", "diagonals")}
    near, far = build_buildings(data, fr, b, stats)
    ground, terrain, road_pts = build_ground(data, fr, b, stats)
    rh = road_height(road_pts)
    cross, info = build_crosswalks(data, fr, b, stats, rh)
    signs, screens = build_signs(data, fr, b, stats)
    lamps, pools = build_lamps(info, b, stats, rh)
    meshes = []
    for m in (terrain, ground, cross, near, far, signs, screens, lamps, pools):
        arrs = m.arrays()
        if arrs is None:
            continue
        if m.name in ("Ground", "Crosswalk", "Terrain"):
            arrs = weld(arrs)
        meshes.append((m.name, arrs))
        log("%-10s 三角形 %7d  点 %7d" % (m.name, len(arrs[3]) // 3, len(arrs[0])))
    stats["arena_max_dev_m"] = arena_flatness(dict(meshes)["Ground"], float(b.get("check_half_m", 15.0)))
    log("戦いの場所の床の高さのずれ（いちばん大きい所）: %.3f m" % stats["arena_max_dev_m"])
    # 版97：大きな形を、前・遠い前・後ろに分ける（見えない所・遠い所を描かないため）
    sp = b.get("split", {})
    if sp:
        split = []
        for name, arrs in meshes:
            if name in sp.get("parts", []):
                pieces = split_mesh(name, arrs, float(sp["back_z_m"]), float(sp["far_m"]))
                for pn, pa in pieces:
                    log("  分けた %-14s 三角形 %7d" % (pn, len(pa[3]) // 3))
                split += pieces
            else:
                split.append((name, arrs))
        meshes = split
    out = Path(args.out) if args.out else ROOT / mc["glb"].replace("res://", "")
    out.parent.mkdir(parents=True, exist_ok=True)
    extras = {"attribution": mc["attribution"], "center": [b["center_lat"], b["center_lon"]], "heading_deg": b["heading_deg"],
              "ground_h": h0, "stats": stats, "crossing": {k: v for k, v in (info or {}).items() if k not in ("outline", "walk_lines")}}
    write_glb(out, meshes, extras)
    log("書いた:", out, "%.1f MB" % (out.stat().st_size / 1e6), stats, "%.0f秒" % (time.time() - t0))
    if args.preview:
        preview(args.preview, meshes, b, info)
        log("上から見た図:", args.preview)


if __name__ == "__main__":
    main()
