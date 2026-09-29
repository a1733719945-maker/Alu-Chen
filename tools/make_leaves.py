"""阔叶树的叶片贴图重做（2026-09-29）：近看是一团团扁平的色块——以前每张 512、160 片叶子、每片 36~61 像素，叶子大、颜色平、枝条粗。
现在 1024、每张 540 片小叶子（ambientCG 真叶照片，CC0：LeafSet024 山毛榉、LeafSet005 长叶、LeafSet030 橡树叶），
由里往外三层：里层暗、偏灰（背光）→ 外层亮；两成叶子翻过来是背面（更浅、更灰）；枝条细、有分叉；每片叶子明暗、色相、饱和度都不一样。
只重做 leaf_green / leaf_dark / leaf_autumn / maple_red（竹叶、柳条、桃花、松针团是别的脚本）。

python tools/make_leaves.py（要先有 tools/_downloads/textures/LeafSet024 / 005 / 030 的 2K PNG）
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageEnhance

import prepare_assets as pa

SIZE = 1024
FT = os.path.join(pa.OUT, "textures", "foliage")
rng = random.Random(9090)


def load(aid):
    d = os.path.join(pa.TEX, aid)
    col = Image.open(os.path.join(d, f"{aid}_2K-PNG_Color.png")).convert("RGBA")
    op = Image.open(os.path.join(d, f"{aid}_2K-PNG_Opacity.png")).convert("L").resize(col.size)
    col.putalpha(op)
    return pa.split_sprites(col, 800)


def _twigs(d, S, color):
    """主枝从底部中间散开，每根上两三根小枝；返回所有枝段（给叶子找位置）"""
    base = (S * 0.5, S * 0.985)
    segs = []
    for k in range(7):
        ang = math.radians(-90 + (k - 3) * 16 + rng.uniform(-7, 7))
        L = S * rng.uniform(0.5, 0.74)
        bend = rng.uniform(-0.25, 0.25)
        pts = []
        for i in range(9):
            t = i / 8
            a = ang + bend * t
            pts.append((base[0] + math.cos(a) * L * t, base[1] + math.sin(a) * L * t))
        d.line(pts, fill=color + (255,), width=max(2, int(S * 0.0055)), joint="curve")
        segs.append((pts, ang + bend * 0.5))
        for j in range(rng.randint(2, 3)):
            i0 = rng.randint(3, 6)
            p0 = pts[i0]
            a2 = ang + rng.choice([-1, 1]) * rng.uniform(0.35, 0.8)
            L2 = L * rng.uniform(0.22, 0.38)
            q = [p0, (p0[0] + math.cos(a2) * L2 * 0.5, p0[1] + math.sin(a2) * L2 * 0.5), (p0[0] + math.cos(a2) * L2, p0[1] + math.sin(a2) * L2)]
            d.line(q, fill=color + (255,), width=max(1, int(S * 0.0035)), joint="curve")
            segs.append((q, a2))
    return segs


def card(leaves, out, n=540, scale=(0.05, 0.085), bright=(0.82, 1.08), hue=(-0.02, 0.02), sat=(0.85, 1.12), branch=(66, 50, 36)):
    S = SIZE
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    segs = _twigs(d, S, branch)
    placed = []
    for i in range(n):
        pts, ang = rng.choice(segs)
        t = 0.28 + 0.74 * math.sqrt(rng.random())
        k = t * (len(pts) - 1)
        i0 = min(int(k), len(pts) - 2)
        f = k - i0
        x = pts[i0][0] + (pts[i0 + 1][0] - pts[i0][0]) * f + rng.gauss(0, S * 0.03)
        y = pts[i0][1] + (pts[i0 + 1][1] - pts[i0][1]) * f + rng.gauss(0, S * 0.025)
        # 离中心越远越"外层"（越亮）
        depth = min(1.0, max(0.0, rng.random() * 0.6 + 0.4 * t))
        placed.append((depth, x, y, ang))
    placed.sort()
    margin = S * 0.06
    for depth, x, y, ang in placed:
        lf = rng.choice(leaves)
        s = rng.uniform(*scale) * S / max(lf.size)
        lf = lf.resize((max(4, int(lf.size[0] * s)), max(4, int(lf.size[1] * s))), Image.LANCZOS)
        underside = rng.random() < 0.2
        if underside:
            lf = lf.transpose(Image.FLIP_LEFT_RIGHT)
        rot = math.degrees(ang) + 90 + rng.uniform(-55, 55)
        lf = lf.rotate(-rot, expand=True, resample=Image.BICUBIC)
        shade = (0.52 + 0.48 * depth) * (1.0 - 0.12 * (y / S)) * rng.uniform(*bright)
        sa = rng.uniform(*sat) * (0.6 if underside else 1.0) * (0.75 + 0.25 * depth)
        if underside:
            shade *= 1.08
        lf = pa.tint(lf, rng.uniform(*hue) + (0.0 if depth > 0.5 else 0.015), shade, sa)
        px = min(max(x, margin), S - margin)
        py = min(max(y, margin), S - margin * 0.4)
        im.alpha_composite(lf, (int(px - lf.size[0] / 2), int(py - lf.size[1] / 2)))
    im.save(out)
    print("生成", out)


def main():
    beech = load("LeafSet024")
    long = load("LeafSet005")
    oak = load("LeafSet030")
    print("山毛榉", len(beech), "长叶", len(long), "橡树叶", len(oak))
    green = beech + beech + long
    card(green, os.path.join(FT, "leaf_green.png"))
    card(green, os.path.join(FT, "leaf_dark.png"), bright=(0.58, 0.82), hue=(-0.05, -0.01))
    card(oak + oak + beech[:2], os.path.join(FT, "leaf_autumn.png"), bright=(0.85, 1.12), hue=(-0.03, 0.03))
    reds = [pa.tint(l, -0.06, 1.0, 1.35) for l in oak]
    card(reds + reds + beech[:2], os.path.join(FT, "maple_red.png"), bright=(0.72, 1.05), hue=(-0.03, 0.0))


if __name__ == "__main__":
    main()
