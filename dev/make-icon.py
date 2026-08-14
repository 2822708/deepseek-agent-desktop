"""
将 dsh 官方 favicon.svg 转为多分辨率 .ico (用于 Windows 应用图标)
用户要求黑色小鲸鱼，因此去掉 prefers-color-scheme 媒体查询，强制 fill=#000
"""
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image
import io
import re
from pathlib import Path

SVG = Path("E:/deepseek work/dsh-desktop/icon-source.svg")
OUT_ICO = Path("E:/deepseek work/dsh-desktop/app.ico")
# Windows .ico 推荐尺寸
SIZES = [16, 24, 32, 48, 64, 128, 256]

# 1. 读 SVG，移除 dark mode 媒体查询，强制 fill=#000
svg_text = SVG.read_text(encoding="utf-8")
# 去掉 <style> 块
svg_text = re.sub(r"<style>.*?</style>", "", svg_text, flags=re.DOTALL)
# 强制 path fill 为黑
svg_text = re.sub(r'fill="#000"', '', svg_text)
# 替换 path 上的 fill="#000000" 或没填的——给 path 加 fill="#000"
svg_text = re.sub(r'(<path\b[^>]*?)>', r'\1 fill="#000000">', svg_text)

# 2. svglib 渲染到 ReportLab Drawing
drawing = svg2rlg(io.StringIO(svg_text))
# 3. 渲染到 256x256 PNG（最高分辨率）
buf = io.BytesIO()
renderPM.drawToFile(drawing, buf, fmt="PNG", bg=0xFFFFFF, configPIL=None)
buf.seek(0)
img256 = Image.open(buf).convert("RGBA")
# svglib 输出的 viewBox 是 50x50，renderPM 出的 PNG 大小可能不是 256，要 resize
print(f"raw render size: {img256.size}")
img256 = img256.resize((256, 256), Image.LANCZOS)

# 4. 准备黑底透明前景的图：白底 + 黑色鲸鱼 -> 透明 + 黑色鲸鱼
# 先把白色背景变透明
def to_transparent(img):
    px = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r < 200 and g < 200 and b < 200:  # 深色（鲸鱼）保留
                op[x, y] = (0, 0, 0, a)
            # 白底变透明
    return out

# 4. 生成多尺寸 PNG
images = []
for sz in SIZES:
    img = img256.resize((sz, sz), Image.LANCZOS)
    # 转成透明背景 + 黑色鲸鱼
    img = to_transparent(img)
    images.append(img)
    print(f"  {sz}x{sz} OK")

# 5. 保存为 .ico
images[0].save(
    OUT_ICO,
    format="ICO",
    sizes=[(s, s) for s in SIZES],
    append_images=images[1:],
)
print(f"ICO saved: {OUT_ICO} ({OUT_ICO.stat().st_size} bytes)")
