"""黄山松枝头的松针团（从上往下看），2026-09-29 重画：
以前是 make_cn_foliage.pine_pad 一整张实心的毛绒圆片，近看一团团像绿盘子。
现在是几十簇分开的松针（每簇几十根细针从一点往外放射），簇和簇之间有空隙、边缘参差，里面暗外面亮。
先画 2 倍大再缩小。雪地版用 prepare_assets.snowy 盖一层雪。

python tools/make_pine_pad.py  →  game/assets/textures/foliage/pine_pad.png、pine_pad_snow.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

import prepare_assets as pa

SIZE = 512
K = 2
FT = os.path.join(pa.OUT, "textures", "foliage")
rng = random.Random(4242)


def tuft(d, x, y, R, base, tip, n):
    """一簇松针：n 根细针从 (x, y) 往外放射，长短不一，尖端亮"""
    for i in range(n):
        a = rng.uniform(0, math.tau)
        L = R * rng.uniform(0.55, 1.0)
        ex, ey = x + math.cos(a) * L, y + math.sin(a) * L
        mx, my = x + math.cos(a) * L * 0.5, y + math.sin(a) * L * 0.5
        j = rng.uniform(0.85, 1.12)
        c0 = tuple(int(v * j) for v in base) + (255,)
        c1 = tuple(int(v * j) for v in tip) + (255,)
        w = max(1, int(K * rng.uniform(1.0, 1.8)))
        d.line([(x, y), (mx, my)], fill=c0, width=w)
        d.line([(mx, my), (ex, ey)], fill=c1, width=max(1, w - 1))


def main():
    S = SIZE * K
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S * 0.5
    # 几根深色细枝
    for k in range(7):
        a = math.radians(k * 51 + rng.uniform(-15, 15))
        d.line([(c, c), (c + math.cos(a) * S * 0.33, c + math.sin(a) * S * 0.33)], fill=(56, 42, 30, 255), width=4 * K)
    # 松针簇：里面的先画、暗；外圈后画、亮
    tufts = []
    for i in range(95):
        r = S * 0.4 * math.sqrt(rng.random())
        a = rng.uniform(0, math.tau)
        tufts.append((r, c + math.cos(a) * r, c + math.sin(a) * r))
    tufts.sort()
    for r, x, y in tufts:
        k = r / (S * 0.4)
        sh = 0.62 + 0.45 * k
        base = (int(34 * sh), int(56 * sh), int(28 * sh))
        tip = (int(78 * sh), int(108 * sh), int(52 * sh))
        tuft(d, x, y, S * rng.uniform(0.06, 0.09), base, tip, rng.randint(28, 44))
    im = im.filter(ImageFilter.SMOOTH).resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join(FT, "pine_pad.png")
    im.save(out)
    print("生成", out)
    pa.snowy(out, os.path.join(FT, "pine_pad_snow.png"))


if __name__ == "__main__":
    main()
