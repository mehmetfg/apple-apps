#!/usr/bin/env python3
"""Ufuk icon: a dawn sky from deep blue to warm orange, a half sun on the horizon and a road running into it.
Writes the three iOS variants (light, dark, tinted) into the asset catalog.   python3 ikon/ikon.py"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "ios" / "Ufuk" / "Assets.xcassets" / "AppIcon.appiconset"
N = 1024
H = 610   # horizon


def gradient(stops):
    im = Image.new("RGB", (N, N))
    d = ImageDraw.Draw(im)
    for y in range(N):
        t = y / (N - 1)
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if a <= t <= b:
                u = (t - a) / (b - a)
                d.line([(0, y), (N, y)], fill=tuple(int(x + (z - x) * u) for x, z in zip(ca, cb)))
                break
    return im


def draw(sky, sun, ground, road, glow=True):
    im = gradient(sky).convert("RGBA")
    if glow:
        g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([212, H - 300, 812, H + 300], fill=sun + (120,))
        im.alpha_composite(g.filter(ImageFilter.GaussianBlur(110)))
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.pieslice([332, H - 180, 692, H + 180], 180, 360, fill=sun + (255,))
    d.rectangle([0, H, N, N], fill=ground + (255,))
    # the road narrowing into the horizon
    d.polygon([(512 - 12, H), (512 + 12, H), (512 + 300, N), (512 - 300, N)], fill=road + (255,))
    for i in range(5):
        y0 = H + 40 + i * i * 22 + i * 30
        y1 = y0 + 18 + i * 10
        w0 = 3 + (y0 - H) * 0.035
        w1 = 3 + (y1 - H) * 0.035
        if y1 < N:
            d.polygon([(512 - w0, y0), (512 + w0, y0), (512 + w1, y1), (512 - w1, y1)], fill=sun + (255,))
    d.line([(0, H), (N, H)], fill=sun + (255,), width=6)
    im.alpha_composite(layer)
    return im.convert("RGB")


OUT.mkdir(parents=True, exist_ok=True)
draw([(0, (16, 28, 74)), (0.45, (52, 72, 150)), (0.6, (244, 150, 98)), (1, (244, 150, 98))],
     (255, 214, 140), (22, 30, 58), (40, 52, 92)).save(OUT / "ikon-acik.png")
draw([(0, (4, 8, 24)), (0.5, (20, 30, 70)), (0.6, (150, 80, 70)), (1, (150, 80, 70))],
     (255, 196, 120), (8, 10, 22), (24, 30, 52)).save(OUT / "ikon-koyu.png")
draw([(0, (0, 0, 0)), (1, (0, 0, 0))], (255, 255, 255), (0, 0, 0), (60, 60, 60), glow=False).convert("L").save(OUT / "ikon-renkli.png")
print("yazıldı:", OUT)
