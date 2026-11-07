"""TESTOPIA のアプリアイコン案（1024 x 1024 の SVG）を、ロゴ（assets/branding/logo/testopia_logo.svg）の部品から組む。

ロゴの SVG は部品ごとに 1 つの path（testopia_logo.json の elements と同じ順）。
O（1P の頭）・A（2P の頭）・T などを取り出して、拡大・配置するだけで、形は描き直さない。

    python tools/logo_editor/build_icon_concepts.py
    → assets/branding/icon_concepts/icon_concept_[a-d].svg
    PNG にするには: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/logo_editor/render_icon_concepts.gd
    採用した D案をゲームと書き出しのアイコンにするには: python tools/logo_editor/export_app_icon.py
"""
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOGO_SVG = os.path.join(ROOT, "assets/branding/logo/testopia_logo.svg")
LOGO_JSON = os.path.join(ROOT, "assets/branding/logo/testopia_logo.json")
OUT_DIR = os.path.join(ROOT, "assets/branding/icon_concepts")

BG = "#0e0e0e"
NAVY = "#1B2A4A"
YELLOW = "#FFE040"   # タイトルのベルト・見出しの黄色（main_menu の TitleLabel と同じ系統）
ORANGE = "#F28C33"
BLUE = "#33A6E6"


def load_parts():
    svg = open(LOGO_SVG, encoding="utf-8").read()
    paths = re.findall(r"<path [^>]*/>", svg)
    ids = [e["id"] for e in json.load(open(LOGO_JSON, encoding="utf-8"))["elements"]]
    assert len(paths) == len(ids), (len(paths), len(ids))
    parts = {}
    for pid, tag in zip(ids, paths):
        d = re.search(r'd="([^"]+)"', tag).group(1)
        nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d)]
        xs, ys = nums[0::2], nums[1::2]
        parts[pid] = {"tag": tag, "bbox": (min(xs), min(ys), max(xs), max(ys))}
    return parts


def group_bbox(parts, ids):
    boxes = [parts[i]["bbox"] for i in ids]
    return (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))


def place(parts, ids, cx, cy, height, fill=None):
    """部品のまとまりを、中心 (cx, cy)・高さ height に置いた <g>。fill を渡すと白い部品だけその色にする。"""
    x0, y0, x1, y1 = group_bbox(parts, ids)
    s = height / (y1 - y0)
    tx = cx - (x0 + x1) * 0.5 * s
    ty = cy - (y0 + y1) * 0.5 * s
    body = []
    for i in ids:
        tag = parts[i]["tag"]
        if fill is not None:
            tag = tag.replace('fill="#ffffff"', f'fill="{fill}"')
        body.append(tag)
    return f'<g transform="translate({tx:.2f} {ty:.2f}) scale({s:.4f})">{"".join(body)}</g>', s, (x1 - x0) * s


def svg(content, bg=BG):
    # 角丸の四角（Windows・デスクトップ用。Android はこの中身を前景・背景に分けて使う）
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        f'<rect x="0" y="0" width="1024" height="1024" rx="200" ry="200" fill="{bg}"/>'
        f"{content}</svg>"
    )


O_IDS = ["o_hole", "o_head_top", "o_head", "o_body"]
A_IDS = ["a_hole", "a_head_top", "a_head", "a_body"]
ALL_IDS = None  # load_parts のあとで決める


def concept_a(parts):
    # A案「O の 1P」：ロゴの O（中に 1P の頭）を大きく 1 つ。16px でも形が分かる
    g, _, _ = place(parts, O_IDS, 512, 512, 700)
    return svg(g)


def concept_b(parts):
    # B案「1P と 2P」：O（1P・オレンジ）と A（2P・青）を並べる。2 人で対戦するゲームだと伝わる
    go, _, wo = place(parts, O_IDS, 512 - 205, 512, 380)
    ga, _, wa = place(parts, A_IDS, 512 + 205, 512, 380)
    return svg(go + ga)


def concept_c(parts):
    # C案「ベルトの上の T」：タイトル演出のベルト（黄色）の上に、ロゴの T と O が乗る
    gt, _, _ = place(parts, ["t1_body"], 512 - 190, 470, 420)
    go, _, _ = place(parts, O_IDS, 512 + 150, 470, 420)
    belt = (
        f'<rect x="120" y="712" width="784" height="56" rx="28" fill="{YELLOW}"/>'
        f'<rect x="120" y="784" width="784" height="18" rx="9" fill="{YELLOW}" opacity="0.45"/>'
    )
    return svg(gt + go + belt)


def _concept_d_content(parts):
    ids = list(parts.keys())
    g, _, w = place(parts, ids, 512, 480, 112)  # 横 780 前後（左右に 120 ほどの余白）
    belt = f'<rect x="{512 - w / 2:.1f}" y="566" width="{w:.1f}" height="22" rx="11" fill="{YELLOW}"/>'
    return g + belt


def concept_d(parts):
    # D案「ロゴ全体」：いまの AIQUIZ のアイコンと同じ作り（暗い地に文字）で、TESTOPIA と黄色いベルト（採用）
    return svg(_concept_d_content(parts))


# D案の中身（ロゴ＋ベルト）は縦 424〜588 に収まる。Android の前景はこの中心を画面の中心へ置いて縮め、
# アダプティブアイコンの安全な円（直径 1024 x 66/108）に入れる。
D_CENTER_Y = 506
ANDROID_FG_SCALE = 0.76


def concept_d_android_fg(parts):
    # Android のアダプティブアイコンの前景（地は透明。背景は BG 一色の別の絵）
    s = ANDROID_FG_SCALE
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        f'<g transform="translate(512 512) scale({s}) translate(-512 -{D_CENTER_Y})">{_concept_d_content(parts)}</g></svg>'
    )


def main():
    parts = load_parts()
    os.makedirs(OUT_DIR, exist_ok=True)
    gdignore = os.path.join(OUT_DIR, ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    for name, fn in [("a", concept_a), ("b", concept_b), ("c", concept_c), ("d", concept_d),
                     ("d_android_fg", concept_d_android_fg)]:
        path = os.path.join(OUT_DIR, f"icon_concept_{name}.svg")
        open(path, "w", encoding="utf-8").write(fn(parts))
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
