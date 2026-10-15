"""胴体の外板：断面（超楕円）を前後に並べて張り、ガラス・ドア・白い帯・床下ハッチの境目を辺にそろえる。

輪の点は「目印の角度」で区切る。左半分（上の真ん中 θ=90° → 下の真ん中 θ=270°）の目印：
  A0 上の真ん中 / A1 屋根の梁のふち（x = -0.35）/ A2 ガラスの線 / A3 帯の上（1.44）/ A4 帯の下（1.30）
  / A5 ドアの敷居（0.76）/ A6 床下ハッチのふち（x = -0.65）/ A7 下の真ん中
目印のあいだの点の数（SEG）は輪ごとに同じなので、境目は輪をまたいで同じ点の並びになり、ギザギザにならない。
その断面に目印の高さがない（機首の先・尾の付け根）ときは、前後の目印から割り振る。

前後の位置（ステーション）は形の変わり方に合わせた間隔＋境目の z（ドアの前後、ハッチの前後、内張りの端）。
キャビン（-2.66〜1.15）の不透明な面には、壁の厚み（0.10）だけ内側に内張り（Interior）を付け、
ガラス・ハッチの穴・ドアとの境目には縁（Rubber）を付ける。
"""
from __future__ import annotations

import bisect
import math

from hb_common import BP, SPEC, GMesh, body_params, section_point, smoothstep

SEG = [2, 7, 3, 1, 3, 3, 2]                  # 目印のあいだの点の数（左半分）
ANCHOR_IDX = [0]
for _n in SEG:
    ANCHOR_IDX.append(ANCHOR_IDX[-1] + _n)    # [0, 2, 9, 12, 13, 16, 19, 21]
HALF = ANCHOR_IDX[-1]                         # 21
RING = 2 * HALF                               # 42

DOOR = SPEC["door"]
HATCH = SPEC["hatch"]
STRIPE_BOT, STRIPE_TOP = SPEC["stripe_y"]
WALL = BP["wall"]
Z_NOSE = BP["z"][0]
Z_END = BP["z"][-1]
CABIN_Z0 = SPEC["dash"]["front_z"] - 0.04     # 内張りの前の端（計器盤のうしろに隠れる）
CABIN_Z1 = SPEC["bay"]["rear_z"]              # 内張りの後ろの端（後ろの仕切り）
FLOOR_Y = SPEC["floor_y"]
CANOPY_LINE_NOSE = 1.50                       # 風防の下の線：ドアの前端（窓の線 1.95）から機首（z = -3.0）でこの高さへ下がる
SEG_STRIPE = 3                                # 白い帯の区間
SEG_ACCENT0 = 4                               # ここから下（帯の下〜下の真ん中）は濃紺（BodyAccent、色替えしない）
PAINT, ACCENT = "BodyPaint", "BodyAccent"


def paint_for(seg, y_mid=None, stripe_bot_defined=True, rear=False):
    """面の塗り：帯より下（セグメント 4〜6）は濃紺。帯の下の線がその断面にない所では：
    後ろ（尾の付け根。下面が帯の高さまで上がる所）はオレンジ（濃紺は帯の下の線とともに細って終わる。横を這い上がらない）、
    機首の先は面の高さが帯の下（STRIPE_BOT）より下のときだけ濃紺。"""
    if seg < SEG_ACCENT0:
        return PAINT
    if stripe_bot_defined or y_mid is None:
        return ACCENT
    if rear:
        return PAINT
    return ACCENT if y_mid < STRIPE_BOT else PAINT


def glass_line(z):
    if z >= DOOR["front_z"]:
        return DOOR["window_belt_y"]
    t = min(1.0, (DOOR["front_z"] - z) / (DOOR["front_z"] - (-3.0)))
    return DOOR["window_belt_y"] + (CANOPY_LINE_NOSE - DOOR["window_belt_y"]) * t


# ---------------------------------------------------------------- 輪

def _theta_for_y(p, y, margin=0.012):
    """左半分で、高さ y を通る角度（なければ None）。"""
    if y >= p["top"] - margin or y <= p["bottom"] + margin:
        return None
    belt = p["belt"]
    if y >= belt:
        s = ((y - belt) / (p["top"] - belt)) ** (p["n_top"] / 2)
        return math.pi - math.asin(min(1.0, s))
    s = ((belt - y) / (belt - p["bottom"])) ** (p["n_bot"] / 2)
    return math.pi + math.asin(min(1.0, s))


def _theta_for_x(p, x, upper, margin=0.02):
    if x >= p["a"] - margin:
        return None
    n = p["n_top"] if upper else p["n_bot"]
    c = (x / p["a"]) ** (n / 2)
    t = math.acos(-c)
    return t if upper else 2 * math.pi - t


# 目印が「ない」所から離れるほど、目印の角度をそのまま使う（その手前は点の数の比の割り振りと混ぜる）。
# 機首の先・尾の付け根で目印が出たり消えたりしても、輪の点が飛ばない（機首の下の陰影のよれを防ぐ）
ANCHOR_BLEND_M = {1: 0.10, 2: 0.10, 3: 0.20, 4: 0.20, 5: 0.35, 6: 0.35}
# 後ろ（z > 0）の帯の目印は混ぜない：帯と濃紺の境目が、下面が帯の高さへ上がる所まで y 1.30 / 1.44 のまま真っすぐ
ANCHOR_BLEND_M_REAR = {1: 0.10, 2: 0.10, 3: 0.0, 4: 0.0, 5: 0.35, 6: 0.35}
_UNDEFINED_Z: dict | None = None
RING_STATS = {"ring_order_fallbacks": 0}


def _raw_targets(z):
    p = body_params(z)
    return [math.pi / 2, _theta_for_x(p, DOOR["hinge_x"], True), _theta_for_y(p, glass_line(z)), _theta_for_y(p, STRIPE_TOP),
            _theta_for_y(p, STRIPE_BOT), _theta_for_y(p, DOOR["sill_y"]), _theta_for_x(p, HATCH["half_w"], False), 3 * math.pi / 2]


def _undefined_z():
    """目印ごとの「ない」z（機首から尾の付け根まで 3,001 か所）。"""
    global _UNDEFINED_Z
    if _UNDEFINED_Z is None:
        _UNDEFINED_Z = {k: [] for k in range(1, 7)}
        for i in range(3001):
            z = Z_NOSE + (Z_END - Z_NOSE) * i / 3000
            raw = _raw_targets(z)
            for k in range(1, 7):
                if raw[k] is None:
                    _UNDEFINED_Z[k].append(z)
    return _UNDEFINED_Z


def _distance_to_undefined(k, z):
    zs = _undefined_z()[k]
    if not zs:
        return math.inf
    i = bisect.bisect_left(zs, z)
    best = math.inf
    for j in (i - 1, i):
        if 0 <= j < len(zs):
            best = min(best, abs(zs[j] - z))
    return best


def anchor_weights(z):
    """目印 1〜6 の重み（1＝その断面の目印の角度、0＝割り振り）。"""
    raw = _raw_targets(z)
    w = [1.0] + [0.0] * 6 + [1.0]
    for k in range(1, 7):
        if raw[k] is None:
            continue
        L = (ANCHOR_BLEND_M_REAR if z > 0.0 else ANCHOR_BLEND_M)[k]
        w[k] = 1.0 if L <= 0 else smoothstep(0.0, L, _distance_to_undefined(k, z))
    return w, raw


def _solve_anchors(raw, w):
    """f_k − (1−w_k)·α_k·f_{k−1} − (1−w_k)·β_k·f_{k+1} = w_k·t_k（f_0 = π/2、f_7 = 3π/2）を三重対角で解く。
    w が 0 か 1 だけなら、今までの「ない目印は前後から点の数の比で割り振る」と同じ答えになる。"""
    I = ANCHOR_IDX
    sub, diag, sup, rhs = [0.0] * 8, [1.0] * 8, [0.0] * 8, [0.0] * 8
    for k in range(1, 7):
        a = (I[k + 1] - I[k]) / (I[k + 1] - I[k - 1])
        b = (I[k] - I[k - 1]) / (I[k + 1] - I[k - 1])
        sub[k] = -(1 - w[k]) * a
        sup[k] = -(1 - w[k]) * b
        rhs[k] = w[k] * (raw[k] if raw[k] is not None else 0.0)
    f0, f7 = math.pi / 2, 3 * math.pi / 2
    rhs[1] -= sub[1] * f0
    rhs[6] -= sup[6] * f7
    c = [0.0] * 8
    d = [0.0] * 8
    for k in range(1, 7):
        lo = sub[k] if k > 1 else 0.0
        den = diag[k] - lo * c[k - 1]
        c[k] = sup[k] / den if k < 6 else 0.0
        d[k] = (rhs[k] - lo * d[k - 1]) / den
    f = [0.0] * 8
    f[0], f[7] = f0, f7
    for k in range(6, 0, -1):
        f[k] = d[k] - (c[k] * f[k + 1] if k < 6 else 0.0)
    return f


def ring_thetas(z):
    """左半分の 22 個の角度と、目印ごとの「その断面にある」フラグ（面の分類に使う。今までと同じ値）。"""
    w, raw_new = anchor_weights(z)
    anchors_new = _solve_anchors(raw_new, w)
    ok = all(anchors_new[k] > anchors_new[k - 1] + 1e-3 for k in range(1, 8))
    thetas_old, defined = _ring_thetas_old(z)
    if not ok:
        RING_STATS["ring_order_fallbacks"] += 1
        return thetas_old, defined
    thetas = []
    for s in range(7):
        for j in range(SEG[s]):
            thetas.append(anchors_new[s] + (anchors_new[s + 1] - anchors_new[s]) * j / SEG[s])
    thetas.append(anchors_new[7])
    return thetas, defined


def _ring_thetas_old(z):
    """今までの割り振り（目印の順番が崩れたら「ない」ことにし、前後から点の数の比で割り振る）。"""
    p = body_params(z)
    raw = [math.pi / 2, _theta_for_x(p, DOOR["hinge_x"], True), _theta_for_y(p, glass_line(z)), _theta_for_y(p, STRIPE_TOP),
           _theta_for_y(p, STRIPE_BOT), _theta_for_y(p, DOOR["sill_y"]), _theta_for_x(p, HATCH["half_w"], False), 3 * math.pi / 2]
    # 順番が崩れた目印は「ない」ことにする
    defined = [t is not None for t in raw]
    last = raw[0]
    for k in range(1, 7):
        if raw[k] is not None and (raw[k] <= last + 1e-4 or raw[k] >= raw[7] - 1e-4):
            raw[k] = None
            defined[k] = False
        if raw[k] is not None:
            last = raw[k]
    # ない目印は、前後の目印から点の数の比で割り振る
    anchors = list(raw)
    for k in range(1, 7):
        if anchors[k] is None:
            kp = max(j for j in range(k) if raw[j] is not None)
            kn = min(j for j in range(k + 1, 8) if raw[j] is not None)
            f = (ANCHOR_IDX[k] - ANCHOR_IDX[kp]) / (ANCHOR_IDX[kn] - ANCHOR_IDX[kp])
            anchors[k] = raw[kp] + (raw[kn] - raw[kp]) * f
    thetas = []
    for s in range(7):
        for j in range(SEG[s]):
            thetas.append(anchors[s] + (anchors[s + 1] - anchors[s]) * j / SEG[s])
    thetas.append(anchors[7])
    return thetas, defined


def full_ring(z, wall=0.0):
    """輪の 42 点（Godot の座標、地面基準）。左半分のあと、右半分を下から上へ。"""
    p = body_params(z)
    thetas, defined = ring_thetas(z)
    left = [section_point(p, t, wall) for t in thetas]
    right = [(-x, y) for x, y in reversed(left[1:-1])]
    return [(x, y, z) for x, y in left + right], defined


def stations(step=0.17):
    """前後の位置：弧の長さで等間隔（機首で細かく）＋境目の z。"""
    zs = [Z_NOSE + (Z_END - Z_NOSE) * i / 3000 for i in range(3001)]
    acc = [0.0]
    prev = body_params(zs[0])
    for z in zs[1:]:
        p = body_params(z)
        d = math.sqrt(((Z_END - Z_NOSE) / 3000) ** 2 + (p["a"] - prev["a"]) ** 2 + (p["top"] - prev["top"]) ** 2 + (p["bottom"] - prev["bottom"]) ** 2)
        acc.append(acc[-1] + d)
        prev = p
    total = acc[-1]
    n = max(2, int(round(total / step)))
    out = []
    j = 0
    for i in range(n + 1):
        target = total * i / n
        while j < len(acc) - 2 and acc[j + 1] < target:
            j += 1
        f = (target - acc[j]) / max(1e-9, acc[j + 1] - acc[j])
        out.append(zs[j] + (zs[j + 1] - zs[j]) * f)
    forced = [DOOR["front_z"], DOOR["rear_z"], HATCH["z"][0], HATCH["z"][1], CABIN_Z0, CABIN_Z1]
    for fz in forced:
        out = [z for z in out if abs(z - fz) > 0.06 or z in (Z_NOSE, Z_END)]
        out.append(fz)
    return sorted(set(round(z, 6) for z in out))


# ---------------------------------------------------------------- 面の分類

def segment_of(r):
    """輪の番号 r の四角（r → r+1）が属する区間（0〜6）と、左右。"""
    if r < HALF:
        i = r
        side = "L"
    else:
        i = RING - 1 - r
        side = "R"
    for s in range(7):
        if ANCHOR_IDX[s] <= i < ANCHOR_IDX[s + 1]:
            return s, side
    return 6, side


def classify(z0, z1, r, def0, def1, y_mid=None):
    """四角の (部品, 材質)。部品は Body / Windows / Door_L / Door_R、None は穴。y_mid は四角の高さの平均（塗り分けに使う）。"""
    zm = (z0 + z1) / 2
    seg, side = segment_of(r)
    glass_ok = def0[2] and def1[2]
    stripe_ok = def0[3] and def0[4] and def1[3] and def1[4]
    if HATCH["z"][0] < zm < HATCH["z"][1] and seg == 6 and def0[6] and def1[6]:
        return None, None
    if zm < DOOR["front_z"] and seg in (0, 1) and glass_ok:
        return "Windows", "Windows"
    in_door = DOOR["front_z"] < zm < DOOR["rear_z"] and seg in (1, 2, 3, 4) and def0[1] and def1[1]
    part = f"Door_{side}" if in_door else "Body"
    if in_door and seg == 1:
        return part, "Windows"
    if seg == SEG_STRIPE and stripe_ok:
        return part, "Trim"
    return part, paint_for(seg, y_mid, def0[4] and def1[4], rear=zm > 0.0)


def build_shell():
    """外板・内張り・縁を部品ごとの GMesh で返す。"""
    zs = stations()
    RING_STATS["ring_order_fallbacks"] = 0
    outer, defs = [], []
    for z in zs:
        ring, defined = full_ring(z)
        outer.append(ring)
        defs.append(defined)
    # 機首の下の輪の点の飛び（隣のステーションとの角度の差の最大 − 中央値）と、ドア・ハッチ・風防で目印がそのまま使われているか
    nose = [ring_thetas(z)[0] for z in zs if z < -2.3]
    deltas = sorted(abs(b[r] - a[r]) for a, b in zip(nose[:-1], nose[1:]) for r in range(13, 21))   # 帯の下〜下の真ん中（セグメント 4〜6）
    nose_jump = (deltas[-1] - deltas[len(deltas) // 2]) if deltas else 0.0
    inexact = []
    for z in zs:
        w = anchor_weights(z)[0]
        if DOOR["front_z"] - 1e-6 <= z <= DOOR["rear_z"] + 1e-6 and any(w[k] < 1.0 - 1e-9 for k in range(1, 6)):
            inexact.append(("door", round(z, 3)))
        if HATCH["z"][0] - 1e-6 <= z <= HATCH["z"][1] + 1e-6 and w[6] < 1.0 - 1e-9:
            inexact.append(("hatch", round(z, 3)))
        if -2.95 <= z <= DOOR["rear_z"] and w[2] < 1.0 - 1e-9:
            inexact.append(("glass", round(z, 3)))
    inner = {}
    for k, z in enumerate(zs):
        if CABIN_Z0 - 1e-6 <= z <= CABIN_Z1 + 1e-6:
            inner[k] = full_ring(z, WALL)[0]
    parts: dict[str, GMesh] = {}

    def mesh(name):
        return parts.setdefault(name, GMesh())

    cell = {}   # (k, r) → (部品, 材質, 内張りあり)
    stripe_z_end = -9.0
    for k in range(len(zs) - 1):
        for r in range(RING):
            j = (r + 1) % RING
            y_mid = (outer[k][r][1] + outer[k][j][1] + outer[k + 1][j][1] + outer[k + 1][r][1]) / 4
            part, mat = classify(zs[k], zs[k + 1], r, defs[k], defs[k + 1], y_mid)
            if part is None:
                cell[(k, r)] = (None, None, False)
                continue
            quad = [outer[k][r], outer[k][j], outer[k + 1][j], outer[k + 1][r]]
            mesh(part).face(quad, mat, smooth=True, weld=f"{part}:outer")
            lined = (mat != "Windows" and k in inner and (k + 1) in inner
                     and max(outer[k][r][1], outer[k][j][1], outer[k + 1][j][1], outer[k + 1][r][1]) > FLOOR_Y + 0.02)
            if lined:
                iq = [inner[k][r], inner[k][j], inner[k + 1][j], inner[k + 1][r]]
                mesh(part).face(list(reversed(iq)), "Interior", smooth=True, weld=f"{part}:inner")
            cell[(k, r)] = (part, mat, lined)
            if mat == "Trim":
                stripe_z_end = max(stripe_z_end, zs[k + 1])
    # 縁：内張りのある四角の辺で、となりが「ガラス・穴・別の部品」なら、外板と内張りのあいだをふさぐ
    rims = 0
    for (k, r), (part, mat, lined) in cell.items():
        if not lined:
            continue
        j = (r + 1) % RING
        edges = [  # (外板の 2 点の (ステーション, 輪), となりの四角)
            (((k, r), (k, j)), (k - 1, r)),
            (((k + 1, r), (k + 1, j)), (k + 1, r)),
            (((k, r), (k + 1, r)), (k, (r - 1) % RING)),
            (((k, j), (k + 1, j)), (k, j)),
        ]
        for (a, b), nb in edges:
            if nb[0] < 0 or nb[0] >= len(zs) - 1:
                continue
            npart, nmat, nlined = cell.get(nb, (None, None, False))
            if nlined and npart == part:
                continue
            if npart is not None and nmat != "Windows" and not nlined:
                continue    # 床の下（内張りなし）とのあいだは床が隠す
            if a[0] not in inner or b[0] not in inner:
                continue
            pa, pb = outer[a[0]][a[1]], outer[b[0]][b[1]]
            ia, ib = inner[a[0]][a[1]], inner[b[0]][b[1]]
            # 縁の面はとなりの四角のほうへ向ける
            ck = [outer[k][r], outer[k][j], outer[k + 1][j], outer[k + 1][r]]
            cx = sum(p[0] for p in ck) / 4, sum(p[1] for p in ck) / 4, sum(p[2] for p in ck) / 4
            mid = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2)
            hint = (mid[0] - cx[0], mid[1] - cx[1], mid[2] - cx[2])
            mesh(part)._oriented([pa, pb, ib, ia], hint, "Rubber")
            rims += 1
    # 機首の先（白い帯は先端の一点まで寄せる）と尾の付け根をふさぐ
    ring = outer[0]
    c = (0.0, (max(p[1] for p in ring) + min(p[1] for p in ring)) / 2, zs[0] - 0.04)
    stripe0 = defs[0][3] and defs[0][4]
    for r in range(RING):
        j = (r + 1) % RING
        seg, _ = segment_of(r)
        mat = "Trim" if (seg == SEG_STRIPE and stripe0) else paint_for(seg, (c[1] + ring[j][1] + ring[r][1]) / 3, defs[0][4])
        mesh("Body").face([c, ring[j], ring[r]], mat, smooth=True, weld="Body:outer")
    ring = outer[-1]
    c = (0.0, sum(p[1] for p in ring) / len(ring), zs[-1])
    for r in range(RING):
        j = (r + 1) % RING
        mesh("Body")._oriented([c, ring[r], ring[j]], (0, 0, 1), paint_for(segment_of(r)[0], (c[1] + ring[r][1] + ring[j][1]) / 3, defs[-1][4], rear=True))
    stats = {"stations": len(zs), "ring": RING, "rims": rims, "z_first": zs[0], "z_last": zs[-1],
             "nose_theta_jump": round(nose_jump, 4), "stripe_z_end": round(stripe_z_end, 4), "ring_order_fallbacks": RING_STATS["ring_order_fallbacks"], "anchor_inexact": inexact[:10]}
    return parts, stats, zs
