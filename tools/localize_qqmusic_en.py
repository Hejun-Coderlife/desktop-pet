"""把 QQ 音乐窗口截图里的中文盖掉换成英文（英文版视频用）"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
SRC, OUT = "video/assets/qqmusic.png", "video/assets/qqmusic-en.png"
SF = "/System/Library/Fonts/SFNS.ttf"
im = Image.open(SRC).convert("RGBA"); d = ImageDraw.Draw(im)
badge = im.crop((236, 812, 302, 852))   # 「本地」的 24↓ 徽标，先存一份

PF = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
def font(px, weight=500):
    # 和 QQ 音乐界面一致用苹方：0=Regular 系列里找对应字重
    want = {400: "Regular", 500: "Medium", 600: "Semibold", 700: "Semibold"}[weight]
    for i in range(40):
        f = ImageFont.truetype(PF, px, index=i)
        if f.getname() == ("PingFang SC", want): return f
    return ImageFont.truetype(PF, px)

def erase(box, sample=None):
    """用框外左侧一点的底色填平"""
    sx, sy = sample or (box[0] - 4, (box[1] + box[3]) // 2)
    d.rectangle(box, fill=im.getpixel((sx, sy)))

def text(xy, s, px, color, weight=500, anchor="lm"):
    d.text(xy, s, font=font(px, weight), fill=color, anchor=anchor)

WHITE, GREY = (232, 232, 232), (140, 140, 140)
# 侧栏
for (y0, y1, s) in [(626, 670, "Liked · 140"), (718, 762, "Recent · 2500"), (811, 855, "Local · 3"), (904, 948, "Owned · 38")]:
    erase((122, y0, 290, y1))
    text((128, (y0 + y1) // 2), s, 28, WHITE)
# 「本地」的徽标往右挪一点，给英文让位
im.paste(badge, (288, 812))
erase((55, 1020, 310, 1062))
text((60, 1041), "Playlists", 26, WHITE, 600); text((172, 1041), "|  Saved", 26, GREY, 400)
# 歌曲信息
erase((498, 1032, 588, 1068), sample=(495, 1050)); text((501, 1050), "Artist", 26, GREY, 400)
erase((498, 1078, 1010, 1118), sample=(495, 1098)); text((501, 1098), "6,627 views      Released  2026-04-01", 26, GREY, 400)
# 播放器「超清」→ HD
d.rounded_rectangle((1836, 890, 1896, 926), radius=4, fill=(24, 24, 24))
d.rounded_rectangle((1838, 892, 1894, 924), radius=4, outline=WHITE, width=2); text((1866, 908), "HD", 21, WHITE, 600, "mm")
# 顶栏「免」图标、底栏「词」图标去掉
erase((1336, 60, 1398, 120), sample=(1420, 90))
erase((1892, 1210, 1946, 1262), sample=(1965, 1236))
# 「QQ音乐」水印 → QQ Music：用左边的天空补底再写
box = (1672, 160, 1956, 262)
patch = im.crop((box[0] - 600, box[1], box[2] - 600, box[3])).filter(ImageFilter.GaussianBlur(10))
feather = Image.new("L", patch.size, 0)
ImageDraw.Draw(feather).rounded_rectangle((12, 10, patch.width - 2, patch.height - 10), radius=14, fill=255)
im.paste(patch, box[:2], feather.filter(ImageFilter.GaussianBlur(5)))
text((1712, 211), "QQ Music", 38, (255, 255, 255), 600)
im.save(OUT); print(OUT)
