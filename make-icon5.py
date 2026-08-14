"""
从 dsh-fish-1024.png 出多分辨率 ICO
源是 1024x1024，path 居中但 viewBox 是 23.16x17.04
需要裁掉透明区域，让鱼居中
"""
from PIL import Image
from pathlib import Path
import struct

SRC = Path("E:/deepseek work/dsh-desktop/dsh-fish-1024.png")
OUT = Path("E:/deepseek work/dsh-desktop/app.ico")
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

img = Image.open(SRC).convert("RGBA")
print(f"Source: {img.size}")

# 找非透明区域的边界（裁掉空白让鱼更大）
bbox = img.getbbox()
if bbox:
    print(f"Non-transparent bbox: {bbox}")
    img = img.crop(bbox)
    print(f"After crop: {img.size}")

# 居中放置到正方形画布
w, h = img.size
side = max(w, h)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(img, ((side - w) // 2, (side - h) // 2))
img = square
print(f"After square: {img.size}")

# 直接保存 ICO
img.save(OUT, format="ICO", sizes=SIZES)

with open(OUT, "rb") as f:
    data = f.read()
_, ico_type, count = struct.unpack("<HHH", data[:6])
print(f"ICO: type={ico_type}, count={count}, size={len(data)} bytes")
offset = 6
for i in range(count):
    w_, h_ = data[offset], data[offset+1]
    w_ = w_ or 256
    h_ = h_ or 256
    print(f"  entry {i}: {w_}x{h_}")
    offset += 16
