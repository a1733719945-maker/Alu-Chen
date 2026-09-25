#!/usr/bin/env python3
"""下载魂兽和 Boss 的 3D 模型（带动画）。

全部来自 Quaternius（https://quaternius.com），CC0 协议：免费商用、不用署名。
原文件放在他的 Google Drive 公开文件夹里，这里按 包 → 子文件夹 → 文件名 找到再下载。

用法：python3 tools/fetch_models.py
保存到 game/assets/models/creatures/<名字>.gltf 或 .fbx
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gdrive  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "models", "creatures")

PACKS = {
    "animals": "1uJ3N5HfB7jKTseJUNQr3N4YaN0UuEtHk",       # Ultimate Animated Animals
    "enemy": "1VbJIslXPWK-1KybQN6yezZrfJcw608qe",         # Easy Enemy
    "monsters": "18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C",      # Ultimate Monsters
    "monster": "102H-oyUM8SGYi1mW0GOgkjEu7xSdaORA",       # Animated Monster
    "dinos": "1u5Fhu3ziuRlGonW6bUI7uClqBGoSNeF6",         # Animated Dinosaurs
    "fish": "1SvlOveJJjmhSn-FgCRyojc1T5QHjjGkF",          # Animated Fish
    "cute": "1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0",          # Cute Monsters
}

# 保存名: (包, 子文件夹路径, 文件名)
MODELS = {
    "wolf": ("animals", ["glTF"], "Wolf.gltf"),
    "husky": ("animals", ["glTF"], "Husky.gltf"),
    "bull": ("animals", ["glTF"], "Bull.gltf"),
    "stag": ("animals", ["glTF"], "Stag.gltf"),
    "deer": ("animals", ["glTF"], "Deer.gltf"),
    "spider": ("enemy", ["FBX"], "Spider.fbx"),
    "snake": ("enemy", ["FBX"], "Snake.fbx"),
    "snake_angry": ("enemy", ["FBX"], "Snake_angry.fbx"),
    "wasp": ("enemy", ["FBX"], "Wasp.fbx"),
    "frog": ("enemy", ["FBX"], "Frog.fbx"),
    "bunny": ("monsters", ["Big", "glTF"], "Bunny.gltf"),
    "yeti": ("monsters", ["Big", "glTF"], "Yeti.gltf"),
    "pigeon": ("monsters", ["Flying", "glTF"], "Pigeon.gltf"),
    "bat": ("monster", ["FBX"], "Bat.fbx"),
    "dragon": ("monster", ["FBX"], "Dragon.fbx"),
    "raptor": ("dinos", ["FBX"], "Velociraptor.fbx"),
    "triceratops": ("dinos", ["FBX"], "Triceratops.fbx"),
    "shark": ("fish", ["FBX"], "Shark.fbx"),
    "whale": ("fish", ["FBX"], "Whale.fbx"),
    "manta": ("fish", ["FBX"], "Manta ray.fbx"),
    "fish1": ("fish", ["FBX"], "Fish1.fbx"),
    "fish2": ("fish", ["FBX"], "Fish2.fbx"),
    "crab": ("cute", ["glTF"], "Crab.gltf"),
}

_cache = {}


def _ls(fid):
    if fid not in _cache:
        _cache[fid] = gdrive.ls(fid)
    return _cache[fid]


def _find(fid, name):
    for cid, n, kind, size in _ls(fid):
        if n.lower() == name.lower():
            return cid
    return None


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, (pack, path, fname) in MODELS.items():
        ext = os.path.splitext(fname)[1]
        dst = os.path.join(OUT, key + ext)
        if os.path.exists(dst):
            continue
        fid = PACKS[pack]
        for p in path:
            fid = _find(fid, p)
            if not fid:
                break
        cid = _find(fid, fname) if fid else None
        if not cid:
            print("找不到", key, pack, path, fname)
            continue
        n = gdrive.get(cid, dst)
        print("模型", key, n)
    # 贴图集（Ultimate Monsters 共用一张色板）
    atlas = os.path.join(OUT, "Atlas_Monsters.png")
    if not os.path.exists(atlas):
        big = _find(_find(PACKS["monsters"], "Big"), "glTF")
        cid = _find(big, "Atlas_Monsters.png")
        if cid:
            gdrive.get(cid, atlas)


if __name__ == "__main__":
    main()
