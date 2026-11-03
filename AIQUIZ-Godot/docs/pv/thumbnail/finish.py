"""応募用サムネイルの仕上げ（実機の撮影から）。

撮影は tests/pv_capture/pv_thumb_runtime.gd（sub=8・PNG。各フレームの最後の 4 回 = シャッター 180° が保存される）。
そのうち最後の shutter 回を重ねて動きのブレを付け、色を整え、左の真ん中にタイトルロゴを重ねて
final/<shot>.jpg（1920x1080・2MB 以下）に書き出す。
4 回を重ねると、カメラと逆に動くもの（t2 の壁の「56」）が 4 重に見えるので、t2 は 1 回（止めた絵）、t3 は 2 回にした。

  python docs/pv/thumbnail/finish.py sheet          # 撮れたコマを全部重ねて並べる（コマ選び用）→ final/_frames_<shot>.jpg
  python docs/pv/thumbnail/finish.py                # SHOTS の frame で仕上げる → final/<shot>.jpg と final/_final.jpg
  python docs/pv/thumbnail/finish.py t2=58 t3=50    # コマを指定して仕上げる

ロゴの位置・大きさとロゴの下の暗さは、logo_layout.json（ロゴの調整の道具 logo_tuner.py で書く）があればその値を使う。
仕上げるたびに、ロゴを重ねる前の絵を final/_base/<名前>.png に残す（道具はこれにロゴを重ねて見せる）。
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAPTURE = ROOT / "artifacts/pv_capture"
OUT = HERE / "final"
LOGO = ROOT / "docs/pv/frames/logo_testopia.png"
FONT = "C:/Windows/Fonts/NotoSansJP-VF.ttf"

W, H = 1920, 1080
NAVY = (27, 42, 74)
LOGO_X = 70
LOGO_W = 820

# frame：使うコマ。shutter：重ねる回数（1〜4）。zone_blur：ロゴの下（左側）の背景をぼかす強さ（px）。
# zone_shade：同じ範囲を暗くする割合。zone_end：ぼかしが消える横の位置（画面の幅に対する割合）
SHOTS = {
    "t2": {"frame": 65, "shutter": 1, "zone_blur": 3, "zone_shade": 0.05, "zone_end": 0.55},
    "t3": {"frame": 48, "shutter": 2, "zone_blur": 9, "zone_shade": 0.12, "zone_end": 0.49},
    # t5：ロゴの下は手前の壁の無地。白い文字が明るい灰色に沈まないよう少し暗くする（ぼかしはほとんど要らない）。
    # 青い扉の入り口が画面の 0.42 から始まるので、ロゴを一回り小さくしてその手前で止める
    "t5": {"frame": 63, "shutter": 1, "zone_blur": 2, "zone_shade": 0.12, "zone_end": 0.48, "logo_x": 56, "logo_w": 740},
    # t7（gen/t2_side.png の再現。Blender 版だけ）：ロゴの下は空と海（もうぼけている）。P1 のうしろの土ぼこりが画面の 0.42 から
    # 始まるので、ロゴを小さめにしてその手前で止める。白い文字が明るい空に沈まないよう少しだけ暗くする
    "t7": {"frame": 71, "shutter": 1, "zone_blur": 0, "zone_shade": 0.08, "zone_end": 0.42, "logo_x": 60, "logo_w": 700,
           "blender_only": True},
    # t8（gen_v2/a_shoulder.png の肩タックル。演出の値は t8/stage.json）：ロゴの下は空と線路（もうぼけている）。
    # 白い文字が明るい空に沈まないよう少しだけ暗くする。手前の破片が画面の 0.45 あたりから入るので、その手前で止める
    "t8": {"frame": 76, "shutter": 1, "zone_blur": 0, "zone_shade": 0.08, "zone_end": 0.45, "logo_x": 56, "logo_w": 740},
}
# ロゴの調整の道具（logo_tuner.py）で決めた値。名前は書き出す絵の名前（t8・t8_blender など）。
# logo_x・logo_y（ロゴの左上、px。logo_y が無ければ上下の真ん中）・logo_w・zone_blur・zone_shade・zone_end を上書きする
LAYOUT = HERE / "logo_layout.json"
LAYOUT_KEYS = ("logo_x", "logo_y", "logo_w", "zone_blur", "zone_shade", "zone_end")
SHARPEN = (1.2, 40, 3)            # 輪郭の強調（半径・強さ・しきい値）


def config(name: str) -> dict:
    """書き出す絵の名前（t8 や t8_blender）の設定：SHOTS のそのショットの値に、logo_layout.json の値を重ねたもの"""
    cfg = dict(SHOTS[name.split("_")[0]])
    if LAYOUT.exists():
        cfg.update({k: v for k, v in json.loads(LAYOUT.read_text(encoding="utf-8")).get(name, {}).items() if k in LAYOUT_KEYS})
    return cfg


def merged(shot: str, n: int, shutter: int = 4) -> Image.Image:
    parts = sorted((CAPTURE / f"thumb_{shot}_sub8").glob(f"pv_{n:04d}_*.png"))[-shutter:]
    if not parts:
        raise FileNotFoundError(f"thumb_{shot}_sub8/pv_{n:04d}_*.png")
    acc = None
    for p in parts:
        a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
        acc = a if acc is None else acc + a
    return Image.fromarray(np.clip(acc / len(parts) + 0.5, 0, 255).astype(np.uint8))


def frames_of(shot: str) -> list[int]:
    return sorted({int(p.name[3:7]) for p in (CAPTURE / f"thumb_{shot}_sub8").glob("pv_*_*.png")})


def grade(im: Image.Image) -> Image.Image:
    """少しだけ締めて、色をのせる（ゲームの色から離れすぎない）"""
    im = ImageEnhance.Contrast(im).enhance(1.07)
    im = ImageEnhance.Color(im).enhance(1.12)
    a = np.asarray(im, dtype=np.float32) / 255.0
    # 明るいところをほんの少し暖かく、暗いところを紺へ
    lum = a.mean(axis=2, keepdims=True)
    a += (lum ** 2) * np.array([0.020, 0.008, -0.012]) + ((1 - lum) ** 2) * np.array([-0.010, -0.002, 0.018])
    # 周辺減光（四隅で約 14%）
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / np.sqrt(2)
    a *= (1.0 - 0.14 * np.clip((r - 0.45) / 0.55, 0, 1) ** 1.6)[..., None]
    return Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))


def calm_title_zone(im: Image.Image, blur: float, shade: float, end: float) -> Image.Image:
    """ロゴの下になる左側だけ、背景をぼかして少し暗くする（end − 0.13 まで効き、end で消える）"""
    if blur <= 0 and shade <= 0:
        return im
    x = np.arange(W, dtype=np.float32) / W
    m = np.clip((end - x) / 0.13, 0, 1)
    m = m * m * (3 - 2 * m)
    mask = np.repeat(m[None, :], H, axis=0)
    soft = im.filter(ImageFilter.GaussianBlur(blur)) if blur > 0 else im
    a = np.asarray(im, dtype=np.float32)
    b = np.asarray(soft, dtype=np.float32) * (1.0 - shade)
    out = a * (1 - mask[..., None]) + b * mask[..., None]
    return Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))


def put_logo(im: Image.Image, x: int = LOGO_X, width: int = LOGO_W, y: int | None = None) -> Image.Image:
    """ロゴ（幅 width、左上 (x, y)。y が None なら上下の真ん中）を影つきで重ねる"""
    base = im.convert("RGBA")
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.resize((width, round(logo.height * width / logo.width)), Image.LANCZOS)
    fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fg.alpha_composite(logo, (x, (H - logo.height) // 2 if y is None else y))
    shadow = Image.new("RGBA", (W, H), (10, 18, 40, 0))
    shadow.putalpha(fg.getchannel("A").point(lambda a: min(a, 170)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    base.alpha_composite(shadow, (6, 12))
    base.alpha_composite(fg)
    return base.convert("RGB")


def save_base(im: Image.Image, name: str, sharpen: tuple = SHARPEN) -> None:
    """ロゴを重ねる前（色を整えたあと）の絵と輪郭の強調の値を final/_base に残す（logo_tuner.py が読む）"""
    (OUT / "_base").mkdir(parents=True, exist_ok=True)
    im.save(OUT / "_base" / f"{name}.png")
    (OUT / "_base" / f"{name}.json").write_text(json.dumps({"sharpen": list(sharpen)}), encoding="utf-8")


def finalize(im: Image.Image, cfg: dict, sharpen: tuple = SHARPEN) -> Image.Image:
    """色を整えた絵に、ロゴの下を落ち着かせ、輪郭を締め、ロゴを重ねる"""
    im = calm_title_zone(im, cfg["zone_blur"], cfg["zone_shade"], cfg["zone_end"])
    im = im.filter(ImageFilter.UnsharpMask(radius=sharpen[0], percent=sharpen[1], threshold=sharpen[2]))
    return put_logo(im, cfg.get("logo_x", LOGO_X), cfg.get("logo_w", LOGO_W), cfg.get("logo_y"))


def finish(shot: str, n: int) -> Path:
    cfg = config(shot)
    im = merged(shot, n, cfg["shutter"])
    im = grade(im)
    save_base(im, shot)
    im = finalize(im, cfg)
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{shot}.jpg"
    im.save(dst, quality=93, optimize=True, subsampling=0)
    im.save(OUT / f"{shot}.png")
    print(f"{dst.relative_to(ROOT)}  frame {n}  {dst.stat().st_size / 1024:.0f} KB")
    return dst


def label_font(size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(FONT, size)
    font.set_variation_by_name("Bold")
    return font


def sheet(shot: str) -> None:
    frames = frames_of(shot)
    cols, tw = 4, 640
    th = tw * H // W
    rows = (len(frames) + cols - 1) // cols
    img = Image.new("RGB", (cols * tw, rows * th), (0, 0, 0))
    d = ImageDraw.Draw(img)
    font = label_font(26)
    for i, n in enumerate(frames):
        x, y = (i % cols) * tw, (i // cols) * th
        img.paste(merged(shot, n).resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x + 10, y + 6), str(n), font=font, fill=(255, 230, 0), stroke_width=3, stroke_fill=(0, 0, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"_frames_{shot}.jpg"
    img.save(dst, quality=88)
    print(dst.relative_to(ROOT))


def side_by_side(paths: list[Path], dst: Path) -> None:
    tw = 960
    th = tw * H // W
    pad, label_h = 16, 44
    img = Image.new("RGB", (len(paths) * (tw + pad) + pad, th + label_h + pad * 2), (245, 245, 242))
    d = ImageDraw.Draw(img)
    font = label_font(26)
    for i, p in enumerate(paths):
        x = pad + i * (tw + pad)
        img.paste(Image.open(p).resize((tw, th), Image.LANCZOS), (x, pad + label_h))
        d.text((x, pad + 4), p.stem, font=font, fill=NAVY)
    img.save(dst, quality=88)
    print(dst.relative_to(ROOT))


def main() -> None:
    args = sys.argv[1:]
    # blender_only のショットはゲーム内撮影版がない（仕上げは blender/compose.py の final から同じ設定で）
    if args[:1] == ["sheet"]:
        for shot, cfg in SHOTS.items():
            if not cfg.get("blender_only"):
                sheet(shot)
        return
    picks = {shot: cfg["frame"] for shot, cfg in SHOTS.items() if not cfg.get("blender_only")}
    for a in args:
        shot, _, n = a.partition("=")
        picks[shot] = int(n)
    done = [finish(shot, n) for shot, n in picks.items()]
    side_by_side(done, OUT / "_final.jpg")


if __name__ == "__main__":
    main()
