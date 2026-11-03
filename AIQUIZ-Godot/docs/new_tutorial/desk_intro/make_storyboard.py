"""ローカル2Pの説明画面の始め（3Dの机）を実写にする絵コンテ（v0.1）を 1 枚の画像に組む。

流れ：夜の部屋に 2 人 → 椅子を引いて座る → 手をキーボードに添える → 準備完了（Space）→ モニターの中へ → 本編。
v0.1（2026-11-02）：ユーザーの選んだ「2人を後ろから映す」（顔は映さない）と「Godot でリアルタイムに描く」に合わせた。
コマの絵は Codex CLI の画像生成（panels/panel_XX.png、プロンプトは prompts/、作り方は gen.sh）。
説明の文字はここで描く（生成画像に文字を描かせない）。
カメラの数字は Blender（Z が上、メートル）の座標。原点は机の手前の縁の真ん中の床で、+Y が机（奥の壁）の方向。
  python docs/new_tutorial/desk_intro/make_storyboard.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parents[2] / "resources" / "fonts"
PANEL_DIR = HERE / "panels"
OUT = HERE / "storyboard_v01.jpg"

BOLD = str(FONTS / "NotoSansJP-Bold.otf")
MEDIUM = str(FONTS / "NotoSansJP-Medium.otf")
REGULAR = str(FONTS / "NotoSansJP-Regular.otf")

BG = (246, 247, 250)
INK = (24, 30, 42)
MUTED = (96, 106, 124)
ACCENT = (242, 140, 51)
BLUE = (47, 95, 168)
CARD = (255, 255, 255)
LINE = (214, 219, 228)

PANELS = [
    {"id": "d1", "title": "夜の部屋", "time": "0.0〜1.0 秒",
     "action": "暗い部屋。モニターにステージのライブ映像、左にデスクライト、右にハテナのフィギュア。P1（オレンジのパーカー・灰色の帽子）とP2（水色のパーカー・フード）が椅子の後ろに立つ。キーの光はまだ消えている",
     "camera": "24mm・高さ 1.55m・机の縁から 3.6m 後ろ。(0, -3.6, 1.55) からモニターへ",
     "build": "デスクライト 3000K が主光、モニター 6500K が2人の輪郭、壁の青いLED"},
    {"id": "d2", "title": "椅子を引いて座る", "time": "1.0〜3.0 秒",
     "action": "2人が椅子を引いて腰を下ろす。P2 は少し遅れて座る。体の動きにだけ軽いぶれ",
     "camera": "28mm・高さ 1.45m・2.7m 後ろ。D1 から途切れずに前へ寄りながら下がる",
     "build": "人物の座る動き（動きの生成を骨組みに移し、Blender で手直し）"},
    {"id": "d3", "title": "座った2人", "time": "3.0〜3.8 秒",
     "action": "座り終える。背もたれで背中の大部分が隠れ、頭・肩・袖が見える。手はまだ膝の上",
     "camera": "35mm・高さ 1.38m・1.75m 後ろ。2人のあいだ",
     "build": "椅子の背もたれと机の奥行きで、見える体を頭・肩・腕にしぼる"},
    {"id": "d4", "title": "手を添える", "time": "3.8〜5.2 秒",
     "action": "P1 の左手が WASD に、P2 の右手が矢印に、左手が 8・9・0 の手前に置かれる。指が触れたキーから光る（P1 オレンジ・P2 水色・ほかは薄い白）",
     "camera": "35mm・高さ 1.48m・1.15m 後ろ。2人の頭のすぐ上から約 30° 見下ろす。ここで止める",
     "build": "腕と指の動きは Blender で付け、Godot では最後の形から入力の動きへつなぐ"},
    {"id": "d5", "title": "準備完了", "time": "5.2 秒〜（プレイヤーしだい）",
     "action": "カメラは止まる。左右の肩の上に説明カード（P1 左・P2 右）、下の真ん中に「準備完了 ［Space］」を載せる（絵には描かない）",
     "camera": "D4 と同じ。説明画面の基準の構図（16:9 以外は、この枠が収まるように画角を合わせる）",
     "build": "キーの刻印は Godot で読める大きさにする（絵コンテでは無地）"},
    {"id": "d6", "title": "キーを試す", "time": "準備完了の間",
     "action": "押したキーを、その人の指が押す（例：P1 が中指で W、P2 が左手で 9）。押したキーは沈んで明るく光る",
     "camera": "D5 と同じ",
     "build": "Godot の IK（指ごと）で、押されたキーへ指先を届かせる"},
    {"id": "d7", "title": "Space で開始", "time": "Space → 1.4 秒",
     "action": "P1 の親指が Space を押す（Space が明るく光る）。カードと文字を 0.3 秒で消し、カメラが2人の頭のあいだを抜けてモニターへ寄る",
     "camera": "35mm・高さ 1.48m → 1.10m。モニターの正面へ回り込む",
     "build": "今の「モニターへ寄る」の仕組みを使う（寄る道は頭に当たらないように通す）"},
    {"id": "d8", "title": "モニターの中へ", "time": "寄り終わり → 0.2 秒",
     "action": "映像が画面いっぱいになった瞬間を静止画にして本編を準備し、0.2 秒で本編の画面へ溶けるように切り替える",
     "camera": "35mm・画面の中心の高さ、画面の約 40cm 手前",
     "build": "今の仕組み（静止画の覆い → 本編がふわっと出る）のまま"},
]

NOTES = [
    "決めたこと（2026-11-02）：2人を後ろから映す（顔は映さない）。描くのは Godot のリアルタイム（Blender で実寸・実写の材質で作る）。モニターの前のミニチュアのキャラは廃止。",
    "寸法（Blender、メートル、Z が上）：原点は机の手前の縁の真ん中の床、+Y が机の方向。机は幅 1.60・奥行き 0.75・高さ 0.72。モニターは 27 型（画面 0.60×0.34）。キーボードは机の縁から 0.15。椅子の中心は x = ±0.36。",
    "人物の顔と髪は映さない（P1 は帽子、P2 はフード）。実写でいちばん難しい髪を避けるため。手と袖は近くに映るので、いちばん作り込む。",
    "キーの色分けは、キーごとに光る RGB のバックライト（P1 オレンジ・P2 水色・ほかは薄い白）。",
    "尺：座る〜手を添えるまで約 5.2 秒。途中で Space を押すと D5 へ飛ぶ。Esc はコース選択へ。「動きを減らす」の設定では D1〜D4 を飛ばす。",
]

PANEL_W = 880
PANEL_H = 495
COLS = 2
MARGIN = 48
GUTTER = 40
TEXT_H = 330
HEADER_H = 170


def font(path, size):
    return ImageFont.truetype(path, size)


def wrap(draw, text, fnt, width):
    lines, line = [], ""
    for ch in text:
        trial = line + ch
        if draw.textlength(trial, font=fnt) > width and line and ch not in "。、）」・：":
            lines.append(line)
            line = ch
        else:
            line = trial
    if line:
        lines.append(line)
    return lines


class Sheet:
    def __init__(self, draw):
        self.draw = draw
        self.f_no = font(BOLD, 30)
        self.f_title = font(BOLD, 28)
        self.f_tag = font(MEDIUM, 19)
        self.f_label = font(BOLD, 20)
        self.f_body = font(REGULAR, 20)

    def card(self, sheet, x, y, p):
        draw = self.draw
        draw.rounded_rectangle((x - 6, y - 6, x + PANEL_W + 6, y + PANEL_H + TEXT_H + 6), radius=14, fill=CARD, outline=LINE, width=2)
        path = PANEL_DIR / f"panel_{p['id']}.png"
        if path.exists():
            img = Image.open(path).convert("RGB").resize((PANEL_W, PANEL_H), Image.LANCZOS)
            sheet.paste(img, (x, y))
        else:
            draw.rectangle((x, y, x + PANEL_W, y + PANEL_H), fill=(225, 229, 236))
            draw.text((x + PANEL_W // 2, y + PANEL_H // 2), "（生成待ち）", font=self.f_title, fill=MUTED, anchor="mm")
        badge = p["id"].upper()
        bw = max(72, int(draw.textlength(badge, font=self.f_no)) + 28)
        draw.rounded_rectangle((x + 14, y + 14, x + 14 + bw, y + 62), radius=10, fill=INK)
        draw.text((x + 14 + bw / 2, y + 38), badge, font=self.f_no, fill=(255, 255, 255), anchor="mm")
        ty = y + PANEL_H + 14
        draw.text((x + 14, ty), p["title"], font=self.f_title, fill=INK)
        tw = draw.textlength(p["time"], font=self.f_tag)
        draw.rounded_rectangle((x + PANEL_W - tw - 38, ty + 4, x + PANEL_W - 10, ty + 38), radius=8, fill=(236, 241, 250))
        draw.text((x + PANEL_W - tw - 24, ty + 21), p["time"], font=self.f_tag, fill=BLUE, anchor="lm")
        ty += 50
        for label, key in (("動き", "action"), ("カメラ", "camera"), ("作り", "build")):
            draw.text((x + 14, ty), label, font=self.f_label, fill=ACCENT)
            for line in wrap(draw, p[key], self.f_body, PANEL_W - 110)[:3]:
                draw.text((x + 96, ty), line, font=self.f_body, fill=INK)
                ty += 28
            ty += 6


def main():
    rows = (len(PANELS) + COLS - 1) // COLS
    row_h = PANEL_H + TEXT_H + GUTTER
    width = MARGIN * 2 + COLS * PANEL_W + (COLS - 1) * GUTTER
    f_note = font(REGULAR, 21)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    note_w = width - MARGIN * 2 - 60
    notes_h = 80 + sum(len(wrap(probe, note, f_note, note_w)) * 31 + 12 for note in NOTES)
    height = HEADER_H + rows * row_h + notes_h + MARGIN
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    s = Sheet(draw)
    draw.rectangle((0, 0, width, 12), fill=ACCENT)
    draw.text((MARGIN, 34), "ローカル2Pの説明画面の始め（実写）　絵コンテ v0.1", font=font(BOLD, 46), fill=INK)
    draw.text((MARGIN, 104), "夜の部屋に 2 人 → 椅子を引いて座る → 手をキーボードに添える → 準備完了（Space）→ モニターの中へ → 本編",
              font=font(MEDIUM, 23), fill=MUTED)

    for i, p in enumerate(PANELS):
        x = MARGIN + (i % COLS) * (PANEL_W + GUTTER)
        y = HEADER_H + (i // COLS) * row_h
        s.card(sheet, x, y, p)

    x = MARGIN
    y = HEADER_H + rows * row_h
    draw.rounded_rectangle((x - 6, y - 6, width - MARGIN + 6, y + notes_h), radius=14, fill=(255, 247, 239), outline=ACCENT, width=2)
    draw.text((x + 18, y + 14), "メモ・決めたこと", font=font(BOLD, 28), fill=ACCENT)
    ty = y + 66
    for note in NOTES:
        draw.text((x + 18, ty), "・", font=f_note, fill=INK)
        for line in wrap(draw, note, f_note, note_w):
            draw.text((x + 42, ty), line, font=f_note, fill=INK)
            ty += 31
        ty += 12

    sheet.save(OUT, quality=88)
    print(OUT)


if __name__ == "__main__":
    main()
