"""下载过场动画用的名画（art.json 里的清单）到 public/art/<key>.jpg，长边缩到 3200 像素。

全部是公有领域：画家都去世超过 100 年；博物馆开放图库（大都会、克利夫兰、美国国家美术馆）是 CC0。
维基的原图接口会限流，所以下 3840 宽的缩略图，每张之间歇几秒。用法：python3 fetch_art.py
"""
import io, json, os, time, urllib.request
from PIL import Image

UA = "CangxuGameCutscene/1.0 (https://github.com/a1733719945-maker/Alu-Chen)"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "public", "art")
os.makedirs(OUT, exist_ok=True)
Image.MAX_IMAGE_PIXELS = None
art = json.load(open(os.path.join(HERE, "art.json"), encoding="utf-8"))
for key, a in art.items():
    path = os.path.join(OUT, key + ".jpg")
    if os.path.exists(path):
        continue
    for attempt in range(5):
        try:
            data = urllib.request.urlopen(urllib.request.Request(a["url"], headers={"User-Agent": UA}), timeout=120).read()
            break
        except Exception as e:
            print(key, "retry", attempt, e)
            time.sleep(8 * (attempt + 1))
    else:
        print("FAILED", key)
        continue
    im = Image.open(io.BytesIO(data)).convert("RGB")
    if "crop" in a:  # 博物馆照片带的画框 / 黑边：[左, 上, 右, 下] 占宽高的比例
        l, t, r, b = a["crop"]
        im = im.crop((int(im.width * l), int(im.height * t), int(im.width * (1 - r)), int(im.height * (1 - b))))
    im.thumbnail((3200, 3200), Image.LANCZOS)
    im.save(path, quality=92)
    print(key, im.size)
    if "wikimedia" in a["url"]:
        time.sleep(4)

# 字体（SIL OFL）：思源宋体（中文字幕）、EB Garamond（英文）、Courier Prime（纸片卡片）
FONTS = {
    "NotoSerifSC.ttf": "ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf",
    "EBGaramond.ttf": "ofl/ebgaramond/EBGaramond%5Bwght%5D.ttf",
    "EBGaramond-Italic.ttf": "ofl/ebgaramond/EBGaramond-Italic%5Bwght%5D.ttf",
    "CourierPrime.ttf": "ofl/courierprime/CourierPrime-Regular.ttf",
}
os.makedirs(os.path.join(HERE, "public", "fonts"), exist_ok=True)
for name, src in FONTS.items():
    path = os.path.join(HERE, "public", "fonts", name)
    if not os.path.exists(path):
        data = urllib.request.urlopen(urllib.request.Request("https://raw.githubusercontent.com/google/fonts/main/" + src, headers={"User-Agent": UA}), timeout=120).read()
        open(path, "wb").write(data)
        print(name, len(data))

# 每张画的像素大小（镜头按它算）
dims = {}
for key in art:
    path = os.path.join(OUT, key + ".jpg")
    if os.path.exists(path):
        dims[key] = list(Image.open(path).size)
json.dump(dims, open(os.path.join(HERE, "src", "artdims.json"), "w"), indent=1)
print("dims", len(dims))
