#!/usr/bin/env python3
"""把 tools/_downloads 里的原始素材处理成游戏用的文件，放进 game/assets/。

  1. 树冠贴片：把一片片树叶拼成一簇枝叶（带透明），树用几十张这样的贴片就很茂密
  2. 草丛贴片：几根草叶拼成一丛
  3. 地面、树皮贴图：复制颜色图和法线图
  4. 天空 HDR、Poly Haven 模型：复制

用法：python3 tools/fetch_assets.py && python3 tools/prepare_assets.py
"""
import glob
import math
import os
import random
import shutil

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
DL = os.path.join(ROOT, "_downloads")
OUT = os.path.join(ROOT, "..", "game", "assets")
TEX = os.path.join(DL, "textures")
rng = random.Random(20260925)


def load_rgba(aid):
    d = os.path.join(TEX, aid)
    col = Image.open(glob.glob(os.path.join(d, "*_Color.png"))[0]).convert("RGBA")
    op = glob.glob(os.path.join(d, "*_Opacity.png"))
    if op:
        a = Image.open(op[0]).convert("L").resize(col.size)
        col.putalpha(a)
    return col


def split_sprites(img, min_area=400):
    """按透明度把图集切成一个个叶子（找连通的不透明区域）"""
    a = img.split()[3].point(lambda v: 255 if v > 40 else 0)
    w, h = a.size
    small = a.resize((w // 4, h // 4))
    px = small.load()
    sw, sh = small.size
    seen = set()
    boxes = []
    for y in range(sh):
        for x in range(sw):
            if px[x, y] and (x, y) not in seen:
                stack = [(x, y)]
                seen.add((x, y))
                x0 = x1 = x
                y0 = y1 = y
                n = 0
                while stack:
                    cx, cy = stack.pop()
                    n += 1
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < sw and 0 <= ny < sh and px[nx, ny] and (nx, ny) not in seen:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
                if n * 16 >= min_area:
                    boxes.append((x0 * 4, y0 * 4, (x1 + 1) * 4, (y1 + 1) * 4))
    return [img.crop(b) for b in boxes]


def tint(im, hue_shift=0.0, bright=1.0, sat=1.0):
    im = ImageEnhance.Brightness(im).enhance(bright)
    im = ImageEnhance.Color(im).enhance(sat)
    if hue_shift:
        r, g, b, a = im.split()
        rgb = Image.merge("RGB", (r, g, b)).convert("HSV")
        hch, s, v = rgb.split()
        hch = hch.point(lambda x: (x + int(hue_shift * 255)) % 256)
        rgb = Image.merge("HSV", (hch, s, v)).convert("RGB")
        im = Image.merge("RGBA", (*rgb.split(), a))
    return im


def colorize(im, rgb):
    """把枯黄的松针染成绿色：先变灰，再乘上颜色"""
    r, g, b, a = im.split()
    gray = Image.merge("RGB", (r, g, b)).convert("L")
    col = Image.merge("RGB", [gray.point(lambda v, c=c: int(min(255, v * c * 1.6))) for c in rgb])
    return Image.merge("RGBA", (*col.split(), a))


def leaf_card(leaves, out, size=512, n=160, bright=(0.75, 1.1), hue=(-0.02, 0.02), branch=(88, 64, 40), leaf_scale=(0.07, 0.12)):
    """一簇枝叶：从底部中间长出几根细枝，叶子沿枝条分布"""
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    base = (size * 0.5, size * 0.98)
    tips = []
    for k in range(7):
        ang = math.radians(-90 + (k - 3) * 17 + rng.uniform(-8, 8))
        L = size * rng.uniform(0.5, 0.72)
        tip = (base[0] + math.cos(ang) * L, base[1] + math.sin(ang) * L)
        d.line([base, tip], fill=branch + (255,), width=int(size * 0.012))
        tips.append((ang, L))
    for i in range(n):
        ang, L = rng.choice(tips)
        t = rng.uniform(0.25, 1.0)
        px = base[0] + math.cos(ang) * L * t + rng.uniform(-40, 40) * t
        py = base[1] + math.sin(ang) * L * t + rng.uniform(-30, 30) * t
        margin = size * 0.1
        px = min(max(px, margin), size - margin)
        py = min(max(py, margin), size - margin * 0.5)
        lf = rng.choice(leaves)
        s = rng.uniform(*leaf_scale) * size / max(lf.size)
        lf = lf.resize((max(4, int(lf.size[0] * s)), max(4, int(lf.size[1] * s))), Image.LANCZOS)
        rot = math.degrees(ang) + 90 + rng.uniform(-60, 60)
        lf = lf.rotate(-rot, expand=True, resample=Image.BICUBIC)
        # 中间和下面的叶子暗一点（假的环境光遮蔽）
        shade = 1.0 - 0.35 * (1.0 - t) - 0.15 * (py / size)
        lf = tint(lf, rng.uniform(*hue), rng.uniform(*bright) * shade, rng.uniform(0.9, 1.15))
        card.alpha_composite(lf, (int(px - lf.size[0] / 2), int(py - lf.size[1] / 2)))
    # 边缘羽化一点，远处不闪
    card = card.filter(ImageFilter.SMOOTH)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    card.save(out)
    print("生成", out)


def grass_card(blades, out, size=256, n=16, bright=(0.7, 1.05)):
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for i in range(n):
        bl = rng.choice(blades)
        h = size * rng.uniform(0.55, 0.98)
        s = h / bl.size[1]
        bl = bl.resize((max(3, int(bl.size[0] * s * 1.2)), max(4, int(bl.size[1] * s))), Image.LANCZOS)
        bl = bl.rotate(rng.uniform(-18, 18), expand=True, resample=Image.BICUBIC)
        bl = tint(bl, rng.uniform(-0.02, 0.03), rng.uniform(*bright), rng.uniform(0.9, 1.2))
        x = size * 0.5 + rng.uniform(-size * 0.3, size * 0.3) - bl.size[0] / 2
        card.alpha_composite(bl, (int(x), int(size - bl.size[1])))
    card.save(out)
    print("生成", out)


def palm_card(out, size=512):
    """棕榈叶：一根弯弯的叶脉，两边一排排细长的小叶"""
    import numpy as np
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    pts = []
    for i in range(41):
        t = i / 40
        x = size * 0.5 + math.sin(t * 1.6) * size * 0.06
        y = size * (0.98 - t * 0.94)
        pts.append((x, y))
    for i in range(3, 40):
        t = i / 40
        x, y = pts[i]
        L = size * 0.34 * math.sin(math.pi * min(1.0, t * 1.05)) ** 0.7
        for side in (-1, 1):
            ang = math.radians(90 + side * (58 - t * 20)) 
            ex = x + side * abs(math.cos(ang)) * L
            ey = y - math.sin(math.radians(28)) * L * (0.6 + t * 0.4)
            w = max(2, int(size * 0.018 * (1.1 - t * 0.5)))
            g = int(rng.uniform(95, 150) * (0.8 + t * 0.3))
            col = (int(g * 0.45), g, int(g * 0.28), 255)
            d.line([(x, y), ((x + ex) / 2, (y + ey) / 2 - 4), (ex, ey)], fill=col, width=w, joint="curve")
    d.line(pts, fill=(120, 110, 60, 255), width=int(size * 0.012))
    card = card.filter(ImageFilter.SMOOTH)
    card.save(out)
    print("生成", out)


def snowy(src, out):
    """给松针贴片加雪：上面的针叶盖一层白"""
    import numpy as np
    im = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32)
    h, w = im.shape[:2]
    noise = np.asarray(Image.effect_noise((w // 8, h // 8), 80).resize((w, h), Image.BILINEAR)).astype(np.float32) / 255.0
    yy = np.linspace(1, 0, h)[:, None]
    k = np.clip((noise * 0.9 + yy * 0.5 - 0.55) * 3.0, 0, 1) * (im[..., 3] > 30)
    for c in range(3):
        im[..., c] = im[..., c] * (1 - k) + 235 * k
    Image.fromarray(im.clip(0, 255).astype(np.uint8), "RGBA").save(out)
    print("生成", out)


def main():
    ft = os.path.join(OUT, "textures", "foliage")
    os.makedirs(ft, exist_ok=True)
    green = split_sprites(load_rgba("LeafSet024"))
    autumn = split_sprites(load_rgba("LeafSet030"))
    blades = split_sprites(load_rgba("Foliage001"), 200) + split_sprites(load_rgba("Foliage006"), 200)
    # 竖直的草叶才能用
    blades = [b for b in blades if b.size[1] > b.size[0] * 2.5]
    needles = split_sprites(load_rgba("PineNeedles001"), 200)
    print("树叶", len(green), "秋叶", len(autumn), "草叶", len(blades), "松针", len(needles))
    leaf_card(green, os.path.join(ft, "leaf_green.png"))
    leaf_card(green, os.path.join(ft, "leaf_dark.png"), bright=(0.5, 0.8), hue=(-0.05, -0.01))
    leaf_card(autumn + green[:3], os.path.join(ft, "leaf_autumn.png"), bright=(0.8, 1.15), hue=(-0.03, 0.03))
    leaf_card([colorize(l, (0.35, 0.6, 0.3)) for l in needles], os.path.join(ft, "leaf_pine.png"), n=220, leaf_scale=(0.16, 0.26), branch=(70, 50, 30))
    grass_card(blades, os.path.join(ft, "grass_tuft.png"))
    grass_card(blades, os.path.join(ft, "grass_tuft_dry.png"), bright=(0.9, 1.2))
    palm_card(os.path.join(ft, "palm_frond.png"))
    snowy(os.path.join(ft, "leaf_pine.png"), os.path.join(ft, "leaf_pine_snow.png"))

    tt = os.path.join(OUT, "textures", "ground")
    os.makedirs(tt, exist_ok=True)
    from fetch_assets import TEXTURES
    for key, aid in TEXTURES.items():
        d = os.path.join(TEX, aid)
        for suffix, name in (("_Color.jpg", "albedo"), ("_NormalGL.jpg", "normal")):
            src = glob.glob(os.path.join(d, "*" + suffix))
            if src:
                im = Image.open(src[0]).convert("RGB")
                im = im.resize((1024, 1024), Image.LANCZOS)
                im.save(os.path.join(tt, f"{key}_{name}.jpg"), quality=88)
        print("贴图", key)

    sk = os.path.join(OUT, "sky")
    os.makedirs(sk, exist_ok=True)
    for f in glob.glob(os.path.join(DL, "hdri", "*.hdr")):
        shutil.copy(f, sk)

    md = os.path.join(OUT, "models", "env")
    for d in glob.glob(os.path.join(DL, "models", "*")):
        name = os.path.basename(d)
        dst = os.path.join(md, name)
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(d, dst)
    print("完成")


if __name__ == "__main__":
    main()
