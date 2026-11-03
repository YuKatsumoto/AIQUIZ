"""サムネイルのタイトルロゴを、絵の上でマウスで動かして決める道具（LogoTuner.cmd から開く）。

  python docs/pv/thumbnail/logo_tuner.py [名前]      # 名前は書き出す絵（t8_blender・t8・t5_blender など。既定 t8_blender）

ロゴを重ねる前の絵（final/_base/<名前>.png。finish.py・compose.py が仕上げるたびに残す）にロゴを重ねて見せる。
  左ドラッグ：動かす（上下の真ん中の近くでは真ん中に吸い付く。Shift を押しながらだと吸い付かない）
  ホイール：大きさ（Shift でこまかく）　矢印キー：1 px 動かす（Shift で 10 px）
  つまみ：ロゴの下の暗さ・ぼかし・効く範囲　G：ガイド（三分割と真ん中）　S：小さく表示（384 px）
  保存（Ctrl+S）：logo_layout.json に書き、final/<名前>.png・.jpg を書き直す　R：開いたときの値に戻す
"""
import json
import sys
import tkinter as tk
from pathlib import Path

from PIL import Image, ImageFilter, ImageTk

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finish as F  # noqa: E402

SCALE = 2 / 3                     # 画面に出す大きさ（1920×1080 → 1280×720）
SNAP = 12                         # 上下の真ん中に吸い付く範囲（px、本番の絵で）
SMALL_W = 384                     # 小さく表示するときの幅


class Tuner:
    def __init__(self, name: str):
        self.name = name
        base = F.OUT / "_base" / f"{name}.png"
        if not base.exists():
            raise SystemExit(f"{base} がありません。先に仕上げ（finish.py か compose.py の final）を一度動かしてください。")
        self.base = Image.open(base).convert("RGB")
        meta = F.OUT / "_base" / f"{name}.json"
        self.sharpen = tuple(json.loads(meta.read_text(encoding="utf-8"))["sharpen"]) if meta.exists() else F.SHARPEN
        self.logo_src = Image.open(F.LOGO).convert("RGBA")
        cfg = F.config(name)
        self.start = {"logo_x": cfg.get("logo_x", F.LOGO_X), "logo_w": cfg.get("logo_w", F.LOGO_W), "logo_y": cfg.get("logo_y"),
                      "zone_blur": cfg["zone_blur"], "zone_shade": cfg["zone_shade"], "zone_end": cfg["zone_end"]}
        self.cfg = dict(cfg)
        self.v = dict(self.start)
        if self.v["logo_y"] is None:
            self.v["logo_y"] = (F.H - self._logo_h(self.v["logo_w"])) // 2
        self.guides = True
        self.small = False
        self.drag = None

        self.root = tk.Tk()
        self.root.title(f"ロゴの調整 — {name}")
        self.cw, self.ch = round(F.W * SCALE), round(F.H * SCALE)
        self.canvas = tk.Canvas(self.root, width=self.cw, height=self.ch, highlightthickness=0, bg="#222")
        self.canvas.grid(row=0, column=0, columnspan=4)
        self.bg_item = self.canvas.create_image(0, 0, anchor="nw")
        self.logo_item = self.canvas.create_image(0, 0, anchor="nw")
        self.small_item = self.canvas.create_image(self.cw - 8, 8, anchor="ne")

        self.sliders = {}
        for col, (key, label, lo, hi, step) in enumerate((
                ("zone_shade", "ロゴの下の暗さ", 0.0, 0.4, 0.01),
                ("zone_blur", "ロゴの下のぼかし（px）", 0.0, 12.0, 0.5),
                ("zone_end", "暗さが消える位置（画面の幅の割合）", 0.2, 0.8, 0.01))):
            s = tk.Scale(self.root, label=label, from_=lo, to=hi, resolution=step, orient="horizontal", length=360,
                         command=lambda val, k=key: self._zone(k, float(val)))
            s.set(self.v[key])
            s.grid(row=1, column=col, padx=6, sticky="w")
            self.sliders[key] = s
        btns = tk.Frame(self.root)
        btns.grid(row=1, column=3, padx=6, sticky="e")
        tk.Button(btns, text="上下の真ん中", command=self.center).pack(fill="x")
        tk.Button(btns, text="元に戻す（R）", command=self.reset).pack(fill="x")
        tk.Button(btns, text="保存して書き出す（Ctrl+S）", command=self.save).pack(fill="x")
        self.status = tk.Label(self.root, anchor="w", font=("Yu Gothic UI", 10))
        self.status.grid(row=2, column=0, columnspan=4, sticky="we", padx=6, pady=4)

        c = self.canvas
        c.bind("<ButtonPress-1>", self._press)
        c.bind("<B1-Motion>", self._move)
        c.bind("<ButtonRelease-1>", lambda e: setattr(self, "drag", None))
        c.bind("<MouseWheel>", self._wheel)
        r = self.root
        for key, d in (("Left", (-1, 0)), ("Right", (1, 0)), ("Up", (0, -1)), ("Down", (0, 1))):
            r.bind(f"<{key}>", lambda e, d=d: self.nudge(*d, 1))
            r.bind(f"<Shift-{key}>", lambda e, d=d: self.nudge(*d, 10))
        r.bind("<g>", lambda e: self._toggle("guides"))
        r.bind("<s>", lambda e: self._toggle("small"))
        r.bind("<r>", lambda e: self.reset())
        r.bind("<Control-s>", lambda e: self.save())

        self._render_bg()
        self._render_logo()

    # ---------------------------------------------------------------- 描く

    def _logo_h(self, w: int) -> int:
        return round(self.logo_src.height * w / self.logo_src.width)

    def _sprite(self, w: int, scale: float) -> Image.Image:
        """ロゴと影（finish.put_logo と同じ：影は左上から (6, 12) ずらし、ぼかし 16、濃さ 170 まで）を 1 枚に"""
        logo = self.logo_src.resize((w, self._logo_h(w)), Image.LANCZOS)
        pad = 48
        sp = Image.new("RGBA", (w + pad * 2, logo.height + pad * 2), (0, 0, 0, 0))
        shadow = Image.new("RGBA", sp.size, (10, 18, 40, 0))
        a = Image.new("L", sp.size, 0)
        a.paste(logo.getchannel("A").point(lambda v: min(v, 170)), (pad + 6, pad + 12))
        shadow.putalpha(a.filter(ImageFilter.GaussianBlur(16)))
        sp.alpha_composite(shadow)
        sp.alpha_composite(logo, (pad, pad))
        self.pad = pad
        return sp.resize((round(sp.width * scale), round(sp.height * scale)), Image.LANCZOS)

    def _render_bg(self):
        im = F.calm_title_zone(self.base, self.v["zone_blur"], self.v["zone_shade"], self.v["zone_end"])
        self.zoned = im
        self.bg_photo = ImageTk.PhotoImage(im.resize((self.cw, self.ch), Image.LANCZOS))
        self.canvas.itemconfigure(self.bg_item, image=self.bg_photo)
        self._render_small()

    def _render_logo(self):
        self.sprite = self._sprite(self.v["logo_w"], SCALE)
        self.logo_photo = ImageTk.PhotoImage(self.sprite)
        self.canvas.itemconfigure(self.logo_item, image=self.logo_photo)
        self._place()
        self._render_small()

    def _place(self):
        x = (self.v["logo_x"] - self.pad) * SCALE
        y = (self.v["logo_y"] - self.pad) * SCALE
        self.canvas.coords(self.logo_item, x, y)
        self._draw_guides()
        self._show_status()

    def _draw_guides(self):
        c = self.canvas
        c.delete("guide")
        if not self.guides:
            return
        for k in (1, 2):
            c.create_line(self.cw * k / 3, 0, self.cw * k / 3, self.ch, fill="#ffffff", dash=(4, 6), tags="guide")
            c.create_line(0, self.ch * k / 3, self.cw, self.ch * k / 3, fill="#ffffff", dash=(4, 6), tags="guide")
        c.create_line(0, self.ch / 2, self.cw, self.ch / 2, fill="#ffd400", dash=(2, 4), tags="guide")
        ze = self.v["zone_end"] * self.cw
        c.create_line(ze, 0, ze, self.ch, fill="#ff6a00", dash=(6, 4), tags="guide")
        c.tag_raise(self.small_item)

    def _render_small(self):
        if not self.small:
            self.canvas.itemconfigure(self.small_item, image="")
            return
        im = F.put_logo(self.zoned, self.v["logo_x"], self.v["logo_w"], self.v["logo_y"])
        im = im.resize((SMALL_W, round(SMALL_W * F.H / F.W)), Image.LANCZOS)
        self.small_photo = ImageTk.PhotoImage(im)
        self.canvas.itemconfigure(self.small_item, image=self.small_photo)
        self.canvas.tag_raise(self.small_item)

    def _show_status(self):
        v = self.v
        h = self._logo_h(v["logo_w"])
        centered = v["logo_y"] == (F.H - h) // 2
        self.status.configure(text=(
            f"x {v['logo_x']}  y {v['logo_y']}{'（上下の真ん中）' if centered else ''}  幅 {v['logo_w']}（高さ {h}）  "
            f"右端 {v['logo_x'] + v['logo_w']}（画面の {100 * (v['logo_x'] + v['logo_w']) / F.W:.0f}%）   "
            "ドラッグ：動かす　ホイール：大きさ　矢印：1px　G：ガイド　S：小さく表示"))

    # ---------------------------------------------------------------- 操作

    def _press(self, e):
        self.drag = (e.x, e.y, self.v["logo_x"], self.v["logo_y"])

    def _move(self, e):
        if self.drag is None:
            return
        x0, y0, lx, ly = self.drag
        self.v["logo_x"] = round(lx + (e.x - x0) / SCALE)
        y = round(ly + (e.y - y0) / SCALE)
        mid = (F.H - self._logo_h(self.v["logo_w"])) // 2
        if not (e.state & 0x1) and abs(y - mid) <= SNAP:
            y = mid
        self.v["logo_y"] = y
        self._place()

    def _wheel(self, e):
        step = 4 if (e.state & 0x1) else 20
        old_w, old_h = self.v["logo_w"], self._logo_h(self.v["logo_w"])
        w = max(200, min(1600, old_w + (step if e.delta > 0 else -step)))
        # ロゴの真ん中を動かさずに大きさを変える
        cx, cy = self.v["logo_x"] + old_w / 2, self.v["logo_y"] + old_h / 2
        self.v["logo_w"] = w
        self.v["logo_x"] = round(cx - w / 2)
        self.v["logo_y"] = round(cy - self._logo_h(w) / 2)
        self._render_logo()

    def nudge(self, dx, dy, n):
        self.v["logo_x"] += dx * n
        self.v["logo_y"] += dy * n
        self._place()
        self._render_small()

    def center(self):
        self.v["logo_y"] = (F.H - self._logo_h(self.v["logo_w"])) // 2
        self._place()
        self._render_small()

    def _zone(self, key, val):
        if abs(self.v[key] - val) < 1e-9:
            return
        self.v[key] = val
        self._render_bg()
        self._draw_guides()

    def _toggle(self, what):
        setattr(self, what, not getattr(self, what))
        self._draw_guides() if what == "guides" else self._render_small()

    def reset(self):
        self.v = dict(self.start)
        if self.v["logo_y"] is None:
            self.v["logo_y"] = (F.H - self._logo_h(self.v["logo_w"])) // 2
        for k, s in self.sliders.items():
            s.set(self.v[k])
        self._render_bg()
        self._render_logo()

    def save(self):
        v = self.v
        out = {"logo_x": v["logo_x"], "logo_w": v["logo_w"], "zone_blur": v["zone_blur"],
               "zone_shade": round(v["zone_shade"], 3), "zone_end": round(v["zone_end"], 3)}
        if v["logo_y"] != (F.H - self._logo_h(v["logo_w"])) // 2:
            out["logo_y"] = v["logo_y"]              # 上下の真ん中なら書かない（大きさを変えても真ん中のまま）
        data = json.loads(F.LAYOUT.read_text(encoding="utf-8")) if F.LAYOUT.exists() else {}
        data[self.name] = out
        F.LAYOUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        im = F.finalize(self.base, F.config(self.name), self.sharpen)
        dst = F.OUT / f"{self.name}.jpg"
        im.save(F.OUT / f"{self.name}.png")
        im.save(dst, quality=95 if self.name.endswith("_blender") else 93, optimize=True, subsampling=0)
        self.status.configure(text=f"保存しました：{F.LAYOUT.name} と final/{self.name}.png・.jpg（{dst.stat().st_size / 1024:.0f} KB）")

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    Tuner(sys.argv[1] if len(sys.argv) > 1 else "t8_blender").run()
