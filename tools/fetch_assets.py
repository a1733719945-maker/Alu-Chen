#!/usr/bin/env python3
"""下载游戏用到的免费素材（全部是 CC0 协议，可以免费商用、不用署名）。

来源：
  Poly Haven   https://polyhaven.com   天空 HDR、灌木、蕨类、花、石头、树桩
  ambientCG    https://ambientcg.com   地面、树皮贴图，树叶和草叶图集

用法：python3 tools/fetch_assets.py
下载到 tools/_downloads，再由 tools/prepare_assets.py 处理成游戏里的文件。
"""
import json
import os
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
DL = os.path.join(ROOT, "_downloads")
UA = {"User-Agent": "DouluoHunter-dev/0.1"}

HDRIS = {
    "sky_day": "kloofendal_48d_partly_cloudy_puresky",
    "sky_dusk": "kloppenheim_06_puresky",
    "sky_night": "qwantani_moonrise_puresky",
    "sky_snow": "snow_field_puresky",
    "sky_sea": "qwantani_noon_puresky",
}
MODELS = [
    "shrub_02", "shrub_03", "shrub_04", "fern_02", "dandelion_01", "periwinkle_plant",
    "flower_ursinia", "rock_moss_set_01", "rock_moss_set_02", "boulder_01", "tree_stump_01",
    "dead_tree_trunk", "dead_tree_trunk_02", "nettle_plant", "shrub_sorrel_01", "root_cluster_01",
]
TEXTURES = {
    "grass": "Grass004", "dirt": "Ground037", "rock": "Rock051", "sand": "Ground054",
    "forest": "Ground078", "mud": "Ground109", "bark": "Bark014", "moss": "Moss002",
    "snow": "Snow010A", "ice": "Ice002",
}
ATLASES = ["Foliage001", "Foliage006", "LeafSet024", "LeafSet030", "PineNeedles001"]


def get(url, path=None):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req) as r:
        data = r.read()
    if path:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    return data


def main():
    os.makedirs(DL, exist_ok=True)
    for name, pid in HDRIS.items():
        out = os.path.join(DL, "hdri", name + ".hdr")
        if not os.path.exists(out):
            files = json.loads(get(f"https://api.polyhaven.com/files/{pid}"))
            get(files["hdri"]["2k"]["hdr"]["url"], out)
            print("天空", name, os.path.getsize(out))
    for m in MODELS:
        d = os.path.join(DL, "models", m)
        if os.path.exists(os.path.join(d, m + "_1k.gltf")):
            continue
        files = json.loads(get(f"https://api.polyhaven.com/files/{m}"))
        g = files["gltf"]["1k"]["gltf"]
        get(g["url"], os.path.join(d, m + "_1k.gltf"))
        for rel, info in g.get("include", {}).items():
            get(info["url"], os.path.join(d, rel))
        print("模型", m)
    for key, aid in {**TEXTURES, **{a: a for a in ATLASES}}.items():
        d = os.path.join(DL, "textures", aid)
        if os.path.isdir(d):
            continue
        fmt = "PNG" if aid in ATLASES else "JPG"
        z = os.path.join(DL, "textures", aid + ".zip")
        get(f"https://ambientcg.com/get?file={aid}_1K-{fmt}.zip", z)
        with zipfile.ZipFile(z) as zf:
            zf.extractall(d)
        os.remove(z)
        print("贴图", aid)


if __name__ == "__main__":
    sys.exit(main())
