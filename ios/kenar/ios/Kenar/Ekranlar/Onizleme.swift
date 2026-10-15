// Yalnız DEBUG: simülatörde ekran sınaması. Başlatma argümanları:
//   -sekme <0…4>         açılış sekmesi          -bolum <b1…b5>   Metin'de bölüm aç
//   -harita <0…2>        Harita yakınlığı (Rota üstünden)   -ornekDoldur  ilk sınama için örnek ilerleme kurar
// Vault: KENAR_VAULT ortam değişkeni (geçici bir vault kopyası) — gerçek vault'a sınamada yazılmaz.
#if DEBUG
import SwiftUI

enum Onizleme {
    @MainActor static func baslat(_ m: Merkez, _ r: Rota) {
        let a = CommandLine.arguments
        func deger(_ ad: String) -> String? { a.firstIndex(of: ad).flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }
        Task {
            if m.d.metin == nil { await m.esitle() }
            if a.contains("-ornekDoldur") { doldur(m) }
            if let s = deger("-sekme"), let i = Int(s) { r.sekme = i }
            if let b = deger("-bolum") { r.bolum = b }
            if let h = deger("-haritaBolum") { r.git("kenar://harita/\(h)") }
        }
    }

    /// Kutu'daki ilgili işaretlerden birkaçını bölümlere dağıtır, §1'e kısa bir paragraf yazar — ekranlar dolu görünsün.
    @MainActor static func doldur(_ m: Merkez) {
        guard let metin = m.d.metin, m.d.isaretler.allSatisfy({ $0.bolum == nil }) else { return }
        let adaylar = m.d.kutu.sorted { Ilgi.puan($0.metin, metin) > Ilgi.puan($1.metin, metin) }
        for (i, x) in adaylar.prefix(7).enumerated() {
            let b = Ilgi.oneri(x.metin, metin)?.id ?? metin.bolumler[i % 5].id
            m.ata(x.id, b)
            m.rol(x.id, [Rol.oncul, .sonuc, .itiraz, .ornek, nil][i % 5])
        }
        if var b = metin.bolumler.first {
            b.paragraf = "Kant'tan önce felsefe bilmeyi bir uyum meselesi olarak düşündü. Zihin, dışarıdaki nesneyi olduğu gibi yansıtan bir aynaydı; bilgi doğruysa ayna temizdi, yanlışsa buğulu. Aristoteles'ten rasyonalistlere kadar soru hep aynı yöne bakıyordu: zihin nesneye nasıl uyar?"
            m.bolumGuncelle(b)
            m.bolumBitti(b.id, false)
        }
        m.oturumBaslat(kitap: KitapKaydi(id: "kagit-krv", ad: "Saf Aklın Eleştirisi", yazar: "Immanuel Kant", kagit: true), soru: "Kant neden 'Kopernik' diyor?")
        m.isaretEkle("Şimdiye kadar bütün bilgimizin nesnelere uyması gerektiği kabul edildi.", kaynak: .kamera)
    }
}
#endif
