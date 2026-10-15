"""PV 冒頭 S01〜S03 の新しい流れの絵コンテ（v2）を 1 枚の画像に組む。

流れ：2 人がコンベアの前に立つ → 壁が 1 枚落ちてくる → 寄って 2 人がドアを交互に見る
→ 先に決めた P2 が踊りながらまちがいのドアへ（ゴツン → 爆散）→ P1 が正解のドアへ
→ 壁の向こう側から、踊りながらドアを突き破って出てくる → ロゴ（3 案を比べる）。
コマの絵は Codex CLI の画像生成（panels/panel_XX.png、プロンプトは prompts/）。
説明の文字はここで描く（生成画像に文字を描かせない）。
  python docs/pv/storyboard_s01_s03_v2/make_storyboard.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
FONTS = HERE.parents[2] / "resources" / "fonts"
PANEL_DIR = HERE / "panels"
OUT = HERE / "s01_s03_storyboard_v2.png"

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
LOGO_BAND = (32, 40, 58)

# 時間は 128 BPM の目安（1 小節＝1.875 秒）
PANELS = [
    {"id": "01", "title": "コンベアの前に 2 人", "time": "0:00.0〜1.9｜1 小節",
     "action": "P1（左・オレンジ）と P2（右・水色）がスタート位置に並んで立つ。前のコースは空っぽ",
     "camera": "2 人の後ろ・上から（今の S01 と同じ高さ、24mm 相当）。止め",
     "audio": "曲はまだ入れない。コンベアの駆動音と観客のざわめき"},
    {"id": "02", "title": "壁が 1 枚落ちてくる", "time": "0:01.9〜3.8｜1 小節",
     "action": "空から問題の壁が落ちてドスン。土ぼこりの輪が広がり、2 人はびくっとのけぞる",
     "camera": "同じ位置のまま。着地の瞬間だけ小さく揺らす",
     "audio": "風を切る音 → 着地の「ドーン」と地鳴り"},
    {"id": "03", "title": "寄る。2 人が左のドアを見る", "time": "0:03.8〜5.6｜1 小節",
     "action": "2 人そろって首と上半身を左の青いドア（AI）へ向ける",
     "camera": "2 拍で 2 人の背中越し・頭の高さのアップへ寄る。看板の問題が読める",
     "audio": "チクタク（考える時間）"},
    {"id": "04", "title": "右のドアを見る（交互に）", "time": "0:05.6〜7.5｜1 小節",
     "action": "右の赤いドア（せんせい）→ 左 → 右と、1 拍ずつ首を振って見比べる",
     "camera": "03 と同じアップのまま",
     "audio": "チクタク。首を振る小さな「シュッ」を拍に合わせる"},
    {"id": "05", "title": "P2 が先に決める", "time": "0:07.5〜8.4｜2 拍",
     "action": "P2 が赤いドアを指さし、胸を張ってドヤ顔。P1 はまだ首をかしげて迷う",
     "camera": "前から P2 の顔のアップ（低め）。前から見るので左右は逆",
     "audio": "決めの「キラーン」（短く）"},
    {"id": "06", "title": "踊りながら、まちがいへ", "time": "0:08.4〜10.3｜1 小節",
     "action": "P2 がエモート（YMCA）を踊りながら赤いドアへ斜めに突っ込む。P1 は首をかしげて見送る",
     "camera": "引いて 2 人の後ろ・上から（01 の位置）",
     "audio": "ライザーが始まる"},
    {"id": "07", "title": "ゴツン", "time": "0:10.3〜11.3｜2 拍",
     "action": "P2 が赤いドアに激突。ドアは割れず、後ろへ吹き飛ぶ（ハート 1 なので脱落）",
     "camera": "06 と同じ引き",
     "audio": "「ゴツン」"},
    {"id": "08", "title": "P1 が青いドアへ", "time": "0:11.3〜12.2｜2 拍",
     "action": "P1 が青いドアへまっすぐ走る。奥で P2 が爆散（激突から 2 秒後）",
     "camera": "P1 の後ろ・低めの追従。P1 がドアに触れる直前で 09 へ切る",
     "audio": "爆散の音。ライザーが頂点へ"},
    {"id": "09", "title": "踊りながら突き破って出てくる", "time": "0:12.2〜14.1｜1 小節",
     "action": "P1 がカンナムスタイルを踊りながら青いドアを破って出てくる。破片がカメラへ",
     "camera": "壁の向こう側・低め・広角（左右は逆に見える）。突破の 0.6 秒は 0.5 倍のスロー",
     "audio": "ドアが砕ける音と同時に曲が入る（最初のアタック）"},
]

LOGO_IDEAS = [
    {"key": "A", "name": "破片が集まってロゴに", "time": "0:14.1〜17.8｜2 小節",
     "panels": [
         {"id": "a1", "title": "破片が宙で止まる",
          "action": "突破の破片がスローのまま宙で止まり、縁が光って上へ吸い寄せられる。P1 は踊り続ける",
          "camera": "09 のカメラのまま、少し下がって見上げる",
          "audio": "破片が止まる瞬間に一瞬だけ無音"},
         {"id": "a2", "title": "組み上がって立体ロゴ",
          "action": "破片が組み上がって青い立体の「AIQUIZ」に。白い閃光・衝撃波・観客のフラッシュ",
          "camera": "見上げたまま 4% だけ寄って止める",
          "audio": "「ガシャッ」と組み上がる音と閃光にジングル"},
     ]},
    {"key": "B", "name": "ロゴが壁のように落ちてくる", "time": "0:14.1〜17.8｜2 小節",
     "panels": [
         {"id": "b1", "title": "空から巨大なロゴ",
          "action": "踊る P1 の後ろのコースへ、巨大な立体ロゴがまっすぐ落ちてくる。影が広がる",
          "camera": "P1 の前のローアングル。ロゴは画面の上半分",
          "audio": "風を切る音（02 の壁と同じ音で対にする）"},
         {"id": "b2", "title": "ドスン",
          "action": "ロゴが着地。土ぼこりの輪・ベルトが跳ねる・P1 も跳ね上がる。観客が立ち上がる",
          "camera": "着地で大きく揺らしてから止める",
          "audio": "着地の重低音にジングル"},
     ]},
    {"key": "C", "name": "今の 2D 演出を強化", "time": "0:14.1〜17.8｜2 小節",
     "panels": [
         {"id": "c1", "title": "ベルトの線が横切る",
          "action": "目盛り付きの黄色いベルトの線が画面いっぱいを横切り、文字が乗って流れてくる",
          "camera": "09 のカメラのまま。背景はぼかさない",
          "audio": "ベルトが走る「シュッ」"},
         {"id": "c2", "title": "ピタッと止まる",
          "action": "文字が止まる瞬間に光の筋・斜め線・ズームパンチ。ロゴは画面の上半分に大きく",
          "camera": "止まる瞬間に 1 コマだけ寄る（ズームパンチ）",
          "audio": "止まる「バン」にジングル"},
     ]},
]

NOTES = [
    "絵は Codex CLI の画像生成で作ったイメージ。本番は今の S01〜S03 と同じく Godot の実機（tests/pv_capture）で撮る。",
    "左右：P1（オレンジ・プロペラのキャップ）と正解の青いドア（AI）が左、P2（水色・キツネの帽子）とまちがいの赤いドア（せんせい）が右。05 と 09 は前・裏から見るので逆に映る。",
    "P2 はハート 1 から始め、ゲームどおりゴツン → 吹き飛び → 爆散。",
    "尺：約 9.5 小節（17.8 秒）。今の 5 小節（9.4 秒）より 4.5 小節長い。75 秒に収めるには他のカットを削る（要相談）。",
    "撮影で新しく要るもの：壁を空から落とす（読み込み中の落下演出を流用）、2 人が首を振る動き、走りながらのエモート。",
    "ロゴは下の A／B／C から 1 つ選ぶ。",
]

PANEL_W = 880
PANEL_H = 495
COLS = 2
MARGIN = 48
GUTTER = 40
TEXT_H = 232
HEADER_H = 170
SECTION_H = 120
IDEA_BAND_H = 64


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

    def card(self, sheet, x, y, p, badge, tag):
        draw = self.draw
        draw.rounded_rectangle((x - 6, y - 6, x + PANEL_W + 6, y + PANEL_H + TEXT_H + 6), radius=14, fill=CARD, outline=LINE, width=2)
        path = PANEL_DIR / f"panel_{p['id']}.png"
        if path.exists():
            img = Image.open(path).convert("RGB").resize((PANEL_W, PANEL_H), Image.LANCZOS)
            sheet.paste(img, (x, y))
        else:
            draw.rectangle((x, y, x + PANEL_W, y + PANEL_H), fill=(225, 229, 236))
            draw.text((x + PANEL_W // 2, y + PANEL_H // 2), "（生成待ち）", font=self.f_title, fill=MUTED, anchor="mm")
        bw = max(72, int(draw.textlength(badge, font=self.f_no)) + 28)
        draw.rounded_rectangle((x + 14, y + 14, x + 14 + bw, y + 62), radius=10, fill=INK)
        draw.text((x + 14 + bw / 2, y + 38), badge, font=self.f_no, fill=(255, 255, 255), anchor="mm")
        ty = y + PANEL_H + 14
        draw.text((x + 14, ty), p["title"], font=self.f_title, fill=INK)
        if tag:
            tw = draw.textlength(tag, font=self.f_tag)
            draw.rounded_rectangle((x + PANEL_W - tw - 38, ty + 4, x + PANEL_W - 10, ty + 38), radius=8, fill=(236, 241, 250))
            draw.text((x + PANEL_W - tw - 24, ty + 21), tag, font=self.f_tag, fill=BLUE, anchor="lm")
        ty += 50
        for label, key in (("動き", "action"), ("カメラ", "camera"), ("音", "audio")):
            draw.text((x + 14, ty), label, font=self.f_label, fill=ACCENT)
            for line in wrap(draw, p[key], self.f_body, PANEL_W - 110)[:2]:
                draw.text((x + 96, ty), line, font=self.f_body, fill=INK)
                ty += 28
            ty += 6


def main():
    main_rows = (len(PANELS) + 1 + COLS - 1) // COLS  # +1 は決めたことの枠
    row_h = PANEL_H + TEXT_H + GUTTER
    width = MARGIN * 2 + COLS * PANEL_W + (COLS - 1) * GUTTER
    height = (HEADER_H + main_rows * row_h + SECTION_H
              + len(LOGO_IDEAS) * (IDEA_BAND_H + row_h) + MARGIN)
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    s = Sheet(draw)
    draw.rectangle((0, 0, width, 12), fill=ACCENT)
    draw.text((MARGIN, 34), "PV 冒頭 S01〜S03　新しい流れ　絵コンテ v2", font=font(BOLD, 46), fill=INK)
    draw.text((MARGIN, 104), "2 人がコンベアの前に → 壁が落ちる → ドアを交互に見る → P2 が踊りながらまちがいへ（ゴツン・爆散）→ P1 が踊りながら正解を突き破る → ロゴ（3 案）",
              font=font(MEDIUM, 23), fill=MUTED)

    for i, p in enumerate(PANELS):
        col, row = i % COLS, i // COLS
        x = MARGIN + col * (PANEL_W + GUTTER)
        y = HEADER_H + row * row_h
        s.card(sheet, x, y, p, p["id"], p["time"])

    # 09 の右に決めたこと
    i = len(PANELS)
    x = MARGIN + (i % COLS) * (PANEL_W + GUTTER)
    y = HEADER_H + (i // COLS) * row_h
    draw.rounded_rectangle((x - 6, y - 6, x + PANEL_W + 6, y + PANEL_H + TEXT_H + 6), radius=14, fill=(255, 247, 239), outline=ACCENT, width=2)
    draw.text((x + 18, y + 14), "決めたこと・残り", font=font(BOLD, 28), fill=ACCENT)
    ty = y + 66
    f_note = font(REGULAR, 21)
    for note in NOTES:
        draw.text((x + 18, ty), "・", font=f_note, fill=INK)
        for line in wrap(draw, note, f_note, PANEL_W - 60):
            draw.text((x + 42, ty), line, font=f_note, fill=INK)
            ty += 31
        ty += 12

    # ロゴ案
    y = HEADER_H + main_rows * row_h
    draw.rectangle((MARGIN, y + 20, width - MARGIN, y + 24), fill=ACCENT)
    draw.text((MARGIN, y + 40), "ロゴの出方　3 案を比べる（09 のあとにつなぐ）", font=font(BOLD, 38), fill=INK)
    y += SECTION_H
    for idea in LOGO_IDEAS:
        draw.rounded_rectangle((MARGIN - 6, y, width - MARGIN + 6, y + IDEA_BAND_H - 16), radius=10, fill=LOGO_BAND)
        draw.text((MARGIN + 16, y + (IDEA_BAND_H - 16) / 2), f"ロゴ案 {idea['key']}　{idea['name']}",
                  font=font(BOLD, 28), fill=(255, 255, 255), anchor="lm")
        draw.text((width - MARGIN - 16, y + (IDEA_BAND_H - 16) / 2), idea["time"],
                  font=font(MEDIUM, 21), fill=(198, 208, 228), anchor="rm")
        y += IDEA_BAND_H
        for col, p in enumerate(idea["panels"]):
            x = MARGIN + col * (PANEL_W + GUTTER)
            s.card(sheet, x, y, p, p["id"].upper(), "")
        y += row_h
    sheet.save(OUT)
    print(OUT, sheet.size)


if __name__ == "__main__":
    main()
