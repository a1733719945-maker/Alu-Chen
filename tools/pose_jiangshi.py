"""跳尸模型整形（Meshy 生成的是 A 字姿势）：
1. 把两条胳膊绕肩膀转到正前方平伸（跳尸的标志动作），按离胳膊中轴的距离、沿胳膊的距离做平滑权重，不撕开衣服
2. 转 180°（glTF 正面朝 +Z，游戏里尸群朝 -Z），脚底放到 y = 0，缩放到 1.9 米高
直接改 GLB 里的顶点、法线、切线（数量不变），写回同一个文件。
用法：python3 tools/pose_jiangshi.py 输入.glb 输出.glb
"""
import json, struct, sys
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())
jl = struct.unpack('<I', data[12:16])[0]
j = json.loads(data[20:20 + jl])
bin0 = 20 + jl + 8
prim = j['meshes'][0]['primitives'][0]
acc = j['accessors']


def view(name):
    a = acc[prim['attributes'][name]]
    bv = j['bufferViews'][a['bufferView']]
    comps = {'VEC3': 3, 'VEC4': 4, 'VEC2': 2}[a['type']]
    stride = bv.get('byteStride', comps * 4)
    off = bin0 + bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    return a, off, stride, comps


def read(name):
    a, off, stride, comps = view(name)
    out = np.zeros((a['count'], comps), dtype=np.float32)
    for i in range(a['count']):
        out[i] = struct.unpack_from('<%df' % comps, data, off + i * stride)
    return out


def write(name, arr):
    a, off, stride, comps = view(name)
    for i in range(a['count']):
        struct.pack_into('<%df' % comps, data, off + i * stride, *arr[i])
    if name == 'POSITION':
        a['min'] = arr.min(0).tolist()
        a['max'] = arr.max(0).tolist()


def rot_between(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = float(np.dot(a, b)); s = np.linalg.norm(v)
    if s < 1e-8:
        return np.eye(3)
    k = v / s
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    ang = np.arctan2(s, c)
    return ang, k


def axis_angle(k, ang):
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


P = read('POSITION'); N = read('NORMAL')
T = read('TANGENT') if 'TANGENT' in prim['attributes'] else None
lo, hi = P[:, 1].min(), P[:, 1].max()
H = hi - lo
h = (P[:, 1] - lo) / H     # 0 脚底 ~ 1 帽顶

for side in (-1, 1):
    # 胳膊上的点：离身体远（|x| 大）、在腰和肩之间
    arm = (P[:, 0] * side > 0.38) & (h > 0.42) & (h < 0.8)
    pts = P[arm]
    c = pts.mean(0)
    u, s, vt = np.linalg.svd(pts - c)
    d = vt[0]
    if d[0] * side < 0:
        d = -d                                  # 从肩膀指向手
    # 肩膀：胳膊中轴上 |x| = 0.2 的地方
    t0 = (0.2 * side - c[0]) / d[0]
    pivot = c + d * t0
    target = np.array([0.1 * side, 0.06, 1.0])     # 往前（+Z，模型正面）、稍稍往里收、微微抬起
    ang, k = rot_between(d, target)
    rel = P - pivot
    along = rel @ d
    perp = np.linalg.norm(rel - np.outer(along, d), axis=1)
    w = smooth(0.02, 0.16, along) * (1 - smooth(0.15, 0.24, perp)) * (P[:, 0] * side > 0.1)
    idx = np.nonzero(w > 1e-4)[0]
    for i in idx:
        R = axis_angle(k, ang * w[i])
        P[i] = pivot + R @ (P[i] - pivot)
        N[i] = R @ N[i]
        if T is not None:
            T[i, :3] = R @ T[i, :3]
    print('side', side, 'pivot', np.round(pivot, 3), 'dir', np.round(d, 2), 'deg', round(float(np.degrees(ang)), 1), 'moved', len(idx))

# 转 180°（绕 Y：x → -x、z → -z），脚底放到 0，缩放到 1.9 米
P[:, 0] *= -1; P[:, 2] *= -1
N[:, 0] *= -1; N[:, 2] *= -1
if T is not None:
    T[:, 0] *= -1; T[:, 2] *= -1
k = 1.9 / H
P[:, 1] -= lo
P *= k
cx, cz = (P[:, 0].min() + P[:, 0].max()) / 2, 0.0
P[:, 0] -= cx
write('POSITION', P); write('NORMAL', N / np.linalg.norm(N, axis=1, keepdims=True))
if T is not None:
    write('TANGENT', T)
js = json.dumps(j, separators=(',', ':')).encode()
js += b' ' * ((4 - len(js) % 4) % 4)
out = bytearray(data[:12]) + struct.pack('<I', len(js)) + b'JSON' + js + data[20 + jl:]
struct.pack_into('<I', out, 8, len(out))
open(dst, 'wb').write(out)
print('写好了', dst, 'min', np.round(P.min(0), 2), 'max', np.round(P.max(0), 2))
