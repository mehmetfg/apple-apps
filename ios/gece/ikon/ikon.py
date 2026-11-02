#!/usr/bin/env python3
"""Gece icon: a night-blue square, a warm crescent moon and a soft spine curve under it.
Writes the three iOS variants (light, dark, tinted) into the asset catalog.   python3 ikon/ikon.py"""
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "ios" / "Gece" / "Assets.xcassets" / "AppIcon.appiconset"
N = 1024


def gradient(top, bottom):
    im = Image.new("RGB", (N, N))
    d = ImageDraw.Draw(im)
    for y in range(N):
        t = y / (N - 1)
        d.line([(0, y), (N, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return im


def draw(bg_top, bg_bottom, moon, spine, glow=True):
    im = gradient(bg_top, bg_bottom).convert("RGBA")
    if glow:
        g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([300, 150, 760, 610], fill=moon + (90,))
        im.alpha_composite(g.filter(ImageFilter.GaussianBlur(90)))
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # crescent: a disc minus an offset disc
    d.ellipse([330, 180, 730, 580], fill=moon + (255,))
    d.ellipse([420, 130, 820, 530], fill=(0, 0, 0, 0))
    # a spine lying down: a soft wave of vertebrae
    for i in range(9):
        x = 200 + i * 78
        y = 790 + 28 * math.sin(i / 8 * math.pi * 1.2 - 0.4)
        r = 30 - abs(i - 4) * 2
        d.rounded_rectangle([x - r, y - r * 0.7, x + r, y + r * 0.7], radius=r * 0.5, fill=spine + (255,))
    im.alpha_composite(layer)
    return im.convert("RGB")


def main():
    amber, cream = (244, 184, 107), (242, 232, 214)
    draw((24, 30, 58), (10, 12, 24), amber, cream).save(OUT / "ikon-acik.png")
    draw((8, 10, 20), (3, 4, 8), amber, (200, 190, 175)).save(OUT / "ikon-koyu.png")
    t = draw((0, 0, 0), (0, 0, 0), (255, 255, 255), (200, 200, 200), glow=False).convert("L")
    t.save(OUT / "ikon-renkli.png")
    print("yazıldı:", OUT)


if __name__ == "__main__":
    main()
