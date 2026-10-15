// Bir çalışma turu: en çok 5 yeni + 15 tekrar (~4 dakika).
//
// Yöntem (araştırmanın en sağlam üç bulgusu):
//  1. Geri çağırma pratiği — kelimeyi tanıtıp bırakmak yerine birkaç soru sonra sor (testing effect).
//  2. Aralıklı tekrar — FSRS her kelimeyi unutmak üzereyken geri getirir (spacing effect).
//  3. Zorlaşan çağırma — kelime oturdukça soru tanımadan üretmeye kayar:
//       Tanışma: İngilizce → Türkçe seç · dinleyip seç
//       Aşina:   cümlede boşluğu doldur · Türkçeden yaz
//       Oturmuş: Türkçeden yaz · kendin değerlendir
//  Yanlış cevap aynı turda üç soru sonra başka biçimde yeniden gelir.
import Foundation
import SwiftUI

enum SoruTuru: String {
    case tanit, anlam, dinle, bosluk, yaz, hatirla, parcacik

    var baslik: String {
        switch self {
        case .tanit: return "Yeni kelime"
        case .anlam: return "Anlamı hangisi?"
        case .dinle: return "Dinle — hangi kelime?"
        case .bosluk: return "Boşluğa hangisi gelir?"
        case .yaz: return "İngilizcesini yaz"
        case .hatirla: return "Hatırlıyor musun?"
        case .parcacik: return "Hangi parçacık?"
        }
    }
}

struct Soru: Identifiable, Equatable {
    let id = UUID()
    let kelime: Kelime
    let tur: SoruTuru
    var secenekler: [Kelime] = []
    var ilkKarsilasma = false     // tanıtımdan sonraki ilk soru → FSRS kartı burada doğar
    var yineleme = false
    /// Parçacık sorusu: parçacığı boşaltılmış cümle ve seçenekler (take off ↔ take on ↔ take up)
    var bosCumle: String? = nil
    var parcacikSec: [String] = []
}

@MainActor
final class Oturum: ObservableObject {
    @Published private(set) var sira: [Soru] = []
    @Published private(set) var konum = 0
    @Published private(set) var cevap: Cevap?
    @Published var bitti = false

    struct Cevap: Equatable {
        let dogru: Bool
        var not: Not
        let verilen: String?
        let yakin: Bool       // yazımda bir harf farkı
    }

    let baslangic = Date()
    private var soruBas = Date()
    private(set) var sonuc: [String: Bool] = [:]          // kelime → ilk denemede doğru mu
    private(set) var yeniSayisi = 0
    private(set) var biliyorumDenen: [Kelime] = []
    private weak var depo: Depo?

    init(depo: Depo, yeniler: [Kelime], tekrarlar: [Kelime]) {
        self.depo = depo
        // En çok 5 yeni: en az 2'si deyimsel fiil olsun (varsa) — aksi hâlde kelimeler sırayı hep yutar.
        let pvler = Array(yeniler.filter(\.isPV).prefix(2))
        var secim = Array(yeniler.filter { !$0.isPV }.prefix(5 - pvler.count))
        for (i, p) in pvler.enumerated() { secim.insert(p, at: min(secim.count, 2 + i * 2)) }
        kur(secim, Array(tekrarlar.prefix(15)))
    }

    var soru: Soru? { konum < sira.count ? sira[konum] : nil }
    var ilerleme: Double { sira.isEmpty ? 0 : Double(konum) / Double(sira.count) }

    // MARK: Kurgu

    private func kur(_ yeniler: [Kelime], _ tekrarlar: [Kelime]) {
        guard let depo else { return }
        yeniSayisi = yeniler.count
        var tekrar = tekrarlar.map { k in soruYap(k, turSec(k, depo.kart(k))) }.shuffled()
        var bekleyen: [Soru] = []
        var out: [Soru] = []
        // Tanıt → araya 1-2 başka soru → aynı kelimeyi sor.
        for k in yeniler {
            out.append(Soru(kelime: k, tur: .tanit))
            if bekleyen.count >= 1 { out.append(bekleyen.removeFirst()) }
            if !tekrar.isEmpty { out.append(tekrar.removeFirst()) }
            bekleyen.append(soruYap(k, .anlam, ilk: true))
        }
        while !bekleyen.isEmpty || !tekrar.isEmpty {
            if !bekleyen.isEmpty { out.append(bekleyen.removeFirst()) }
            if !tekrar.isEmpty { out.append(tekrar.removeFirst()) }
            if !tekrar.isEmpty { out.append(tekrar.removeFirst()) }
        }
        sira = out
        soruBas = Date()
        if out.isEmpty { bitti = true }
    }

    private func turSec(_ k: Kelime, _ kart: Kart?) -> SoruTuru {
        let s = kart?.kararlilik ?? 0
        let zar = Int.random(in: 0..<10)
        if k.isPV {
            // Deyimsel fiil: asıl hedef parçacığı ayırt etmek — take off mı, take on mı, take up mı?
            let parc = parcacikHazirla(k) != nil
            let yazilir = k.w.count <= 16
            #if DEBUG
            if parc, ProcessInfo.processInfo.arguments.contains("-parcacikTest") { return .parcacik }
            #endif
            switch s {
            case ..<4: return zar < 5 && parc ? .parcacik : (zar < 8 ? .anlam : .dinle)
            case ..<21:
                if zar < 5, parc { return .parcacik }
                return zar < 8 && yazilir ? .yaz : .anlam
            default:
                if zar < 5, parc { return .parcacik }
                return zar < 8 && yazilir ? .yaz : .hatirla
            }
        }
        let boslukVar = k.x.contains { Vurgu.bosluk($0, k.w) != nil }
        let yazilir = k.w.count <= 16 && !k.tr.isEmpty
        switch s {
        case ..<4: return zar < 3 ? .dinle : .anlam
        case ..<21:
            if zar < 5, boslukVar { return .bosluk }
            if zar < 8, yazilir { return .yaz }
            return .anlam
        default:
            if zar < 6, yazilir { return .yaz }
            return boslukVar ? .bosluk : .hatirla
        }
    }

    private func soruYap(_ k: Kelime, _ t: SoruTuru, ilk: Bool = false, yineleme: Bool = false) -> Soru {
        var tur = t
        var bos: String? = nil
        var psec: [String] = []
        if tur == .parcacik {
            if let (b, s) = parcacikHazirla(k) { bos = b; psec = s } else { tur = .anlam }
        }
        return Soru(kelime: k, tur: tur, secenekler: secenek(k, tur), ilkKarsilasma: ilk,
                    yineleme: yineleme, bosCumle: bos, parcacikSec: psec)
    }

    /// Örnek cümlede parçacığı boşaltır; seçenekler: doğru parçacık + aynı fiilin öteki parçacıkları + yaygın parçacıklar.
    private func parcacikHazirla(_ k: Kelime) -> (String, [String])? {
        guard let p = k.parcacik, let depo,
              let re = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: p) + "\\b",
                                                options: [.caseInsensitive]) else { return nil }
        for x in k.x.shuffled() {
            let ns = x as NSString
            guard let m = re.firstMatch(in: x, range: NSRange(location: 0, length: ns.length)) else { continue }
            var sec = [p]
            for c in depo.ayniFiil(k).compactMap(\.parcacik).shuffled() where !sec.contains(c) && sec.count < 4 { sec.append(c) }
            for c in ["up", "out", "off", "on", "in", "down", "over", "away", "back", "through"].shuffled()
            where !sec.contains(c) && sec.count < 4 { sec.append(c) }
            return (ns.replacingCharacters(in: m.range, with: "_____"), sec.shuffled())
        }
        return nil
    }

    private func secenek(_ k: Kelime, _ t: SoruTuru) -> [Kelime] {
        guard [.anlam, .dinle, .bosluk].contains(t), let depo else { return [] }
        return ([k] + depo.celdiriciler(k)).shuffled()
    }

    // MARK: Cevaplar

    func sec(_ k: Kelime) {
        guard let s = soru, cevap == nil else { return }
        let dogru = k.w == s.kelime.w
        let sure = Date().timeIntervalSince(soruBas)
        cevap = Cevap(dogru: dogru, not: dogru ? (sure < 7 ? .iyi : .zor) : .unuttum, verilen: k.w, yakin: false)
    }

    func secParcacik(_ p: String) {
        guard let s = soru, cevap == nil else { return }
        let dogru = p == s.kelime.parcacik
        let sure = Date().timeIntervalSince(soruBas)
        cevap = Cevap(dogru: dogru, not: dogru ? (sure < 7 ? .iyi : .zor) : .unuttum, verilen: p, yakin: false)
    }

    func yaz(_ metin: String) {
        guard let s = soru, cevap == nil else { return }
        let a = Self.sade(metin), b = Self.sade(s.kelime.w)
        let fark = Self.mesafe(a, b)
        let dogru = fark == 0 || (fark == 1 && b.count > 4)
        cevap = Cevap(dogru: dogru, not: fark == 0 ? .iyi : (dogru ? .zor : .unuttum), verilen: metin, yakin: fark == 1)
    }

    func degerlendir(_ n: Not) {
        guard cevap == nil else { return }
        cevap = Cevap(dogru: n != .unuttum, not: n, verilen: nil, yakin: false)
        devam()
    }

    func kolaydi() {
        guard var c = cevap, c.dogru else { return }
        c.not = c.not == .kolay ? .iyi : .kolay
        cevap = c
    }

    func tanidim() {
        soruBas = Date()
        ilerle()
    }

    func zatenBiliyorum() {
        guard let s = soru, let depo else { return }
        depo.biliyorum(s.kelime)
        biliyorumDenen.append(s.kelime)
        yeniSayisi -= 1
        sira.removeAll { $0.kelime.w == s.kelime.w && $0.id != s.id }
        ilerle()
    }

    /// Cevap ekranından sonraki soruya geçiş — not burada işlenir (kolaydı düzeltmesi için).
    func devam() {
        guard let s = soru, let c = cevap, let depo else { return }
        if s.ilkKarsilasma {
            depo.tanis(s.kelime, c.not)
        } else {
            depo.cevap(s.kelime, c.not)
        }
        if sonuc[s.kelime.w] == nil { sonuc[s.kelime.w] = c.dogru }
        if !c.dogru, !s.yineleme {
            // Başka biçimde, üç soru sonra
            let t: SoruTuru = s.kelime.isPV ? (s.tur == .parcacik ? .anlam : .parcacik)
                                            : (s.tur == .anlam ? .dinle : .anlam)
            let y = soruYap(s.kelime, t, yineleme: true)
            sira.insert(y, at: min(sira.count, konum + 4))
        }
        cevap = nil
        ilerle()
    }

    private func ilerle() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            konum += 1
            if konum >= sira.count { bitti = true }
        }
        soruBas = Date()
    }

    var dogruOrani: Double {
        sonuc.isEmpty ? 0 : Double(sonuc.values.filter { $0 }.count) / Double(sonuc.count)
    }

    // MARK: Yazım denetimi

    static func sade(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
            .replacingOccurrences(of: "’", with: "'")
    }

    static func mesafe(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var onceki = Array(0...y.count)
        for i in 1...x.count {
            var simdi = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                simdi[j] = min(onceki[j] + 1, simdi[j - 1] + 1, onceki[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            onceki = simdi
        }
        return onceki[y.count]
    }
}
