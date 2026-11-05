"""封面标题字：自己做了一个 / 桌面宠物 —— 卡通童话风，透明背景 PNG"""
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter
import numpy as np

FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/9f4afe404b767c06554b8b78551e10e92f695147.asset/AssetData/WawaTC-Regular.otf"
SC = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/37618f984b05fb22375ca0987912653aba363389.asset/AssetData/WawaSC-Regular.otf"
OUT = sys.argv[1] if len(sys.argv) > 1 else "cover-title.png"
W, H = 2400, 1300
INK = (43, 36, 112)          # 深靛蓝描边

def glyph(ch, size, stroke, angle):
    f = ImageFont.truetype(SC, size)
    pad = stroke + size // 4
    im = Image.new("L", (size + pad * 2, size + pad * 2), 0)
    ImageDraw.Draw(im).text((pad, pad), ch, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    return im.rotate(angle, resample=Image.BICUBIC, center=(im.width / 2, im.height / 2))

def line_masks(text, size, cx, cy, spacing, arch, tilt, strokes, bounce):
    """返回每种描边宽度的整行遮罩；字沿圆弧排，交替微跳"""
    masks = [Image.new("L", (W, H), 0) for _ in strokes]
    n = len(text)
    for i, ch in enumerate(text):
        u = (i - (n - 1) / 2)
        x = cx + u * spacing
        y = cy + arch * (u / ((n - 1) / 2)) ** 2 + (bounce if i % 2 else -bounce)
        ang = -u * tilt + (4 if i % 2 else -4)
        for m, s in zip(masks, strokes):
            g = glyph(ch, size, s, ang)
            layer = Image.new("L", (W, H), 0)
            layer.paste(g, (int(x - g.width / 2), int(y - g.height / 2)))
            m.paste(ImageChops.lighter(m, layer))
    return masks

def vgrad(top, mid, bot, y0, y1):
    ys = np.clip((np.arange(H) - y0) / max(1, y1 - y0), 0, 1)[:, None]
    t, m, b = (np.array(c, float) for c in (top, mid, bot))
    c = np.where(ys < 0.5, t + (m - t) * (ys / 0.5)[..., None][:, :, 0:1].squeeze(-1)[..., None] if False else 0, 0)
    out = np.zeros((H, W, 3))
    for y in range(H):
        k = ys[y, 0]
        col = t + (m - t) * (k / 0.5) if k < 0.5 else m + (b - m) * ((k - 0.5) / 0.5)
        out[y, :] = col
    return Image.fromarray(out.astype(np.uint8), "RGB")

def solid(rgb):
    return Image.new("RGB", (W, H), rgb)

def put(canvas, rgb_img, mask, alpha=1.0):
    if alpha < 1: mask = mask.point(lambda v: int(v * alpha))
    layer = rgb_img.convert("RGBA"); layer.putalpha(mask)
    canvas.alpha_composite(layer)

def star(draw, x, y, r, fill):
    pts = []
    for k in range(8):
        a = k * math.pi / 4 - math.pi / 2
        rr = r if k % 2 == 0 else r * 0.22
        pts.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    draw.polygon(pts, fill=fill)

canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

lines = [
    # 文字, 字号, 中心, 字距, 弧度, 每字倾斜, 跳动, 渐变(上中下), 描边
    dict(text="自己做了一个", size=230, cx=W / 2, cy=330, sp=255, arch=70, tilt=2.2, bounce=10,
         grad=((225, 248, 255), (120, 205, 255), (40, 130, 230)), strokes=(9, 30, 52)),
    dict(text="桌面宠物", size=430, cx=W / 2, cy=830, sp=470, arch=55, tilt=3.0, bounce=18,
         grad=((255, 250, 205), (255, 205, 60), (255, 125, 50)), strokes=(11, 40, 74)),
]

for L in lines:
    fill, ink, white = line_masks(L["text"], L["size"], L["cx"], L["cy"], L["sp"], L["arch"], L["tilt"],
                                  L["strokes"], L["bounce"])
    y0, y1 = L["cy"] - L["size"] * 0.55, L["cy"] + L["size"] * 0.6 + L["arch"]
    # 投影
    sh = Image.new("L", (W, H), 0); sh.paste(white, (0, int(L["size"] * 0.06)))
    put(canvas, solid((30, 20, 80)), sh.filter(ImageFilter.GaussianBlur(L["size"] * 0.05)), 0.45)
    # 白色外描边 + 深色内描边（外圈白边让它放在任何底图上都清楚）
    put(canvas, solid((255, 255, 255)), white)
    put(canvas, solid(INK), ink)
    # 主体渐变
    put(canvas, vgrad(*L["grad"], y0, y1), fill)
    # 底部内阴影：遮罩下移后与原遮罩的差
    inner = ImageChops.subtract(fill, ImageChops.offset(fill, 0, -int(L["size"] * 0.035)))
    put(canvas, solid((200, 70, 40) if L is lines[1] else (20, 80, 180)), inner.filter(ImageFilter.GaussianBlur(3)), 0.55)
    # 顶部高光：腐蚀后的遮罩只留上半部分
    er = fill.filter(ImageFilter.MinFilter(int(L["size"] * 0.03) | 1))
    hl = ImageChops.subtract(er, ImageChops.offset(er, 0, int(L["size"] * 0.05)))
    put(canvas, solid((255, 255, 255)), hl.filter(ImageFilter.GaussianBlur(4)), 0.6)

# 星星闪光
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); gd = ImageDraw.Draw(glow)
sparks = [(260, 210, 70), (2150, 250, 55), (2290, 560, 75), (110, 640, 60), (140, 1160, 45), (2290, 1180, 55), (1200, 90, 40)]
for x, y, r in sparks: star(gd, x, y, r * 1.5, (255, 230, 120, 140))
canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(14)))
sd = ImageDraw.Draw(canvas)
for x, y, r in sparks:
    star(sd, x, y, r + 8, INK + (255,))
    star(sd, x, y, r, (255, 248, 200, 255))
for x, y in [(420, 120), (1950, 110), (2300, 950), (90, 450), (1500, 1230), (850, 1240)]:
    sd.ellipse((x - 12, y - 12, x + 12, y + 12), fill=(255, 240, 170, 255), outline=INK, width=5)

canvas = canvas.crop(canvas.getbbox())
canvas.save(OUT)
print(OUT, canvas.size)
