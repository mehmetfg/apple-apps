#!/usr/bin/env python3
"""FBS app icon: a ring of dots (one dot is one unit of money) with one full arc, on a soft ground. Writes the three iOS variants."""
import math, pathlib
from PIL import Image, ImageDraw, ImageFont
OUT = pathlib.Path(__file__).resolve().parent.parent / "ios/FBS/Assets.xcassets/AppIcon.appiconset"
S = 2048
SEGS = [("#0E9E78", 34), ("#2F6BFF", 22), ("#7C5CFF", 16), ("#F0A030", 12), ("#F0525A", 8)]

def make(name, ground, colors, empty):
    img = Image.new("RGB", (S, S), ground)
    d = ImageDraw.Draw(img)
    rows, per_row = 5, 74
    total = sum(n for _, n in SEGS)
    seq = []
    for (c, n), col in zip(SEGS, colors):
        seq += [col] * round(n / total * per_row)
    seq += [empty] * (per_row - len(seq))
    gap = 3
    slots = per_row + gap * len(SEGS)
    k = 0
    for i, col in enumerate(seq):
        if i and seq[i - 1] != col:
            k += gap
        a = -math.pi / 2 + 2 * math.pi * (k + 0.5) / slots
        for r in range(rows):
            rad = S * (0.40 - r * 0.042)
            dot = S * 0.0135
            x, y = S / 2 + rad * math.cos(a), S / 2 + rad * math.sin(a)
            d.ellipse([x - dot, y - dot, x + dot, y + dot], fill=col)
        k += 1
    # the lira sign, from the system font
    font = None
    for path in ("/System/Library/Fonts/SFNSRounded.ttf", "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/HelveticaNeue.ttc"):
        try:
            font = ImageFont.truetype(path, int(S * 0.36))
            break
        except OSError:
            continue
    d.text((S / 2, S / 2), "\u20ba", font=font, fill=colors[0], anchor="mm")
    img.resize((1024, 1024), Image.LANCZOS).save(OUT / name)

make("icon-light.png", "#F4F3FA", [c for c, _ in SEGS], "#DDDCE6")
make("icon-dark.png", "#101018", [c for c, _ in SEGS], "#2C2C38")
make("icon-tinted.png", "#000000", ["#FFFFFF", "#CCCCCC", "#AAAAAA", "#888888", "#666666"], "#333333")
print("icons written to", OUT)
