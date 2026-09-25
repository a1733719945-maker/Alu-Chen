#!/usr/bin/env python3
"""把思源黑体（Noto Sans SC，SIL OFL 协议，可免费商用）裁成游戏用得到的字，减小体积。

保留：游戏脚本和说明里出现的所有字 + GB2312 一级常用字（3755 个，玩家起名字够用）+ ASCII。
原文件：https://github.com/notofonts/noto-cjk （Sans/SubsetOTF/SC）
数字用的 Barlow Condensed（SIL OFL）来自 Google Fonts。

用法：python3 tools/subset_fonts.py <放原始 otf 的文件夹>
加了新的中文文字以后重新跑一次。
"""
import glob
import os
import sys

from fontTools import subset

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "game", "assets", "fonts")


def charset():
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars |= set("·—…“”‘’、。，：；！？（）【】《》「」『』〔〕×÷±°％～·￥")
    for f in glob.glob(os.path.join(ROOT, "game", "scripts", "**", "*.gd"), recursive=True) + glob.glob(os.path.join(ROOT, "docs", "*")):
        with open(f, encoding="utf-8", errors="ignore") as fh:
            chars |= set(fh.read())
    # GB2312 一级汉字
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(sorted(c for c in chars if c.isprintable()))


def main(src):
    text = charset()
    print("保留 %d 个字" % len(text))
    for w in ["Medium", "Bold", "Black"]:
        path = os.path.join(src, "NotoSansSC-%s.otf" % w)
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        font = subset.load_font(path, opts)
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        out = os.path.join(OUT, "NotoSansSC-%s.otf" % w)
        subset.save_font(font, out, opts)
        print("生成", out, os.path.getsize(out))


if __name__ == "__main__":
    main(sys.argv[1])
