"""草丛贴图（2026-09-29 重做）：以前的草叶是从 ambientCG 的阔叶照片里抠的，一片片又宽又平，近看像纸片，
"枯草"那张其实也是绿的。这里直接画细草：90 根左右细长、会弯的草叶，一半亮一半暗（叶脉两边受光不同），
根部暗、尖端亮，少量黄尖 / 枯叶 / 草穗。先画 2 倍大再缩小（边缘抗锯齿）。

python tools/make_grass.py  →  game/assets/textures/foliage/grass_tuft.png、grass_tuft_dry.png
"""
import math
import os
import random

from PIL import Image, ImageDraw

SIZE = 512
K = 2  # 先画 2 倍
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "textures", "foliage")


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c) + (255,)


def blade(d, x0, y0, h, w, lean, base, tip, side, rng):
    """一根草叶：中线是往 lean 那边弯的曲线，宽度往尖端收；叶脉两边一亮一暗"""
    n = 22
    droop = rng.uniform(0.0, 0.35) * abs(lean)
    pts = []
    for i in range(n + 1):
        t = i / n
        x = x0 + lean * h * t * t
        y = y0 - h * (t - droop * t * t)
        pts.append((x, y, t))
    for i in range(n):
        xa, ya, ta = pts[i]
        xb, yb, tb = pts[i + 1]
        wa = w * (1.0 - ta) ** 0.75
        wb = w * (1.0 - tb) ** 0.75
        dx, dy = xb - xa, yb - ya
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L, dx / L
        c = lerp(base, tip, ta ** 0.8)
        d.polygon([(xa, ya), (xb, yb), (xb + nx * wb, yb + ny * wb), (xa + nx * wa, ya + ny * wa)], fill=shade(c, 1.0 + side))
        d.polygon([(xa, ya), (xb, yb), (xb - nx * wb, yb - ny * wb), (xa - nx * wa, ya - ny * wa)], fill=shade(c, 1.0 - side))
    return pts[-1]


def seed_head(d, x, y, lean, col, rng):
    """草穗：顶上一串小椭圆"""
    for j in range(rng.randint(6, 10)):
        t = j / 9.0
        px = x + lean * 30 * t + rng.uniform(-3, 3) * K
        py = y - j * 7 * K
        r = (3.2 - t * 1.4) * K
        px += (1 if j % 2 else -1) * r * 0.5
        d.ellipse([px - r * 0.45, py - r, px + r * 0.45, py + r], fill=shade(col, rng.uniform(0.7, 1.0)))


def card(out, palette, n=92, seed=7, heads=0.0):
    rng = random.Random(seed)
    S = SIZE * K
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    blades = []
    for i in range(n):
        x0 = S * 0.5 + rng.gauss(0, S * 0.13)
        x0 = max(S * 0.1, min(S * 0.9, x0))
        # 矮的多、高的少
        h = S * (0.3 + 0.67 * rng.random() ** 1.4)
        lean = rng.gauss(0, 0.16) + (x0 - S * 0.5) / S * 0.7
        # 叶尖别出贴图边
        lean = max((S * 0.04 - x0) / h, min((S * 0.96 - x0) / h, lean))
        w = K * rng.uniform(2.2, 4.6) * (0.7 + 0.5 * h / S)
        blades.append((rng.random(), x0, h, lean, w))
    # 后面的先画（暗一点），前面的后画
    blades.sort()
    for depth, x0, h, lean, w in blades:
        kind = rng.random()
        base, tip = palette["main"]
        for p, pal in palette["extra"]:
            if kind < p:
                base, tip = pal
                break
            kind -= p
        j = rng.uniform(0.85, 1.12) * (0.78 + 0.3 * depth)
        base = tuple(v * j for v in base)
        tip = tuple(v * j * rng.uniform(0.95, 1.08) for v in tip)
        # 根部高低错开一点，贴片底边不是一条直线
        top = blade(d, x0, S * rng.uniform(0.965, 1.0), h, w, lean, base, tip, rng.uniform(0.1, 0.22), rng)
        if rng.random() < heads:
            # 草穗：叶尖再往上一根细茎
            sx, sy, _ = top
            hx, hy = sx + lean * 40 * K, sy - rng.uniform(30, 60) * K
            d.line([(sx, sy), (hx, hy)], fill=shade(palette["head"], 0.8), width=int(1.6 * K))
            seed_head(d, hx, hy, lean, palette["head"], rng)
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    im.save(out)
    print("生成", out)


FRESH = {
    # 根暗尖亮；平均色和以前那张差不多（R 75 G 100 B 35 上下），地面和草丛的颜色才接得上
    "main": ((30, 48, 16), (98, 128, 44)),
    "extra": [
        (0.16, ((34, 50, 18), (132, 132, 64))),   # 黄尖
        (0.12, ((36, 56, 26), (84, 118, 58))),    # 偏青
        (0.05, ((70, 62, 36), (150, 134, 84))),   # 枯叶
    ],
    "head": (150, 136, 92),
}

DRY = {
    # 枯草：秋天的林子、雪地、海边沙丘
    "main": ((66, 54, 30), (176, 152, 98)),
    "extra": [
        (0.25, ((58, 50, 34), (140, 128, 104))),  # 灰白
        (0.15, ((44, 50, 22), (118, 118, 60))),   # 还带点绿
        (0.1, ((80, 58, 28), (168, 120, 66))),    # 红褐
    ],
    "head": (170, 150, 104),
}


if __name__ == "__main__":
    card(os.path.join(OUT, "grass_tuft.png"), FRESH, seed=7, heads=0.04)
    card(os.path.join(OUT, "grass_tuft_dry.png"), DRY, seed=11, heads=0.08)
