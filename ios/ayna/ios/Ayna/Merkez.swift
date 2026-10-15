// Uygulamanın tek durumu + vault eşitleme.
//   Vault'a (tek yazar telefon): telefon/ayna.json · telefon/ses/<id>.m4a
//   Vault'tan (Mac yazar):       mac/<id>.json (döküm · düzeltme · hatalar · sorular) · mac/ses/<id>.m4a (düzeltilmiş hâlin Kokoro sesi)
//   Kenar'la: atolye dolabından iş alır, düzeltilen İngilizce paragrafı geri yazar.
import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class Merkez: ObservableObject {
    static weak var paylasilan: Merkez?
    @Published var d = Depo.durumOku()
    @Published var kenarIsleri: [KenarIsi] = []
    @Published private(set) var bagli = false
    @Published private(set) var esitleniyor = false
    @Published private(set) var sonEsitleme: Date?
    @Published var hata: String?

    private var kok: URL?
    private let yerImiAnahtari = "ayna.kasa.yerimi"
    static let proje = "01 - English Learning/_projects/ayna"

    init() {
        if let v = ProcessInfo.processInfo.environment["AYNA_VAULT"] { kok = URL(fileURLWithPath: v); bagli = true }
        else if let v = Depo.ayar.data(forKey: yerImiAnahtari) {
            var eski = false
            if let u = try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &eski) { kok = u; bagli = true; if eski { yerImi(u) } }
        }
        kenarIsleri = Depo.kenarKuyrugu()
        Merkez.paylasilan = self
    }

    func klasorSecildi(_ url: URL) {
        let e = url.startAccessingSecurityScopedResource()
        defer { if e { url.stopAccessingSecurityScopedResource() } }
        yerImi(url); kok = url; bagli = true; hata = nil
        Task { await esitle() }
    }

    private func yerImi(_ u: URL) {
        if let v = try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) { Depo.ayar.set(v, forKey: yerImiAnahtari) }
    }

    func kaydet() {
        d.guncelleme = .now
        Depo.durumYaz(d)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: istemler
    var kapiBekleyen: [Date] { d.kapiIstemleri.filter { Date().timeIntervalSince($0) < 6 * 3600 } }
    func kapiIsteminiKapat(_ z: Date) { d.kapiIstemleri.removeAll { $0 == z }; kaydet() }

    /// Kenar'dan gelen, henüz anlatılmamış ya da düzeltilmemiş işler.
    var bekleyenKenar: [KenarIsi] {
        kenarIsleri.filter { x in !d.kayitlar.contains { $0.kenarIs == x.id && $0.duzeltme != nil } }
    }

    // MARK: kayıtlar
    func kayitEkle(_ k: Kayit) { d.kayitlar.append(k); kaydet(); Task { await vaultaYaz() } }

    func onDokum(_ id: String, _ metin: String) {
        guard let i = d.kayitlar.firstIndex(where: { $0.id == id }) else { return }
        d.kayitlar[i].onDokum = metin; kaydet()
    }

    func dinlendi(_ id: String) {
        guard let i = d.kayitlar.firstIndex(where: { $0.id == id }) else { return }
        d.kayitlar[i].dinlendi = true; kaydet()
    }

    func sil(_ id: String) {
        d.kayitlar.removeAll { $0.id == id }
        for f in [id + ".m4a", id + "-duz.m4a"] { try? FileManager.default.removeItem(at: Depo.sesKlasoru.appendingPathComponent(f)) }
        kaydet(); Task { await vaultaYaz() }
    }

    // MARK: eşitle
    struct MacSonuc: Codable, Sendable { var id: String; var dokum: String?; var duzeltme: String?; var hatalar: [Hata]?; var sorular: [Soru]? }

    func esitle() async {
        kenarIsleri = Depo.kenarKuyrugu()
        d = Depo.durumOku().birlesik(d)
        guard let kok, !esitleniyor else { return }
        esitleniyor = true
        defer { esitleniyor = false }
        await vaultaYaz()
        let bekleyen = d.kayitlar.filter { $0.duzeltme == nil || !$0.sesVar }.map(\.id)
        let ses = Depo.sesKlasoru
        let sonuc = await Task.detached { () -> Result<([String: MacSonuc], Set<String>), Error> in
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let k = Vault.kokBul(kok)
            guard FileManager.default.fileExists(atPath: k.appendingPathComponent("01 - English Learning").path) else {
                return .failure(NSError(domain: "Ayna", code: 1, userInfo: [NSLocalizedDescriptionKey: "Seçilen klasör vault değil."]))
            }
            let mac = k.appendingPathComponent(Merkez.proje + "/mac")
            var s: [String: MacSonuc] = [:]; var sesler = Set<String>()
            for id in bekleyen {
                let f = mac.appendingPathComponent(id + ".json")
                if Vault.indir(f, bekle: 2), let v = Vault.koordineliOku(f), let m = try? JSONDecoder().decode(MacSonuc.self, from: v) { s[id] = m }
                let a = mac.appendingPathComponent("ses/\(id).m4a")
                if Vault.indir(a, bekle: 3), let v = Vault.koordineliOku(a), v.count > 1000 {
                    try? v.write(to: ses.appendingPathComponent(id + "-duz.m4a")); sesler.insert(id)
                }
            }
            return .success((s, sesler))
        }.value
        switch sonuc {
        case .failure(let h): hata = h.localizedDescription
        case .success(let (s, sesler)):
            hata = nil
            for i in d.kayitlar.indices {
                let id = d.kayitlar[i].id
                if let m = s[id] {
                    d.kayitlar[i].dokum = m.dokum ?? d.kayitlar[i].dokum
                    d.kayitlar[i].duzeltme = m.duzeltme ?? d.kayitlar[i].duzeltme
                    if let h = m.hatalar, !h.isEmpty { d.kayitlar[i].hatalar = h }
                    if let q = m.sorular, !q.isEmpty { d.kayitlar[i].sorular = q }
                }
                if sesler.contains(id) { d.kayitlar[i].sesVar = true }
            }
            sonEsitleme = .now
        }
        kenaraDon()
        kaydet()
    }

    /// Düzeltilmiş Kenar anlatımları Kenar'ın dolabına: Kenar onları bölümün İngilizce sürümü olarak gösterir.
    private func kenaraDon() {
        let x = d.kayitlar.compactMap { k -> Depo.KenarDonus? in
            guard let is_ = k.kenarIs, let duz = k.duzeltme else { return nil }
            return Depo.KenarDonus(id: is_, ingilizce: duz, tarih: k.tarih)
        }
        if !x.isEmpty { Depo.kenaraDon(x) }
    }

    func vaultaYaz() async {
        guard let kok else { return }
        let durum = d
        let ses = Depo.sesKlasoru
        let tasinan = await Task.detached { () -> [String] in
            let e = kok.startAccessingSecurityScopedResource()
            defer { if e { kok.stopAccessingSecurityScopedResource() } }
            let k = Vault.kokBul(kok).appendingPathComponent(Merkez.proje)
            var t: [String] = []
            for x in durum.kayitlar where !x.vaultta {
                if let v = try? Data(contentsOf: ses.appendingPathComponent(x.id + ".m4a")),
                   Vault.koordineliYaz(v, k.appendingPathComponent("telefon/ses/\(x.id).m4a")) { t.append(x.id) }
            }
            var son = durum
            for i in son.kayitlar.indices where t.contains(son.kayitlar[i].id) { son.kayitlar[i].vaultta = true }
            if let v = try? Depo.kodlayici.encode(son) { _ = Vault.koordineliYaz(v, k.appendingPathComponent("telefon/ayna.json")) }
            return t
        }.value
        if !tasinan.isEmpty {
            for i in d.kayitlar.indices where tasinan.contains(d.kayitlar[i].id) { d.kayitlar[i].vaultta = true }
            kaydet()
        }
    }

    // MARK: akşam hatırlatması
    static func aksamBildirimi(_ saat: Int, _ dakika: Int, acik: Bool) {
        let m = UNUserNotificationCenter.current()
        m.removePendingNotificationRequests(withIdentifiers: ["ayna-aksam"])
        guard acik else { return }
        let c = UNMutableNotificationContent()
        c.title = "Ayna"
        c.body = "Gününden bir anı seç, 60 saniye İngilizce anlat."
        c.userInfo = ["rota": "ayna://bugun"]
        m.add(UNNotificationRequest(identifier: "ayna-aksam", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: saat, minute: dakika), repeats: true)))
    }
}

extension AynaDurum {
    /// Kapı uzantısının ortak dolaba yazdığı anları uygulamanın elindeki duruma katar (kayıtlar uygulamanındır).
    func birlesik(_ uygulama: AynaDurum) -> AynaDurum {
        var s = uygulama
        // saniyeye yuvarla: dosyaya yazılan tarih küsuratsız döner, aynı an iki kez sayılmasın
        s.kapiIstemleri = Array(Set((uygulama.kapiIstemleri + kapiIstemleri).map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) })).sorted()
        return s
    }
}

// MARK: vault dosya yardımcıları (Kenar'la aynı)
enum Vault {
    nonisolated static func kokBul(_ kok: URL) -> URL {
        var u = kok
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("01 - English Learning").path) { return u }
            u = u.deletingLastPathComponent()
        }
        return kok
    }

    nonisolated static func indir(_ u: URL, bekle: Double = 6) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: u.path), (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus != .notDownloaded { return true }
        try? fm.startDownloadingUbiquitousItem(at: u)
        var i = 0.0
        while i < bekle {
            let s = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            if s == .current || (s == nil && fm.fileExists(atPath: u.path)) { return true }
            Thread.sleep(forTimeInterval: 0.25); i += 0.25
        }
        return false
    }

    nonisolated static func koordineliOku(_ u: URL) -> Data? {
        var v: Data?; var h: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &h) { x in v = try? Data(contentsOf: x) }
        return v
    }

    nonisolated static func koordineliYaz(_ v: Data, _ u: URL) -> Bool {
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        var ok = false; var h: NSError?
        NSFileCoordinator().coordinate(writingItemAt: u, options: .forReplacing, error: &h) { x in ok = (try? v.write(to: x, options: .atomic)) != nil }
        return ok
    }
}

enum Haptik {
    static func hafif() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func secim() { UISelectionFeedbackGenerator().selectionChanged() }
    static func basari() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func uyari() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

extension Color {
    static let ayna = Color(red: 0.45, green: 0.78, blue: 0.95)
}
