# apple-apps çalışma kuralları

Bu repo, kullanıcının tüm iPhone ve Mac uygulamalarının tek merkezidir. Oturumlar farklı
makinelerde ve bulutta açılır; süreklilik yalnızca bu repo üzerinden sağlanır.

## Oturum başında
1. `HANDOFF.md` dosyasını oku (SessionStart hook'u zaten gösterir). "Şurada kaldık" kısmından devam et.
2. Çalıştığın dalı `git log` ile kontrol et; başka dalda yarım iş varsa kullanıcıya söyle.

## Oturum sonunda (her zaman)
1. `HANDOFF.md` içindeki "Şu an" ve "Sıradaki adımlar" bölümlerini güncelle.
2. Commit at ve push et. Push edilmemiş iş, başka makinede görünmez.
3. Yarım kalan iş varsa dalı ve ilgili uygulamayı HANDOFF.md'ye yaz.

## Kurallar
- Arayüz metinleri Türkçe kalır.
- `.gitignore` içindeki kişisel veri ve model dosyalarını ekleme.
- Mac uygulamaları Xcode projesi değil; `derle.sh` ile `swiftc` kullanılır. Bulut ortamı Linux'tur,
  bu yüzden Swift/Xcode derlemesi burada doğrulanamaz; "derlendi" deme, "derlenmedi, Mac'te doğrula" de.
- iOS uygulamaları `ios/<Uygulama>.xcodeproj` ile açılır.
