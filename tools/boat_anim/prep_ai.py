"""AI 生成的国风过场图（ai/NN.webp|jpg|png，用户用即梦 / 豆包 / Dola 生成的）→ public/art/aiNN.jpg。

裁掉右下角的 AI 水印（底部 CUT_BOTTOM 比例），写进 src/artdims.json（和名画共用镜头尺寸表）。用法：python3 prep_ai.py
"""
import glob, json, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CUT_BOTTOM = 0.11    # 水印在右下角（Dola AI 大约占底部 5%~10%），裁掉底部这么高的一条
dims_path = os.path.join(HERE, "src", "artdims.json")
dims = json.load(open(dims_path))
os.makedirs(os.path.join(HERE, "public", "art"), exist_ok=True)
for f in sorted(glob.glob(os.path.join(HERE, "ai", "*"))):
    stem = os.path.splitext(os.path.basename(f))[0]
    if not stem.isdigit():
        continue
    key = "ai%02d" % int(stem)
    im = Image.open(f).convert("RGB")
    im = im.crop((0, 0, im.width, int(im.height * (1 - CUT_BOTTOM))))
    im.save(os.path.join(HERE, "public", "art", key + ".jpg"), quality=94)
    dims[key] = list(im.size)
    print(key, im.size)
json.dump(dims, open(dims_path, "w"), indent=1)

# 流云贴图（国风过场里飘过画面的云层）：分形噪声 → 白色 + 透明度，左右无缝
import numpy as np
fx_dir = os.path.join(HERE, "public", "fx")
os.makedirs(fx_dir, exist_ok=True)
path = os.path.join(fx_dir, "clouds.png")
if not os.path.exists(path):
    rng = np.random.default_rng(7)
    W, H = 2048, 768
    acc = np.zeros((H, W))
    amp, total = 1.0, 0.0
    for octave in range(6):
        gw, gh = 4 * 2 ** octave, max(2, int(1.5 * 2 ** octave))
        grid = rng.random((gh + 1, gw))
        grid = np.concatenate([grid, grid[:, :1]], axis=1)  # 左右接得上
        layer = np.asarray(Image.fromarray((grid * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), dtype=float) / 255
        acc += layer * amp; total += amp; amp *= 0.5
    acc /= total
    v = np.clip((acc - 0.46) / 0.3, 0, 1) ** 1.6
    fade = np.clip(np.sin(np.linspace(0, np.pi, H)) * 1.6, 0, 1)[:, None]  # 上下边缘淡掉
    a = (v * fade * 255).astype(np.uint8)
    rgba = np.dstack([np.full((H, W), 255, np.uint8)] * 3 + [a])
    Image.fromarray(rgba, "RGBA").save(path)
    print("clouds.png")
