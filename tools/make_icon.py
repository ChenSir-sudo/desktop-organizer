#!/usr/bin/env python3
"""
生成「桌面整理」的像素风 app 图标。

思路：
  1. 图案画在 32x32 的经典像素网格上，用 NEAREST 放大 25 倍 -> 硬边像素块
  2. 底衬用 macOS 标准的 squircle 轮廓（824x824 内容区），保证在 Dock 里不违和
  3. 底衬渐变用 Bayer 4x4 有序抖动 —— 像素画做渐变的正确做法，而不是平滑渐变
  4. 输出完整 iconset，并用 iconutil 打包成 .icns

用法：python3 tools/make_icon.py
产物：Resources/AppIcon.icns、Resources/AppIcon.iconset/、docs/screenshots/icon-preview.png
"""
from PIL import Image, ImageDraw, ImageChops
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- 画布参数
CANVAS = 1024          # 最终图标边长
SQUIRCLE = 824         # macOS 图标内容区（Big Sur 规范）
SQUIRCLE_OFF = (CANVAS - SQUIRCLE) // 2
CORNER_N = 3.9         # 超椭圆指数，越大约接近方形

GRID = 32              # 逻辑像素网格（经典像素画尺寸）
BLOCK = 25             # 每个逻辑像素放大成多少真实像素
ART = GRID * BLOCK     # 800

# ---------------------------------------------------------------- 配色
C_OUTLINE  = (22, 30, 68, 255)      # 卡片描边（深蓝而非纯黑，避免割裂感）
C_HI       = (148, 190, 242, 255)   # 玻璃顶部高光
C_HEADER   = (92, 136, 206, 255)    # 标题条
C_HEADER_LO= (58, 92, 152, 255)     # 标题条暗面
C_SEP      = (26, 36, 76, 255)      # 标题条下的分隔线
C_BODY     = (40, 56, 106, 255)     # 内容区
C_BODY_LO  = (33, 46, 90, 255)      # 内容区暗面（底部一条）
C_DOT      = (10, 132, 255, 255)    # 标题条上的主题圆点
C_KNOB     = (132, 170, 224, 255)   # 标题条右侧的小按钮

BG_TOP     = (60, 74, 156, 255)     # 底衬色带渐变：上
BG_BOTTOM  = (42, 53, 116, 255)     # 底衬色带渐变：下
EDGE_LIGHT = (160, 200, 255, 60)    # squircle 内描边

# 沿用 app 里那套主题色
TILE_COLORS = [
    (10, 132, 255, 255),    # 蓝
    (48, 209, 88, 255),     # 绿
    (255, 159, 10, 255),    # 橙
    (255, 55, 95, 255),     # 粉红
    (191, 90, 242, 255),    # 紫
    (100, 210, 255, 255),   # 青
]

# ---------------------------------------------------------------- 工具
def _superellipse_points(size, n):
    r = size / 2.0
    pts = []
    steps = 1024
    for i in range(steps):
        t = 2.0 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2.0 / n), ct) * r + r
        y = math.copysign(abs(st) ** (2.0 / n), st) * r + r
        pts.append((x, y))
    return pts


def squircle_mask(size, n=CORNER_N, supersample=4):
    """Apple 风格 squircle 遮罩：超椭圆 |x|^n + |y|^n = 1。"""
    ss = size * supersample
    mask = Image.new("L", (ss, ss), 0)
    ImageDraw.Draw(mask).polygon(_superellipse_points(ss, n), fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def shade(color, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in color[:3]) + (255,)


def draw_block(d, x, y, w, h, color):
    """带立体感的像素块：上/左提亮，下/右压暗。"""
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)
    d.rectangle([x, y, x + w - 1, y], fill=shade(color, 1.38))                  # 顶面
    d.rectangle([x, y, x, y + h - 1], fill=shade(color, 1.18))                  # 左侧
    d.rectangle([x, y + h - 1, x + w - 1, y + h - 1], fill=shade(color, 0.55))  # 底面
    d.rectangle([x + w - 1, y, x + w - 1, y + h - 1], fill=shade(color, 0.70))  # 右侧


# ---------------------------------------------------------------- 像素图案
def row_span(y, y0, y1, cut, x0, x1):
    """返回该行在阶梯圆角下的左右边界（含端点）。"""
    inset = max(0, cut - (y - y0), cut - (y1 - y))
    return x0 + inset, x1 - inset


def draw_art():
    """32x32：一张玻璃卡片（整理框），细标题条 + 3x2 个整齐排列的文件。"""
    im = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    CARD = (3, 5, 28, 26)          # 留出 3~5 像素边距，不顶到 squircle
    TOP, BOTTOM, CUT = CARD[1], CARD[3], 2

    # ---- 轮廓 ----
    for y in range(TOP, BOTTOM + 1):
        left, right = row_span(y, TOP, BOTTOM, CUT, CARD[0], CARD[2])
        d.rectangle([left, y, right, y], fill=C_OUTLINE)

    def inner(y):
        left, right = row_span(y, TOP, BOTTOM, CUT, CARD[0], CARD[2])
        return left + 1, right - 1

    # ---- 标题条（3 行）+ 顶部高光 ----
    for y in range(6, 9):
        l, r = inner(y)
        d.rectangle([l, y, r, y], fill=C_HEADER)
    l, r = inner(6)
    d.rectangle([l, 6, r, 6], fill=C_HI)
    l, r = inner(8)
    d.rectangle([l, 8, r, 8], fill=C_HEADER_LO)
    l, r = inner(10)
    d.rectangle([l, 10, r, 10], fill=C_SEP)

    # ---- 标题条上的主题圆点与小按钮 ----
    d.rectangle([6, 6, 8, 7], fill=C_DOT)
    d.rectangle([21, 6, 22, 7], fill=C_KNOB)
    d.rectangle([25, 6, 26, 7], fill=C_KNOB)

    # ---- 内容区 ----
    for y in range(11, BOTTOM):
        l, r = inner(y)
        d.rectangle([l, y, r, y], fill=C_BODY)
    l, r = inner(BOTTOM - 1)
    d.rectangle([l, BOTTOM - 1, r, BOTTOM - 1], fill=C_BODY_LO)

    # ---- 3x2 个文件 ----
    AREA = (5, 12, 26, 25)
    cols, rows, tile, gap = 3, 2, 5, 3
    grid_w = cols * tile + (cols - 1) * gap
    grid_h = rows * tile + (rows - 1) * gap
    x0 = AREA[0] + (AREA[2] - AREA[0] + 1 - grid_w) // 2
    y0 = AREA[1] + (AREA[3] - AREA[1] + 1 - grid_h) // 2
    for index in range(cols * rows):
        cx, cy = index % cols, index // cols
        draw_block(
            d,
            x0 + cx * (tile + gap),
            y0 + cy * (tile + gap),
            tile, tile,
            TILE_COLORS[index % len(TILE_COLORS)],
        )

    return im


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def draw_background():
    """色带渐变：像素画做渐变最干净的方式，不引入抖动噪点。"""
    im = Image.new("RGBA", (GRID, GRID), BG_BOTTOM)
    d = ImageDraw.Draw(im)
    bands = 6
    for index in range(bands):
        y0 = index * GRID // bands
        y1 = (index + 1) * GRID // bands - 1
        color = lerp(BG_TOP, BG_BOTTOM, index / (bands - 1))
        d.rectangle([0, y0, GRID - 1, y1], fill=color)
    return im


# ---------------------------------------------------------------- 组装
def compose():
    bg = draw_background().resize((ART, ART), Image.NEAREST)
    art = draw_art().resize((ART, ART), Image.NEAREST)

    outer = squircle_mask(SQUIRCLE)
    inner = squircle_mask(SQUIRCLE - 12)
    mask_full = Image.new("L", (CANVAS, CANVAS), 0)
    mask_full.paste(outer, (SQUIRCLE_OFF, SQUIRCLE_OFF))
    inner_full = Image.new("L", (CANVAS, CANVAS), 0)
    inner_full.paste(inner, (SQUIRCLE_OFF + 6, SQUIRCLE_OFF + 6))
    ring = ImageChops.subtract(mask_full, inner_full)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off = (CANVAS - ART) // 2
    canvas.paste(bg, (off, off), mask_full.crop((off, off, off + ART, off + ART)))
    canvas.paste(Image.new("RGBA", (CANVAS, CANVAS), EDGE_LIGHT), (0, 0), ring)
    canvas.paste(art, (off, off), art)
    return canvas


# ---------------------------------------------------------------- 输出
def main():
    icon = compose()

    iconset = os.path.join(ROOT, "Resources", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    specs = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for name, size in specs:
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))

    icon.save(os.path.join(ROOT, "Resources", "AppIcon-1024.png"))

    icns = os.path.join(ROOT, "Resources", "AppIcon.icns")
    result = subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print("iconutil 失败:", result.stderr, file=sys.stderr)
        return 1
    print("已生成:", icns, os.path.getsize(icns), "bytes")

    make_preview(icon)
    return 0


def make_preview(icon):
    """预览图：大图 + 各尺寸在浅色/深色背景上的实际观感。"""
    sizes = [128, 64, 32, 16]
    W, H = 1040, 460
    sheet = Image.new("RGBA", (W, H), (243, 244, 248, 255))
    d = ImageDraw.Draw(sheet)
    d.rectangle([0, 380, W, H], fill=(22, 24, 32, 255))

    big = icon.resize((300, 300), Image.LANCZOS)
    sheet.paste(big, (40, 40), big)

    x = 400
    for size in sizes:
        small = icon.resize((size, size), Image.LANCZOS)
        sheet.paste(small, (x, 40 + (300 - size) // 2), small)
        sheet.paste(small, (x, 385 + (70 - size) // 2), small)
        d.text((x, 350), f"{size}px", fill=(120, 124, 138, 255))
        x += size + 34

    out = os.path.join(ROOT, "docs", "screenshots", "icon-preview.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    print("预览图:", out)


if __name__ == "__main__":
    sys.exit(main())
