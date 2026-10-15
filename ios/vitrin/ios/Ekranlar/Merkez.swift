// Uygulamanın tek durumu: içerik + tasarımlar + vault bağlantısı. Her değişiklik App Group'a yazılır, widget'lar yenilenir.
import SwiftUI
import WidgetKit

@MainActor
final class Merkez: ObservableObject {
    @Published var veri: VitrinVeri
    @Published var kayit: Tasarimlar
    @Published var bagli = false
    @Published var klasorAdi = ""
    @Published var duyuru: String?
    @Published var yukleniyor = false

    private let anahtar = "vaultYerImi"
    private var kok: URL?

    var bilinen: Set<String> { Set(kayit.bilinen) }

    init() {
        Merkez.gomuluyuYerlestir()
        veri = Depo.veriOku() ?? .bos
        if let k = Depo.tasarimOku() {
            kayit = k
        } else {
            kayit = Varsayilan.tasarimlar()
            Depo.tasarimYaz(kayit)
        }
        if let v = Depo.ayar.data(forKey: anahtar) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) {
                kok = u; bagli = true; klasorAdi = u.lastPathComponent
                if eski { yerImi(u) }
            }
        }
    }

    /// Uygulamaya gömülü vitrin.json, App Group'takinden yeniyse onu koyar (kurulumla gelen tazelik)
    private static func gomuluyuYerlestir() {
        let aday = Bundle.main.url(forResource: "vitrin", withExtension: "json")
            ?? Bundle.main.url(forResource: "vitrin", withExtension: "json", subdirectory: "Veri")
        guard let u = aday, let d = try? Data(contentsOf: u),
              let g = try? JSONDecoder().decode(VitrinVeri.self, from: d) else { return }
        if let mevcut = Depo.veriOku(), mevcut.uretildi >= g.uretildi { return }
        Depo.veriYaz(d)
    }

    func kaydet() {
        Depo.tasarimYaz(kayit)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func duyur(_ s: String) {
        withAnimation(.spring) { duyuru = s }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            withAnimation(.easeOut) { if duyuru == s { duyuru = nil } }
        }
    }

    // MARK: içerik

    func gosterilen(_ d: Duvar, tarih: Date = .now) -> Gosterilen {
        Gosterilen.hesapla(d.icerik, veri: veri, tarih: tarih, adim: 0, bilinen: bilinen, metin: d.metin)
    }

    func gosterilen(_ w: WidgetTasarim, tarih: Date = .now) -> Gosterilen {
        Gosterilen.hesapla(w.icerik, veri: veri, tarih: tarih, adim: Secici.dilim(tarih, dongu: w.dongu) + Depo.ileri(w.id),
                           bilinen: bilinen, metin: w.metin)
    }

    func biliyorum(_ w: String) {
        guard !kayit.bilinen.contains(w) else { return }
        kayit.bilinen.append(w)
        kaydet()
        duyur("“\(w)” bir daha çıkmayacak")
    }

    func bilinenSil(_ w: String) {
        kayit.bilinen.removeAll { $0 == w }
        kaydet()
    }

    // MARK: duvarlar

    func gunlukDuvar(_ tarih: Date = .now) -> Duvar? { GunlukSecim.duvar(kayit, tarih) }

    func kaydet(_ d: Duvar) {
        var d = d
        d.guncellendi = .now
        if let i = kayit.duvarlar.firstIndex(where: { $0.id == d.id }) { kayit.duvarlar[i] = d } else { kayit.duvarlar.insert(d, at: 0) }
        kaydet()
    }

    func sil(_ d: Duvar) {
        kayit.duvarlar.removeAll { $0.id == d.id }
        kayit.gunlukListe.removeAll { $0 == d.id }
        kaydet()
    }

    func gunlukte(_ d: Duvar) -> Bool { kayit.gunlukListe.contains(d.id) }

    func gunlukDegistir(_ d: Duvar) {
        if gunlukte(d) { kayit.gunlukListe.removeAll { $0 == d.id } } else { kayit.gunlukListe.append(d.id) }
        kaydet()
    }

    // MARK: widget tasarımları

    func kaydet(_ w: WidgetTasarim) {
        var w = w
        w.guncellendi = .now
        if let i = kayit.widgetlar.firstIndex(where: { $0.id == w.id }) { kayit.widgetlar[i] = w } else { kayit.widgetlar.insert(w, at: 0) }
        kaydet()
    }

    func sil(_ w: WidgetTasarim) {
        kayit.widgetlar.removeAll { $0.id == w.id }
        kaydet()
    }

    // MARK: tema

    func uygula(_ t: Tema) {
        let d = t.duvar()
        kayit.duvarlar.insert(d, at: 0)
        kayit.widgetlar.insert(contentsOf: t.widgetlar(), at: 0)
        kayit.gunlukListe = [d.id]
        kaydet()
        duyur("\(t.ad) eklendi · günün duvarı oldu")
    }

    func uygula(duvar d: Duvar, widgetlar w: [WidgetTasarim]) {
        kayit.duvarlar.insert(d, at: 0)
        kayit.widgetlar.insert(contentsOf: w, at: 0)
        kayit.gunlukListe = [d.id]
        kaydet()
    }

    // MARK: vault

    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImi(url)
        kok = url; bagli = true; klasorAdi = url.lastPathComponent
        Task { await tazele() }
    }

    func unut() {
        Depo.ayar.removeObject(forKey: anahtar)
        kok = nil; bagli = false; klasorAdi = ""
    }

    private func yerImi(_ url: URL) {
        if let v = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            Depo.ayar.set(v, forKey: anahtar)
        }
    }

    func tazele(sessiz: Bool = false) async {
        guard let kok else { return }
        yukleniyor = true
        defer { yukleniyor = false }
        let sonuc: Data? = await Task.detached {
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let adaylar = ["_araçlar/vitrin/durum/vitrin.json", "vitrin/durum/vitrin.json", "durum/vitrin.json", "vitrin.json"]
            for a in adaylar {
                let u = kok.appendingPathComponent(a)
                var hata: NSError?
                var veri: Data?
                // iCloud dosyası henüz inmemişse koordinatör indirmeyi bekler
                NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &hata) { veri = try? Data(contentsOf: $0) }
                if let veri { return veri }
            }
            return nil
        }.value
        guard let d = sonuc, Depo.veriYaz(d), let v = Depo.veriOku() else {
            if !sessiz { duyur("vitrin.json bulunamadı — Personel Data Management klasörünü seç") }
            return
        }
        veri = v
        WidgetCenter.shared.reloadAllTimelines()
        if !sessiz { duyur("İçerik tazelendi · \(v.kelimeler.count) kelime") }
    }
}

/// Kestirme ve uygulama aynı kuralla seçer: günlük listedeki tasarımlar gün gün sırayla
enum GunlukSecim {
    static func duvar(_ k: Tasarimlar, _ tarih: Date) -> Duvar? {
        let liste = k.gunlukListe.compactMap { id in k.duvarlar.first { $0.id == id } }
        if liste.isEmpty { return k.duvarlar.first }
        return liste[Secici.gunNo(tarih) % liste.count]
    }
}
