# Tezgâh — iPhone uygulaması

Kuruluş: 2026-10-02 (kullanıcı isteği). Cümle, İdrak, İngilizce ve vault güncellemelerini
telefonda, telefona göre tasarlanmış yerli (SwiftUI) bir uygulamada izlemek için.

**Yeni sistem değil, salt okur.** Veri girişi, puan, yeni zamanlanmış iş yok. Uygulama vault'a
hiçbir şey yazmaz; Mac'in iCloud'a bıraktığı tek dosyayı okur. `mobil.html` (Kestirmeler +
Hızlı Bakış) yerinde duruyor, bu onun yerli uygulama hâli.

## Veri yolu

```
Mac: pano.py ──(arka planda)──▶ _pano/ios.py ──▶ Artifacts/_ortak/ios/tezgah.json  (+ kapak/*.jpg)
                                                        │ iCloud (Obsidian kapsayıcısı)
iPhone: Tezgâh.app ── ilk açılışta seçilen vault klasörü ─┘  → okur, gösterir
```

- `ios.py` pano'nun okuduğu her şeyi + vault taramasını (`_vault/sunucu.py` → `Dizin`),
  `_vault/hareket.jsonl`'u, CLAUDE.md §8 değişiklik günlüğünü, İngilizce/Felsefe `log.md`'lerini
  ve Kelime Eki defterini okur. Yalnız `_ortak/ios/`'a yazar. Bir bölüm okunamazsa yalnız o
  bölüm `{"hata": …}` olur.
- Ne zaman yenilenir: `pano.py` her koştuğunda (sabah görevleri, Tezgâh.app'te panoya geçiş) +
  Tezgâh.app açıkken 20 dakikada bir (`tezgah_sunucu.py` → `periyodik`). Elle:
  `python3 Artifacts/_pano/ios.py`
- Telefon: uygulamaya her dönüşte ve aşağı çekince yeniden okur. Mac kapalıyken son anı gösterir;
  36 saatten eskiyse uyarır.

## Ekranlar

| Sekme | İçerik |
|---|---|
| **Bugün** | 28 günlük etkinlik halkaları (Cümle · Mühendis · İdrak · Vault), sayfa sayfa kayan tezgâh kartları (Mühendis yarım sayfada açılır), vault'un bugünü, son dört hafta ısı satırları |
| **İngilizce** | Günün kartı, **dokununca 3B çevrilen cümle kartları** (Türkçe → İngilizce), yeni/yankı kelimeler, tutma grafiği, hata türleri, gramer yapıları (en zayıf önce), kelime deposu halkası, geçmiş günler (kendi paragrafın + yazımın), Kelime Eki, son kayıtlar |
| **İdrak** | Kayan kapak şeridi (ilerleme halkalı), günün işareti, biten raf; kitap odası: dinleme seyri, işaretler (bağlam açılır, uzun bas → kopyala), can alıcı cümleler, bölüm haritası |
| **Vault** | Köken halkası (sen / YZ / dış / belirsiz), 26 haftalık ısı haritası (dokun → o gün), son dokunulan notlar (süzgeç; uzun bas → Obsidian'da aç), bu haftanın alanları, değişiklik günlüğü |

Telefona özgü: alt sekme çubuğu, başparmakla kaydırılan şeritler (`scrollTargetBehavior`),
dokunsal geri bildirim (`sensoryFeedback`), alttan açılan sayfalar, aşağı çekip yenileme,
görününce dolan halkalar ve çubuklar, kayarken beliren kartlar. **Görünüm:** Otomatik · Açık · Gece (lacivert-siyah, ikonla uyumlu); her ekranın sağ üstünde ay/güneş düğmesiyle tek dokunuşta geçiş, seçim kalıcı (`@AppStorage("gorunum")`).

## Kurulum (bir kez)

1. Xcode lisansını onayla (Terminal): `sudo xcodebuild -license accept`
2. Xcode'da `Artifacts/_ortak/ios-app/Tezgah.swiftpm` klasörünü aç.
3. iPhone'u kabloyla bağla (ilk sefer: iPhone'da *Ayarlar › Gizlilik ve Güvenlik › Geliştirici
   Modu* açılır). Xcode'da sol üstte **Tezgâh** › hedef olarak iPhone'u seç.
4. *Signing & Capabilities* › Team: Apple kimliğin (Xcode › Settings › Accounts'tan eklenir).
5. ▶︎ (⌘R). İlk açılışta iPhone'da *Ayarlar › Genel › VPN ve Aygıt Yönetimi*'nden geliştiriciye güven.
6. Uygulamada **Vault klasörünü seç** → iCloud Drive › Obsidian › Personel Data Management › Aç.

**Ücretsiz Apple kimliğiyle** imzalanan uygulama 7 günde bir yeniden imza ister (iPhone bağlıyken
Xcode'da ▶︎). Ücretli geliştirici hesabıyla bir yıl.

## Simülatörde sınama

Simülatörde iCloud/Obsidian olmadığı için hata ayıklama derlemesi klasör seçmeden doğrudan
bir dosyadan yükleyebilir (yalnız `DEBUG`; telefondaki sürümü etkilemez):

    xcrun simctl launch <cihaz> com.fatihgocgun.tezgah -tezgahJSON "<vault>/Artifacts/_ortak/ios/tezgah.json"

2026-10-02'de iPhone 17 Pro (iOS 26.3) simülatöründe derlendi ve dört sekme, kart kaydırma,
cümle kartı çevirme ve kitap odası gerçek veriyle sınandı.

## Mac'te ön izleme (Xcode gerekmeden)

`zsh Artifacts/_ortak/ios-app/onizleme/calistir.sh` — kaynakları macOS için derler, gerçek
`tezgah.json` ile her ekranı `onizleme/ekran/` altına PNG çizer (açık + koyu). Derleme denetimi
olarak da kullanılır. Not: çizici yerli düğme/seçicileri sarı kutu olarak gösterir, kaydırma
şeritlerinin ilk üç ögesini düz dizer — telefonda ikisi de normaldir.

## Dosyalar

| Yer | Ne |
|---|---|
| `Tezgah.swiftpm/Package.swift` | Uygulama paketi (iOS 17+, yalnız iPhone, dikey) |
| `ikon.swift` | Mavi/siyah iPhone ikonunu çizer → `Assets.xcassets/AppIcon.appiconset/ikon-1024.png` (2026-10-02, kullanıcı isteği; Mac uygulamasının kum rengi ikonu ayrı, `../app/ikon.swift`) |
| `Kaynak/Model.swift` | `tezgah.json` modeli — her alan isteğe bağlı |
| `Kaynak/VeriDeposu.swift` | Klasör yer imi, iCloud indirme, koordineli okuma, kapaklar |
| `Kaynak/Tema.swift` | Renkler (pano CSS'iyle aynı), kart, halka, çubuk, ısı satırı, şerit |
| `Kaynak/TezgahApp.swift` | Uygulama, sekmeler, ekran kabuğu, ayarlar |
| `Kaynak/Kurulum.swift` · `BugunEkrani` · `IngilizceEkrani` · `IdrakEkrani` · `VaultEkrani` | Ekranlar |
| `../../_pano/ios.py` | Veri üreticisi |

Bir tezgâhın veri biçimi değişirse düzeltilecek yer `ios.py`'deki o bölümün fonksiyonudur;
uygulama bilinmeyen alanı yok sayar, eksik alanı "—" gösterir.
