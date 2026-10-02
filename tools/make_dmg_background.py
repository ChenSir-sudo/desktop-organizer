#!/usr/bin/env python3
"""
生成 DMG 安装窗口的背景图。

主流 macOS 安装盘的样子：一块干净的底，中间一个箭头指向「应用程序」。
不放说明文字 —— 拖拽本身就是最直白的引导。
"""
from PIL import Image, ImageDraw
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

W, H = 640, 400
SCALE = 2                      # 2x 出图，Retina 下更细腻

BG_TOP = (238, 242, 250)
BG_BOTTOM = (222, 230, 244)
ARROW = (150, 168, 200)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def main():
    w, h = W * SCALE, H * SCALE
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)

    # 竖直渐变底
    for y in range(h):
        d.line([(0, y), (w, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / (h - 1)))

    # 中间的箭头：一根横杆 + 一个三角头
    cy = h // 2
    shaft_len = 120 * SCALE
    shaft_h = 7 * SCALE
    x0 = (w - shaft_len) // 2 - 10 * SCALE
    x1 = x0 + shaft_len
    d.rounded_rectangle(
        [x0, cy - shaft_h // 2, x1, cy + shaft_h // 2],
        radius=shaft_h // 2,
        fill=ARROW,
    )

    head_w = 26 * SCALE
    head_h = 30 * SCALE
    d.polygon(
        [
            (x1 - 2 * SCALE, cy - head_h // 2),
            (x1 + head_w, cy),
            (x1 - 2 * SCALE, cy + head_h // 2),
        ],
        fill=ARROW,
    )

    # 四角一点柔光，避免大平面显得死板
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-w * 0.2, -h * 0.6, w * 1.2, h * 0.7], fill=70)
    img = Image.composite(Image.new("RGB", (w, h), (255, 255, 255)), img, glow.point(lambda v: v // 3))

    out = os.path.join(ROOT, "Resources", "dmg-background.png")
    img.save(out)
    print("已生成:", out, img.size)


if __name__ == "__main__":
    main()
