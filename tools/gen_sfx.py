#!/usr/bin/env python3
"""合成游戏音效，输出到 game/assets/sfx/*.wav（44.1kHz 16 位单声道）。

没有用任何外部音效素材，全部用噪声、正弦波、滤波器叠出来。
改完这个脚本重新运行一次即可：  python3 tools/gen_sfx.py
"""
import os
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sfx")
rng = np.random.default_rng(20260925)


def t_(dur):
    return np.arange(int(SR * dur)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def filt(x, kind, f, order=2):
    if kind == "band":
        sos = butter(order, [f[0] / (SR / 2), f[1] / (SR / 2)], btype="band", output="sos")
    else:
        sos = butter(order, f / (SR / 2), btype=kind, output="sos")
    return sosfilt(sos, x)


def env_exp(dur, tau, attack=0.001):
    t = t_(dur)
    e = np.exp(-t / tau)
    a = int(SR * attack)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def sweep(f0, f1, dur, curve=1.0):
    t = t_(dur)
    k = (t / dur) ** curve
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def tone(f, dur):
    return np.sin(2 * np.pi * f * t_(dur))


def bell(f, dur, tau=0.25, partials=((1, 1.0), (2.76, 0.45), (5.4, 0.25), (8.9, 0.12))):
    out = np.zeros(int(SR * dur))
    for mult, amp in partials:
        out += amp * tone(f * mult, dur) * env_exp(dur, tau / (1 + mult * 0.3), 0.002)
    return out


def place(buf, x, at):
    i = int(SR * at)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]
    return buf


def mix(dur, *parts):
    buf = np.zeros(int(SR * dur))
    for x, at in parts:
        place(buf, x, at)
    return buf


def reverb(x, size=0.35, wet=0.25, lp=3500):
    ir = noise(size) * np.exp(-t_(size) / (size / 4))
    ir = filt(ir, "low", lp)
    ir /= np.max(np.abs(ir)) + 1e-9
    y = fftconvolve(x, ir)[: len(x) + int(SR * size)]
    y = y / (np.max(np.abs(y)) + 1e-9) * np.max(np.abs(x))
    xx = np.concatenate([x, np.zeros(len(y) - len(x))])
    return xx * (1 - wet) + y * wet


def fade_tail(x, ms=15):
    n = min(len(x), int(SR * ms / 1000))
    x[-n:] *= np.linspace(1, 0, n)
    return x


def save(name, x, peak=0.89):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    x = fade_tail(x)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ---------------------------------------------------------------- 暗器

def xiujian_fire():
    click = filt(noise(0.004), "high", 3000) * 1.2
    body = filt(noise(0.09), "band", (700, 3200)) * env_exp(0.09, 0.022) * 0.9
    thump = sweep(150, 55, 0.11, 0.6) * env_exp(0.11, 0.035) * 1.1
    twang = sweep(460, 380, 0.16) * env_exp(0.16, 0.05) * 0.35
    tail = filt(noise(0.25), "low", 1800) * env_exp(0.25, 0.07) * 0.25
    x = mix(0.3, (click, 0), (body, 0.001), (thump, 0), (twang, 0.002), (tail, 0.01))
    return reverb(x, 0.3, 0.18)


def baoyu_fire():
    crack = filt(noise(0.006), "high", 1500) * 1.3
    body = filt(noise(0.22), "low", 2600) * env_exp(0.22, 0.05) * 1.0
    thump = sweep(95, 40, 0.2, 0.5) * env_exp(0.2, 0.06) * 1.4
    parts = [(crack, 0), (body, 0.001), (thump, 0)]
    for i in range(16):
        f = rng.uniform(3200, 6800)
        n = sweep(f, f * 0.8, 0.05) * env_exp(0.05, 0.012) * 0.16
        parts.append((n, rng.uniform(0.0, 0.05)))
    tail = filt(noise(0.45), "low", 1200) * env_exp(0.45, 0.12) * 0.35
    parts.append((tail, 0.02))
    x = mix(0.55, *parts)
    return reverb(x, 0.45, 0.22)


def click(f_lo=1800, f_hi=6000, dur=0.02, tau=0.004):
    return filt(noise(dur), "band", (f_lo, f_hi)) * env_exp(dur, tau)


def reload_start():
    return mix(0.25, (click(), 0), (click(1200, 4000) * 0.8, 0.11), (tone(240, 0.05) * env_exp(0.05, 0.01) * 0.4, 0.11))


def reload_end():
    knock = tone(190, 0.08) * env_exp(0.08, 0.02) * 0.8
    return mix(0.18, (click(2000, 7000), 0), (knock, 0.004), (click(900, 3000) * 0.6, 0.05))


def reload_shell():
    ting = bell(2600, 0.2, 0.06) * 0.3
    return mix(0.22, (click(1500, 5000), 0), (ting, 0.01))


def dry():
    return click(2500, 8000, 0.03, 0.003)


def switch():
    cloth = filt(noise(0.18), "band", (400, 2500)) * np.hanning(int(SR * 0.18)) * 0.5
    return mix(0.25, (cloth, 0), (click(), 0.14))


# ---------------------------------------------------------------- 命中反馈

def hit():
    tick = tone(1500, 0.05) * env_exp(0.05, 0.012) * 0.8
    thwk = filt(noise(0.04), "band", (500, 2500)) * env_exp(0.04, 0.008) * 0.8
    return mix(0.07, (tick, 0), (thwk, 0))


def hit_head():
    ding = bell(1960, 0.35, 0.18, ((1, 1.0), (2.0, 0.4), (3.01, 0.2))) * 0.9
    return mix(0.38, (hit() * 0.6, 0), (ding, 0.0))


def kill():
    pop = filt(noise(0.05), "low", 1500) * env_exp(0.05, 0.012) * 1.0
    notes = [1046.5, 1318.5, 1568.0, 2093.0]
    parts = [(pop, 0)]
    for i, f in enumerate(notes):
        parts.append((bell(f, 0.5, 0.22) * (0.55 if i < 3 else 0.4), 0.02 + i * 0.045))
    return reverb(mix(0.7, *parts), 0.5, 0.25, 6000)


def kill_burst():
    swell = filt(noise(0.5), "band", (800, 5000)) * np.hanning(int(SR * 0.5)) ** 2 * 0.6
    parts = [(swell, 0)]
    for i in range(10):
        f = rng.uniform(1800, 4200)
        parts.append((bell(f, 0.4, 0.12) * 0.18, rng.uniform(0.02, 0.3)))
    return reverb(mix(0.8, *parts), 0.5, 0.3, 7000)


def coin():
    return reverb(mix(0.45, (bell(1976, 0.35, 0.14) * 0.7, 0), (bell(2637, 0.35, 0.18) * 0.7, 0.07)), 0.3, 0.2, 8000)


# ---------------------------------------------------------------- 引魂索

def whoosh(dur=0.32, f0=350, f1=1700):
    n = noise(dur)
    t = t_(dur)
    out = np.zeros_like(n)
    # 分段带通，中心频率扫过去
    seg = 12
    L = len(n) // seg
    for i in range(seg):
        fc = f0 + (f1 - f0) * (i / seg)
        chunk = filt(n[max(0, i * L - 400):(i + 1) * L], "band", (fc * 0.6, fc * 1.5))
        out[i * L:(i + 1) * L] = chunk[-L:]
    e = np.sin(np.pi * t / dur) ** 1.5
    return out * e


def lure_throw():
    return mix(0.4, (whoosh(0.34, 300, 1500), 0), (sweep(900, 1500, 0.2) * env_exp(0.2, 0.08) * 0.08, 0.05))


def splash(size=1.0):
    dur = 0.5 * size + 0.2
    body = filt(noise(dur), "low", 2200) * env_exp(dur, 0.09 * size, 0.004) * 1.0
    hiss = filt(noise(dur), "band", (2500, 7000)) * env_exp(dur, 0.12 * size, 0.01) * 0.35
    parts = [(body, 0), (hiss, 0.01)]
    for i in range(int(6 * size)):
        f = rng.uniform(500, 1400)
        b = sweep(f, f * 1.8, 0.05) * env_exp(0.05, 0.015) * 0.25
        parts.append((b, rng.uniform(0.03, 0.3 * size)))
    return mix(dur + 0.1, *parts)


def thud():
    return mix(0.2, (tone(85, 0.18) * env_exp(0.18, 0.04) * 1.0, 0), (filt(noise(0.08), "low", 900) * env_exp(0.08, 0.02) * 0.7, 0))


def bite():
    # 风铃：叮—叮
    b1 = bell(1760, 0.6, 0.3) * 0.8
    b2 = bell(2349, 0.6, 0.3) * 0.7
    return reverb(mix(0.8, (b1, 0), (b2, 0.13)), 0.4, 0.2, 9000)


def yank():
    rise = whoosh(0.14, 500, 2600) * 0.8
    crack = filt(noise(0.012), "band", (1800, 7000)) * 1.4
    tail = filt(noise(0.2), "low", 1500) * env_exp(0.2, 0.05) * 0.3
    return mix(0.36, (rise, 0), (crack, 0.13), (tail, 0.135))


def snap():
    tw = sweep(320, 120, 0.3, 0.5) * env_exp(0.3, 0.09) * 0.6
    cr = filt(noise(0.01), "high", 2000) * 1.2
    return mix(0.35, (cr, 0), (tw, 0.003))


def struggle():
    dur = 0.3
    n = filt(noise(dur), "band", (180, 700))
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 22 * t_(dur))
    return n * trem * np.hanning(len(n))


# ---------------------------------------------------------------- 魂兽

def emerge_rabbit():
    t = t_(0.14)
    f = 1900 + 500 * np.sin(np.pi * t / 0.14) + 60 * np.sin(2 * np.pi * 40 * t)
    sq = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(len(t))
    return mix(0.3, (sq * 0.7, 0), (sq * 0.4, 0.15))


def emerge_vine():
    hiss = filt(noise(0.5), "band", (2800, 7000)) * np.hanning(int(SR * 0.5)) * 0.6
    rumble = filt(noise(0.5), "low", 180) * env_exp(0.5, 0.2) * 1.0
    return mix(0.55, (hiss, 0.02), (rumble, 0))


def emerge_bird():
    parts = []
    for i in range(3):
        c = sweep(2900, 4300, 0.07) * np.hanning(int(SR * 0.07)) * 0.6
        parts.append((c, i * 0.09))
    return mix(0.35, *parts)


def emerge_moth():
    dur = 0.45
    fl = filt(noise(dur), "band", (300, 1600)) * (0.5 + 0.5 * np.sin(2 * np.pi * 28 * t_(dur))) * np.hanning(int(SR * dur)) * 0.6
    return mix(0.6, (fl, 0), (bell(3136, 0.4, 0.2) * 0.15, 0.05))


def rare():
    parts = []
    for i, f in enumerate([784, 988, 1175, 1568, 1976]):
        parts.append((bell(f, 0.8, 0.3) * 0.45, i * 0.06))
    swell = filt(noise(0.7), "band", (2000, 8000)) * np.hanning(int(SR * 0.7)) * 0.2
    parts.append((swell, 0))
    return reverb(mix(1.1, *parts), 0.7, 0.35, 9000)


# ---------------------------------------------------------------- 人物

def step():
    return filt(noise(0.09), "band", (250, 1800)) * env_exp(0.09, 0.02, 0.004)


def jump():
    return mix(0.2, (whoosh(0.16, 250, 700) * 0.5, 0), (step() * 0.7, 0))


def land():
    return mix(0.25, (tone(70, 0.2) * env_exp(0.2, 0.05) * 0.9, 0), (filt(noise(0.12), "low", 1200) * env_exp(0.12, 0.03) * 0.8, 0))


def ui_click():
    return tone(1200, 0.04) * env_exp(0.04, 0.008) * 0.6 + click(3000, 9000, 0.04, 0.002) * 0.3


# ---------------------------------------------------------------- 环境（循环）

def ambient():
    dur = 10.0
    n = int(SR * dur)
    wind = filt(noise(dur), "low", 380, 2) * 0.9
    t = t_(dur)
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 2) * np.sin(2 * np.pi * t / dur * 3 + 1)
    water = np.zeros(n)
    for i in range(22):
        at = rng.uniform(0, dur - 0.6)
        l = filt(noise(0.5), "band", (300, 1400)) * np.hanning(int(SR * 0.5)) * rng.uniform(0.15, 0.35)
        place(water, l, at)
    birds = np.zeros(n)
    for i in range(3):
        at = rng.uniform(0.5, dur - 1)
        for k in range(rng.integers(2, 4)):
            f = rng.uniform(2600, 3800)
            c = sweep(f, f * 1.25, 0.06) * np.hanning(int(SR * 0.06)) * 0.05
            place(birds, c, at + k * 0.1)
    x = wind + water + birds
    # 首尾交叉淡化，循环时没有接缝
    xf = int(SR * 1.0)
    head = x[:xf].copy()
    x = x[: n - xf]
    x[-xf:] = x[-xf:] * np.linspace(1, 0, xf) + head * np.linspace(0, 1, xf)
    return x


# ---------------------------------------------------------------- 第二版：新暗器、机械声

def saw(f, dur):
    t = t_(dur)
    ph = np.cumsum(np.full(len(t), f) if np.isscalar(f) else f) / SR
    return 2.0 * (ph % 1.0) - 1.0


def zhuge_fire():
    # 连发弩：短、脆，一秒十五发也不糊在一起
    snap_ = filt(noise(0.006), "high", 2500) * 1.3
    body = filt(noise(0.06), "band", (900, 4200)) * env_exp(0.06, 0.012) * 0.9
    thump = sweep(180, 70, 0.07, 0.5) * env_exp(0.07, 0.02) * 0.9
    twang = sweep(620, 520, 0.08) * env_exp(0.08, 0.025) * 0.3
    tail = filt(noise(0.12), "low", 2200) * env_exp(0.12, 0.03) * 0.2
    return mix(0.14, (snap_, 0), (body, 0.001), (thump, 0), (twang, 0.002), (tail, 0.006))


def kongque_fire():
    # 孔雀翎（步枪）：有力的爆裂 + 低频冲击 + 回声
    crack = filt(noise(0.008), "high", 1800) * 1.4
    body = filt(noise(0.12), "band", (500, 3600)) * env_exp(0.12, 0.028) * 1.0
    thump = sweep(120, 45, 0.16, 0.45) * env_exp(0.16, 0.045) * 1.5
    mech = click(2500, 8000, 0.02, 0.004) * 0.35
    tail = filt(noise(0.45), "low", 1500) * env_exp(0.45, 0.11) * 0.35
    x = mix(0.5, (crack, 0), (body, 0.001), (thump, 0), (mech, 0.03), (tail, 0.01))
    return reverb(x, 0.4, 0.22)


def zhuihun_fire():
    # 追魂穿心弩（狙击）：巨响 + 很深的低音 + 山谷回声
    crack = filt(noise(0.01), "high", 1200) * 1.6
    body = filt(noise(0.25), "band", (300, 3000)) * env_exp(0.25, 0.05) * 1.1
    boom_ = sweep(90, 32, 0.4, 0.4) * env_exp(0.4, 0.11) * 1.8
    string = sweep(300, 240, 0.35) * env_exp(0.35, 0.09) * 0.35
    tail = filt(noise(1.2), "low", 900) * env_exp(1.2, 0.35) * 0.5
    x = mix(1.3, (crack, 0), (body, 0.001), (boom_, 0), (string, 0.003), (tail, 0.02))
    x = reverb(x, 0.9, 0.3, 2500)
    # 远处回声
    echo = filt(x, "low", 1200) * 0.25
    return mix(1.9, (x, 0), (echo, 0.42))


def bolt_cycle():
    up = click(1500, 6000, 0.03, 0.006) * 0.9
    slide = filt(noise(0.09), "band", (1200, 5000)) * np.hanning(int(SR * 0.09)) * 0.35
    fwd = click(1000, 5000, 0.03, 0.006) * 1.0
    lock = tone(320, 0.06) * env_exp(0.06, 0.012) * 0.5
    return mix(0.42, (up, 0), (slide, 0.04), (fwd, 0.2), (lock, 0.2), (click(2000, 7000, 0.02, 0.004) * 0.6, 0.29))


def pump():
    back = filt(noise(0.07), "band", (700, 4000)) * env_exp(0.07, 0.02) * 0.9
    clack1 = tone(260, 0.06) * env_exp(0.06, 0.012) * 0.6
    fwd = filt(noise(0.07), "band", (900, 5000)) * env_exp(0.07, 0.018) * 1.0
    clack2 = tone(340, 0.06) * env_exp(0.06, 0.012) * 0.7
    return mix(0.36, (back, 0), (clack1, 0.02), (fwd, 0.17), (clack2, 0.18))


def mag_out():
    return mix(0.25, (click(1800, 7000, 0.02, 0.004), 0), (filt(noise(0.12), "band", (600, 3000)) * np.hanning(int(SR * 0.12)) * 0.4, 0.03))


def mag_in():
    seat = tone(150, 0.08) * env_exp(0.08, 0.02) * 0.9
    return mix(0.2, (filt(noise(0.05), "band", (800, 4000)) * env_exp(0.05, 0.012), 0), (seat, 0.02), (click(2500, 8000, 0.02, 0.003) * 0.7, 0.03))


def exhale():
    dur = 0.8
    n = filt(noise(dur), "band", (300, 1800)) * np.hanning(int(SR * dur)) ** 1.5
    return n


# ---------------------------------------------------------------- 受伤、成长

def hurt():
    thump = tone(70, 0.2) * env_exp(0.2, 0.05) * 1.2
    grunt_f = 190 + 40 * np.exp(-t_(0.22) / 0.05)
    grunt = filt(saw(grunt_f, 0.22), "band", (250, 1200)) * env_exp(0.22, 0.07, 0.01) * 0.5
    return mix(0.3, (thump, 0), (grunt, 0.01), (filt(noise(0.05), "low", 1500) * env_exp(0.05, 0.01), 0))


def death():
    boom_ = sweep(80, 30, 1.2, 0.5) * env_exp(1.2, 0.4) * 1.2
    drone = (tone(110, 2.0) + tone(116.5, 2.0) * 0.8 + tone(165, 2.0) * 0.4) * np.exp(-t_(2.0) / 0.8) * 0.35
    fall = sweep(600, 150, 1.4) * env_exp(1.4, 0.5) * 0.15
    return reverb(mix(2.2, (boom_, 0), (drone, 0.05), (fall, 0.05)), 0.8, 0.35, 2000)


def arpeggio(freqs, gap, dur, tau=0.3, amp=0.45):
    parts = [(bell(f, dur, tau) * amp, i * gap) for i, f in enumerate(freqs)]
    return mix(dur + gap * len(freqs), *parts)


def heal():
    x = arpeggio([784, 988, 1175, 1568], 0.07, 0.8, 0.35, 0.4)
    shimmer = filt(noise(0.9), "band", (4000, 9000)) * np.hanning(int(SR * 0.9)) * 0.08
    return reverb(mix(1.2, (x, 0), (shimmer, 0)), 0.6, 0.35, 9000)


def level_up():
    x = arpeggio([523, 659, 784, 1047, 1319, 1568], 0.075, 1.2, 0.45, 0.45)
    chord = (tone(523, 1.4) + tone(659, 1.4) * 0.8 + tone(784, 1.4) * 0.7) * np.exp(-t_(1.4) / 0.6) * np.minimum(t_(1.4) / 0.05, 1) * 0.25
    swell = filt(noise(1.2), "band", (3000, 9000)) * np.hanning(int(SR * 1.2)) * 0.12
    return reverb(mix(1.9, (x, 0), (chord, 0.45), (swell, 0.2)), 0.8, 0.35, 9000)


def choir(freqs, dur):
    out = np.zeros(int(SR * dur))
    t = t_(dur)
    for f in freqs:
        for det in (-0.6, 0.0, 0.7):
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t + det * 3)
            out += np.sin(2 * np.pi * np.cumsum(np.full(len(t), f + det) * vib) / SR) * 0.3
    return filt(out, "low", 3000)


def absorb():
    dur = 3.2
    t = t_(dur)
    swell = whoosh(dur, 200, 2400) * 0.5
    ch = choir([220, 277, 330, 440], dur) * (t / dur) ** 1.5 * 0.9
    sub = tone(55, dur) * (t / dur) * 0.4
    fin = bell(1760, 1.0, 0.4) * 0.5
    return reverb(mix(dur + 1.0, (swell, 0), (ch, 0), (sub, 0), (fin, dur - 0.05)), 0.9, 0.35, 6000)


def ring_drop():
    hum = choir([196, 294], 1.4) * np.hanning(int(SR * 1.4)) * 0.6
    return reverb(mix(1.6, (bell(1568, 1.0, 0.4) * 0.6, 0), (bell(2093, 1.0, 0.4) * 0.45, 0.1), (hum, 0)), 0.7, 0.35, 8000)


def quest_done():
    x = arpeggio([659, 784, 1047], 0.11, 0.9, 0.4, 0.5)
    return reverb(x, 0.6, 0.3, 8000)


# ---------------------------------------------------------------- Boss、魂兽攻击

def growl(dur, f0, f1, rough=0.6):
    t = t_(dur)
    f = f0 + (f1 - f0) * (t / dur) + 8 * np.sin(2 * np.pi * 7 * t)
    body = filt(saw(f, dur), "low", 900) * 0.8
    grit = filt(noise(dur), "band", (150, 900)) * (0.5 + 0.5 * np.sin(2 * np.pi * 31 * t)) * rough
    return (body + grit) * np.sin(np.pi * np.minimum(t / dur, 1)) ** 0.6


def boss_roar():
    g = growl(2.2, 70, 50, 0.8) * 1.2
    hiss = filt(noise(2.2), "band", (1500, 5000)) * np.hanning(int(SR * 2.2)) * 0.25
    sub = tone(38, 2.2) * np.hanning(int(SR * 2.2)) * 0.6
    return reverb(mix(2.8, (g, 0), (hiss, 0.1), (sub, 0)), 1.0, 0.35, 2500)


def spit():
    wet = filt(noise(0.25), "band", (600, 3500)) * env_exp(0.25, 0.05) * 0.9
    glob = sweep(400, 150, 0.12) * env_exp(0.12, 0.03) * 0.5
    return mix(0.3, (wet, 0), (glob, 0))


def throw():
    return mix(0.45, (growl(0.25, 120, 90, 0.5) * 0.6, 0), (whoosh(0.35, 200, 900) * 0.8, 0.08))


def slam():
    impact = filt(noise(0.5), "low", 700) * env_exp(0.5, 0.12) * 1.2
    sub = sweep(60, 28, 0.6, 0.5) * env_exp(0.6, 0.2) * 1.6
    debris = np.zeros(int(SR * 0.9))
    for i in range(14):
        place(debris, click(600, 3000, 0.03, 0.008) * rng.uniform(0.2, 0.5), rng.uniform(0.05, 0.7))
    return reverb(mix(1.0, (impact, 0), (sub, 0), (debris, 0)), 0.7, 0.3, 2500)


def boom():
    blast = filt(noise(0.9), "low", 2500) * env_exp(0.9, 0.18, 0.002) * 1.3
    crack = filt(noise(0.02), "high", 1000) * 1.3
    sub = sweep(70, 25, 1.0, 0.5) * env_exp(1.0, 0.3) * 1.8
    rumble = filt(noise(1.8), "low", 300) * env_exp(1.8, 0.6) * 0.6
    return reverb(mix(2.0, (crack, 0), (blast, 0), (sub, 0), (rumble, 0.05)), 0.9, 0.3, 2000)


def bite_attack():
    snarl = growl(0.35, 150, 110, 0.9) * 0.9
    snap_ = click(1500, 6000, 0.03, 0.005) * 1.2
    return mix(0.45, (snarl, 0), (snap_, 0.3))


def emerge_wolf():
    return mix(0.9, (growl(0.7, 130, 95, 0.9), 0), (sweep(700, 900, 0.3) * np.hanning(int(SR * 0.3)) * 0.2, 0.55))


def emerge_rhino():
    snort = filt(noise(0.3), "band", (200, 1500)) * env_exp(0.3, 0.08) * 0.9
    stomp = tone(60, 0.25) * env_exp(0.25, 0.06) * 1.3
    return mix(0.8, (snort, 0), (stomp, 0.3), (stomp * 0.8, 0.5))


def emerge_ape():
    parts = [(growl(0.5, 110, 140, 0.6) * 0.7, 0)]
    for i in range(4):
        parts.append((tone(90, 0.12) * env_exp(0.12, 0.03) * 1.2, 0.35 + i * 0.1))
    return mix(0.9, *parts)


def emerge_snake():
    hiss = filt(noise(0.7), "band", (3000, 9000)) * np.hanning(int(SR * 0.7)) * 0.8
    return mix(0.8, (hiss, 0), (emerge_vine() * 0.4, 0))


# ---------------------------------------------------------------- 魂技

def skill_cast():
    up = whoosh(0.35, 300, 3000) * 0.6
    return reverb(mix(0.7, (up, 0), (bell(1319, 0.5, 0.2) * 0.4, 0.25), (bell(1976, 0.5, 0.2) * 0.3, 0.3)), 0.5, 0.3, 8000)


def skill_launch():
    return mix(0.8, (slam() * 0.5, 0), (whoosh(0.4, 300, 2500) * 0.8, 0.05))


def skill_root():
    creak = np.zeros(int(SR * 0.9))
    for i in range(30):
        place(creak, click(300, 2000, 0.02, 0.006) * rng.uniform(0.2, 0.6), rng.uniform(0, 0.8))
    return mix(1.0, (creak, 0), (filt(noise(0.8), "low", 400) * np.hanning(int(SR * 0.8)) * 0.6, 0))


def skill_mark():
    return reverb(mix(0.8, (bell(880, 0.7, 0.3) * 0.6, 0), (tone(110, 0.6) * env_exp(0.6, 0.2) * 0.6, 0)), 0.5, 0.3)


def skill_pull():
    t = t_(1.0)
    swirl = filt(noise(1.0), "band", (200, 1600)) * (0.5 + 0.5 * np.sin(2 * np.pi * (3 + 9 * t) * t)) * (1 - t) * 0.8
    return mix(1.1, (swirl, 0), (sweep(800, 120, 1.0) * env_exp(1.0, 0.4) * 0.3, 0))


def skill_beam():
    t = t_(1.0)
    hum = (saw(220 + 30 * t, 1.0) * 0.3 + tone(440, 1.0) * 0.3) * np.hanning(len(t))
    return reverb(mix(1.2, (filt(hum, "low", 3000), 0), (filt(noise(1.0), "band", (2000, 6000)) * np.hanning(len(t)) * 0.3, 0)), 0.5, 0.3)


def skill_rain():
    buf = np.zeros(int(SR * 1.4))
    for i in range(24):
        place(buf, filt(noise(0.1), "low", 1500) * env_exp(0.1, 0.03) * rng.uniform(0.3, 0.8), rng.uniform(0.1, 1.2))
    return mix(1.5, (whoosh(0.5, 2000, 400) * 0.5, 0), (buf, 0))


def skill_dash():
    return whoosh(0.3, 400, 3000)


def skill_leap():
    return mix(0.9, (whoosh(0.35, 300, 1500) * 0.7, 0), (slam() * 0.5, 0.35))


def skill_projectile():
    return mix(0.7, (whoosh(0.5, 200, 1200) * 0.8, 0), (filt(noise(0.5), "band", (300, 1500)) * np.hanning(int(SR * 0.5)) * 0.4, 0))


def skill_buff():
    return reverb(mix(1.0, (arpeggio([659, 880, 1319], 0.06, 0.6, 0.25, 0.4), 0), (filt(noise(0.6), "band", (3000, 8000)) * np.hanning(int(SR * 0.6)) * 0.12, 0)), 0.5, 0.3, 8000)


def skill_shield():
    hum = choir([330, 495], 0.8) * np.hanning(int(SR * 0.8)) * 0.5
    return reverb(mix(1.0, (bell(2637, 0.6, 0.25) * 0.5, 0), (hum, 0)), 0.5, 0.3, 8000)


SOUNDS = {
    "xiujian_fire": xiujian_fire, "baoyu_fire": baoyu_fire,
    "reload_start": reload_start, "reload_end": reload_end, "reload_shell": reload_shell,
    "dry": dry, "switch": switch,
    "hit": hit, "hit_head": hit_head, "kill": kill, "kill_burst": kill_burst, "coin": coin,
    "lure_throw": lure_throw, "splash_small": lambda: splash(0.6), "splash_big": lambda: splash(1.4),
    "thud": thud, "bite": bite, "yank": yank, "snap": snap, "struggle": struggle,
    "emerge_rabbit": emerge_rabbit, "emerge_vine": emerge_vine, "emerge_bird": emerge_bird,
    "emerge_moth": emerge_moth, "rare": rare,
    "step": step, "jump": jump, "land": land, "ui_click": ui_click,
    "zhuge_fire": zhuge_fire, "kongque_fire": kongque_fire, "zhuihun_fire": zhuihun_fire,
    "bolt_cycle": bolt_cycle, "pump": pump, "mag_out": mag_out, "mag_in": mag_in, "exhale": exhale,
    "hurt": hurt, "death": death, "heal": heal, "level_up": level_up, "absorb": absorb,
    "ring_drop": ring_drop, "quest_done": quest_done,
    "boss_roar": boss_roar, "spit": spit, "throw": throw, "slam": slam, "boom": boom,
    "bite_attack": bite_attack, "emerge_wolf": emerge_wolf, "emerge_rhino": emerge_rhino,
    "emerge_ape": emerge_ape, "emerge_snake": emerge_snake,
    "skill_cast": skill_cast, "skill_launch": skill_launch, "skill_root": skill_root,
    "skill_mark": skill_mark, "skill_pull": skill_pull, "skill_beam": skill_beam,
    "skill_rain": skill_rain, "skill_dash": skill_dash, "skill_leap": skill_leap,
    "skill_projectile": skill_projectile, "skill_buff": skill_buff, "skill_shield": skill_shield,
    "skill_heal": heal,
}

if __name__ == "__main__":
    for name, fn in SOUNDS.items():
        save(name, fn())
    # 环境声没有 fade_tail，单独存，音量低一点
    amb = ambient()
    amb = amb / (np.max(np.abs(amb)) + 1e-9) * 0.6
    data = (np.clip(amb, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, "ambient.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("生成了 %d 个音效到 %s" % (len(SOUNDS) + 1, os.path.abspath(OUT)))
