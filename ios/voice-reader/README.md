# Voice Reader (eski adı Okur) — sesli okuyucu (iPhone)

Voice Dream Reader'ın işlevini, kullanım biçimini ve kararlılığını kendi kodumuzla yeniden kuran iPhone uygulaması.
Ses motoru Teoria'nın `ReaderVoice`'undan gelir (paragraf → ses tamponu → kendi AVAudioEngine'imiz; imleç gerçekten
duyulan kelimeyi izler, Bluetooth gecikmesi dahil). Voice Dream'in kodu, adı, ikonu, görselleri ve lisanslı sesleri
(Will, Heather) kullanılmaz; sesler iPhone'un kendi sesleridir (Premium / Gelişmiş / Kişisel Ses).

İşlev envanteri, Mac'teki Voice Dream Reader 2.0.2'nin ekran dosyalarından **REA** ile çıkarıldı
(`rea decode-interface-builder`): ana menü, Görsel Ayarlar, Ses Ayarları, kütüphane sütunları.

## Faz 1 (2026-10-19) — yapılan

- **Kütüphane:** başlık, yazar, biçim rozeti, ilerleme, kalan dinleme süresi; sırala (son açılan, eklenme, başlık, yazar,
  süre, ilerleme), süz (tümü, okunmamış, devam eden, biten, etiketli), ara, klasörler, renk etiketi, yeniden adlandır,
  başa sar, sil. Çalarken alt kısımda mini oynatıcı; yeniden açılışta son belge mini oynatıcıda bekler.
- **Ekleme:** Dosyalar (çoklu seçim), pano, başka uygulamadan "Okur'da aç"/AirDrop, **bırakma klasörü**
  (Dosyalar › iPhone'umda › Okur'a bırakılan dosya açılışta kütüphaneye girer).
- **Biçimler:** PDF (satırlar paragrafa birleştirilir, sayfa numaraları atılır, anahat → başlıklar, sayfalar),
  EPUB 2/3 (OPF, spine, nav/NCX içindekiler), DOCX (başlık stilleri), HTML, RTF, TXT (UTF-8/16, Windows-1254), Markdown.
  ZIP okuyucu ve HTML→metin dönüştürücü kendi kodumuz (WebKit'siz, ana iş parçacığı dışında).
- **Okuyucu:** tek sütun kayan metin; okunan kelime ve cümle renkle işaretli, metin sesle kendiliğinden kayar; elle
  kaydırınca izleme durur, "Konuşma imlecine git" döner. Kelimeye dokun → oradan okur. Seçim menüsü: Buradan oku,
  İşaretle (sarı/mavi/kırmızı/yeşil), Not ekle, Yer imi. Ara (Türkçe, aksan duyarsız), içindekiler / yer imleri /
  işaretler paneli, sayfaya ve yüzdeye git, işaretleri Markdown olarak dışa aktar.
- **Ses:** hız 0,5×–3,5× (belgeye özel ya da genel; kelime/dakika ölçülen hızdan), dile göre ses seçimi + önizleme,
  ton, gezinme birimi (cümle, paragraf, sayfa, bölüm, yer imi, işaret, 15/30 sn), uyku zamanlayıcısı (dakika ya da
  bölüm sonu), belge sonunda dur / sonrakine geç / tekrarla, cümle başından başla, web/e-posta adreslerini sadeleştir,
  metin içi kaynak göstermelerini atla (sayfada kalır, sesle okunmaz). Kilit ekranı ve kulaklık tuşları; ⏮ ⏭ seçili
  birimle gider; kilit ekranında ilerleme çubuğu sürüklenebilir. Arama, Siri, Bluetooth değişimi, kulaklık çıkarma.
- **Görünüm:** 8 yazı tipi, boyut, satır ve harf aralığı, 6 tema (Sistem, Beyaz, Sepya, Gri, Koyu, Siyah), kelime ve
  cümle vurgusu aç/kapa + renkleri, imleç konumu (üst/orta), odak kipi.

## Faz 2–3 — sırada

Kamerayla tarama (OCR), web makalesi, telaffuz sözlüğü (`SpokenText`'in eşleme yapısı hazır), MP3'e dışa aktarma,
iCloud eşitleme, Dropbox / Google Drive, Mac sürümü. Ekran düzeni kullanıcının Voice Dream ekran görüntüleriyle
birebir hizalanacak.

## Kurulum

```
zsh telefona-kur.sh          # kablolu ya da ağdaki eşleşmiş iPhone'a Release derler, kurar, açar
```

Simülatör: `xcodebuild -project ios/Okur.xcodeproj -scheme Okur -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`.

## Dosyalar

| Klasör | İçerik |
|---|---|
| `ios/Okur/Model` | `Records` (belge, yer imi, işaret, başlık), `LibraryStore` (Application Support/Okur), `Settings` |
| `ios/Okur/Import` | `ZipArchive`, `MarkupText` (HTML→paragraf), `DocumentImporter` (biçimler, PDF yeniden akış) |
| `ios/Okur/Speech` | `SpeechPlayer` (motor, birimler, uyku, kilit ekranı), `SpokenText` (söylenen ↔ sayfa eşlemesi), `Voices` |
| `ios/Okur/Views` | `LibraryScreen`, `ReaderScreen` + `PlayerPanel`, `ReaderTextView` (UIKit, TextKit 1), `Panels` |

## Sınanan / sınanmayan (2026-10-19)

Sınanan: simülatör derlemesi; simülatörde Hızlı Başlangıç ve Kıymet (EPUB) okuma, kelime + cümle vurgusu, içindekilerden
atlama, bırakma klasörüyle EPUB ve PDF ekleme; Mac test düzeneğinde gerçek dosyalarla içe aktarma (Kıymet EPUB 38 başlık,
Klasik Mantık DOCX 599 başlık, rehber.html 58 başlık, Camus PDF 23 sayfa, CLAUDE.md), söylenen metin eşlemesi.
iPhone 13 Pro Max'e kuruldu (telefon kilitli olduğu için açılmadı).
Sınanmayan: telefonda ses ve kilit ekranı, Bluetooth, uyku zamanlayıcısı, seçim menüsü, Dosyalar'dan ekleme, harf
aralığı açık başlıklı PDF'ler (o PDF'lerde metin dağınık çıkıyor; PDFKit'in metniyle ilgili).

## 2026-10-20 — ses, müzik, kararlılık, eşitleme

- **Kalınlık:** Voice Reader seslerinde ses başına "Kalınlık" sürgüsü (−3 … +2 ton, yarım ton adım; formant korunur).
  Yelda Kalın artık varsayılan üç ton kalın (önce iki). Ses seçiminde ve Ses ayarlarında.
- **Bozulmasız ses düzeyi:** seviye katı her örneği `tanh` ile yuvarlıyordu (ölçülen bozulma −31 dB ≈ %3); yerine düz
  kazanç (konuşan kısımlar −19 dBFS) + 4 ms ileri bakışlı sınırlayıcı (−1,5 dBFS). Her sese 75 Hz alçak kesici.
  Ses yükseltme artık sınırlayıcıya +12 dB düz kazanç değil, sıkıştırıcı (eşik yükseltmeyi izler) + hızlı sınırlayıcı.
- **Müzik (Spotify vb.):** Duraklat'ta motor durur, oturum `notifyOthersOnDeactivation` ile bırakılır: iOS kısmayı anında
  kaldırır, müzik basıldığı anda öne çıkar. Tek "Arka plan müziği" sürgüsü (0–100): Spotify'ın sesini başka uygulama
  değiştiremez, oran okuma tarafından kurulur — 0–30 iOS müziği kısar ve okuma 0…+14 dB (en solda müzik hafif bir fon), 30–100 kısma yok ve okuma
  0…−18 dB (`SpeechPlayer.balanceDB`). Tını'ya dokunulmaz.
- **Kitap açılışı:** okuyucu, görünüm gerçek boyutunu alana dek metni gizler ve kaldığın yere animasyonsuz atlar; uzak atlamalarda kayarak gitmez (`ReaderTextView.pendingScroll`). Simülatörde Kıymet %14'te 0,3 sn'de yerinde açıldı.
- **Ayarlar:** kütüphanenin sol üstündeki dişli: Görünüm, Ses seçimi, Ses ve müzik, iCloud durumu + Şimdi eşitle.
- **Performans:** duraklatınca motor ve saniyede 25'lik zamanlayıcı durur; perde izleyici (YIN) vDSP ile ~10× hızlı
  (sonuç %99,97 aynı); dil tanıyıcı yeniden kullanılır; kütüphane kaydı arka planda.
- **Eşitleme:** `State/<cihaz>.json` artık uzunluk ve başlık da yazar. Mac'te PDM Ağı `adapter_voicereader`
  (`_bus/hub.py`) işaretleri ve kaldığın yeri `reading.json`'a taşır.
- **Düğme:** ileri/geri `goforward`/`gobackward` kapalı halkası (15/30 sn rakamlı); birim simgesi ortada.

Sınanan: simülatör derlemesi, DSP Mac'te gerçek Yelda kaydıyla, hub köprüsü sentetik iCloud verisiyle, mini oynatıcı
görünümü. 08:45'te telefona kuruldu (düğme düzeltmesinden önceki yapı). Sınanmayan: telefonda kulakla ses, Tını ile
duraklatma (Tını henüz kurulmadı), iCloud klasörünün Mac'te belirmesi (telefonda eşitleme ilk kez çalışacak).

## 2026-10-20 (öğleden önce) — görünüm, üst çubuk, vault kopyası, akıcı ayarlar

- **Görünüm:** Açık / Koyu / Otomatik (Ayarlar ve Görünüm ayarları); uygulama renkleri iki kipte de (`Palette` dinamik renk).
- **Okuyucu üst çubuğu** (Voice Dream düzeni): solda Kütüphane · İçindekiler · Ses ayarları · kutulu "diğer" menüsü
  (müzik, uyku, ara, git, dışa aktar); sağda Ses · Aa · Yer imi; altında ◀◀ başlık ▶▶. Konuşulan kelime sarı işaret,
  siyah yazı (eski kullanıcıda bir kez sarıya alındı).
- **Çalma işareti** yalnız Son dinlenenler'de ve klasörün içinde; klasör kutusunda ve mini oynatıcıda yok.
- **Vault kopyası** (`Model/VaultMirror.swift`): Ayarlar › PDM vault'ta "Personel Data Management" klasörü bir kez
  seçilir; kaldığın yer, işaretler, notlar, yer imleri ve belge listesi `_araçlar/voice-reader/durum/` altına da yazılır
  (State/, Events/, Library/<id>.json). İlk bağlanışta var olan bütün işaretler de yazılır. PDM hub önce buradan okur.
  Uygulamanın kendi iCloud kapsayıcısı Mac'te belirmediği için (macOS onu ancak Mac'te bir uygulama kullanınca açıyor).
- **Akıcı ayarlar:** cihaz sesleri listesi önbellekte (her çizimde `speechVoices()` taranıyordu); ayar ekranlarından
  gelen değişiklikler 180 ms toplanıp bir kez uygulanır, sürgü sürüklerken okuma her adımda baştan başlamaz.

## 2026-10-20 (öğleden sonra) — Stüdyo sesi: Mac'te büyük modelle önceden seslendirme

Telefonda anında çalışan modeller (Ema, Supertonic) insan sesine yetişemiyor; insan sesine yakın açık modeller
(0,5–2 milyar parametre) iPhone'da gerçek zamanlı çalışmıyor. Yol: kitabı Mac seslendirir, Voice Reader hazır sesi çalar.

- **Model:** VoxCPM2 (OpenBMB, Apache-2.0, 2 milyar parametre, Türkçe resmî). Kurulum `~/.local/share/insan-ses/vox`
  (uv, Python 3.11; model `~/.cache/huggingface`, 4,6 GB). Ses bir kez tarifle tasarlandı ("warm, deep, mature male
  audiobook narrator") ve kullanıcı onayladı (`~/.local/share/insan-ses/deneme/vox-narrator.wav`); her parça bu kayıttan
  klonlanır, böylece kitap boyunca aynı ses. Gerçek bir kişinin sesi kopyalanmadı.
- **Mac:** `studio/studio.py <metin.md> <çıktı.vrstudio> --title … --author …` → paket: `book.json` (metin, başlıklar,
  parçalar, kelime zamanları) + `audio/NNNN.m4a`. Parça = bir ya da birkaç cümle (≤260 karakter). Her parça Whisper
  large-v3-turbo ile dinlenir (harf harf karşılaştırma, rakamlar yazıya çevrilir); %92'nin altındaysa yeniden üretilir
  (en çok 3). Kelime zamanları da buradan. "◆ Durak … Bir nefes düşün." sonrasında 4 sn sessizlik. Kaldığı yerden sürer.
  M1 Max'te üretim aşağı yukarı sesin süresi kadar (yedi saatlik kitap ≈ bir gece).
- **Telefona:** `zsh studio/telefona-gonder.sh <paket>` (devicectl ile uygulamanın Documents klasörüne). Uygulama öne
  gelince paketi kütüphaneye alır; bütün ses dosyaları gelmeden almaz; aynı kitap yeniden gelirse sesi değişir.
- **Uygulama:** `Speech/StudioPack.swift`; sesi **Anlatıcı** (`vr.studio`), yalnız paketi olan kitapta Ses seçiminde
  "Stüdyo" bölümünde. Hız 0,5–3,5× aynı WSOLA ile (perde korunur), kelime imleci paketteki zamanlarla; kelimeye
  dokununca o kelimeden başlar. Paketin ulaşmadığı yeri ya da eksik dosyayı Ema Tok okur, okuma durmaz.
  Sınama kancası: `-playtest <belge id>` (20 sn okur, `Library/play-test.txt`).

İlk deneme: Bir Yöne › Felsefe 01 › Üçüncü Gün · Leibniz (4.437 kelime, 198 parça). Sınanan: VoxCPM2 Türkçe örneklerde
Whisper'la kelime hatası yok; simülatörde paketin içe alınması, Felsefe klasörü, Anlatıcı sesiyle çalma ve kelime
imleci; devicectl ile klasör aktarımı telefonda. Sınanmayan: telefonda kulakla dinleme, kilit ekranı, hızlı dinlemede
(3×) stüdyo sesinin anlaşılırlığı.

## 2026-10-20 (akşamüstü) — hızda cızırtısız Ema, müzik arası

- **Cızırtının kaynağı ölçüldü:** hızlandırma değil, ses yükseltme katıydı. Müzik sürgüsü 0'dayken okuma +14 dB
  isteniyordu ve bu, canlı zincirde düz kazanç olarak hızlı bir tepe sınırlayıcıya veriliyordu: örneklerin %23,6'sı
  3 dB'den fazla kırpılıyordu (Python benzetimi, 14 Ema cümlesi, 3×). Hızlı dinlemede aralar kısaldığı için daha çok
  duyuluyordu.
- **Yeni:** Voice Reader seslerinde (Ema, Supertonic, Apple tabanlı profiller, Anlatıcı) yükseltme artık her parça
  üretilirken yapılıyor: 10 ms ileriyi gören sıkıştırıcı (−10 dBFS, 2:1) + 8 ms ileri bakışlı sınırlayıcı
  (`Level.apply(_:boost:)`, `Compressor`). Canlı zincir bu seslere kazanç vermez, yalnız sistem seslerine. Kırpma
  kaynaklı bozulma −15,6 → −21 dB. Temiz yükseltmenin tavanı ölçüldü: konuşma ≈ −14 dBFS RMS (her ses titreşiminin
  tepesi tavana değiyor; ötesi kırpmadır). Faz döndürücü yalnız ~1 dB kazandırdı, eklenmedi.
- **Sıra:** önce hızlandırma (WSOLA), sonra perde (PSOLA). 2,5×'te Whisper'ın doğru duyduğu harfler %92,7 → %97,4,
  en kötü cümle %46,9 → %94,0. 3×'te ikisi aynı (~%80); 3,5×'te Whisper da güvenilir değil.
- **Parça uçları:** her parçaya 3 ms açılış/kapanış (art arda kuyruklanan parçaların birleşiminde tık olmasın).
- **Müzik arası** (Ses ayarları › Dinlenme): 3–15 dakikada bir, 30 sn–2 dk. Dinleme süresi dolunca okuma bir cümlenin
  başında durur, iOS'un müziği kısması kaldırılır (oturum kapatılıp kısmasız açılır, motor sessizlikte çalışmayı sürdürür,
  böylece arka planda uygulama uyumaz), ara bitince o cümleden sürer. Ara sırasında oynat → hemen sürer. Oynatıcıda
  "Müzik arası · 0:25".

Sınanan: Mac'te aynı Swift DSP kodu + Whisper ile ölçüm; simülatörde müzik arası (12 sn dinleme, 8 sn ara, cümle
başından sürme, ikinci ara) ve Anlatıcı'dan Ema'ya geçiş; telefona kuruldu. Sınanmayan: telefonda kulakla cızırtı,
Spotify ile müzik arasında kısmanın gerçekten kalkması, ekran kilitliyken aranın bitişi.

## 2026-10-21 — Voice Dream'in Yelda ayarı: 330 · 100 · 50

İstek: Voice Dream'deki Yelda'nın tonu ve kararlılığı Voice Reader'da birebir (ekran kaydı: Hız 330, Ses Miktarı 100, Kalınlık 50); sonra aynısı bir erkek sesiyle.

**Ölçüm (kayıttan, Mac'te aynı metinle):** Voice Dream'deki ses, iOS'un sade (compact) Yelda'sının `pitchMultiplier 0,5` ile hiç işlenmeden çalınmasıdır. Perde: kayıt 157 Hz (p10 139, p90 173) ↔ Mac Yelda 0,5 156 Hz (139/173); Yelda 1,0 = 208 Hz. Hız: kayıtta 330 kelime/dk = saniyede 39,35 harf ↔ `rate 0,81` = 39,22. Apple'ın Türkçe motoru (Yelda ve Cem) hızı basamaklarla değiştirir (0,79–0,83 tek basamak); tablo `SpeechPlayer.steps`, her hız en yakın basamağın ortasından çalınır. 1× = 120 kelime/dk (Voice Dream'in sayışı, ≈7 harf bir kelime).

**Kararsızlığın sebebi (bulundu, onarıldı):** sistem sesi 255 örneklik (11,6 ms) parçalarla gelir; `prepare()` her parçada örnekleme dönüştürücüsünü sıfırlıyordu → saniyede 86 kopukluk, örneklerin %6,3'ü yutuluyor, 8 kHz üstünde 6 kat enerji (pürüz). Artık dönüştürücü yalnız yeni bir cümle grubunun başında sıfırlanır. Sistem sesi ek yükseltme yokken sınırlayıcıdan da geçmez (tepe 0,86).

**Arayüz:** Ses ayarları'nda sistem sesi seçiliyken Voice Dream düzeninde üç kart: Hız (60–430, 5'er), Ses Miktarı (0–100), Kalınlık (50–200, 5'er); her kartta uçlarda aralık, altta değer ve −|+. Ses miktarı ve kalınlık her sese ayrı saklanır (`a.tune`). "Voice Dream ayarı" bölümü: **Yelda 330 · 100 · 50** ve **Cem (erkek) 330 · 100 · 85** (Cem kendi 120 Hz'inden 110 Hz'e). Hız sayfası ve okuyucu çubuğu sistem sesinde kelime/dk gösterir. Eski genel "Ton" sürgüsü kalktı.

Sınanan: Mac'te ölçüm (perde, hız, dönüştürücü), simülatör derlemesi; 09:22'de iPhone 13 Pro Max'e kuruldu ve açıldı. Sınanmayan: telefonda kulakla dinleme, kartların görünümü. Yedek: `_yedek-20261021-yelda/`.

### 2026-10-21 (devam) — Düzlük; Cem

Kullanıcı: "tam istediğim gibi oldu; Cem seçilemiyor; aynı kararlılığı Cem ve diğerlerinde de istiyorum — tek düze, kararlı vurgular odaklanmamı kolaylaştırıyor, inişli çıkışlı ses dikkatimi sese çekiyor."

- **Cem seçilemiyordu çünkü telefonda yüklü değil.** Telefonda tek Türkçe ses var: `com.apple.voice.super-compact.tr-TR.Yelda` (uygulama artık açılışta `Library/voices.txt` yazar). Cem, iPhone Ayarlar › Erişilebilirlik › Seslendirilen İçerik › Sesler › Türkçe'den indirilmeli; düğme eksikse bunu söyler.
- **Tonlama ölçüsü** (perdenin p10–p90 aralığı, yarım ton): VD kaydı 3,8 · Yelda 4,1 · Cem 5,4–5,7. Apple'ın SSML `prosody range`'i Türkçe seste hiçbir şey değiştirmiyor (dört değerde birebir aynı ses).
- **Düzlük** (her sese ayrı, 0–50 %): `PitchShift.flatten` her periyodu parçanın orta perdesine doğru çeker (PSOLA, formant ve süre korunur; ±25 ms yumuşatma). Cem %10 → 3,8 yarım ton (Yelda düzeyi); 8 kHz üstü enerji artmadı (0,029 → 0,027). Sistem sesinde Düzlük açıksa ses canlı akış yerine bellekte üretilir (aynı hız basamağı, perde, ses düzeyi), düzleştirilir ve kuyruğa girer; Voice Reader seslerinde (Ema…) render zincirinin sonunda uygulanır.
- Hazır ayar Cem: 330 · 100 · 85 · düz %10.

Sınanan: Mac'te ölçüm, simülatör derlemesi, 09:34'te telefona kuruldu. Sınanmayan: telefonda Düzlük'ün kulakla dinlenmesi (Cem yüklü değil).

### 2026-10-21 (öğle) — Ema hızda çatlamıyor; Derin düz; Siri/gelişmiş sesler

- **Ölçüm düzeneği:** `-voicedump` açılış bayrağı (`Speech/VoiceDump.swift`) simülatörde uygulamanın kendi motoruyla sabit bir paragrafı seslendirir (`VR_SPEED`, `VR_MODEL`, `VR_DUMP="düzlük:sakinlik;…"`, `VR_NOPITCH`, `VR_PFIRST`, `VR_ONLY_EMA`, `VR_TAG`); Mac'te pyin (iniş çıkış, >1 / >2 yarım ton sıçrama) + parçalı Whisper.
- **Ema'nın çatlaması:** hızın tamamı WSOLA'dan gelince PSOLA sıkışmış periyotları yanlış okuyordu (−4 yerine −2 yarım ton, sıçrama %4, Whisper %49). Artık model hızın 1,5'ini kendisi alır, WSOLA kalanı (`emaModelSpeed = 1.5`): perde doğru, sıçrama %3,3, Whisper %80. 1,3 / 1,7 / perde önce: daha kötü.
- **Düzlük sinir ağı seslerinde = model sakinliği** (başlangıç gürültüsü × (1 − düzlük), `NeuralAudio.temperature`). Sonradan PSOLA ile daraltma Ema'yı çatlatıyordu (%0,88 kopma). Derin %50: 6,8 → 3,6 yarım ton, kopma yok, Whisper aynı. Apple seslerinde Düzlük PSOLA ile kalır (Cem'de kopma 0,04 → 0).
- Hazır ayarlar: Yelda · Cem · **Derin (330 · düz %50)** · **Ema Tok (330)**. Düzlük 0–70 %.
- **Siri sesleri** uygulamalara açık değil. **Gelişmiş sesler** daha dalgalı (Yelda 4,1 → 4,4 yarım ton, sıçrama %1,8 → %3,8; Cem 5,4 → 5,7, %4,0 → %5,6): sade sürüm önerilir; ikisi yüklüyse uygulama sadeyi seçer.
- İnternet: hazır bir "tonlama düzlüğü" düğmesi olan Türkçe açık model bulunmadı; aynı yöntem (ortancadan sapmayı çarpanla küçültme) soundgen'de `multProsody`. Piper Türkçe Cem (high) kapılı (koşul onayı gerekir), Okur TTS (ahakan) tek ses.

Sınanan: simülatör ölçümleri, 09:56'da telefona kuruldu. Sınanmayan: telefonda kulakla.

## 2026-10-22 — Voice Dream düzeni: tek satır işareti, düz çubuklar, popover ayarlar, tek yerde ayar

Ekran kaydından ölçülerek (piksel örnekleme): sayfa `#F0F0F0`, çubuklar `#F6F6F6` + `#A0A0A0` ince çizgi, okunan satır
bandı saf beyaz ve kenardan kenara, kelime işareti saf sarı `#FFFF00`, simgeler lacivert `#003D61`, ilerleme `#006FB4`,
oynat düğmesi `#FF3601`.

- **Okunan satır = tek satır.** Cümle arka planı (birkaç satırı boyayan, satır aralığında boşluk bırakan) kalktı. Satır
  bandı ve kelime işareti artık metnin altında duran iki düz görünüm (`ReaderTextView`): band tek satırın yüksekliğinde ve
  ekranın iki kenarına uzanıyor, kelime işareti onun içinde geziyor; ikisi aynı karede, aynı satırda hareket eder.
  Metin deposuna dokunulmaz → kelime başına yeniden yerleşim yok (açık temada metin rengi bile değişmez).
- **Akıcılık.** Oynatıcı kelime değişince `onSpokenChange` ile doğrudan sayfayı boyar; kelime başına hiçbir SwiftUI görünümü
  yeniden hesaplanmaz (eskiden `ReaderScreen` + metin görünümü her kelimede yeniden çiziliyordu). Alt çubukta yalnız süre
  satırı ve % satırı kelimeyi izler. Sayfa bir kitap gibi akar: band satır satır iner, alt sınıra (≈%67) gelince sayfa bir kez
  0,42 sn yumuşak kayar ve band seçilen yüksekliğe (üstte/ortada) döner; parmakla dokunmak kaymayı hemen keser. Satır
  konumu için artık her kelimede metni baştan yerleştirmek yok (yalnız atlamalarda).
- **Düz üst/alt çubuk** (Voice Dream): üstte simgeler + ◀◀ başlık ▶▶, altta içindekiler · geri · oynat · ileri · ara,
  süre – ilerleme – kalan, % · bölüm · gezinme birimi. Cam panel, soluklaştırma gradyanı, hız/birim hapları kalktı.
- **Popover ayarlar:** hoparlör → *Ses Ayarları*, Aa → *Görsel Ayarlar*, liste → *Konumlar*; hepsi simgesinden açılır,
  içinde alt sayfalar (Dil, Ses, Gelişmiş…) aynı popover'da kayar. Kütüphanenin dişlisi aynı iki paneli açar.
- **Renk tek yerde:** önceden üç üst üste ayar vardı (sayfa teması, uygulama rengi, açık/koyu). Şimdi: *Görsel Ayarlar ›
  Renkler* (Sistemi izle ya da Açık · Sepya · Koyu · Siyah; sayfa + çubuklar + satır bandı birlikte) ve *Renk Ayarları*
  (vurgu rengi: 6 hazır + istediğin renk; varsayılan lacivert). Konuşma imleci (kelime/satır rengi, satırın durduğu yer,
  odak kipi) canlı önizlemeyle *Konuşma İmleci* sayfasında.
- **Ses tek yerde:** hız yalnız *Ses Ayarları*'ndaki Konuşma Hızı kartında (eskiden dört yerde: hap, hız sayfası, kart,
  ses ayarı). *Dil* varsayılan Türkçe; İngilizce ve öteki diller dokunulmadıkça listelenmez, İngilizce iOS sesleri yalnız
  Dil › İngilizce seçilince görünür. Kalınlık, Ses Miktarı, Düzlük, müzik, müzik arası, okuma davranışı *Gelişmiş Ses
  Ayarları*'nda, her biri bir kez.
- **Kaldırılanlar:** Ses yükseltme (dB), "Voice Dream ayarı" hazır ayar düğmeleri (Yelda/Cem/Derin/Ema), alt çubuktaki hız
  ve birim hapları, hız sayfası, üstteki "içindekiler" ve "diğer" kutusu (uyku/ara/git artık simge menüsünde; müzik
  yalnız Gelişmiş'te), `appTheme` / `appearance` / `ReaderTheme.system|gray`.
- **Bir kez taşıma** (`v.look.20261022`): görünüm Açık + lacivert + beyaz satır bandı + sarı kelime olarak kuruldu; hepsi
  Görsel Ayarlar'dan değişir. Müzik, ses ve hız ayarlarına dokunulmadı.

Sınanan: simülatörde (iPhone 17 Pro, 1,5 saatlik Türkçe kitap) oynatma, band + işaret hizası, sayfa kayması (24 kare),
bütün popover sayfaları, açık/koyu tema, dişli paneli, Konumlar. Sınanmayan: telefonda gerçek ses ve dokunuş, Yelda
(simülatörde yalnız Ema Tok ve sıkıştırılmış Yelda var), Spotify ile müzik. Telefona kurulum için telefon bağlı olmalı:
`zsh telefona-kur.sh`.

## 2026-10-22 (öğleden sonra) — müzik arası geçişi, tek hareket işaret, bisiklet modu, sesli not

Kullanıcı isteği: "müzik arası cümle bitimini beklesin, geçiş yavaş olsun; seçince doğrudan sarı olsun, öteki işlemler
ikinci aşamada; bisiklet takip modu, okuma ekranında ekran kilitlenmesin; sesli not el altında, Kıvılcım gibi yazıya
dökülsün, raporlansın". draw.io şeması onaylandı; FiiO BTR15 tuşları da istendi; aranın soru sorması istenmedi.

- **Müzik arası** (`SpeechPlayer`): süre dolunca okunan cümle bitirilir. Bir sonraki cümlenin ilk kelimesinin duyulacağı
  kare (`boundary(after:)`) bulunur, ses 0,22 sn'de o arada susar, kelime kesilmez. iOS kısmayı kaldırır, müzik yükselir.
  Ara bitince önce müzik iner (0,8 sn), sonra ses 2 sn'de yumuşakça açılır (`fadeTo`, mikserin düzeyi ×). Müziğin ne kadar
  yavaş yükseleceği iOS'un elinde: Spotify'ın sesine uygulama dokunamaz.
- **Tek hareket işaret** (`ReaderTextView`): seçip parmağı kaldırınca (`TouchLiftRecognizer`) seçim sözcük sınırına
  genişler ve sarı olur, menü çıkmaz. Dokunduğu işaretlerle birleşir, onların rengini alır. İşarete dokununca ikinci aşama:
  Sesli not · Not yaz · renkler · Kopyala · Buradan oku · Kaldır. Renk değişince ya da birleşince işaretin eski notu
  korunur (`addHighlight`).
- **Ekran kilitlenmez:** okuma ekranı açıkken `isIdleTimerDisabled` her zaman açık. Kilit tuşuna basılırsa iOS yine kilitler.
- **Bisiklet modu** (üst çubukta 🚲; ayar `v.bike`): yazı 1,35 kat büyür. Altta üç büyük düğme var: İşaretle (okunan cümle sarı
  olur) · 🎙 · Oynat. Sayfaya dokunulursa metin 4 sn sonra yeniden sesi izler. **Kulaklık tuşları** (BTR15): ⏭ okunan cümleyi
  işaretler, ⏮ sesli notu başlatır ve bitirir. Ses ve titreşimle haber verir. Not: Arka planda müzik açıkken (mixWithOthers)
  iOS kulaklık tuşlarını Spotify'a verir. O sırada tuşlar Voice Reader'a gelmez, ekrandaki düğmeler kullanılır.
- **Sesli not** (`NoteRecorder`, `NoteStore`, `AppModel+Notes`): 🎙 okuma ekranında her zaman sol altta durur. Tek dokunuş
  kaydı başlatır, tekrar dokunmak bitirir. Not, okunan cümleye ya da işarete bağlanır. Kayıt sürerken okuma durur, bitince
  aynı cümlenin başından sürer. Kayıt AAC 16 kHz 32 kbit/sn (Kıvılcım'ın kalitesi). Telefon notu hemen yazıya döker (iOS
  Türkçe tanıma). Notun yeri sayfada mavi noktalı alt çizgiyle görünür. Konumlar'da yeni **Notlar** sekmesi var: nota
  dokunmak notu açar (dinle, düzelt, sil), ▶ notun yerinden okur.
- **Eşitleme ve rapor:** not günlüğü `Application Support/VoiceReader/notes/<cihaz>.jsonl` dosyasında, ses `notes/audio/`
  klasöründe tutulur. İkisi de vault'a kopyalanır: `durum/Notes`, `durum/NoteAudio`. Mac'te Teoria'nın `library.py` dosyası
  `veri/voicereader_notes.py` betiğini çağırır. Betik Whisper ile (large-v3-turbo, Kıvılcım'ın modeli ve uydurma süzgeci)
  temiz bir döküm yazar ve notları `library/notes/voicereader.jsonl` + `notes-audio/` olarak Teoria'nın biçimine çevirir.
  Notlar Teoria'nın **Notlarım** ekranında kitaba ve yerine bağlı görünür. Telefonda elle düzeltilen döküm ("edited")
  korunur.
- **Yeni sistem değil:** aynı uygulama ve Teoria'nın var olan Notlarım ekranı. Puan, seri ve zamanlanmış iş yok.
- **Sınanan:** simülatör derlemesi. Simülatörde seç-bırak işareti, işaret menüsü, sesli not kaydı (dosya, süre, not
  günlüğü, noktalı alt çizgi), Notlar sekmesi, bisiklet modu ve cümle işaretleme denendi. Müzik arası kısa ayarla denendi:
  ara tam cümle sınırında başladı (kayıtlı konum yeni cümlenin başı), ara bitince okuma sürdü. Mac hattı sentetik notla
  denendi: Whisper Türkçe sesi doğru döktü, not kitaptaki paragrafa bağlandı, silinen not düştü, ikinci koşu önbellekten
  geldi. iPhone 13 Pro Max'e kuruldu ve açıldı (13:17).
- **Sınanmayan:** telefonda gerçek sesle kayıt ve iOS dökümü (simülatörün mikrofonu sessiz kaldı), BTR15 tuşları, ses
  düzeyindeki yumuşak geçişin kulakla dinlenmesi, Spotify ile ara, Teoria ekranında notların görünüşü.
- Yedek: `_yedek-20261022/`.

### 2026-10-22 (akşamüstü) — hızlı hız düğmesi, bisiklet çubuğu yeni düzende
- **Hızlı hız** (`SpeedChip`): alt çubukta, sağ altta duran bir düğme. Bisiklet modunda üst çubukta duruyor. Her dokunuş
  sıradaki hıza geçiyor: 260 → 330 → 380 → 430 kelime/dk. Ayrıntılı hız ayarı Ses Ayarları'nda olduğu gibi kalıyor
  (kullanıcı kararı). Düğme aynı değeri yazıyor; belgenin kendi hızı varsa belgeye yazıyor.
- **Bisiklet çubuğu:** soldan sağa 🎙 · Oynat · İşaretle. İşaretle en büyük düğme, çünkü en çok kullanılan o.
  🎙 (`BikeMicButton`) 1 sn basılı tutulunca başlıyor; tutarken etrafında bir halka doluyor. Kısa dokunuş kaydı başlatmıyor,
  böylece yanlışlıkla basılmıyor. Kaydı bitirmek için tek dokunuş yetiyor.
- Sınanan: simülatörde hız geçişi (120 → 260 → 330), kısa dokunuşun kayıt başlatmaması, 1,3 sn basışın başlatması. Telefona
  kuruldu.

## 2026-10-23 — Otomasyon (klasör klasör, süreli ve aralı dinleme); bisiklette işaret aç/kapa

Kullanıcı isteği: "otomasyon ayarlarına gireyim; önce Felsefe klasöründeki cari okunan 15 dk, 1 dk düşünme arası ve sıradakinin anonsu, sonra Bilimler 15 dk, ara, sonra Mesleki 15 dk; hiçbir şeye dokunmadan kendiliğinden yürüsün". İkinci istek: bisiklet ekranında İşaretle'ye aynı cümlede iki kez basınca işaret silinsin.

- **Yer:** ~~Ayarlar › Otomasyon~~ → 2026-10-24'ten beri kütüphanede (Otomasyon kartı + sol üstteki ✦ düğmesi; aşağıya bak). Liste, ▶︎ başlat / ■ durdur, düzenleyici (ad, adımlar, klasör seçici, süre, ara uzunluğu, sırala/sil). Yeni otomasyon eklenebilir.
- **Pilot hazır kurulu:** "Üç dal · 15 dakika" = Felsefe 15 dk → ara 1 dk → Bilimler 15 dk → ara 1 dk → Mühendislik 15 dk ("mesleki" = Mühendislik klasörü).
- **Cari kitap:** klasörde en son açılmış, bitmemiş belge; hiç açılmamışsa ada göre ilk bitmemiş. Kaldığı yerden okunur. Kitap adım içinde biterse kalan süre klasörün sıradaki bitmemiş kitabına geçer.
- **Süre:** yalnız ses duyulurken sayılır (elle duraklatınca durur). Süre dolunca müzik arasındaki gibi cümle sonunda susar, yer o cümlenin başında saklanır.
- **Anonslar** (Türkçe sistem sesi, ayarlardaki Yelda): "Otomasyon başlıyor. Felsefe. <kitap>." · "Düşünme arası, bir dakika. Sonra Bilimler." · "Bilimler. <kitap>." · "Otomasyon bitti."
- **Arka plan:** adımlar arasında ses motoru sessizlikle çalışmaya devam eder, oturum bırakılmaz (`SpeechPlayer.stop(release:)`, `load(handover:)`, `endSegment`, `playAfterHold`); kilitli ekranda yürümesi için. Müzik açıksa arada müzik yükselir, okuma başlarken iner.
- **Bitiş:** başka bir kitabı açınca, Durdur'a basınca ya da son adımdan sonra.
- **Görünüm:** mini oynatıcıda "2/5 · Düşünme arası · 0:42", Otomasyon ekranının başında adım listesi ve kalan süre.
- **Bisiklet:** İşaretle düğmesi okunan cümle zaten işaretliyse "İşareti kaldır" olur, basınca işaret silinir (farklı tık sesi, hafif titreşim). Kulaklığın ⏭ tuşu da aynı aç/kapa.
- **Dosyalar:** `Model/Automation.swift`, `AppModel+Automation.swift`, `Views/AutomationViews.swift`, `Speech/AutomationTest.swift` (simülatör kancaları `-autotest <n>`, `-marktest`); yedek `_yedek-20261023/`.

### 2026-10-23 (öğle) — bisiklette İçindekiler, cam düğmeler + renk takımları, imlece dönüş, üst dokunuş

Kullanıcı isteği: bisikletteyken içindekilere hızlı ulaşmak (bulunduğu yeri görmek, başka bölüme geçmek); alt düğmeler eşit boyda, daha temiz, cam (crystal) görünümde ve renk seçilebilir; kitap açıkken üste dokununca kitabın başına gitmesin; "Konuşma imlecine git" daha etkili olsun.

- **Bisiklet üst çubuğu:** Kütüphane · **İçindekiler** (liste simgesi; başlığa dokunmak da açar) · kitap adı ve altında **okunan bölüm** · hız · **Aa** (Görsel Ayarlar) · bisikletten çık. İçindekiler büyük sayfa olarak açılır, okunan bölüm vurgulu ve ortada; en üstte büyük **Önceki bölüm / Sonraki bölüm** düğmeleri (okuyorsa oradan okumaya devam eder).
- **Alt düğmeler** (`Views/BikeControls.swift`): Basılı tut · Oynat · İşaretle eşit boyda, 26 pt köşeli cam (iOS 26 Liquid Glass, öncesinde ince malzeme + parlak kenar); mikrofonun 1 sn halkası düğmenin kenarında döner; işaretli cümlede "Kaldır" soluk ve kesik çizgili.
- **Renk takımları:** Görsel Ayarlar › **Bisiklet Düğmeleri**: Kristal (varsayılan: saydam cam, renkli simge) · Klasik · Okyanus · Orman · Gün batımı · Grafit (`settings.bikeStyle`, `v.bikeStyle`).
- **Üste dokunma:** `tv.scrollsToTop = false`; durum çubuğuna dokunmak artık kitabı başa sarmıyor.
- **Konuşma imlecine git:** büyük, dolu düğme; ok imlecin yönünü gösterir (yukarı/aşağı); her basışta mutlaka kaydırır (eskiden imleç yerinden oynamamışsa istek aynı değer olduğu için hiçbir şey olmuyordu: `goToCursor()`); Oynat'a basınca da sayfa kendiliğinden sese döner.
- Sınanan: simülatörde bisiklet ekranı (Kristal, Gün batımı), İçindekiler + Sonraki bölüm (7 → 16), durum çubuğu dokunuşu, imlece dönüş; iPhone 13 Pro Max'e kuruldu. Yedek `_yedek-20261023b/`.

## 2026-10-23 (öğle sonrası) — kaldığın yer yalnız bilerek değişir; cümle işareti; dokunulmaz kütüphane

Kullanıcı isteği: "ekranda gördüğüm yer ile kaldığım yer ayrı olmalı; okuma yerini ancak bilerek değiştireyim."

- **İçindekiler / arama:** satıra dokunmak yalnız sayfayı oraya götürür; okuma yeri yerinde kalır. Okuma yeri ▶ ile
  (listede) ya da metne çift dokununca değişir. Eskiden satır `onJump(offset, false)` ile imleci taşıyordu (asıl arıza).
  Bisikletteki "Önceki/Sonraki bölüm" düğmeleri bilerek basılan düğme olduğu için okuma yerini taşımayı sürdürür.
- **Çift dokunuş:** imleç o kelimeye gelir ve okuma başlar (duraklatılmışken de).
- **Basılı tutma:** kelime değil, bütün cümle sarı işaretlenir; cümle tutamaçlarıyla seçili kalır, tutamacı çekip
  bırakınca aynı işaret o aralığa daralır (ikinci işaret açılmaz). Bir dokunuş seçimi kapatır.
- **"Konuşma imlecine git":** altta, mikrofonla aynı sırada, yarı saydam; yalnız sayfa kayarken ve durduktan sonra
  1,8 sn görünür. Tam ekranda mikrofon ve oynat düğmesi de öyle; kayıt sürerken mikrofon hep görünür.
- **Mikrofon (bisiklet dışı):** kayıt ancak 1 sn basılı tutunca başlar (halka dolar); kısa dokunuş "Kayıt için basılı
  tut" der. Kayıttayken tek dokunuş bitirir.
- **Ekran:** yalnız okuma (ya da kayıt) sürerken açık kalır; duraklatılınca telefon olağan sürede kararır.
- **Kütüphane dosyası güncellemelere dayanıklı:** `library.json` (kaldığın yer + işaretler) her alanı isteğe bağlı
  okur (eksik alan varsayılanla, bilinmeyen renk/biçim yedek değerle), bozuk tek kayıt ötekileri düşürmez. Eskiden
  Swift'in hazır Codable'ı yüzünden yeni bir alan eklenen güncellemede dosya hiç okunamaz, boş kütüphane üstüne
  yazılırdı. Her başarılı açılışta `library.backup.json`; okunamayan dosya `library-unread-<zaman>.json` olarak
  kenara alınır, eksik kayıtlar yedekten döner.

Sınanan (simülatör): eksik/bilinmeyen alanlı ve kimliği bozuk kayıtlı kütüphane (4 kitap da geldi, yeni konum korundu,
bozuk kayıt yedekten döndü); içindekiler satırı yalnız kaydırdı (okuma %40'ta kaldı), düğme göründü ve kayboldu;
basılı tutma bütün cümleyi işaretledi, tutamaçla kısaltma tek işaret bıraktı; çift dokunuş oradan okumayı başlattı.
iPhone'a kuruldu. Sınanmayan: telefonda dokunuşlar, mikrofonun basılı tutma hissi, ekranın kararma süresi.
Yedek: `_yedek-20261023c/`.

## 2026-10-23 — İstatistik: dinleme, verim, üretim

Kullanıcının isteği: Ana ekranda küçük de olsa grafikli bir dinleme istatistiği olsun. Günlük, haftalık ve aylık ortalamaları saat, kelime, sayfa ve kitap olarak göstersin. Uygulamanın ne kadar ve ne verimle çalıştığı, işaret ve sesli not sayısı da görünsün. draw.io şeması onaylandı (＋ek vault kopyası dahil).
- **Günlük** (`Model/ListeningLog.swift`): Saniyede bir oynatıcının durumuna bakıyor. Çalarken o belgenin dinleme saniyesi artıyor. Okuma oturumu açık ama duraklatılmışsa duraklatılmış süre artıyor. Müzik arasında ara süresi artıyor. Duyulan kelime, imlecin ilerlediği metindeki kelimelerden sayılıyor; 3.000 karakterden büyük atlama sayılmıyor. Yüzde 99'a varan belge o günün biten kitabı oluyor, her belge bir kez. Kayıt `Application Support/VoiceReader/listening/<cihaz>.json` dosyasına yazılıyor, kopyası vault'ta `durum/Listening/<cihaz>.json`. Ses motoruna dokunulmadı.
- **Ekran** (`Views/StatsViews.swift`):
  - Kütüphane'nin en üstünde bir kart duruyor: bugünün süresi, kelime ve sayfa sayısı, son 7 günün çubukları (bugün turuncu). Karta dokununca **İstatistik** açılıyor.
  - İstatistik sayfasında Gün / Hafta / Ay seçimi var. Altında dört kutu (süre, kelime, sayfa, biten kitap) ve Swift Charts çubuk grafiği (son 14 gün / 8 hafta / 6 ay).
  - "Neyi dinledin" daire grafiği dinlemeyi klasörlere göre dağıtıyor.
  - Ortalama tablosu günlük, haftalık ve aylık değerleri süre, kelime, sayfa ve kitap için veriyor.
  - Verim bölümü: çalma oranı (çalma ÷ çalma + duraklatma), gerçek hız (kelime/dk), müzik arası.
  - Üretim bölümü: işaret, sesli not ve yazılı not sayısı, 1000 kelimede işaret, saat başına not.
  - En altta dönemin kitapları duruyor.
  - Sayfa ölçüsü 225 kelime. Hedef, seri ya da puan yok.
- **Geçmiş:** Dinleme süresi bu sürümden önce tutulmuyordu, o yüzden süre, kelime ve sayfa kurulduğu günden başlıyor. İşaretler ve notlar eski tarihleriyle sayılıyor.
- **Sınanan:** simülatörde örnek verilerle kart, Gün ve Hafta görünümü, daire grafik ve ortalamalar. Gerçek çalmada 31 sn'de 172 kelime kaydedildi (≈333 kelime/dk, ayar 330). Örnek veri sonra silindi.
- **Sınanmayan:** telefona kurulum (telefon bağlı değildi: `zsh telefona-kur.sh`) ve gerçek bir günün kaydı.

## 2026-10-24 — Otomasyon kütüphanede: kart, ✦ düğmesi, kaldığı yerden / baştan

Kullanıcı isteği: "otomasyonu daha ulaşılabilir yap, ona ulaşmak için bir düğme koy; ya sıfırdan başlasın ya kaldığı yerden devam etsin; ulaşım sezgisel ve kolay olsun." (Şema istenmedi: "plan yapma, direkt uygula".)

- **Kütüphane kartı** (`AutomationCard`, ana sayfanın en üstünde, İstatistik kartının üstünde): otomasyonun adı (birden çok varsa adına dokunup seçilir), adımların şeridi (okuma = süresi kadar uzun, klasör renginde çubuk; ara = nokta; biten adımlar dolu, bulunduğu adım duyulan süre kadar dolu) ve tek dokunuşluk düğmeler:
  - hiç başlamamış ya da sonuna kadar çalmışsa **▶ Başlat**;
  - yarıda kalmışsa altında "Kaldığı yer · 3/5 · Bilimler · 7:20 kaldı" + kitabın adı, düğmeler **▶ Kaldığı yerden** ve **↺ Baştan**;
  - çalışırken "Şimdi · 3/5 · Bilimler · 7:20 kaldı", şerit canlı dolar, **■ Durdur**.
- **✦ düğmesi** (kütüphanenin sol üstü, dişlinin yanı; otomasyon çalışırken nabız gibi atar) ve kartın ≡ simgesi aynı **Otomasyon** sayfasını açar: liste, düzenleyici, "Şu an". Listede yarıda kalanın altında turuncu "Kaldığı yer" satırı; ▶'ye basınca *Kaldığı yerden · Baştan başlat* sorulur.
- **Ayarlar'dan çıktı:** her şey tek yerde kuralı; Otomasyon'un evi artık kütüphane.
- **Kaldığı yer nedir:** otomasyonun hangi adımda olduğu ve o adımda kaç saniye dinlendiği (`AutomationProgress`, otomasyon başına, UserDefaults `automations.progress.v1`). Durdur'a basınca, başka kitap açınca, uygulama arka plana geçince ve okurken ~10 sn'de bir yazılır; uygulama kapansa da kalır. Son adım bitince silinir.
- **Kaldığı yerden:** o adımdan, kalan süreyle sürer ("Otomasyon kaldığı yerden sürüyor."). Düşünme arasında durdurulduysa ara bitmiş sayılır, sıradaki okumadan sürer; 5 sn'den az kalmış okuma da bitmiş sayılır. Düzenlenip adımı silinen otomasyon eski sırasına düşer.
- **Baştan:** ilk adımdan, tam sürelerle. **İki durumda da kitaplar kendi kaldıkları yerden okunur** — otomasyon kitabın yerine dokunmaz (kaldığın yer kutsal).
- **Dosyalar:** `Model/Automation.swift` (`AutomationProgress`, `ResumePoint`, `resumePoint(for:)`), `AppModel+Automation.swift` (`startAutomation(_:resume:)`, `saveAutomationProgress`, `automationTick`), `Views/AutomationViews.swift` (`AutomationCard`, `AutomationTrack`, `AutomationSheet`), `Views/LibraryScreen.swift`; simülatör kancaları `-resumetest <n>`, `-cardtest`. Yedek `_yedek-20261024/`.

- **Sınanan:** simülatörde `-resumetest 30` (pilot 30× kısa): 3. adımın (Bilimler) 8,3. saniyesinde durduruldu → kayıt "adım 2 · 8,3 sn", kitap imleci 1694'te kaldı; Kaldığı yerden → "kaldığı yerden sürüyor", Bilimler aynı imleçten kalan 22 sn okundu, ara, Mühendislik 30 sn, bitiş; bitişte kayıt silindi. Kartın üç hâli (Başlat · Şimdi/Durdur · Kaldığı yerden/Baştan) ekran görüntüsüyle; ✦ düğmesi Otomasyon sayfasını açıyor, ▶ "Kaldığı yerden · Felsefe · 14:55 kaldı / Baştan başlat" soruyor. iPhone 13 Pro Max'e kuruldu ve açıldı.
- **Sınanmayan:** telefonda gerçek 15 dakikalık durdur-sürdür; uygulama sistemce kapatıldıktan sonra sürdürme (kayıt ~10 sn'de bir ve arka plana geçerken yazılıyor).
- **Not:** `telefona-kur.sh`'nin `/tmp/vr-dev` önbelleği bu sefer onnxruntime paketini çözemedi; Xcode'un varsayılan DerivedData'sıyla derlenip `devicectl` ile kuruldu.

## 2026-10-24 — Net ve gür ses (VoiceMaster): Yelda'ya güç, çıtırtısız

Kullanıcı isteği: "sesi Voice Dream'deki Yelda gibi kuvvetli çıkmıyor; gücünü artır, vurucu olsun; çıtırtıları gideren bir ses algoritması; net ve gür".

- **Ölçüm (Mac, aynı ses ve ayar: Yelda 50 · 100, hız 3,12×):** VD Yelda'yı hiç işlemiyor: VD kaydı −18,1 LUFS, tepe −1,9 dBFS. Ham Yelda da aynı, −18,2 LUFS. Telefonda müzik "arka planda" ve düzeyi 0 olduğu için eski kod Yelda'ya +14 dB istiyordu. Bunu Apple'ın DynamicsProcessor'ı ve 2 ms'lik PeakLimiter'ı ile yapıyordu. Sonuç **−20,0 LUFS**, yani VD'den 2 dB daha kısık ("kuvvetli çıkmıyor" hissinin sebebi), bozulma −40,6 dB. Ham seste ve VD'de de saniyede yaklaşık bir kısa tiz tık var: ünsüz patlamalarındaki iğneler ve birim eklerindeki basamaklar.
- **Yeni zincir** (`Speech/VoiceMaster.swift`, 48 kHz, akışlı, 7 ms gecikme):
  1. Tiz bant (4 kHz üstü, LR4) ayrılır. ±2 ms çevresinin 4 katını aşan örneğin fazlasının dörtte üçü alınır. 4 kHz altına dokunulmaz.
  2. Faz döndürücü (150/250/400/700 Hz). Gırtlak darbelerinin tepe/ortalama oranını 9,7 → 7,5 dB indirir.
  3. 70 Hz alçak kesici, gövde +2 dB (170 Hz), kutu sesi −2 dB (450 Hz), netlik +4 dB (2,8 kHz), 10 kHz alçak geçiren.
  4. Yumuşak dizli sıkıştırıcı: 3:1, 5 ms atak, 110 ms bırakma.
  5. 5 ms ileriyi gören sınırlayıcı, tavan −1 dBFS. Kazanç ±5 ms içinde tutulur ve ortalanır. Bir gırtlak periyodu içinde oynamaz, tavanı hiçbir örnek aşmaz.
- **Sonuç:** **−12,6 LUFS** (VD'den 5,6 dB, eski zincirden 7,4 dB güçlü), tepe −1,0 dBFS, bozulma −44,4 dB (eskiden temiz). Sınırlayıcı ortanca 0,3 dB, %99'da 4,3 dB çalışıyor. 2,5–5 kHz bandı ham sese göre +4,5 dB. Telefondaki VD kaydı (super-compact Yelda) da −18,1 → −12,7 LUFS. iPhone'u yormaz: Mac'te gerçek zamanın ~400 katı.
- **Bağlantı:** canlı sistem sesi yolu (`received` → `master.process`, cümle grubu sonunda `scheduleTail`, kelime imleci `shift = latency`). Düzlük açıkken bellek yolu `renderSystem(clear:)`. Apple'ın DynamicsProcessor'ı grafikten çıktı. PeakLimiter yalnız Voice Reader seslerinde kaldı. Müzik öndeyken ses mikserde kısılır, müzik arkadayken en çok +2 dB eklenir.
- **Ayar:** Gelişmiş Ses Ayarları › Ses gücü › **Net ve gür ses** (varsayılan açık; kapalı = VD gibi işlenmemiş). Voice Reader'ın kendi seslerine (Ema, Anlatıcı…) dokunulmadı.
- **Örnek sesler:** `studio/ornek-ses-20261024/` (aynı 20 saniye: ham · eski zincir · yeni).
- Sınanan: Mac düzeneğinde ölçüm (uygulamanın VoiceMaster dosyası, Apple birimleri çevrimdışı), simülatör derlemesi, iPhone 13 Pro Max'e kuruldu ve açıldı (14:13). Sınanmayan: telefonda kulakla dinleme ve kelime imlecinin hizası (7 ms kayma hesaba katıldı), BTR15 ile. Yedek `_yedek-20261024-ses/`.

### 2026-10-24 (öğleden sonra) — güç değil temizlik: hışırtı süzgeci

Kullanıcı: "ses yüksekliğine değil kaliteye odaklan; sesin etrafında azalmış da olsa bir hışırtı ve hafif cızırtı var".

- **Ölçüm:** sessizlikte gürültü yok (−48 / −55 dB). Hışırtı sesli harflerin üstünde. Apple'ın bütün Türkçe seslerinde (Yelda, Cem; sade, gelişmiş; Kalınlık 50 ya da 100) sesli harfin 1 kHz üstü periyottan periyoda benzemiyor: 100–500 Hz'te benzerlik 0,94, 1–2 kHz'te 0,20, 2–3 kHz'te 0,12, 3–5 kHz'te 0,05. VD kaydı da aynı. Gövdeye göre eşitlenmiş bant ölçümünde ilk sürüm sesli harflerin 2,5–4 kHz'ini +5,2, 4–6 kHz'ini +3,8 dB büyütüyordu: hışırtıyı büyüten oydu (netlik yükseltmesi, 450 Hz kesmesi, 3:1 sıkıştırma).
- **Denenip bırakılan:** perde son süzgeci (kodeklerdeki pitch postfilter). Kaynakta harmonik olmadığı için kazanç yok.
- **Bulunan hata:** tiz bant "tüm ses − tiz" diye ayrılıyordu. LR4 tiz süzgeç geçişte fazı 180° çevirdiği için tizi kısmak 2,5 kHz'i +1,8 dB yükseltiyordu. Artık eşleşmiş alçak/yüksek yarılar kullanılıyor (toplamı düz).
- **Yeni:** 2,5 kHz üstü bandın payı küçükken (sesli harf, −20 dB ve altı) bant 10 dB'ye kadar kısılıyor, 12 ms üzerinden karar veriliyor; s, ş, ç, f'de (−10 dB ve üstü) açık kalıyor. İğne bastırma 6σ'ya çıktı (4σ düz gürültüye saniyede 64 kez dokunuyordu, şimdi saniyede 0,5). Ton: faz döndürücü + 70 Hz kesici + 170 Hz'te +1,5 dB + 8,5 kHz alçak geçiren; netlik yükseltmesi ve 450 Hz kesmesi kalktı. Sıkıştırma 1,5:1.
- **Sonuç** (ham Yelda'ya göre, gövde 150 Hz–1 kHz eşit): sesli harfler 2,5–4 kHz −2,6, 4–6 kHz −2,1, 6–8,5 kHz −3,9 dB; ünsüzler +0,7 / +1,5 / −0,7 dB. Güç −16,4 LUFS (VD −18,1), tepe −1 dBFS, sınırlayıcı neredeyse hiç çalışmıyor. Telefondaki VD kaydında da −16,4 LUFS.
- Örnek: `studio/ornek-ses-20261024/4-temiz-son.m4a` (3 = ilk sürüm). 14:42'de iPhone'a kuruldu. Sınanmayan: telefonda kulakla.

### 2026-10-24 (akşamüstü) — tını dokunulmaz: boğukluk giderildi

Kullanıcı: "Net ve gür açıkken boğuklaşıyor, kapalıyken netleşiyor." Sebep: sesli harflerde 2,5 kHz üstünü 10 dB'ye dek kısan "hışırtı" katı ve 8,5 kHz kesici. Ölçümde gürültü gibi görünen o bant kulağın netlik diye duyduğu bant. Kapalı hâl ise artık işlenmemiş ham ses (eski Apple kırpıcı zinciri her iki kipte de yok), çıtırtısız ve net. Hışırtı katı, 8,5 kHz kesici ve 170 Hz yükseltmesi kaldırıldı. Kalanlar: iğne temizliği (6σ), faz döndürücü + 70 Hz kesici (genlik değişmez), 1,5:1 sıkıştırıcı, 5 ms ileriyi gören sınırlayıcı. Ölçü (ham Yelda'ya göre, gövde eşit): sesli harfler 1–8,5 kHz ±0,5 dB; ünsüzler +0,8…+2,3 dB; −16,6 LUFS (ham −18,2), tepe −1 dBFS. iPhone'a kuruldu. **Ders:** bu seste tınıya dokunan her kat (yükseltme ya da kısma) kayıp olarak duyuldu; temizlik = dokunmamak.

## 2026-10-24 — Sesli not kulaklığın mikrofonundan; Notlarım ekranı

Kullanıcı: "bisiklette BTR15'i ağzıma yaklaştırıp konuşuyorum ama ses kaydetmiyor; uygulama telefonun mikrofonunu kullanıyor, telefon uzakta kaldığı için sesimi almıyor. O seslere kolay ulaşacağım, bağımsız ama kitapla ilişkisini gösteren bir yer olsun."

- **Arıza:** `NoteRecorder` oturumu yalnız `.allowBluetoothA2DP` ile açıyordu: ses kulaklıktan çıkıyor, kayıt bile bile telefonun mikrofonundan yapılıyordu. Artık `.allowBluetoothHFP` (iOS 26; öncesinde `.allowBluetooth`) da açık ve `setPreferredInput` ile önce Bluetooth eller serbest mikrofonu (BTR15), sonra kablolu kulaklık mikrofonu, en son telefon seçiliyor. HFP bağlantısı kurulana dek (en çok ~1,5 sn) kayıt bekliyor, ilk kelimeler kaybolmasın diye. Kayıt bitince tercih sıfırlanıyor, okuma kendi `.playback` oturumunu kurunca A2DP geri geliyor. Kayıt sırasında kulaklıktaki ses telefon görüşmesi kalitesinde olur (HFP'nin doğası).
- Kayıt şeridi hangi mikrofonun dinlediğini yazıyor: yeşil 🎧 + cihaz adı (ör. BTR15) ya da turuncu 📱 "Telefon".
- **Notlarım** (Kütüphane'de İstatistik kartının altında kart → `Views/NotesScreen.swift`): bütün notlar kitaptan bağımsız tek listede. Hepsi / Sesli / Yazılı, arama (not, cümle, kitap, bölüm), tarihe ya da kitaba göre (kitap başlığında kapak ve not sayısı). Her satırda: oynat düğmesi (ses satırda çalar, okuma duraklar), döküm, notun bağlı olduğu cümle, mavi kitap bağlantısı. Kitap bağlantısı kitabı açar ve o cümleyi ekrana getirir; **kaldığın yer değişmez** (yalnız ▶ ya da çift dokunuşla). Satıra dokunmak not sayfasını açar (dinle, düzelt, sil); sola kaydır = kitapta aç, sağa kaydır = sil.
- Yedek `_yedek-20261024-mik/`.

Sınanan: simülatör derlemesi; Notlarım kartı, liste, satırda çalma, kitap bağlantısıyla notun cümlesine atlama (ekran görüntüsüyle). iPhone'a kuruldu ve açıldı. **Sınanmayan:** BTR15 ile gerçek kayıt (simülatörde Bluetooth yok), HFP açıkken BTR15'in ⏮ tuşunun kaydı bitirip bitirmediği, Spotify açıkken HFP davranışı.

## 2026-10-26 — iOS 27: metin atlaması onarıldı; Kalınlık 50'nin zayıflaması ölçüldü

Kullanıcı: "iOS 27'yi yükledim, Voice Reader'da metin atlamaları ve ses kalınlık bozulmaları oldu; Voice Dream'deki
Yelda ayarını (ekolayzer dahil) olduğu gibi uygula, hataları düzelt."

Ölçüm telefonda (iPhone 13 Pro Max, iOS 27.0.1), `-sysdump` kancasıyla (`Speech/SystemDump.swift`): uygulamanın kendi
`AVSpeechSynthesizer.write` çağrısı, her tampon (biçim, uzunluk, nesne, zaman) ve her kelime bildirimi kaydedildi,
ses Mac'te çözümlendi.

- **Ses kimliği değişti:** `super-compact.tr-TR.Yelda` yok, yerine `compact.tr-TR.Yelda` (ve `compact…Cem`). Ses aynı:
  Mac'teki Yelda ile ses rengi birebir (zarf farkı 0,005), hız aynı (0,81'de 11,23 ↔ 11,17 sn). Hız tablosu doğru.
- **Metin atlamasının sebebi:** iOS 27 uzun bir cümle grubunun ortasında da boş tampon gönderiyor (örnekte üç cümlenin
  ikincisinden sonra; sonra ses sürüyor, en sonda ikinci boş tampon). Voice Reader boş tamponu "bitti" sayıyordu: sıradaki
  parça başlıyor, geç gelen tamponlar atılıyordu → paragrafın kalanı okunmuyordu. **Onarım:** bitiş artık
  sentezleyicinin `didFinish` bildirimi; yedek olarak boş tampondan sonra 0,5 sn ses gelmezse (`SpeechPlayer.endIfQuiet`,
  `utteranceFinished`). Bellekte üretim yolu (`AppleCapture`, Düzlük açıkken) aynı kuralla.
  Tamponların yeniden kullanılması şüphesi boşa çıktı (geç okunan kopya birebir aynı). Tamponlar artık ana iş
  parçacığında ve neredeyse bir anda geliyor (31 sn'lik ses 0,4 sn'de).
- **Kalınlığın sebebi:** iOS 27'de `pitchMultiplier` zayıfladı. Yelda 1,0 = 206 Hz (değişmedi), 0,5 = **181 Hz**
  (eskiden ve Voice Dream kaydında 155–157 Hz). 0,5'in altı 181 Hz'te kesiliyor (0,1–0,4 aynı ses). SSML
  `<prosody pitch>` bu seste hiç ses üretmedi (3 dk bekledi). Eski davranış Mac'te ölçüldü: perde oranı 100'ün altında
  (1 + p) / 2, üstünde p; ses rengi (formantlar) değişmiyordu.
- **Denenip bırakılan:** eksik 2,7 yarım tonu PSOLA ile eklemek. Ortanca perde tuttu (159 Hz) ama karelerin %8'i 3–5
  yarım ton yüksek kaldı, tonlama 4,3 → 5,2 yarım ton genişledi (eşik, perde aralığı, boşluk doldurma değiştirmedi).
- **Voice Dream'de ekolayzer yok:** Mac'teki Voice Dream'in ses çerçevesi (`VDCoreTTSMacOS`) yalnız `rate`,
  `volume`, `pitchMultiplier` verip `writeUtterance:toBufferCallback:` ile çalar. **Ses Ayarları › Voice Dream ayarı:
  330 · 100 · 50** düğmesi bunu birebir kurar: hız 330, ses miktarı 100, kalınlık 50, Düzlük 0, Net ve gür ses kapalı.

Sınama kancası `-skiptest`: iki uzun paragraf (altışar cümle) gerçek oynatıcıyla Yelda 330'da okunur, okunan kelime
0,2 sn'de bir `Documents/skiptest.txt`'ye yazılır. Simülatörde (iOS 26.3): 165 konum, en büyük sıçrama 31 harf, iki
paragraf da sonuna kadar.

### 2026-10-26 (devam) — iPhone'un seslendirme ayarlarıyla oku

Kullanıcı iOS 27'nin Ekranı Seslendir'iyle Yelda'nın kaydını gönderdi ("tam istediğim tını"; Ayarlar'da Perde en
altta, Ekolayzer var). Kayıt: 161 Hz (143/174), tonlama 3,3 yarım ton, ≈280 kelime/dk.

- `AVSpeechUtterance.prefersAssistiveTechnologySettings = true` ile uygulamanın kendi `write()` çağrısı bu ayarları
  alıyor (telefonda ölçüldü): Yelda **156 Hz** (136/174), tonlama 4,2 yarım ton, ses rengi eski Yelda ile bantlarda
  ±1 dB. Uygulamanın verdiği hız yok sayılıyor (0,5 ve 0,81 aynı süre); ses de iOS ayarındaki ses. Tamponlara
  ekolayzerden ayrıca bir renk gelmedi (kullanıcının ekolayzeri düz olabilir ya da çıkışta uygulanıyor olabilir).
- **Ses Ayarları › Gelişmiş › "iPhone'un seslendirme ayarlarıyla oku"** (varsayılan açık, `a.systemSpeech`): Türkçe
  sistem sesi (canlı yol, Düzlük yolu, önizleme) bu bayrakla okunur. Bu kipte hız, perde, ses ve ekolayzer Ayarlar ›
  Erişilebilirlik › Seslendirilen İçerik'ten gelir; Voice Reader'ın hız düğmesi sesi değiştirmez; Ses Miktarı ve
  Kalınlık kartları gizlenir. Kapalıyken eski düzen ve "Voice Dream ayarı: 330 · 100 · 50" düğmesi.

Sınanan (iOS 27.0.1, iPhone 13 Pro Max): `-sysdump ats` ölçümü; `-skiptest` iki kipte de (en büyük sıçrama 21 harf, iki
paragraf da sonuna kadar). Sınanmayan: canlı okumada perde ayrıca ölçülmedi (aynı `write()` çağrısı), İngilizce
cümlelerde (karışık dil) bayrak kapalı kalır, kilit ekranında uzun dinleme.
Not: `devicectl device process launch` uygulama argümanlarını `--` ardından ister (`-- -skiptest`); yoksa `-skiptest`'i
kendi seçeneği sanıp başlatmaz.

### 2026-10-26 (öğle) — ses gücü: iPhone ayarları kipinde kısılma giderildi, +4 dB

Kullanıcı: "iPhone seslendirme ayarlarıyla oku dediğimde kısılıyor (iOS'ta en yüksekte); Net ve gür artırıyor ama Voice
Dream seviyesine gelmiyor." Telefonda ölçüldü: bu kipte iOS sesi uygulamaya **11,6 dB kısık** veriyor (konuşma
ortalaması −28 dBFS, düz Yelda −16,3); ilk ölçümde aradaki fark yoktu, iOS'taki sürgü oynayınca değişti. Bu yüzden ölçülür:
`ProfileRenderer.assistiveGain` kısa bir cümleyi duyulmadan iki kez (ayarlarla ve ayarsız) üretir, farkı (−6…+24 dB)
her okuma başında `SpeechPlayer.calibrateAssistive` ile alır, sonraki tamponlara uygular (son değer `a.assistiveGain`).
Ardından VoiceMaster bu kipte hep açık, **+4 dB** (Net ve gür ses de +4, önce +2). Mac'te uygulamanın VoiceMaster'ıyla
ölçüldü: −27,8 → telafi −16,7 → **−11,7 dBFS**, tepe −1 dBFS; tını bantlarda ±1,2 dB (+6'da 2 dB kayıyor, +8 yalnız
0,4 dB daha veriyor). Bu kipte "Net ve gür ses" anahtarı gizli. Bulgu: bu kipte iOS uygulamanın hızını bazen alıyor bazen
almıyor (0,5 ve 0,81 bir ölçümde aynı süre, ötekinde 0,5 daha kısa); hız için iOS sürgüsü esas.
Sınanmayan: telefonda kulakla Voice Dream'le yan yana karşılaştırma.

## 2026-10-26 (öğleden sonra) — kaldığın yer artık kaybolmaz; bisiklette Yolda ekranı

Kullanıcı isteği: "Voice Reader sürekli kaldığım yeri unutup geri dönüyor; hiçbir şekilde unutmasın, güncellemeler de
etkilemesin. Yolda Okuma artifact'ındaki simülasyonu Voice Reader'da gerçekleştir; mevcut bisiklet görünümü seçenek
olarak dursun; işaretleme, ses kaydı, bölümler arası gezinme ve hız bu ekranda da olsun." Aynı oturumda: "görselleştirmeyi
üste taşı, işaretlemeleri animatik öğelerle güzelleştir."

**Arıza (ölçüldü):** `LibraryStore.saveSoon()` her çağrıda bekleyen kaydı iptal edip 2 sn'lik sayacı yeniden kuruyordu;
okuma sürerken imleç ~2 sn'de bir bildirildiği için **kütüphane okuma boyunca hiç yazılmıyordu**. Yer yalnız uygulama
arka plana geçerken (`saveNow`) diske iniyordu. Kilitli ekranda uzun dinlemeden sonra iOS uygulamayı kapatınca ya da bir
güncelleme kurulunca o andan sonra dinlenen her şey kayboluyordu → "geri dönme". İkinci yol: iCloud eşitlemesi başka bir
cihazın daha yeni tarihli ama geride kalan yerini uygulayabiliyordu.

- **Yer defteri** `Application Support/VoiceReader/places.json` (+ UserDefaults `places.v1`): her imleç hareketinden en çok
  1 sn sonra yazılır, sonraki hareket onu ertelemez. Açılışta defter `library.json`'dan (ya da yedeğinden) daha yeniyse o
  kazanır. Bütün yer yazımları `store.setPosition(_:_:)` üzerinden (bitiş, Başa sar, eşitleme dahil).
- `saveSoon()` artık bekleyen kaydı yeniden başlatmaz (2 sn içinde mutlaka yazar).
- Eşitleme yeri **asla geri almaz**; başka cihaz yalnız daha ileri bir yer getirirse uygulanır.
- Sınama (simülatör, Felsefe 03): okuma sürerken 12/24/34. sn'de defter 241 → 395 → 576; 34. sn'de `kill -9`, yeniden
  açılışta yer 576 (kayıp < 1 sn). Eski kodda kütüphane bu sürede yazılmıyordu.

**Yolda ekranı** (`Views/RideView.swift`; Bisiklet modu › görünüm Yolda (varsayılan) / Klasik; ayar `v.bikeLook`):
OLED siyah, krem metin, kehribar = duyulan, altın = işaret. Kademeler (`v.rideStage`: Otomatik GPS / Durgun / Seyir /
Dikkat): durgun (<3 km/sa) son üç cümle, yalnız söylenmiş kısım, duyulan kelime ve kavramlar kehribar; seyir (3–20)
üstte sabit noktada tek kavram kelimesi, 3,2 sn sonra mürekkep gibi aşağı dağılır, dibe tortu olur; dikkat (>20, viraj,
sert fren) yazı yok, nabız + ilerleme ışığı. Sakinleşme 1,2 sn bekler, dikkate geçiş anında; konum yoksa sakin kademe.
Kavramlar kitapta tekrar eden içerik kelimesi ya da özel ad (`RideConcepts`, başlıklardaki büyük harf ad sayılmaz).
- Her kademede: ekrana dokun / İşaretle = cümleyi işaretle (aynı cümlede tekrar = kaldır), yeni cümlenin ilk 2 sn'sinde
  basılırsa biten cümle (işaretli değilse; kulaklık ⏭ de aynı); mikrofon 0,5 sn basılı = sesli not (her ekranda `MicHold`; 1 sn yolda uzun geldi); hız −/+ 20 k/dk
  (iOS seslendirme kipi açıksa uyarır).
- Durgunken ya da okuma durmuşken: önceki/sonraki bölüm, önceki/sonraki cümle, oynat. İçindekiler satırı yalnız o yerin
  açılışını gösterir (`RidePeek`), okuma yeri ▶ ile değişir.
- İşaret animasyonu: dokunulan yerden altın halka + kıvılcımlar, yaprak süzülüp sayaca konar, cümle altın çerçeve ve
  bir kez üstünden geçen ışıkla kalır; Hareketi Azalt açıksa yalnız halka.
- Konum izni: `NSLocationWhenInUseUsageDescription`; yalnız ekran açıkken ve Otomatik'te.
- Sınama kancası `-ridelog` (Documents/ride.log: kademe, kavram, tortu).

Sınanan: simülatörde (ayrı "VR Yolda" cihazı) durgun ve seyir kademeleri, işaret + animasyon, ayar sayfası, derleme.
Sınanmayan: gerçek GPS ile kademe geçişi ve dikkat kademesi yolda, telefonda kulakla, BTR15 ile geriye yakalama.
Yedek `_yedek-20261026-yer/`.

## 2026-10-27 — Wise Path: biten kitap biter; kaldığın yer yalnız sen isteyince değişir; yeni ad ve ikon

Kullanıcı isteği (draw.io şeması onaylandı; kararlar: müzik bitince = Spotify durunca, müzik modunda ritim mikrofon + BPM birlikte; önce çekirdek). Aynı oturumda: "logoyu modernize et, daha büyük, sade, kitap biçimi, güçlü renk" ve "uygulamanın adı Wise Path olsun".

**Bulunan arıza.** Biten kitap açılınca oynatıcıya 0. karakterden yükleniyordu (`doc.position >= doc.length ? 0 : …`); ▶'ye basınca o sıfır, yer olarak yazılıyordu. Ayrıca "bitti" kayıtlı değildi, yüzde 99'dan tahmin ediliyordu; Belge sonu › "Belgeyi tekrarla" kitabı kendiliğinden başa atıyordu.

**Şimdi.**
- `DocumentRecord.finishedAt` + `finishes` (her biten okumanın tarihi). Bitti = kayıtlı olgu; eski kütüphanede %99'daki kitaplar bir kez "bitti" sayılır (yalnız bu iki alan hiç yoksa).
- Biten kitap sonunda açılır. `SpeechPlayer.mayMove` her oynatma ve yer değişikliğinden önce sorulur; biten kitapta hiçbir şey olmaz, "Bu kitap bitti" sorusu gelir: Baştan başla · Buradan başla (N. okuma) · Bitti olarak kalsın. Okuyucuda üstte "Bitti · tarih · Başa dön" bandı.
- Yeni okuma `startReadingAgain`: rafta turuncu "2. okuma" rozeti, durum yazısı "2. okuma · %…"; biten kitapta yeşil "Bitti / 2×".
- "Belgeyi tekrarla" kaldırıldı; "Sonraki belgeye geç" yalnız bitmemiş belgeye geçer. Başa sar artık sorar (kütüphane menüsü ve okuyucu).
- Otomasyon: adımın kitabı (klasörde son açılan) bitmişse ya da adım sürerken biterse susup sorar: ekranda uyarı + sesli anons; kulaklıkta ⏭ sıradaki bitmemiş kitap, ⏮ yüklü kitaptan sür, ⏯ durdur (`SpeechPlayer.remoteChoice`). Biten kitabı otomasyon bir daha okumaz.
- Ad **Wise Path** (görünen ad; paket kimliği `com.fatihgocgun.okur`, iCloud klasörü "Voice Reader" aynı: kütüphane ve imza korunur). İkon: mavi zemin, büyük beyaz açık kitap, kitaptan çıkıp güneşe uzanan altın yol; açık/koyu/renklendirilmiş. Kaynak `ios/icon-source/gen.py` (SVG → Chrome başsız → PNG).

**Sınanan:** simülatörde `-finishtest` (`Speech/FinishTest.swift`) 12/12: sona kadar okuma → bitti, yer sonda; ▶ ve atlamalar yeri oynatmaz, soru gelir; yeniden açılış sonda; otomasyon sorar, ⏭ sıradaki kitabı açar, biten kitaba dokunmaz; Baştan başla = 2. okuma. Ana ekranda ad ve ikon. iPhone'a kuruldu (telefon kilitliydi, açılmadı).
**Sınanmayan:** telefonda eski kütüphanenin bitti dönüşümü, kilitli ekranda otomasyon sorusu ve kulaklık tuşlarıyla cevap, okuyucudaki bandın gerçek ekranda yeri.
**Sırada (şemanın kalanı):** geriye kademeli işaretleme, aktif duraklatma, bisiklet/yürüyüş modları + GPS, müzik modu, Yolda istatistiği, raftan işaretlere bakış. Yedek `_yedek-20261027-bitti/`.

### 2026-10-27 (öğleden sonra) — geriye kademeli işaret, aktif bekleme, yeni ikon, değnek kalktı

- **İkon** (kullanıcının gösterdiği örneğin fikriyle, kendi çizimimiz): Voice Reader mavisinde zemin, beyaz kapalı kitap, üstte ve sağda iki sayfa kenarı, kitabın içinden aşağı akan kırmızı-turuncu yol; yolun ortasında incelen tek beyaz şerit (kesik çizgi yok, kullanıcı "daha modern" dedi). Kaynak `ios/icon-source/gen.py`.
- **Geriye kademeli işaret:** bisikletteki İşaretle tuşu (Yolda ve Klasik) dokununca okunan cümleyi işaretler; basılı tutunca 0,45 sn'de cümleyi alır, sonra her 0,6 sn'de bir önceki cümleyi ekler (en çok 6), tuşta "3 cümle" yazar, her adımda tık + titreşim. Kulaklık ⏭ 4 sn içinde yeniden basılırsa aynı şekilde bir cümle geriye uzar. Tek işaret olarak saklanır (`AppModel.extendMarkBack`, `MarkChain`, `SpeechPlayer.sentence(before:)`, `Views/MarkHold.swift`).
- **Aktif bekleme:** oynat düğmesine basılı tut (okuyucu, mini oynatıcı, bisiklet, Yolda) → 1 · 1,5 · 2 · 3 · 5 dk · Müzik durunca; okuma cümle başında durur, Spotify öne çıkar, süre dolunca (ya da Spotify 3 sn sessiz kalınca) aynı cümleden yumuşak açılışla sürer. Beklerken ⏯ hemen sürdürür. Kulaklık ⏯ / kilit ekranı duraklat okurken varsayılan olarak aktif bekleme başlatır (Ses Ayarları › Dinlenme: aç/kapa ve süre, varsayılan 2 dk). Müzik arasının düzeneği kullanıldı (`startBreak(kind:)`, `activePause`, `waitForMusicToStop` = `isOtherAudioPlaying`).
- **Değnek kalktı:** kütüphanenin üstündeki ✦ yerine dişli menüsü: Ayarlar · Otomasyon; otomasyon çalışırken dişlinin üstünde turuncu nokta. Otomasyon kartı ve mini oynatıcıda değnek simgesi de liste simgesine döndü.

Sınanan: simülatörde `-marktest2` 6/6 (işaret 1 → 2 → 3 cümle tek işaret, 4 sn bekleme kendiliğinden sürdü); ana ekranda ikon; telefonda kütüphanenin yeni biçimi (11 kitap, 1 bitti: Kurucuların Kitaplığı). iPhone'a kuruldu ve açıldı. Sınanmayan: basılı tutma hareketinin gerçek parmakla hissi, kulaklıkta ⏭ ikinci basış ve ⏯ bekleme, gerçek Spotify ile "Müzik durunca".

### 2026-10-27 (akşamüstü) — bisiklet ve yürüyüş modları: GPS kaydı, şerit, dönen simge, hızlı geçiş

- **İki mod:** okuyucunun üst çubuğunda bisiklet simgesi menü oldu: Bisiklet modu · Yürüyüş modu (`settings.moveKind`, `AppModel.startMove/endMove`). İkisi de aynı büyük tuşlu ekranları kullanır; ekranda simgeye dokunup ötekine geçilir ya da moddan çıkılır.
- **Kayıt (`Model/Workout.swift`, `WorkoutRecorder`):** mod açık olduğu sürece GPS rotası (4 sn'de bir nokta), km, hareket süresi, en yüksek hız, barometreyle tırmanış/iniş, yürüyüşte adımsayar, kalori. Kalori: yürüyüşte ACSM denklemi (eğim dahil), bisiklette Compendium MET'i hıza göre + tırmanış işi (%25 verim, bisiklet 12 kg). Kilo bir kez sorulur (`v.weight`, girilmezse 75 kg). Arka planda konum açık (`UIBackgroundModes: location`), ekran kilitli/cepteyken sürer; 30 sn'de bir ve arka plana geçişte yazılır; uygulama yolda kapanırsa yarım saat içinde açılınca aynı kayda devam eder; 1 dk ve 50 m altı tutulmaz. Dosyalar `Application Support/VoiceReader/workouts/`, vault `durum/Workouts/`.
- **Şerit (`Views/MoveViews.swift`):** saat · pil (%20 altı turuncu, %10 altı kırmızı) · km · süre · kcal · bisiklette km/sa, yürüyüşte adım · tırmanış · "geç". "geç" menüsü: son açılan 3 bitmemiş kitap (moddan çıkmadan geçer ve okumayı sürdürür) ve otomasyonlar (başlat / durdur).
- **Dönen simge:** bisiklette tekerlekler hızla orantılı döner (gözle izlenebilsin diye ¼ hızda), durunca durur; yürüyüşte figür adım atar.
- **Yazı eşikleri (kullanıcı kararı):** bisiklet 8 km/sa'e kadar cümleler, 8–25 kavram, 25 üstü ve sert fren/dönüşte yazı yok; yürüyüş hep cümleler, yalnız 8 km/sa üstünde kavram.
- **Yolda hız düğmesi:** eksi/artı kalktı (iPhone'un seslendirme ayarı açıkken kilitleniyordu); tek düğme, her dokunuşta 330 → 380 → 430. İşaretle en sağda (hız · mikrofon · İşaretle).

Sınanan: simülatörde sahte rota (6 m/sn) 40 sn: 241 m, 21 km/sa, 80 kg'da 7,2 kcal (beklenen 7,1), 9 rota noktası, dosya yazıldı; Yolda ekranında şerit ve simge. iPhone'a kuruldu. Sınanmayan: telefonda gerçek yolda GPS, cepte ve kilitliyken kayıt, adımsayar ve barometre, pil uyarısı, yürüyüş modunun ekranı. Sırada: İstatistik'te "Yolda" bölümü (rota haritası, gün/hafta/ay), müzik modu, raftan işaretlere bakış.

### 2026-10-27 (akşam) — Yolda üstü sadeleşti, durgun ekran ferahladı, Müzik modu

- **Üst satır** (kullanıcı: "gereksiz kalabalık"): yalnız saat ve pil, "SEYİR · 22 KM/SA" ile aynı sade yazıyla (`ClockBattery`, dakikada bir yenilenir; pil izleme açılışta başlar, %20 altı turuncu, %10 altı kırmızı). km · süre · kalori · hız/adım · tırmanış · "geç" o satıra dokununca açılır, 6 sn sonra kendiliğinden kaybolur (`MoveDetails`). Klasik bisiklet çubuğunda da başlığın üstünde aynı satır.
- **Durgun kademe:** cümlelere ayrılan alan büyüdü (altta 270 yerine 196 nokta); oynat · cümle · bölüm düğmeleri en alta ince, yuvarlak bir sıraya indi, oynat sıcak renkli dolu daire; hız düğmesi küçüldü; yeni cümle başlarken yazı yumuşakça yukarı kayar. Takılma görüntüsünün sebebi büyük ihtimalle uzun cümlenin dar alanda baştan kırpılmasıydı.
- **Müzik modu** (`Model/MusicMode.swift`, `Views/MusicModeView.swift`; şemanın 6. bölümü): okuyucunun mod menüsünden ya da bisiklet/yürüyüş simgesinin menüsünden açılır. Wise Path susar, müzik önde. Okunmuş kısımdan cümleler: önce kullanıcının işaretleri (kitap sırasıyla), araya Teoria'nın can alıcı cümleleri (yalnız metinde bulunup okunan yerden önce olanlar, ağırlık sırasıyla) ve ana fikir (vault'tan `00 - Philosophy/_projects/teoria/library`, kitap başlıkla eşlenir). Her vuruşta 1–3 kelime büyük, bulanıktan netleşerek gelir; cümle 5 vuruş kalır, sonra sıradaki. Arka planda renkli ışık lekeleri vuruşla nabız atar, halka yayılır; renk her cümlede kayar. Dokun: durur, cümle bütün hâliyle, neden önemli olduğu, bölümü ve kitabın ana fikri sakin bir kartta. Yana kaydır: sonraki/önceki. Ritim: mikrofon (müzik hoparlörden çalarken; Bluetooth mikrofonu açılmaz, müzik bozulmaz) ya da ritim düğmesine 3–4 kez ritimle dokunarak; ikisi de yoksa 96. Basılı tutunca mikrofon aç/kapa.

Sınanan: simülatörde üst satır, durgun kademe ve müzik modu ekranları (vuruşla kelime gelişi, sığma); iPhone'a kuruldu. Sınanmayan: telefonda gerçek müzikle mikrofon ritmi, Teoria cümlelerinin telefonda vault'tan gelişi, pil göstergesinin telefonda görünüşü.

### 2026-10-27 (gece) — İstatistik › Yolda; raftan işaretlere bakış

- **Yolda** (`Views/RoadStats.swift`, İstatistik'in sonunda, üstteki Gün/Hafta/Ay'a bağlı): km · hareket süresi · kcal · adım · tırmanış · yol sayısı; Hepsi/Bisiklet/Yürüyüş seçimi; son 14 gün / 8 hafta / 6 ay km çubukları (bisiklet turuncu, yürüyüş yeşil, üst üste); dönemin son gerçek yolunun haritası (rota çizgisi, yeşil başlangıç, kırmızı bitiş; yeni başlamış 0 km'lik kayıt gösterilmez); yol listesi (gün-saat, km, süre, kcal, adım ya da ortalama hız, tırmanış, yolda dinlenen kitaplar, süren yol "sürüyor").
- **İşaretlere bakış** (`Views/MarksSheet.swift`): kapağın sağ altında sarı "✎ n" (son dinlenenler kartı ve liste satırı) ya da kartın menüsünde "İşaretlere bak": kitaba girmeden bütün işaretler kitap sırasıyla, bölüm başlıkları altında, tarih ve notla; arama; dışa aktarma; satırı kaydır ya da basılı tut → "Kitapta göster" (kaldığın yer değişmez) / Kopyala.

Sınanan: simülatörde işaret penceresi, Yolda bölümü (sahte rotanın haritası, grafik, liste); iPhone'a kuruldu. Sınanmayan: telefonda gerçek yollarla. Kancalar `-statstest [road]`, `-markssheet`.

## 2026-10-27 (gece, geç) — Seri kapakları uygulamanın kendi çizimi

Kullanıcının isteği: kitap kapaklarında kitabın adı okunmuyor; iki seri (Felsefe, Bilimler) daha anlaşılır olsun.
- Sebep: Bir Yöne epub'larının kapağı baskı kapağı (1600×2400, lacivert/bordo bez üstünde ince altın Didot). Rafta 100 pt genişliğe inince ad ve seri okunmuyordu.
- **`SeriesCover`** (`Views/Covers.swift`): başlığı `Felsefe 04 — Arkhe: …` (ya da `Felsefe 01 · Üçüncü Gün · Leibniz`) biçiminde olan kitapta epub resmi yerine uygulama kapağı kendisi çizer. Üstte seri renginde şerit: seri adı + kitap numarası. Ortada kitabın meselesi büyük kalın harfle (ARKHE, İMAN VE AKIL). Altında ince çizgi ve alt başlık. Arkada soluk büyük numara. Liste satırı boyunda (70 pt altı) yalnız numara ve mesele kalır.
- Seri renkleri: **Felsefe** lacivert + altın şerit · **Bilimler** koyu yeşil + kayısı şerit (eskiden bordo; lacivertten daha kolay ayrılsın diye) · **Mühendislik** (kapandı) grafit + gümüş.
- Öteki kitaplar (Kütüphane eserleri, Voice Dream'den gelenler) kendi kapaklarıyla kalır.
- Dokunulmayan: `04 - Books/Bir Yöne/cover.py` (epub ve Teoria'daki kapak) eski düzende.
- Sınanan: Mac'te aynı kodla 116 pt ve 46 pt çizim (yedi seri kitabı); iPhone'a kuruldu. Sınanmayan: telefonda rafın gerçek görünümü. Yedek `_yedek-20261027-kapak/`.

### 2026-10-27 (gece, 2) — Kinetik yazı, ritim çubukları, dört arka plan, Yolda'da dolan sayfa, Yolda kartı

- **Müzik modu › Kinetik** (`Views/KineticType.swift`; Akış hâlâ var, sağ üstte "Kinetik/Akış" düğmesi; varsayılan Kinetik): cümle noktalama işaretlerinden ya da 5 kelimede bir öbeklere bölünür; her öbek bir kompozisyon: sütunu dolduran kelime yığını · anahtar kelime yan yatık dikey, yanında öbürleri · ortada dev anahtar kelime, küçük kelimeler aralıklı büyük harf · eğik yığın. Küçük kelimeler (ve, bir, ile…) küçük, aralıklı, monospace; anahtar kelime en uzun / simgeli kelime, serif siyah, sıcak renk, inişinde zemin parlar. Kelimeler vuruşta "çarparak" iner (büyükten, eğik ve bulanıktan yerine); biten öbek izleyiciye doğru büyüyüp kaybolur. 60 kadar kök kelime simgeyle gelir (akıl → beyin, zaman → kum saati, yol, ışık → ampul, insan, soru, hakikat…).
- **Ritim çubukları ve arka planlar** (sağ üstteki simge sırayla değiştirir, `v.musicBackdrop`): Daire (varsayılan; tam siyah, ortada vuruşla nabız atan dairesel ritim çubukları), Siyah (tam siyah, altta ince çubuklar), Işık (renkli ışıklar + ortada soluk çubuklar), Gün batımı (mor-turuncu, vuruşla parlar). Çubuklar vuruşta sıçrar, sonraki vuruşa doğru söner, mikrofonun duyduğu ses düzeyi hepsini yükseltir; her vuruşta yeni bir biçim.
- **Yolda durgun kademe — sayfa:** yazı artık ortada bitmiyor; sayfa üstten aşağı, alttaki düğmelere kadar dolar (eski cümleler soluklaşır), sıradaki cümle sığmayacaksa sayfa yukarı kayarak silinir ve o cümleyle yeni sayfa başlar. Sığma gerçek yazı tipiyle ölçülür. Geriye atlanırsa sayfa oradan başlar.
- **Yolda'ya giriş:** kütüphanenin en üstünde "Yolda" kartı: Bisiklet · Yürüyüş · Müzik, tek dokunuş (çalan ya da son açılan kitapla). Bisiklet/yürüyüş her açılışta Yolda görünümüyle açılır (eskiden "Klasik" seçilmişse klasik açılıyordu; kullanıcı Yolda'yı bulamadı).

Sınanan: simülatörde Kinetik (dev kelime + beyin, dikey "ışıktır" + ampul, "soruyla" + insan), üç arka plan, dolan ve dönen sayfa, kütüphane kartı; iPhone'a kuruldu. Sınanmayan: telefonda gerçek müzikle.

## 2026-10-28 — Yolda tek düzen, GPS ekrandan ayrı; Kinetik ve Tam metin; müzikte Yalnız ritim ve Dinle

Kaynak: kullanıcının 27 Ekim akşamı Kıvılcım'a söylediği altı sesli not (21:05–21:23; telefonda kalmıştı, devicectl ile
alınıp dökümü yapıldı: `05 - Notlar/Fikirler/Kıvılcım/dokum/20261027-21*.json`).

- **GPS ekrandan ayrıldı.** Hareket modu (`bikeMode`) yalnız "modundan çık" ile biter; görünüm (`bikeLook`) dört:
  **Yolda** · **Kinetik** · **Tam metin** · Klasik. Tam metin sıradan okuyucudur (bütün kitap, geriye bakıp işaretleme),
  yol kaydı sürer; üstte ince bir şerit (süre · km · kcal, "Yolda" dönüşü). Görünüm bisiklet simgesinin menüsünden ya da
  Yolda'daki belge düğmesinden.
- **Kademeler kalktı.** Durgun/Seyir/Dikkat (hıza göre ya da elle) ve "Yolda ayarları" sayfası yok; tek düzen: son
  cümleler, duyulan kelime amber. `RideMotion` (ekranın ikinci GPS'i) kalktı, hız `WorkoutRecorder`'dan.
- **Üst:** kitabın adı + bölüm (amber); altında her zaman süre · km · kcal; dokununca ortada büyük pano (süre, km, kcal,
  hız/adım, ortalama, tırmanış; 6 sn'de kapanır). Saat ve pil telefonun kendi durum çubuğunda (ekran artık onu gizlemez,
  Yolda'da koyu).
- **Teker dönmüyordu:** simge `Menu`'nün etiketindeydi; menü etiketi bir kez çizilir. Simge menünün dışına alındı.
  Hızsız GPS noktasında hız iki noktanın arasından hesaplanır.
- **Kitap değiştirme:** Kütüphane düğmesine basılı tut → altta süren kitaplar ve otomasyonlar (`BookSwitchSheet`);
  üst şeritteki "geç" kalktı.
- **Kinetik görünüm:** okunan cümle müzik modunun kinetik dizgisiyle; duyulan kelimeye kadar öbek öbek iner
  (`KineticListening`).
- **Müzik modu üç içerik:** Cümleler (eskisi) · **Yalnız ritim** (yazı yok, yalnız arka plan ve ritim) · **Dinle**
  (kitap okunur, duyulan kelimeler kinetik). **Arada müzik ekranı** (Ses ayarları › Dinlenme, varsayılan açık): aktif
  bekleme ya da müzik arası başlayınca müzik modu Yalnız ritimle açılır, kalan süreyi gösterir; okuma sürünce kapanır.
- **Okuyucunun üstü:** kitabın adının altında okunan bölüm (vurgu renginde); Tam metin'de de görünür.
- **Kütüphane:** Notlarım kartı ana sayfadan kalktı; dişlinin yanında küçük dalga (waveform) düğmesi ve dişli menüsünde.

Sınanan: simülatörde Yolda, Kinetik, Tam metin (GPS sürdü: 0,32 → 0,40 km), Yalnız ritim. Sınanmayan: gerçek yolda,
basılı tutarak kitap değiştirme, aktif beklemede müzik ekranının açılıp kapanması, Dinle içeriği. Yedek
`_yedek-20261028-kivilcim/`.

### 2026-10-28 (öğle) — müzik modu müziği kesmiyor: açınca öne, kapatınca arkaya

Kullanıcı: "müzik modunu açınca arka plandaki müzik öne çıksın, kapatınca arkaya geçsin; açınca da kapatınca da
kesiyor." Sebepler: (1) açılışta ritim için oturum play-and-record'a geçiyordu (kulaklıkta mikrofon zaten bir şey
duymaz) ve bu Spotify'ı kesiyordu; (2) kapanışta etkin oturumun kategorisi değiştiriliyordu; (3) "Arka planda müzik"
kapalıyken okuma oturumu tekildi. Şimdi: mikrofon yalnız ses telefonun hoparlöründen çıkıyorsa (kulaklıkta ritim
dokunarak/saatle); açılışta okuma duraklar, oturum `notifyOthersOnDeactivation` ile bırakılır (`releaseToMusic`),
müzik tam düzeyde öne gelir; kapanışta mikrofon kapanırsa önce oturum bırakılır sonra kategori döner, okuma açılışta
sürüyorduysa kaldığı yerden sürer ve müzik sesin arkasına geçer (sürgüdeki düzeyde). Müzik modu açılınca "Arka
planda müzik" kapalıysa açılır. Sınanan: derleme, iPhone'a kuruldu. Sınanmayan: Spotify ve BTR15 ile kulakla.

### 2026-10-28 (öğleden sonra) — Yolda'nın sakin üstü geri geldi; müzik modunun üst satırı onarıldı

Kullanıcı (ekran görüntüleriyle): üstteki süre · km · kcal kutusu kalabalık ve dikkat dağıtıyor; ilk Yolda'nın soluk
üst satırı (saat · pil, altında hız) geri gelsin, kitap bilgisi en alta; müzik modunda da aynı soluk bilgi; pil ve
saat mutlaka görünsün. Şimdi `RoadStatus`: saat · pil (bilinmiyorsa "–", hiç düşmez), altında soluk büyük harfle
hız (hareket modunda) ve etiket. Yolda'da durum çubuğu yine gizli, kitap · bölüm ilerleme çizgisinin üstünde; süre ·
km · kcal yalnız üst satıra dokununca ortada büyük (`MoveBoard`). Klasik sayfanın üstünde ve müzik modunda aynı satır
(müzikte "MÜZİK MODU · hız" ve kitap); müzik modunun düğmeleri ikinci sıraya alındı (eklenen içerik düğmesi ilk
sırayı sıkıştırıp "Müzik modu" yazısını dikine kırıyordu). Tam metin şeridinde yalnız "Bisiklet sürüyor" ve Yolda
dönüşü. Sınanan: simülatörde Yolda ve müzik modu; iPhone'a kuruldu.

## 2026-10-28 (akşam) — kitap öncelikli kütüphane, Kitaplık (sırt rafı), tek İstatistik, hız; hızlı eylemler ve widget'lar

Kullanıcı isteği (draw.io şeması onaylandı): "telefonun amacı kitaplara ulaşmak; kitaplar en üstte, Yolda kalksın,
Bugün küçük; istatistik sayfası okuma + GPS; kitapları kütüphanedeki gibi sırtlarıyla, arşiv niteliğinde; takılma
olmasın, kodu temizle". Ardından: "ikona uzun basınca kaldığım yerden dinlesin, modlar; widget'lar: okuma
istatistiği, okuduğum kitaplar, bir kitabın kapağı ve alıntıları değişen; mantığı sana bırakıyorum".

- **Ana sayfa:** Okumaya devam (kapak, yer, ▶) → **Kitaplarım** (görünüm: Kitaplık · Vitrin · Izgara · Liste; raf:
  Tümü · Süren · Okunacak · Bitenler · klasörler) → ince şerit (Bugün · Otomasyon menüsü) → Klasörler. Üstte
  İstatistik, Yolda menüsü (Bisiklet · Yürüyüş · Müzik · Yollarım), Ekle; Notlarım ve Ayarlar solda.
- **Kitaplık (`Bookshelf.swift`):** ahşap raflarda dik duran sırtlar; kalınlık = kitabın uzunluğu, renk = seri/klasör,
  başlık sırtta dikey, yazar dipte; süren kitapta kırmızı ayraç kurdelesi ve ilerleme şeridi, biten kitapta altın
  bant (2+ okumada sayı). "Tümü"de üç raf: Süren · Okunacak · Bitenler · arşiv. Dokununca kitap raftan çıkar, kapağına
  döner: Devam et / işaretler.
- **İstatistik tek sayfa:** Okuma | Yol; Yol = Yollarım (`RoadsPanel`). Eski `RoadStats` silindi.
- **Hız:** okurken yer her 2 sn'de kütüphane listesine yazılıyordu, listeyi izleyen her ekran (okuyucu dahil) yeniden
  çiziliyordu. Artık liste yalnız yüzde değişince ya da sıçramada değişir; tam yer `places.json` defterinden
  (`LibraryStore.document(_:)` defteri katar; eşitleme de oradan). Kullanılmayan görünümler silindi
  (ListeningCard, AutomationCard, RoadLauncher, QuickBooksMenu, ReadingBadge).
- **Hızlı eylemler (ikona uzun bas):** Kaldığın yerden dinle (kitap adıyla) · Bisiklet · Yürüyüş · Müzik.
  `wisepath://` bağlantıları: resume · book/<id> · bike · walk · music · stats · road.
- **Widget'lar (`WisePathWidgets` hedefi):** Okumaya devam (küçük/orta/kilit) · Okuduklarım (orta/büyük, her kitap
  bağlantı) · Okuma (bugün + 7 gün) · Kitap ve alıntı (kitabı widget ayarından seç; boşsa okuduğun; işaretli
  cümleler yarım saatte bir ve → ile değişir). Veri App Group `group.com.fatihgocgun.okur`, `Shared/WidgetSnapshot.swift`,
  uygulama `WidgetFeed` ile yazar (küçük kapaklar dahil).

Sınanan: simülatörde ana sayfa, Kitaplık, İstatistik › Yol, `wisepath://road`, widget anlık görüntüsü ve kapaklar
yazıldı. iPhone'a **widget'sız** kuruldu: Xcode'da Apple hesabı yok ("No Accounts"), App Group ve widget için profil
alınamadı. Hesap eklenince `zsh telefona-kur.sh` tam sürümü kurar. Sınanmayan: widget'ların ekranda görünüşü,
hızlı eylemlerin telefonda.

### 2026-10-28 (gece) — mantıksal akış haritası (archify) ve ASD-STE100 açıklaması

Harita `Artifacts/wise-path-akis.html` (kaynak `docs/wisepath-flow.dataflow.json`, archify dataflow; 9/9 denetim,
0 hata, visual-check geçti). Açıklama `docs/FLOW-STE100.md` (ASD-STE100): bileşenler, ana akış, kayıt akışı, widget
akışı, aksama noktaları ve yordamları, giderilenler. Asıl aksama: telefonun iCloud'u kayıtları Mac'e yüklemiyor.
