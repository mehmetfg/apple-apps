# Önizleme PNG'lerini tek paftada toplar: python3 mac/pafta.py <önek> <çıktı> [ölçek]
import sys, glob
from PIL import Image
onek, cikti = sys.argv[1], sys.argv[2]
olcek = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
dosyalar = sorted(glob.glob(f"onizleme/{onek}*.png"))
resimler = [Image.open(f) for f in dosyalar]
resimler = [r.resize((int(r.width * olcek), int(r.height * olcek))) for r in resimler]
satirlar, satir, gen = [], [], 0
for r in resimler:
    if gen + r.width > 2600 and satir:
        satirlar.append(satir); satir, gen = [], 0
    satir.append(r); gen += r.width
if satir: satirlar.append(satir)
W = max(sum(r.width for r in s) for s in satirlar)
H = sum(max(r.height for r in s) for s in satirlar)
p = Image.new("RGB", (W, H), (60, 60, 60))
y = 0
for s in satirlar:
    x = 0
    for r in s:
        p.paste(r, (x, y)); x += r.width
    y += max(r.height for r in s)
p.save(cikti)
print(cikti, p.size)
