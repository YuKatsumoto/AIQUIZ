"""PDF に使う太さごとの Noto Sans JP を、Windows に入っている可変フォントから fonts/ に作る。

    python docs/submission/pdf/make_fonts.py    # fonttools が要る（pip install fonttools。4.66 以降は Python 3.11 以上）

- 可変フォント（NotoSansJP-VF.ttf）のままだと、Edge は PDF の文字を図形（Type 3）として入れるので、Acrobat で書き換えにくい。
  太さを固定したフォントにすると、普通のフォント（TrueType）として入る。字の形は可変フォントと同じ。
- 作るのは deck.css・doc.css で使っている太さ（400〜900）だけ。読み込みは fonts.css。
- Noto Sans JP は SIL Open Font License 1.1。太さを固定しただけで、字の形には手を加えていない。
"""

import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

VF = Path(r"C:\Windows\Fonts\NotoSansJP-VF.ttf")
FONTS = Path(__file__).resolve().parent / "fonts"
WEIGHTS = {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black"}


def set_names(font: TTFont, weight: int, style: str) -> None:
    """名前を固定の太さのものにする。PDF には 6 番（NotoSansJP-Bold など）が出る。"""
    family = "Noto Sans JP"
    ribbi = style in ("Regular", "Bold")
    names = {
        1: family if ribbi else f"{family} {style}",
        2: style if ribbi else "Regular",
        3: f"NotoSansJP-{style};static from NotoSansJP-VF",
        4: f"{family} {style}",
        6: f"NotoSansJP-{style}",
        16: family,
        17: style,
    }
    table = font["name"]
    table.names = [n for n in table.names if n.nameID not in names and n.nameID != 25]
    for name_id, text in names.items():
        table.setName(text, name_id, 3, 1, 0x409)
    os2 = font["OS/2"]
    os2.usWeightClass = weight
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | (0b100000 if style == "Bold" else 0b1000000 if style == "Regular" else 0)
    font["head"].macStyle = 1 if style == "Bold" else 0


def main() -> None:
    if not VF.exists():
        sys.exit(f"可変フォントが見つからない: {VF}")
    FONTS.mkdir(exist_ok=True)
    for weight, style in WEIGHTS.items():
        font = instantiateVariableFont(TTFont(VF), {"wght": weight})
        set_names(font, weight, style)
        path = FONTS / f"NotoSansJP-{style}.ttf"
        font.save(path)
        print(f"{path.name}: {path.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
