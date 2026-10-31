"""コース③ 3-1「2人の操作」控え室のノートPC版 絵コンテ（v0.5）を 1 枚の画像に組む。

流れ：控え室に 2 人 → ノートPCの前へ（自動で歩く）→ 画面とキーで操作を説明 → 画面にステージが映り、練習
→ 画面の中へ拡大 → そのままステージに入って 3-2 へ。
v0.4（2026-10-29）：入り方はユーザーの選んだ X（カメラが画面に入る）に決めた。別案 Y（2 人が画面に吸い込まれる。panel_y1・y2）は外した。
v0.5（2026-10-29）：ユーザーの指示で、控え室は暗い部屋（明かりは画面と机のスタンドだけ、窓なし）。画面に入るときは普通の拡大だけ（ぶれ・光・粒・ハテナが飛び込むのはなし）。コマの絵は regen_dark.sh で作り直した。
コマの絵は Codex CLI の画像生成（panels/panel_XX.png、プロンプトは prompts/、作り方は gen.sh）。
説明の文字はここで描く（生成画像に文字を描かせない）。
  python docs/new_tutorial/laptop_keys/room/make_storyboard.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parents[3] / "resources" / "fonts"
PANEL_DIR = HERE / "panels"
OUT = HERE / "storyboard_v05.jpg"

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
    {"id": "r1", "title": "控え室に 2 人", "time": "0.0〜1.5 秒",
     "action": "3-0 のカードが閉じると暗転（0.3 秒）して暗い控え室。明かりは机のスタンドだけ。P1（左）と P2（右）が入口に立つ",
     "hatena": "机に座って手をふる（セリフなし）",
     "camera": "入口から 2 人の背中越しに部屋の奥（窓はない）"},
    {"id": "r2", "title": "ノートPCの前へ", "time": "1.5〜4.0 秒",
     "action": "2 人が自動で机まで歩く（操作はまだ止めたまま）。着く直前にふたが開き、画面の青白い光が部屋を照らす",
     "hatena": "机の上に立ち、ノートPCを指す",
     "camera": "2 人について前へ"},
    {"id": "r3", "title": "肩越しで説明を始める", "time": "4.0〜6.4 秒",
     "action": "2 人がキーボードに手を置く（P1 は左半分、P2 は右半分）。画面にキーボードの図（左オレンジ・右青）",
     "hatena": "「2人のときは操作が変わるよ」（c3.keys.1）",
     "camera": "2 人の頭のあいだから肩越し。画面が真ん中"},
    {"id": "r4", "title": "P1 のキー", "time": "6.4〜8.9 秒",
     "action": "W A S D・スペースが、画面の図と本体の両方でオレンジに光る。図に「P1　移動／ジャンプ」",
     "hatena": "「P1はWASDとスペースだよ」（c3.keys.2）。左を指す",
     "camera": "R3 のまま"},
    {"id": "r5", "title": "P2 のキー", "time": "8.9〜14.2 秒",
     "action": "矢印・右 Ctrl が青に光り、続いて 8 9 0 も青。P1 のキーは薄く光ったまま",
     "hatena": "「P2は矢印キーと右Ctrlだよ」→「P2のエモートは8・9・0だよ」",
     "camera": "R3 のまま"},
    {"id": "r6", "title": "画面にステージ。練習", "time": "14.2 秒〜（プレイヤーしだい）",
     "action": "画面が本物のステージに変わる。押したキーが本体で光り、画面の中の 2 人が動く・跳ぶ。画面の隅に P1・P2 の ✓（左右・前後・ジャンプ）",
     "hatena": "「2人とも動いてみて！」（c3.keys.6）→ 全員 ✓ で「NICE!」",
     "camera": "R3 より少し寄る"},
    {"id": "r7", "title": "画面の中へ拡大", "time": "✓ のあと 1.2 秒",
     "action": "カメラが画面へまっすぐ寄る。ぶれ・光・粒などの演出はなし（普通の拡大だけ）",
     "hatena": "机の上で見送る（セリフなし）",
     "camera": "1.2 秒でまっすぐ前へ。画面が画面いっぱいになったら R8"},
    {"id": "r8", "title": "そのままステージの中へ", "time": "0.4 秒 → 3-2",
     "action": "控え室の絵が 0.2 秒で消え、本番のステージの画面。下のカードが出てくる → 3-2 の壁 1 が落ちてくる",
     "hatena": "ステージのハテナは 3-2 の始めに空から降りる",
     "camera": "本番の 2 人のカメラで止まる（切れ目を見せない）"},
]

NOTES = [
    "部屋は新しく作る暗い「控え室」（明かりは画面と机のスタンドだけ。ロッカー・ベンチ・机。窓なし）。ノートPCは実物の約 2 倍。",
    "画面には本物のステージをそのまま映す。R7 で画面が画面いっぱいになったら本番の画面へ 0.2 秒で重ねてつなぐ（作り方は phase10_design.md）。",
    "CPU と：R3 で「今回の相手はCPUだよ」。R5 で CPU（P2）の手がひとりでに矢印を押して見せる。R6 は P1 だけ ✓。P1 が矢印を押したら図の W A S D が点滅し「2人のときP1はWASDで動くよ」。",
    "セリフは今の c3.keys.*（「セリフ」パネルで直された文）をそのまま使う。画面の文字に c3.pc.labels・c3.pc.checks を足す。",
    "尺：約 18 秒＋練習（今の 3-1 は約 20 秒）。",
    "決めたこと（2026-10-29）：入り方は X（カメラだけが画面に入る）。部屋の 2 人は部屋に残る。",
    "決めたこと（2026-10-29）：控え室は暗い部屋。画面に入るときは普通の拡大だけ。R7 の一言はなし。",
]

PANEL_W = 880
PANEL_H = 495
COLS = 2
MARGIN = 48
GUTTER = 40
TEXT_H = 250
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
        for label, key in (("動き", "action"), ("ハテナ", "hatena"), ("カメラ", "camera")):
            draw.text((x + 14, ty), label, font=self.f_label, fill=ACCENT)
            for line in wrap(draw, p[key], self.f_body, PANEL_W - 110)[:3]:
                draw.text((x + 96, ty), line, font=self.f_body, fill=INK)
                ty += 28
            ty += 6


def main():
    main_rows = (len(PANELS) + 1 + COLS - 1) // COLS  # +1 は決めることの枠
    row_h = PANEL_H + TEXT_H + GUTTER
    width = MARGIN * 2 + COLS * PANEL_W + (COLS - 1) * GUTTER
    height = HEADER_H + main_rows * row_h + MARGIN
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    s = Sheet(draw)
    draw.rectangle((0, 0, width, 12), fill=ACCENT)
    draw.text((MARGIN, 34), "コース③ 3-1「2人の操作」控え室のノートPC版　絵コンテ v0.5", font=font(BOLD, 46), fill=INK)
    draw.text((MARGIN, 104), "暗い控え室に 2 人 → ノートPCの前へ → 画面とキーで説明 → 画面にステージが映って練習 → 画面へ拡大 → そのままステージへ（3-2）",
              font=font(MEDIUM, 23), fill=MUTED)

    for i, p in enumerate(PANELS):
        x = MARGIN + (i % COLS) * (PANEL_W + GUTTER)
        y = HEADER_H + (i // COLS) * row_h
        s.card(sheet, x, y, p)

    i = len(PANELS)
    x = MARGIN + (i % COLS) * (PANEL_W + GUTTER)
    y = HEADER_H + (i // COLS) * row_h
    draw.rounded_rectangle((x - 6, y - 6, x + PANEL_W + 6, y + PANEL_H + TEXT_H + 6), radius=14, fill=(255, 247, 239), outline=ACCENT, width=2)
    draw.text((x + 18, y + 14), "メモ・決めること", font=font(BOLD, 28), fill=ACCENT)
    ty = y + 66
    f_note = font(REGULAR, 21)
    for note in NOTES:
        draw.text((x + 18, ty), "・", font=f_note, fill=INK)
        for line in wrap(draw, note, f_note, PANEL_W - 60):
            draw.text((x + 42, ty), line, font=f_note, fill=INK)
            ty += 31
        ty += 12

    sheet.save(OUT, quality=88)
    print(OUT)


if __name__ == "__main__":
    main()
