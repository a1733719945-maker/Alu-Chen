#!/usr/bin/env python3
"""国风 CG：把用户用即梦 / 可灵做的图生视频（01~14.mp4）剪成游戏里的过场（Ogg Theora）。

原片放在 tools/_downloads/cg/（用户传在 GitHub Release 草稿里，太大不进仓库）。
每段：缩到 1280x720、30 帧；段和段之间 0.8 秒淡入淡出，开头从黑淡入、结尾淡到黑。
字幕、标题由游戏叠（Voyage.captions / title），不画进视频。

用法：python tools/build_cg.py [片名 ...]
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "_downloads", "cg")
OUT = os.path.join(ROOT, "..", "game", "assets", "cutscene")
XF = 0.8

# 片名: (段落, 码率)
LORD = {1: "06", 2: "07", 3: "08", 4: "09", 5: "10"}
FILMS = {
    # 序章：叩天 → 云岫碎身 → 天枢坠落 → 九重天 → 青崖子
    "prologue": (["02", "03", "04", "01", "05"], "3200k"),
    "dungeon": (["12"], "3500k"),
    "hunt": (["13"], "3000k"),
    "ascend": (["14", "01"], "3200k"),
}
for ch, lord in LORD.items():
    # 渡海：乌篷船在云海上 → 这一章的灵主
    FILMS["voyage_%d" % ch] = (["11", lord], "3000k")


def ffprobe_dur(path):
    exe = os.path.join(os.path.dirname(FFMPEG), "ffprobe.exe" if os.name == "nt" else "ffprobe")
    out = subprocess.check_output([exe, "-v", "error", "-show_entries", "format=duration", "-of", "json", path])
    return float(json.loads(out)["format"]["duration"])


def build(name, clips, rate):
    ins = []
    durs = []
    for c in clips:
        p = os.path.join(SRC, c + ".mp4")
        ins += ["-i", p]
        durs.append(ffprobe_dur(p))
    parts = []
    for i in range(len(clips)):
        # 右下角有 AI 工具的水印（即梦 AI / Dola AI，占底下 13%、右边 20%）：取画面的 86%——顶上对齐、左右各切 7%，再放大回 1280x720
        parts.append("[%d:v]fps=30,crop=iw*0.86:ih*0.86:iw*0.07:0,scale=1280:720:flags=lanczos,setsar=1,format=yuv420p[v%d]" % (i, i))
    last = "v0"
    t = durs[0]
    for i in range(1, len(clips)):
        off = t - XF
        parts.append("[%s][v%d]xfade=transition=fade:duration=%.2f:offset=%.3f[x%d]" % (last, i, XF, off, i))
        last = "x%d" % i
        t = off + durs[i]
    total = t
    parts.append("[%s]fade=t=in:st=0:d=0.6,fade=t=out:st=%.3f:d=0.8[out]" % (last, total - 0.8))
    out = os.path.join(OUT, name + ".ogv")
    cmd = [FFMPEG, "-y", "-hide_banner", "-loglevel", "error"] + ins + ["-filter_complex", ";".join(parts), "-map", "[out]", "-an",
           "-c:v", "libtheora", "-b:v", rate, "-maxrate", rate, "-bufsize", "6M", out]
    subprocess.check_call(cmd)
    print("%-10s %5.1f 秒  %.1f MB  %s" % (name, total, os.path.getsize(out) / 1048576.0, " + ".join(clips)))


def main():
    only = set(sys.argv[1:])
    for name, (clips, rate) in FILMS.items():
        if only and name not in only:
            continue
        if not all(os.path.exists(os.path.join(SRC, c + ".mp4")) for c in clips):
            print("缺原片，跳过", name)
            continue
        build(name, clips, rate)


def _ffmpeg():
    import shutil
    return shutil.which("ffmpeg") or "ffmpeg"


FFMPEG = _ffmpeg()

if __name__ == "__main__":
    sys.exit(main())
