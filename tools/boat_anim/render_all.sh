#!/bin/bash
# 渲染全部过场：Remotion（1920x1080 mp4）→ ffmpeg 缩到 1600x900、轻微降噪，按码率转 Ogg Theora → game/assets/cutscene/
# 名画细节多，按质量编码体积会很大（铜版画 4 秒就 20 MB），所以每段给一个码率：画面越细、片子越短，码率越高。
# 用法：./render_all.sh                      全部
#       ./render_all.sh HuntGate:hunt:3500k  只渲一段
# 先跑一次 python3 fetch_art.py（下载名画和字体），再 npm install。Linux 上用 Playwright 自带的无头 Chromium。
set -e
cd "$(dirname "$0")"
B=${BROWSER:-$(ls -d /opt/pw-browsers/chromium_headless_shell-*/*/headless_shell 2>/dev/null | head -1)}
DST=../../game/assets/cutscene
mkdir -p out/final
npx remotion bundle src/index.ts --out-dir out/bundle --log=error > /dev/null
LIST=${@:-"Prologue:prologue:2600k Voyage1:voyage_1:3500k Voyage2:voyage_2:3500k Voyage3:voyage_3:3500k Voyage4:voyage_4:3500k Voyage5:voyage_5:3500k Ascend:ascend:3000k DungeonGate:dungeon:7000k HuntGate:hunt:3500k"}
for item in $LIST; do
	IFS=: read -r id name rate <<< "$item"
	t0=$(date +%s)
	npx remotion render out/bundle "$id" "out/final/$name.mp4" --codec=h264 --crf=14 --concurrency=${CONC:-4} --browser-executable="$B" --log=error > /dev/null
	ffmpeg -y -loglevel error -i "out/final/$name.mp4" -vf "scale=1600:900:flags=lanczos,hqdn3d=1.5:1.5:3:3" -c:v libtheora -b:v "${rate:-3000k}" -an "$DST/$name.ogv"
	echo "$name $(( $(date +%s) - t0 ))s $(du -h "$DST/$name.ogv" | cut -f1)"
done
