#!/usr/bin/env python3
"""下载界面图标：game-icons.net（CC BY 3.0，作者 Lorc、Delapouite 等，https://game-icons.net）。
去掉黑色背景方块，存成透明的白色剪影 SVG：game/assets/icons/<名字>.svg
用法：python3 tools/fetch_icons.py
"""
import os
import re
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "game", "assets", "icons")
BASE = "https://raw.githubusercontent.com/game-icons/icons/master/"

# 名字: 候选路径（按顺序试，第一个能下的）
ICONS = {
    "beam": ["lorc/laser-blast.svg", "lorc/beam-wake.svg", "lorc/sun-radiations.svg"],
    "buff": ["lorc/muscle-up.svg", "lorc/upgrade.svg"],
    "dash": ["delapouite/sprint.svg", "lorc/run.svg"],
    "heal": ["lorc/health-normal.svg", "lorc/heart-plus.svg", "lorc/healing.svg", "delapouite/health-potion.svg", "lorc/heart-bottle.svg"],
    "launch": ["lorc/earth-spit.svg", "lorc/spiky-explosion.svg"],
    "leap": ["delapouite/jump-across.svg", "lorc/wing-cloak.svg"],
    "mark": ["lorc/targeted.svg", "lorc/crosshair.svg", "lorc/on-target.svg", "delapouite/target-arrows.svg", "lorc/bullseye.svg"],
    "projectile": ["lorc/fireball.svg", "lorc/fire-ray.svg"],
    "pull": ["lorc/vortex.svg", "lorc/magnet.svg"],
    "rain": ["lorc/meteor-impact.svg", "lorc/fire-rain.svg"],
    "root": ["lorc/vine-whip.svg", "lorc/curling-vines.svg"],
    "shield": ["lorc/magic-shield.svg", "sbed/shield.svg"],
    "grenade": ["lorc/lotus.svg", "lorc/lotus-flower.svg"],
    "pill": ["delapouite/pill.svg", "lorc/pill.svg"],
    "coin": ["delapouite/two-coins.svg", "lorc/crown-coin.svg"],
    "lure": ["delapouite/fishing-hook.svg", "lorc/fishing-hook.svg"],
    "quest": ["lorc/scroll-unfurled.svg", "delapouite/scroll-quill.svg"],
    "lock": ["delapouite/padlock.svg", "lorc/padlock.svg"],
    "heart": ["zeromancer/heart-plus.svg", "lorc/heart-organ.svg", "lorc/hearts.svg"],
    "soul": ["lorc/spiral-lollipop.svg", "lorc/fairy-wand.svg", "lorc/star-swirl.svg"],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, cands in ICONS.items():
        for c in cands:
            try:
                svg = urllib.request.urlopen(BASE + c, timeout=30).read().decode()
            except Exception:
                continue
            svg = re.sub(r'<path d="M0 0h512v512H0z"\s*/>', "", svg)
            with open(os.path.join(OUT, name + ".svg"), "w") as f:
                f.write(svg)
            print(name, "<-", c)
            break
        else:
            print(name, "没找到")


if __name__ == "__main__":
    main()
