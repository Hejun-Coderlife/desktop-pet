#!/usr/bin/env python3
"""
Pip 程序图标候选：白底圆角方块 + 猫爪，5 个版本 → preview/paw-icons/
用法：uv run --with numpy --with pillow python3 tools/make_paw_icons.py
全部用距离场画（2048 超采样再缩到 1024），肉垫有体积光，不是平涂。
"""
import os
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

S = 2048                      # 超采样画布
OUT = os.path.join(os.path.dirname(__file__), "..", "preview", "paw-icons")
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
rng = np.random.default_rng(3)


def k(v):  # 1024 坐标 → 超采样坐标
    return v * S / 1024


# ---------- 形状 ----------

def ellipse_f(cx, cy, rx, ry, ang=0.0):
    """归一化椭圆半径：<1 在里面"""
    c, s = np.cos(ang), np.sin(ang)
    dx, dy = xx - k(cx), yy - k(cy)
    u = (dx * c + dy * s) / k(rx)
    v = (-dx * s + dy * c) / k(ry)
    return np.sqrt(u * u + v * v)


def smin(a, b, r=0.25):
    h = np.clip(0.5 + 0.5 * (b - a) / r, 0, 1)
    return b * (1 - h) + a * h - r * h * (1 - h)


def paw_fields(cx=512, cy=520, scale=1.0, tilt=0.0):
    """返回 (主肉垫场, [4 个脚趾场])，都是归一化半径场"""
    def P(x, y):  # 绕中心旋转 + 缩放
        dx, dy = (x - 512) * scale, (y - 520) * scale
        c, s = np.cos(tilt), np.sin(tilt)
        return cx + dx * c - dy * s, cy + dx * s + dy * c
    sc = scale
    # 主肉垫：上面一个大椭圆 + 下面三个圆鼓包，平滑并起来 → 圆润的"三瓣"形
    parts = [ellipse_f(*P(512, 612), 150 * sc, 112 * sc, tilt),
             ellipse_f(*P(420, 676), 84 * sc, 80 * sc, tilt),
             ellipse_f(*P(604, 676), 84 * sc, 80 * sc, tilt),
             ellipse_f(*P(512, 700), 96 * sc, 78 * sc, tilt)]
    main = parts[0]
    for p in parts[1:]:
        main = smin(main, p, 0.35)
    toes = []
    for ang, r, rx, ry in [(-58, 238, 58, 72), (-20, 262, 66, 84), (20, 262, 66, 84), (58, 238, 58, 72)]:
        a = np.radians(ang)
        tx, ty = 512 + r * np.sin(a), 640 - r * np.cos(a)
        toes.append(ellipse_f(*P(tx, ty), rx * sc, ry * sc, a + tilt))
    return main, toes


def cover(f, soft=1.5):
    """场 → 抗锯齿覆盖率（按像素宽度估算边缘）"""
    gy, gx = np.gradient(f)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    return np.clip(0.5 - (f - 1) / (g * soft), 0, 1)


def dome_light(f, light=(-0.45, -0.6, 0.66), gloss=60, spec=0.55):
    """把场当成圆顶：法线 → 漫反射 + 高光"""
    h = np.sqrt(np.clip(1 - np.minimum(f, 1) ** 2, 0, 1))
    gy, gx = np.gradient(h * k(60))
    n = np.stack([-gx, -gy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    L = np.array(light, np.float32); L /= np.linalg.norm(L)
    diff = np.clip((n * L).sum(-1), 0, 1)
    H = L + np.array([0, 0, 1], np.float32); H /= np.linalg.norm(H)
    sp = np.clip((n * H).sum(-1), 0, 1) ** gloss * spec
    return diff, sp, h


# ---------- 合成 ----------

def rgb(hexs):
    return np.array([int(hexs[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


class Canvas:
    def __init__(self):
        self.c = np.zeros((S, S, 3), np.float32)
        self.a = np.zeros((S, S), np.float32)

    def over(self, color, alpha):
        alpha = np.clip(alpha, 0, 1)[..., None]
        col = color if color.ndim == 3 else np.broadcast_to(color, (S, S, 3))
        self.c = col * alpha + self.c * (1 - alpha)
        self.a = alpha[..., 0] + self.a * (1 - alpha[..., 0])

    def image(self):
        rgba = np.dstack([np.clip(self.c, 0, 1), np.clip(self.a, 0, 1)])
        im = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
        return im.resize((1024, 1024), Image.LANCZOS)


def blur(a, px):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(k(px))), np.float32) / 255


def tile(cv):
    """白色圆角方块（Big Sur 网格 824 / 圆角 185）+ 底部柔影 + 极淡的上亮下灰"""
    x0, y0, side, rad = k(100), k(100), k(824), k(185)

    def sd(ox=0, oy=0):
        cx = np.abs(xx - ox - (x0 + side / 2)) - (side / 2 - rad)
        cy = np.abs(yy - oy - (y0 + side / 2)) - (side / 2 - rad)
        return np.sqrt(np.maximum(cx, 0) ** 2 + np.maximum(cy, 0) ** 2) + np.minimum(np.maximum(cx, cy), 0) - rad
    shadow = blur((sd(0, k(14)) < 0).astype(np.float32), 22) * 0.30
    cv.over(np.zeros(3, np.float32), shadow)
    t = ((yy - y0) / side)[..., None]
    body = rgb("#FFFFFF") * (1 - t) + rgb("#F1F1F3") * t
    cv.over(body, np.clip(0.5 - sd() / 1.2, 0, 1))
    # 内侧一圈极淡的描边，白底放在白桌面上也看得出边
    edge = np.clip(1 - np.abs(sd() + k(1.5)) / k(1.5), 0, 1) * 0.10
    cv.over(np.zeros(3, np.float32), edge)
    return sd() < 0


def pad_shading(cv, f, base, dark, gloss=60, spec=0.55, ao=0.25):
    diff, sp, h = dome_light(f, gloss=gloss, spec=spec)
    m = cover(f)
    col = dark[None, None] * (1 - diff[..., None]) + base[None, None] * diff[..., None]
    col = col * (1 - ao * (1 - h[..., None]) ** 3)
    col = col + sp[..., None]
    cv.over(col, m)


def drop_shadow(cv, mask, dy=14, px=14, op=0.18, inside=None):
    sh = blur(np.roll(mask, int(k(dy)), axis=0), px) * op
    if inside is not None:
        sh *= inside
    cv.over(np.zeros(3, np.float32), sh)


def all_pads(main, toes):
    u = main
    for t in toes:
        u = np.minimum(u, t)
    return u


# ---------- 5 个版本 ----------

def v1_pink_beans():
    """① 粉色肉垫：果冻感的粉色豆豆，白底干净"""
    cv = Canvas(); inside = tile(cv)
    main, toes = paw_fields(scale=0.95)
    drop_shadow(cv, cover(all_pads(main, toes)), 16, 16, 0.20, inside)
    for f in [main] + toes:
        pad_shading(cv, f, rgb("#FFB3C4"), rgb("#E8708E"), gloss=70, spec=0.75)
    return cv.image()


def fur_paw(cv, inside, fur, fur_dark, stripes=None, pad=("#F7A9BA", "#D9728B"), scale=1.0):
    """毛绒爪子：外轮廓是所有肉垫外扩的一团，边缘带绒毛，里面嵌粉色肉垫"""
    main, toes = paw_fields(scale=scale)
    # 外轮廓：把肉垫场整体放大（除以 1.32），再平滑并起来，边缘用噪声扰动出毛
    outer = smin(main / 1.30, toes[0] / 1.45, 0.5)
    for t in toes[1:]:
        outer = smin(outer, t / 1.45, 0.5)
    noise = blur(rng.random((S, S)).astype(np.float32), 0.8) - 0.5
    ang = np.arctan2(yy - k(560), xx - k(512))
    fuzz = 0.05 * np.sin(ang * 90 + noise * 8) + noise * 0.35
    outer_f = outer + fuzz * 0.07
    om = cover(outer_f, 2)
    drop_shadow(cv, om, 18, 18, 0.22, inside)
    diff, sp, h = dome_light(np.minimum(outer, 1), gloss=12, spec=0.08)
    col = fur_dark[None, None] * (1 - diff[..., None]) + fur[None, None] * diff[..., None]
    if stripes is not None:
        band = np.sin((yy * 0.35 - xx * 0.94) / k(26) + noise * 1.5)
        st = np.clip((band - 0.2) * 2.5, 0, 1) * 0.85
        col = col * (1 - st[..., None]) + stripes[None, None] * st[..., None] * (0.6 + 0.4 * diff[..., None])
    # 毛的细纹理
    grain = (blur(rng.random((S, S)).astype(np.float32), 0.6) - 0.5) * 0.10
    col = col * (1 + grain[..., None])
    cv.over(col, om)
    # 肉垫比外轮廓小一圈，并在毛里压出一点暗边
    for f in [main * 1.12] + [t * 1.15 for t in toes]:
        cv.over(np.zeros(3, np.float32), blur(cover(f / 1.06), 4) * 0.18)
        pad_shading(cv, f, rgb(pad[0]), rgb(pad[1]), gloss=50, spec=0.5)


def v2_cream_fur():
    """② 奶白毛绒爪：和 Pip 同款米白绒毛 + 粉肉垫"""
    cv = Canvas(); inside = tile(cv)
    fur_paw(cv, inside, rgb("#FBF5EC"), rgb("#D9CFC2"), scale=0.82)
    return cv.image()


def v3_line():
    """③ 线条贴纸：深灰粗描边 + 淡粉填色，像手账贴纸"""
    cv = Canvas(); inside = tile(cv)
    main, toes = paw_fields(scale=0.92)
    ink = rgb("#3B3436")
    for f in [main] + toes:
        cv.over(rgb("#FFD9E1"), cover(f))
        gy, gx = np.gradient(f)
        g = np.sqrt(gx * gx + gy * gy) + 1e-6
        ring = np.clip(k(7) - np.abs((f - 1) / g), 0, 1)   # 距离边界 7 点以内 = 描边
        cv.over(ink, ring)
    # 每颗肉垫的小高光
    for (x, y, r) in [(470, 600, 26), (325, 505, 14), (452, 430, 15), (590, 430, 15), (712, 505, 14)]:
        cv.over(np.ones(3, np.float32), cover(ellipse_f(x, y, r * 1.5, r * 0.8, -0.6)) * 0.85)
    return cv.image()


def v4_glossy_black():
    """④ 黑色亮面爪印：经典爪印剪影，钢琴漆质感，稍微歪一点"""
    cv = Canvas(); inside = tile(cv)
    main, toes = paw_fields(scale=0.95, tilt=np.radians(-12), cx=520)
    drop_shadow(cv, cover(all_pads(main, toes)), 16, 14, 0.25, inside)
    for f in [main] + toes:
        pad_shading(cv, f, rgb("#4A4A50"), rgb("#101012"), gloss=90, spec=0.9, ao=0.4)
    return cv.image()


def v5_orange_tabby():
    """⑤ 橘猫爪：橘色虎斑毛 + 粉肉垫"""
    cv = Canvas(); inside = tile(cv)
    fur_paw(cv, inside, rgb("#F6B36A"), rgb("#C97A34"), stripes=rgb("#D9822F") * 0.82, scale=0.82)
    return cv.image()


def main():
    os.makedirs(OUT, exist_ok=True)
    makers = [("1-粉色肉垫", v1_pink_beans), ("2-奶白毛绒爪", v2_cream_fur), ("3-线条贴纸", v3_line),
              ("4-黑色亮面", v4_glossy_black), ("5-橘猫爪", v5_orange_tabby)]
    ims = []
    for name, fn in makers:
        im = fn()
        im.save(os.path.join(OUT, f"{name}.png"))
        ims.append((name, im))
        print(name)
    # 对照图：浅灰底一排，下面标号
    W, pad = 360, 40
    sheet = Image.new("RGB", (pad + len(ims) * (W + pad), W + 120), "#E6E6EA")
    font = None
    for p in ["/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/STHeiti Medium.ttc"]:
        if os.path.exists(p):
            font = ImageFont.truetype(p, 30); break
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(ims):
        x = pad + i * (W + pad)
        sheet.paste(im.resize((W, W), Image.LANCZOS), (x, 30), im.resize((W, W), Image.LANCZOS))
        tw = d.textlength(name, font=font)
        d.text((x + (W - tw) / 2, W + 50), name, fill="#333", font=font)
        # 小尺寸预览（程序坞/访达里的大小）
        small = im.resize((64, 64), Image.LANCZOS)
        sheet.paste(small, (x + W - 70, W - 40), small)
    sheet.save(os.path.join(OUT, "对比.png"))


if __name__ == "__main__":
    main()
