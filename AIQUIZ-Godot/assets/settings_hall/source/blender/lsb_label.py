"""印刷物の画像（ラベル・表紙・時計の文字盤・定規の目盛り）を GPU のオフスクリーンに描いて PNG にする。

ライブ Blender の UI のある GPU コンテキストで動く（blf で Noto Sans JP、gpu の UNIFORM_COLOR で図形）。
座標はピクセル（左下が原点、y は上向き）。2 倍で描いて縮めてなめらかにする。
    c = Canvas("chalk_box_front", 1024, 512, bg=(1, 1, 1, 1))
    c.rect(0, 0, 1024, 120, "#C62828"); c.text(512, 300, "ダストレスチョーク", 96, "#1A1A1A", align="center")
    path = c.save()
出力は source/labels/<name>.png（source は .gdignore なので Godot は読まない。GLB には焼いた画像だけが入る）。
"""
from __future__ import annotations

import math
from pathlib import Path

import blf
import bpy
import gpu
import numpy as np
from gpu_extras.batch import batch_for_shader
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
LABELS = HERE.parent / "labels"
FONTS = HERE.parents[3] / "resources" / "fonts"
FONT_FILES = {
    "bold": "NotoSansJP-Bold.otf",
    "semibold": "NotoSansJP-SemiBold.otf",
    "medium": "NotoSansJP-Medium.otf",
    "regular": "NotoSansJP-Regular.otf",
}
_FONT_IDS: dict[str, int] = {}
SS = 2


def _font(weight: str) -> int:
    fid = _FONT_IDS.get(weight)
    if fid is None or fid < 0:
        fid = blf.load(str(FONTS / FONT_FILES[weight]))
        _FONT_IDS[weight] = fid
    return fid


def color(c):
    """'#RRGGBB'（sRGB）か (r, g, b[, a])。画像は sRGB のまま書く（読み込み側で sRGB として扱う）。"""
    if isinstance(c, str):
        c = c.lstrip("#")
        rgb = [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
        a = int(c[6:8], 16) / 255.0 if len(c) == 8 else 1.0
        return (rgb[0], rgb[1], rgb[2], a)
    return tuple(c) if len(c) == 4 else (c[0], c[1], c[2], 1.0)


class Canvas:
    def __init__(self, name: str, width: int, height: int, bg=(0.0, 0.0, 0.0, 0.0)):
        self.name = name
        self.w = width
        self.h = height
        self.bg = color(bg)
        self.ops: list = []

    # 描画の命令をためておき、save() でまとめて GPU に描く（bind の中で Python の例外を出さないため）
    def rect(self, x, y, w, h, c, angle_deg=0.0, cx=None, cy=None):
        pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
        if angle_deg:
            ox = x + w * 0.5 if cx is None else cx
            oy = y + h * 0.5 if cy is None else cy
            a = math.radians(angle_deg)
            ca, sa = math.cos(a), math.sin(a)
            pts = [(ox + (px - ox) * ca - (py - oy) * sa, oy + (px - ox) * sa + (py - oy) * ca) for px, py in pts]
        self.poly(pts, c)

    def poly(self, pts, c):
        """凸多角形（扇で三角形に分ける）。"""
        tris = []
        for i in range(1, len(pts) - 1):
            tris += [pts[0], pts[i], pts[i + 1]]
        self.ops.append(("tris", tris, color(c)))

    def line(self, x0, y0, x1, y1, width, c):
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length * width * 0.5, dx / length * width * 0.5
        self.poly([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], c)

    def circle(self, cx, cy, r, c, segments=96):
        pts = [(cx + r * math.cos(math.tau * i / segments), cy + r * math.sin(math.tau * i / segments))
               for i in range(segments)]
        self.poly(pts, c)

    def ring(self, cx, cy, r0, r1, c, segments=128, a0=0.0, a1=math.tau):
        tris = []
        for i in range(segments):
            t0 = a0 + (a1 - a0) * i / segments
            t1 = a0 + (a1 - a0) * (i + 1) / segments
            p00 = (cx + r0 * math.cos(t0), cy + r0 * math.sin(t0))
            p01 = (cx + r1 * math.cos(t0), cy + r1 * math.sin(t0))
            p10 = (cx + r0 * math.cos(t1), cy + r0 * math.sin(t1))
            p11 = (cx + r1 * math.cos(t1), cy + r1 * math.sin(t1))
            tris += [p00, p01, p11, p00, p11, p10]
        self.ops.append(("tris", tris, color(c)))

    def text(self, x, y, s, size, c, weight="bold", align="left", angle_deg=0.0, valign="baseline"):
        self.ops.append(("text", (x, y, s, size, color(c), weight, align, angle_deg, valign)))

    # --- render
    def _draw(self, W, H):
        sh = gpu.shader.from_builtin("UNIFORM_COLOR")
        proj = Matrix(((2.0 / W, 0, 0, -1), (0, 2.0 / H, 0, -1), (0, 0, 1, 0), (0, 0, 0, 1)))
        gpu.matrix.load_matrix(Matrix.Identity(4))
        gpu.matrix.load_projection_matrix(proj)
        gpu.state.blend_set("ALPHA")
        for op in self.ops:
            if op[0] == "tris":
                pts = [(px * SS, py * SS) for px, py in op[1]]
                batch = batch_for_shader(sh, "TRIS", {"pos": pts})
                sh.uniform_float("color", op[2])
                batch.draw(sh)
            else:
                x, y, s, size, col, weight, align, angle, valign = op[1]
                fid = _font(weight)
                blf.size(fid, size * SS)
                blf.color(fid, *col)
                tw, th = blf.dimensions(fid, s)
                ox = {"left": 0.0, "center": -tw * 0.5, "right": -tw}[align]
                oy = {"baseline": 0.0, "center": -th * 0.42, "top": -th}[valign]
                if angle:
                    blf.enable(fid, blf.ROTATION)
                    a = math.radians(angle)
                    blf.rotation(fid, a)
                    rx = ox * math.cos(a) - oy * math.sin(a)
                    ry = ox * math.sin(a) + oy * math.cos(a)
                    blf.position(fid, x * SS + rx, y * SS + ry, 0)
                else:
                    blf.disable(fid, blf.ROTATION)
                    blf.position(fid, x * SS + ox, y * SS + oy, 0)
                blf.draw(fid, s)
                blf.disable(fid, blf.ROTATION)

    def pixels(self) -> np.ndarray:
        W, H = self.w * SS, self.h * SS
        off = gpu.types.GPUOffScreen(W, H)
        try:
            with off.bind():
                fb = gpu.state.active_framebuffer_get()
                fb.clear(color=self.bg)
                with gpu.matrix.push_pop():
                    with gpu.matrix.push_pop_projection():
                        self._draw(W, H)
                buf = fb.read_color(0, 0, W, H, 4, 0, "FLOAT")
        finally:
            off.free()
        arr = np.array(buf.to_list(), dtype=np.float32).reshape(H, W, 4)
        # 2×2 の平均で縮める（アルファで重みを付けて縁の色がにじまないように）
        a = arr[:, :, 3:4]
        prem = arr[:, :, :3] * a
        prem = prem.reshape(self.h, SS, self.w, SS, 3).mean(axis=(1, 3))
        a = a.reshape(self.h, SS, self.w, SS, 1).mean(axis=(1, 3))
        rgb = np.where(a > 1e-5, prem / np.maximum(a, 1e-5), arr[::SS, ::SS, :3])
        return np.concatenate([rgb, a], axis=2).clip(0.0, 1.0)

    def save(self) -> str:
        arr = self.pixels()
        LABELS.mkdir(parents=True, exist_ok=True)
        path = LABELS / f"{self.name}.png"
        save_png(arr, path, self.name)
        return str(path)


def save_png(arr: np.ndarray, path: Path, name: str = "LSL_tmp") -> str:
    h, w = arr.shape[:2]
    img = bpy.data.images.get("LSL_" + name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new("LSL_" + name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    return str(path)
