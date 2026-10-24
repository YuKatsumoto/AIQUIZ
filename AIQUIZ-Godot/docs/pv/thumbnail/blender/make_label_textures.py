"""Godot の壁の文字（Label3D：扉の答えと問題の看板）を、縁取りつきの透過 PNG にする。Blender では板に貼る（build_scene.py）。

Blender の文字（Text オブジェクト）の太らせは角がとがるので、縁取りは PIL で丸い角のまま描く（Label3D の縁取りも角が丸い）。
形はゲームの絵を板の正面に直して一字ずつ測った（t2 の「56」、t5 の「54」と問題文。2026-10-23）:
  - 字の並び（送り幅）はフォントの公称のまま。行の送り幅の合計の真ん中が Label3D の原点（中央揃え）
  - 各字は、公称の位置のインクの左下を動かさずに GLYPH_SCALE 倍で描かれる（ゲームの MSDF の字は公称より少し大きく出る）
  - 縁の太さは OUTLINE_EM（公称の em）。outline_size / font_size が 0.125 未満のときはその比で細くする
    （上限 0.125 は、壁の文字のフォント（quiz_wall.gd：MSDF の大きさ 64・幅 16 → 縁は 8 まで）から）
  - 縦は、Godot の Label3D と同じく、行の高さ（ascent + descent）の積み重ねを、中央揃えなら真ん中、下揃えなら下端で原点に
    合わせる（Noto Sans JP の ascent 1.160・descent 0.288 em）。1 行なら基準線は中央揃えで原点の (ascent − descent) / 2 下、
    下揃えで descent 上。測ったずれ BASELINE_NUDGE を足す
  - 折り返しは Label3D の width（font_size の px）で。日本語は字のあいだで折り、閉じかっこ・句読点の前と開きかっこの後では折らない。
    各行はそれぞれ中央揃え
出力：tex/<shot>_label_NN.png と tex/<shot>_labels.json（板の 4 隅の位置。Label3D の座標で、x 右・y 上、単位 m）。

  python docs/pv/thumbnail/blender/make_label_textures.py t5
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FONT = ROOT / "resources/fonts/NotoSansJP-Regular.otf"

EM_PX = 800                      # 画像の公称の 1 em の画素数
GLYPH_SCALE = 1.073              # 字の大きさ ÷ 公称（「56」「54」と問題文の 14 字の中央値）
OUTLINE_EM = 0.100               # 縁の太さ（字の端から外へ、公称の em）
ASCENT, DESCENT = 1.160, 0.288   # Noto Sans JP（公称の em）
BASELINE_NUDGE = 0.005           # 測った基準線のずれ（上へ、公称の em）
MARGIN = 16


def rgba8(c: list) -> tuple:
    def enc(v: float) -> int:
        return max(0, min(255, round(v * 255)))
    return (enc(c[0]), enc(c[1]), enc(c[2]), enc(c[3] if len(c) > 3 else 1.0))


def ink_box(font: ImageFont.FreeTypeFont, ch: str) -> tuple | None:
    """その字のインクの範囲（基準線の左端から、px。x 右・y 下）"""
    size = font.size
    im = Image.new("L", (size * 3, size * 3), 0)
    ImageDraw.Draw(im).text((size, size * 2), ch, font=font, anchor="ls", fill=255)
    box = im.getbbox()
    if box is None:
        return None
    return box[0] - size, box[1] - size * 2, box[2] - size, box[3] - size * 2


NO_LINE_START = set("」』）】〕］｝〉》、。，．・：；？！ー…‥ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ)]},.:;?!")
NO_LINE_END = set("「『（【〔［｛〈《([{")


def wrap(text: str, font: ImageFont.FreeTypeFont, width_px: float) -> list[str]:
    """Label3D の自動の折り返し（幅 width_px。font は公称の大きさ）を、字のあいだで折る近似で"""
    lines, line = [], ""
    for ch in text:
        if line and font.getlength(line + ch) > width_px + 0.5:
            # 行頭に来てはいけない字なら、前の字ごと次の行へ
            cut = len(line)
            while cut > 1 and (ch if cut == len(line) else line[cut]) in NO_LINE_START:
                cut -= 1
            while cut > 1 and line[cut - 1] in NO_LINE_END:
                cut -= 1
            lines.append(line[:cut].rstrip())
            line = line[cut:].lstrip()
        line += ch
    lines.append(line)
    return lines


def draw_label(lines: list[str], fill: tuple, outline: tuple, stroke: int) -> tuple:
    """行ごとに中央揃えで描く。戻り値：画像、原点（行の送り幅の真ん中・1 行目の基準線）の画像の中の位置 (ox, oy)、行の高さ（px）"""
    nominal = ImageFont.truetype(str(FONT), EM_PX)
    big = ImageFont.truetype(str(FONT), round(EM_PX * GLYPH_SCALE))
    k = big.size / EM_PX
    line_h = (ASCENT + DESCENT) * EM_PX
    glyphs = []
    for n, text in enumerate(lines):
        x0 = -nominal.getlength(text) / 2            # 送り幅の真ん中が原点
        for i, ch in enumerate(text):
            bb = ink_box(nominal, ch)
            if bb is None:
                continue
            pen = x0 + nominal.getlength(text[:i])
            # 公称のインクの左下 (pen + bb[0], bb[3]) を動かさずに k 倍：大きい字の基準線の左端の位置
            glyphs.append((ch, pen + bb[0] * (1 - k), n * line_h + bb[3] * (1 - k)))
    pad = stroke + MARGIN
    left = min(x for _, x, _ in glyphs) - pad
    right = max(x + big.getlength(ch) for ch, x, _ in glyphs) + pad
    top = -ASCENT * EM_PX * k - pad
    bottom = (len(lines) - 1) * line_h + DESCENT * EM_PX * k + pad
    w, h = int(right - left + 1), int(bottom - top + 1)
    ox, oy = -left, -top
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if stroke > 0:
        for ch, x, y in glyphs:       # 縁を先に全部（ゲームも縁は字より下の順で描く）
            d.text((ox + x, oy + y), ch, font=big, anchor="ls", fill=outline, stroke_width=stroke, stroke_fill=outline)
    for ch, x, y in glyphs:
        d.text((ox + x, oy + y), ch, font=big, anchor="ls", fill=fill)
    return img, ox, oy, line_h


def make(shot: str) -> None:
    scene = json.loads((ROOT / f"artifacts/pv_capture/thumb_{shot}_export/export/scene.json").read_text(encoding="utf-8"))
    out_dir = HERE / "tex"
    out_dir.mkdir(exist_ok=True)
    rows = []
    for i, label in enumerate(l for l in scene["labels"] if l["text"]):
        text = label["text"]
        em_m = label["font_size"] * label["pixel_size"]          # 公称の 1 em（m）
        m_per_px = em_m / EM_PX
        ratio = min(label["outline_size"] / max(label["font_size"], 1), 0.125) / 0.125
        stroke = max(1, round(OUTLINE_EM * ratio * EM_PX)) if label["outline_size"] > 0 else 0
        nominal = ImageFont.truetype(str(FONT), EM_PX)
        width_px = label["width"] / label["font_size"] * EM_PX if label.get("autowrap", 0) else 1e9
        lines = wrap(text, nominal, width_px)
        img, ox, oy, line_h = draw_label(lines, rgba8(label["modulate"]), rgba8(label["outline_modulate"]), stroke)
        name = f"{shot}_label_{i:02d}.png"
        img.save(out_dir / name)
        w, h = img.size
        # 1 行目の基準線（Label3D：行の高さの積み重ねの上端 vbegin から ascent 下）
        stack = len(lines) * (ASCENT + DESCENT)
        vbegin = {0: 0.0, 1: stack / 2, 2: stack}.get(label["v_align"], stack / 2)
        y_base = (vbegin - ASCENT + BASELINE_NUDGE) * em_m

        def to_local(px: float, py: float) -> list:
            return [(px - ox) * m_per_px, y_base - (py - oy) * m_per_px]

        rows.append({"path": label["path"], "text": text, "lines": lines, "texture": f"tex/{name}", "size_px": [w, h],
                     "em_m": em_m, "stroke_px": stroke, "xform": label["xform"],
                     "corners": [to_local(0, h), to_local(w, h), to_local(w, 0), to_local(0, 0)]})   # 左下・右下・右上・左上
        print(f"{name}  {' / '.join(lines)}  em {em_m:.3f} m  stroke {stroke} px  {w}x{h}")
    (out_dir / f"{shot}_labels.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    make(sys.argv[1] if len(sys.argv) > 1 else "t5")
