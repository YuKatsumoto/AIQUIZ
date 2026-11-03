"""extract.js の結果（deck.json）から、PowerPoint で編集できる .pptx を組む。

    python -I docs/submission/pdf/to_pptx/run_extract.py <deck.json>
    python -I docs/submission/pdf/to_pptx/build_pptx.py <deck.json> docs/submission/pdf/to_pptx/base.pptx <out.pptx>

- base.pptx は PowerPoint で作った白紙 15 ページ（16:9・960×540 pt、テーマのフォントは Noto Sans JP）。各ページの spTree を差し替える。
- 座標は px（1920×1080）。1 px = 6350 EMU = 0.5 pt。
- 文字は太さごとのフォント名（Noto Sans JP Medium / SemiBold / ExtraBold / Black、700 は Noto Sans JP の太字）。
- 画像は元の画像をそのまま入れて、PowerPoint のトリミング（srcRect）で切り抜く。あとからトリミングを直せる。
"""

import json
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

EMU = 6350
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
NOTO_ASCENT_DESCENT = 1.448  # Noto Sans JP の行の高さ（normal）: (1160 + 288) / 1000
PPT_SLACK = 1.02  # PowerPoint の折り返しが Chrome より早くならないよう、文字の箱を少し広げる

NS = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
REL_IMAGE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"


def emu(v: float) -> int:
    return int(round(v * EMU))


def hexcolor(c: dict) -> str:
    return f"{c['r']:02X}{c['g']:02X}{c['b']:02X}"


def solid(c: dict | None) -> str:
    if not c:
        return "<a:noFill/>"
    alpha = "" if c.get("a", 1) >= 0.999 else f'<a:alpha val="{int(round(c["a"] * 100000))}"/>'
    return f'<a:solidFill><a:srgbClr val="{hexcolor(c)}">{alpha}</a:srgbClr></a:solidFill>'


def font_for(weight: int) -> tuple[str, bool]:
    if weight >= 850:
        return "Noto Sans JP Black", False
    if weight >= 750:
        return "Noto Sans JP ExtraBold", False
    if weight >= 650:
        return "Noto Sans JP", True
    if weight >= 550:
        return "Noto Sans JP SemiBold", False
    if weight >= 450:
        return "Noto Sans JP Medium", False
    return "Noto Sans JP", False


def xfrm(x, y, w, h, rot=0, flip_h=False, flip_v=False, tag="a:xfrm") -> str:
    attrs = ""
    if rot:
        attrs += f' rot="{int(rot)}"'
    if flip_h:
        attrs += ' flipH="1"'
    if flip_v:
        attrs += ' flipV="1"'
    return f'<{tag}{attrs}><a:off x="{emu(x)}" y="{emu(y)}"/><a:ext cx="{max(emu(w), 0)}" cy="{max(emu(h), 0)}"/></{tag}>'


def geometry(radius: list, w: float, h: float) -> str:
    """角丸。4 つの角が同じなら roundRect、上だけ丸いなら round2SameRect。"""
    m = min(w, h)
    if m <= 0 or not any(r > 0.5 for r in radius):
        return '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
    tl, tr, br, bl = radius
    def adj(r):
        return int(min(50000, round(r / m * 100000)))
    if abs(tl - tr) < 0.5 and abs(br - bl) < 0.5 and abs(tl - br) >= 0.5:
        return (f'<a:prstGeom prst="round2SameRect"><a:avLst><a:gd name="adj1" fmla="val {adj(tl)}"/>'
                f'<a:gd name="adj2" fmla="val {adj(br)}"/></a:avLst></a:prstGeom>')
    return f'<a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val {adj(max(radius))}"/></a:avLst></a:prstGeom>'


def shadow_xml(sh: dict | None) -> str:
    if not sh or not sh.get("color"):
        return ""
    import math
    dist = math.hypot(sh["x"], sh["y"])
    direction = (math.degrees(math.atan2(sh["y"], sh["x"])) % 360) if dist else 0
    c = sh["color"]
    return (f'<a:effectLst><a:outerShdw blurRad="{emu(sh["blur"])}" dist="{emu(dist)}" dir="{int(direction * 60000)}" '
            f'algn="ctr" rotWithShape="0"><a:srgbClr val="{hexcolor(c)}"><a:alpha val="{int(round(c["a"] * 100000))}"/>'
            f'</a:srgbClr></a:outerShdw></a:effectLst>')


def line_xml(b: dict | None) -> str:
    if not b:
        return "<a:ln><a:noFill/></a:ln>"
    dash = '<a:prstDash val="dash"/>' if b.get("style") == "dashed" else ""
    return f'<a:ln w="{emu(b["w"])}">{solid(b["color"])}{dash}</a:ln>'


def grad_xml(g: dict) -> str:
    if g["kind"] == "stripes":
        cols = [c for c in g["colors"] if c]
        avg = {k: round(sum(c[k] for c in cols) / len(cols)) for k in "rgb"} if cols else {"r": 238, "g": 241, "b": 247}
        avg["a"] = 1
        return solid(avg)
    stops = "".join(
        f'<a:gs pos="{int(round(s["pos"] * 100000))}"><a:srgbClr val="{hexcolor(s["color"])}">'
        f'<a:alpha val="{int(round(s["color"].get("a", 1) * 100000))}"/></a:srgbClr></a:gs>'
        for s in g["stops"])
    ang = int(((g["angle"] - 90) % 360) * 60000)
    return f'<a:gradFill rotWithShape="1"><a:gsLst>{stops}</a:gsLst><a:lin ang="{ang}" scaled="0"/></a:gradFill>'


class Slide:
    def __init__(self, number: int, media):
        self.number = number
        self.media = media
        self.parts: list[str] = []
        self.next_id = 2
        self.rels: list[tuple[str, str]] = []  # (rId, target)

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

    # ---------------------------------------------------------------- 箱
    def box(self, it: dict) -> None:
        x, y, w, h = it["x"], it["y"], it["w"], it["h"]
        if w < 0.5 or h < 0.5:
            return
        sides = it.get("sides") or {}
        top = sides.get("top")
        others = [sides.get(k) for k in ("right", "bottom", "left")]
        fill = grad_xml(it["grad"]) if it.get("grad") else solid(it.get("fill"))
        inset = it.get("inset")
        if inset and inset.get("spread") and inset.get("color") and not inset.get("blur"):
            s = inset["spread"]
            # 内側の影（inset）の太さを線で表す。線は縁の内外に半分ずつ乗るので、形を線の半分だけ縮める
            self.shape("箱", x + s / 2, y + s / 2, w - s, h - s, geometry([max(0.0, r - s / 2) for r in it["radius"]], w - s, h - s), fill,
                       line_xml({"w": s, "color": inset["color"], "style": "solid"}), shadow_xml(it.get("shadow")))
            return
        if top and not any(others):
            # 上だけの太い線（カードの色の帯）：外側を線の色で塗り、その上に本体を下の角だけ丸めて重ねる
            self.shape("箱の帯", x, y, w, h, geometry(it["radius"], w, h), solid(top["color"]), line_xml(None),
                       shadow_xml(it.get("shadow")))
            r = it["radius"]
            self.shape("箱", x, y + top["w"], w, h - top["w"], geometry([0, 0, r[2], r[3]], w, h - top["w"]),
                       fill, line_xml(None), "")
            return
        self.shape("箱", x, y, w, h, geometry(it["radius"], w, h), fill, line_xml(it.get("border")), shadow_xml(it.get("shadow")))
        for name, b in (("right", sides.get("right")), ("bottom", sides.get("bottom")), ("left", sides.get("left")), ("top", top)):
            if not b or it.get("border"):
                continue
            bx, by, bw, bh = {"right": (x + w - b["w"], y, b["w"], h), "bottom": (x, y + h - b["w"], w, b["w"]),
                              "left": (x, y, b["w"], h), "top": (x, y, w, b["w"])}[name]
            self.shape("線", bx, by, bw, bh, geometry([0, 0, 0, 0], bw, bh), solid(b["color"]), line_xml(None), "")

    def shape(self, name, x, y, w, h, geom, fill, line, effects) -> None:
        i = self.nid()
        self.parts.append(
            f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{name} {i}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
            f'<p:spPr>{xfrm(x, y, w, h)}{geom}{fill}{line}{effects}</p:spPr></p:sp>')

    def triangle(self, it: dict) -> None:
        cx, cy = it["x"] + it["w"] / 2, it["y"] + it["h"] / 2
        if it["dir"] == "down":
            w, h, rot = it["w"], it["h"], 10800000
        else:
            w, h, rot = it["h"], it["w"], 5400000
        i = self.nid()
        self.parts.append(
            f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="三角 {i}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
            f'<p:spPr>{xfrm(cx - w / 2, cy - h / 2, w, h, rot)}<a:prstGeom prst="triangle"><a:avLst/></a:prstGeom>'
            f'{solid(it["color"])}<a:ln><a:noFill/></a:ln></p:spPr></p:sp>')

    def line(self, it: dict) -> None:
        x1, y1, x2, y2 = it["x1"], it["y1"], it["x2"], it["y2"]
        dash = '<a:prstDash val="dash"/>' if it.get("dash") else ""
        tail = '<a:tailEnd type="triangle" w="med" len="med"/>' if it.get("arrow") else ""
        i = self.nid()
        self.parts.append(
            f'<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="{i}" name="矢印 {i}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>'
            f'<p:spPr>{xfrm(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1), 0, x2 < x1, y2 < y1)}'
            f'<a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
            f'<a:ln w="{emu(it["width"])}" cap="flat">{solid(it["color"])}{dash}{tail}</a:ln></p:spPr></p:cxnSp>')

    # ---------------------------------------------------------------- 画像
    def image(self, it: dict) -> None:
        src = Path(it["src"])
        fr = dict(it["frame"])
        radius = it.get("radius") or [0, 0, 0, 0]
        clip = it.get("clip")
        if clip:
            x1, y1 = max(fr["x"], clip["x"]), max(fr["y"], clip["y"])
            x2, y2 = min(fr["x"] + fr["w"], clip["x"] + clip["w"]), min(fr["y"] + fr["h"], clip["y"] + clip["h"])
            if any(abs(a - b) < 1.5 for a, b in ((x1, clip["x"]), (y1, clip["y"]))):
                radius = clip["radius"]
            box = {"x": x1, "y": y1, "w": x2 - x1, "h": y2 - y1}
        else:
            box = fr
        nw, nh = it["nw"] or 1, it["nh"] or 1
        crop = (0.0, 0.0, 0.0, 0.0)
        if it["fit"] == "cover":
            s = max(fr["w"] / nw, fr["h"] / nh)
            pw, ph = nw * s, nh * s
            px0 = fr["x"] + (fr["w"] - pw) * it["pos"][0]
            py0 = fr["y"] + (fr["h"] - ph) * it["pos"][1]
            crop = ((box["x"] - px0) / pw, (box["y"] - py0) / ph,
                    (px0 + pw - box["x"] - box["w"]) / pw, (py0 + ph - box["y"] - box["h"]) / ph)
        elif it["fit"] == "contain":
            s = min(fr["w"] / nw, fr["h"] / nh)
            pw, ph = nw * s, nh * s
            box = {"x": fr["x"] + (fr["w"] - pw) * it["pos"][0], "y": fr["y"] + (fr["h"] - ph) * it["pos"][1], "w": pw, "h": ph}
        rid, svg_rid = self.media.add(self, src)
        src_rect = ""
        if any(abs(c) > 1e-4 for c in crop):
            l, t, r, b = (int(round(c * 100000)) for c in crop)
            src_rect = f'<a:srcRect l="{l}" t="{t}" r="{r}" b="{b}"/>'
        svg = ""
        if svg_rid:
            svg = ('<a:extLst><a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">'
                   f'<asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="{svg_rid}"/>'
                   '</a:ext></a:extLst>')
        i = self.nid()
        self.parts.append(
            f'<p:pic><p:nvPicPr><p:cNvPr id="{i}" name="画像 {i}" descr="{escape(src.name)}"/>'
            f'<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
            f'<p:blipFill><a:blip r:embed="{rid}">{svg}</a:blip>{src_rect}<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
            f'<p:spPr>{xfrm(box["x"], box["y"], box["w"], box["h"])}{geometry(radius, box["w"], box["h"])}</p:spPr></p:pic>')

    # ---------------------------------------------------------------- 文字
    @staticmethod
    def segments(runs: list) -> list[dict]:
        """inline 要素の左右の余白（ml・mr）を、その前の字の字間（extra）に置き換える。"""
        segs: list[dict] = []
        for r in runs:
            seg = dict(r, extra=0.0)
            if r["s"] != "\n" and r.get("ml") and segs and segs[-1]["s"] != "\n":
                last = segs.pop()
                if len(last["s"]) > 1:
                    segs.append(dict(last, s=last["s"][:-1]))
                segs.append(dict(last, s=last["s"][-1], extra=last["extra"] + r["ml"]))
            if r["s"] != "\n" and r.get("mr"):
                if len(r["s"]) > 1:
                    segs.append(dict(seg, s=r["s"][:-1]))
                seg = dict(seg, s=r["s"][-1], extra=r["mr"])
            segs.append(seg)
        return segs

    @classmethod
    def runs_xml(cls, runs: list, slide_number_field: bool = False) -> str:
        merged: list[dict] = []
        for r in cls.segments(runs):
            key = (r["size"], r["weight"], json.dumps(r["color"]), r.get("ls", 0))
            if (merged and merged[-1]["key"] == key and r["s"] != "\n" and merged[-1]["s"] != "\n"
                    and not r["extra"] and not merged[-1]["extra"]):
                merged[-1]["s"] += r["s"]
            else:
                merged.append(dict(r, key=key))
        out = []
        for r in merged:
            face, bold = font_for(r["weight"])
            tracking = r.get("ls", 0) + r["extra"]
            spc = f' spc="{int(round(tracking * 50))}"' if tracking else ""
            rpr = (f'<a:rPr lang="ja-JP" altLang="en-US" sz="{int(round(r["size"] * 50))}" b="{1 if bold else 0}"{spc} dirty="0">'
                   f'{solid(r["color"])}<a:latin typeface="{face}"/><a:ea typeface="{face}"/><a:cs typeface="{face}"/></a:rPr>')
            if r["s"] == "\n":
                out.append(f"<a:br>{rpr}</a:br>")
                continue
            m = re.match(r"^(\d+)( / \d+)$", r["s"]) if slide_number_field else None
            if m:
                out.append(f'<a:fld id="{{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}}" type="slidenum">{rpr}<a:t>{m.group(1)}</a:t></a:fld>')
                out.append(f"<a:r>{rpr}<a:t>{escape(m.group(2))}</a:t></a:r>")
                continue
            out.append(f"<a:r>{rpr}<a:t>{escape(r['s'])}</a:t></a:r>")
        return "".join(out)

    def text(self, it: dict) -> None:
        size = it["size"]
        lh = it["lh"] or size * NOTO_ASCENT_DESCENT
        algn = {"center": "ctr", "right": "r", "end": "r", "justify": "just"}.get(it["align"], "l")
        box, ink = it["box"], it["ink"]
        runs = it["runs"]
        if it["vertical"]:
            # 縦書きの帯のラベル。PowerPoint の縦書き（eaVert）は Noto Sans JP の小さい字でかな・カナが横に倒れるので、
            # 1 字ずつ改行して積む。長音「ー」は縦の棒「丨」にする。字間（letter-spacing）は行の間隔に足す
            x, y, w, h = box["x"], box["y"], box["w"], box["h"]
            chars = [c for c in "".join(r["s"] for r in runs if r["s"] != "\n") if not c.isspace()]
            style = dict(runs[0], ls=0, ml=0, mr=0)
            runs = []
            for k, c in enumerate(chars):
                runs.append(dict(style, s="丨" if c == "ー" else c))
                if k < len(chars) - 1:
                    runs.append(dict(style, s="\n"))
            lh = size + it["runs"][0].get("ls", 0)
            body = f'<a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" anchorCtr="0" rtlCol="0"><a:noAutofit/></a:bodyPr>'
            algn = "ctr"
        else:
            left = min(box["x"], ink["x"])
            right = max(box["x"] + box["w"], ink["x"] + ink["w"])
            w = right - left
            extra = max(6.0, w * (PPT_SLACK - 1))
            x = left - (extra / 2 if algn == "ctr" else extra if algn == "r" else 0)
            w += extra
            half_leading = (lh - size * NOTO_ASCENT_DESCENT) / 2
            y = ink["y"] - half_leading + calibrate(size, lh)
            h = max(it["lines"], 1) * lh
            wrap = "none" if it["nowrap"] else "square"
            body = f'<a:bodyPr wrap="{wrap}" lIns="0" tIns="0" rIns="0" bIns="0" anchor="t" anchorCtr="0" rtlCol="0"><a:noAutofit/></a:bodyPr>'
        is_footer = bool(re.match(r"^\d+ / \d+$", "".join(r["s"] for r in runs).strip()))
        ppr = f'<a:pPr algn="{algn}"><a:lnSpc><a:spcPts val="{int(round(lh * 50))}"/></a:lnSpc><a:spcBef><a:spcPts val="0"/></a:spcBef></a:pPr>'
        last = runs[-1]
        face, bold = font_for(last["weight"])
        end = (f'<a:endParaRPr lang="ja-JP" altLang="en-US" sz="{int(round(last["size"] * 50))}" b="{1 if bold else 0}" dirty="0">'
               f'{solid(last["color"])}<a:latin typeface="{face}"/><a:ea typeface="{face}"/><a:cs typeface="{face}"/></a:endParaRPr>')
        i = self.nid()
        name = "ページ番号" if is_footer else "文字"
        self.parts.append(
            f'<p:sp><p:nvSpPr><p:cNvPr id="{i}" name="{name} {i}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
            f'<p:spPr>{xfrm(x, y, w, h)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
            f'<p:txBody>{body}<a:lstStyle/><a:p>{ppr}{self.runs_xml(runs, is_footer)}{end}</a:p></p:txBody></p:sp>')

    # ---------------------------------------------------------------- 表
    def table(self, it: dict) -> None:
        rows = it["rows"]
        cols = [c["w"] for c in rows[0]["cells"]]
        grid = "".join(f'<a:gridCol w="{emu(w)}"/>' for w in cols)
        trs = []
        for row in rows:
            tcs = []
            for c in row["cells"]:
                size = c["size"]
                lh = c["lh"] or size * NOTO_ASCENT_DESCENT
                algn = {"center": "ctr", "right": "r"}.get(c["align"], "l")
                ppr = f'<a:pPr algn="{algn}"><a:lnSpc><a:spcPts val="{int(round(lh * 50))}"/></a:lnSpc></a:pPr>'
                runs = self.runs_xml(c["runs"]) if c["runs"] else ""
                end = f'<a:endParaRPr lang="ja-JP" sz="{int(round(size * 50))}" dirty="0"/>'
                pad = list(c["pad"])
                # PowerPoint は Chrome よりわずかに早く折り返すので、右の余白を文字の幅の 2% だけ減らす
                pad[1] = max(0.0, pad[1] - (c["w"] - pad[1] - pad[3]) * (PPT_SLACK - 1))
                bottom = c.get("bottom")
                ln_b = f'<a:lnB w="{emu(bottom["w"])}">{solid(bottom["color"])}</a:lnB>' if bottom else '<a:lnB w="0"><a:noFill/></a:lnB>'
                tcs.append(
                    f'<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>{ppr}{runs}{end}</a:p></a:txBody>'
                    f'<a:tcPr marL="{emu(pad[3])}" marR="{emu(pad[1])}" marT="{emu(pad[0])}" marB="{emu(pad[2])}" anchor="t">'
                    f'<a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT>{ln_b}'
                    f'{solid(c["fill"])}</a:tcPr></a:tc>')
            trs.append(f'<a:tr h="{emu(row["h"])}">{"".join(tcs)}</a:tr>')
        i = self.nid()
        self.parts.append(
            f'<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="{i}" name="表 {i}"/><p:cNvGraphicFramePr>'
            f'<a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
            f'{xfrm(it["x"], it["y"], it["w"], it["h"], tag="p:xfrm")}<a:graphic>'
            f'<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>'
            f'<a:tblPr firstRow="1"/><a:tblGrid>{grid}</a:tblGrid>{"".join(trs)}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>')

    def xml(self, bg: dict | None, creation: str) -> str:
        background = f"<p:bg><p:bgPr>{solid(bg)}<a:effectLst/></p:bgPr></p:bg>" if bg else ""
        return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:sld {NS}><p:cSld>{background}<p:spTree>'
                '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm>'
                '<a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
                f'{"".join(self.parts)}</p:spTree>{creation}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>')

    def rels_xml(self, layout_target: str) -> str:
        rels = [f'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="{layout_target}"/>']
        rels += [f'<Relationship Id="{rid}" Type="{REL_IMAGE}" Target="{t}"/>' for rid, t in self.rels]
        return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{"".join(rels)}</Relationships>')


# 文字の上下の位置の補正（px）。PowerPoint の「固定値」の行間は、Chrome と行の中の文字の置き方が少し違う。QA で決める
CALIBRATION = {"a": 0.0, "b": 0.0}


def calibrate(size: float, lh: float) -> float:
    return CALIBRATION["a"] * size + CALIBRATION["b"] * (lh - size * NOTO_ASCENT_DESCENT)


class Media:
    def __init__(self, work: Path):
        self.files: dict[str, tuple[str, str | None]] = {}  # src -> (media name, svg media name)
        self.blobs: dict[str, bytes] = {}
        self.work = work

    def add(self, slide: Slide, src: Path) -> tuple[str, str | None]:
        key = str(src)
        if key not in self.files:
            n = len(self.files) + 1
            if src.suffix.lower() == ".svg":
                png = self.rasterize(src)
                self.blobs[f"image{n}.png"] = png
                self.blobs[f"image{n}s.svg"] = src.read_bytes()
                self.files[key] = (f"image{n}.png", f"image{n}s.svg")
            else:
                ext = src.suffix.lower().lstrip(".")
                self.blobs[f"image{n}.{ext}"] = src.read_bytes()
                self.files[key] = (f"image{n}.{ext}", None)
        name, svg = self.files[key]
        rid = slide.rel(f"../media/{name}")
        svg_rid = slide.rel(f"../media/{svg}") if svg else None
        return rid, svg_rid

    def rasterize(self, svg: Path) -> bytes:
        """SVG の代わりに使う PNG（SVG を読めない古い PowerPoint 用）を Edge で作る。"""
        page = self.work / f"_svg_{svg.stem}.html"
        page.write_text(f'<html><body style="margin:0;background:transparent"><img src="{svg.as_uri()}" '
                        'style="width:512px;height:512px;object-fit:contain"></body></html>', encoding="utf-8")
        out = self.work / f"_svg_{svg.stem}.png"
        profile = Path(tempfile.gettempdir()) / "testopia_pptx_edge"
        subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}",
                        "--default-background-color=00000000", "--window-size=512,512", f"--screenshot={out}", page.as_uri()],
                       check=True, capture_output=True)
        return out.read_bytes()


def main() -> None:
    deck = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    base, out = Path(sys.argv[2]), Path(sys.argv[3])
    if len(sys.argv) > 5:
        CALIBRATION["a"], CALIBRATION["b"] = float(sys.argv[4]), float(sys.argv[5])
    zin = zipfile.ZipFile(base)
    pres = zin.read("ppt/presentation.xml").decode("utf-8")
    pres_rels = zin.read("ppt/_rels/presentation.xml.rels").decode("utf-8")
    order = re.findall(r'<p:sldId id="\d+" r:id="(rId\d+)"/>', pres)
    targets = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="(slides/slide\d+\.xml)"', pres_rels))
    targets.update({k: v for v, k in re.findall(r'Target="(slides/slide\d+\.xml)"[^>]*Id="(rId\d+)"', pres_rels)})
    slide_paths = ["ppt/" + targets[r] for r in order]
    media = Media(Path(tempfile.mkdtemp(prefix="testopia_pptx_")))
    written: dict[str, bytes] = {}
    for n, (path, data) in enumerate(zip(slide_paths, deck["slides"]), 1):
        old = zin.read(path).decode("utf-8")
        creation = (re.search(r"<p:extLst>.*?</p:extLst>", old) or [""])[0]
        rels_path = path.replace("slides/", "slides/_rels/") + ".rels"
        layout = re.search(r'Target="(\.\./slideLayouts/slideLayout\d+\.xml)"', zin.read(rels_path).decode("utf-8")).group(1)
        s = Slide(n, media)
        for it in data["items"]:
            getattr(s, {"box": "box", "img": "image", "text": "text", "line": "line", "tri": "triangle", "table": "table"}[it["t"]])(it)
        written[path] = s.xml(data["bg"], creation).encode("utf-8")
        written[rels_path] = s.rels_xml(layout).encode("utf-8")
    ctypes = zin.read("[Content_Types].xml").decode("utf-8")
    for ext, ct in (("jpg", "image/jpeg"), ("png", "image/png"), ("svg", "image/svg+xml")):
        if f'Extension="{ext}"' not in ctypes:
            ctypes = ctypes.replace("<Default ", f'<Default Extension="{ext}" ContentType="{ct}"/><Default ', 1)
    written["[Content_Types].xml"] = ctypes.encode("utf-8")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            zout.writestr(item, written.pop(item.filename, None) or zin.read(item.filename))
        for name, data in written.items():
            zout.writestr(name, data)
        for name, blob in media.blobs.items():
            zout.writestr(f"ppt/media/{name}", blob)
    print(f"{out.name}: {len(deck['slides'])} slides, {len(media.blobs)} media, {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
