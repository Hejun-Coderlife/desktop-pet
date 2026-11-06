#!/usr/bin/env python3
"""第二轮：落地 / 睡醒打哈欠 候选。长录音里自动切出一声（按包络分段），固定增益到 -3dB。
用法：uv run --with numpy python3 tools/prep_sound_round2.py <素材目录> <输出目录>"""
import subprocess, sys, os
import numpy as np
SR = 44100
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

def decode(p):
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True, check=True)
    return np.frombuffer(r.stdout, np.float32).copy()

def encode(x, p):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libmp3lame", "-b:a", "192k", p],
                   input=x.astype(np.float32).tobytes(), check=True)

def events(x, rel_db=-32, gap=0.25):
    w = int(0.01 * SR); n = len(x) // w
    env = np.sqrt((x[:n * w].reshape(n, w) ** 2).mean(1) + 1e-12)
    on = env > env.max() * 10 ** (rel_db / 20)
    ev, i = [], 0
    while i < n:
        if on[i]:
            j = i
            while j < n and (on[j] or (j + int(gap / 0.01) < n and on[j:j + int(gap / 0.01)].any())):
                j += 1
            ev.append((i * w, j * w, float((env[i:j] ** 2).sum())))
            i = j
        else:
            i += 1
    return ev

def pick(x, mode, maxlen):
    ev = events(x)
    if not ev: return x[: int(maxlen * SR)]
    a, b, _ = max(ev, key=lambda e: e[2]) if mode == "loudest" else ev[0]
    a = max(0, a - int(0.02 * SR)); b = min(len(x), b + int(0.03 * SR), a + int(maxlen * SR))
    return x[a:b]

# (文件, 输出名, 模式, 最长秒, 标签)
JOBS = {
 "落地": [("789793", "land_pop", "first", 0.6, "啵（短）"), ("754902", "land_plasticpop", "first", 0.8, "啵（塑料）"),
          ("515919", "land_mouthplop", "first", 0.6, "嘴巴 plop"), ("610756", "land_plopp", "first", 0.6, "噗通"),
          ("19285", "land_poppy", "first", 1.0, "卡通弹出"), ("686321", "land_softpunch", "first", 0.6, "软软一砸"),
          ("584442", "land_bagdrop", "first", 0.8, "软包落地"), ("119794", "land_spring", "first", 1.0, "弹簧板 boing"),
          ("497133", "land_paper", "first", 0.8, "纸片落地"), ("842794", "land_bubble", "first", 0.5, "泡泡啵")],
 "睡醒 / 打哈欠": [("854551", "yawn_kitty", "loudest", 3.5, "小猫打哈欠"), ("875658", "yawn_catwake", "loudest", 3.5, "猫咪睡醒"),
          ("383473", "yawn_catpurr", "loudest", 3.5, "猫咪呼噜+哈欠"), ("575562", "yawn_1", "loudest", 3.5, "哈欠 A"),
          ("545721", "yawn_2", "loudest", 3.5, "哈欠 B（带尾音）"), ("422653", "yawn_3", "loudest", 3.5, "游戏角色哈欠"),
          ("511188", "yawn_dane", "loudest", 3.5, "大狗狗哈欠"), ("443497", "yawn_4", "loudest", 3.5, "哈欠 C")],
}
for group, items in JOBS.items():
    for fid, name, mode, ml, label in items:
        x = pick(decode(os.path.join(src, fid + ".mp3")), mode, ml)
        x = x * (10 ** (-3 / 20) / (np.abs(x).max() + 1e-9))
        fi, fo = int(0.008 * SR), int((0.35 if mode == "loudest" else 0.05) * SR)
        x[:fi] *= np.linspace(0, 1, fi); x[-fo:] *= np.linspace(1, 0, fo)
        encode(x, os.path.join(out, name + ".mp3"))
        print(f"{group} {name:16s} {len(x)/SR:4.2f}s  ← Freesound {fid}")

# 试听页
cards, n = [], 0
for group, items in JOBS.items():
    btns = []
    for fid, name, mode, ml, label in items:
        n += 1
        btns.append(f'<button onclick="p(\'{name}\',this)"><b>{n}</b><span>{label}</span></button>')
    cards.append(f'<section><h2>{group}</h2><div class="g">{"".join(btns)}</div></section>')
html = f'''<!doctype html><html lang="zh"><meta charset="utf-8"><title>Pip 声音试听 · 第二轮</title>
<style>body{{margin:0;font-family:-apple-system,"PingFang SC",sans-serif;background:linear-gradient(160deg,#fff7f2,#f3f0ff);color:#3a3340;padding:40px 6vw}}
h1{{font-size:30px;margin:0 0 6px}}.hint{{color:#8a8090;margin:0 0 28px}}
section{{background:#fff;border-radius:22px;padding:20px 24px 24px;margin-bottom:18px;box-shadow:0 6px 24px rgba(120,90,140,.08)}}
h2{{margin:0 0 14px;font-size:20px}}.g{{display:flex;flex-wrap:wrap;gap:10px}}
button{{border:0;background:#f6f1fb;border-radius:14px;padding:12px 16px;font-size:15px;cursor:pointer;display:flex;gap:10px;align-items:center;color:inherit}}
button:hover{{background:#efe4fa}}button.on{{background:#ffd9e4}}
button b{{background:#fff;border-radius:50%;width:28px;height:28px;display:grid;place-items:center;font-size:13px;color:#b0639a}}
.src{{color:#a8a0ad;font-size:12px;margin-top:26px}}</style>
<h1>第二轮：落地 / 睡醒</h1><p class="hint">拎起 4、点一下 9、摸头 18、举牌 29 已经定了。这两组各挑一个，告诉我编号。</p>
{"".join(cards)}<p class="src">全部 Freesound CC0；已切出单独一声、统一音量（峰值 -3dB，不压缩）。</p>
<script>let a;function p(f,b){{if(a)a.pause();a=new Audio(f+".mp3");a.play();document.querySelectorAll("button").forEach(x=>x.classList.remove("on"));b.classList.add("on")}}</script></html>'''
open(os.path.join(out, "index.html"), "w").write(html)
