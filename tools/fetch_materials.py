#!/usr/bin/env python3
"""下载 PBR 材质贴图（ambientCG，CC0），处理成游戏里 MatLib 用的文件。

用法：python tools/fetch_materials.py
输出：game/assets/textures/mat/<名字>_albedo.jpg / _normal.jpg / _rough.jpg

- neutral = True 的材质（瓦、朱漆、布、皮、纸、灰泥）：颜色去掉、亮度拉平，游戏里用 albedo_color 上色
  （同一张贴图能当青瓦、朱漆、黑漆、各色袍子），平均亮度 NEUTRAL_MEAN，MatLib 里乘回来
- 其他（木头、铜、铁、石板）：保留原色
- 法线用 OpenGL 方向（NormalGL，Godot 用的就是这个）
"""
import io
import os
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
DL = os.path.join(ROOT, "_downloads", "mat")
OUT = os.path.join(ROOT, "..", "game", "assets", "textures", "mat")
UA = {"User-Agent": "CangxuHunter-dev/0.1"}
NEUTRAL_MEAN = 0.72

# 名字: (ambientCG id, 分辨率, 是否去色)
MATS = {
    "roof": ("RoofingTiles008", "2K", True),       # 筒瓦（屋顶）
    "lacquer": ("PaintedWood006A", "1K", True),    # 漆木（朱漆柱子、牌坊、船舷）
    "planks": ("Planks037A", "2K", False),         # 旧木板（码头、桥、甲板）
    "wood": ("Wood026", "2K", False),              # 紫檀色硬木（暗器、家具）
    "wood_light": ("Wood049", "1K", False),        # 浅色木（箱子、杆子）
    "bronze": ("Metal008", "2K", False),           # 青铜（暗器包边、香炉）
    "gold": ("Metal048A", "1K", False),            # 金
    "brass": ("Metal035", "1K", False),            # 黄铜 / 红铜
    "iron": ("Metal038", "2K", False),             # 乌铁
    "cloth": ("Fabric030", "1K", True),            # 细布（袖子、袍子）
    "canvas": ("Fabric061", "1K", True),           # 粗布（帆、旗、幌子）
    "leather": ("Leather026", "2K", True),         # 皮（手套、护腕、握把缠皮）
    "cobble": ("PavingStones070", "2K", False),    # 石板路
    "brick": ("Bricks066", "1K", False),           # 青砖（城墙）
    "marble": ("Marble012", "1K", False),          # 汉白玉（台基）
    "granite": ("Granite002B", "1K", False),       # 哑光花岗岩（石狮子、石灯笼、柱础）
    "paper": ("Paper006", "1K", True),             # 灯笼纸
    "rope": ("Rope001", "1K", False),              # 麻绳
    "bamboo": ("Bamboo001A", "1K", False),         # 竹
    "plaster": ("Plaster001", "1K", True),         # 白墙
    "thatch": ("ThatchedRoof001A", "1K", False),   # 茅草
}


def get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def pick(names, suffix):
    for n in names:
        if n.endswith(suffix):
            return n
    return None


def neutral(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    lum = a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114
    lum = lum * (NEUTRAL_MEAN / max(float(lum.mean()), 1e-3))
    lum = np.clip(lum, 0.0, 1.0)
    g = (lum * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(np.stack([g, g, g], axis=-1))


def main() -> int:
    os.makedirs(DL, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, (aid, res, neu) in MATS.items():
        if only and name not in only:
            continue
        if os.path.exists(os.path.join(OUT, name + "_albedo.jpg")) and not only:
            continue
        z = os.path.join(DL, f"{aid}_{res}.zip")
        if not os.path.exists(z):
            data = get(f"https://ambientcg.com/get?file={aid}_{res}-JPG.zip")
            with open(z, "wb") as f:
                f.write(data)
        with zipfile.ZipFile(z) as zf:
            names = zf.namelist()
            col = pick(names, "_Color.jpg")
            nrm = pick(names, "_NormalGL.jpg")
            rgh = pick(names, "_Roughness.jpg")
            img = Image.open(io.BytesIO(zf.read(col))).convert("RGB")
            if neu:
                img = neutral(img)
            img.save(os.path.join(OUT, name + "_albedo.jpg"), quality=90)
            if nrm:
                Image.open(io.BytesIO(zf.read(nrm))).convert("RGB").save(os.path.join(OUT, name + "_normal.jpg"), quality=92)
            if rgh:
                Image.open(io.BytesIO(zf.read(rgh))).convert("L").save(os.path.join(OUT, name + "_rough.jpg"), quality=90)
        print("材质", name, aid, res)
    return 0


if __name__ == "__main__":
    sys.exit(main())
