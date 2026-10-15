// Depo + eşitleme uçtan uca sınaması (geçici vault, geçici kapsayıcı). zsh mac/sina2.sh
import Foundation
import SwiftUI

var hata = 0
func dogrula(_ k: Bool, _ m: String) { print(k ? "✓" : "✗", m); if !k { hata += 1 } }

@main enum Sina {
    static func main() async {
        let vault = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEORIA_VAULT"]!)
        let kap = Paylasim.kapsayici
        let fm = FileManager.default

        // Öteki cihazlar: ev Mac'i + iCloud çakışma kopyası (aynı olayı tekrar taşıyor)
        var ev = Olay(tur: .favori, hedef: "a-9", deger: true); ev.cihaz = "mac-ev"; ev.t = Date().addingTimeInterval(-3600)
        var evKur = Olay(tur: .yerIsareti, hedef: "a-1", deger: true); evKur.cihaz = "mac-ev"
        try! Gunluk.yaz([ev, evKur], vault.appendingPathComponent("ilerleme/mac-ev.jsonl"))
        try! Gunluk.yaz([ev], vault.appendingPathComponent("ilerleme/mac-ev 2.jsonl"))

        // Widget/bildirim kutusu: uygulama kapalıyken basılmış iki düğme
        Paylasim.kutuyaAt(Olay(tur: .cevap, hedef: "hatirla:k-apriori", hat: .hatirla, puan: 1, not: 3, rol: "widget"))
        Paylasim.kutuyaAt(Olay(tur: .kendiCumle, hedef: "k-apriori", metin: "Deneyimden önce gelen bilgi."))

        // Yarım kalmış kür (40 dk önce, kapanış yok)
        let yarimId = UUID().uuidString
        var y = Olay(tur: .cevap, hedef: "kur:c-k1", hat: .kur, kademe: 1, puan: 1, kurId: yarimId)
        y.t = Date().addingTimeInterval(-2400)
        try! Gunluk.yaz([y], kap.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl"))

        let depo = await Depo()
        await MainActor.run {
            dogrula(depo.olaylar.contains { $0.rol == "widget" }, "widget kutusundaki olay günlüğe alındı")
            dogrula(!fm.fileExists(atPath: Paylasim.kutuURL.path), "kutu boşaltıldı")
            dogrula(depo.durum.kurlar.contains { $0.id == yarimId }, "yarım kalan kür 30 dk sonra kendiliğinden kapandı (sayıldı)")
            dogrula(depo.durum.kendiCumleler.count == 1, "bildirimden yazılan kendi cümle akışta")
        }
        // Ses notu: yerel dosya → vault
        let sesAd = "2026-10-05-deneme.m4a"
        try! fm.createDirectory(at: depo.sesKlasoru, withIntermediateDirectories: true)
        try! Data(repeating: 7, count: 2048).write(to: depo.sesKlasoru.appendingPathComponent(sesAd))
        await MainActor.run { depo.ekle(Olay(tur: .sesNot, hedef: "a-2", metin: sesAd, sure: 12)) }
        // Değerlendirme Mac hattından gelmiş gibi
        try! fm.createDirectory(at: vault.appendingPathComponent("ses/degerlendirme"), withIntermediateDirectories: true)
        try! fm.createDirectory(at: vault.appendingPathComponent("ses/dokum"), withIntermediateDirectories: true)
        try! #"{"ozet":"Kant'ın iki kutbunu doğru kurdun.","guclu":["boş/kör karşıtlığı"],"eksik":["sezgi kavramı"],"hatirlama":4,"yorum":3}"#
            .write(to: vault.appendingPathComponent("ses/degerlendirme/2026-10-05-deneme.json"), atomically: true, encoding: .utf8)
        try! "İçeriksiz düşünce boştur demek…".write(to: vault.appendingPathComponent("ses/dokum/2026-10-05-deneme.txt"), atomically: true, encoding: .utf8)

        await depo.esitleSimdi()
        await MainActor.run {
            dogrula(depo.durum.favoriler.contains("a-9"), "ev Mac'inin favorisi bu cihaza geldi")
            dogrula(depo.olaylar.filter { $0.id == ev.id }.count == 1, "çakışma kopyasındaki olay bir kez sayıldı")
            let benim = Gunluk.oku(vault.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl")).olaylar
            dogrula(benim.count >= 4 && benim.allSatisfy { $0.cihaz == Cihaz.ad || $0.rol == "widget" || $0.tur == .kendiCumle }, "bu cihazın günlüğü vault'a yazıldı (\(benim.count) olay)")
            dogrula(fm.fileExists(atPath: vault.appendingPathComponent("ses/\(sesAd)").path), "ses notu vault'a kopyalandı")
            let b = depo.sesler.values.first
            dogrula(b?.vaultta == true && b?.dokum != nil && b?.degerlendirme?.hatirlama == 4, "döküm ve değerlendirme uygulamaya döndü")
            let a = depo.anlik()
            dogrula(!a.aforizmalar.isEmpty && !a.hatirla.isEmpty && !a.kitaplar.isEmpty, "widget anlık görüntüsü dolu (\(a.aforizmalar.count) aforizma · \(a.hatirla.count) hatırla · \(a.kitaplar.count) kitap)")
            dogrula(a.isaretHafta.count == 8, "son 8 haftanın işaret grafiği hazır")
        }
        // Yerel kayıt kaybolursa (yeniden kurulum): vault'tan geri gelir
        try? fm.removeItem(at: kap.appendingPathComponent("ilerleme/\(Cihaz.ad).jsonl"))
        let depo2 = await Depo()
        await depo2.esitleSimdi()
        await MainActor.run {
            dogrula(depo2.durum.sesNotlari.count == 1 && depo2.durum.kurlar.contains { $0.id == yarimId }, "yerel kayıt silindi → vault'tan geri yüklendi")
        }
        print(hata == 0 ? "\nHEPSİ GEÇTİ" : "\n\(hata) BAŞARISIZ")
        exit(hata == 0 ? 0 : 1)
    }
}
