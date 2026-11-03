"""作品ページのサムネイル 2〜5 枚目（実機の撮影から）。

応募フォームの「サムネイル画像 2〜5」は作品掲載ページで使う（16:9・100MB 以下・JPG か PNG、1920x1080 推奨）。
1 枚目（final/t8_blender）はロゴの入ったキービジュアルなので、2〜5 枚目は遊びの中身を 1 枚に 1 つずつ見せる。
絵は PV のテロップの無い撮影の連番（artifacts/pv_capture/*_frames。1920x1080・本番画質）と、オンライン対戦の
VS カットインを本物のメニューで撮ったもの（tests/pv_capture/pv_thumbvs_runtime.gd → artifacts/pv_capture/thumb_vs/）。
その上に PV と同じ決まりのテロップ（docs/pv/previz/ae/pv_telop.jsxinc）を描き直して重ねる。

| | 名前 | 絵 | テロップ |
|---|---|---|---|
| 2 | wall | s09_play の 1 問目で、2 人がそれぞれの扉へ向かうところ（ゲームの画面そのまま） | 迫りくる壁の[問題に答えよう！] / 正解のドアを突き破れ！ |
| 3 | subjects | s06_s07 の S07 の 6 問（算数・国語・理科・社会・英語、3〜6 年）を 3x2 に並べる | [小1〜小6]の5教科から出題！ / 学年に合わせて、AIが問題を作る |
| 4 | shark | s09_play の脱落した P2 がサメに乗って P1 を襲うところ（後ろは 10 問目のボス壁） | 脱落した人は、[サメに乗って相手を狙う] |
| 5 | online | thumb_vs の VS カットイン（相手は「プリン好きの大根」・海賊帽） | [オンライン対戦]で勝負！ |

  python docs/pv/thumbnail/pv_stills.py                       # 書き出し → final/thumb<番号>_<名前>.jpg・.png、
                                                              #   テロップ無しの final/thumb<番号>_<名前>_clean.jpg、並べたもの final/_thumbs_2to5.jpg
  python docs/pv/thumbnail/pv_stills.py wall=1072 shark=4762   # コマを変える（online は vs_05_cutin_hold のような名前）

テロップの組み方は PV（After Effects）の書き出しを測って合わせた：本文 4.4cqw の Noto Sans JP Black・紺のふち 0.55cqw・
下へ 0.35cqw の影（紺 40%）・字間 +20/1000 em。AE は仮名と約物を詰めて組むので、仮名・約物は字形の幅に左右 0.055 em を
足した幅で送る（「迫りくる壁の問題に答えよう！」が PV 2720 と同じ幅 約 1063 px になる）。上の真ん中（tc）の本文は
字の上端が y 約 97、補足の帯は y 214〜266（PV 2150 の S07 のテロップ）。cqw は画面の幅の 1%（19.2 px）。
"""
import sys
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CAPTURE = ROOT / "artifacts/pv_capture"
OUT = HERE / "final"
FONTS = [Path("C:/Windows/Fonts/NotoSansJP-Black.ttf"), ROOT / "docs/submission/pdf/fonts/NotoSansJP-Black.ttf"]

W, H = 1920, 1080
CQ = W / 100
NAVY = (11, 22, 48)
YELLOW = (242, 194, 27)
WHITE = (255, 255, 255)

MAIN_SIZE = 4.4 * CQ
MAIN_STROKE = 0.55 * CQ
SHADOW_DY = 0.35 * CQ
SHADOW_OPACITY = 0.4
TRACKING = 0.020          # em
KANA_PAD = 0.055          # 仮名・約物の左右の余白（em）
MAIN_TOP = 85.5           # tc の本文の文字の原点の y（字の上端が約 97 になる）
SUB_SIZE = 2.05 * CQ
SUB_PAD_X = 1.1 * CQ
SUB_PLATE = (214, 266)    # tc の補足の帯の上と下
SUB_RADIUS = 0.4 * CQ
TAG_SIZE = 2.6 * CQ       # 教科の札（PV の S07 の左上）
TAG_PAD = (1.4 * CQ, 0.2 * CQ + 2.6 * CQ * 0.2)
TAG_RADIUS = 0.5 * CQ
TAG_BORDER = 0.3 * CQ

STILLS = {
    # P1 が青い扉（正解の 48）の前、P2 が赤い扉へ手をのばすところ。扉と問題の文がいちばん大きく読める
    "wall": {"no": 2, "take": "s09_play_frames", "frame": 1102,
             "telop": "迫りくる壁の[問題に答えよう！]", "sub": "正解のドアを突き破れ！"},
    "subjects": {"no": 3, "take": "s06_s07_frames", "telop": "[小1〜小6]の5教科から出題！", "sub": "学年に合わせて、AIが問題を作る"},
    "shark": {"no": 4, "take": "s09_play_frames", "frame": 4759, "telop": "脱落した人は、[サメに乗って相手を狙う]"},
    # 2 人の帽子（角帽と海賊帽）が上の真ん中の近くまであるので、本文だけ上へ寄せる（main_y：文字の原点の y）
    "online": {"no": 5, "take": "thumb_vs", "frame": "vs_06_gone", "telop": "[オンライン対戦]で勝負！", "main_y": 36},
}
# S07 の 6 問（tests/pv_capture/pv_s06_s07_runtime.gd の S07_QUIZZES の順。各 2 拍 = 56 コマの真ん中あたり）
SUBJECTS = [("算数 4年", 370), ("国語 6年", 425), ("理科 3年", 480), ("社会 6年", 535), ("英語 3年", 590), ("算数 6年", 650)]
SUBJECT_CROP = (380, 255, 1540, 907.5)   # 壁の問題と扉が入る 16:9 の範囲。上に空を少し入れて、問題の文を札より下にする


@lru_cache(maxsize=None)
def font(size: float) -> ImageFont.FreeTypeFont:
    for path in FONTS:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    raise FileNotFoundError("Noto Sans JP Black が無い（C:/Windows/Fonts か docs/submission/pdf/fonts/）")


@lru_cache(maxsize=None)
def ink(ch: str, size: float) -> tuple[int, int, int, int]:
    """文字の原点から見た、字形の範囲（左・上・右・下）"""
    pad = int(size)
    im = Image.new("L", (pad * 3, pad * 3), 0)
    ImageDraw.Draw(im).text((pad, pad), ch, font=font(size), fill=255)
    box = im.getbbox() or (pad, pad, pad, pad)
    return box[0] - pad, box[1] - pad, box[2] - pad, box[3] - pad


def tight(ch: str) -> bool:
    """AE が詰めて組む字（仮名・約物）"""
    o = ord(ch)
    return 0x3040 <= o <= 0x30FF or 0xFF01 <= o <= 0xFF0F or 0xFF1A <= o <= 0xFF1F or ch in "、。「」『』（）〜・"


def parse(marked: str) -> list[tuple[str, bool]]:
    """"教科と学年を、[えらぶ]" → [(字, 黄色か), ...]"""
    out, key = [], False
    for ch in marked:
        if ch in "[]":
            key = ch == "["
            continue
        out.append((ch, key))
    return out


def layout(chars: list[tuple[str, bool]], size: float) -> tuple[list[tuple[str, bool, float]], float]:
    """字ごとの描く位置（原点の x）と、字形の左端から右端までの幅"""
    placed, x = [], 0.0
    left = right = None
    for i, (ch, key) in enumerate(chars):
        l, _, r, _ = ink(ch, size)
        if tight(ch):
            ox = x - l + KANA_PAD * size
            adv = (r - l) + 2 * KANA_PAD * size
        else:
            ox = x
            adv = font(size).getlength(ch)
        placed.append((ch, key, ox))
        left = ox + l if left is None else min(left, ox + l)
        right = ox + r if right is None else max(right, ox + r)
        x += adv + (TRACKING * size if i < len(chars) - 1 else 0)
    return [(ch, key, ox - left) for ch, key, ox in placed], right - left


def draw_main(im: Image.Image, marked: str, cx: float, y: float, size: float = MAIN_SIZE, stroke: float = MAIN_STROKE) -> None:
    """本文：白（[] の中は黄色）・紺のふち・下へ影。横の真ん中 cx、文字の原点の y"""
    placed, width = layout(parse(marked), size)
    x0 = cx - width / 2
    fill = Image.new("L", im.size, 0)
    rim = Image.new("L", im.size, 0)
    color = Image.new("RGB", im.size, WHITE)
    df, dr, dc = ImageDraw.Draw(fill), ImageDraw.Draw(rim), ImageDraw.Draw(color)
    f = font(size)
    for ch, key, ox in placed:
        p = (x0 + ox, y)
        df.text(p, ch, font=f, fill=255)
        dr.text(p, ch, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
        dc.text(p, ch, font=f, fill=YELLOW if key else WHITE)
    shadow = Image.new("L", im.size, 0)
    shadow.paste(rim, (0, round(SHADOW_DY)))
    base = im.convert("RGBA")
    base.alpha_composite(solid(NAVY, shadow.point(lambda a: round(a * SHADOW_OPACITY))))
    base.alpha_composite(solid(NAVY, rim))
    face = color.convert("RGBA")
    face.putalpha(fill)
    base.alpha_composite(face)
    im.paste(base.convert("RGB"))


def solid(rgb: tuple, alpha: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", alpha.size, rgb + (0,))
    layer.putalpha(alpha)
    return layer


def text_box(text: str, size: float) -> tuple[float, float, float]:
    """字形の幅と、漢字の字形の上下（原点から）。帯の中で上下の真ん中にそろえるのに使う"""
    _, width = layout(parse(text), size)
    _, top, _, bottom = ink("題", size)
    return width, top, bottom


def draw_sub(im: Image.Image, text: str, cx: float, top: float = SUB_PLATE[0], bottom: float = SUB_PLATE[1]) -> None:
    """補足：紺の角丸の帯に白い字（横の真ん中 cx）"""
    width, ink_top, ink_bottom = text_box(text, SUB_SIZE)
    plate_w = width + 2 * SUB_PAD_X
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((cx - plate_w / 2, top, cx + plate_w / 2, bottom), radius=SUB_RADIUS, fill=NAVY)
    placed, _ = layout(parse(text), SUB_SIZE)
    y = (top + bottom) / 2 - (ink_top + ink_bottom) / 2
    for ch, _, ox in placed:
        d.text((cx - width / 2 + ox, y), ch, font=font(SUB_SIZE), fill=WHITE)


def draw_tag(im: Image.Image, text: str, x: float, y: float, scale: float = 1.0) -> None:
    """教科の札：紺の地・黄色い縁・白い字（左上が (x, y)）"""
    size = TAG_SIZE * scale
    width, ink_top, ink_bottom = text_box(text, size)
    pad_x, pad_y = TAG_PAD[0] * scale, TAG_PAD[1] * scale
    w, h = width + 2 * pad_x, (ink_bottom - ink_top) + 2 * pad_y
    border = TAG_BORDER * scale
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((x - border, y - border, x + w + border, y + h + border), radius=TAG_RADIUS * scale + border, fill=YELLOW)
    d.rounded_rectangle((x + border, y + border, x + w - border, y + h - border), radius=max(1, TAG_RADIUS * scale - border), fill=NAVY)
    placed, _ = layout(parse(text), size)
    for ch, _, ox in placed:
        d.text((x + pad_x + ox, y + pad_y - ink_top), ch, font=font(size), fill=WHITE)


# ------------------------------------------------------------------ 絵

def frame(take: str, n) -> Image.Image:
    name = n if isinstance(n, str) else f"pv_{int(n):04d}"
    for ext in (".png", ".jpg"):
        p = CAPTURE / take / f"{name}{ext}"
        if p.exists():
            im = Image.open(p).convert("RGB")
            if im.size != (W, H):
                raise ValueError(f"{p} は {im.size}（1920x1080 で撮る）")
            return im
    raise FileNotFoundError(CAPTURE / take / name)


def subjects_board(with_telop: bool) -> Image.Image:
    """S07 の 6 問を 3x2 に並べる。後ろは S07 の 1 問を大きくぼかしたもの（空と壁の色）。
    教科の札は、問題の文に重ならないよう、カードの上の縁にまたがる見出しにする"""
    tiles = [(tag, frame("s06_s07_frames", n).crop(SUBJECT_CROP)) for tag, n in SUBJECTS]
    back = frame("s06_s07_frames", SUBJECTS[1][1]).filter(ImageFilter.GaussianBlur(28))
    back = Image.eval(back, lambda v: round(v * 0.82))
    cols, gap = 3, 46
    tw = 576 if with_telop else 600
    th = tw * 9 / 16
    side = (W - (cols * tw + (cols - 1) * 24)) / 2
    top = 318 if with_telop else (H - (2 * th + gap)) / 2 + 12
    spots = [(round(side + (i % cols) * (tw + 24)), round(top + (i // cols) * (th + gap))) for i in range(len(tiles))]
    w, h = round(tw), round(th)
    shade = Image.new("L", (W, H), 0)
    ds = ImageDraw.Draw(shade)
    for x, y in spots:
        ds.rounded_rectangle((x - 4, y + 2, x + w + 4, y + h + 12), radius=16, fill=150)
    board = Image.composite(Image.new("RGB", (W, H), NAVY), back, shade.filter(ImageFilter.GaussianBlur(12)))
    d = ImageDraw.Draw(board)
    tag_scale = 0.62
    tag_h = (ink("題", TAG_SIZE * tag_scale)[3] - ink("題", TAG_SIZE * tag_scale)[1]) + 2 * TAG_PAD[1] * tag_scale
    for (tag, tile), (x, y) in zip(tiles, spots):
        d.rounded_rectangle((x - 4, y - 4, x + w + 4, y + h + 4), radius=14, fill=WHITE)
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=10, fill=255)
        board.paste(tile.resize((w, h), Image.LANCZOS), (x, y), mask)
        draw_tag(board, tag, x + 18, y - tag_h / 2 - 2, scale=tag_scale)
    return board


def still(name: str, pick, with_telop: bool) -> Image.Image:
    cfg = STILLS[name]
    if name == "subjects":
        im = subjects_board(with_telop)
    else:
        im = frame(cfg["take"], pick)
    if with_telop:
        draw_main(im, cfg["telop"], W / 2, cfg.get("main_y", MAIN_TOP))
        if cfg.get("sub"):
            draw_sub(im, cfg["sub"], W / 2)
    return im


def save(im: Image.Image, stem: str) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{stem}.jpg"
    im.save(dst, quality=95, optimize=True, subsampling=0)
    im.save(OUT / f"{stem}.png", optimize=True)
    print(f"{dst.relative_to(ROOT)}  {dst.stat().st_size / 1024:.0f} KB / png {(OUT / f'{stem}.png').stat().st_size / 1024:.0f} KB")
    return dst


def overview(paths: list[Path], dst: Path) -> None:
    """1 枚目（t8_blender）と 2〜5 枚目を並べる（小さく表示したときの確かめ）"""
    tw = 640
    th = tw * H // W
    pad = 16
    img = Image.new("RGB", (3 * tw + 4 * pad, 2 * th + 3 * pad), (245, 245, 242))
    for i, p in enumerate(paths):
        x = pad + (i % 3) * (tw + pad)
        y = pad + (i // 3) * (th + pad)
        img.paste(Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y))
    img.save(dst, quality=88)
    print(dst.relative_to(ROOT))


def main() -> None:
    picks = {name: cfg.get("frame") for name, cfg in STILLS.items()}
    for arg in sys.argv[1:]:
        key, _, value = arg.partition("=")
        if key in picks and value:
            picks[key] = value if key == "online" else int(value)
    made = []
    for name, cfg in STILLS.items():
        stem = f"thumb{cfg['no']}_{name}"
        made.append(save(still(name, picks[name], True), stem))
        save(still(name, picks[name], False), f"{stem}_clean")
    overview([OUT / "t8_blender.jpg"] + made, OUT / "_thumbs_2to5.jpg")


if __name__ == "__main__":
    main()
