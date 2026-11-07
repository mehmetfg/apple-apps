#!/usr/bin/env python3
"""SBS app icon: a ring of petals (the "where things stand" picture) on a soft ground. Writes the three iOS variants."""
import math, pathlib
from PIL import Image, ImageDraw, ImageFilter
OUT = pathlib.Path(__file__).resolve().parent.parent / "ios/SBS/Assets.xcassets/AppIcon.appiconset"
S = 1024 * 2
PETALS = ["#FF5A5F", "#FF9F43", "#F7C948", "#34C7A1", "#2BB3C0", "#2F6BFF", "#7C5CFF", "#C05CE0"]

def petal(draw, cx, cy, ang, r0, r1, half, fill, outline=None, width=0):
    pts = [(cx + r0 * math.cos(ang), cy + r0 * math.sin(ang))]
    steps = 24
    for i in range(steps + 1):
        a = ang - half + 2 * half * i / steps
        bulge = r1 * (1 + 0.06 * math.sin(math.pi * i / steps))
        pts.append((cx + bulge * math.cos(a), cy + bulge * math.sin(a)))
    draw.polygon(pts, fill=fill, outline=outline)
    if outline and width:
        draw.line(pts + [pts[0]], fill=outline, width=width, joint="curve")

def make(name, ground, colors, outline_only=()):
    img = Image.new("RGB", (S, S), ground)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    n = len(colors)
    for i, c in enumerate(colors):
        ang = -math.pi / 2 + 2 * math.pi * i / n
        if i in outline_only:
            petal(d, S / 2, S / 2, ang, S * 0.10, S * 0.36, math.pi / n * 0.80, c + "40", c, 22)
        else:
            petal(d, S / 2, S / 2, ang, S * 0.10, S * 0.36, math.pi / n * 0.80, c)
    layer = layer.filter(ImageFilter.GaussianBlur(3))
    img.paste(layer, (0, 0), layer)
    d2 = ImageDraw.Draw(img)
    d2.ellipse([S * 0.445, S * 0.445, S * 0.555, S * 0.555], fill=ground)
    img.resize((1024, 1024), Image.LANCZOS).save(OUT / name)

make("icon-light.png", "#F4F3FA", PETALS, outline_only=(1, 6))
make("icon-dark.png", "#101018", PETALS, outline_only=(1, 6))
make("icon-tinted.png", "#000000", ["#FFFFFF", "#BBBBBB", "#FFFFFF", "#DDDDDD", "#FFFFFF", "#CCCCCC", "#FFFFFF", "#AAAAAA"], outline_only=(1, 6))
print("icons written to", OUT)
