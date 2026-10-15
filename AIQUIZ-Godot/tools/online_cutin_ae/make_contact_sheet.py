"""VS カットイン（After Effects 版）の動画から、決めたフレームを並べたコンタクトシートを作る。

    python tools/online_cutin_ae/make_contact_sheet.py            # host と guest の両方
    python tools/online_cutin_ae/make_contact_sheet.py host

入力：artifacts/online_cutin_ae/VS_Cutin_host.mp4 / VS_Cutin_guest.mp4（render_vs_cutin.jsx で書き出したもの）
出力：artifacts/online_cutin_ae/VS_Cutin_contact_sheet.png（host）/ VS_Cutin_guest_contact_sheet.png（guest）
フレームは 60 fps の番号で選ぶ（指定の秒と同じか、そのすぐあとのフレーム）。ffmpeg は C:/ffmpeg/bin/ffmpeg.exe。
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "artifacts", "online_cutin_ae")
FFMPEG = "C:/ffmpeg/bin/ffmpeg.exe"
FONT = "C:/Windows/Fonts/YuGothB.ttc"
FPS = 60
# (フレーム番号, ラベル)。0.10 / 0.24 / 0.30 / 0.45 / 0.60 / 0.90 s、ホールド、
# REVEAL（3.60 s＝フレーム 216）から +0.25 / +0.45 / +0.77 / +1.10 / +1.60 / +2.10 / +3.00 s（S10 v1.6）
FRAMES = [
    (6, "パネルが左右から入る"),
    (15, "稲妻が走りはじめる"),
    (18, "パネル着地・稲妻"),
    (27, "キャラ登場・VS が落ちる"),
    (36, "VS 着地・揺れ"),
    (54, "名前・ルール 出そろう"),
    (120, "ホールド（ループ）"),
    (231, "R+0.25 2 色の稲妻が下へ"),
    (243, "R+0.45 稲妻が下に届く・溜め"),
    (262, "R+0.77 割れる（がくんと開く）"),
    (282, "R+1.10 震えながら・火花"),
    (312, "R+1.60 ゆっくり開く・ステージが寄る"),
    (342, "R+2.10 こすれ火花"),
    (396, "R+3.00 外へ抜ける"),
]
VARIANTS = {
    "host": ("VS_Cutin_host.mp4", "VS_Cutin_contact_sheet.png", "VS カットイン（ホスト：左＝オレンジ／右＝ブルー）  60 fps・1920×1080・R＝REVEAL（3.60 s）"),
    "guest": ("VS_Cutin_guest.mp4", "VS_Cutin_guest_contact_sheet.png", "VS カットイン（ゲスト：左＝ブルー／右＝オレンジ）  60 fps・1920×1080・R＝REVEAL（3.60 s）"),
}


def extract(video: str, tmp: str) -> list:
    sel = "+".join("eq(n\\,%d)" % n for n, _ in FRAMES)
    pattern = os.path.join(tmp, "f_%02d.png")
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", video,
                    "-vf", "select='%s'" % sel, "-vsync", "0", pattern], check=True)
    return [os.path.join(tmp, "f_%02d.png" % (i + 1)) for i in range(len(FRAMES))]


def sheet(files: list, title: str, out: str) -> None:
    cw, ch, lb, gap, th = 640, 360, 46, 12, 64
    cols = 4
    rows = (len(FRAMES) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw + (cols + 1) * gap, th + rows * (ch + lb) + (rows + 1) * gap), (20, 26, 38))
    d = ImageDraw.Draw(img)
    d.text((14, 14), title, font=ImageFont.truetype(FONT, 30), fill=(255, 255, 255))
    fb = ImageFont.truetype(FONT, 21)
    order = sorted(range(len(FRAMES)), key=lambda i: FRAMES[i][0])
    for slot, i in enumerate(order):
        n, label = FRAMES[i]
        im = Image.open(files[slot]).convert("RGB").resize((cw, ch), Image.LANCZOS)
        c, r = slot % cols, slot // cols
        x, y = gap + c * (cw + gap), th + gap + r * (ch + lb + gap)
        img.paste(im, (x, y))
        d.rectangle((x, y + ch, x + cw, y + ch + lb), fill=(27, 42, 65))
        d.text((x + 12, y + ch + 8), "%.2f s（%d）  %s" % (n / FPS, n, label), font=fb, fill=(255, 210, 63))
    img.save(out)
    print(out, img.size)


def main() -> None:
    names = sys.argv[1:] or list(VARIANTS)
    for name in names:
        video, out, title = VARIANTS[name]
        with tempfile.TemporaryDirectory() as tmp:
            files = extract(os.path.join(OUT_DIR, video), tmp)
            sheet(files, title, os.path.join(OUT_DIR, out))


if __name__ == "__main__":
    main()
