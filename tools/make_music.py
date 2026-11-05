"""原创背景音乐：八音盒 + 柔和低音 + 轻打击，112 拍/分（和 Pip 跳舞同速），41 秒。
用法：python make_music.py 输出.wav [秒数]"""
import sys, wave, numpy as np
SR = 44100
BPM = 112
BEAT = 60 / BPM
DUR = float(sys.argv[2]) if len(sys.argv) > 2 else 41.0
N = int(SR * DUR)
L = np.zeros(N); R = np.zeros(N)
rng = np.random.default_rng(5)

def midi(m): return 440 * 2 ** ((m - 69) / 12)

def add(buf, start, sig, pan=0.0, gain=1.0):
    i = int(start * SR)
    if i >= N: return
    sig = sig[: N - i] * gain
    L[i:i + len(sig)] += sig * (1 - pan) * 0.5 * 2 ** 0.5 if buf is None else 0
    R[i:i + len(sig)] += sig * (1 + pan) * 0.5 * 2 ** 0.5 if buf is None else 0

def musicbox(m, length=1.6):
    t = np.arange(int(SR * length)) / SR
    f = midi(m)
    s = (np.sin(2*np.pi*f*t) + 0.35*np.sin(2*np.pi*2*f*t) + 0.12*np.sin(2*np.pi*3.01*f*t) + 0.05*np.sin(2*np.pi*5.4*f*t))
    env = np.exp(-t * 4.2) * np.minimum(1, t / 0.004)
    return s * env

def bass(m, length):
    t = np.arange(int(SR * length)) / SR
    f = midi(m)
    s = np.sin(2*np.pi*f*t) + 0.25*np.sin(2*np.pi*2*f*t)
    env = np.minimum(1, t / 0.02) * np.exp(-t * 1.6)
    return s * env

def pad(ms, length):
    t = np.arange(int(SR * length)) / SR
    s = sum(np.sin(2*np.pi*midi(m)*t) + np.sin(2*np.pi*midi(m)*1.003*t) for m in ms) / (2 * len(ms))
    env = np.minimum(1, t / 0.5) * np.minimum(1, (length - t) / 0.5)
    return s * env

def kick():
    t = np.arange(int(SR * 0.25)) / SR
    f = 120 * np.exp(-t * 18) + 45
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-t * 14)

def shaker():
    t = np.arange(int(SR * 0.06)) / SR
    n = rng.standard_normal(len(t))
    n = np.diff(np.concatenate([[0], n]))       # 粗略高通
    return n * np.exp(-t * 70)

# C – Am – F – G（每和弦一小节）
chords = [(48, [60, 64, 67]), (45, [57, 60, 64]), (41, [53, 57, 60]), (43, [55, 59, 62])]
scale = [60, 62, 64, 67, 69, 72, 74, 76, 79]       # C 大调五声
bar = 4 * BEAT
bars = int(DUR / bar) + 1

# 一段 2 小节的旋律动机，后面重复并轻微变化
motif = [(0, 7), (0.5, 6), (1, 5), (1.5, 4), (2, 5), (3, 2),
         (4, 4), (4.5, 5), (5, 7), (6, 6), (6.5, 5), (7, 4)]

for b in range(bars):
    t0 = b * bar
    root, tri = chords[b % 4]
    add(None, t0, pad(tri, bar), 0, 0.10)
    add(None, t0, bass(root, bar * 0.9), 0, 0.28)
    add(None, t0 + 2 * BEAT, bass(root + 7, bar * 0.45), 0, 0.18)
    if b >= 1:                                       # 第 2 小节起进鼓
        for k in range(4):
            if k in (0, 2): add(None, t0 + k * BEAT, kick(), 0, 0.30)
            add(None, t0 + (k + 0.5) * BEAT, shaker(), 0.3, 0.05)
    # 旋律：每两小节一轮；第 3、4 轮升高一点更轻快
    if b % 2 == 0:
        lift = 2 if (b // 2) % 4 in (2, 3) else 0
        for beat, idx in motif:
            i = min(len(scale) - 1, idx + lift - (1 if rng.random() < 0.15 else 0))
            pan = rng.uniform(-0.4, 0.4)
            add(None, t0 + beat * BEAT, musicbox(scale[i] + 12), pan, 0.16)
    # 和弦琶音点缀
    for k, m in enumerate(tri):
        add(None, t0 + 3.25 * BEAT + k * 0.12, musicbox(m + 12, 1.0), (k - 1) * 0.5, 0.06)

# 简易混响：几条短延迟
for d, g in [(0.083, 0.22), (0.131, 0.16), (0.197, 0.11)]:
    k = int(d * SR)
    L[k:] += R[:-k] * g; R[k:] += L[:-k] * g

t = np.arange(N) / SR
fade = np.minimum(1, t / 0.6) * np.minimum(1, (DUR - t) / 2.5)
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 0.85, R / peak * 0.85
out = (np.stack([L, R], 1) * 32767).astype(np.int16)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(out.tobytes())
print("ok", sys.argv[1], DUR, "s")
