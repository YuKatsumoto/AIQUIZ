"""gen_v2 の案を、ユーザーが選んだ実機の絵と並べる（仕上げと同じ位置にロゴを重ねる）→ _sheet.jpg"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
LOGO = HERE.parents[2] / "pv/frames/logo_testopia.png"
ITEMS = [("ref_chosen", "いまの実機（選んだ画角）"), ("a_shoulder", "A 肩タックル"), ("b_superman", "B 空中パンチ"),
         ("c_cross_guard", "C 腕クロスで突破"), ("d_front_kick", "D 前蹴り")]
TW, TH = 960, 540
font = ImageFont.truetype("C:/Windows/Fonts/NotoSansJP-VF.ttf", 30)
font.set_variation_by_name("Bold")
logo = Image.open(LOGO).convert("RGBA")
lw = round(740 * TW / 1920)
logo = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
cols, pad, lab = 2, 16, 48
rows = (len(ITEMS) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (TW + pad) + pad, rows * (TH + lab + pad) + pad), (245, 245, 242))
d = ImageDraw.Draw(sheet)
for i, (name, label) in enumerate(ITEMS):
    im = Image.open(HERE / f"{name}.png").convert("RGBA").resize((TW, TH), Image.LANCZOS)
    im.alpha_composite(logo, (round(56 * TW / 1920), (TH - logo.height) // 2))
    x, y = pad + (i % cols) * (TW + pad), pad + (i // cols) * (TH + lab + pad)
    d.text((x, y + 4), label, font=font, fill=(27, 42, 74))
    sheet.paste(im.convert("RGB"), (x, y + lab))
sheet.save(HERE / "_sheet.jpg", quality=88)
print(HERE / "_sheet.jpg")
