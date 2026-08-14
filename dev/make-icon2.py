"""
从 Edge 渲染的 PNG 生成多分辨率 .ico
"""
from PIL import Image
from pathlib import Path

SRC = Path("E:/deepseek work/dsh-desktop/icon-source-256.png")
OUT = Path("E:/deepseek work/dsh-desktop/app.ico")
SIZES = [16, 24, 32, 48, 64, 128, 256]

img = Image.open(SRC).convert("RGBA")
assert img.size == (256, 256), f"expected 256x256, got {img.size}"

# 把白底变透明（保留黑色鲸鱼）
def whiten_to_transparent(im):
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # 接近白色 -> 透明
            if r > 220 and g > 220 and b > 220:
                op[x, y] = (0, 0, 0, 0)
            else:
                # 鲸鱼部分：保留灰度作为 alpha，让边缘有抗锯齿
                gray = (r + g + b) / 3
                alpha = int(255 - gray) if gray < 220 else 0
                op[x, y] = (0, 0, 0, alpha)
    return out

images = []
for sz in SIZES:
    resized = img.resize((sz, sz), Image.LANCZOS)
    transparent = whiten_to_transparent(resized)
    images.append(transparent)
    print(f"  {sz}x{sz} OK")

# 保存为 .ico
images[0].save(
    OUT,
    format="ICO",
    sizes=[(s, s) for s in SIZES],
    append_images=images[1:],
)
print(f"ICO saved: {OUT} ({OUT.stat().st_size} bytes)")

# 验证：列出 .ico 内所有尺寸
import struct
with open(OUT, "rb") as f:
    data = f.read()
reserved, ico_type, count = struct.unpack("<HHH", data[:6])
print(f"ICO: type={ico_type}, count={count}")
offset = 6
for i in range(count):
    w, h = data[offset], data[offset+1]
    w = w or 256
    h = h or 256
    print(f"  entry {i}: {w}x{h}")
    offset += 16
