#!/usr/bin/env python3
"""列出 / 下载公开的 Google Drive 文件夹（Quaternius 的 CC0 素材包放在 Google Drive 上）。

用法：
  python3 tools/gdrive.py ls <文件夹id>
  python3 tools/gdrive.py get <文件id> <保存路径>
"""
import json
import re
import sys
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) DouluoHunter-dev"}


def _get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def ls(folder_id):
    """返回 [(id, 名字, 类型, 大小)]"""
    html = _get("https://drive.google.com/drive/folders/%s?usp=sharing" % folder_id).decode("utf-8", "ignore")
    m = re.search(r"window\['_DRIVE_ivd'\] = '(.*?)';", html, re.S)
    if not m:
        return []
    raw = m.group(1)
    raw = re.sub(r"\\x([0-9a-fA-F]{2})", lambda x: chr(int(x.group(1), 16)), raw)
    raw = raw.replace("\\/", "/")
    data = json.loads(raw)
    out = []
    for e in data[0] or []:
        out.append((e[0], e[2], e[3], e[13] if len(e) > 13 else None))
    return out


def get(file_id, path):
    data = _get("https://drive.usercontent.google.com/download?id=%s&export=download&confirm=t" % file_id)
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


if __name__ == "__main__":
    if sys.argv[1] == "ls":
        for fid, name, kind, size in ls(sys.argv[2]):
            print("%s  %-40s %s %s" % (fid, name, "DIR" if kind.endswith("folder") else kind, size or ""))
    elif sys.argv[1] == "get":
        print(get(sys.argv[2], sys.argv[3]))
