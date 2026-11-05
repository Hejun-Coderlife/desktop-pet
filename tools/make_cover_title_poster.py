"""封面字·海报风：瘦高粗黑体主标题 + 侧边竖排小字（仿电影海报排法），纯色无描边，透明 PNG"""
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/f14049099a04e570b893c01d9a4cd71f87c9e8d8.asset/AssetData/Lantinghei.ttc"
OUT = sys.argv[1] if len(sys.argv) > 1 else "cover-title-poster.png"
COLOR = (242, 189, 60, 255)      # 芥末黄
MAIN, SUB = "桌面宠物", "自己做了一个"
SIZE = 900                        # 主标题字号（渲染后再横向压窄）
SQUEEZE = 0.46                    # 横向压缩比 → 瘦高
GAP = 10                          # 主标题字间距（压窄后）

def glyph(ch, size, squeeze):
    f = ImageFont.truetype(FONT, size, index=2)
    l, t, r, b = f.getbbox(ch)
    im = Image.new("L", (r - l, b - t), 0)
    ImageDraw.Draw(im).text((-l, -t), ch, font=f, fill=255)
    return im.resize((max(1, int(im.width * squeeze)), im.height), Image.LANCZOS)

# 主标题：每个字压窄后统一拉到同一高度，紧密排一行
gs = [glyph(c, SIZE, SQUEEZE) for c in MAIN]
Hm = max(g.height for g in gs)
gs = [g.resize((g.width, Hm), Image.LANCZOS) for g in gs]
Wm = sum(g.width for g in gs) + GAP * (len(gs) - 1)

# 竖排副标题：字竖着叠、整体高度和主标题一致，像海报上转 90° 的小字
sub_size = int(Hm / len(SUB) * 0.78)
sg = [glyph(c, sub_size, 1.0) for c in SUB]
step = Hm / len(SUB)
Ws = max(g.width for g in sg)

PAD, SIDE_GAP = 40, 36
W = PAD * 2 + Wm + SIDE_GAP + Ws
H = PAD * 2 + Hm
mask = Image.new("L", (W, H), 0)
x = PAD
for g in gs:
    mask.paste(g, (x, PAD)); x += g.width + GAP
sx = PAD + Wm + SIDE_GAP
for i, g in enumerate(sg):
    y = PAD + int(i * step + (step - g.height) / 2)
    mask.paste(g, (sx + (Ws - g.width) // 2, y))

out = Image.new("RGBA", (W, H), COLOR); out.putalpha(mask)
out = out.crop(out.getbbox()); out.save(OUT); print(OUT, out.size)
