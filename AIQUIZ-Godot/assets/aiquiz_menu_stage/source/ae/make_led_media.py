"""メニューの LED 番組（AIQUIZ VISION）の素材を作る。

- led/led_logo.png：看板と同じロゴ（ロゴエディタの書き出し assets/branding/logo/aiquiz_logo.png）を白・透過で。
  AE の LED_Logo と Godot が使う。ロゴエディタで保存するとこの画像も作り直される
- source/ae/media/clip_placeholder.jpg：AE でハイライトの枠を確かめるための仮の映像（ゲームの実画面を
  LED の比 216:98 に切り抜いたもの）。Godot は保存したハイライトの連番に差し替えるので、ゲームには入れない

プロジェクトルートから `python assets/aiquiz_menu_stage/source/ae/make_led_media.py`
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE.parent / "textures"))
from make_textures import _logo_mask  # noqa: E402  看板と同じロゴの取り出し

LED_DIR = ROOT / "assets" / "aiquiz_menu_stage" / "led"
MEDIA_DIR = HERE / "media"
PLACEHOLDER_SOURCE = ROOT / "artifacts" / "aiquiz_stadium" / "game" / "v3_2p_day_play.png"
LED_ASPECT = 216.0 / 98.0
WHITE = (246, 244, 238)
LOGO_SIZE = (1310, 300)  # led_motion.json の LED_Logo / LED_LogoLoop が使う画像の大きさ


def make_logo(size: tuple[int, int] = LOGO_SIZE) -> Path:
    # LED の番組（led_motion.json）はこの画像を 1310×300 として描くので、縦横比が変わっても
    # 画像の大きさは変えず、ロゴを中に収めて真ん中に置く（引き伸ばさない）
    w, h = size
    mask = _logo_mask(h)
    if mask.width > w:
        mask = _logo_mask(max(1, int(h * w / mask.width)))
    alpha = Image.new("L", size, 0)
    alpha.paste(mask, ((w - mask.width) // 2, (h - mask.height) // 2))
    logo = Image.new("RGBA", size, WHITE + (0,))
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
