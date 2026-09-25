#!/usr/bin/env python3
"""把 3D 用的贴图改成“显卡压缩 + 多级纹理（mipmap）”导入。

Godot 只有在编辑器里把贴图拖进 3D 材质时才会自动这样做；我们的材质是代码里建的，
所以要手动改 .import 文件，否则远处的草地、树叶会闪烁，显存也占得多。

用法：先 godot --headless --path game --import 生成 .import 文件，再运行本脚本，再导入一次。
"""
import glob
import os
import re
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game")
DIRS = ["assets/textures", "assets/models"]
EXTS = (".jpg", ".png")


def set_param(text, key, value):
    pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    if pat.search(text):
        return pat.sub("%s=%s" % (key, value), text)
    return text.rstrip("\n") + "\n%s=%s\n" % (key, value)


def main():
    changed = 0
    for d in DIRS:
        for path in glob.glob(os.path.join(ROOT, d, "**", "*"), recursive=True):
            if not path.lower().endswith(EXTS):
                continue
            imp = path + ".import"
            if not os.path.exists(imp):
                print("还没导入过：", path)
                continue
            text = open(imp, encoding="utf-8").read()
            old = text
            name = os.path.basename(path).lower()
            normal = "normal" in name or "nor_gl" in name
            text = set_param(text, "compress/mode", "2")
            text = set_param(text, "mipmaps/generate", "true")
            text = set_param(text, "compress/normal_map", "1" if normal else "0")
            text = set_param(text, "detect_3d/compress_to", "0")
            text = set_param(text, "compress/high_quality", "false")
            if text != old:
                open(imp, "w", encoding="utf-8").write(text)
                # 删掉旧的导入缓存，下次导入时重新生成
                m = re.search(r'^path(?:\.[a-z_0-9]+)?="(res://\.godot/imported/[^"]+)"', old, re.M)
                if m:
                    base = m.group(1).replace("res://", "")
                    for f in glob.glob(os.path.join(ROOT, os.path.splitext(base)[0] + "*")):
                        os.remove(f)
                changed += 1
    print("改了 %d 个贴图的导入设置" % changed)


if __name__ == "__main__":
    main()
