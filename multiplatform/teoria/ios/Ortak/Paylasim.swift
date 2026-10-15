// Uygulama ↔ widget köprüsü (App Group kapsayıcısı).
//  · widget.json         — uygulamanın yazdığı anlık görüntü; widget yalnız okur, hesap yapmaz.
//  · widget-olaylar.jsonl — widget/bildirim düğmelerinin bıraktığı olaylar; uygulama açılınca kendi günlüğüne alır.
import Foundation

enum Paylasim {
    static let grup = "group.com.fatihgocgun.teoria"
    static let aforizmaTuru = "TeoriaAforizma"
    static let hatirlaTuru = "TeoriaHatirla"
    static let okumaTuru = "TeoriaOkuma"
    static let kurTuru = "TeoriaKur"

    static var kapsayici: URL {
        // Önizleme/sınama: gerçek kayda dokunmadan ayrı bir klasörle çalış.
        if let o = ProcessInfo.processInfo.environment["TEORIA_KAPSAYICI"] {
            let u = URL(fileURLWithPath: o, isDirectory: true)
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        #if os(iOS)
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) { return u }
        #endif
        // App Group imzalanamadıysa (imzasız derleme, Mac) uygulamanın kendi klasörüne düşer.
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Teoria", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }
    static var anlikURL: URL { kapsayici.appendingPathComponent("widget.json") }
    static var kutuURL: URL { kapsayici.appendingPathComponent("widget-olaylar.jsonl") }

    static let afoSira = "w.afo.sira"
    static let hatSira = "w.hat.sira"
    static let hatAcik = "w.hat.acik"

    static func oku() -> WidgetAnlik? {
        guard let v = try? Data(contentsOf: anlikURL) else { return nil }
        let c = JSONDecoder()
        c.dateDecodingStrategy = .iso8601
        return try? c.decode(WidgetAnlik.self, from: v)
    }

    static func yaz(_ a: WidgetAnlik) {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        if let v = try? c.encode(a) { try? v.write(to: anlikURL, options: .atomic) }
    }

    /// Widget ya da bildirim düğmesinin olayı. Satır satır eklenir; yarım satır okunurken atlanır.
    static func kutuyaAt(_ o: Olay) {
        let c = JSONEncoder()
        c.dateEncodingStrategy = .iso8601
        guard var v = try? c.encode(o) else { return }
        v.append(0x0A)
        var hata: NSError?
        NSFileCoordinator().coordinate(writingItemAt: kutuURL, options: .forMerging, error: &hata) { u in
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile(); h.write(v); try? h.close()
            } else {
                try? v.write(to: u)
            }
        }
    }

    /// Kutudaki olayları alır ve kutuyu boşaltır.
    static func kutuyuBosalt() -> [Olay] {
        var veri = Data()
        var hata: NSError?
        NSFileCoordinator().coordinate(writingItemAt: kutuURL, options: .forDeleting, error: &hata) { u in
            veri = (try? Data(contentsOf: u)) ?? Data()
            try? FileManager.default.removeItem(at: u)
        }
        return Gunluk.coz(veri).olaylar
    }
}

// MARK: - Widget anlık görüntüsü

struct WAforizma: Codable, Hashable, Identifiable {
    let id: String
    let metin: String
    let kaynak: String
    var renk: String
    var favori: Bool
    var isaret: Bool = false
    var ilgiEtiket: String? = nil   // "Bağlam" · "Kavram": alttaki kutu aynı fikrin devamı olsun, ayrı bir şey değil
    var ilgili: String? = nil
}

struct WHatirla: Codable, Hashable, Identifiable {
    let id: String          // FSRS kart anahtarı
    let soru: String
    var baglam: String?
    let cevap: String
    let kaynak: String
    var renk: String
    var ornek: String? = nil        // aynı kitaptan bir cümle: kavramın geçtiği yer
}

struct WKitap: Codable, Hashable, Identifiable {
    let id: String
    let baslik: String
    let yuzde: Int
    let isaret: Int
    var renk: String
    let suruyor: Bool
    let son: Date
}

struct WidgetAnlik: Codable {
    var guncel: Date
    var aforizmalar: [WAforizma]
    var hatirla: [WHatirla]
    var kitaplar: [WKitap]
    var bugunDakika: Double
    var hedefDakika: Int
    var hafta: [Double]
    var kademeler: [String: Int]
    var buHaftaKur: Int
    var isaretHafta: [Int]      // son 8 haftanın işaret sayısı
    var gundem: [String]        // bu ayın sık kelimeleri
    var gecmisteBugun: WAforizma?
    var oturmus: Int
    var toplamKavram: Int

    func kademe(_ h: Hat) -> Int { kademeler[h.rawValue] ?? 1 }

    static let ornek = WidgetAnlik(
        guncel: Date(),
        aforizmalar: [
            WAforizma(id: "a-2", metin: "İçeriksiz düşünceler boş, kavramsız sezgiler kördür.", kaynak: "Kant · Saf Aklın Eleştirisi", renk: "mavi", favori: true),
            WAforizma(id: "a-9", metin: "Dil varlığın evidir.", kaynak: "Heidegger · Hümanizm Üzerine Mektup", renk: "turuncu", favori: false),
        ],
        hatirla: [
            WHatirla(id: "hatirla:h-elaltinda", soru: "Şeyin kullanım içinde, işin içinde erimiş olarak verilmesi.", baglam: nil,
                     cevap: "el altında olmak", kaynak: "Heidegger: varlık sorusu", renk: "amber"),
            WHatirla(id: "hatirla:k-kopernik", soru: "Nesnelerin bilgi biçimimize uyduğu varsayımı.", baglam: nil,
                     cevap: "Kopernik devrimi", kaynak: "Kant ve aklın mahkemesi", renk: "mavi"),
        ],
        kitaplar: [
            WKitap(id: "zamanin-fiyati", baslik: "Zamanın Fiyatı", yuzde: 83, isaret: 15, renk: "amber", suruyor: true, son: Date()),
            WKitap(id: "kurucularin-kitapligi", baslik: "Kurucuların Kitaplığı", yuzde: 49, isaret: 8, renk: "indigo", suruyor: true, son: Date()),
            WKitap(id: "albert-camus-dusus", baslik: "Düşüş", yuzde: 41, isaret: 1, renk: "turuncu", suruyor: true, son: Date()),
            WKitap(id: "kiymet", baslik: "Kıymet", yuzde: 37, isaret: 11, renk: "mavi", suruyor: true, son: Date()),
        ],
        bugunDakika: 3.5, hedefDakika: 5, hafta: [5, 0, 5, 10, 0, 5, 3.5],
        kademeler: ["hatirla": 3, "donustur": 1, "kur": 2], buHaftaKur: 4,
        isaretHafta: [6, 12, 9, 22, 18, 11, 25, 14], gundem: ["kanıt", "varlık", "özgürlük", "teknik"],
        gecmisteBugun: WAforizma(id: "x", metin: "Anlama, Dasein'ın kendi imkânlarına doğru açık olmasıdır.",
                                 kaynak: "F1-26 Heidegger I · 27 Ağu", renk: "amber", favori: false, isaret: true),
        oturmus: 7, toplamKavram: 32)
}
