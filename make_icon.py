#!/usr/bin/env python3
"""生成 app 图标：画的就是这个 app 算的东西 —— 备兑开仓的到期损益曲线
（斜上升 → 被行权价削平的那一横），亮底深字，和 app 内主题一致。
不用外部素材、不联网，重跑结果逐像素一致。"""
from PIL import Image, ImageDraw
import pathlib

S = 1024
BG      = (247, 247, 249)   # 浅底（与 iOS Form 背景同族）
GRID    = (222, 224, 230)
AXIS    = (150, 154, 165)
LINE    = (10, 122, 255)    # systemBlue
CAP     = (52, 199, 89)     # 封顶段用绿：这段是「已锁定的盈利」
LOSS    = (255, 59, 48)
BE      = (140, 144, 155)

img = Image.new("RGB", (S, S), BG)
d = ImageDraw.Draw(img)

M = 150                      # 留白，iOS 会再切圆角
x0, x1 = M, S - M
y0, y1 = M, S - M

for i in range(1, 4):        # 淡网格
    y = y0 + (y1 - y0) * i / 4
    d.line([(x0, y), (x1, y)], fill=GRID, width=4)
    x = x0 + (x1 - x0) * i / 4
    d.line([(x, y0), (x, y1)], fill=GRID, width=4)

yz = y0 + (y1 - y0) * 0.62   # 零轴
d.line([(x0, yz), (x1, yz)], fill=AXIS, width=6)

xbe = x0 + (x1 - x0) * 0.34  # 保本点
xk  = x0 + (x1 - x0) * 0.62  # 行权价 → 之后封顶
ycap = y0 + (y1 - y0) * 0.20

d.line([(xbe, y0), (xbe, y1)], fill=BE, width=4)          # 保本竖线

W = 30
d.line([(x0, yz + (y1 - yz) * 0.62), (xbe, yz)], fill=LOSS, width=W)   # 亏损段
d.line([(xbe, yz), (xk, ycap)], fill=LINE, width=W)                    # 上升段
d.line([(xk, ycap), (x1, ycap)], fill=CAP, width=W)                    # 封顶段
for p in ((xbe, yz), (xk, ycap)):                                      # 拐点圆头
    d.ellipse([p[0] - W // 2, p[1] - W // 2, p[0] + W // 2, p[1] + W // 2], fill=LINE)

out = pathlib.Path("Resources/icon-1024.png")
img.save(out)
print(f"✅ {out} {img.size[0]}x{img.size[1]}")
