"""黒板面に焼き付けるチョークの画像（RGBA、アルファ = チョークの濃さ）を numpy で描く。

座標は黒板の面の上のメートル（u = 見る人から見て左端から右へ、v = 下端から上へ）。
- stroke(): 手描きの線。点列を低い周波数でゆらし、筆圧（線の途中の濃さ）と黒板の凹凸によるかすれ
  （細かい粒の閾値）を掛ける。始まりと終わりは少し濃く（チョークを押し当てた跡）。
- smear(): 黒板消しで拭いた跡のもや（横長の帯、拭いた向きの筋）。
- dust(): 下端のチョーク受けの上に積もった粉のもや。
Godot の黒板のキャンバス（第 3 段階）でも同じ考え方で描く。
"""
from __future__ import annotations

import math

import numpy as np

CHALK = {
    "white": (0.93, 0.93, 0.89),
    "yellow": (0.96, 0.86, 0.42),
    "red": (0.94, 0.52, 0.55),
    "blue": (0.55, 0.74, 0.95),
}


def _box_blur(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="wrap")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a: np.ndarray, r: int) -> np.ndarray:
    """ガウスに近いぼかし（箱を 3 回）。"""
    for _ in range(3):
        a = _box_blur(a, r, 0)
        a = _box_blur(a, r, 1)
    return a


def field(h: int, w: int, radius: int, rng: np.random.Generator) -> np.ndarray:
    """平均 0.5、だいたい 0..1 の滑らかな雑音。"""
    f = blur(rng.random((h, w), dtype=np.float32), radius)
    f -= f.mean()
    f /= max(1e-6, f.std() * 4.0)
    return (f + 0.5).astype(np.float32)


class Board:
    def __init__(self, width_m: float, height_m: float, px_per_m: float = 520.0, seed: int = 1):
        self.wm = width_m
        self.hm = height_m
        self.ppm = px_per_m
        self.W = int(round(width_m * px_per_m))
        self.H = int(round(height_m * px_per_m))
        self.rng = np.random.default_rng(seed)
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        # 黒板の凹凸: チョークは山にだけ乗る（細かい粒 1〜2 px と、少し大きい 6 px のむら）
        self.grain = 0.7 * field(self.H, self.W, 1, self.rng) + 0.3 * field(self.H, self.W, 3, self.rng)
        # 拭いた跡のもやの雲（大きなむら）
        self.cloud = field(self.H, self.W, 28, self.rng)

    # --- coordinates
    def px(self, u, v):
        return u * self.ppm, (self.hm - v) * self.ppm  # 画像の行は上から

    # --- strokes
    def _jitter(self, pts, amount, seed):
        rng = np.random.default_rng(seed)
        pts = np.asarray(pts, np.float64)
        if len(pts) < 2:
            return pts
        # 長さに沿って点を細かく取り直し、低い周波数でゆらす
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        total = seg.sum()
        n = max(2, int(total / 0.01))
        t = np.concatenate([[0.0], np.cumsum(seg)]) / max(total, 1e-9)
        s = np.linspace(0.0, 1.0, n)
        res = np.stack([np.interp(s, t, pts[:, 0]), np.interp(s, t, pts[:, 1])], axis=1)
        for k, amp in ((2.0, 1.0), (5.0, 0.45), (11.0, 0.2)):
            ph = rng.random(2) * math.tau
            res[:, 0] += amount * amp * np.sin(s * k * math.tau + ph[0])
            res[:, 1] += amount * amp * np.sin(s * k * math.tau + ph[1])
        return res

    def stroke(self, pts, width=0.022, chalk="white", pressure=1.0, jitter=0.004, seed=0, density=1.0):
        """pts: [(u, v), ...] メートル。width: 線の太さ（m）。"""
        pts = self._jitter(pts, jitter, seed)
        col = np.array(CHALK.get(chalk, chalk), np.float32)
        rng = np.random.default_rng(seed + 991)
        n = len(pts)
        # 筆圧: 長さに沿って 0.75〜1.0 でゆれ、始点と終点で少し強い
        s = np.linspace(0.0, 1.0, n)
        press = 0.85 + 0.15 * np.sin(s * math.tau * rng.uniform(1.5, 3.0) + rng.random() * 6.0)
        press += 0.12 * (np.exp(-s * 25.0) + np.exp(-(1.0 - s) * 25.0))
        press *= pressure
        r_px = width * self.ppm * 0.5
        P = np.array([self.px(u, v) for u, v in pts], np.float64)
        for i in range(n - 1):
            self._segment(P[i], P[i + 1], r_px, press[i], col, density)

    def _segment(self, p0, p1, r, press, col, density):
        x0 = int(max(0, math.floor(min(p0[0], p1[0]) - r - 2)))
        x1 = int(min(self.W, math.ceil(max(p0[0], p1[0]) + r + 2)))
        y0 = int(max(0, math.floor(min(p0[1], p1[1]) - r - 2)))
        y1 = int(min(self.H, math.ceil(max(p0[1], p1[1]) + r + 2)))
        if x1 <= x0 or y1 <= y0:
            return
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.asarray(p1, np.float32) - np.asarray(p0, np.float32)
        L2 = float(d @ d) or 1e-6
        t = np.clip(((xs - p0[0]) * d[0] + (ys - p0[1]) * d[1]) / L2, 0.0, 1.0)
        dx = xs - (p0[0] + t * d[0])
        dy = ys - (p0[1] + t * d[1])
        dist = np.sqrt(dx * dx + dy * dy)
        edge = np.clip((r - dist) / 1.2 + 0.5, 0.0, 1.0)
        # 線の縁ほどかすれる: 閾値が縁で上がる
        g = self.grain[y0:y1, x0:x1]
        thresh = 0.50 - 0.36 * press + 0.42 * np.clip(dist / max(r, 1e-6), 0.0, 1.0) ** 2.5
        cov = np.clip((g - thresh) / 0.10 + 0.5, 0.0, 1.0) * edge * density
        cov = np.clip(cov * (0.75 + 0.25 * press), 0.0, 1.0)
        a_old = self.a[y0:y1, x0:x1]
        a_new = np.maximum(a_old, cov)
        w = np.where(a_new > 1e-5, (cov - np.minimum(cov, a_old) * 0.0) / np.maximum(a_new, 1e-5), 0.0)
        w = np.clip(w, 0.0, 1.0)[..., None]
        self.rgb[y0:y1, x0:x1] = self.rgb[y0:y1, x0:x1] * (1.0 - w) + col * w
        self.a[y0:y1, x0:x1] = a_new

    def circle(self, cu, cv, r, width=0.02, chalk="white", seed=0, start=0.0, sweep=math.tau, pressure=1.0):
        n = max(12, int(abs(sweep) * r / 0.01))
        pts = [(cu + r * math.cos(start + sweep * i / n), cv + r * math.sin(start + sweep * i / n)) for i in range(n + 1)]
        self.stroke(pts, width, chalk, pressure, jitter=0.003 + r * 0.01, seed=seed)

    def arrow(self, u0, v0, u1, v1, width=0.018, chalk="white", head=0.06, both=False, seed=0):
        self.stroke([(u0, v0), (u1, v1)], width, chalk, seed=seed)
        ang = math.atan2(v1 - v0, u1 - u0)
        ends = [(u1, v1, ang)] + ([(u0, v0, ang + math.pi)] if both else [])
        for k, (eu, ev, a) in enumerate(ends):
            for s in (-1.0, 1.0):
                b = a + math.pi - s * 0.5
                self.stroke([(eu + head * math.cos(b), ev + head * math.sin(b)), (eu, ev)], width, chalk,
                            seed=seed + 10 + k * 2 + int(s > 0), jitter=0.002)

    # --- eraser ghosts and dust
    def smear(self, cu, cv, w, h, strength=0.06, chalk="white", seed=0, angle_deg=0.0):
        """黒板消しで拭いた跡: 中心 (cu, cv)、幅 w・高さ h（m）の横長の帯。拭いた向きの筋入り。"""
        rng = np.random.default_rng(seed + 5000)
        cx, cy = self.px(cu, cv)
        rw, rh = w * self.ppm * 0.5, h * self.ppm * 0.5
        R = int(max(rw, rh) + 8)
        x0, x1 = int(max(0, cx - R)), int(min(self.W, cx + R))
        y0, y1 = int(max(0, cy - R)), int(min(self.H, cy + R))
        if x1 <= x0 or y1 <= y0:
            return
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        a = math.radians(angle_deg)
        lx = (xs - cx) * math.cos(a) + (ys - cy) * math.sin(a)
        ly = -(xs - cx) * math.sin(a) + (ys - cy) * math.cos(a)
        e = np.clip(1.0 - np.sqrt((lx / max(rw, 1)) ** 2 + (ly / max(rh, 1)) ** 2), 0.0, 1.0) ** 0.7
        streak = blur(rng.random((y1 - y0, 1), dtype=np.float32).repeat(x1 - x0, axis=1), 4)
        streak = (streak - streak.mean()) / max(1e-6, streak.std()) * 0.12 + 1.0
        cloud = np.clip(self.cloud[y0:y1, x0:x1] * 1.6 - 0.3, 0.0, 1.5)
        cov = np.clip(e * strength * streak * cloud * (0.8 + 0.4 * self.grain[y0:y1, x0:x1]), 0.0, 1.0)
        self._over(y0, y1, x0, x1, cov, np.array(CHALK[chalk], np.float32))

    def dust(self, height_m=0.12, strength=0.12):
        rows = int(height_m * self.ppm)
        ramp = np.linspace(0.0, 1.0, rows, dtype=np.float32) ** 2.2
        cov = (ramp[:, None] * strength * (0.6 + 0.8 * self.grain[self.H - rows:, :])).clip(0.0, 1.0)
        self._over(self.H - rows, self.H, 0, self.W, cov, np.array(CHALK["white"], np.float32))

    def _over(self, y0, y1, x0, x1, cov, col):
        a_old = self.a[y0:y1, x0:x1]
        a_new = a_old + cov * (1.0 - a_old)
        w = np.where(a_new > 1e-5, cov * (1.0 - a_old) / np.maximum(a_new, 1e-5), 0.0)[..., None]
        self.rgb[y0:y1, x0:x1] = self.rgb[y0:y1, x0:x1] * (1.0 - w) + col * w
        self.a[y0:y1, x0:x1] = a_new

    def rgba(self) -> np.ndarray:
        """Blender の画像の画素順（下の行から）に並べた RGBA。色は sRGB（チョークの色の値をそのまま）。"""
        img = np.concatenate([self.rgb, self.a[..., None]], axis=2)
        return np.flipud(img).clip(0.0, 1.0)


# ------------------------------------------------------------------ the boards of the lecture set

def blade_lesson(b: Board, u0: float, v0: float, width: float, seed: int = 100):
    """連結チップソーの図: 刃の列（歯付きの円）、台車の線と端の支柱、間隔の矢印（黄）、回転の弧（赤）、
    跳び越える棒人間と放物線、注意の三角（黄）。u0, v0 は左下、width は図の幅（m）。"""
    pitch = width / 8.0
    r = pitch * 0.34
    base_v = v0 + 0.18
    blade_v = base_v + r + 0.05
    for k in range(8):
        cu = u0 + (k + 0.5) * pitch
        b.circle(cu, blade_v, r, 0.014, "white", seed=seed + k)
        teeth = 10
        for t in range(teeth):
            a0 = math.tau * t / teeth
            p0 = (cu + r * math.cos(a0), blade_v + r * math.sin(a0))
            p1 = (cu + (r + 0.022) * math.cos(a0 + 0.18), blade_v + (r + 0.022) * math.sin(a0 + 0.18))
            b.stroke([p0, p1], 0.010, "white", seed=seed + 40 + k * teeth + t, jitter=0.001, pressure=0.9)
        b.circle(cu, blade_v, 0.012, 0.014, "white", seed=seed + 200 + k)
    b.stroke([(u0 - 0.03, base_v), (u0 + width + 0.03, base_v)], 0.018, "white", seed=seed + 300)
    for cu in (u0 + pitch * 0.5, u0 + width - pitch * 0.5):
        b.stroke([(cu, base_v), (cu, base_v - 0.12)], 0.016, "white", seed=seed + 301 + int(cu * 100))
    b.arrow(u0 + pitch * 0.5, blade_v + r + 0.12, u0 + pitch * 1.5, blade_v + r + 0.12, 0.014, "yellow",
            head=0.04, both=True, seed=seed + 320)
    for cu in (u0 + pitch * 0.5, u0 + pitch * 1.5):
        b.stroke([(cu, blade_v + r + 0.05), (cu, blade_v + r + 0.19)], 0.010, "yellow", seed=seed + 330 + int(cu * 97))
    b.circle(u0 + width - pitch * 1.5, blade_v, r * 1.55, 0.014, "red", seed=seed + 340,
             start=math.radians(-40.0), sweep=math.radians(240.0))
    b.arrow(u0 + width - pitch * 1.5 + r * 1.55 * math.cos(math.radians(200.0)),
            blade_v + r * 1.55 * math.sin(math.radians(200.0)),
            u0 + width - pitch * 1.5 + r * 1.55 * math.cos(math.radians(205.0)),
            blade_v + r * 1.55 * math.sin(math.radians(205.0)) - 0.002, 0.014, "red", head=0.045, seed=seed + 345)
    # 放物線と棒人間（頂点で脚を抱える）
    cu = u0 + width * 0.5
    top = blade_v + r + 0.55
    arc = [(cu - 0.45 + 0.9 * i / 30.0, blade_v + r + 0.08 + (top - blade_v - r - 0.08) *
            (1.0 - ((i / 30.0 - 0.5) * 2.0) ** 2)) for i in range(31)]
    b.stroke(arc, 0.012, "white", pressure=0.8, seed=seed + 350, jitter=0.002)
    b.arrow(arc[-3][0], arc[-3][1], arc[-1][0], arc[-1][1], 0.012, "white", head=0.035, seed=seed + 351)
    hv = top + 0.1
    b.circle(cu, hv + 0.07, 0.05, 0.014, "white", seed=seed + 360)
    b.stroke([(cu, hv + 0.02), (cu + 0.01, hv - 0.12)], 0.014, "white", seed=seed + 361)
    b.stroke([(cu - 0.09, hv + 0.05), (cu, hv - 0.02), (cu + 0.09, hv + 0.06)], 0.012, "white", seed=seed + 362)
    b.stroke([(cu + 0.01, hv - 0.12), (cu - 0.05, hv - 0.06), (cu - 0.08, hv - 0.15)], 0.012, "white", seed=seed + 363)
    b.stroke([(cu + 0.01, hv - 0.12), (cu + 0.07, hv - 0.07), (cu + 0.05, hv - 0.17)], 0.012, "white", seed=seed + 364)
    # 注意の三角
    tu, tv, ts = u0 + width - 0.12, top + 0.08, 0.16
    tri = [(tu - ts * 0.5, tv - ts * 0.4), (tu + ts * 0.5, tv - ts * 0.4), (tu, tv + ts * 0.5), (tu - ts * 0.5, tv - ts * 0.4)]
    b.stroke(tri, 0.016, "yellow", seed=seed + 370, jitter=0.002)
    b.stroke([(tu, tv + ts * 0.22), (tu, tv - ts * 0.08)], 0.016, "yellow", seed=seed + 371, jitter=0.001)
    b.stroke([(tu, tv - ts * 0.2), (tu + 0.002, tv - ts * 0.23)], 0.02, "yellow", seed=seed + 372, jitter=0.0)


def ghosts(b: Board, seed: int, lines=5, area=(0.15, 0.25, 4.8, 1.4)):
    """前の授業の消し残し: 薄い文字の行（短い縦横の線のかたまり）を何行か書いてから、上から拭いたもや。"""
    rng = np.random.default_rng(seed)
    u0, v0, w, h = area
    for li in range(lines):
        v = v0 + h - (li + 0.5) * (h / lines)
        u = u0 + rng.uniform(0.0, 0.3)
        end = u0 + rng.uniform(0.5, 1.0) * w
        while u < end:
            gw = rng.uniform(0.09, 0.14)
            for _ in range(rng.integers(2, 5)):
                x0 = u + rng.uniform(0.0, gw)
                y0 = v + rng.uniform(-0.06, 0.06)
                if rng.random() < 0.5:
                    pts = [(x0, y0), (x0 + rng.uniform(0.03, 0.08), y0 + rng.uniform(-0.01, 0.01))]
                else:
                    pts = [(x0, y0 + 0.05), (x0 + rng.uniform(-0.02, 0.02), y0 - rng.uniform(0.02, 0.06))]
                # 拭いたあとの跡なので、本物の文字（Godot がその上に書く）と見分けがつくくらい薄く・ぼやけさせる
                b.stroke(pts, 0.02, "white", pressure=0.2, density=0.045, seed=int(rng.integers(1 << 30)), jitter=0.003)
            u += gw + rng.uniform(0.02, 0.05)
    for k in range(int(w / 0.5) + 2):
        b.smear(u0 + k * 0.5 + rng.uniform(-0.1, 0.1), v0 + h * 0.5 + rng.uniform(-0.2, 0.2), rng.uniform(0.6, 1.0),
                h * rng.uniform(0.6, 0.95), strength=rng.uniform(0.026, 0.045), seed=seed + k * 13,
                angle_deg=rng.uniform(-6.0, 6.0))
