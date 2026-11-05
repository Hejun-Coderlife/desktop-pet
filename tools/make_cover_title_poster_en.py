"""英文版海报风封面字：DESKTOP / PET 两行等宽瘦高粗体 + 左侧竖排 I MADE A（转 90°，从下往上读），透明 PNG"""
import sys
from PIL import Image, ImageDraw, ImageFont

FONT, IDX = "/System/Library/Fonts/HelveticaNeue.ttc", 9      # Helvetica Neue Condensed Black
SUB_FONT, SUB_IDX = "/System/Library/Fonts/HelveticaNeue.ttc", 4  # Condensed Bold
OUT = sys.argv[1] if len(sys.argv) > 1 else "cover-title-poster-en.png"
COLOR = (242, 189, 60, 255)
MAIN, SUB = "DESKTOP PET", "I MADE A"
SIZE, SQUEEZE, TRACK = 900, 0.78, 6

def word_mask(text, font, track):
    """逐字母排，字距 track；返回紧贴字形的遮罩"""
    l, t, r, b = font.getbbox("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    w = int(sum(font.getlength(c) for c in text) + track * len(text) + 40)
    im = Image.new("L", (w, b - t), 0); d = ImageDraw.Draw(im); x = 0
    for c in text:
        d.text((x, -t), c, font=font, fill=255); x += font.getlength(c) + track
    return im.crop(im.getbbox())

f = ImageFont.truetype(FONT, SIZE, index=IDX)
# 两行：DESKTOP 在上，PET 放大到同样宽（海报式左右对齐）
top = word_mask("DESKTOP", f, TRACK)
top = top.resize((int(top.width * SQUEEZE), top.height), Image.LANCZOS)
bot = word_mask("PET", f, TRACK)
bot = bot.resize((int(bot.width * SQUEEZE), bot.height), Image.LANCZOS)      # 先同样压窄
bot = bot.resize((top.width, int(bot.height * top.width / bot.width)), Image.LANCZOS)  # 再等比放大到同宽
LG = 30
main = Image.new("L", (top.width, top.height + LG + bot.height), 0)
main.paste(top, (0, 0)); main.paste(bot, (0, top.height + LG))
Hm = main.height

# 侧边小字：横排、字距拉开，转 90° 后长度等于主标题高度
sf = ImageFont.truetype(SUB_FONT, 200, index=SUB_IDX)
sub = word_mask(SUB, sf, 30)
sub = sub.resize((Hm, int(sub.height * Hm / sub.width)), Image.LANCZOS).rotate(90, expand=True)

PAD, GAP = 40, 34
W, H = PAD * 2 + sub.width + GAP + main.width, PAD * 2 + Hm
mask = Image.new("L", (W, H), 0)
mask.paste(sub, (PAD, PAD)); mask.paste(main, (PAD + sub.width + GAP, PAD))
out = Image.new("RGBA", (W, H), COLOR); out.putalpha(mask)
out = out.crop(out.getbbox()); out.save(OUT); print(OUT, out.size)
