"""
Pillow ICO 标准做法：source 是大图，sizes 给完整列表
"""
from PIL import Image
from pathlib import Path

SRC = Path("E:/deepseek work/dsh-desktop/icon-source-256.png")
OUT = Path("E:/deepseek work/dsh-desktop/app.ico")
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

img = Image.open(SRC).convert("RGBA")
assert img.size == (256, 256)

# 白底转透明 + 鲸鱼黑色 + 抗锯齿 alpha
def whiten_to_transparent(im):
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r > 220 and g > 220 and b > 220:
                op[x, y] = (0, 0, 0, 0)
            else:
                gray = (r + g + b) / 3
                alpha = int(255 - gray) if gray < 220 else 0
                op[x, y] = (0, 0, 0, alpha)
    return out

img = whiten_to_transparent(img)

# 关键：sizes 参数里包含 source 自身的 256x256
img.save(OUT, format="ICO", sizes=SIZES)

# 验证
import struct
with open(OUT, "rb") as f:
    data = f.read()
reserved, ico_type, count = struct.unpack("<HHH", data[:6])
print(f"ICO: type={ico_type}, count={count}, size={len(data)} bytes")
offset = 6
for i in range(count):
    w, h = data[offset], data[offset+1]
    w = w or 256
    h = h or 256
    bpp = struct.unpack("<H", data[offset+6:offset+8])[0]
    print(f"  entry {i}: {w}x{h} {bpp}bpp")
    offset += 16
