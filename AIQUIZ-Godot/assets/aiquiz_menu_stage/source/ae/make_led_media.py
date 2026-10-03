"""メニューの LED 番組（AIQUIZ VISION）の素材を作る。

- led/led_logo.png：看板と同じロゴ（リポジトリ直下の icon.jpg）を白・透過で。AE の LED_Logo と Godot が使う
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


def make_logo(height_px: int = 300) -> Path:
    mask = _logo_mask(height_px)
    logo = Image.new("RGBA", mask.size, WHITE + (0,))
    logo.putalpha(mask)
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
