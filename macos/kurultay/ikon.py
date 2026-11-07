"""Kurultay icon: eight seats in a ring around one centre (the decision). python3 ikon.py"""
import math, pathlib, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter
HERE = pathlib.Path(__file__).parent
S = 1024
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):  # deep night gradient
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(18 + 20 * t), int(24 + 18 * t), int(52 + 30 * t)))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(glow)
g.ellipse([S/2-260, S/2-260, S/2+260, S/2+260], fill=(214, 168, 74, 70))
img.paste(glow.filter(ImageFilter.GaussianBlur(90)), (0, 0), glow.filter(ImageFilter.GaussianBlur(90)))
d = ImageDraw.Draw(img)
colors = ["#10A37F", "#4285F4", "#E8E8E8", "#4D6BFE", "#615CED", "#9AA4B2", "#2D5BFF", "#20808D"]
R, r = 330, 62
pts = []
for i, c in enumerate(colors):
    a = -math.pi / 2 + i * 2 * math.pi / len(colors)
    x, y = S/2 + R * math.cos(a), S/2 + R * math.sin(a)
    pts.append((x, y))
for x, y in pts:  # threads to the centre
    d.line([(x, y), (S/2, S/2)], fill=(214, 168, 74), width=10)
for (x, y), c in zip(pts, colors):
    d.ellipse([x-r, y-r, x+r, y+r], fill=c, outline=(255, 255, 255), width=10)
d.ellipse([S/2-118, S/2-118, S/2+118, S/2+118], fill=(214, 168, 74), outline=(255, 244, 214), width=14)
img.save(HERE / "ios/Kurultay/Assets.xcassets/AppIcon.appiconset/icon.png")
# Mac: rounded square + icns
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([56, 56, S-56, S-56], radius=190, fill=255)
mac = Image.new("RGBA", (S, S), (0, 0, 0, 0))
mac.paste(img.resize((S-112, S-112)), (56, 56), mask.crop((56, 56, S-56, S-56)))
tmp = pathlib.Path(tempfile.mkdtemp()) / "Kurultay.iconset"; tmp.mkdir()
for z in [16, 32, 128, 256, 512]:
    mac.resize((z, z), Image.LANCZOS).save(tmp / f"icon_{z}x{z}.png")
    mac.resize((z*2, z*2), Image.LANCZOS).save(tmp / f"icon_{z}x{z}@2x.png")
subprocess.run(["iconutil", "-c", "icns", str(tmp), "-o", str(HERE / "mac/Resources/Kurultay.icns")], check=True)
print("ok")
