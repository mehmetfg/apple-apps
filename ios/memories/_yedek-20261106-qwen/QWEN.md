# Memories · telefonda paket üretimi (Qwen) — 2026-10-30

Karar: müfredatı Mac seçer, metni iPhone yazar. Qwen yalnız İngilizce yazar; Türkçe Apple Translation'dan (cihazda).

## Akış
1. Mac: `python3 hatlar/EN-01-orgu/gun.py brief --kurma --ileri --json`
   → `oncalisma/paket/gun-NNN/brief.json` + `oncalisma/paket/bilinen.json`. Ekran çıktısı eskisiyle aynı.
2. Mac → iPhone (kablo; telefonun iCloud'u vault'u eşitlemiyor):
   `python3 oncalisma/telefona_gonder.py` (brief'ler) · ilk kez `--model` (~1,08 GB) · `--kuru` deneme.
   Telefonda App Group: `qwen/brief/gun-NNN.json`, `qwen/brief/bilinen.json`, `qwen/model/`.
   Elle: `xcrun devicectl device copy to --device <id> --domain-type appGroupDataContainer --domain-identifier group.com.fatihgocgun.memories --source <dosya> --destination qwen/model/<dosya>`
   Model ayrıca Ayarlar › Telefonda üretim › «Modeli içe aktar» ile Dosyalar'dan alınabilir.
3. iPhone: Bugün › «Bugünün paketini telefonda üret».
   14 cümle, her cümleye kod hedef kelime + yapı verir. Her cümle denetlenir, tutmazsa en çok 3 kez yeniden yazılır.
   Sonra Türkçe (TranslationSession), anlatım (build_day şablonu, LLM yok) ve ses (AVSpeechSynthesizer → ses.m4a).
   Ses, satır zamanlarıyla `paket/gun-NNN/paket.json` olarak yazılır (surum `telefon-qwen`); Dinle, Oku ve widget değişmeden okur.
4. Geri: `telefona_gonder.py --cek NNN` → `oncalisma/paket/gun-NNN/telefon/` (gun.json = Tezgâh taslağı).

## Dosyalar
- `Ekranlar/Uretici.swift`: model yükleme, cümle cümle üretim, paket, ses.
- `Ekranlar/Denetci.swift`: derle_kurma + K3'ün Swift karşılığı. Gün 30, 35 ve 39'da Python'la aynı sonucu veriyor.
- `Ekranlar/UretEkrani.swift`: ilerleme (cümle n/N, tok/sn) ve çeviri.
- Bugün ve Ayarlar'a düğme ve model bölümü, `Depo.yerelYenile()`, `increased-memory-limit` entitlement.
- SwiftPM: mlx-swift-lm **3.31.4** (MLXLLM, MLXLMCommon) ve swift-transformers 1.3.5 (Tokenizers).
  3.32.3 kullanılamadı: mlx-swift ≥0.31.5, Swift tools 6.3 istiyor; bu Mac'te Xcode 26.3 (Swift 6.2) var.
  3.31.4 de qwen3_5'i destekliyor; bizim dönüştürdüğümüz ağırlıkta norm kaydırması yapmıyor (doğru davranış).

## Durum
- Derleme: generic iOS ✓ ve Simulator ✓ (imzasız). İmzalı derleme ✗: takım profilinde Increased Memory Limit yok.
  `-allowProvisioningUpdates` ile Apple hesabında App ID'ye bu yetenek eklenmeli (kullanıcı onayı gerekir).
- Cihazda hiç çalıştırılmadı. Qwen'in bu istemlerle cümle tutturma oranı, hız, bellek, çeviri kalitesi ve ses denenmedi.
- Bilinen sınırlar:
  - Tireli yeni kelime (so-called, make-up) yedekten değiştirilir; derle'nin KELIME_RE'si bunları hiç saymıyor.
  - Passive sayımı yalnız -ed/-en ortacı tanıyor.
  - K3 anlatımın tamamında ölçülür.
