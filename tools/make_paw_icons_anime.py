#!/usr/bin/env python3
"""
Pip 图标候选 v2：毛茸茸动漫风小猫爪（白底圆角方块），5 个版本 → preview/paw-icons-anime/
小猫从方块底部伸上来一只圆滚滚的爪子：毛边一簇簇、赛璐璐两三层色块、柔和深棕描边、粉豆豆、小星星。
用法：uv run --with numpy --with pillow python3 tools/make_paw_icons_anime.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

S = 2048
OUT = os.path.join(os.path.dirname(__file__), "..", "preview", "paw-icons-anime")
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5


def k(v):
    return v * S / 1024


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


# ---------- 有符号距离场（单位：超采样像素，<0 在里面） ----------

def sd_ellipse(cx, cy, rx, ry, ang=0.0):
    c, s = np.cos(ang), np.sin(ang)
    dx, dy = xx - k(cx), yy - k(cy)
    u = (dx * c + dy * s) / k(rx)
    v = (-dx * s + dy * c) / k(ry)
    r = np.sqrt(u * u + v * v)
    return (r - 1) * k(min(rx, ry))


def sd_box(cx, cy, hw, hh, rad):
    qx = np.abs(xx - k(cx)) - k(hw - rad)
    qy = np.abs(yy - k(cy)) - k(hh - rad)
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - k(rad)


def smin(a, b, r):
    r = k(r)
    h = np.clip(0.5 + 0.5 * (b - a) / r, 0, 1)
    return b * (1 - h) + a * h - r * h * (1 - h)


def fill(sd, soft=1.2):
    return np.clip(0.5 - sd / soft, 0, 1)


def ring(sd, w):
    return np.clip(k(w) - np.abs(sd), 0, 1.0)


class Canvas:
    def __init__(self):
        self.c = np.zeros((S, S, 3), np.float32)
        self.a = np.zeros((S, S), np.float32)

    def over(self, color, alpha):
        al = np.clip(alpha, 0, 1)[..., None]
        col = color if np.ndim(color) == 3 else np.broadcast_to(color, (S, S, 3))
        self.c = col * al + self.c * (1 - al)
        self.a = al[..., 0] + self.a * (1 - al[..., 0])

    def image(self):
        rgba = np.dstack([np.clip(self.c, 0, 1), np.clip(self.a, 0, 1)])
        return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").resize((1024, 1024), Image.LANCZOS)


def blur(a, px):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(k(px))), np.float32) / 255


def tile(cv):
    sd = sd_box(512, 512, 412, 412, 185)
    shadow = blur(fill(sd_box(512, 526, 412, 412, 185)), 22) * 0.22
    cv.over(np.zeros(3, np.float32), shadow)
    t = ((yy - k(100)) / k(824))[..., None]
    cv.over(rgb("#FFFFFF") * (1 - t) + rgb("#F4F2F6") * t, fill(sd))
    cv.over(np.zeros(3, np.float32), ring(sd + k(1.5), 1.5) * 0.08)
    return sd


# ---------- 爪子 ----------

def paw_sd(cx=512, cy=500, s=1.0, tilt=0.0):
    """圆手套形的爪子 + 从底边伸上来的小胳膊；上沿 4 个圆鼓包是脚趾"""
    def P(x, y):
        dx, dy = (x - 512) * s, (y - 500) * s
        c, sn = np.cos(tilt), np.sin(tilt)
        return cx + dx * c - dy * sn, cy + dx * sn + dy * c
    palm = sd_ellipse(*P(512, 520), 250 * s, 215 * s, tilt)
    toes = [sd_ellipse(*P(x, y), r * s, r * 0.92 * s, tilt) for x, y, r in
            [(338, 395, 92), (448, 330, 100), (576, 330, 100), (686, 395, 92)]]
    d = palm
    for t in toes:
        d = smin(d, t, 26 * s)
    ax, ay = P(512, 900)
    arm = sd_box(ax, ay, 165 * s, 330, 120 * s)
    d = smin(d, arm, 60 * s)
    centre = P(512, 470)
    return d, toes, palm, centre


def fluff(d, centre, n=46, amp=13, seed=0):
    """沿轮廓加一簇簇尖尖的毛：按绕中心的角度做锯齿状起伏"""
    rng = np.random.default_rng(seed)
    ang = np.arctan2(yy - k(centre[1]), xx - k(centre[0]))
    ph = rng.uniform(0, 6.28)
    tuft = np.abs(np.sin(ang * n / 2 + ph)) ** 0.55          # 0..1，尖头朝外
    wob = 0.5 + 0.5 * np.sin(ang * 7 + ph * 2)
    return d - k(amp) * (tuft * (0.7 + 0.3 * wob))


def beans(cv, pal, s=1.0, cx=512, cy=500, tilt=0.0):
    """粉豆豆：主肉垫是三瓣的圆胖爱心形，4 颗小豆；赛璐璐两层 + 一个白高光点"""
    def P(x, y):
        dx, dy = (x - 512) * s, (y - 500) * s
        c, sn = np.cos(tilt), np.sin(tilt)
        return cx + dx * c - dy * sn, cy + dx * sn + dy * c
    main = sd_ellipse(*P(512, 548), 118 * s, 92 * s, tilt)
    for x, y, r in [(452, 590, 58), (572, 590, 58), (512, 610, 62)]:
        main = smin(main, sd_ellipse(*P(x, y), r * s, r * 0.9 * s, tilt), 30 * s)
    small = [sd_ellipse(*P(x, y), 44 * s, 52 * s, tilt + a) for x, y, a in
             [(352, 420, -0.45), (452, 362, -0.15), (572, 362, 0.15), (672, 420, 0.45)]]
    for d in [main] + small:
        cv.over(pal["bean"], fill(d))
        # 右下一层暗色（向左上平移后挖掉）
        sh = np.maximum(d, -(np.roll(np.roll(d, -int(k(12 * s)), 0), -int(k(10 * s)), 1)))
        cv.over(pal["bean_dark"], fill(sh) * 0.9)
        cv.over(pal["line"], ring(d, 4.5 * s) * 0.85)
    # 高光点
    for x, y, rx, ry in [(470, 520, 30, 18), (338, 398, 13, 9), (440, 342, 14, 10), (560, 342, 14, 10), (660, 398, 13, 9)]:
        cv.over(np.ones(3, np.float32), fill(sd_ellipse(*P(x, y), rx * s, ry * s, -0.5 + tilt)) * 0.95)


def strands(cv, d, centre, color, rng, count=70, inner=(20, 70), clip=None):
    """毛的小细线：沿轮廓内侧随机画短弧线，动漫里表现毛绒的那几笔"""
    im = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(im)
    ys, xs = np.where((d < -k(inner[0])) & (d > -k(inner[1])))
    if len(xs) == 0:
        return
    for i in rng.choice(len(xs), size=min(count, len(xs)), replace=False):
        x, y = xs[i], ys[i]
        a = np.arctan2(y - k(centre[1]), x - k(centre[0]))
        L = k(rng.uniform(16, 30))
        pts = [(x - np.cos(a) * L * 0.2, y - np.sin(a) * L * 0.2),
               (x + np.cos(a + 0.25) * L * 0.5, y + np.sin(a + 0.25) * L * 0.5),
               (x + np.cos(a + 0.1) * L, y + np.sin(a + 0.1) * L)]
        dr.line(pts, fill=255, width=int(k(3.2)), joint="curve")
    m = np.asarray(im, np.float32) / 255 * (d < 0)
    if clip is not None:
        m = m * clip
    cv.over(color, m * 0.45)


def sparkle(cv, x, y, r, color, alpha=1.0):
    """四角星"""
    dx, dy = np.abs(xx - k(x)) / k(r), np.abs(yy - k(y)) / k(r)
    star = np.sqrt(dx) + np.sqrt(dy) - 1
    cv.over(color, fill(star * k(r) * 0.6) * alpha)


def heart(cv, x, y, r, color):
    """两个圆 + 转 45° 的方块"""
    a = sd_ellipse(x - r * 0.42, y - r * 0.2, r * 0.5, r * 0.5)
    b = sd_ellipse(x + r * 0.42, y - r * 0.2, r * 0.5, r * 0.5)
    u = ((xx - k(x)) + (yy - k(y + r * 0.12))) / np.sqrt(2)
    v = ((xx - k(x)) - (yy - k(y + r * 0.12))) / np.sqrt(2)
    sq = np.maximum(np.abs(u), np.abs(v)) - k(r * 0.6)
    d = np.minimum(np.minimum(a, b), np.maximum(sq, yy - k(y + r * 0.95)))
    d = np.minimum(np.minimum(a, b), sq)
    cv.over(color, fill(d))


def paw_icon(pal, seed=0, stripes=False, patch=False, deco="sparkle", s=0.92, tilt=-0.08):
    rng = np.random.default_rng(seed)
    cv = Canvas()
    tsd = tile(cv)
    inside = fill(tsd)
    d, toes, palm, centre = paw_sd(512, 520, s, tilt)
    fd = fluff(d, centre, seed=seed)
    # 地上的影子（只画在方块里）
    cv.over(np.zeros(3, np.float32), blur(fill(np.roll(fd, int(k(16)), 0)), 16) * 0.16 * inside)
    body = fill(fd) * inside
    # 底色 → 暗部（右下）→ 亮部（左上）
    cv.over(pal["fur"], body)
    shade = np.maximum(fd, -(np.roll(np.roll(fd, -int(k(34)), 0), -int(k(26)), 1)))
    cv.over(pal["fur_dark"], fill(shade) * inside * 0.95)
    if stripes:
        # 手臂上 3 道细横纹 + 爪子两侧各两道短纹，像虎斑猫
        bands = np.zeros((S, S), np.float32)
        for y0 in (720, 800, 880):
            bands = np.maximum(bands, fill(sd_ellipse(512, y0 + 0.0008 * (xx / k(1) - 512) ** 2, 175, 13)))
        for sx in (-1, 1):
            for y0, ln in ((500, 60), (560, 50)):
                bands = np.maximum(bands, fill(sd_ellipse(512 + sx * 228, y0, ln, 11, sx * 0.25)))
        cv.over(pal["stripe"], bands * (fd < -k(6)) * inside * 0.9)
    if patch:  # 三花：左上一块花斑
        p = fluff(sd_ellipse(660, 360, 175, 150, 0.3), (660, 360), n=30, amp=10, seed=seed + 1)
        cv.over(pal["patch"], fill(np.maximum(p, fd)) * inside)
        p2 = fluff(sd_ellipse(330, 330, 95, 85, -0.3), (330, 330), n=22, amp=8, seed=seed + 2)
        cv.over(pal["patch2"], fill(np.maximum(p2, fd)) * inside)
    hl = fill(np.maximum(fd, sd_ellipse(410, 410, 170, 120, -0.5))) * inside
    cv.over(pal["fur_light"], hl * 0.85)
    strands(cv, fd, centre, pal["line"], rng, clip=inside * (yy < k(905)))
    # 描边（柔和深色，不是纯黑）
    cv.over(pal["line"], ring(fd, 5.5) * inside)
    # 脚趾之间的分隔小弧（往下的一小撇）
    for x in (393, 512, 631):
        seg = sd_ellipse(x, 330 + (40 if x != 512 else 0), 10, 46)
        cv.over(pal["fur_dark"], fill(seg) * (fd < -k(8)) * inside * 0.0)
    beans(cv, pal, s=s, cx=512, cy=520, tilt=tilt)
    # 小装饰
    if deco == "sparkle":
        sparkle(cv, 790, 250, 40, pal["deco"]); sparkle(cv, 220, 300, 26, pal["deco2"]); sparkle(cv, 820, 420, 18, pal["deco2"])
    elif deco == "heart":
        heart(cv, 800, 260, 46, pal["deco"]); heart(cv, 228, 300, 28, pal["deco2"]); sparkle(cv, 830, 430, 18, pal["deco2"])
    return cv.image()


PALS = {
    "cream": dict(fur=rgb("#FFF8EF"), fur_dark=rgb("#EED9C4"), fur_light=rgb("#FFFFFF"), line=rgb("#8C6B5D"),
                  bean=rgb("#FFA9C0"), bean_dark=rgb("#F2849F"), deco=rgb("#FFD36E"), deco2=rgb("#FFB3C8")),
    "orange": dict(fur=rgb("#FFC27A"), fur_dark=rgb("#F29A4A"), fur_light=rgb("#FFE0B2"), line=rgb("#9A5A33"),
                   stripe=rgb("#E9893A"), bean=rgb("#FFA9C0"), bean_dark=rgb("#F2849F"), deco=rgb("#FFD36E"), deco2=rgb("#FFB3C8")),
    "calico": dict(fur=rgb("#FFFAF4"), fur_dark=rgb("#EADFD3"), fur_light=rgb("#FFFFFF"), line=rgb("#7E6A62"),
                   patch=rgb("#F5A35C"), patch2=rgb("#6B5A55"), bean=rgb("#FFA9C0"), bean_dark=rgb("#F2849F"), deco=rgb("#FFD36E"), deco2=rgb("#9FD3F5")),
    "pink": dict(fur=rgb("#FFE3EC"), fur_dark=rgb("#F8C4D5"), fur_light=rgb("#FFF6F9"), line=rgb("#B06A86"),
                 bean=rgb("#FF8FB0"), bean_dark=rgb("#EE6E95"), deco=rgb("#FF8FB0"), deco2=rgb("#FFC2D4")),
    "grey": dict(fur=rgb("#E6E9F0"), fur_dark=rgb("#C3C9D6"), fur_light=rgb("#F8F9FC"), line=rgb("#5E6577"),
                 bean=rgb("#FFA9C0"), bean_dark=rgb("#F2849F"), deco=rgb("#A9D4FF"), deco2=rgb("#FFC2D4")),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    vs = [("1-奶白小猫", dict(pal=PALS["cream"], seed=1)),
          ("2-橘猫", dict(pal=PALS["orange"], seed=2, stripes=True)),
          ("3-三花", dict(pal=PALS["calico"], seed=3, patch=True)),
          ("4-粉色毛毛", dict(pal=PALS["pink"], seed=4, deco="heart")),
          ("5-蓝灰小猫", dict(pal=PALS["grey"], seed=5))]
    ims = []
    for name, kw in vs:
        im = paw_icon(**kw)
        im.save(os.path.join(OUT, f"{name}.png"))
        ims.append((name, im)); print(name)
    W, pad = 360, 40
    sheet = Image.new("RGB", (pad + len(ims) * (W + pad), W + 120), "#E8E6EC")
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 30)
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(ims):
        x = pad + i * (W + pad)
        big = im.resize((W, W), Image.LANCZOS)
        sheet.paste(big, (x, 30), big)
        tw = d.textlength(name, font=font)
        d.text((x + (W - tw) / 2, W + 50), name, fill="#333", font=font)
        small = im.resize((64, 64), Image.LANCZOS)
        sheet.paste(small, (x + W - 70, W - 40), small)
    sheet.save(os.path.join(OUT, "对比.png"))


if __name__ == "__main__":
    main()
