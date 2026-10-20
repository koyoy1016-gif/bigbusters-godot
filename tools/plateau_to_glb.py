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
    def __init__(self, name):
        self.name = name
        self.pos, self.nor, self.col, self.idx = [], [], [], []
        self.nv = 0
        self.ntri = 0

    def add(self, pts, tri, normal, rgba):
        k = len(pts)
        self.pos.append(pts.astype(np.float32))
        self.nor.append(np.tile(np.asarray(normal, np.float32), (k, 1)))
        self.col.append(np.tile(np.asarray(rgba, np.float32), (k, 1)))
        self.idx.append(tri.astype(np.uint32) + self.nv)
        self.nv += k
        self.ntri += len(tri)

    def arrays(self):
        if not self.pos:
            return None
        return (np.concatenate(self.pos), np.concatenate(self.nor), np.concatenate(self.col), np.concatenate(self.idx).reshape(-1))


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


def build_buildings(data, fr, b, stats):
    cols = b["colors"]
    walls = [hex_rgb(c) for c in cols["walls"]]
    glass = [hex_rgb(c) for c in cols["glass"]]
    roof = hex_rgb(cols["roof"])
    inst = hex_rgb(cols["install"])
    near, far = Mesh("BldgNear"), Mesh("BldgFar")
    R, R2, RI = float(b["radius_m"]), float(b["lod2_radius_m"]), float(b["install_radius_m"])
    arena = float(b.get("check_half_m", 15.0)) + 2.0  # 戦いの場所（と、まわり2m）にかかる建物は出さない
    for bd in data["bldg"]:
        src = bd["lod1"] or [rr for _, rr in bd["lod2"]]
        foot = fr.game(np.concatenate([rr[0] for rr in src]))
        cx, cz = float(foot[:, 0].mean()), float(foot[:, 2].mean())
        dist = math.hypot(cx, cz)
        if dist > R:
            continue
        if np.any((np.abs(foot[:, 0]) < arena) & (np.abs(foot[:, 2]) < arena)):
            stats["inside_arena"] += 1
            continue
        # 建物ごとの高さの合わせ（平らにした所の近くでは、建物ごと上下させる。形はくずさない）
        base_real = float(foot[:, 1].min())
        base_flat = float(flatten(np.array([[cx, base_real, cz]]), b)[0, 1])
        dy = base_flat - base_real
        tall = bd["h"] >= float(cols["glass_from_m"])
        pal = glass if tall else walls
        wc = pal[int(_rand(bd["id"], 1) * len(pal)) % len(pal)] * (0.92 + 0.16 * _rand(bd["id"], 2))
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
                rgba = (*wc, 1.0)  # a=1：窓を描く面
            elif kind == "roof":
                rgba = (*rc, 0.0)
            else:
                rgba = (*(inst * (0.9 + 0.2 * _rand(bd["id"], 4))), 0.0)
            target.add(pts, tri, n, rgba)
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

    def bar(p0, along, across, w, l):
        quad = np.array([p0, p0 + along * w, p0 + along * w + across * l, p0 + across * l])
        y = height(quad) + 0.02
        pts = np.stack([quad[:, 0], y, quad[:, 1]], 1)
        m.add(pts, np.array([[0, 2, 1], [0, 3, 2]]), UP, (*col, 1.0))

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
    for A, B in diag:
        w = (B - A) / np.linalg.norm(B - A)
        side = np.array([-w[1], w[0]])
        L = np.linalg.norm(B - A)
        s = float(cw.get("diag_trim_m", 3.0))
        while s + stripe <= L - float(cw.get("diag_trim_m", 3.0)):
            bar(A + w * s - side * band / 2, w, side, stripe, band)
            s += stripe + gap
        stats["diagonals"] += 1
    return m, {"outline": np.array(cl.exterior.coords).tolist(), "mouths": made, "corners": [c.tolist() for c in corners],
               "diagonals": [[A.tolist(), B.tolist()] for A, B in diag], "cross_center": [cl.centroid.x, cl.centroid.y]}


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
        pos, nor, col, idx = arrs
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
        mats.append({"name": name + "Mat", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        gmeshes.append({"name": name, "primitives": [{"attributes": {"POSITION": ap, "NORMAL": ap + 1, "COLOR_0": ap + 2},
                                                       "indices": ap + 3, "material": len(mats) - 1}]})
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
            pos, nor, col, idx = arrs
            t = idx.reshape(-1, 3)
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
    cross, info = build_crosswalks(data, fr, b, stats, road_height(road_pts))
    meshes = []
    for m in (terrain, ground, cross, near, far):
        arrs = m.arrays()
        if arrs is None:
            continue
        if m.name in ("Ground", "Crosswalk", "Terrain"):
            arrs = weld(arrs)
        meshes.append((m.name, arrs))
        log("%-10s 三角形 %7d  点 %7d" % (m.name, len(arrs[3]) // 3, len(arrs[0])))
    stats["arena_max_dev_m"] = arena_flatness(dict(meshes)["Ground"], float(b.get("check_half_m", 15.0)))
    log("戦いの場所の床の高さのずれ（いちばん大きい所）: %.3f m" % stats["arena_max_dev_m"])
    out = Path(args.out) if args.out else ROOT / mc["glb"].replace("res://", "")
    out.parent.mkdir(parents=True, exist_ok=True)
    extras = {"attribution": mc["attribution"], "center": [b["center_lat"], b["center_lon"]], "heading_deg": b["heading_deg"],
              "ground_h": h0, "stats": stats, "crossing": {k: v for k, v in (info or {}).items() if k != "outline"}}
    write_glb(out, meshes, extras)
    log("書いた:", out, "%.1f MB" % (out.stat().st_size / 1e6), stats, "%.0f秒" % (time.time() - t0))
    if args.preview:
        preview(args.preview, meshes, b, info)
        log("上から見た図:", args.preview)


if __name__ == "__main__":
    main()
