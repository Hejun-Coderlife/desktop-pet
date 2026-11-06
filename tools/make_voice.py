#!/usr/bin/env python3
"""
生成 Pip 的声音（Resources/sounds/*.wav，Mac / Windows 两版共用）。

不用正弦波"哔哔"（电子感重），改成嗓音合成：
  声门脉冲（谐波按 -12dB/倍频程衰减）→ 元音共振峰（a/u/i/嗯…随时间滑动）
  + 随机音高抖动/振幅抖动 + 一点气声 + 小房间混响。
落地 = 布料"噗"（低频闷响 + 低通噪声），举牌 = 拇指琴"叮咚"。

用法：uv run --with numpy --with scipy python3 tools/make_voice.py
"""
import os
import wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "sounds")
rng = np.random.default_rng(7)

# 小孩/小动物的元音共振峰 (F, 带宽, 增益)
VOWELS = {
    "a": [(1050, 130, 1.0), (1600, 150, 0.7), (3200, 250, 0.25)],
    "u": [(420, 90, 1.0), (1000, 120, 0.35), (2900, 250, 0.12)],
    "i": [(380, 90, 1.0), (2800, 180, 0.55), (3700, 260, 0.3)],
    "e": [(650, 110, 1.0), (1900, 160, 0.55), (3100, 250, 0.22)],
    "m": [(300, 80, 1.0), (1300, 200, 0.10), (2600, 300, 0.05)],   # 闭嘴哼
}


def interp_track(points, n):
    """points: [(u, value)]，u∈[0,1]，线性插值成 n 个采样"""
    u = np.linspace(0, 1, n)
    xs, ys = zip(*points)
    return np.interp(u, xs, ys)


def smooth_noise(n, rate_hz, depth):
    """慢变随机（抖动）：每秒 rate_hz 个随机点，三次平滑"""
    k = max(2, int(n / SR * rate_hz) + 2)
    pts = rng.standard_normal(k)
    return 1 + depth * np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)


def voice(dur, pitch_pts, vowel_pts, env_pts, breath=0.05, jitter=0.012):
    """
    pitch_pts: [(u, Hz)]；vowel_pts: [(u, 'a')] 元音在这些时间点之间平滑过渡；env_pts: [(u, 0..1)]
    """
    n = int(dur * SR)
    f0 = interp_track(pitch_pts, n) * smooth_noise(n, 18, jitter)
    phase = 2 * np.pi * np.cumsum(f0) / SR
    # 元音过渡：对每个共振峰的 F / B / 增益做插值
    us = [p[0] for p in vowel_pts]
    forms = []
    for j in range(3):
        F = np.interp(np.linspace(0, 1, n), us, [VOWELS[v][j][0] for _, v in vowel_pts])
        B = np.interp(np.linspace(0, 1, n), us, [VOWELS[v][j][1] for _, v in vowel_pts])
        G = np.interp(np.linspace(0, 1, n), us, [VOWELS[v][j][2] for _, v in vowel_pts])
        forms.append((F, B, G))

    def H(freq):
        h = np.zeros(n)
        for F, B, G in forms:
            h += G / (1 + ((freq - F) / (B / 2)) ** 2)
        return h

    out = np.zeros(n)
    kmax = int(6000 / f0.min())
    for k in range(1, kmax + 1):
        fk = k * f0
        amp = (1 / k ** 1.0) * H(fk) * (fk < 7000)   # 声门源 -6dB/倍频程 + 共振峰
        out += amp * np.sin(k * phase + rng.uniform(0, 2 * np.pi))
    # 气声：噪声按共振峰染色（简化：带通在 F1~F2 一带）
    noise = rng.standard_normal(n)
    sos = butter(2, [600, 2800], btype="band", fs=SR, output="sos")
    out += breath * sosfilt(sos, noise) * 1.5
    env = interp_track(env_pts, n) * smooth_noise(n, 25, 0.06)   # 振幅抖动
    return out * env


def thud(dur=0.16):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 95 * np.exp(-t * 9) + 45
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 28)
    sos = butter(2, 900, btype="low", fs=SR, output="sos")
    puff = sosfilt(sos, rng.standard_normal(n)) * np.exp(-t * 40) * 2.2
    return (body + puff) * np.minimum(1, t / 0.003)


def kalimba(notes, gap, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i, f in enumerate(notes):
        t0 = i * gap
        tt = t - t0
        m = tt >= 0
        tt = np.where(m, tt, 0)
        tone = (np.sin(2 * np.pi * f * tt) * np.exp(-tt * 5.5)
                + 0.25 * np.sin(2 * np.pi * f * 2.0 * tt) * np.exp(-tt * 9)
                + 0.12 * np.sin(2 * np.pi * f * 5.4 * tt) * np.exp(-tt * 30))   # 拇指琴簧片的高次泛音很快消失
        click = rng.standard_normal(n) * np.exp(-tt * 900) * 0.25
        out += m * (tone + click) * np.minimum(1, tt / 0.002)
    return out


def room(x, wet=0.12, length=0.22):
    """小房间混响：指数衰减的噪声脉冲响应，低通一下更暖"""
    n = int(length * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 22)
    ir = sosfilt(butter(1, 3500, btype="low", fs=SR, output="sos"), ir)
    ir /= np.sqrt((ir ** 2).sum())
    y = np.concatenate([x, np.zeros(n)])
    tail = np.pad(np.convolve(x, ir), (0, 1))[: len(y)]
    return y + wet * tail


def finish(x, peak=0.5):
    x = room(x)
    x = sosfilt(butter(1, 60, btype="high", fs=SR, output="sos"), x)
    fade = int(0.01 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / (np.abs(x).max() + 1e-9) * peak


CUES = {
    # "哇!" 被拎起：u→a，往上挑
    "grab": lambda: voice(0.30, [(0, 430), (0.45, 720), (1, 680)], [(0, "u"), (0.3, "a"), (1, "a")],
                          [(0, 0), (0.06, 1), (0.6, 0.85), (1, 0)]),
    # "咿~" 被扔出去：往下滑
    "thrown": lambda: voice(0.34, [(0, 760), (1, 470)], [(0, "i"), (1, "e")],
                            [(0, 0), (0.08, 1), (0.6, 0.7), (1, 0)]),
    # "咦?" 被点了一下
    "hop": lambda: voice(0.15, [(0, 560), (1, 820)], [(0, "e"), (1, "i")],
                         [(0, 0), (0.15, 1), (0.6, 0.8), (1, 0)]),
    # "噗" 落地
    "land": lambda: thud(),
    # "嗯~" 被摸头：闭嘴哼，带呼噜的颤
    "petted": lambda: voice(0.62, [(0, 360), (0.4, 450), (1, 400)], [(0, "m"), (0.7, "m"), (1, "u")],
                            [(0, 0), (0.12, 1), (0.75, 0.8), (1, 0)], breath=0.03) *
                      (0.8 + 0.2 * np.sin(2 * np.pi * 13 * np.arange(int(0.62 * SR)) / SR)),
    # 拇指琴"叮咚"
    "sign": lambda: kalimba([1046.5, 784.0], 0.20, 0.9),
    # "啊~呜" 伸懒腰打哈欠：气声多
    "wake": lambda: voice(0.85, [(0, 380), (0.35, 560), (1, 300)], [(0, "a"), (0.55, "a"), (1, "u")],
                          [(0, 0), (0.2, 1), (0.6, 0.75), (1, 0)], breath=0.16),
}

PEAK = {"land": 0.6, "sign": 0.45, "petted": 0.42, "wake": 0.42}


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    demo = []
    for name, fn in CUES.items():
        x = finish(fn(), PEAK.get(name, 0.5))
        write(os.path.join(OUT, f"{name}.wav"), x)
        demo += [x, np.zeros(int(0.45 * SR))]
        print(f"{name}.wav  {len(x) / SR:.2f}s")
    write(os.path.join(OUT, "..", "..", "preview", "voice-preview.wav"), np.concatenate(demo))


if __name__ == "__main__":
    main()
