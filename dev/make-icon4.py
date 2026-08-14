"""
从已渲好的 RGBA 512x512 PNG 直接出多分辨率 ICO
不需要再处理背景（已经透明）
"""
from PIL import Image
from pathlib import Path
import struct

SRC = Path("E:/deepseek work/dsh-desktop/dsh-transparent-512.png")
OUT = Path("E:/deepseek work/dsh-desktop/app.ico")
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

img = Image.open(SRC).convert("RGBA")
assert img.size == (512, 512), f"expected 512x512, got {img.size}"

# 直接保存为 ICO，Pillow 会从 source 自动 resize
img.save(OUT, format="ICO", sizes=SIZES)

# 验证
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
