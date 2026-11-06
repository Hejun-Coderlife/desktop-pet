#!/usr/bin/env python3
"""
Pip 图标候选 v3：手绘涂鸦表情包风的白胖猫爪（白底），5 个版本 → preview/paw-icons-doodle/
风格要点：纯白胖爪 + 有一点抖的黑色手绘描边（粗细不均）+ 小粉豆豆（平涂，不反光）+ 一点点浅灰阴影 + 少量毛簇。
用法：uv run --with numpy --with pillow --with scipy python3 tools/make_paw_icons_doodle.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

S = 2048
OUT = os.path.join(os.path.dirname(__file__), "..", "preview", "paw-icons-doodle")
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
rng = np.random.default_rng(11)


def k(v):
    return v * S / 1024


def rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


INK = rgb("#2B2627")
WHITE = rgb("#FFFFFF")
GREY = rgb("#E4E3E8")
PINK = rgb("#FFB4C6")
PINK_D = rgb("#F497AE")
BLUSH = rgb("#FFC9D6")


def blur(a, px):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(k(px))), np.float32) / 255


# 手抖：低频噪声位移场（所有描边共用，像同一支笔画的）
_n = rng.standard_normal((S // 64 + 2, S // 64 + 2)).astype(np.float32)
WOBBLE = np.asarray(Image.fromarray(_n).resize((S, S), Image.BICUBIC), np.float32)
WIDTH = np.asarray(Image.fromarray(rng.standard_normal((S // 128 + 2, S // 128 + 2)).astype(np.float32)).resize((S, S), Image.BICUBIC), np.float32)


def sd_ellipse(cx, cy, rx, ry, ang=0.0):
    c, s = np.cos(ang), np.sin(ang)
    dx, dy = xx - k(cx), yy - k(cy)
    u = (dx * c + dy * s) / k(rx)
    v = (-dx * s + dy * c) / k(ry)
    return (np.sqrt(u * u + v * v) - 1) * k(min(rx, ry))


def sd_box(cx, cy, hw, hh, rad, ang=0.0):
    c, s = np.cos(ang), np.sin(ang)
    dx, dy = xx - k(cx), yy - k(cy)
    u, v = dx * c + dy * s, -dx * s + dy * c
    qx, qy = np.abs(u) - k(hw - rad), np.abs(v) - k(hh - rad)
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - k(rad)


def smin(a, b, r):
    r = k(r)
    h = np.clip(0.5 + 0.5 * (b - a) / r, 0, 1)
    return b * (1 - h) + a * h - r * h * (1 - h)


def fill(sd, soft=1.3):
    return np.clip(0.5 - sd / soft, 0, 1)


def stroke(sd, w=6.5, var=0.35):
    """手绘线：位置抖一点、粗细不均"""
    d = sd + k(2.2) * WOBBLE
    width = k(w) * (1 + var * WIDTH)
    return np.clip(width / 2 - np.abs(d) + 0.5, 0, 1)


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


def tile(cv, circle=False):
    sd = sd_ellipse(512, 512, 430, 430) if circle else sd_box(512, 512, 412, 412, 185)
    sh = sd_ellipse(512, 524, 430, 430) if circle else sd_box(512, 526, 412, 412, 185)
    cv.over(np.zeros(3, np.float32), blur(fill(sh), 20) * 0.16)
    cv.over(WHITE, fill(sd))
    cv.over(np.zeros(3, np.float32), np.clip(k(1.6) - np.abs(sd + k(1.6)), 0, 1) * 0.07)
    return fill(sd)


# ---------- 爪子零件 ----------

class Paw:
    """胖爪（掌心朝前）：圆胖手掌 + 上沿 4 个鼓包脚趾 + 可选从底边伸上来的胳膊"""

    def __init__(self, cx, cy, s=1.0, ang=0.0, arm=True, arm_len=520):
        self.cx, self.cy, self.s, self.ang = cx, cy, s, ang
        P = self.P
        palm = sd_ellipse(*P(0, 40), 232 * s, 192 * s, ang)
        self.toes = [(P(x, y), r * s) for x, y, r in [(-168, -88, 72), (-62, -150, 80), (62, -150, 80), (168, -88, 72)]]
        d = palm
        for (tx, ty), r in self.toes:
            d = smin(d, sd_ellipse(tx, ty, r, r * 0.95, ang), 14 * s)   # 小半径并起来 → 脚趾鼓包分得清
        if arm:
            ax, ay = P(0, 120 + arm_len / 2)
            d = smin(d, sd_box(ax, ay, 185 * s, arm_len / 2, 110 * s, ang), 70 * s)
        self.sd = d

    def P(self, x, y):
        c, sn = np.cos(self.ang), np.sin(self.ang)
        x, y = x * self.s, y * self.s
        return self.cx + x * c - y * sn, self.cy + x * sn + y * c

    def draw(self, cv, clip, beans=True, back=False):
        s, ang, P = self.s, self.ang, self.P
        cv.over(WHITE, fill(self.sd) * clip)
        # 一点点浅灰阴影：右下内侧，边缘很软
        inner = fill(self.sd) * (1 - fill(np.roll(np.roll(self.sd, -int(k(30 * s)), 0), -int(k(24 * s)), 1) + k(6)))
        cv.over(GREY, blur(inner, 5) * fill(self.sd) * clip * 0.9)
        if back:
            # 手背：脚趾之间三道短线
            for x in (-102, 0, 102):
                y0 = -128 if x == 0 else -112
                seg = sd_box(*P(x, y0 + 28), 2, 30 * s, 2, ang)
                cv.over(INK, stroke(seg, 5.5) * fill(self.sd + k(4)) * clip)
        if beans:
            main = sd_ellipse(*P(0, 72), 112 * s, 88 * s, ang)
            for x, y, r in [(-60, 112, 54), (60, 112, 54), (0, 128, 56)]:
                main = smin(main, sd_ellipse(*P(x, y), r * s, r * 0.9 * s, ang), 26 * s)
            cv.over(PINK, fill(main) * clip)
            cv.over(PINK_D, fill(np.maximum(main, -(np.roll(main, -int(k(14 * s)), 0)))) * clip * 0.8)
            for (tx, ty), r in self.toes:
                b = sd_ellipse(tx, ty + 8 * s, r * 0.52, r * 0.6, ang)
                cv.over(PINK, fill(b) * clip)
                cv.over(PINK_D, fill(np.maximum(b, -(np.roll(b, -int(k(8 * s)), 0)))) * clip * 0.7)
        cv.over(INK, stroke(self.sd) * clip)

    def tufts(self, cv, clip, where):
        """几簇小毛：在给定的点画 3 根短尖毛（V 字小簇），朝外"""
        im = Image.new("L", (S, S), 0)
        dr = ImageDraw.Draw(im)
        for (x, y, a) in where:
            X, Y = self.P(x, y)
            a = a + self.ang
            for j, da in enumerate((-0.35, 0, 0.35)):
                L = k(26 if j == 1 else 18) * self.s
                bx, by = k(X) + np.cos(a + da * 2.2) * k(10), k(Y) + np.sin(a + da * 2.2) * k(10)
                dr.line([(bx - np.cos(a + da) * L * 0.6, by - np.sin(a + da) * L * 0.6), (bx + np.cos(a + da) * L * 0.5, by + np.sin(a + da) * L * 0.5)],
                        fill=255, width=int(k(5)))
        cv.over(INK, np.asarray(im, np.float32) / 255 * clip)


def sparkle(cv, x, y, r, clip, color=INK, filled=False):
    dx, dy = np.abs(xx - k(x)) / k(r), np.abs(yy - k(y)) / k(r)
    star = (np.sqrt(dx) + np.sqrt(dy) - 1) * k(r) * 0.55
    if filled:
        cv.over(color, fill(star) * clip)
    else:
        cv.over(color, stroke(star, 5) * clip)


def heart(cv, x, y, r, clip, color=PINK, outline=True):
    """经典爱心曲线 (x²+y²-1)³ - x²y³ ≤ 0，用数值梯度换成近似距离"""
    u = (xx - k(x)) / k(r) * 1.15
    v = -(yy - k(y)) / k(r) * 1.15 + 0.15
    f = (u * u + v * v - 1) ** 3 - u * u * v ** 3
    from scipy.ndimage import distance_transform_edt as edt
    m = f <= 0
    d = (edt(~m) - edt(m)).astype(np.float32)   # 精确的有符号距离（像素）
    cv.over(color, fill(d) * clip)
    if outline:
        cv.over(INK, stroke(d, 5) * clip)


def motion(cv, x, y, r, clip, side=1):
    """挥手的小弧线 ))"""
    for i, rr in enumerate((r, r * 1.45)):
        d = sd_ellipse(x, y, rr, rr * 1.2)
        arc = (np.sign(xx - k(x)) == side) & (np.abs(yy - k(y)) < k(rr * 0.75))
        cv.over(INK, stroke(d, 5.5) * arc * clip)


def blush(cv, x, y, clip):
    cv.over(BLUSH, blur(fill(sd_ellipse(x, y, 36, 22)), 6) * clip * 0.9)


# ---------- 5 个版本 ----------

def v1():
    """① 举起一只白胖爪"""
    cv = Canvas(); clip = tile(cv)
    p = Paw(512, 560, 0.95, -0.06)
    p.draw(cv, clip)
    sparkle(cv, 800, 250, 34, clip); sparkle(cv, 230, 300, 22, clip, PINK, True)
    return cv.image()


def v2():
    """② 两只爪子扒在底边往上看（手背朝前）"""
    cv = Canvas(); clip = tile(cv)
    for cx, a in ((345, 0.10), (679, -0.10)):
        p = Paw(cx, 720, 0.72, a, arm=True, arm_len=500)
        p.draw(cv, clip, beans=False, back=True)
    heart(cv, 512, 330, 70, clip)
    sparkle(cv, 300, 330, 22, clip); sparkle(cv, 730, 300, 28, clip)
    return cv.image()


def v3():
    """③ 挥手打招呼"""
    cv = Canvas(); clip = tile(cv)
    p = Paw(500, 560, 0.9, 0.22)
    p.draw(cv, clip)
    motion(cv, 770, 360, 70, clip, side=1)
    motion(cv, 250, 300, 50, clip, side=-1)
    return cv.image()


def v4():
    """④ 圆形白底 + 爪子 + 小爱心冒出来"""
    cv = Canvas(); clip = tile(cv, circle=True)
    p = Paw(512, 590, 0.86, 0.0)
    p.draw(cv, clip)
    heart(cv, 760, 250, 56, clip)
    heart(cv, 280, 280, 34, clip)
    return cv.image()


def v5():
    """⑤ 两只爪捧着一颗粉爱心（掌心朝前）"""
    cv = Canvas(); clip = tile(cv)
    heart(cv, 512, 420, 150, clip)
    for cx, a in ((330, 0.38), (694, -0.38)):
        p = Paw(cx, 690, 0.6, a, arm=True, arm_len=600)
        p.draw(cv, clip)
    sparkle(cv, 790, 230, 26, clip); sparkle(cv, 236, 250, 20, clip, PINK, True)
    return cv.image()


def main():
    os.makedirs(OUT, exist_ok=True)
    vs = [("1-举爪", v1), ("2-扒边偷看", v2), ("3-挥手", v3), ("4-圆底爱心", v4), ("5-捧爱心", v5)]
    ims = []
    for name, fn in vs:
        im = fn(); im.save(os.path.join(OUT, f"{name}.png")); ims.append((name, im)); print(name)
    W, pad = 360, 40
    sheet = Image.new("RGB", (pad + len(ims) * (W + pad), W + 120), "#E8E6EC")
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 30)
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(ims):
        x = pad + i * (W + pad)
        big = im.resize((W, W), Image.LANCZOS); sheet.paste(big, (x, 30), big)
        tw = d.textlength(name, font=font); d.text((x + (W - tw) / 2, W + 50), name, fill="#333", font=font)
        small = im.resize((64, 64), Image.LANCZOS); sheet.paste(small, (x + W - 70, W - 40), small)
    sheet.save(os.path.join(OUT, "对比.png"))


if __name__ == "__main__":
    main()
