"""サムネイル絵コンテの合成。

gen/<name>.png（Codex CLI の画像生成）を 1920x1080 に切り抜き、
左の真ん中にタイトルロゴだけを重ねて comp/<name>.jpg に書き出す。
最後に全案を並べた一覧 comp/_contact.jpg を作る。

  python docs/pv/thumbnail/compose.py            # gen/ にある全部
  python docs/pv/thumbnail/compose.py t1_headon  # 指定したものだけ
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
LOGO = ROOT / "docs/pv/frames/logo_testopia.png"
FONT = "C:/Windows/Fonts/NotoSansJP-VF.ttf"

W, H = 1920, 1080
NAVY = (27, 42, 74)

LOGO_X = 80
LOGO_W = 860


def fit_16x9(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    w, h = im.size
    if w / h > W / H:
        nw = round(h * W / H)
        im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = round(w * H / W)
        im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    return im.resize((W, H), Image.LANCZOS)


def compose(src: Path, dst: Path) -> None:
    base = fit_16x9(Image.open(src)).convert("RGBA")

    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.resize((LOGO_W, round(logo.height * LOGO_W / logo.width)), Image.LANCZOS)

    fg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fg.alpha_composite(logo, (LOGO_X, (H - logo.height) // 2))

    # 背景が明るくても読めるよう、ロゴの下にやわらかい影を敷く
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow.putalpha(fg.getchannel("A").point(lambda a: min(a, 150)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    base.alpha_composite(shadow, (6, 10))
    base.alpha_composite(fg)

    dst.parent.mkdir(parents=True, exist_ok=True)
    base.convert("RGB").save(dst, quality=90, optimize=True)
    print(f"{dst.relative_to(ROOT)}  {dst.stat().st_size / 1024:.0f} KB")


def contact(paths: list[Path], dst: Path) -> None:
    cols, tw = 2, 960
    th = tw * H // W
    rows = (len(paths) + cols - 1) // cols
    pad, label_h = 16, 44
    sheet = Image.new("RGB", (cols * (tw + pad) + pad, rows * (th + label_h + pad) + pad), (245, 245, 242))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 26)
    font.set_variation_by_name("Bold")
    for i, p in enumerate(paths):
        x = pad + (i % cols) * (tw + pad)
        y = pad + (i // cols) * (th + label_h + pad)
        sheet.paste(Image.open(p).resize((tw, th), Image.LANCZOS), (x, y + label_h))
        d.text((x, y + 6), p.stem, font=font, fill=NAVY)
    sheet.save(dst, quality=85, optimize=True)
    print(f"{dst.relative_to(ROOT)}")


def main() -> None:
    names = sys.argv[1:] or sorted(p.stem for p in (HERE / "gen").glob("*.png"))
    for n in names:
        compose(HERE / "gen" / f"{n}.png", HERE / "comp" / f"{n}.jpg")
    done = sorted(p for p in (HERE / "comp").glob("*.jpg") if not p.stem.startswith("_"))
    if done:
        contact(done, HERE / "comp" / "_contact.jpg")


if __name__ == "__main__":
    main()
