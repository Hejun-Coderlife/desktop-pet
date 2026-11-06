#!/usr/bin/env python3
"""
把 assets-src/paw-sticker-pink.png（用户给的毛绒猫爪）里的粉色换成棕色系，出 5 个版本 + 做成图标。
粉色按「粉度」权重（色相在红粉一带 × 饱和度）平滑替换；按原亮度映射到棕色深浅渐变上，
所以高光、阴影、边缘的毛都保留；白毛饱和度低几乎不受影响。
用法：uv run --with numpy --with pillow python3 tools/recolor_paw.py
"""
import os, colorsys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(ROOT, "assets-src", "paw-sticker-pink.png")
OUT = os.path.join(ROOT, "preview", "paw-brown")

# 每个版本：(名字, 最暗处颜色, 中间色, 最亮处颜色)
VARIANTS = [
    ("1-奶茶棕", "#A9805F", "#D2AE8C", "#F1DFCC"),
    ("2-焦糖", "#9A5F33", "#C98A56", "#EBC9A4"),
    ("3-可可", "#6E4630", "#9C6C4E", "#D3B29A"),
    ("4-摩卡浅", "#B79579", "#DABFA6", "#F4E8DB"),
    ("5-巧克力", "#4E3122", "#7D5139", "#B98E72"),
]


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255


def main():
    os.makedirs(OUT, exist_ok=True)
    im = np.asarray(Image.open(SRC).convert("RGB"), np.float32) / 255
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    mx, mn = im.max(-1), im.min(-1)
    sat = (mx - mn) / (mx + 1e-6)
    # 色相（度）
    hue = np.zeros_like(mx)
    d = mx - mn + 1e-6
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    pinkhue = np.clip(1 - np.minimum(np.abs(hue - 360), np.abs(hue)) / 40, 0, 1)   # 0°/360° 附近
    w = pinkhue * np.clip((sat - 0.06) / 0.18, 0, 1)
    w = np.asarray(Image.fromarray((w * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # 粉色区域的亮度范围（用于映射到棕色渐变）
    lo, hi = np.percentile(lum[w > 0.6], 2), np.percentile(lum[w > 0.6], 99.5)
    t = np.clip((lum - lo) / (hi - lo + 1e-6), 0, 1)[..., None]
    ims = []
    for name, dark, mid, light in VARIANTS:
        D, M, L = hexrgb(dark), hexrgb(mid), hexrgb(light)
        ramp = np.where(t < 0.55, D + (M - D) * (t / 0.55), M + (L - M) * ((t - 0.55) / 0.45))
        # 高光（接近白、原本就是亮点）保持白
        spec = np.clip((lum[..., None] - 0.93) / 0.05, 0, 1)
        ramp = ramp * (1 - spec) + im * spec
        out = im * (1 - w[..., None]) + ramp * w[..., None]
        o = Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8))
        o.save(os.path.join(OUT, f"{name}-原图.png"))
        ims.append((name, o, icon(o)))
        print(name)
    sheet(ims)


def icon(img):
    """白色圆角方块图标（1024，Big Sur 网格），图贴在方块里"""
    N = 1024
    can = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh = Image.new("L", (N, N), 0)
    ImageDraw.Draw(sh).rounded_rectangle([100, 114, 924, 938], 185, fill=70)
    can.paste(Image.new("RGBA", (N, N), (0, 0, 0, 255)), (0, 0), sh.filter(ImageFilter.GaussianBlur(22)))
    mask = Image.new("L", (N * 2, N * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle([200, 200, 1848, 1848], 370, fill=255)
    mask = mask.resize((N, N), Image.LANCZOS)
    tile = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    art = img.resize((900, 900), Image.LANCZOS)   # 原图四周留白较多，放大一些
    tile.paste(art, ((N - 900) // 2, (N - 900) // 2 + 10))
    can.paste(tile, (0, 0), mask)
    return can


def sheet(ims):
    W, pad = 360, 40
    s = Image.new("RGB", (pad + len(ims) * (W + pad), W + 120), "#E8E6EC")
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Medium.ttc", 30)
    d = ImageDraw.Draw(s)
    for i, (name, _, ic) in enumerate(ims):
        ic.save(os.path.join(OUT, f"{name}-图标.png"))
        x = pad + i * (W + pad)
        big = ic.resize((W, W), Image.LANCZOS); s.paste(big, (x, 30), big)
        tw = d.textlength(name, font=font); d.text((x + (W - tw) / 2, W + 50), name, fill="#333", font=font)
        sm = ic.resize((64, 64), Image.LANCZOS); s.paste(sm, (x + W - 70, W - 40), sm)
    s.save(os.path.join(OUT, "对比.png"))


if __name__ == "__main__":
    main()
