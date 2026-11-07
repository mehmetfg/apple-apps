# Ufuk

Bisikletle işe gidip gelen biri için dış dünyayı okuyan iPhone uygulaması. Önce **çıkış saatini** söyler
(sabah 07–09 ve akşam 16–19 penceresinde en kuru an), sonra önümüzdeki 6 saati, aydınlanma ve kararmayı,
tehlikeleri. Giyim Defteri ile kısa koldan uzun kola geçişi havasıyla kaydeder ve gelecek yıl hatırlatır;
kendi yerlerini (park, Kavaklık Parkı, çarşı, eski yer) haftalık hedefle sıralar ve rotayı kaydeder. Öğle
yürüyüşünü ve akşam rotasını önerir. Doğuş, batış ve kararmayı birçok biçimde gösterir. Havayı
kişinin kendi günleriyle karşılaştırır.

Kaynak `~/Documents/projects/apple-apps/ios/ufuk` (vault'ta `_araçlar/ufuk` bağlantıları).
Paket `com.fatihgocgun.ufuk`, widget `com.fatihgocgun.ufuk.widget`, App Group `group.com.fatihgocgun.pdm`.

## Kurulum

```
python3 ios/proje_uret.py      # Xcode projesini üretir (Ufuk + UfukWidgetExtension, PDMBus bağlı)
python3 ikon/ikon.py           # ikonu çizer
zsh telefona-kur.sh            # kablolu iPhone'a derler ve kurar
```

Telefonda ilk açılış: bildirim, konum ve Apple Sağlık izinleri; Ayarlar › Yerler'de ev ve iş;
Ayarlar › PDM Ağı › Vault klasörünü seç (Tekne üretim dakikaları ve olay yazımı için).

## Nasıl karar verir

| Parça | Dosya | Ne yapar |
|---|---|---|
| Tahmin | `Data/OpenMeteo.swift` | ECMWF, ICON, GFS 15 dakikalık tahmini + 122 üyelik topluluk (saatlik ≥0,2 mm oranı) |
| İkinci görüş | `Data/AppleWeather.swift` | WeatherKit saatlik yağış ihtimali ve anlık durum; hata olursa devre dışı |
| Karışım | `OpenMeteo.blend` | topluluk 0,45 · model uyuşması 0,35 · Apple 0,20, var olanlara göre yeniden ağırlıklı; kaynaklar ayrıştıkça güven düşer |
| Radar | `Data/Radar.swift` | RainViewer son iki saat; 7 üstü yakınlaştırmada 7. seviyedeki kutucuk kırpılıp büyütülür |
| Güneş | `Ortak/Shared.swift` `Sun` | NOAA formülü, dakika taraması + ara değer; Open-Meteo ile saniye düzeyinde aynı |
| Çıkış | `Engine/Decision.swift` | pencerede 15 dk adımla her çıkışın riski: en yüksek ihtimal + beklenen mm + hamle + karanlık + plandan uzaklık |
| Giyim | `Engine/Clothing.swift` | bisiklette hissedilen = rüzgâr soğuğu (hız + 0,6×rüzgâr), ıslaksa −2°; içlik ve rüzgârlık eşiği geri bildirimlerden öğrenilir (başlangıç 12° ve 4°, 3 kayıt ağırlığında) |
| Tehlike | `Decision.hazards` | buzlanma, gök gürültüsü, sağanak, sert rüzgâr, sis, dondurucu, karanlıkta gidiş/dönüş |
| Dışarı | `Engine/Places.swift` | öğle: işin çevresinde, kuruysa park/sahil, yağışlıysa kafe/müze; akşam: kararmadan dönülebilecek yerler, gidişi rüzgâra karşı olanlar önde |
| Giyim Defteri | `Engine/Wardrobe.swift` | kısa kol · uzun kol · içlik · mont geçişleri, o anın sıcaklığı/hissedileni/rüzgârı/gün aralığı/gün ışığıyla; önceki yıllarda bugünün −10…+30 gününe düşen en yakın geçiş ipucu olur; tahminde hissedilen o eşiğin altına inerse "eşiğe geldi" |
| Dışarı Planı | `Engine/Outings.swift` | kendi yerlerin + haftalık hedef (hafta pazartesi başlar); sıra: kalan ihtiyaç ÷ kalan gün, yağış (gidiş-45 dk-dönüş), dönüşte kalan ışık, bugün gidildiyse en sona; 150 m içinde ziyaret sayılır (uygulama açılışında ve rota bitince) |
| Rota | `Data/RouteRecorder.swift` | GPS izi (10 m adım, ≤40 m doğruluk), ekran kilitliyken de (arka plan konum + `CLBackgroundActivitySession`); 50 m / 1 dk altı kaydedilmez; geçilen kendi yerler ziyaret olur |
| Ben ve hava | `Engine/Insights.swift` | son 60 gün hava × Sağlık (adım, yürüyüş, bisiklet, uyku) × ruh hâli × Tekne üretimi; iki tarafta ≥5 gün ve fark > 1,5 standart hata ise cümle olur |

## Ekran düzeni (2026-11-03)

Bugün: çıkış saati (büyük, geri sayım, plandan farkı, tehlikeler, şimdiki hava) → önümüzdeki 6 saat
(saat saat hava, sıcaklık, yağış, rüzgâr; karanlık saatler koyu, çıkış saati çerçeveli) → Işık
(aydınlanma = sivil şafak, kararma = sivil alacakaranlık, yaklaşan geri sayımlı) → Bugün dışarı →
yolculuk kartları → öğle → Giyim Defteri satırı → ruh hâli. İçlik önerisi ekranda ve widget'ta yok;
öğrenilen eşik Ben ve hava'nın en altında duruyor. Dışarı: Bu haftanın planı → Rota → radar → öğle → akşam.

Widget'lar (2026-11-04, simgesiz, sade):
- **Bugün** (2026-11-07, küçük/orta/büyük, kilit ekranı): yalnız sıradaki çıkış (gündüz akşam, 19:00'dan sonra
  yarın sabah). Büyük: **yağmursuz aralık** ("Yağmursuz 16:00–18:00", yağış ihtimali <%30, en az 30 dk; en iyi çıkışı
  içeren, yoksa en uzunu), altında "çık 17:30 · 11°" (sıcaklık çıkış saatinin). Pencere çeyrek çeyrek renkli
  çubuk, kuru aralık beyaz çizgiyle, çıkış bisikletle işaretli. Yanda simgeleriyle sıradaki üç güneş saati
  sırayla: batış (büyük), karanlık, doğuş. Kuru aralık yoksa "Yağmursuz aralık yok · en az yağış 18:15 · %45".
  Şimdiki sıcaklık, en yüksek/en düşük ve öteki pencere çıkarıldı.
- **Saatler** (orta/büyük): önümüzdeki 6 (büyükte 12) saat: sıcaklık, yağış çubuğu ve %, rüzgâr;
  karanlık saatler koyu, çıkış saati çerçeveli; yanında "yağış 17:15'te başlıyor/diniyor", en yüksek
  rüzgâr, karanlık. Bugün widget'ının altına konmak için.
- **5 gün** (orta/büyük): yarından itibaren beş gün, ortak ölçekte en düşük–en yüksek çubuğu, yağış %
  (büyükte durum ve mm). Veri Open-Meteo günlük tahmini (`OpenMeteo.daily`, 6 gün).
- **Güneş** aynen. Park/yer satırı ve "karanlıkta dönüş" gibi uyarılar widget'ta yok.

Akşam 21:00 bildirimi: yarın sabah 07–09'da yağış ≥%40 ise başlık "Yarın sabah yağmur bekleniyor · %X",
gövdede başlama saati ve varsa yağmursuz çıkış saati; kuruysa "Sabah 07–09 kuru görünüyor, 07:30'da çık".

Veri `Application Support/Ufuk/`: `wardrobe.json`, `spots.json`, `visits.json`, `routes.json` + `routes/<id>.json`.
Uygulama silinirse bu dosyalar gider; kalıcı iz PDM Ağı olaylarıdır.

## Bildirimler

06:30 sabah kararı (tehlike varsa en başta) · 15:00 kararma saati + 16–19 penceresi · 21:00 yarının
doğuşu ve sabah çıkışının ışığa göre yeri · yolculuktan 15 dk sonra "Nasıldı?" (kilit ekranından üç
düğme) · çıkıştan en çok 3 saat önce yağış girer ya da çekilirse uyarı. Güneş bildirimleri bir hafta
önden kurulur; hava satırları tahminin uzandığı günlere yazılır. Arka planda yenileme
`com.fatihgocgun.ufuk.refresh` (iOS izin verdikçe, en sık 30 dk).

## PDM Ağı

Yazar: `weather.day` (günde bir: yağış, sıcaklık, sabah/akşam ihtimali, içlik, gün uzunluğu,
kararma), `ride.feedback`, `mood.logged`, `clothing.changed`, `place.visited`, `route.recorded`, `app.opened`. Okur: `_bus/events/tekne/*.jsonl`
(`production.session`, Ben ve hava için).

## Durum

- 2026-11-02: kuruldu. Simülatörde sınandı: İstanbul (kuru) ve Köstence (yağmurlu) gerçek verisiyle
  Bugün, Gökyüzü, Dışarı, Ben ve hava; radar; bildirim metinleri; güneş saatleri (İstanbul, Ankara);
  içlik öğrenmesi.
- 2026-11-02 16:43: iPhone 13 Pro Max'e kuruldu (WeatherKit, HealthKit, App Group yetkileriyle). Önceki denemeler
  Apple'ın yeni Program License Agreement'ı yüzünden durmuştu: yeni App ID açılamıyor, kayıtlı
  uygulamalar imzalanabiliyordu. Onay + Xcode'da yeniden giriş sonrası geçti.
- 2026-11-03: çıkış saati öne, 6 saat şeridi, aydınlanma/kararma kartı; içlik geri plana (ekran, widget,
  bildirim); Giyim Defteri; Dışarı Planı; rota kaydı; widget yeniden. Simülatörde İstanbul gerçek verisiyle
  sınandı: Bugün, Giyim Defteri (geçen yıl ipucu, yıllar grafiği, kayıt → `clothing.changed`), Dışarı
  Planı sıralaması, sahte yürüyüşle rota (0,54 km, park kendiliğinden ziyaret, `place.visited` +
  `route.recorded`). iPhone'a kuruldu. Sınanmayan: widget görünümü, telefonda kilitli ekranda rota,
  gerçek yerlerin koordinatları (Dışarı › Bu haftanın planı › ayar düğmesi).
- 2026-11-04: üç widget yeniden (Bugün · Saatler · 5 gün), 21:00 bildirimi yarının sabah yağışıyla.
  Widget görünümleri Mac'te gerçek simülatör anlık görüntüsüyle ekran dışında çizildi; bildirim metni
  simülatörde döküldü (kuru durum). iPhone'a kuruldu. Sınanmayan: telefonda widget eklenmiş hâli, yağmurlu
  sabah için akşam bildiriminin gerçek gelişi.
- Sınanmayan: WeatherKit (imzalı yapı gerekir), Apple Sağlık okuma, widget ve Canlı Etkinlik görünümü,
  arka plan yenilemesi ve ani değişim uyarısı, kilit ekranından geri bildirim.
