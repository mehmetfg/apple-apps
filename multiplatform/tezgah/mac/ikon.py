# Tezgâh ikonu v3 (PIL): sade — koyu zemin, ince mavi çerçeve, iki tonlu açık kitap.
# Kullanım: python3 ikon.py <çıkış.png> [--tam]   (1024×1024)
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S = 2; N = 1024 * S
cikis = sys.argv[1] if len(sys.argv) > 1 else "ikon.png"
tam = "--tam" in sys.argv
def rgb(h, a=255): return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)
def sc(v): return [x * S for x in v]
def dikey(boyut, ust, alt):
    g = Image.new("RGBA", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(int(ust[i] + (alt[i] - ust[i]) * t) for i in range(4)))
    return g.resize(boyut)
def rr(kutu, r):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).rounded_rectangle(sc(kutu), radius=r * S, fill=255); return m
def katman(maske, ust, alt):
    g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    g.paste(dikey((N, N), ust, alt), (0, 0)); g.putalpha(maske); return g

k = (0, 0, 1024, 1024) if tam else (100, 100, 924, 924)
R = 0 if tam else 185
tuval = Image.new("RGBA", (N, N), (0, 0, 0, 0))
if not tam:
    g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    g.putalpha(rr([k[0], k[1] + 14, k[2], k[3] + 14], R).point(lambda v: v * 110 // 255).filter(ImageFilter.GaussianBlur(16 * S)))
    tuval = Image.alpha_composite(tuval, g)
# çerçeve (mavi) + iç zemin (koyu)
tuval = Image.alpha_composite(tuval, katman(rr(list(k), R), rgb(0x6AA6EE), rgb(0x2F5FA8)))
i = 0 if tam else 14
tuval = Image.alpha_composite(tuval, katman(rr([k[0] + 22, k[1] + 22, k[2] - 22, k[3] - 22], max(R - 22, 0)), rgb(0x1F2A44), rgb(0x0B0F1A)))

K = 1.12
def T(x, y): return (512 + (x - 512) * K, 500 + (y - 520) * K)
def bez(p0, p1, p2, n=40):
    return [((1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t*t*p2[0], (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t*t*p2[1]) for t in [j/n for j in range(n+1)]]
def sayfa(yon, dx=0, dy=0):
    # Swift tarzı y-yukarı koordinat; yon=-1 sol, +1 sağ
    cx = 512
    def X(v): return cx + yon * (v - cx) + dx
    pts = bez((cx, 700), (cx + yon*-1*-110, 790), (cx + yon*290, 720))   # üst kenar: dış uca doğru
    pts = [(cx + yon*(x - cx), y) for x, y in bez((cx, 690), (cx + 130, 770), (cx + 300, 715))]
    pts += [(cx + yon*300, 715 - 330)]
    pts += [(cx + yon*(x - cx), y) for x, y in bez((cx + 300, 385), (cx + 140, 440), (cx, 340))]
    return [((T(x, y + dy)[0]) * S, (1024 - T(x, y + dy)[1]) * S) for x, y in pts]

kitap = Image.new("RGBA", (N, N), (0, 0, 0, 0))
# kapak (altta, daha koyu, hafif taşan)
for yon in (-1, 1):
    m = Image.new("L", (N, N), 0)
    cx = 512
    kapak = [(T(cx + yon*322, 700)), (T(cx + yon*322, 345)), (T(cx + yon*150, 395)), (T(cx, 300)), (T(cx, 690))]
    kapak = [(a * S, (1024 - b) * S) for a, b in kapak]
    ImageDraw.Draw(m).polygon(kapak, fill=255)
    kitap = Image.alpha_composite(kitap, katman(m.filter(ImageFilter.GaussianBlur(1)), rgb(0x2C5799), rgb(0x1D4073)))
# sayfalar: sol koyu, sağ açık (VS Code'daki iki ton gibi)
for yon, ust, alt in ((-1, rgb(0x4A82CC), rgb(0x3866A8)), (1, rgb(0x9CCBF8), rgb(0x5E9DE8))):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).polygon(sayfa(yon, 0, 14), fill=255)
    kitap = Image.alpha_composite(kitap, katman(m, ust, alt))
# omurga çizgisi
d = ImageDraw.Draw(kitap)
d.rectangle(sc([508, 1024 - T(0, 704)[1], 516, 1024 - T(0, 322)[1]]), fill=rgb(0x15294F))
tuval = Image.alpha_composite(tuval, kitap)
tuval.resize((1024, 1024), Image.LANCZOS).save(cikis)
print("ikon:", cikis)
