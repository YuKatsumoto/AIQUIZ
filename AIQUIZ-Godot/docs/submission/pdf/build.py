"""審査用フォルダの PDF を組む（ゲームクリエイター甲子園2026）。

    python docs/submission/pdf/build.py                 # 画像を用意して、3 つの PDF を out/ に書き出す
    python docs/submission/pdf/build.py --shots <dir>   # あわせて、見た目の確認用の画像をページごとに撮る
    python docs/submission/pdf/build.py --final         # 提出用。【】の書きかけが残っていたら止める

- 00・05 は docs/submission の Markdown から組む。最初の `---` より後ろ、`<!-- pdf:end -->` より前が本文。
- 02 は 02_appeal.html（原稿は 02_appeal_script.md）。
- 画像は PV（docs/pv/previz/v6/PV_full.mp4）のコマと、artifacts/ などの画面写真から img/ に用意する。
- PDF は Microsoft Edge のヘッドレス印刷で書き出す。フォントは make_fonts.py が fonts/ に作る太さごとの Noto Sans JP
  （Windows の可変フォントのままだと PDF の文字が図形になり、Acrobat で書き換えにくい）。
"""

import argparse
import html
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
SUBMISSION = HERE.parent
ROOT = SUBMISSION.parent.parent
IMG = HERE / "img"
OUT = HERE / "out"
FONTS = HERE / "fonts"
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
PROFILE = Path(tempfile.gettempdir()) / "testopia_pdf_edge"

PV = ROOT / "docs/pv/previz/v6/PV_full.mp4"
# 名前: PV の秒。テロップ「壁のスピードも、AIが決める」の出るコマ（38〜40 秒）は使わない。
PV_FRAMES = {
    "pv_wall_fall": 2.5,
    "pv_choose": 5.5,
    "pv_bonk": 11.5,
    "pv_break": 14.4,
    "pv_logo": 20.5,
    "pv_heli": 26.5,
    "pv_tower": 75.0,
    "pv_end": 84.0,
}
# 名前: (元の画像, 切り抜き (左, 上, 右, 下) か None)
STILLS = {
    "cover": ("docs/pv/thumbnail/final/t8_blender.png", None),
    "push": ("docs/pv/thumbnail/final/t8.png", (720, 0, 1920, 1080)),
    # テロップの入るカットは、テロップの入っていない撮影の連番から（PV のコマだと切り抜きでテロップが切れる）
    "saw": ("artifacts/pv_capture/s16_frames/pv_0141.jpg", None),
    "ghost": ("artifacts/pv_capture/s17_frames/pv_0253.jpg", None),
    "wall_q": ("artifacts/pv_capture/s09_frames/pv_0901.jpg", None),
    # p4 の「出題（壁）」の箱に入れる小さな絵。問題の札と答えのドアの上半分
    "wall_thumb": ("artifacts/pv_capture/s09_frames/pv_0901.jpg", (520, 300, 1400, 640)),
    "boss": ("artifacts/pv_capture/s09_frames/pv_3001.jpg", None),
    "custom": ("artifacts/pv_capture/s20_frames/pv_0151.jpg", None),
    "preload": ("artifacts/preload_progress/02_count_pop.png", None),
    "preload_done": ("artifacts/preload_progress/04a_complete_flash.png", None),
    # 旧チュートリアルのリザルト。右下のハテナの吹き出しが入らないよう、カードの左右を少し内側で切る
    "result_card": ("artifacts/practice_course2/26_result_card.png", (348, 0, 932, 720)),
    "online_home": ("artifacts/online_skin/home.png", None),
    "online_friend": ("artifacts/net/menu_shots/online_friend.png", None),
    "online_vs": ("artifacts/online_staging/live_cover/reveal_0_9.png", None),
    "online_heli": ("artifacts/online_cutin_ae/plates/formation_plate.png", None),
    "tut_keyboard": ("artifacts/tutorial_keyboard_intro/solo_overview.png", None),
    "tut_keys3d": ("artifacts/tutorial_v7/solo/03_arrow_legends.png", None),
    "tut_hatena": ("artifacts/tutorial_customize_handoff/02_go_hello.png", None),
    "crowd": ("artifacts/crowd_sim/runtime/06_goal_race.png", None),
    "goal": ("artifacts/result_finale/runtime/programme/p1_goal_approach.png", None),
    # p13 の比較。最初のころの版（4/11・床がマグマ）と今の版を、同じ手順で撮ったもの（撮り方は artifacts/submission_p13/README.md）
    "menu_before": ("artifacts/submission_p13/menu_early_2026-04-11_64ca140.png", None),
    "menu_after": ("artifacts/submission_p13/menu_now_2026-11-01.png", None),
    "stage_before": ("artifacts/submission_p13/stage_early_2026-04-11_64ca140.png", None),
    "stage_after": ("artifacts/submission_p13/stage_now_2026-11-01.png", None),
}
LOGO = "assets/ui/branding/testopia_logo.png"

DOCS = [
    {
        "src": "00_hajimeni.md",
        "html": "00_hajimeni.gen.html",
        "pdf": "00_はじめにお読みください.pdf",
        "kicker": "はじめにお読みください",
        "title": None,  # 本文の最初の「##」を見出しにする
        "body_class": "portrait onepage",
        "page": "A4",
    },
    {
        "src": "05_credits_ai.md",
        "html": "05_credits_ai.gen.html",
        "pdf": "05_外部素材とAIの使用箇所.pdf",
        "kicker": "TESTOPIA 審査用資料",
        "title": "外部素材とAIの使用箇所",
        "body_class": "landscape",
        "page": "A4 landscape",
    },
]
# 02 は 2026-11-01 から PowerPoint 版（docs/submission/02_アピール資料.pptx）が元。提出用の PDF は PowerPoint で書き出す。
# ここで作る HTML 版の PDF は、PowerPoint で書き出した 02_アピール資料.pdf を上書きしないよう別の名前にする
DECK = {"html": "02_appeal.html", "pdf": "02_アピール資料_HTML版.pdf", "pages": 15}


# --- 画像 ---------------------------------------------------------------------

def save_jpeg(im: Image.Image, path: Path, max_width: int = 1600) -> None:
    im = im.convert("RGB")
    if im.width > max_width:
        im = im.resize((max_width, round(im.height * max_width / im.width)), Image.LANCZOS)
    im.save(path, "JPEG", quality=86, optimize=True, progressive=True)


def prepare_images() -> None:
    shutil.rmtree(IMG, ignore_errors=True)
    IMG.mkdir()
    with tempfile.TemporaryDirectory() as tmp:
        for name, seconds in PV_FRAMES.items():
            png = Path(tmp) / f"{name}.png"
            subprocess.run(
                ["ffmpeg", "-v", "error", "-y", "-ss", str(seconds), "-i", str(PV), "-frames:v", "1", str(png)],
                check=True,
            )
            with Image.open(png) as im:
                save_jpeg(im, IMG / f"{name}.jpg")
    for name, (src, box) in STILLS.items():
        with Image.open(ROOT / src) as im:
            if box:
                im = im.crop(box)
            save_jpeg(im, IMG / f"{name}.jpg", 1920 if name == "cover" else 1600)
    with Image.open(ROOT / LOGO) as im:
        im = im.convert("RGBA")
        im.thumbnail((900, 300), Image.LANCZOS)
        im.save(IMG / "logo.png", optimize=True)
    print(f"images: {len(PV_FRAMES) + len(STILLS) + 1} -> {IMG}")


# --- Markdown（このディレクトリの下書きで使う書き方だけ） ------------------------------

def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"【([^】]*)】", r'<mark class="todo">【\1】</mark>', text)
    return text


def table_html(rows: list[str]) -> str:
    cells = [[c.strip() for c in row.strip().strip("|").split("|")] for row in rows]
    head, body = cells[0], [r for r in cells[2:]]
    out = ["<table><thead><tr>"]
    out += [f"<th>{inline(c)}</th>" for c in head]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
    out.append("</tbody></table>")
    return "".join(out)


def markdown_body(text: str, first_h2_as_title: bool) -> tuple[str | None, str]:
    """本文（最初の `---` の後ろ）を HTML にする。(見出しにする最初の ## の文, 本文の HTML) を返す。"""
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == "---") + 1
    title = None
    out: list[str] = []
    para: list[str] = []
    table: list[str] = []
    list_stack: list[str] = []  # 開いている箇条書きのタグ（ul / ol）
    open_sections: list[str] = []
    seen_h3 = False

    def flush_para() -> None:
        if para:
            out.append(f"<p>{inline(''.join(para))}</p>")
            para.clear()

    def flush_table() -> None:
        if table:
            out.append(table_html(table))
            table.clear()

    def close_lists(to_depth: int = 0) -> None:
        while len(list_stack) > to_depth:
            out.append(f"</li></{list_stack.pop()}>")

    def flush_all() -> None:
        flush_para()
        flush_table()
        close_lists()

    def close_sections(level: str) -> None:
        # level "lv2" は lv3 と lv2 を、"lv3" は lv3 だけを閉じる
        while open_sections and (level == "lv2" or open_sections[-1] == "lv3"):
            out.append("</section>")
            closed = open_sections.pop()
            if level == "lv3" and closed == "lv3":
                break

    for line in lines[start:]:
        stripped = line.strip()
        if stripped.startswith("<!-- pdf:end"):
            break
        if stripped.startswith("<!--"):
            continue
        if stripped.startswith("|"):
            flush_para()
            close_lists()
            table.append(stripped)
            continue
        flush_table()
        if not stripped:
            flush_para()
            close_lists()
            continue
        if stripped == "---":
            flush_all()
            close_sections("lv2")
            out.append('<hr class="sep">')
            continue
        heading = re.match(r"^(#{1,3}) (.*)$", stripped)
        if heading:
            flush_all()
            level, words = len(heading.group(1)), heading.group(2)
            if level <= 2 and first_h2_as_title and title is None:
                title = words
                continue
            if level <= 2:
                close_sections("lv2")
                out.append(f'<section class="lv2"><h2>{inline(words)}</h2>')
                open_sections.append("lv2")
            else:
                if first_h2_as_title and not seen_h3:
                    out.append('</div><div class="content">')
                seen_h3 = True
                close_sections("lv3")
                out.append(f'<section class="lv3"><h3>{inline(words)}</h3>')
                open_sections.append("lv3")
            continue
        item = re.match(r"^(\s*)(-|\d+\.) (.*)$", line)
        if item:
            flush_para()
            depth = len(item.group(1)) // 2 + 1
            tag = "ol" if item.group(2)[0].isdigit() else "ul"
            words = item.group(3)
            words = re.sub(r"^\[ \] ", "☐ ", words)
            words = re.sub(r"^\[x\] ", "☑ ", words)
            if depth > len(list_stack):
                while len(list_stack) < depth:
                    out.append(f"<{tag}><li>")
                    list_stack.append(tag)
            else:
                close_lists(depth)
                out.append("</li><li>")
            out.append(inline(words))
            continue
        if list_stack and line.startswith(" "):
            out.append(inline(stripped))  # 箇条書きの続きの行
            continue
        if stripped.startswith(">"):
            flush_all()
            out.append(f"<blockquote>{inline(stripped.lstrip('> '))}</blockquote>")
            continue
        para.append(stripped)
    flush_all()
    close_sections("lv2")
    body = "".join(out)
    if first_h2_as_title:
        body = f'<div class="intro">{body}</div>' if seen_h3 else body
    return title, body


def render_doc(doc: dict) -> Path:
    text = (SUBMISSION / doc["src"]).read_text(encoding="utf-8")
    title, body = markdown_body(text, doc["title"] is None)
    title = doc["title"] or title
    page = f"<style>@page {{ size: {doc['page']}; }}</style>"
    page_html = f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="doc.css">
{page}
</head>
<body class="{doc['body_class']}">
<header class="doc-head">
  <img src="img/logo.png" alt="TESTOPIA">
  <div><p class="kicker">{html.escape(doc['kicker'])}</p><h1>{html.escape(title)}</h1></div>
</header>
{body}
</body>
</html>
"""
    path = HERE / doc["html"]
    path.write_text(page_html, encoding="utf-8")
    return path


# --- 書き出し -----------------------------------------------------------------

def edge(*args: str) -> None:
    if not EDGE.exists():
        sys.exit(f"Microsoft Edge が見つからない: {EDGE}")
    subprocess.run(
        [str(EDGE), "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars",
         f"--user-data-dir={PROFILE}", "--virtual-time-budget=10000", *args],
        check=True, capture_output=True,
    )


def to_pdf(html_path: Path, pdf_name: str, final: bool) -> Path:
    OUT.mkdir(exist_ok=True)
    tmp = OUT / "_printing.pdf"
    url = html_path.as_uri() + ("#final" if final else "")
    edge("--no-pdf-header-footer", "--print-to-pdf-no-header", f"--print-to-pdf={tmp}", url)
    target = OUT / pdf_name
    tmp.replace(target)
    data = target.read_bytes()
    pages = len(re.findall(rb"/Type\s*/Page[^s]", data))
    print(f"{target.name}: {pages} ページ, {len(data) / 1e6:.1f} MB")
    type3 = len(re.findall(rb"/Subtype\s*/Type3", data))
    if type3:
        print(f"  図形（Type 3）で入った文字のフォントが {type3} 個ある。fonts/ が読めていないかもしれない")
    return target


def shots(shot_dir: Path) -> None:
    shot_dir.mkdir(parents=True, exist_ok=True)
    deck = (HERE / DECK["html"]).as_uri()
    for n in range(1, DECK["pages"] + 1):
        edge(f"--screenshot={shot_dir / f'02_p{n:02d}.png'}", "--window-size=1920,1080", f"{deck}#only={n}")
    for doc, size in ((DOCS[0], "794,1123"), (DOCS[1], "1123,4800")):
        name = Path(doc["html"]).stem.replace(".gen", "")
        edge(f"--screenshot={shot_dir / f'{name}.png'}", f"--window-size={size}", (HERE / doc["html"]).as_uri())
    print(f"shots -> {shot_dir}")


def printed_lines(path: Path) -> list[str]:
    """PDF に出る行だけ（Markdown は最初の `---` から `<!-- pdf:end` まで。HTML のコメントの行は除く）。"""
    lines = path.read_text(encoding="utf-8").splitlines()
    if path.suffix == ".md":
        start = next(i for i, line in enumerate(lines) if line.strip() == "---") + 1
        end = next((i for i, line in enumerate(lines) if line.strip().startswith("<!-- pdf:end")), len(lines))
        lines = lines[start:end]
    return [line for line in lines if "<!--" not in line]


def check_final() -> None:
    sources = [SUBMISSION / d["src"] for d in DOCS] + [HERE / DECK["html"]]
    left = [f"{p.name}: {line.strip()}" for p in sources for line in printed_lines(p) if "【" in line]
    if left:
        print("【】の書きかけが残っている：", *left[:20], sep="\n  ")
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shots", type=Path, help="確認用の画像を撮るフォルダ")
    parser.add_argument("--final", action="store_true", help="提出用（書きかけの印を消す。残っていたら止める）")
    parser.add_argument("--skip-images", action="store_true", help="img/ をそのまま使う")
    args = parser.parse_args()
    if not list(FONTS.glob("NotoSansJP-*.ttf")):
        sys.exit("fonts/ に Noto Sans JP が無い。先に make_fonts.py で作る")
    if args.final:
        check_final()
    if not args.skip_images:
        prepare_images()
    for doc in DOCS:
        to_pdf(render_doc(doc), doc["pdf"], args.final)
    to_pdf(HERE / DECK["html"], DECK["pdf"], args.final)
    if args.shots:
        shots(args.shots)
    shutil.rmtree(PROFILE, ignore_errors=True)


if __name__ == "__main__":
    main()
