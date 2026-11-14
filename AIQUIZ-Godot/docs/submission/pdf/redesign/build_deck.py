"""02 アピール資料の新デザイン版（PowerPoint）を組む。

    python -I docs/submission/pdf/redesign/build_deck.py [出力.pptx]

- 中身（文・写真・図のつながり）は 2026-11-03 の `02_アピール資料.pptx`（16 ページ）と同じ。見た目だけを作り直す。
- 出力は `docs/submission/02_アピール資料_新デザイン.pptx`。もう一度実行すると、PowerPoint で直したところは消える。
- `to_pptx/base.pptx`（PowerPoint で作った白紙・16:9）の各ページの中身を差し替える。追加のライブラリは Pillow だけ（字の幅と画像の大きさを測る）。
- 座標は px（1920×1080）。1 px = 6350 EMU = 0.5 pt。
- 字は、見出しが Noto Sans JP ExtraBold・SemiBold（`pdf/fonts/` の固定の太さ）、本文が BIZ UDPゴシック（Windows に入っている）。
  PowerPoint の PDF 書き出しで細く出る Noto Sans JP の Regular・Medium・Bold・Black は使わない。
"""

import math
import re
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image, ImageFont

HERE = Path(__file__).resolve().parent
PDF = HERE.parent
IMG, LOGOS = PDF / "img", PDF / "logos"
BASE = PDF / "to_pptx" / "base.pptx"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else PDF.parent / "02_アピール資料_新デザイン.pptx"

EMU = 6350

# ---------------------------------------------------------------- 色と字
BG_TOP, BG_BOTTOM = "0E1B42", "091230"
NAVY = "0B1634"      # 明るい札の上の字
PANEL = "111F49"     # 写真の無い枠・帯の地
CARD = "182858"      # カード
EDGE = "2E4283"      # カードと写真のふち
INK = "FFFFFF"
BODY = "DCE4F7"      # カードの中の本文
SUB = "9FB0D8"       # 補足・キャプション
SKY = "9CCBFF"       # 副題
YEL = "FFD23F"       # 強調（コンベアの黄色）
BLUE = "3BA3F5"      # 青いドア・プレイヤー
RED = "F0464F"       # 赤いドア
ORG = "F58F2E"       # オレンジのプレイヤー
GRN = "35C27A"
SLATE = "93A2CC"

F_T = "Noto Sans JP ExtraBold"
F_H = "Noto Sans JP SemiBold"
F_B = "BIZ UDPゴシック"

_FONT_FILES = {(F_T, False): ("NotoSansJP-ExtraBold.ttf", 0), (F_H, False): ("NotoSansJP-SemiBold.ttf", 0),
               (F_B, False): ("BIZ-UDGothicR.ttc", 1), (F_B, True): ("BIZ-UDGothicB.ttc", 1)}
_fonts: dict = {}


def tw(text: str, size: float, font: str = F_B, bold: bool = False) -> float:
    """字の幅（px）。"""
    key = (font, bold and font == F_B)
    if key not in _fonts:
        name, index = _FONT_FILES[key]
        _fonts[key] = ImageFont.truetype(str(Path("C:/Windows/Fonts") / name), 200, index=index)
    return _fonts[key].getlength(text) * size / 200


# ---------------------------------------------------------------- DrawingML の部品
NS = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
SHADOW = (f'<a:effectLst><a:outerShdw blurRad="{26 * EMU}" dist="{8 * EMU}" dir="5400000" algn="ctr" rotWithShape="0">'
          '<a:srgbClr val="000000"><a:alpha val="38000"/></a:srgbClr></a:outerShdw></a:effectLst>')


def emu(v: float) -> int:
    return int(round(v * EMU))


def solid(color: str | None, alpha: float | None = None) -> str:
    if not color:
        return "<a:noFill/>"
    a = f'<a:alpha val="{int(alpha * 1000)}"/>' if alpha is not None else ""
    return f'<a:solidFill><a:srgbClr val="{color}">{a}</a:srgbClr></a:solidFill>'


def grad(stops: list, angle: float = 90) -> str:
    """stops は (位置 %, 色, 不透明度 %)。angle 90 = 上から下。"""
    gs = "".join(f'<a:gs pos="{int(p * 1000)}"><a:srgbClr val="{c}"><a:alpha val="{int(a * 1000)}"/></a:srgbClr></a:gs>' for p, c, a in stops)
    return f'<a:gradFill rotWithShape="1"><a:gsLst>{gs}</a:gsLst><a:lin ang="{int(angle * 60000)}" scaled="0"/></a:gradFill>'


def xfrm(x, y, w, h, rot=0, flip_h=False, flip_v=False, tag="a:xfrm") -> str:
    attrs = (f' rot="{int(rot)}"' if rot else "") + (' flipH="1"' if flip_h else "") + (' flipV="1"' if flip_v else "")
    return f'<{tag}{attrs}><a:off x="{emu(x)}" y="{emu(y)}"/><a:ext cx="{max(emu(w), 0)}" cy="{max(emu(h), 0)}"/></{tag}>'


def geom(r, w: float, h: float) -> str:
    """r が数なら 4 つの角、(上, 下) なら上と下で別の丸み。"""
    m = min(w, h)
    def adj(v):
        return int(min(50000, round(v / m * 100000)))
    if isinstance(r, tuple):
        return (f'<a:prstGeom prst="round2SameRect"><a:avLst><a:gd name="adj1" fmla="val {adj(r[0])}"/>'
                f'<a:gd name="adj2" fmla="val {adj(r[1])}"/></a:avLst></a:prstGeom>')
    if not r:
        return '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
    return f'<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val {adj(r)}"/></a:avLst></a:prstGeom>'


def rpr(size: float, color: str, font: str, bold: bool, tag: str = "a:rPr") -> str:
    return (f'<{tag} lang="ja-JP" altLang="en-US" sz="{int(round(size * 50))}" b="{1 if bold else 0}" dirty="0">{solid(color)}'
            f'<a:latin typeface="{font}"/><a:ea typeface="{font}"/><a:cs typeface="{font}"/></{tag}>')


def runs(text: str, size: float, color: str, font: str, bold: bool, emph: str | None) -> str:
    """**…** は強調（色を emph に。本文は太字、見出しは ExtraBold）。\n は段落の中の改行。"""
    out = []
    for k, seg in enumerate(text.split("**")):
        c, f, b = color, font, bold
        if k % 2:
            c = emph or color
            f, b = (font, True) if font == F_B else (F_T, False)
        for j, piece in enumerate(seg.split("\n")):
            if j:
                out.append(f"<a:br>{rpr(size, c, f, b)}</a:br>")
            if piece:
                out.append(f"<a:r>{rpr(size, c, f, b)}<a:t>{escape(piece)}</a:t></a:r>")
    return "".join(out)


def body(paras, size=24, color=INK, font=F_B, bold=False, align="l", anchor="t", lh=None, gap=0, wrap_text=True, emph=YEL,
         page_field=False) -> str:
    if isinstance(paras, str):
        paras = [paras]
    lh = lh or round(size * 1.5)
    al = {"l": "l", "c": "ctr", "r": "r"}[align]
    ps = []
    for k, p in enumerate(paras):
        after = gap if k < len(paras) - 1 else 0
        ppr = (f'<a:pPr algn="{al}"><a:lnSpc><a:spcPts val="{int(lh * 50)}"/></a:lnSpc><a:spcBef><a:spcPts val="0"/></a:spcBef>'
               f'<a:spcAft><a:spcPts val="{int(after * 50)}"/></a:spcAft></a:pPr>')
        if page_field:
            n, rest = p.split(" ", 1)
            inner = (f'<a:fld id="{{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}}" type="slidenum">{rpr(size, color, font, bold)}<a:t>{n}</a:t></a:fld>'
                     f'<a:r>{rpr(size, color, font, bold)}<a:t> {escape(rest)}</a:t></a:r>')
        elif isinstance(p, list):  # [(文字, 色), …]
            inner = "".join(f"<a:r>{rpr(size, c, font, bold)}<a:t>{escape(t)}</a:t></a:r>" for t, c in p)
        else:
            inner = runs(p, size, color, font, bold, emph)
        ps.append(f'<a:p>{ppr}{inner}{rpr(size, color, font, bold, "a:endParaRPr")}</a:p>')
    an = {"t": "t", "c": "ctr", "b": "b"}[anchor]
    return (f'<p:txBody><a:bodyPr wrap="{"square" if wrap_text else "none"}" lIns="0" tIns="0" rIns="0" bIns="0" anchor="{an}" '
            f'anchorCtr="0" rtlCol="0"><a:noAutofit/></a:bodyPr><a:lstStyle/>{"".join(ps)}</p:txBody>')


class Media:
    def __init__(self):
        self.names: dict[str, str] = {}
        self.blobs: dict[str, bytes] = {}

    def add(self, path: Path) -> str:
        key = str(path)
        if key not in self.names:
            name = f"image{len(self.names) + 1}{path.suffix.lower()}"
            self.names[key] = name
            self.blobs[name] = path.read_bytes()
        return self.names[key]


class Slide:
    def __init__(self, number: int, media: Media):
        self.number = number
        self.media = media
        self.parts: list[str] = []
        self.next_id = 2
        self.rels: list[tuple[str, str]] = []

    def nid(self) -> int:
        self.next_id += 1
        return self.next_id - 1

    def rel(self, target: str) -> str:
        for rid, t in self.rels:
            if t == target:
                return rid
        rid = f"rId{len(self.rels) + 2}"  # rId1 はレイアウト
        self.rels.append((rid, target))
        return rid

    # ------------------------------------------------------------ 基本の形
    def rect(self, x, y, w, h, fill=None, line=None, lw=1.5, r=0, alpha=None, shadow=False, dash=False, name="箱",
             shape=None, fill_xml=None, text=None, rot=0) -> None:
        g = f'<a:prstGeom prst="{shape}"><a:avLst/></a:prstGeom>' if shape else geom(r, w, h)
        f = fill_xml or solid(fill, alpha)
        d = '<a:prstDash val="dash"/>' if dash else ""
        ln = f'<a:ln w="{emu(lw)}">{solid(line)}{d}</a:ln>' if line else "<a:ln><a:noFill/></a:ln>"
        i = self.nid()
        self.parts.append(
            f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{name} {i}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
            f'<p:spPr>{xfrm(x, y, w, h, rot)}{g}{f}{ln}{SHADOW if shadow else ""}</p:spPr>{text or ""}</p:sp>')

    def text(self, x, y, w, h, paras, size=24, color=INK, font=F_B, name="文字", **kw) -> None:
        i = self.nid()
        self.parts.append(
            f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{name} {i}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
            f'<p:spPr>{xfrm(x, y, w, h)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
            f'{body(paras, size, color, font, **kw)}</p:sp>')

    def line(self, x1, y1, x2, y2, color=SLATE, width=3, arrow=True, dash=False) -> None:
        d = '<a:prstDash val="dash"/>' if dash else ""
        tail = '<a:tailEnd type="triangle" w="med" len="med"/>' if arrow else ""
        i = self.nid()
        self.parts.append(
            f'<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="{i}" name="{"矢印" if arrow else "線"} {i}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>'
            f'<p:spPr>{xfrm(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1), 0, x2 < x1, y2 < y1)}'
            f'<a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
            f'<a:ln w="{emu(width)}" cap="flat">{solid(color)}{d}{tail}</a:ln></p:spPr></p:cxnSp>')

    def pic(self, src, x, y, w, h, r=16, pos=(0.5, 0.5), line=EDGE, lw=1.5, fit="cover", descr=None) -> None:
        path = src if isinstance(src, Path) else IMG / src
        svg = ""
        if path.suffix.lower() == ".svg":  # SVG は PNG（古い PowerPoint 用）と組で入れる
            svg_rid = self.rel(f"../media/{self.media.add(path)}")
            svg = ('<a:extLst><a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">'
                   f'<asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="{svg_rid}"/>'
                   '</a:ext></a:extLst>')
            path = path.with_suffix(".png")
        nw, nh = Image.open(path).size
        crop = ""
        if fit == "cover":
            s = max(w / nw, h / nh)
            pw, ph = nw * s, nh * s
            l, rr = (pw - w) * pos[0] / pw, (pw - w) * (1 - pos[0]) / pw
            t, b = (ph - h) * pos[1] / ph, (ph - h) * (1 - pos[1]) / ph
            if max(l, rr, t, b) > 1e-4:
                crop = f'<a:srcRect l="{int(l * 100000)}" t="{int(t * 100000)}" r="{int(rr * 100000)}" b="{int(b * 100000)}"/>'
        else:  # contain
            s = min(w / nw, h / nh)
            x, y, w, h = x + (w - nw * s) / 2, y + (h - nh * s) / 2, nw * s, nh * s
        rid = self.rel(f"../media/{self.media.add(path)}")
        ln = f'<a:ln w="{emu(lw)}">{solid(line)}</a:ln>' if line else ""
        i = self.nid()
        self.parts.append(
            f'<p:pic><p:nvPicPr><p:cNvPr id="{i}" name="画像 {i}" descr="{escape(descr or path.name)}"/>'
            f'<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
            f'<p:blipFill><a:blip r:embed="{rid}">{svg}</a:blip>{crop}<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
            f'<p:spPr>{xfrm(x, y, w, h)}{geom(r, w, h)}{ln}</p:spPr></p:pic>')

    # ------------------------------------------------------------ 組み合わせた部品
    def card(self, x, y, w, h, fill=CARD, line=EDGE, r=18, shadow=True, name="カード") -> None:
        self.rect(x, y, w, h, fill=fill, line=line, r=r, shadow=shadow, name=name)

    def chip(self, x, y, label, fill=None, color=NAVY, size=18, font=F_H, h=30, padx=12, r=6, line=None, alpha=None, w=None) -> float:
        """字の入った札。幅を返す。"""
        w = w or math.ceil(tw(label, size, font) + 2 * padx)
        self.rect(x, y, w, h, fill=fill, line=line, r=r, alpha=alpha, name="札",
                  text=body(label, size, color, font, align="c", anchor="c", lh=round(size * 1.3), wrap_text=False))
        return w

    def door(self, x, y, n, s=58) -> None:
        """番号の札。ゲームの答えのドア（青い四角に白い数字）の形。"""
        self.rect(x, y, s, s, fill=BLUE, line=INK, lw=3, r=12, shadow=True, name="番号",
                  text=body(str(n), 34, INK, F_T, align="c", anchor="c", lh=44, wrap_text=False))

    def square(self, x, y, s, color) -> None:
        self.rect(x, y, s, s, fill=color, r=s * 0.22, name="印")

    def belt(self, x, y, w) -> None:
        """手順の写真の下に敷くベルトコンベア（ロゴの下のコンベアと同じ、黄色い破線）。"""
        self.rect(x, y, w, 26, fill="1C2D63", line="3D529A", r=13, name="コンベア")
        self.line(x + 34, y + 13, x + w - 34, y + 13, YEL, 4, arrow=False, dash=True)
        for cx in (x + 13, x + w - 13):
            self.rect(cx - 6, y + 7, 12, 12, fill="6F83C4", shape="ellipse", name="コンベアの軸")

    def lane(self, x, y, w, h, label, fill, color) -> None:
        """図の帯のラベル。1 字ずつ改行して積む（PowerPoint の縦書きは、かなが横に倒れるため）。"""
        stacked = "\n".join("丨" if c == "ー" else c for c in label)
        self.rect(x, y, w, h, fill=fill, r=12, name="帯",
                  text=body(stacked, 24, color, F_T, align="c", anchor="c", lh=32, wrap_text=False))

    def who(self, x, y, kind) -> float:
        """図の箱の上の「どこで動くか」の札。幅を返す。"""
        if kind == "game":
            self.rect(x, y, 134, 30, fill="0A1230", line="4A5FA8", r=6, name="札")
            self.pic("logo.png", x + 12, y + 7, 110, 16, r=0, line=None, fit="contain", descr="TESTOPIA")
            return 134
        if kind in ("cloudrun", "firebase"):
            label, file = {"cloudrun": ("Cloud Run", "cloud-run.svg"), "firebase": ("Firebase", "firebase-logomark.svg")}[kind]
            w = math.ceil(42 + tw(label, 18, F_H) + 12)
            self.rect(x, y, w, 32, fill="FFFFFF", r=6, name="札")
            self.pic(LOGOS / file, x + 8, y + 4, 24, 24, r=0, line=None, fit="contain", descr=label)
            self.text(x + 40, y, w - 44, 32, label, 18, "3C4043", F_H, anchor="c", lh=24, wrap_text=False)
            return w
        label, fill = kind
        return self.chip(x, y, label, fill)

    def header(self, title, tag=None, sub=None) -> None:
        if tag:
            self.chip(96, 60, tag, fill=None, color=YEL, size=22, h=40, padx=16, r=8, line=YEL)
        self.text(96, 110, 1728, 96, title, 72, INK, F_T, lh=96, name="タイトル")
        if sub:
            self.text(96, 216, 1728, 48, sub, 32, SKY, F_H, lh=48, name="副題")

    def footer(self) -> None:
        self.pic("logo.png", 96, 1012, 177, 26, r=0, line=None, fit="contain", descr="TESTOPIA")
        self.text(1624, 1008, 200, 34, f"{self.number} / {TOTAL}", 22, SUB, F_H, align="r", anchor="c", lh=30, name="ページ番号",
                  page_field=True)

    def table(self, x, y, widths, rows, lh=32, mar=(22, 16, 14, 14)) -> None:
        """rows は (高さ, [セル…])。セルは (文字, 大きさ, 色, 字, 地の色)。mar はセルの余白（左, 右, 上, 下）。
        行の高さは最小の高さで、文が折り返せば PowerPoint が広げる。"""
        grid = "".join(f'<a:gridCol w="{emu(w)}"/>' for w in widths)
        trs = []
        for k, (h, cells) in enumerate(rows):
            tcs = []
            for text, size, color, font, fill in cells:
                ppr = f'<a:pPr algn="l"><a:lnSpc><a:spcPts val="{int(lh * 50)}"/></a:lnSpc></a:pPr>'
                inner = f"<a:r>{rpr(size, color, font, False)}<a:t>{escape(text)}</a:t></a:r>" if text else ""
                bottom = (f'<a:lnB w="{emu(1.5)}">{solid(EDGE)}</a:lnB>' if k < len(rows) - 1 else '<a:lnB w="0"><a:noFill/></a:lnB>')
                tcs.append(
                    f'<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>{ppr}{inner}{rpr(size, color, font, False, "a:endParaRPr")}</a:p></a:txBody>'
                    f'<a:tcPr marL="{emu(mar[0])}" marR="{emu(mar[1])}" marT="{emu(mar[2])}" marB="{emu(mar[3])}" anchor="t">'
                    f'<a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT>{bottom}'
                    f'{solid(fill)}</a:tcPr></a:tc>')
            trs.append(f'<a:tr h="{emu(h)}">{"".join(tcs)}</a:tr>')
        i = self.nid()
        total_h = sum(h for h, _ in rows)
        self.parts.append(
            f'<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{i}" name="表 {i}"/><p:cNvGraphicFramePr>'
            f'<a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
            f'{xfrm(x, y, sum(widths), total_h, tag="p:xfrm")}<a:graphic>'
            f'<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>'
            f'<a:tblPr firstRow="1"/><a:tblGrid>{grid}</a:tblGrid>{"".join(trs)}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>')

    # ------------------------------------------------------------ 書き出し
    def xml(self) -> str:
        bg = f"<p:bg><p:bgPr>{grad([(0, BG_TOP, 100), (100, BG_BOTTOM, 100)])}<a:effectLst/></p:bgPr></p:bg>"
        return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:sld {NS}><p:cSld>{bg}<p:spTree>'
                '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm>'
                '<a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
                f'{"".join(self.parts)}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')

    def rels_xml(self, layout: str) -> str:
        items = [f'<Relationship Id="rId1" Type="{REL}/slideLayout" Target="{layout}"/>']
        items += [f'<Relationship Id="{rid}" Type="{REL}/image" Target="{t}"/>' for rid, t in self.rels]
        return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{"".join(items)}</Relationships>')


# ================================================================ 各ページ
SONNET = ("Claude Sonnet 5.5", BLUE)
OPUS = ("Claude Opus 5.5", ORG)
HAIKU = ("Claude Haiku 5.5", ORG)


def p01(s: Slide) -> None:
    s.pic("cover.jpg", 0, 0, 1920, 1080, r=0, line=None, descr="TESTOPIA のサムネイル")
    s.rect(0, 600, 1920, 480, fill_xml=grad([(0, "060D26", 0), (55, "060D26", 78), (100, "060D26", 96)]), name="下の影")
    x = 96
    for label in ("小学生向け 3Dクイズランナー", "1人/2人ローカルプレイ・オンライン対戦", "Windows"):
        x += s.chip(x, 962, label, fill="FFFFFF", alpha=12, color=INK, size=28, h=60, padx=24, r=10, line="8FA3DA") + 16
    s.text(1324, 944, 500, 36, "ゲームクリエイター甲子園2026 応募作品", 24, INK, F_H, align="r", lh=36, wrap_text=False)
    w = math.ceil(tw("審査用資料", 24, F_T) + 40)
    s.chip(1824 - w, 986, "審査用資料", fill=YEL, color=NAVY, size=24, font=F_T, h=40, r=8, w=w)


def strip(s: Slide, y, h, frames, w, gap, caption_size=30) -> None:
    """番号つきの写真を横に並べ、下にコンベアと説明を置く。frames は (画像, 位置, 見出し, 補足)。"""
    for i, (src, pos, title, sub) in enumerate(frames):
        x = 96 + i * (w + gap)
        if src == "result_card.jpg":  # 縦長の画面は、暗い枠の中に全体を入れる
            s.rect(x, y, w, h, fill="0A1230", line=EDGE, r=16, name="画像の枠")
            s.pic(src, x, y + 12, w, h - 24, r=8, line=None, fit="contain")
        else:
            s.pic(src, x, y, w, h, pos=pos)
        s.door(x - 12, y - 16, i + 1)  # 写真の角に少しはみ出して置く（画面の中身を隠さない）
        lines = title.count("\n") + 1
        s.text(x, y + h + 74, w, 42 * lines, title, caption_size, INK, F_H, lh=42)
        if sub:
            s.text(x, y + h + 74 + 42 * lines + 4, w, 36, sub, 24, SUB, lh=36)
    s.belt(96, y + h + 24, 1728)


def p02(s: Slide) -> None:
    s.header("迫り来る壁の正解のドアを突き破れ！", "分かりやすさ", "説明を読まなくても、最初の壁で遊び方が分かる。")
    strip(s, 334, 350, [
        ("pv_wall_fall.jpg", (0.5, 0.5), "空から問題の壁が落ちてくる", None),
        ("pv_choose.jpg", (0.5, 0.5), "答えのドアを選んで走る", None),
        ("pv_bonk.jpg", (0.5, 0.5), "間違えると死ぬ", "ハートが 1 つ減る"),
        ("pv_break.jpg", (0.5, 0.5), "正解のドアを突き破ると\n次の問題へ", None),
    ], 414, 24)


def p03(s: Slide) -> None:
    s.header("AIが毎回違う問題を出す", None, "学年・教科・難易度を選ぶと、AI がその場で 10 問を作る。")
    s.pic("preload.jpg", 96, 300, 960, 540)
    s.text(96, 854, 960, 36, "準備画面：AI が問題を作っているところ", 24, SUB, lh=36)
    items = [("小1〜小6 × 5 教科 × 3 つの難易度", "算数・国語・理科・社会・英語", 160),
             ("遊ぶたびに、違う問題", "出題済みの問題と比べて似た問題や同じ問題は出さない", 160),
             ("壁のスピードは、問題ごとに自動で決まる", "文の長さ・学年・計算の手数・プレイヤーの正答率から\nAIが決定する", 180)]
    y = 300
    for title, text, h in items:
        s.card(1096, y, 728, h)
        s.square(1124, y + 38, 18, YEL)
        s.text(1158, y + 24, 646, 46, title, 30, INK, F_H, lh=46)
        s.text(1158, y + 78, 646, h - 90, text, 24, BODY, lh=38)
        y += h + 20


def node(s: Slide, x, y, w, h, who, title, text, size=20, lh=30) -> None:
    """図の箱：だれが動かすかの札・見出し・本文。"""
    s.card(x, y, w, h, r=14)
    top = y + 16
    if who:
        s.who(x + 16, top, who)
        top += 40
    s.text(x + 16, top, w - 32, 38, title, 26, INK, F_T, lh=38)
    s.text(x + 16, top + 42, w - 30, h - (top - y) - 48, text, size, BODY, lh=lh)


def label(s: Slide, x, y, text, align="c", w=200) -> None:
    left = {"c": x - w / 2, "l": x, "r": x - w}[align]
    s.text(left, y, w, 28, text, 18, SUB, F_H, align=align, lh=28, wrap_text=False, name="矢印の説明")


def p04(s: Slide) -> None:
    s.header("現在の問題生成ライン", "独自性・突き詰め")
    cw, gap = 287, 54
    xs = [172 + i * (cw + gap) for i in range(5)]
    r1, r2, r3, rh = 250, 530, 790, 200
    s.lane(96, r1, 52, rh, "試合ごと", YEL, NAVY)
    s.lane(96, r2, 52, r3 + 140 - r2, "毎週", "24376F", YEL)
    # 上の段：試合ごと（左から右）
    node(s, xs[0], r1, cw, rh, "game", "試合開始", "学年・教科・難易度を選ぶ\n新作は 10 問中 N 問")
    node(s, xs[1], r1, cw, rh, "cloudrun", "関所（サーバー）", "月の予算の進み具合で\n出題するN問の数を決める")
    node(s, xs[2], r1, cw, rh, SONNET, "新作を作る", "143 単元の設計図で、\n6 本同時に 24 候補")
    node(s, xs[3], r1, cw, rh, "game", "端末でチェック", "形式・重複・偏りを検査\n正解を伏せてClaude が解き直し、整合性を検査する")
    s.card(xs[4], r1, cw, rh, r=14)
    s.text(xs[4] + 16, r1 + 14, cw - 32, 38, "出題（壁）", 26, INK, F_T, lh=38)
    s.pic("wall_thumb.jpg", xs[4] + 16, r1 + 58, cw - 32, 98, r=8)
    s.text(xs[4] + 16, r1 + 162, cw - 32, 30, "解説も AI が書く", 20, BODY, lh=30)
    for i in range(4):
        s.line(xs[i] + cw + 7, r1 + 100, xs[i + 1] - 7, r1 + 100)
    label(s, xs[0] + cw + gap / 2, r1 + 64, "N 問")
    # 上と下をつなぐ
    s.line(xs[4] + cw / 2, r1 + rh + 8, xs[4] + cw / 2, r2 - 8)
    label(s, xs[4] + cw / 2 - 14, r1 + rh + 26, "作った問題", "r")
    s.line(xs[0] + cw / 2, r2 - 8, xs[0] + cw / 2, r1 + rh + 8)
    label(s, xs[0] + cw / 2 + 14, r1 + rh + 26, "残り 10−N 問", "l")
    # 下の段：毎週（右から左）
    node(s, xs[4], r2, cw, rh, "game", "候補として送る", "作った問題と\n「良い・悪い」の評価を\n通信の合間に送る")
    node(s, xs[3], r2, cw, rh, None, "判定待ち", "試合と補充の問題が並ぶ\n「悪い」がつけばすぐ外し\n「良い」が多い順に判定へ")
    node(s, xs[2], r2, cw, rh, OPUS, "毎週月曜 判定", "正解を伏せてAIが解き直し、\n合えば合格\nこれまでの合格率 **89.1%**")
    node(s, xs[1], r2, cw, rh, "firebase", "共有バンク", "現在 **16,663 問**\nうち 4,456 問は試合から\n変わった分を各端末へ")
    node(s, xs[0], r2, cw, rh, "game", "ストック", "共有バンクからダウンロード\nした問題を保存する")
    for i in range(4):
        s.line(xs[i + 1] - 7, r2 + 100, xs[i] + cw + 7, r2 + 100)
    for i, text in ((2, "判定"), (1, "合格"), (0, "同期")):
        label(s, xs[i] + cw + gap / 2, r2 + 64, text)
    # いちばん下
    node(s, xs[2], r3, cw, 140, None, "使わない", "**2,189 問**\n不合格や「悪い」の問題")
    s.line(xs[2] + cw / 2, r2 + rh + 8, xs[2] + cw / 2, r3 - 8)
    label(s, xs[2] + cw / 2 + 14, r2 + rh + 16, "不合格", "l")
    wide = xs[4] + cw - xs[3]
    s.card(xs[3], r3, wide, 140, r=14)
    w = s.who(xs[3] + 16, r3 + 18, HAIKU)
    s.text(xs[3] + 16 + w + 14, r3 + 13, 300, 38, "月曜 3:00 補充", 26, INK, F_T, lh=38)
    s.text(xs[3] + 16, r3 + 60, wide - 32, 64, "足りない区分（教科×学年×難易度）の問題を作る\n共有バンクの 12,207 問がここから", 20, BODY, lh=30)
    s.line(xs[3] + cw / 2, r3 - 8, xs[3] + cw / 2, r2 + rh + 8)
    label(s, xs[3] + cw / 2 + 14, r2 + rh + 16, "足りない区分を補充", "l")


def role(s: Slide, x, y, w, h, who, title, paras, size=21, lh=31) -> None:
    """AI の役割の箱。paras は段落のリスト。"""
    s.card(x, y, w, h, r=16)
    s.who(x + 20, y + 18, who)
    s.text(x + 20, y + 54, w - 40, 44, title, 30, INK, F_T, lh=44)
    s.text(x + 20, y + 102, w - 38, h - 112, paras, size, BODY, lh=lh, gap=4)


def p05(s: Slide) -> None:
    s.header("試合中の AI の役割", "突き詰め")
    xs, cw = [172, 760, 1348], 476
    r1, h1, r2, h2 = 244, 280, 586, 350
    s.lane(96, r1, 52, h1, "試合ごと", YEL, NAVY)
    s.lane(96, r2, 52, h2, "裏で", "24376F", YEL)
    role(s, xs[0], r1, cw, h1, SONNET, "① 新作を作る", [
        "単元を 6 本に振り分け、6 本同時に 4 問ずつ、合計 24 候補を作る",
        "問題・選択肢・正解・解説・ジャンル・答えるのにかかる時間の予測まで",
        "**最初の 1 問まで 約 2 秒**"])
    role(s, xs[1], r1, cw, h1, ("Claude Sonnet 5.5（別の呼び出し）", BLUE), "② 正解を確かめる", [
        "正解を伏せて 10 問を解き直し、登録の正解と合うか・その学年で習う内容かを判定",
        "合わない問題は、正解を直さずに外す（AI に正解を書き換えさせない）",
        "**約 5 秒**"])
    role(s, xs[2], r1, cw, h1, ("ゲーム", "FFFFFF"), "出題（壁）", [
        "確かめた 10 問を壁にして出す",
        "外した分は、確認済みの共有バンクの問題で埋める"])
    for i, texts in ((0, ("端末で検査", "先着 10 問")), (1, ("合格した問題", None))):
        mid = xs[i] + cw + 56
        s.line(xs[i] + cw + 12, r1 + h1 / 2, xs[i + 1] - 12, r1 + h1 / 2)
        label(s, mid, r1 + h1 / 2 - 40, texts[0])
        if texts[1]:
            label(s, mid, r1 + h1 / 2 + 12, texts[1])
    s.line(xs[2] + cw / 2, r1 + h1 + 8, xs[2] + cw / 2, r2 - 8)
    label(s, xs[2] + cw / 2 + 14, r1 + h1 + 17, "出題のあいだ", "l")
    role(s, xs[0], r2, cw, h2, ("関所（サーバー）", SLATE), "どの役割にも共通", [
        "モデルは用途ごとにサーバーが決める（ゲームからは選べない）",
        "すべての依頼の先頭に、子ども向けの安全の指示を必ず付ける",
        "AI に送るのは出題の条件だけ。名前などは送らない",
        "**月 40 ドルまで（1 試合 約 14.5 円）**"])
    role(s, xs[1], r2, cw, h2, SONNET, "④ 問題を評価する", [
        "**4 試合に 1 回**",
        "AI が作った問題を「良い / 悪い」で判定",
        "「悪い」はすぐ外し、次の問題作りで避ける例にする",
        "「良い」は、毎週の判定の順番を早める票になる"])
    role(s, xs[2], r2, cw, h2, SONNET, "③ 解説を書く", [
        "**出題のあいだに**",
        "10 問の解説をまとめて書く。なぜその答えになるかを 50〜100 字で、その学年の言葉で",
        "リザルト画面で全問の解説を読める",
        "**約 7 秒**"])


def p06(s: Slide) -> None:
    s.header("毎週の AI と、モデルの選び方", "突き詰め")
    xs, cw = [172, 596, 1020, 1444], 380
    r1, h1, r2, h2 = 250, 310, 610, 320
    s.lane(96, r1, 52, h1, "毎週", "24376F", YEL)
    s.lane(96, r2, 52, h2, "選び方", YEL, NAVY)
    # Firebase のロゴは同じ場所に 2 つ置けないので、このページは名前の札にする
    firebase = ("Firebase", GRN)
    role(s, xs[0], r1, cw, h1, HAIKU, "⑤ 足りない問題を補充", [
        "**月曜 3:00**", "問題が足りない区分（教科×学年×難易度）を作る", "Batch API で料金は半額", "**月 5 ドルまで**"], 20, 30)
    role(s, xs[1], r1, cw, h1, firebase, "判定待ち", [
        "試合と補充の問題が並ぶ", "「悪い」がつけばすぐ外す", "「良い」が多い順に判定へ"], 20, 30)
    role(s, xs[2], r1, cw, h1, OPUS, "⑥ 合否を判定", [
        "**月曜 4:00 と 12:00**", "正解を伏せて 1 問ずつ解き直す", "正解なし・複数・あいまい・事実の誤り・学年外・不適切も確かめる",
        "**1 問 約 0.4 円・月 20 ドルまで**"], 20, 30)
    role(s, xs[3], r1, cw, h1, firebase, "共有バンク", [
        "合格した問題だけが入る", "変わった分を各端末へ届ける", "何回出しても追加の費用はかからない"], 20, 30)
    for i in range(3):
        s.line(xs[i] + cw + 8, r1 + 155, xs[i + 1] - 8, r1 + 155)
    label(s, xs[2] + cw + 22, r1 + 116, "合格")
    role(s, xs[0], r2, cw, h2, SONNET, "作るのは Sonnet", [
        "Gemini 3.6 Flash と、同じ 42 の依頼で比べた", "2 人の AI 採点者がともに合格", "**Sonnet 82.6%・Gemini 82.5%**", "最初の 1 問まで 約 2 秒"], 20, 30)
    role(s, xs[1], r2, cw, h2, HAIKU, "Haiku は補充だけ", [
        "考える時間が長く、最初の 1 問まで 約 17 秒", "考えずに作らせると合格 70%", "**→ 急がない毎週の補充に使う**"], 20, 30)
    role(s, xs[2], r2, cw, h2, OPUS, "判定は Opus", [
        "作った Sonnet・Haiku より一段強いモデルで確かめる", "作った AI と、確かめる AI を分ける", "Batch API で料金は半額"], 20, 30)
    role(s, xs[3], r2, cw, h2, ("利用規約", SLATE), "Gemini から Claude へ", [
        "Gemini は 18 歳未満向けのサービスでは使えない", "Claude は、子ども向けの安全対策を条件に使える", "**切り替える前に品質を比べた**"], 20, 30)


def pillar_head(s: Slide, x, y, w, title, color) -> None:
    s.square(x + 32, y + 36, 34, color)
    s.text(x + 82, y + 26, w - 110, 54, title, 36, INK, F_T, lh=54)


def p07(s: Slide) -> None:
    s.header("止まらない・被らない・間違えない", "突き詰め・完成度", "子どもが遊ぶゲームで、AI の問題を安心して出すための 3 つの守り。")
    cols = [
        ("止まらない", YEL, ["AI → 共有バンク → 端末の問題 → 同梱の 12,601 問 → 自動の計算問題の順に切り替える",
                         "生成は 30 秒で打ち切り、届いた問題で先へ進む",
                         "月の予算の進み具合で、新しく作る数（10 問中 0〜10）をサーバーが決め、残りはストックで埋める"]),
        ("被らない", BLUE, ["これまでの問題（最大 1000 件）と同じ問題は出さない。同じ単元をずっと禁止にはしない",
                        "同じ設定の直近 2 回とは、数字を変えただけ・言い換えただけの問題も外す",
                        "1 回の 10 問の中でも似た問題を外し、同じジャンルは 2 問まで"]),
        ("間違えない", RED, ["問題 60 字・選択肢 20 字以内、2 択か 4 択、選択肢の重複なし",
                         "正解を伏せ、別の AI 呼び出しで解き直す",
                         "答えが合わない・学年に合わない問題は、直さずに外す"]),
    ]
    y, h, w = 296, 500, 560
    for i, (title, color, items) in enumerate(cols):
        x = 96 + i * 584
        s.card(x, y, w, h)
        pillar_head(s, x, y, w, title, color)
        # 1 列の表にして、項目の間の線が文の行数に合わせて動くようにする
        s.table(x + 30, y + 94, [w - 56], [(68, [(item, 25, BODY, F_B, None)]) for item in items], lh=40, mar=(0, 0, 14, 14))
    s.rect(96, 820, 1728, 124, fill="113B3C", line=GRN, r=18, shadow=True, name="カード")
    s.chip(128, 856, "良くなる", fill=GRN, color=NAVY, size=28, font=F_T, h=52, padx=22, r=10)
    s.text(322, 840, 1470, 84, "プレイヤーと AI の「良い / 悪い」の評価を集め、「悪い」はすぐ外して次の問題作りでも避け、\n「良い」が多い問題から Claude が先に判定する",
           26, INK, F_H, lh=42)


def p08(s: Slide) -> None:
    s.header("学年に合った問題を、安全に", "完成度", "子どもが遊ぶことを前提に、問題・名前・費用の 3 つを守る。")
    y, h, w = 296, 650, 560
    cols = [("問題", BLUE, "子ども向けに使える AI（Claude）を選び、学年ごとの単元・考え方・よくある間違いを渡す。正解は別の呼び出しで確かめ、全問に解説をつける。"),
            ("名前", ORG, "オンラインの名前は 12 文字まで、NG ワードを検査。サイコロで決める二つ名（5000 通り以上）でも遊べる。"),
            ("費用", GRN, "AI の鍵はゲームに置かず、自前のサーバーで 1 日・1 か月・1 台ごとの使用量を管理する。")]
    for i, (title, color, text) in enumerate(cols):
        x = 96 + i * 584
        s.card(x, y, w, h)
        pillar_head(s, x, y, w, title, color)
        s.text(x + 30, y + 104, w - 56, 160, text, 23, BODY, lh=38)
    # 問題：リザルト画面（縦長なので、暗い枠の中に全体を入れる）
    s.rect(128, y + h - 32 - 270, 496, 270, fill="0A1230", line=EDGE, r=12, name="画像の枠")
    s.pic("result_card.jpg", 128, y + h - 32 - 270 + 8, 496, 254, r=6, line=None, fit="contain")
    # 名前：オンライン対戦のトップ
    s.pic("online_home.jpg", 712, y + h - 32 - 270, 496, 270, r=12, pos=(0.5, 0.2))
    # 費用：鍵の置き場所の図
    x, bw = 1296, 496
    top = y + 262
    s.rect(x, top, bw, 56, fill="24376F", r=10, name="箱", text=body("ゲーム", 24, INK, F_H, align="c", anchor="c", lh=32))
    s.rect(x + bw / 2 - 13, top + 64, 26, 16, fill=SLATE, shape="triangle", rot=10800000, name="三角")
    s.rect(x, top + 88, bw, 92, fill=YEL, r=10, name="箱")
    s.text(x, top + 98, bw, 38, "自前のサーバー", 26, NAVY, F_T, align="c", lh=38)
    s.text(x, top + 138, bw, 32, "AI の鍵・1 日と 1 台ごとの上限", 20, NAVY, F_H, align="c", lh=32)
    s.rect(x + bw / 2 - 13, top + 188, 26, 16, fill=SLATE, shape="triangle", rot=10800000, name="三角")
    s.rect(x, top + 212, bw, 56, fill="24376F", r=10, name="箱", text=body("AI（Claude）", 24, INK, F_H, align="c", anchor="c", lh=32))
    s.rect(x, top + 292, bw, 64, fill="113B3C", line=GRN, r=10, name="箱",
           text=body("上限に達しても、用意した問題で続けられる", 22, "8EE6B8", F_H, align="c", anchor="c", lh=30))


def p09(s: Slide) -> None:
    s.header("準備 → 10 問 → ボス壁 → 振り返り", "分かりやすさ・成立")
    strip(s, 256, 310, [
        ("preload_done.jpg", (0.5, 0.5), "AI が 10 問を準備", "揃うまでの進み具合を見せる"),
        ("wall_q.jpg", (0.5, 0.5), "2 択の壁を 9 つ", "正解のドアを突き破って進む"),
        ("boss.jpg", (0.5, 0.5), "10 問目は 4 択のボス壁", "大きな壁を最後に突破"),
        ("result_card.jpg", (0.5, 0.5), "振り返り", "正答率・連続正解・タイム・解説"),
    ], 414, 24)
    s.card(96, 808, 1728, 124)
    s.text(136, 834, 160, 72, "♥♥♥", 50, RED, F_T, anchor="c", lh=72, wrap_text=False)
    s.text(322, 834, 1470, 72, "ハートは 3 つ。不正解のドアと壁で 1 つ減り、0 になるか海に落ちると脱落。", 30, INK, F_H, anchor="c", lh=44)


def p10(s: Slide) -> None:
    s.header("答えで競って、体でぶつかる", "面白さ・成立", "ローカル 2 人プレイは、1 台のキーボードで。")
    items = [("push.jpg", (0.5, 0.5), "押し合い", "相手のほうへ踏ん張って、一押し"),
             ("saw.jpg", (0.5, 0.5), "8 連チップソー", "遅れると、後ろの刃に巻き込まれる"),
             ("ghost.jpg", (0.4, 0.5), "ゴーストシャーク", "脱落した人は、サメに乗って相手を狙う"),
             ("pv_tower.jpg", (0.5, 0.5), "スコアタワー", "正解数と残りのハートで点数が決まる")]
    y, w, ih, h = 300, 414, 380, 560
    for i, (src, pos, title, sub) in enumerate(items):
        x = 96 + i * 438
        s.card(x, y, w, h)
        s.pic(src, x, y, w, ih, r=(18, 0), pos=pos, line=None)
        s.rect(x, y, w, h, line=EDGE, r=18, name="カードのふち")
        s.text(x + 26, y + ih + 22, w - 52, 46, title, 32, INK, F_T, lh=46)
        s.text(x + 26, y + ih + 76, w - 50, 72, sub, 22, SUB, lh=34)


def p11(s: Slide) -> None:
    s.header("離れていても、同じ壁に挑む", "面白さ・完成度", "オンライン対戦は、ランダムマッチとともだちコードの 2 つ。")
    items = [("ランダムマッチ", "同じ教科・学年の近い相手を探す（20 秒で条件を広げる）"),
             ("ともだちと あそぶ", "5 文字のコードで待ち合わせ"),
             ("ヘリで合流して VS", "乗り込み → 離陸 → 合流 → VS カットイン"),
             ("滑らかな通信", "ホストが判定し、相手は予測と補間で動く。切れても再接続")]
    y = 296
    for title, text in items:
        s.card(96, y, 704, 151)
        s.square(126, y + 46, 18, YEL)
        s.text(160, y + 32, 610, 46, title, 30, INK, F_H, lh=46)
        s.text(160, y + 82, 616, 36, text, 23, BODY, lh=34)
        y += 151 + 16
    shots = [("online_home.jpg", "トップ：教科と学年を選ぶ"), ("online_friend.jpg", "ともだちコード"),
             ("online_heli.jpg", "ヘリで合流"), ("online_vs.jpg", "VS カットイン")]
    for i, (src, cap) in enumerate(shots):
        x, yy = 840 + (i % 2) * 504, 296 + (i // 2) * 334
        s.pic(src, x, yy, 480, 270)
        s.text(x, yy + 278, 480, 34, cap, 24, INK, F_H, lh=34)


def p12(s: Slide) -> None:
    s.header("説明書要らずのチュートリアル", "分かりやすさ", "1P 実践コース（約 3 分）と、ローカル 2P 実践コース（約 6 分）。")
    strip(s, 336, 330, [  # 画面の写真なので、左右をほとんど切らない比率にする
        ("tut_keyboard.jpg", (0.5, 0.5), "使うキーを 1 画面で", "キーボードの絵で、押すキーを示す"),
        ("tut_keys3d.jpg", (0.5, 0.5), "押すキーを頭の上に 3D で", "体を動かしながら 1 つずつ覚える"),
        ("tut_hatena.jpg", (0.5, 0.5), "ハテナが本物のメニューで案内", "カスタマイズの画面を光らせて紹介"),
    ], 560, 24)


def p13(s: Slide) -> None:
    s.header("ステージ丸ごと、遊びの舞台に", "突き詰め・完成度")
    shots = [("crowd.jpg", "試合に合わせて動く観客"), ("pv_heli.jpg", "ヘリのお迎え"), ("pv_logo.jpg", "ベルトコンベアで組み立つタイトルロゴ"),
             ("goal.jpg", "ゴールで待つハテナ"), ("custom.jpg", "帽子とエモートで、自分だけのキャラに"), ("pv_end.jpg", "海の上のスタジアム")]
    w, h = 560, 315
    for i, (src, cap) in enumerate(shots):
        x, y = 96 + (i % 3) * 584, 250 + (i // 3) * 345
        s.pic(src, x, y, w, h, r=18, line=None)
        s.rect(x, y + h - 120, w, 120, r=(0, 18), fill_xml=grad([(0, "050B20", 0), (60, "050B20", 72), (100, "050B20", 90)]), name="写真の下の影")
        s.rect(x, y, w, h, line=EDGE, r=18, name="写真のふち")
        s.text(x + 24, y + h - 54, w - 48, 40, cap, 26, INK, F_H, lh=40, wrap_text=False)


def p14(s: Slide) -> None:
    s.header("作る → 撮って確かめる → 直す", "突き詰め", "ゲームを動かして画面を撮り、前と後を比べてから次へ進む。")
    rows = [("メニュー", "menu_before.jpg", (0.5, 0.5), "menu_after.jpg", (0.5, 0.0)),
            ("ステージ", "stage_before.jpg", (0.5, 0.35), "stage_after.jpg", (0.5, 0.5))]
    w, h = 740, 310
    for i, (name, before, pos_b, after, pos_a) in enumerate(rows):
        y = 296 + i * 334
        s.rect(96, y, 136, h, fill=PANEL, line=EDGE, r=16, name="行の名前",
               text=body(name, 28, INK, F_T, align="c", anchor="c", lh=40, wrap_text=False))
        s.pic(before, 256, y, w, h, pos=pos_b)
        s.chip(276, y + h - 64, "2026 年 4 月", fill="0A1230", alpha=88, color=INK, size=24, h=44, padx=16, r=8, line="5B6FB5")
        s.pic(after, 1084, y, w, h, pos=pos_a)
        s.chip(1104, y + h - 64, "現在", fill=YEL, color=NAVY, size=24, font=F_T, h=44, padx=18, r=8)
        s.rect(1010, y + h / 2 - 30, 60, 60, fill=YEL, shape="ellipse", shadow=True, name="矢印の丸")
        s.rect(1024, y + h / 2 - 15, 32, 30, fill=NAVY, shape="rightArrow", name="矢印")


def p15(s: Slide) -> None:
    s.header("AIの使用箇所", "AI の使用箇所")
    head, a, b = "24376F", "172654", "13204A"
    rows = [("分野", "自分たちが決めた・確かめた・直したこと", "AI に任せたこと", 66),
            ("企画・ルール", "", "―", 66),
            ("問題生成", "出題の範囲と禁止事項、検査と重複を除く決まり、問題の評価",
             "ゲーム中の問題・解説・正解の確認と、共有バンクの判定と補充（Claude）。内蔵の問題の多く（Claude・Gemini）", 98),
            ("プログラム", "仕様と設計、動作の確認、直す点の指示", "コードの多く（Claude Code・Cursor・Codex など）", 66),
            ("3D・動き", "形・見た目・演出", "Blender で組み立てるスクリプト", 66),
            ("音", "曲の選定と要望（テンポ・音の数）、ループの切り出しと音量", "BGM 6 曲（Suno）", 66),
            ("画像", "看板とプラカードの使い方、プラカードの手描きの文字", "火花・GOAL の看板・看板の下地・プラカードの絵", 66),
            ("文章", "台詞の方向づけ（「もっと大人向けに」など）と直し", "チュートリアルとハテナの台詞の下書き（Claude）", 66),
            ("PV・サムネイル", "カットと構図を決めてゲームで撮影。サムネイルは Blender で描き直し", "構図の案（画像生成）、PV の曲（Suno）", 98)]
    table = []
    for k, (c1, c2, c3, h) in enumerate(rows):
        if k == 0:
            table.append((h, [(c, 22, YEL, F_H, head) for c in (c1, c2, c3)]))
        else:
            fill = a if k % 2 else b
            table.append((h, [(c1, 22, INK, F_H, fill), (c2, 22, BODY, F_B, fill), (c3, 22, BODY, F_B, fill)]))
    s.table(96, 240, [250, 680, 798], table)
    s.text(96, 916, 1728, 32, "詳しくは「05_外部素材とAIの使用箇所」へ。算数の 2,262 問は AI を使わない自動生成。", 20, SUB, lh=32)


def p16(s: Slide) -> None:
    s.header("教室でも、スマホでも", "これから", "遊びながら学べる場所を、もっと広げたい。")
    items = [("Android 版の試作", "タッチ操作（仮想スティックとボタン）と、折りたたみスマホの画面に対応して動いている"),
             ("教室での利用", "AI の使用量の上限は「1 回線で 40 人 × 2〜3 クラス」でも止まらない設計")]
    y = 296
    for title, text in items:
        s.card(96, y, 808, 176)
        s.square(126, y + 36, 18, YEL)
        s.text(160, y + 22, 716, 46, title, 30, INK, F_H, lh=46)
        s.text(160, y + 76, 720, 80, text, 24, BODY, lh=38)
        y += 176 + 20
    s.pic("logo.png", 96, 740, 436, 64, r=0, line=None, fit="contain", descr="TESTOPIA")
    s.text(96, 838, 808, 92, [[("AIが出す。", INK), ("キミが走る。", YEL)]], 64, INK, F_T, lh=92, wrap_text=False)
    s.rect(944, 296, 880, 636, fill=PANEL, line=SLATE, lw=3, r=24, dash=True, name="撮影待ちの枠",
           text=body("【撮影予定】Android の実機で遊んでいるところ", 28, SUB, F_H, align="c", anchor="c", lh=42))


# 2026-11-10：8 ページ以降は「作る → 撮って確かめる → 直す」（p14）だけを残した。
# 外したページ（p08〜p13・p15・p16）の関数は残してあるので、ここに足せば戻せる。
PAGES = [p01, p02, p03, p04, p05, p06, p07, p14]
TOTAL = len(PAGES)


# ================================================================ .pptx に入れる
def build(out: Path) -> None:
    zin = zipfile.ZipFile(BASE)
    files = {n: zin.read(n) for n in zin.namelist()}
    pres = files["ppt/presentation.xml"].decode("utf-8")
    pres_rels = files["ppt/_rels/presentation.xml.rels"].decode("utf-8")
    ctypes = files["[Content_Types].xml"].decode("utf-8")
    targets = {}
    for m in re.finditer(r"<Relationship [^>]*>", pres_rels):
        targets[re.search(r'Id="([^"]+)"', m.group(0)).group(1)] = re.search(r'Target="([^"]+)"', m.group(0)).group(1)
    order = re.findall(r'<p:sldId id="(\d+)" r:id="(rId\d+)"/>', pres)
    paths = ["ppt/" + targets[rid] for _, rid in order]
    layout = re.search(r'Target="(\.\./slideLayouts/slideLayout\d+\.xml)"',
                       files[paths[0].replace("slides/", "slides/_rels/") + ".rels"].decode("utf-8")).group(1)
    # 白紙のページが足りない分を足す
    next_id = max(int(i) for i, _ in order) + 1
    next_rid = max(int(r[3:]) for r in targets) + 1
    while len(paths) < len(PAGES):
        n = len(paths) + 1
        path = f"ppt/slides/slide{n}.xml"
        assert path not in files
        pres = pres.replace("</p:sldIdLst>", f'<p:sldId id="{next_id}" r:id="rId{next_rid}"/></p:sldIdLst>')
        pres_rels = pres_rels.replace("</Relationships>", f'<Relationship Id="rId{next_rid}" Type="{REL}/slide" Target="slides/slide{n}.xml"/></Relationships>')
        ctypes = ctypes.replace("</Types>", f'<Override PartName="/{path}" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>')
        paths.append(path)
        next_id, next_rid = next_id + 1, next_rid + 1
    # 白紙のページが多い分は外す（部品は残るが、PowerPoint で保存し直すと消える）
    for (sid, rid), path in list(zip(order, paths))[len(PAGES):]:
        pres = pres.replace(f'<p:sldId id="{sid}" r:id="{rid}"/>', "")
        pres_rels = re.sub(rf'<Relationship Id="{rid}"[^>]*/>', "", pres_rels)
        ctypes = re.sub(rf'<Override PartName="/{re.escape(path)}"[^>]*/>', "", ctypes)
        files.pop(path, None)
        files.pop(path.replace("slides/", "slides/_rels/") + ".rels", None)
    paths = paths[:len(PAGES)]
    media = Media()
    for n, (path, page) in enumerate(zip(paths, PAGES), 1):
        s = Slide(n, media)
        page(s)
        if n > 1:
            s.footer()
        files[path] = s.xml().encode("utf-8")
        files[path.replace("slides/", "slides/_rels/") + ".rels"] = s.rels_xml(layout).encode("utf-8")
    for ext, ct in (("jpg", "image/jpeg"), ("png", "image/png"), ("svg", "image/svg+xml")):
        if f'Extension="{ext}"' not in ctypes:
            ctypes = ctypes.replace("<Default ", f'<Default Extension="{ext}" ContentType="{ct}"/><Default ', 1)
    files["[Content_Types].xml"] = ctypes.encode("utf-8")
    files["ppt/presentation.xml"] = pres.encode("utf-8")
    files["ppt/_rels/presentation.xml.rels"] = pres_rels.encode("utf-8")
    for name, blob in media.blobs.items():
        files[f"ppt/media/{name}"] = blob
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        zout.writestr("[Content_Types].xml", files.pop("[Content_Types].xml"))
        for name, data in files.items():
            zout.writestr(name, data)
    print(f"{out.name}: {len(PAGES)} slides, {len(media.blobs)} media, {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    build(OUT)
