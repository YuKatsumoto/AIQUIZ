"""採用したアイコン（D案「ロゴ全体」：暗い地に TESTOPIA と黄色いベルト）を、ゲームと書き出しが使う形に出す。

先に次の 2 つで SVG と 1024 の PNG を作っておく：
    python tools/logo_editor/build_icon_concepts.py
    Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_icon_concepts.gd
そのあと：
    python tools/logo_editor/export_app_icon.py

出力：
  assets/branding/icon/testopia_icon.png       1024（project.godot の config/icon。ウィンドウ・タスクバー）
  assets/branding/icon/testopia_icon.ico       16〜256（Windows の exe。export_presets.cfg の application/icon）
  assets/ui/android/icon_192.png               Android の昔の形のアイコン
  assets/ui/android/icon_fg_432.png / icon_bg_432.png   Android のアダプティブアイコン（前景：ロゴ / 背景：暗い地）
"""
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CONCEPT_DIR = os.path.join(ROOT, "assets/branding/icon_concepts")
ICON_DIR = os.path.join(ROOT, "assets/branding/icon")
ANDROID_DIR = os.path.join(ROOT, "assets/ui/android")
FULL = os.path.join(CONCEPT_DIR, "icon_concept_d.png")
ANDROID_FG = os.path.join(CONCEPT_DIR, "icon_concept_d_android_fg.png")
BG = (0x0E, 0x0E, 0x0E, 255)  # build_icon_concepts.py の BG
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def main():
    os.makedirs(ICON_DIR, exist_ok=True)
    full = Image.open(FULL).convert("RGBA")
    assert full.size == (1024, 1024), full.size
    full.save(os.path.join(ICON_DIR, "testopia_icon.png"))
    frames = [full.resize((n, n), Image.LANCZOS) for n in ICO_SIZES]
    frames[-1].save(os.path.join(ICON_DIR, "testopia_icon.ico"), format="ICO",
                    sizes=[(n, n) for n in ICO_SIZES], append_images=frames[:-1])
    full.resize((192, 192), Image.LANCZOS).save(os.path.join(ANDROID_DIR, "icon_192.png"))
    Image.open(ANDROID_FG).convert("RGBA").resize((432, 432), Image.LANCZOS).save(os.path.join(ANDROID_DIR, "icon_fg_432.png"))
    Image.new("RGBA", (432, 432), BG).save(os.path.join(ANDROID_DIR, "icon_bg_432.png"))
    print("ok")


if __name__ == "__main__":
    main()
