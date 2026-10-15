"""AIQUIZ ロゴエディタのローカルサーバー。

ブラウザのエディタ（index.html）を開き、「保存して反映」で次を書き出す。

- assets/branding/logo/aiquiz_logo.json   ロゴの元データ（線・輪・すき間）。これを編集する
- assets/branding/logo/aiquiz_logo.svg    同じ形の SVG（Inkscape や Figma で開ける）
- assets/branding/logo/aiquiz_logo.png    白・透過の高解像度ロゴ。看板・LED のロゴはここから作る
- icon.jpg                                 プロジェクトのアイコン（黒地に白のロゴ、1024×1024）
- ゲームの中でロゴが出るすべての場所（apply_logo.py：メニューのタイトル・スコアボード・LED・看板・ヘリコプター）

保存のたびに前の元データを assets/branding/logo/history/ に残す。

使い方：プロジェクトルートで `python tools/logo_editor/server.py`（start_logo_editor.bat でも可）
"""
from __future__ import annotations

import base64
import importlib.util
import io
import json
import shutil
import sys
import threading
import time
import webbrowser
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LOGO_DIR = ROOT / "assets" / "branding" / "logo"
MODEL = LOGO_DIR / "aiquiz_logo.json"
SVG = LOGO_DIR / "aiquiz_logo.svg"
MASTER = LOGO_DIR / "aiquiz_logo.png"
REFERENCE = LOGO_DIR / "icon_original.jpg"
HISTORY = LOGO_DIR / "history"
ICON = ROOT / "icon.jpg"
APPLY = HERE / "apply_logo.py"  # ゲームの中のロゴへ反映する
HISTORY_KEEP = 50
PORT = 8765

STATIC = {
	"/": ("index.html", "text/html; charset=utf-8"),
	"/index.html": ("index.html", "text/html; charset=utf-8"),
	"/logo_geometry.js": ("logo_geometry.js", "text/javascript; charset=utf-8"),
}


def _decode_png(data_url: str) -> Image.Image:
	head, _, b64 = data_url.partition(",")
	if not head.startswith("data:image/png"):
		raise ValueError("PNG ではありません")
	return Image.open(io.BytesIO(base64.b64decode(b64)))


def _check_model(model: dict) -> None:
	if not isinstance(model, dict) or not isinstance(model.get("elements"), list) or not model["elements"]:
		raise ValueError("ロゴの元データが空です")


def _remember_previous() -> None:
	if not MODEL.exists():
		return
	HISTORY.mkdir(parents=True, exist_ok=True)
	stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
	shutil.copy2(MODEL, HISTORY / f"aiquiz_logo_{stamp}.json")
	old = sorted(HISTORY.glob("aiquiz_logo_*.json"))
	for path in old[:-HISTORY_KEEP]:
		path.unlink()


def _retry(write, attempts: int = 10, wait: float = 0.3):
	"""Godot の再インポートなどで画像が一瞬ロックされていても、少し待って書き直す。"""
	for i in range(attempts):
		try:
			return write()
		except OSError:
			if i == attempts - 1:
				raise
			time.sleep(wait)


def _apply_everywhere() -> tuple[list[str], list[str]]:
	spec = importlib.util.spec_from_file_location("apply_logo", APPLY)
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module.apply_all()


def save(body: dict) -> dict:
	model = body.get("model")
	_check_model(model)
	master = _decode_png(body["master_png"]).convert("RGBA")
	icon = _decode_png(body["icon_png"]).convert("RGB")
	if master.getchannel("A").getbbox() is None:
		raise ValueError("ロゴが空です（白い部分がありません）")

	_remember_previous()
	LOGO_DIR.mkdir(parents=True, exist_ok=True)
	MODEL.write_text(json.dumps(model, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8", newline="\n")
	SVG.write_text(body.get("svg", ""), encoding="utf-8", newline="\n")
	_retry(lambda: master.save(MASTER, optimize=True))
	_retry(lambda: icon.save(ICON, quality=95, subsampling=0))
	written = [str(p.relative_to(ROOT)).replace("\\", "/") for p in (MODEL, SVG, MASTER, ICON)]
	# ゲームの中のロゴ（メニュー・スコアボード・LED・看板・ヘリコプター）へ反映。
	# どれかが作れなくても、元データの保存は成功させる
	files, problems = _retry(_apply_everywhere)
	written += files
	return {"ok": True, "written": written, "warning": "、".join(problems)}


class Handler(BaseHTTPRequestHandler):
	def log_message(self, fmt, *args):  # 1 行ずつ静かに
		sys.stderr.write("  " + (fmt % args) + "\n")

	def _send(self, code: int, data: bytes, ctype: str) -> None:
		self.send_response(code)
		self.send_header("Content-Type", ctype)
		self.send_header("Content-Length", str(len(data)))
		self.send_header("Cache-Control", "no-store")
		self.end_headers()
		self.wfile.write(data)

	def _json(self, code: int, obj: dict) -> None:
		self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

	def do_GET(self):
		path = self.path.split("?", 1)[0]
		if path in STATIC:
			name, ctype = STATIC[path]
			self._send(200, (HERE / name).read_bytes(), ctype)
		elif path == "/api/logo":
			self._send(200, MODEL.read_bytes(), "application/json; charset=utf-8")
		elif path == "/api/reference":
			self._send(200, REFERENCE.read_bytes(), "image/jpeg")
		else:
			self._send(404, b"not found", "text/plain")

	def do_POST(self):
		if self.path != "/api/save":
			self._send(404, b"not found", "text/plain")
			return
		# 別のサイトから勝手に保存されないよう、このサーバーのページからの送信だけ受ける
		origin = self.headers.get("Origin", "")
		host = self.headers.get("Host", "")
		if origin and origin != f"http://{host}":
			self._json(403, {"ok": False, "error": "このページ以外からの保存は受け付けません"})
			return
		try:
			length = int(self.headers.get("Content-Length", "0"))
			body = json.loads(self.rfile.read(length).decode("utf-8"))
			result = save(body)
			print("保存しました:", ", ".join(result["written"]))
			if result["warning"]:
				print("注意:", result["warning"])
			self._json(200, result)
		except Exception as exc:
			self._json(400, {"ok": False, "error": str(exc)})


class Server(ThreadingHTTPServer):
	# Windows では SO_REUSEADDR だと、使用中のポートにもう 1 つ起動できてしまう（古いサーバーが応答してしまう）
	allow_reuse_address = False


def main() -> None:
	no_browser = "--no-browser" in sys.argv
	first = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else PORT
	server = None
	for port in range(first, first + 20):
		try:
			server = Server(("127.0.0.1", port), Handler)
			break
		except OSError:
			continue
	if server is None:
		sys.exit("空いているポートが見つかりませんでした")
	url = f"http://127.0.0.1:{server.server_address[1]}/"
	print(f"AIQUIZ ロゴエディタ: {url}")
	print("終了するにはこのウィンドウで Ctrl+C を押すか、ウィンドウを閉じてください。")
	if not no_browser:
		threading.Thread(target=lambda: (time.sleep(0.6), webbrowser.open(url)), daemon=True).start()
	try:
		server.serve_forever()
	except KeyboardInterrupt:
		pass
	finally:
		server.server_close()


if __name__ == "__main__":
	main()
