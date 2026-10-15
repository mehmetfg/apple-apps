import Foundation

/// Hazır ses ayarı. Gruplar cihazlara göre: Cowon JetEffect, Sony Walkman, Tını'nın kendi ayarları.
struct Hazir: Identifiable, Hashable {
    enum Grup: String, CaseIterable { case tini = "Tını", cowon = "Cowon JetEffect", sony = "Sony Walkman", tur = "Tür EQ" }
    let ad: String
    let grup: Grup
    let ayar: SesAyari
    var id: String { ad }
    static func == (a: Hazir, b: Hazir) -> Bool { a.ad == b.ad }
    func hash(into h: inout Hasher) { h.combine(ad) }

    static func yap(_ ad: String, _ grup: Grup, _ f: (inout SesAyari) -> Void) -> Hazir {
        var a = SesAyari()
        f(&a)
        return Hazir(ad: ad, grup: grup, ayar: a)
    }

    static func eq(_ ad: String, _ d: [Float]) -> Hazir { yap(ad, .tur) { $0.grafik = d } }

    static let hepsi: [Hazir] = [
        yap("Normal", .tini) { _ in },
        yap("Kitap altında", .tini) {
            // Konuşmanın oturduğu 1-4 kHz'e yer açar, dinamiği sıkar (müzik ani yükselip sesi örtmesin), sahneyi açar.
            $0.grafik = [1, 1, 0, -1, -2, -4, -5, -3, 0, 1]
            $0.dengeleyici = true; $0.genislik = 1.4; $0.surround = 2
        },
        yap("Hi-Fi saflık", .tini) { $0.eqAcik = false; $0.otomatikBosluk = false },
        yap("Gece", .tini) { $0.dengeleyici = true; $0.grafik = [-2, -1, 0, 0, 0, 0, 0, -1, -2, -2]; $0.crossfeed = 4 },
        yap("Canlılık", .tini) { $0.maximizer = true; $0.maxBas = 4; $0.maxNetlik = 5; $0.tiz = 3; $0.genislik = 1.2; $0.psikoBas = 3 },

        yap("BBE", .cowon) { $0.maximizer = true; $0.maxBas = 5; $0.maxNetlik = 5 },
        yap("BBE ViVA", .cowon) { $0.maximizer = true; $0.maxBas = 6; $0.maxNetlik = 6; $0.surround = 4; $0.genislik = 1.2 },
        yap("BBE Mach3Bass", .cowon) { $0.maximizer = true; $0.maxBas = 4; $0.maxNetlik = 5; $0.bas = .mach3; $0.basSeviye = 6; $0.basFrekans = 60 },
        yap("BBE Headphone", .cowon) { $0.maximizer = true; $0.maxBas = 4; $0.maxNetlik = 5; $0.crossfeed = 5 },
        yap("Mach3Bass", .cowon) { $0.bas = .mach3; $0.basSeviye = 7; $0.basFrekans = 60 },
        yap("MP Enhance", .cowon) { $0.tiz = 6 },
        yap("3D Surround", .cowon) { $0.surround = 6 },
        yap("Wide", .cowon) { $0.genislik = 1.6 },
        yap("Reverb Hall", .cowon) { $0.yanki = .salon; $0.yankiSeviye = 5 },

        yap("ClearAudio+", .sony) { $0.maximizer = true; $0.maxBas = 3; $0.maxNetlik = 4; $0.tiz = 5; $0.bas = .megaBass; $0.basSeviye = 3 },
        yap("Mega Bass", .sony) { $0.bas = .megaBass; $0.basSeviye = 6 },
        yap("Groove", .sony) { $0.bas = .groove; $0.basSeviye = 6 },
        yap("ClearBass", .sony) { $0.bas = .mach3; $0.basSeviye = 5; $0.basFrekans = 45; $0.psikoBas = 3 },
        yap("DSEE HX", .sony) { $0.tiz = 7 },
        yap("VPT Stüdyo", .sony) { $0.yanki = .studyo },
        yap("VPT Kulüp", .sony) { $0.yanki = .kulup },
        yap("VPT Konser salonu", .sony) { $0.yanki = .salon },
        yap("VPT Arena", .sony) { $0.yanki = .arena },
        yap("Dynamic Normalizer", .sony) { $0.dengeleyici = true },

        eq("Rock", [5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
        eq("Pop", [-1, 1, 3, 4, 3, 1, -1, -1, -1, -1]),
        eq("Jazz", [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]),
        eq("Klasik", [0, 0, 0, 0, 0, 0, -2, -3, -3, -4]),
        eq("Balad", [2, 2, 1, 0, 1, 2, 2, 1, 0, 0]),
        eq("Kulüp", [0, 0, 3, 4, 4, 4, 3, 0, 0, 0]),
        eq("Funk", [4, 3, 0, -1, 0, 2, 3, 2, 2, 2]),
        eq("Hip Hop", [6, 5, 2, 0, -1, -1, 1, 0, 2, 3]),
        eq("Techno", [5, 4, 0, -3, -2, 0, 4, 5, 5, 4]),
        eq("Blues", [2, 3, 2, 0, -1, 0, 2, 1, 0, -1]),
        eq("Metal", [4, 3, 2, 0, -2, -1, 2, 4, 5, 4]),
        eq("Vokal", [-3, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        eq("Dans", [6, 5, 2, 0, 0, -2, -3, -3, 0, 0]),
        eq("Bas + tiz", [5, 4, 0, -4, -3, 1, 5, 7, 8, 8]),
    ]
}

/// Geçerli ses ayarı, seçili hazır ad ve dört kullanıcı yuvası. Her değişiklik anında `Zincir`e gider ve saklanır.
@MainActor
final class Ses: ObservableObject {
    static let shared = Ses()

    @Published var ayar: SesAyari {
        didSet {
            guard ayar != oldValue else { return }
            zincir?.ayarla(ayar)
            var once = oldValue
            once.atla = ayar.atla   // A/B düğmesi ayarı "Özel" yapmaz
            if !uyguluyor, once != ayar, ad != "Özel" { ad = "Özel" }
            kaydet()
        }
    }
    /// Seçili hazır ya da kullanıcı yuvasının adı; elle değişince "Özel".
    @Published private(set) var ad: String
    @Published private(set) var yuvalar: [SesAyari?]

    weak var zincir: Zincir? { didSet { zincir?.ayarla(ayar) } }
    private var uyguluyor = false

    private init() {
        let d = UserDefaults.standard
        ayar = d.data(forKey: "sesAyari").flatMap { try? JSONDecoder().decode(SesAyari.self, from: $0) } ?? SesAyari()
        ad = d.string(forKey: "sesAdi") ?? "Normal"
        yuvalar = d.data(forKey: "sesYuvalari").flatMap { try? JSONDecoder().decode([SesAyari?].self, from: $0) }
            ?? Array(repeating: nil, count: 4)
    }

    /// Hazırı uygular; kişisel kalıcı ayarlar (denge, ReplayGain, otomatik boşluk) korunur.
    func uygula(_ h: Hazir) { yukle(h.ayar, ad: h.ad, kisiselKalsin: true) }

    func yuvadanYukle(_ i: Int) {
        guard let a = yuvalar[i] else { return }
        yukle(a, ad: "Kullanıcı \(i + 1)", kisiselKalsin: false)
    }

    func yuvayaKaydet(_ i: Int) {
        var a = ayar
        a.atla = false
        yuvalar[i] = a
        if let v = try? JSONEncoder().encode(yuvalar) { UserDefaults.standard.set(v, forKey: "sesYuvalari") }
        ad = "Kullanıcı \(i + 1)"
        UserDefaults.standard.set(ad, forKey: "sesAdi")
    }

    func abDegistir() { ayar.atla.toggle() }

    private func yukle(_ yeni: SesAyari, ad yeniAd: String, kisiselKalsin: Bool) {
        var y = yeni
        if kisiselKalsin {
            y.denge = ayar.denge
            y.replayGain = ayar.replayGain
            if yeniAd != "Hi-Fi saflık" { y.otomatikBosluk = ayar.otomatikBosluk }
            y.onKazanc = ayar.onKazanc
        }
        y.atla = false
        uyguluyor = true
        ayar = y
        uyguluyor = false
        ad = yeniAd
        UserDefaults.standard.set(ad, forKey: "sesAdi")
    }

    private func kaydet() {
        if let v = try? JSONEncoder().encode(ayar) { UserDefaults.standard.set(v, forKey: "sesAyari") }
        UserDefaults.standard.set(ad, forKey: "sesAdi")
    }
}
