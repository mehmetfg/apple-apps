// Orkestra'nın iş mantığı. Uygulama ve widget aynı motoru çalıştırır; girdi = orkestra.json + şu an.
// Saat ilerledikçe hüküm değişir: Mac kapalıyken de bir sürecin "gecikti"ye düşmesi doğru anda görünür.
//
// Kurallar (Kılavuz ekranı bunları aynen anlatır):
//  1. Durum
//     uykuda    — kullanıcı kararıyla bekleyen hat (STATE "devam demeden üretilmez" vb.). Uyarı yok.
//     görünmüyor— süreç telefonda yaşıyor, vault'a iz bırakmıyor. Hüküm verilmez.
//     tıkalı    — beslendiği sabah görevi çıktı vermedi ya da birikme eşiği aşıldı (üretim tüketimi geçti).
//     aksıyor   — sessizlik > 2×ritim+1 gün.
//     gecikti   — sessizlik > ritim gün.
//     akıyor    — sessizlik ≤ ritim gün.
//     başlamadı — hiç iz yok.
//  2. Ağırlık = Yön Belgesi kademesi: ana 3 · destek 2 · hat 1,5 · bakım 1.
//  3. Hamle sırası (kullanıcı kararı: Yön Belgesi + birikme): tıkalı boru her zaman ilk (1000) >
//     ana odakta aksayan (+300) > ana odağa bugünkü dokunuş (+150) > aksama (sessizlik/ritim, en çok 6, × 10 × a).
//     Birikme eşiği aşıldıysa hamle "önce tüket" olur (40×a + bekleyen). Vade ≤7 gün +60, ≤3 gün +120. En çok 3 hamle.
//  4. Nabız = Σ a × puan / Σ a  (akıyor 1 · gecikti 0,6 · başlamadı 0,3 · aksıyor 0,2 · tıkalı 0,1).
//  5. Vade, seri, borç sayacı yok: kaçırılan gün hiçbir yerde birikmez; yalnız bugünün sessizliği görünür.
import Foundation

enum Durum: String, Codable, CaseIterable {
    case tikali, aksiyor, gecikti, baslamadi, akiyor, uykuda, gorunmuyor

    var ad: String {
        switch self {
        case .tikali: "tıkalı"
        case .aksiyor: "aksıyor"
        case .gecikti: "gecikti"
        case .baslamadi: "başlamadı"
        case .akiyor: "akıyor"
        case .uykuda: "uykuda"
        case .gorunmuyor: "görünmüyor"
        }
    }

    var puan: Double {
        switch self {
        case .akiyor: 1
        case .gecikti: 0.6
        case .baslamadi: 0.3
        case .aksiyor: 0.2
        case .tikali: 0.1
        case .uykuda, .gorunmuyor: 0
        }
    }

    /// Sıralama ağırlığı — kötüden iyiye.
    var sira: Int { Durum.allCases.firstIndex(of: self) ?? 0 }
    var sorunlu: Bool { self == .tikali || self == .aksiyor || self == .gecikti }
    var hukumVar: Bool { self != .uykuda && self != .gorunmuyor }

    var aciklama: String {
        switch self {
        case .tikali: "Akış bir yerde düğümlendi: besleyen sabah görevi çıktı vermedi ya da üretim tüketimi geçti."
        case .aksiyor: "Ritminin iki katından uzun süredir sessiz."
        case .gecikti: "Beklenen ritmi geçti; henüz kopmadı."
        case .baslamadi: "Hiç iz yok — kurulmuş ama ilk adım atılmamış."
        case .akiyor: "Ritminde ilerliyor."
        case .uykuda: "Senin kararınla bekliyor. Uyarı üretmez."
        case .gorunmuyor: "Telefonda yaşıyor ama vault'a iz bırakmıyor; hüküm verilemez."
        }
    }
}

struct Hukum: Identifiable, Equatable {
    var surec: Surec
    var durum: Durum
    var sessizlik: Int?          // son dokunuştan bugüne gün
    var neden: String            // tek cümle
    var agirlik: Double
    var bugunDokunuldu: Bool
    var vadeGun: Int?            // vadeye kalan gün
    var id: String { surec.id }
}

struct Hamle: Identifiable, Equatable {
    enum Tur: String { case onar, tuket, vade, dokun, surdur }
    var id: String
    var surecId: String
    var tur: Tur
    var baslik: String
    var neden: String
    var skor: Double
    var acilis: String?
    var acilisAd: String?
    var yer: String              // "iPhone" · "Mac"

    var fiil: String {
        switch tur {
        case .onar: "Onar"
        case .tuket: "Önce tüket"
        case .vade: "Vade yaklaşıyor"
        case .dokun: "Geri dön"
        case .surdur: "Bugünün işi"
        }
    }
}

struct Durumlar {
    var veri: OrkestraVeri
    var simdi: Date
    var hukumler: [Hukum]
    var hamleler: [Hamle]
    var nabiz: Int
    var veriYasi: TimeInterval   // orkestra.json kaç saniye önce üretildi

    var ilk3: [Hamle] { Array(hamleler.prefix(3)) }
    var aktif: [Hukum] { hukumler.filter { $0.durum.hukumVar } }
    var sorunlu: [Hukum] { hukumler.filter { $0.durum.sorunlu }.sorted { ($0.durum.sira, -$0.agirlik) < ($1.durum.sira, -$1.agirlik) } }
    var tikaliBorular: [Boru] { veri.borular.filter { $0.durum == "tikali" } }
    func hukum(_ id: String) -> Hukum? { hukumler.first { $0.id == id } }
    func say(_ d: Durum) -> Int { hukumler.filter { $0.durum == d }.count }
    var veriEski: Bool { veriYasi > 36 * 3600 }
}

enum Motor {
    static func agirlik(_ kademe: String) -> Double {
        switch kademe {
        case "ana": 3
        case "destek": 2
        case "hat": 1.5
        default: 1
        }
    }

    static func hukum(_ s: Surec, _ v: OrkestraVeri, _ simdi: Date) -> Hukum {
        let a = agirlik(s.kademe)
        let sessizlik = s.sonDokunus.map { max(0, Tarih.gunFarki($0, simdi)) }
        let vadeGun = s.vade?.gun.map { Tarih.gunFarki(simdi, $0) }
        let bugun = (sessizlik ?? 99) == 0
        func h(_ d: Durum, _ n: String) -> Hukum {
            Hukum(surec: s, durum: d, sessizlik: sessizlik, neden: n, agirlik: a, bugunDokunuldu: bugun, vadeGun: vadeGun)
        }
        if s.durdu { return h(.uykuda, s.durdu_neden.isEmpty ? "Kararını bekliyor." : s.durdu_neden) }
        if s.kaynak == "yok" && s.son == nil {
            return h(.gorunmuyor, s.ayrinti.first?.d ?? "Vault'ta izi yok.")
        }
        if let b = v.boru(s.boru), b.durum == "tikali", b.besler.contains(s.id) {
            return h(.tikali, "\(b.ad): \(b.not)")
        }
        if let bk = s.birikme, bk.asildi {
            return h(.tikali, "\(bk.bekleyen ?? 0) \(bk.birim) bekliyor (eşik \(bk.esik)). \(bk.not).")
        }
        guard let g = sessizlik else { return h(.baslamadi, "Henüz hiç iz yok.") }
        let r = max(1, s.ritim)
        let ritimMetni = r == 1 ? "her gün" : "\(r) günde bir"
        if g <= r { return h(.akiyor, bugun ? "Bugün dokunuldu." : g == 1 ? "Dün dokunuldu; ritim \(ritimMetni)." : "\(g) gün önce; ritim \(ritimMetni).") }
        if g <= 2 * r + 1 { return h(.gecikti, "\(g) gündür sessiz; ritim \(ritimMetni).") }
        return h(.aksiyor, "\(g) gündür sessiz; ritmin \(g / r) katı.")
    }

    static func hamleler(_ hk: [Hukum], _ v: OrkestraVeri) -> [Hamle] {
        var out: [Hamle] = []
        // 1. tıkalı borular — Mac'te onarılır
        for b in v.borular where b.durum == "tikali" {
            let hedef = b.besler.first.flatMap { id in hk.first { $0.id == id } }
            out.append(Hamle(id: "onar-\(b.id)", surecId: hedef?.id ?? b.besler.first ?? b.id, tur: .onar,
                             baslik: b.ad, neden: b.not, skor: 1000, acilis: nil, acilisAd: nil, yer: "Mac"))
        }
        let tikaliBoruHedefleri = Set(v.borular.filter { $0.durum == "tikali" }.flatMap(\.besler))
        for h in hk where h.durum.hukumVar {
            let s = h.surec
            let yer = s.acilis == nil ? "Mac" : "iPhone"
            var skor = 0.0
            var tur: Hamle.Tur = .surdur
            var baslik = s.ad
            var neden = h.neden
            if let bk = s.birikme, bk.asildi {
                tur = .tuket
                skor = 40 * h.agirlik + Double(min(bk.bekleyen ?? 0, 20))
                baslik = "\(s.ad): dinle, üretme"
                neden = "\(bk.bekleyen ?? 0) \(bk.birim). Yeni metin istemeden önce birini bitir."
            } else if tikaliBoruHedefleri.contains(s.id) {
                continue   // boru onarılınca kendiliğinden açılır; çift hamle yazılmaz
            } else if h.durum == .aksiyor || h.durum == .gecikti {
                tur = .dokun
                let oran = Double(h.sessizlik ?? 0) / Double(max(1, s.ritim))
                skor = min(oran, 6) * 10 * h.agirlik
                neden = "\(h.neden) Sırada: \(s.bugun)"
            } else if h.durum == .baslamadi {
                tur = .dokun
                skor = 12 * h.agirlik
                neden = "İlk adım: \(s.bugun)"
            } else if h.durum == .akiyor && !h.bugunDokunuldu && s.kademe == "ana" {
                tur = .surdur
                skor = 15 * h.agirlik + 150
                neden = "Ana odak — bugün henüz dokunulmadı. \(s.bugun)"
            }
            if s.kademe == "ana" && h.durum.sorunlu { skor += 300 }
            if let g = h.vadeGun, g >= 0, g <= 7 {
                skor += g <= 3 ? 120 : 60
                if tur == .surdur || skor < 40 { tur = .vade }
                neden = "Vade \(g == 0 ? "bugün" : "\(g) gün sonra"): \(s.vade?.olcut ?? ""). " + neden
            }
            guard skor > 0 else { continue }
            out.append(Hamle(id: "\(tur.rawValue)-\(s.id)", surecId: s.id, tur: tur, baslik: baslik, neden: neden,
                             skor: skor, acilis: s.acilis, acilisAd: s.acilis_ad, yer: yer))
        }
        return out.sorted { $0.skor > $1.skor }
    }

    static func hesapla(_ v: OrkestraVeri, simdi: Date = .now, ertelenen: Set<String> = []) -> Durumlar {
        let hk = v.surecler.map { hukum($0, v, simdi) }
        let aktif = hk.filter { $0.durum.hukumVar }
        let pay = aktif.reduce(0.0) { $0 + $1.agirlik * $1.durum.puan }
        let payda = aktif.reduce(0.0) { $0 + $1.agirlik }
        let nabiz = payda > 0 ? Int((pay / payda * 100).rounded()) : 0
        let hamle = hamleler(hk, v).filter { !ertelenen.contains($0.surecId) }
        let yas = v.uretimZamani.map { simdi.timeIntervalSince($0) } ?? .infinity
        return Durumlar(veri: v, simdi: simdi, hukumler: hk, hamleler: hamle, nabiz: nabiz,
                        veriYasi: yas)
    }

    /// Hiçbir şey değişmezse süreç hangi gün hangi duruma düşer? (önceden kurulan bildirimler için)
    static func gelecek(_ s: Surec, _ simdi: Date) -> [(Date, Durum)] {
        guard !s.durdu, let son = s.sonDokunus, s.birikme?.asildi != true else { return [] }
        let r = max(1, s.ritim)
        let t = Tarih.takvim
        var out: [(Date, Durum)] = []
        for (esik, d) in [(r + 1, Durum.gecikti), (2 * r + 2, .aksiyor)] {
            guard let gun = t.date(byAdding: .day, value: esik, to: t.startOfDay(for: son)),
                  let an = t.date(bySettingHour: 9, minute: 0, second: 0, of: gun), an > simdi else { continue }
            out.append((an, d))
        }
        return out
    }
}
