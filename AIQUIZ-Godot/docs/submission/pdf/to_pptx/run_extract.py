"""02_appeal.html を Edge で開き、extract.js の結果（スライドごとの部品の一覧）を JSON に書き出す。引数: 出力 JSON"""
import base64, html, re, subprocess, sys, tempfile
from pathlib import Path

PDF = Path(r"G:\AIQUIZ-Main\AIQUIZ-Godot\docs\submission\pdf")
HERE = Path(__file__).resolve().parent
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

src = (PDF / "02_appeal.html").read_text(encoding="utf-8")
src = src.replace("<head>", f'<head>\n<base href="{PDF.as_uri()}/">', 1)
src = src.replace("</body>", f'<script src="{(HERE / "extract.js").as_uri()}"></script>\n</body>', 1)
page = Path(tempfile.gettempdir()) / "testopia_extract_page.html"
page.write_text(src, encoding="utf-8")
profile = Path(tempfile.gettempdir()) / "testopia_pptx_edge"
out = subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars", f"--user-data-dir={profile}",
                      "--allow-file-access-from-files", "--window-size=1920,1080", "--virtual-time-budget=15000", "--dump-dom",
                      page.as_uri() + "#final"], capture_output=True, check=True)
dom = out.stdout.decode("utf-8", "replace")
m = re.search(r'<pre id="__extract">([^<]*)</pre>', dom)
if not m:
    sys.exit("extract の結果が無い")
data = base64.b64decode(html.unescape(m.group(1))).decode("utf-8")
Path(sys.argv[1]).write_text(data, encoding="utf-8")
print(f"{len(data)} bytes")
