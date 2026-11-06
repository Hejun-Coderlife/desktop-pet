#!/usr/bin/env python3
"""把下载的 CC0 音效裁成试听片段：只去头尾真正的静音、固定增益到峰值 -3dB（不压缩不 loudnorm）、头尾极短渐变。
用法：uv run --with numpy python3 tools/prep_sound_choices.py <素材目录> <输出目录>"""
import subprocess, sys, os
import numpy as np

SR = 44100
src_dir, out_dir = sys.argv[1], sys.argv[2]

def decode(path, ss=None, dur=None):
    cmd = ["ffmpeg", "-loglevel", "error"]
    if ss is not None: cmd += ["-ss", str(ss), "-t", str(dur)]
    cmd += ["-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float32).copy()

def encode(x, path):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libmp3lame", "-b:a", "192k", path], input=x.astype(np.float32).tobytes(), check=True)

def trim(x, rel_db=-40):
    """按 10ms 包络找第一个/最后一个高于(峰值+rel_db)的点，两头各留 15ms"""
    w = int(0.01 * SR)
    n = len(x) // w
    env = np.sqrt((x[: n * w].reshape(n, w) ** 2).mean(1) + 1e-12)
    thr = env.max() * 10 ** (rel_db / 20)
    idx = np.where(env > thr)[0]
    a, b = max(0, idx[0] * w - int(0.015 * SR)), min(len(x), (idx[-1] + 1) * w + int(0.015 * SR))
    return x[a:b]

JOBS = [(f"oga/x/cute_{i:02d}.ogg", f"cute_{i:02d}", None, None) for i in range(1, 11)] + \
       [(f"oga/x/{f}.ogg", f, None, None) for f in ["ooh", "misc_01", "misc_04", "misc_06", "misc_08", "misc_09", "snore", "breath"]] + [
    ("fs/448018.mp3", "meow_short1", None, None), ("fs/686775.mp3", "meow_short2", None, None),
    ("fs/756236.mp3", "meow_3", 0, 1.6), ("fs/728095.mp3", "meow_4", 0, 1.6),
    ("fs/686447.mp3", "squeak_1", None, None), ("fs/504904.mp3", "squeak_2", 0, 1.0),
    ("fs/343984.mp3", "giggle_1", None, None), ("fs/343992.mp3", "giggle_2", None, None), ("fs/737452.mp3", "giggle_3", None, None),
    ("fs/424355.mp3", "purr_1", 3, 1.6), ("fs/640475.mp3", "purr_2", 0.8, 1.6), ("fs/779220.mp3", "purr_3", 2, 1.6), ("fs/364893.mp3", "purr_4", 4, 1.6),
    ("fs/827660.mp3", "yawn_dog", None, None), ("fs/858479.mp3", "jingle_1", 0, 2.2)]

for src, name, ss, dur in JOBS:
    raw = decode(os.path.join(src_dir, src))
    x = decode(os.path.join(src_dir, src), ss, dur) if ss is not None else raw
    if ss is None: x = trim(x)
    peak = np.abs(x).max()
    x = x * (10 ** (-3 / 20) / peak)
    fi, fo = int(0.008 * SR), int(0.04 * SR)
    x[:fi] *= np.linspace(0, 1, fi); x[-fo:] *= np.linspace(1, 0, fo)
    encode(x, os.path.join(out_dir, name + ".mp3"))
    print(f"{name:12s} 原长 {len(raw)/SR:5.2f}s → {len(x)/SR:5.2f}s  原峰值 {20*np.log10(np.abs(raw).max()):6.1f} dB → -3 dB")
