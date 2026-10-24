"""メニューの LED 番組（AIQUIZ VISION）の素材を作る。

- led/led_logo.png：今のゲームのロゴ（タイトルと同じ testopia。ロゴエディタの書き出し
  assets/branding/logo/testopia_logo.svg）の白い字だけを透過で（O と A の中の P1・P2 の頭は描かない）。
  AE の LED_Logo / LED_LogoLoop と Godot が使う。ロゴエディタで保存するとこの画像も作り直される
- source/ae/media/clip_placeholder.jpg：AE でハイライトの枠を確かめるための仮の映像（ゲームの実画面を
  LED の比 216:98 に切り抜いたもの）。Godot は保存したハイライトの連番に差し替えるので、ゲームには入れない

プロジェクトルートから `python assets/aiquiz_menu_stage/source/ae/make_led_media.py`
"""
from __future__ import annotations

import re
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

LED_DIR = ROOT / "assets" / "aiquiz_menu_stage" / "led"
MEDIA_DIR = HERE / "media"
PLACEHOLDER_SOURCE = ROOT / "artifacts" / "aiquiz_stadium" / "game" / "v3_2p_day_play.png"
LED_ASPECT = 216.0 / 98.0
## 今のゲームのロゴ（メインメニューのタイトルと同じ）。白い字の多角形と、P1・P2 の頭（紺の丸と色のブロック）
CURRENT_LOGO = ROOT / "assets" / "branding" / "logo" / "testopia_logo.svg"
## 字の多角形を描く倍率（描いてから縮めて縁をなめらかにする）
SUPERSAMPLE = 4
LOGO_SIZE = (1310, 300)  # led_motion.json の LED_Logo / LED_LogoLoop が使う画像の大きさ


def _letters(height: int) -> Image.Image:
    """ロゴの白い字だけ（頭の部品は色が白でないので除く）を、字の高さ `height` 前後の白・透過で。"""
    svg = CURRENT_LOGO.read_text(encoding="utf-8")
    shapes = []
    for d, fill in re.findall(r'<path d="([^"]*)" fill="([^"]*)"', svg):
        if fill.lower() != "#ffffff":
            continue
        numbers = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", d)]
        shapes.append(list(zip(numbers[0::2], numbers[1::2])))
    xs = [x for shape in shapes for x, _ in shape]
    ys = [y for shape in shapes for _, y in shape]
    left, top = min(xs), min(ys)
    scale = height * SUPERSAMPLE / (max(ys) - top)
    size = (int((max(xs) - left) * scale) + 2, int((max(ys) - top) * scale) + 2)
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    for shape in shapes:
        draw.polygon([((x - left) * scale, (y - top) * scale) for x, y in shape], fill=255)
    mask = mask.resize((max(1, size[0] // SUPERSAMPLE), max(1, size[1] // SUPERSAMPLE)), Image.LANCZOS)
    return mask


def make_logo(size: tuple[int, int] = LOGO_SIZE) -> Path:
    # LED の番組（led_motion.json）はこの画像を 1310×300 として描くので、縦横比が変わっても
    # 画像の大きさは変えず、ロゴを中に収めて真ん中に置く（引き伸ばさない）
    w, h = size
    mask = _letters(h)
    if mask.width > w - 12:
        mask = _letters(max(1, int(h * (w - 12) / mask.width)))
    alpha = Image.new("L", size, 0)
    alpha.paste(mask, ((w - mask.width) // 2, (h - mask.height) // 2))
    logo = Image.new("RGBA", size, (255, 255, 255, 0))
    logo.putalpha(alpha)
    LED_DIR.mkdir(parents=True, exist_ok=True)
    out = LED_DIR / "led_logo.png"
    logo.save(out)
    return out


def make_placeholder(width: int = 864) -> Path:
    src = Image.open(PLACEHOLDER_SOURCE).convert("RGB")
    w, h = src.size
    # 下の HUD（得点の枠、画面の下 17%）を避け、壁と二人が入る帯を LED の比で中央から切る
    bottom = int(h * 0.83)
    top = int(h * 0.05)
    crop_w = int((bottom - top) * LED_ASPECT)
    left = (w - crop_w) // 2
    clip = src.crop((left, top, left + crop_w, bottom)).resize((width, int(width / LED_ASPECT)), Image.LANCZOS)
    MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    out = MEDIA_DIR / "clip_placeholder.jpg"
    clip.save(out, quality=90)
    return out


if __name__ == "__main__":
    for path in (make_logo(), make_placeholder()):
        print(path.relative_to(ROOT), Image.open(path).size)
