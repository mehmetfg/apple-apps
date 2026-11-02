# Gece

Akşam, yatmadan önce 3–5 dakikalık bir rutin: boyun, bel, diz, sonra uykuya geçiş nefesi.
Kaynak: Kıvılcım kaydı 2026-10-25 13:58 ("gece yatmadan önce… bel ağrısı, boyun ağrısı… 2–5 dakika… video ve animasyon").
Kurulum kararları 2026-10-27 (kullanıcı): ayrı uygulama (Demir'e dokunulmaz), animasyon + video,
yemek kaydı Kıvılcım'dan sesle, rapor haftalık + gece kartı, yatış 23:30.

## Rutin (v2, 2026-10-30: beşliler)

Her gece bir **beşli**: 5 hareket × 1 dk = 5 dk. Bütün beşliler aynı beş duraktan geçer:
1 boyun · 2 omuz-göğüs (ikisi yatak kenarında oturarak) · 3 omurga · 4 kalça-bacak (yerde) · 5 kapanış/nefes.

| Beşli | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| A · AÇ | Boyun esnetme | Göğüs açma | Kedi–inek | Kalça önü (psoas) | Diyafram nefesi |
| B · BÜK | Boyun esnetme | Kürek kemiği sıkıştırma | Çocuk pozu | Dört (piriformis) | Sırtüstü burgu |
| C · ÇEK | Çene içe çekme | Kürek kemiği sıkıştırma | Tek dizi göğse | Havluyla arka bacak | Bacaklar duvarda |

Kaynak 2026-10-30: kullanıcının iki infografiği (10 dk duruş/ağrı rutini); oradaki bütün hareketler + duruş için
çene içe çekme ve kürek kemiği; pelvik tilt ve topuk kaydırma yedek (`slots[].pool`).

Alışkanlık evreleri uygulanan gece sayısıyla (`Habit.swift`): Öğren 1–9 (blok A×3, B×3, C×3) → Ezberle 10–42
(dönüşümlü; her durakta önce "hangisi?" — Göster, Bildim/Bilemedim kaydedilir) → Oturt 43–66 (ses yalnız durak no,
haftalık SRBAI) → Yerleşti (66+ ve SRBAI ≥ 5,5 iki kez üst üste). Çapa (Ayarlar): "Dişlerimi fırçaladıktan sonra".
Dün kaçtıysa ana ekran mini geceyi ister (durak 3 + 5, 2 dk). Ezber sonrası bacak ağırlıklı gün → C (ÇEK).
Son 14 gecede iki kez "Ağrıttı" denen hareket, aynı duraktaki ilk uygun yedekle değişir. Başta ağrı ≥7 → mini.
Kırmızı bayraklar aynı. Referans not: vault `02 - Eudomonia/Beden/Spor/🌙 Gece Beşlileri.md`.

## Animasyon ve video

`ios/Gece/moves.json` tek kaynaktır: yandan görünüş, eklem açıları, anahtar kareler.
`Figure.swift` aynı kinematikle canlı çizer; `MoveVideo.swift` aynı çizimi kare kare MP4'e
yazar (çevrimdışı, döngülü, paylaş/kaydet). Pozları telefona göndermeden denetlemek için:

```bash
python3 veri/preview.py /tmp/gece-onizleme.png
```

## Veri

| Nereye | Ne |
|---|---|
| `_bus/events/gece/<cihaz>.jsonl` | `stretch.session` (set, phase, night_no, streak, anchor, recall, moves[].recalled), `habit.check` (SRBAI), `pain.redflag`, `sleep.logged`, `activity.logged` (biten günler, Sağlık'tan; boş gün gönderilmez), `app.opened` |
| Apple Sağlık | Rutin "esneme" antrenmanı olarak yazılır |
| `_bus/state/body.json` (v2) | `nights_7`, `nights_28` (ağrı önce/sonra, ağrıtan hareketler, kırmızı bayrak, sets, recall, phase, streak), `habit` (son 4 SRBAI), `week` (uyku, adım, km, antrenman dakikası kaynağa göre, öğün sayısı) |

Öteki kaynaklar `_bus/hub.py`'de: Wise Path yol kayıtları (`adapter_wisepath`, `workout.logged`),
Kıvılcım'da geçmiş zamanla söylenen öğün (`meal.logged`, rutin gıdalar `supplement.taken`).
Demir antrenmanları Apple Sağlık'a yazıyorsa `activity.logged.workouts` içinde kaynak adıyla görünür.

## Rapor

`02 - Eudomonia/Beden/_rapor/beden_raporu.py` → `Raporlar/<yyyy>-W<ww> Beden Raporu.md` + `Artifacts/beden-raporu.html`.
Zamanlanmış görev `beden-raporu-haftalik` pazar 20:00: hub → rapor → "## Yorum" (Beden/CLAUDE.md §7: veri, yorum, en fazla iki adım).

## Kurulum

```bash
zsh ~/Documents/projects/apple-apps/ios/gece/telefona-kur.sh
```

Proje `ios/proje_uret.py` ile üretilir (PDMBus bağlanır). İlk açılış: bildirim + Sağlık izni,
sonra Ayarlar › PDM Ağı › Vault klasörünü seç (Personel Data Management). Simgeye basılı tut:
"Gece rutinine başla". Bildirimdeki "Başla" rutini açar, "15 dk sonra" erteler.

## Apple Watch (sonra)

Aynı `moves.json`; durak değişiminde bilek dokunuşu, kapanış nefesinde nabız/HRV (`stretch.session.hr_start/hr_end`),
WatchConnectivity ile telefona. Şema bunu kaldırır, şimdilik yapılmadı.

## Günlük

- 2026-10-27 — Kuruldu. Sınanan: simülatörde bütün akış (izinler, ağrı, 10 adım, sağ/sol aynalı figür,
  gece kartı, ağ olayları geçici vault'a), detayda video üretimi (MP4 1,3 MB); hub ve rapor sahte veriyle.
  Sınanmayan: gerçek Sağlık verisi, bildirim saatinde gelişi.
- 2026-10-28 — Kullanıcı Xcode'a hesabı ekledi; iPhone 13 Pro Max'e kuruldu ve açıldı (09:25). `imza-yenile.sh` listesine eklendi.
- 2026-10-30 — v2 beşliler: 4 yeni hareket (boyun esnetme, göğüs açma, diyafram nefesi, sırtüstü burgu), çene içe çekme
  oturarak; modüller → A·AÇ / B·BÜK / C·ÇEK; alışkanlık evreleri, ezber kipi, SRBAI, çapa; hub `build_nights` + `habit`,
  registry `habit.check`. Sınanan: preview.py pozları, simülatörde ana ekran + ezber akışı (12 sahte gece), hub fonksiyonları
  sahte olayla. iPhone 13 Pro Max'e kuruldu (14:04). Sınanmayan: gerçek gecede SRBAI kartı, Oturt evresi sesi.
