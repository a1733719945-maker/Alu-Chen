#!/usr/bin/env python3
"""中式树种的叶片 / 树干贴图（用 prepare_assets.py 同一批 ambientCG 真实树叶照片拼）：

  bamboo_leaf.png   竹叶：几根细枝，每根挂一串细长的竹叶，往下垂
  willow_strand.png 柳条：竖长条，三根垂下的细枝，两边一片片细长柳叶
  blossom.png       桃花：一簇枝，叶子染成粉白（远看就是一团桃花），夹几片绿叶
  maple_red.png     红枫：秋叶往红色偏
  pine_pad.png      黄山松的松针团：从中间往四周放射，平着放（从上往下看）
  lotus_pad.png     荷叶：圆的，叶脉放射，有个缺口
  ../ground/bamboo_culm_albedo.jpg  竹竿：青绿、竖纹、一节一节的竹节

用法：python3 tools/make_cn_foliage.py（要先有 tools/_downloads，见 fetch_assets.py）
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepare_assets as pa  # noqa: E402

rng = random.Random(20260929)
FT = os.path.join(pa.OUT, "textures", "foliage")
GT = os.path.join(pa.OUT, "textures", "ground")


def narrow(lf, wk, hk):
    """把一片叶子拉细拉长（竹叶、柳叶是披针形的）"""
    w, h = lf.size
    if w > h:
        lf = lf.rotate(90, expand=True)
        w, h = lf.size
    return lf.resize((max(3, int(w * wk)), max(4, int(h * hk))), Image.LANCZOS)


def paste_leaf(card, lf, x, y, ang_deg, scale, bright=1.0, hue=0.0):
    s = scale / max(lf.size)
    lf = lf.resize((max(3, int(lf.size[0] * s)), max(4, int(lf.size[1] * s))), Image.LANCZOS)
    lf = lf.rotate(-ang_deg, expand=True, resample=Image.BICUBIC)
    lf = pa.tint(lf, hue, bright, rng.uniform(0.95, 1.15))
    card.alpha_composite(lf, (int(x - lf.size[0] / 2), int(y - lf.size[1] / 2)))


def bamboo_leaf(green, out, size=512):
    """竹叶：从底部中间长出 6 根细枝往上斜，枝梢微微下垂，每根两边挂细长竹叶"""
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    leaves = [narrow(l, 0.26, 1.6) for l in green]
    base = (size * 0.5, size * 0.97)
    sprays = []
    for k in range(6):
        ang = math.radians(-90 + (k - 2.5) * 12 + rng.uniform(-5, 5))
        L = size * rng.uniform(0.6, 0.8)
        pts = []
        for i in range(14):
            t = i / 13
            a = ang + t * t * 0.35 * (1 if math.cos(ang) >= 0 else -1)
            pts.append((base[0] + math.cos(a) * L * t, base[1] + math.sin(a) * L * t))
        d.line(pts, fill=(96, 110, 52, 255), width=max(2, int(size * 0.006)))
        sprays.append(pts)
    for pts in sprays:
        for i in range(3, 14):
            x, y = pts[i]
            seg = math.degrees(math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0]))
            for side in (-1, 1):
                if rng.random() < 0.8:
                    # 叶子顺着枝条往外斜、稍微下垂
                    la = seg + 90 + side * rng.uniform(35, 70)
                    paste_leaf(card, rng.choice(leaves), x, y, la, size * rng.uniform(0.2, 0.3), rng.uniform(0.72, 1.05), rng.uniform(0.0, 0.03))
    card = card.filter(ImageFilter.SMOOTH)
    card.save(out)
    print("生成", out)


def willow_strand(green, out, w=256, h=1024):
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    leaves = [narrow(l, 0.22, 1.2) for l in green]
    for k in range(4):
        x0 = w * (0.2 + 0.2 * k) + rng.uniform(-10, 10)
        pts = []
        amp = rng.uniform(6, 16)
        for i in range(40):
            t = i / 39
            pts.append((x0 + math.sin(t * 5.0 + k) * amp * t, t * h * rng.uniform(0.9, 0.98) if i == 39 else t * h * 0.95))
        d.line(pts, fill=(100, 92, 50, 255), width=2)
        for i in range(1, 40):
            x, y = pts[i]
            if rng.random() < 0.85:
                side = -1 if i % 2 else 1
                paste_leaf(card, rng.choice(leaves), x + side * 7, y, 180 + side * rng.uniform(15, 35), w * rng.uniform(0.26, 0.36), rng.uniform(0.8, 1.1), rng.uniform(0.01, 0.05))
    card = card.filter(ImageFilter.SMOOTH)
    card.save(out)
    print("生成", out)


def blossom(green, out, size=512):
    """粉白的花瓣团：小叶子染成粉、白两种，按枝条分布"""
    petals = []
    for l in green:
        if max(l.size) < 8:
            continue
        pink = pa.colorize(l, (1.0, rng.uniform(0.62, 0.75), rng.uniform(0.72, 0.82)))
        petals.append(pa.tint(pink, 0.0, 1.35, 0.85))
        white = pa.colorize(l, (1.0, 0.92, 0.94))
        petals.append(pa.tint(white, 0.0, 1.5, 0.6))
    mix = petals * 3 + green[:4]
    pa.leaf_card(mix, out, size=size, n=240, bright=(0.85, 1.1), hue=(-0.005, 0.005), branch=(60, 40, 36), leaf_scale=(0.05, 0.085))


def maple_red(autumn, green, out):
    reds = [pa.tint(l, -0.06, 1.0, 1.35) for l in autumn]
    pa.leaf_card(reds + reds + green[:2], out, bright=(0.7, 1.05), hue=(-0.03, 0.0))


def pine_pad(needles, out, size=512):
    """从上往下看的一团松针：先画几根深色细枝，再从中心往四周密密放射松针，外圈亮一点"""
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    c = size * 0.5
    for k in range(9):
        a = math.radians(k * 40 + rng.uniform(-12, 12))
        d.line([(c, c), (c + math.cos(a) * size * 0.36, c + math.sin(a) * size * 0.36)], fill=(62, 46, 32, 255), width=4)
    ns = [pa.colorize(l, (0.3, 0.55, 0.28)) for l in needles]
    for i in range(1100):
        ang = rng.uniform(0, 360)
        r = size * 0.42 * math.sqrt(rng.random())
        x = c + math.cos(math.radians(ang)) * r
        y = c + math.sin(math.radians(ang)) * r
        k = r / (size * 0.42)
        paste_leaf(card, rng.choice(ns), x, y, ang + 90 + rng.uniform(-30, 30), size * rng.uniform(0.18, 0.28), 0.6 + 0.5 * k * rng.uniform(0.85, 1.1), rng.uniform(-0.02, 0.02))
    card = card.filter(ImageFilter.SMOOTH)
    card.save(out)
    print("生成", out)


def lotus_pad(out, size=512):
    import numpy as np
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = size * 0.5
    dx, dy = x - c, y - c
    r = np.sqrt(dx * dx + dy * dy) / (size * 0.47)
    ang = np.arctan2(dy, dx)
    notch = np.abs(((ang - 0.4 + np.pi) % (2 * np.pi)) - np.pi) < 0.09
    edge = 1.0 + 0.025 * np.sin(ang * 23.0) + 0.015 * np.sin(ang * 7.0 + 1.0)
    inside = (r < edge) & ~(notch & (r > 0.08))
    vein = np.abs(np.sin(ang * 11.0)) ** 40
    base = np.stack([0.2 + 0.08 * r, 0.42 + 0.12 * r, 0.16 + 0.05 * r], -1)
    base *= (0.9 + 0.12 * vein[..., None]) * (1.0 - 0.18 * np.clip(r - 0.85, 0, 1) / 0.15)[..., None]
    noise = np.random.default_rng(5).random((size, size)).astype(np.float32)
    base *= (0.94 + 0.08 * noise)[..., None]
    rim = (r > edge - 0.035) & inside
    base[rim] *= 0.7
    rgb = np.clip(base * 255, 0, 255).astype(np.uint8)
    a = (inside * 255).astype(np.uint8)
    im = Image.fromarray(np.dstack([rgb, a]), "RGBA").filter(ImageFilter.SMOOTH)
    im.save(out)
    print("生成", out)


def bamboo_culm(out, w=256, h=1024):
    import numpy as np
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    rng2 = np.random.default_rng(7)
    streak = rng2.random(w).astype(np.float32)
    streak = np.convolve(streak, np.ones(9) / 9, mode="same")
    col = np.stack([0.34 + 0.0 * x, 0.5 + 0.0 * x, 0.2 + 0.0 * x], -1)
    col *= (0.82 + 0.3 * streak[None, :, None])
    # 两节：节上一圈浅色的环 + 一道深缝，节下一点粉白
    for node in (0.0, 0.5):
        yy = (y / h - node) % 1.0
        dist = np.minimum(yy, 1.0 - yy) * h
        ring = np.exp(-(dist / 5.0) ** 2)
        col *= (1.0 - 0.45 * np.exp(-(dist / 1.5) ** 2))[..., None]
        col += (ring * 0.12)[..., None]
        below = np.clip(1.0 - (yy * h) / 60.0, 0, 1) * (yy < 0.2)
        col += (below * 0.08)[..., None]
    rgb = np.clip(col * 255, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, "RGB").save(out, quality=92)
    print("生成", out)


def main():
    os.makedirs(FT, exist_ok=True)
    green = pa.split_sprites(pa.load_rgba("LeafSet024"))
    autumn = pa.split_sprites(pa.load_rgba("LeafSet030"))
    needles = pa.split_sprites(pa.load_rgba("PineNeedles001"), 200)
    bamboo_leaf(green, os.path.join(FT, "bamboo_leaf.png"))
    willow_strand(green, os.path.join(FT, "willow_strand.png"))
    blossom(green, os.path.join(FT, "blossom.png"))
    maple_red(autumn, green, os.path.join(FT, "maple_red.png"))
    pine_pad(needles, os.path.join(FT, "pine_pad.png"))
    lotus_pad(os.path.join(FT, "lotus_pad.png"))
    bamboo_culm(os.path.join(GT, "bamboo_culm_albedo.jpg"))


if __name__ == "__main__":
    main()
