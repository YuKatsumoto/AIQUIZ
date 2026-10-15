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

import math

from hb_common import BP, SPEC, GMesh, body_params, section_point

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


def ring_thetas(z):
    """左半分の 22 個の角度と、目印ごとの「その断面にある」フラグ。"""
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


def classify(z0, z1, r, def0, def1):
    """四角の (部品, 材質)。部品は Body / Windows / Door_L / Door_R、None は穴。"""
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
    if seg == 3 and stripe_ok:
        return part, "Trim"
    return part, "BodyPaint"


def build_shell():
    """外板・内張り・縁を部品ごとの GMesh で返す。"""
    zs = stations()
    outer, defs = [], []
    for z in zs:
        ring, defined = full_ring(z)
        outer.append(ring)
        defs.append(defined)
    inner = {}
    for k, z in enumerate(zs):
        if CABIN_Z0 - 1e-6 <= z <= CABIN_Z1 + 1e-6:
            inner[k] = full_ring(z, WALL)[0]
    parts: dict[str, GMesh] = {}

    def mesh(name):
        return parts.setdefault(name, GMesh())

    cell = {}   # (k, r) → (部品, 材質, 内張りあり)
    for k in range(len(zs) - 1):
        for r in range(RING):
            part, mat = classify(zs[k], zs[k + 1], r, defs[k], defs[k + 1])
            if part is None:
                cell[(k, r)] = (None, None, False)
                continue
            j = (r + 1) % RING
            quad = [outer[k][r], outer[k][j], outer[k + 1][j], outer[k + 1][r]]
            mesh(part).face(quad, mat, smooth=True, weld=f"{part}:outer")
            lined = (mat != "Windows" and k in inner and (k + 1) in inner
                     and max(outer[k][r][1], outer[k][j][1], outer[k + 1][j][1], outer[k + 1][r][1]) > FLOOR_Y + 0.02)
            if lined:
                iq = [inner[k][r], inner[k][j], inner[k + 1][j], inner[k + 1][r]]
                mesh(part).face(list(reversed(iq)), "Interior", smooth=True, weld=f"{part}:inner")
            cell[(k, r)] = (part, mat, lined)
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
        mat = "Trim" if (seg == 3 and stripe0) else "BodyPaint"
        mesh("Body").face([c, ring[j], ring[r]], mat, smooth=True, weld="Body:outer")
    ring = outer[-1]
    c = (0.0, sum(p[1] for p in ring) / len(ring), zs[-1])
    for r in range(RING):
        j = (r + 1) % RING
        mesh("Body")._oriented([c, ring[r], ring[j]], (0, 0, 1), "BodyPaint")
    stats = {"stations": len(zs), "ring": RING, "rims": rims, "z_first": zs[0], "z_last": zs[-1]}
    return parts, stats, zs
