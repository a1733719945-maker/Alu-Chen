"""地上的小零碎（2026-09-29，学 Road to Vostok：它满地都是落叶、枯枝、碎石，我们的地面干净得像刚扫过）。
一张 1024 图集，4×4 格，每格一小堆（平铺在地上的贴片用 WorldBuilder._litter 撒）：
  0~3  秋天的落叶（橡树叶照片 LeafSet030；2 是往黄偏的银杏色）       4~5  烂了一半的绿叶（LeafSet024 压暗偏褐）
  6~7  红叶（橡树叶往红偏，落霞林的红枫底下）   8~9  枯松针（PineNeedles001）
  10~11 枯枝（画的：分叉、树皮明暗）             12~13 碎石子（画的）
  14  两三片新落的绿叶                            15  柏树小枝（LeafSet019）
叶子来自 ambientCG（CC0）：python tools/fetch_assets.py 之后，或者按 tools/_downloads/textures/<id>/<id>_2K-PNG_Color.png 放好。

python tools/make_litter.py  →  game/assets/textures/foliage/litter.png
"""
import colorsys
import math
import os
import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

import prepare_assets as pa

CELL = 256
OUT = os.path.join(pa.OUT, "textures", "foliage", "litter.png")
rng = random.Random(20260929)


def load(aid):
    d = os.path.join(pa.TEX, aid)
    col = Image.open(os.path.join(d, f"{aid}_2K-PNG_Color.png")).convert("RGBA")
    op = Image.open(os.path.join(d, f"{aid}_2K-PNG_Opacity.png")).convert("L").resize(col.size)
    col.putalpha(op)
    return col


def recolor(im, hue=0.0, sat=1.0, bright=1.0):
    """整片叶子换色：色相转一点、饱和度、明暗"""
    r, g, b, a = im.split()
    rgb = Image.merge("RGB", (r, g, b))
    if hue:
        px = rgb.load()
        w, h = rgb.size
        for y in range(h):
            for x in range(w):
                pr, pg, pb = px[x, y]
                hh, ss, vv = colorsys.rgb_to_hsv(pr / 255, pg / 255, pb / 255)
                cr, cg, cb = colorsys.hsv_to_rgb((hh + hue) % 1.0, ss, vv)
                px[x, y] = (int(cr * 255), int(cg * 255), int(cb * 255))
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def pile(sprites, n, size_k, dark=(0.75, 1.0), fx=None):
    """一格里撒 n 片：先放的暗（压在下面），后放的亮"""
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for i in range(n):
        s = rng.choice(sprites)
        k = CELL * size_k * rng.uniform(0.75, 1.15) / max(s.size)
        s = s.resize((max(4, int(s.size[0] * k)), max(4, int(s.size[1] * k))), Image.LANCZOS)
        if fx:
            s = fx(s)
        s = s.rotate(rng.uniform(0, 360), expand=True, resample=Image.BICUBIC)
        t = i / max(1, n - 1)
        s = recolor(s, bright=dark[0] + (dark[1] - dark[0]) * t)
        # 离格子边 10 像素（缩小贴图时别渗到隔壁格）
        mx = CELL - 20 - s.size[0]
        my = CELL - 20 - s.size[1]
        if mx < 0 or my < 0:
            continue
        cx = int(10 + mx * (0.5 + rng.gauss(0, 0.22)))
        cy = int(10 + my * (0.5 + rng.gauss(0, 0.22)))
        cell.alpha_composite(s, (max(10, min(10 + mx, cx)), max(10, min(10 + my, cy))))
    return cell


def twigs():
    """枯枝：一根主枝 + 几根分叉，一边亮一边暗"""
    S = CELL * 2
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k in range(rng.randint(3, 4)):
        x, y = rng.uniform(S * 0.2, S * 0.8), rng.uniform(S * 0.2, S * 0.8)
        a = rng.uniform(0, math.tau)
        L = rng.uniform(S * 0.35, S * 0.6)
        _branch(d, x - math.cos(a) * L / 2, y - math.sin(a) * L / 2, a, L, rng.uniform(9, 15), 0)
    im = im.resize((CELL, CELL), Image.LANCZOS)
    return _clip(im)


def _branch(d, x, y, a, L, w, depth):
    n = 10
    pts = []
    for i in range(n + 1):
        t = i / n
        a2 = a + math.sin(t * 3.0 + depth) * 0.15
        pts.append((x + math.cos(a2) * L * t, y + math.sin(a2) * L * t))
    base = (rng.randint(70, 95), rng.randint(56, 72), rng.randint(40, 52))
    for i in range(n):
        ww = max(1.5, w * (1 - i / n * 0.6))
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        nx, ny = -(yb - ya), xb - xa
        ln = math.hypot(nx, ny) or 1
        nx, ny = nx / ln * ww * 0.35, ny / ln * ww * 0.35
        d.line([(xa, ya), (xb, yb)], fill=base + (255,), width=int(ww))
        d.line([(xa + nx, ya + ny), (xb + nx, yb + ny)], fill=tuple(int(c * 1.35) for c in base) + (255,), width=max(1, int(ww * 0.3)))
        d.line([(xa - nx, ya - ny), (xb - nx, yb - ny)], fill=tuple(int(c * 0.6) for c in base) + (255,), width=max(1, int(ww * 0.3)))
    if depth < 2:
        for j in range(rng.randint(1, 3)):
            t = rng.uniform(0.3, 0.85)
            bx, by = pts[int(t * n)]
            _branch(d, bx, by, a + rng.choice([-1, 1]) * rng.uniform(0.4, 0.9), L * rng.uniform(0.25, 0.45), w * 0.55, depth + 1)


def pebbles():
    """碎石子：十几颗扁的、不规则的灰褐色石片（以前是圆的、一圈圈上光，像彩色玻璃弹珠）"""
    S = CELL * 2
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(rng.randint(12, 22)):
        r = rng.uniform(8, 28)
        x, y = rng.gauss(S / 2, S * 0.2), rng.gauss(S / 2, S * 0.2)
        x, y = max(r + 24, min(S - r - 24, x)), max(r + 24, min(S - r - 24, y))
        g = rng.randint(70, 112)
        base = (g, int(g * rng.uniform(0.94, 0.99)), int(g * rng.uniform(0.86, 0.95)))
        e = rng.uniform(0.45, 0.85)
        rot = rng.uniform(0, math.tau)
        rad = [rng.uniform(0.72, 1.0) for _ in range(9)]

        def poly(k, dx=0.0, dy=0.0):
            pts = []
            for j in range(9):
                a = rot + j / 9 * math.tau
                pts.append((x + dx + math.cos(a) * r * rad[j] * k, y + dy + math.sin(a) * r * rad[j] * k * e))
            return pts
        d.polygon(poly(1.05, 2, 4), fill=(28, 24, 20, 130))
        d.polygon(poly(1.0), fill=base + (255,))
        d.polygon(poly(0.6, -r * 0.12, -r * 0.15 * e), fill=tuple(int(v * 1.15) for v in base) + (255,))
    im = im.filter(ImageFilter.GaussianBlur(1.6)).resize((CELL, CELL), Image.LANCZOS)
    return _clip(im)


def _clip(im):
    """格子边上 10 像素清空"""
    a = im.split()[3]
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rectangle([10, 10, CELL - 11, CELL - 11], fill=255)
    from PIL import ImageChops
    im.putalpha(ImageChops.multiply(a, mask))
    return im


def main():
    oak = pa.split_sprites(load("LeafSet030"), 800)
    beech = pa.split_sprites(load("LeafSet024"), 800)
    needles = pa.split_sprites(load("PineNeedles001"), 300)
    cedar = pa.split_sprites(load("LeafSet019"), 800)
    print("橡树叶", len(oak), "山毛榉", len(beech), "松针", len(needles), "柏枝", len(cedar))
    rotten = lambda s: recolor(s, hue=-0.07, sat=0.55, bright=0.7)
    red = lambda s: recolor(s, hue=-0.03, sat=1.25, bright=0.95)
    cells = [
        pile(oak, 16, 0.2), pile(oak, 20, 0.18), pile(oak, 14, 0.21, fx=lambda s: recolor(s, hue=0.04, sat=1.25, bright=1.3)), pile(oak, 22, 0.17),
        pile(beech, 12, 0.2, fx=rotten), pile(oak, 16, 0.19, fx=lambda s: recolor(s, sat=0.45, bright=0.62)),
        pile(oak, 16, 0.2, fx=red), pile(oak, 20, 0.18, fx=red),
        pile(needles, 14, 0.62, dark=(0.6, 1.0)), pile(needles, 22, 0.55, dark=(0.55, 1.0)),
        twigs(), twigs(),
        pebbles(), pebbles(),
        pile(beech, 3, 0.36, dark=(0.85, 1.0)), pile(cedar, 3, 0.55, dark=(0.6, 0.85)),
    ]
    atlas = Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        atlas.alpha_composite(c, ((i % 4) * CELL, (i // 4) * CELL))
    # 透明的地方填邻近颜色（缩小贴图时边缘不发黑）
    import numpy as np
    a = np.asarray(atlas).astype(np.float32)
    al = a[..., 3:4] / 255.0
    pre = Image.fromarray((a[..., :3] * al).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))
    alb = Image.fromarray((al[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(10))
    pre = np.asarray(pre).astype(np.float32)
    alb = np.asarray(alb).astype(np.float32)[..., None] / 255.0
    fill = pre / np.maximum(alb, 1e-3)
    rgb = np.where(al > 0.5, a[..., :3], fill)
    out = np.concatenate([rgb, a[..., 3:4]], axis=2).clip(0, 255).astype(np.uint8)
    atlas = Image.fromarray(out, "RGBA")
    atlas.save(OUT)
    print("生成", OUT)


if __name__ == "__main__":
    main()
