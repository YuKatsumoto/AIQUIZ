"""レーン 3（S16・S17・S21）の確認用の一覧（要所のコマ）を作る。

    python docs/pv/takes/lane3_contact.py <出力.jpg> <連番のフォルダ> <見出し> <列の数> <フレーム:説明> [<フレーム:説明> ...]

例：python docs/pv/takes/lane3_contact.py docs/pv/previz/check/s16_contact.jpg artifacts/pv_capture/s16_frames "S16 うしろからチップソー（8 拍）" 4 1:頭 36:P2が止まる
各コマの上に「フレーム番号・拍（128 BPM、1 拍 = 28.125 フレーム）・説明」を書く。
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BEAT_FRAMES = 60.0 * 60.0 / 128.0


def main() -> None:
    out, src, title, cols = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    shots = []
    for arg in sys.argv[5:]:
        frame, _, caption = arg.partition(":")
        shots.append((int(frame), caption))
    tw, th, head, label = 640, 360, 34, 26
    rows = (len(shots) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, head + rows * (th + label)), (16, 16, 20))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/meiryo.ttc", 18)
        big = ImageFont.truetype("C:/Windows/Fonts/meiryob.ttc", 20)
    except OSError:
        font = big = None
    draw.text((10, 6), title, fill=(255, 255, 255), font=big)
    for i, (frame, caption) in enumerate(shots):
        x, y = (i % cols) * tw, head + (i // cols) * (th + label)
        path = src / f"pv_{frame:04d}.jpg"
        if path.exists():
            sheet.paste(Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y + label))
        else:
            draw.text((x + 10, y + label + 10), f"missing {path.name}", fill=(255, 80, 80), font=font)
        beat = (frame - 1) / BEAT_FRAMES
        draw.text((x + 6, y + 2), f"{frame}  ({beat:.2f} 拍)  {caption}", fill=(255, 235, 150), font=font)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, quality=90)
    print(out)


if __name__ == "__main__":
    main()
