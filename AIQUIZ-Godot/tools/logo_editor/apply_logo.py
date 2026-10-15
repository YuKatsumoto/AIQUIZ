"""ロゴ（assets/branding/logo/aiquiz_logo.png）を、ゲームの中でロゴが出るすべての場所へ反映する。

ロゴエディタの「保存して反映」から呼ばれる。単独でも `python tools/logo_editor/apply_logo.py` で実行できる。

反映先
- ui_logo        assets/ui/branding/aiquiz_logo.png         メインメニューのタイトル・スコアボードの見出し（Godot が直接読む）
- led_logo       assets/aiquiz_menu_stage/led/led_logo.png  LED 番組（AIQUIZ VISION）のロゴ（make_led_media.make_logo）
- menu_sign      メニューのステージの看板（make_textures.make_sign）。発進デッキは今は作っていないが、作り直したときのため
- helicopter     ヘリコプターの機体のデカール（hb_decals.png のロゴ 2 つ）。機体の UV はそのままにするため、
                 ロゴの枠（hb_decals_regions.json の regions）は変えず、その中へ縦横比を保って収める。
                 Blender で機体を作り直すと hb_textures.py が led_logo.png から同じように描き直す
- lighthouse     スタジアムの灯台とゴールスタンドの看板「AIQUIZ STADIUM」。字を消した下地
                 （lighthouse_sign_plate.png）の上に、光る箱文字の見た目でロゴを描く

Godot が GLB から取り出した画像（<glb名>_<画像名>.png）も、元の画像と同じ内容で上書きする。
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MASTER = ROOT / "assets" / "branding" / "logo" / "aiquiz_logo.png"

UI_LOGO = ROOT / "assets" / "ui" / "branding" / "aiquiz_logo.png"
UI_LOGO_WIDTH = 1200

MENU_STAGE = ROOT / "assets" / "aiquiz_menu_stage"
MENU_SIGN_SOURCE = MENU_STAGE / "source" / "textures" / "sign_aiquiz.png"
MENU_SIGN_GAME = MENU_STAGE / "aiquiz_menu_stage_sign_aiquiz.png"

HELI = ROOT / "assets" / "vehicles" / "helicopter_boarding"
HELI_SOURCE = HELI / "source" / "textures" / "hb_decals.png"
HELI_REGIONS = HELI / "source" / "textures" / "hb_decals_regions.json"
HELI_GAME = HELI / "helicopter_boarding_hb_decals.png"

STADIUM = ROOT / "assets" / "aiquiz_stadium"
LH_SOURCE = STADIUM / "source" / "textures" / "lighthouse_sign.png"
LH_PLATE = STADIUM / "source" / "textures" / "lighthouse_sign_plate.png"
LH_ORIGINAL = STADIUM / "source" / "textures" / "lighthouse_sign_original.png"
LH_GAME = [STADIUM / "aiquiz_stadium_goal_stand_lighthouse_sign.png", STADIUM / "aiquiz_stadium_backdrop_lighthouse_sign.png"]
# 元の看板で「AIQUIZ」の字が占めていた枠（x0, y0, x1, y1）。新しいロゴはこの枠の高さに合わせ、横はまん中にそろえる
LH_LOGO_BOX = (166, 80, 1353, 360)


def _rel(path: Path) -> str:
	return str(path.relative_to(ROOT)).replace("\\", "/")


def logo_alpha() -> Image.Image:
	"""ロゴの不透明度（L、ロゴの外接矩形で切り抜き）。"""
	alpha = Image.open(MASTER).convert("RGBA").getchannel("A")
	return alpha.crop(alpha.getbbox())


def _fit(alpha: Image.Image, w: int, h: int) -> Image.Image:
	s = min(w / alpha.width, h / alpha.height)
	return alpha.resize((max(1, round(alpha.width * s)), max(1, round(alpha.height * s))), Image.LANCZOS)


def _load_module(name: str, path: Path):
	spec = importlib.util.spec_from_file_location(name, path)
	module = importlib.util.module_from_spec(spec)
	sys.path.insert(0, str(path.parent))
	try:
		spec.loader.exec_module(module)
	finally:
		sys.path.remove(str(path.parent))
	return module


# ---------------------------------------------------------------- UI

def ui_logo() -> list[Path]:
	a = logo_alpha()
	a = a.resize((UI_LOGO_WIDTH, round(a.height * UI_LOGO_WIDTH / a.width)), Image.LANCZOS)
	img = Image.new("RGBA", a.size, (255, 255, 255, 0))
	img.putalpha(a)
	UI_LOGO.parent.mkdir(parents=True, exist_ok=True)
	img.save(UI_LOGO, optimize=True)
	return [UI_LOGO]


# ---------------------------------------------------------------- LED・メニューの看板

def led_logo() -> list[Path]:
	module = _load_module("make_led_media", MENU_STAGE / "source" / "ae" / "make_led_media.py")
	return [module.make_logo()]


def menu_sign() -> list[Path]:
	module = _load_module("make_textures", MENU_STAGE / "source" / "textures" / "make_textures.py")
	module.make_sign(MENU_SIGN_SOURCE)
	shutil.copyfile(MENU_SIGN_SOURCE, MENU_SIGN_GAME)
	return [MENU_SIGN_SOURCE, MENU_SIGN_GAME]


# ---------------------------------------------------------------- ヘリコプターのデカール
# hb_textures.py（Blender の中で動く）と同じ描き方。行 0 が下（Blender の向き）の float 配列で描く。

def _hex(h: str) -> np.ndarray:
	h = h.lstrip("#")
	return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


HB_NAVY = _hex("#1D2F5C")
HB_WHITE = _hex("#F4F3EE")
HB_OUTLINE = 12
HB_BLEED = 8


def _over(view, rgb, a):
	a = a.astype(np.float32)
	da = view[..., 3]
	oa = a + da * (1.0 - a)
	safe = np.where(oa > 1e-6, oa, 1.0)
	for c in range(3):
		view[..., c] = (rgb[c] * a + view[..., c] * da * (1.0 - a)) / safe
	view[..., 3] = oa


def _dilate(mask, r):
	out = mask.copy()
	H, W = mask.shape
	pad = np.pad(mask, r)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				out = np.maximum(out, pad[r + dy:r + dy + H, r + dx:r + dx + W])
	return out


def _bleed(buf, iters=HB_BLEED):
	rgb = buf[..., :3]
	a = buf[..., 3]
	filled = a > 0.01
	for _ in range(iters):
		acc = np.zeros_like(rgb)
		cnt = np.zeros(a.shape, np.float32)
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			sh = np.roll(np.roll(filled, dy, 0), dx, 1)
			src = np.roll(np.roll(rgb, dy, 0), dx, 1)
			acc += src * sh[..., None]
			cnt += sh
		grow = (~filled) & (cnt > 0)
		rgb[grow] = acc[grow] / cnt[grow][:, None]
		filled = filled | grow


def helicopter() -> list[Path]:
	info = json.loads(HELI_REGIONS.read_text(encoding="utf-8"))
	size = int(info["size"])
	img = np.asarray(Image.open(HELI_SOURCE).convert("RGBA")).astype(np.float32) / 255.0
	buf = img[::-1].copy()  # 行 0 を下に
	a = logo_alpha()
	for name in ("LOGO_KEY", "LOGO_MASK"):
		cx, cy, cw, ch = info["cells"][name]
		x0, y0, rw, rh = info["regions"][name]
		buf[cy:cy + ch, cx:cx + cw] = 0.0
		lw, lh = rw - 2 * HB_OUTLINE, rh - 2 * HB_OUTLINE
		fitted = _fit(a, lw, lh)
		mask = np.asarray(fitted).astype(np.float32)[::-1] / 255.0
		full = np.zeros((rh, rw), np.float32)
		ox = HB_OUTLINE + (lw - fitted.width) // 2
		oy = HB_OUTLINE + (lh - fitted.height) // 2
		full[oy:oy + fitted.height, ox:ox + fitted.width] = mask
		view = buf[y0:y0 + rh, x0:x0 + rw]
		if name == "LOGO_KEY":
			_over(view, HB_WHITE, _dilate(full, HB_OUTLINE))
			_over(view, HB_NAVY, full)
		else:
			_over(view, HB_WHITE, full)
		cell = buf[cy:cy + ch, cx:cx + cw]
		_bleed(cell)
	np.clip(buf, 0.0, 1.0, out=buf)
	out = Image.fromarray((buf[::-1] * 255.0 + 0.5).astype(np.uint8), "RGBA")
	assert out.size == (size, size)
	out.save(HELI_SOURCE)
	shutil.copyfile(HELI_SOURCE, HELI_GAME)
	return [HELI_SOURCE, HELI_GAME]


# ---------------------------------------------------------------- 灯台・ゴールスタンドの看板

def _layer(color, alpha: Image.Image) -> Image.Image:
	img = Image.new("RGBA", alpha.size, color + (0,))
	img.putalpha(alpha)
	return img


def _shift(alpha: Image.Image, dx: int, dy: int) -> Image.Image:
	return ImageChops.offset(alpha, dx, dy)


def lighthouse() -> list[Path]:
	if not LH_PLATE.exists():
		raise FileNotFoundError(f"字を消した下地 {_rel(LH_PLATE)} がありません")
	if not LH_ORIGINAL.exists():
		shutil.copyfile(LH_SOURCE, LH_ORIGINAL)
	plate = Image.open(LH_PLATE).convert("RGBA")
	W, H = plate.size
	x0, y0, x1, y1 = LH_LOGO_BOX
	face = _fit(logo_alpha(), x1 - x0, y1 - y0)
	px = (x0 + x1 - face.width) // 2
	py = y0 + (y1 - y0 - face.height) // 2
	a = Image.new("L", (W, H), 0)
	a.paste(face, (px, py))

	out = plate.copy()
	# 板に落ちる影（右下へ）
	shadow = _shift(a, 7, 11).filter(ImageFilter.GaussianBlur(9)).point(lambda v: int(v * 0.6))
	out.alpha_composite(_layer((3, 8, 20), shadow))
	# 字の側面（箱文字の厚み）：右下へ少しずつずらして重ねる
	side = Image.new("L", (W, H), 0)
	for k in range(1, 7):
		side = ImageChops.lighter(side, _shift(a, k // 2, k))
	out.alpha_composite(_layer((70, 82, 104), side))
	out.alpha_composite(_layer((40, 48, 66), ImageChops.subtract(side, _shift(a, 1, 3))))
	# 光るふち（字のまわりの淡い光）
	glow = a.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.35))
	out.alpha_composite(_layer((200, 225, 255), glow))
	# 字の面：白、下へいくほどわずかに青み。縁に細い灰色の縁取り（トリムキャップ）
	rim = ImageChops.subtract(a, a.filter(ImageFilter.MinFilter(5)))
	grad = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]
	face_rgb = np.stack([
		np.full((H, W), 250.0, np.float32) - 14.0 * grad,
		np.full((H, W), 252.0, np.float32) - 8.0 * grad,
		np.full((H, W), 255.0, np.float32) - 0.0 * grad,
	], axis=-1)
	face_img = Image.fromarray(face_rgb.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
	face_img.putalpha(a)
	out.alpha_composite(face_img)
	out.alpha_composite(_layer((172, 184, 204), rim.point(lambda v: int(v * 0.8))))

	result = out.convert("RGB")
	result.save(LH_SOURCE)
	for path in LH_GAME:
		shutil.copyfile(LH_SOURCE, path)
	return [LH_SOURCE, *LH_GAME]


STEPS = [
	("ui_logo", "メニュー・スコアボードのロゴ", ui_logo),
	("led_logo", "LED のロゴ", led_logo),
	("menu_sign", "メニューのステージの看板", menu_sign),
	("helicopter", "ヘリコプターのデカール", helicopter),
	("lighthouse", "灯台・ゴールスタンドの看板", lighthouse),
]


def apply_all() -> tuple[list[str], list[str]]:
	"""すべての反映先を作り直す。書いたファイルと、できなかったものの説明を返す。"""
	written: list[str] = []
	problems: list[str] = []
	for _, label, step in STEPS:
		try:
			written += [_rel(p) for p in step()]
		except Exception as exc:  # 1 か所が失敗しても、ほかは反映する
			problems.append(f"{label}: {exc}")
	return written, problems


if __name__ == "__main__":
	only = sys.argv[1:]
	if only:
		for key, label, step in STEPS:
			if key in only:
				print(label, [_rel(p) for p in step()])
	else:
		files, errors = apply_all()
		print("\n".join(files))
		for line in errors:
			print("できなかったもの:", line)
