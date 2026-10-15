"""PV 冒頭 S01〜S03 の新しい流れの絵コンテ v3：ロゴは案 C（今の 2D の登場演出を強化）に決めた版。

本編 01〜09 は v2（make_storyboard.py）と同じ。ロゴを C の動きに合わせて 6 コマ（C1〜C6）に割った。
コマの絵は Codex CLI の画像生成（panels/panel_XX.png、プロンプトは prompts/）。C3・C4 は v2 の c1・c2。
  python docs/pv/storyboard_s01_s03_v2/make_storyboard_v3.py
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import make_storyboard as v2  # noqa: E402

OUT = HERE / "s01_s03_storyboard_v3.png"

# 1 拍＝0.469 秒（128 BPM）。ロゴは 09 のあとの 2 小節（0:14.1〜17.8）
LOGO_C = [
    {"id": "c_line", "badge": "C1", "title": "黄色い線が走る", "time": "0:14.1〜14.6｜1 拍",
     "action": "細い黄色い線が画面の左から右へ一気に走る。先は白く光り、長い尾を引く",
     "camera": "09 のカメラのまま。背景はぼかさない（今の S03 のぼかし・暗くするのはやめる）",
     "audio": "「シュッ」"},
    {"id": "c_belt", "badge": "C2", "title": "線が開いてベルトになる", "time": "0:14.6〜15.0｜1 拍",
     "action": "線が上下に開いて、目盛りの付いた黄色いベルトになる。目盛りが横へ流れ、少し弾む",
     "camera": "そのまま",
     "audio": "ベルトが開く「カシャッ」"},
    {"id": "c1", "badge": "C3", "title": "文字がベルトに乗って流れてくる", "time": "0:15.0〜15.9｜2 拍",
     "action": "白い文字（黒い影付き）がベルトに乗って右から流れ込む。横に強いブレ、後ろに速度の線",
     "camera": "そのまま",
     "audio": "ベルトが走る音が高くなっていく"},
    {"id": "c2", "badge": "C4", "title": "ピタッと止まる", "time": "0:15.9〜16.4｜1 拍（2 小節目の頭）",
     "action": "文字が止まる瞬間に白い閃光・横に走る光の筋・黄色と白の斜め線。ロゴは画面の上半分に大きく",
     "camera": "止まる瞬間に 1 コマだけ寄る（ズームパンチ）",
     "audio": "「バン」とジングルを小節の頭に合わせる"},
    {"id": "c_hold", "badge": "C5", "title": "止めて見せる", "time": "0:16.4〜17.3｜2 拍",
     "action": "ロゴは止まったまま。まわりに小さなきらめき、観客席のフラッシュ。P1 は踊り続ける",
     "camera": "4% だけゆっくり寄る",
     "audio": "ジングルの残り"},
    {"id": "c_wipe", "badge": "C6", "title": "ベルトごと流れて次のカットへ", "time": "0:17.3〜17.8｜1 拍",
     "action": "ベルトがロゴごと左へ流れ出し、右から黄色い斜めの帯が画面を横切る",
     "camera": "帯のワイプで S04（教科と学年をえらぶ）へ切り替える",
     "audio": "「シュッ」→ 次の小節の頭で S04"},
]

NOTES = [
    "ロゴは案 C（今の 2D の登場演出を強化）に決めた。作るのは After Effects（docs/pv/previz/ae/build_s03.jsx とタイトルロゴの AEP が元）。",
    "変えること：ベルトを画面いっぱいに、背景はぼかさず暗くしない、止まる瞬間の閃光・光の筋・斜め線・ズームパンチ、最後はベルトのワイプで S04 へ。",
    "左右：P1（オレンジ・プロペラのキャップ）と正解の青いドア（AI）が左、P2（水色・キツネの帽子）とまちがいの赤いドア（せんせい）が右。05・09・C は前・裏から見るので逆に映る。",
    "P2 はハート 1 から始め、ゲームどおりゴツン → 吹き飛び → 爆散。",
    "尺：約 9.5 小節（17.8 秒）。今の 5 小節（9.4 秒）より 4.5 小節長い。75 秒に収めるには他のカットを削る（要相談）。",
    "撮影で新しく要るもの：壁を空から落とす、2 人が首を振る動き、走りながらのエモート。",
]


def main():
    main_rows = (len(v2.PANELS) + 1 + v2.COLS - 1) // v2.COLS
    logo_rows = (len(LOGO_C) + v2.COLS - 1) // v2.COLS
    row_h = v2.PANEL_H + v2.TEXT_H + v2.GUTTER
    width = v2.MARGIN * 2 + v2.COLS * v2.PANEL_W + (v2.COLS - 1) * v2.GUTTER
    height = v2.HEADER_H + main_rows * row_h + v2.SECTION_H + v2.IDEA_BAND_H + logo_rows * row_h + v2.MARGIN
    sheet = Image.new("RGB", (width, height), v2.BG)
    draw = ImageDraw.Draw(sheet)
    s = v2.Sheet(draw)
    draw.rectangle((0, 0, width, 12), fill=v2.ACCENT)
    draw.text((v2.MARGIN, 34), "PV 冒頭 S01〜S03　新しい流れ　絵コンテ v3（ロゴは案 C）", font=v2.font(v2.BOLD, 46), fill=v2.INK)
    draw.text((v2.MARGIN, 104), "2 人がコンベアの前に → 壁が落ちる → ドアを交互に見る → P2 が踊りながらまちがいへ（ゴツン・爆散）→ P1 が踊りながら正解を突き破る → ベルトのロゴ",
              font=v2.font(v2.MEDIUM, 23), fill=v2.MUTED)

    for i, p in enumerate(v2.PANELS):
        x = v2.MARGIN + (i % v2.COLS) * (v2.PANEL_W + v2.GUTTER)
        y = v2.HEADER_H + (i // v2.COLS) * row_h
        s.card(sheet, x, y, p, p["id"], p["time"])

    # 09 の右に決めたこと
    i = len(v2.PANELS)
    x = v2.MARGIN + (i % v2.COLS) * (v2.PANEL_W + v2.GUTTER)
    y = v2.HEADER_H + (i // v2.COLS) * row_h
    draw.rounded_rectangle((x - 6, y - 6, x + v2.PANEL_W + 6, y + v2.PANEL_H + v2.TEXT_H + 6), radius=14,
                           fill=(255, 247, 239), outline=v2.ACCENT, width=2)
    draw.text((x + 18, y + 14), "決めたこと・残り", font=v2.font(v2.BOLD, 28), fill=v2.ACCENT)
    ty = y + 66
    f_note = v2.font(v2.REGULAR, 20)
    for note in NOTES:
        draw.text((x + 18, ty), "・", font=f_note, fill=v2.INK)
        for line in v2.wrap(draw, note, f_note, v2.PANEL_W - 60):
            draw.text((x + 42, ty), line, font=f_note, fill=v2.INK)
            ty += 29
        ty += 9

    # ロゴ（案 C）
    y = v2.HEADER_H + main_rows * row_h
    draw.rectangle((v2.MARGIN, y + 20, width - v2.MARGIN, y + 24), fill=v2.ACCENT)
    draw.text((v2.MARGIN, y + 40), "ロゴ（案 C：今の 2D の登場演出を強化）　09 から切らずにつなぐ", font=v2.font(v2.BOLD, 38), fill=v2.INK)
    y += v2.SECTION_H
    draw.rounded_rectangle((v2.MARGIN - 6, y, width - v2.MARGIN + 6, y + v2.IDEA_BAND_H - 16), radius=10, fill=v2.LOGO_BAND)
    draw.text((v2.MARGIN + 16, y + (v2.IDEA_BAND_H - 16) / 2), "線 → ベルト → 文字が流れ込む → ピタッ → 止め → ワイプ",
              font=v2.font(v2.BOLD, 28), fill=(255, 255, 255), anchor="lm")
    draw.text((width - v2.MARGIN - 16, y + (v2.IDEA_BAND_H - 16) / 2), "0:14.1〜17.8｜2 小節",
              font=v2.font(v2.MEDIUM, 21), fill=(198, 208, 228), anchor="rm")
    y += v2.IDEA_BAND_H
    for n, p in enumerate(LOGO_C):
        x = v2.MARGIN + (n % v2.COLS) * (v2.PANEL_W + v2.GUTTER)
        s.card(sheet, x, y + (n // v2.COLS) * row_h, p, p["badge"], p["time"])
    sheet.save(OUT)
    print(OUT, sheet.size)


if __name__ == "__main__":
    main()
