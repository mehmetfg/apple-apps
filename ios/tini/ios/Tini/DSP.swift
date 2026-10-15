import Foundation
import os

// Tını'nın ses işleme çekirdeği. Hiçbir Apple efekt birimine bağlı değildir: aynı kod bugün AVAudioEngine içindeki
// `EfektBirimi`nde, 2. aşamada akış kaynakları için AVPlayer'ın ses musluğunda (MTAudioProcessingTap) çalışacak.
// Zincir sırası (SesAyari'ndaki alanlarla aynı):
//   ön kazanç · ReplayGain → EQ (10 bant grafik ya da 5 bant parametrik) → Sonic Maximizer (BBE tarzı netlik)
//   → bas (Mega Bass / Groove / Mach3Bass + psikoakustik bas) → tiz onarımı (DSEE / MP Enhance tarzı)
//   → stereo genişlik + 3D surround → kulaklık crossfeed → VPT yankı → dinamik dengeleyici → denge → ses → limiter

// MARK: - Ayarlar

struct ParamBant: Codable, Equatable, Hashable {
    var frekans: Float
    var kazanc: Float   // dB, ±12
    var q: Float        // 0.3 … 4
}

enum EQKipi: String, Codable, CaseIterable, Identifiable {
    case grafik, parametrik
    var id: String { rawValue }
    var ad: String { self == .grafik ? "10 bant" : "Parametrik 5 bant" }
}

enum BasKipi: String, Codable, CaseIterable, Identifiable {
    case kapali, megaBass, groove, mach3
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .kapali: return "Kapalı"
        case .megaBass: return "Mega Bass"
        case .groove: return "Groove"
        case .mach3: return "Mach3Bass"
        }
    }
}

enum YankiOda: String, Codable, CaseIterable, Identifiable {
    case kapali, studyo, kulup, salon, arena
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .kapali: return "Kapalı"
        case .studyo: return "Stüdyo"
        case .kulup: return "Kulüp"
        case .salon: return "Konser salonu"
        case .arena: return "Arena"
        }
    }
    /// (oda boyu 0-1, sönüm 0-1, ıslak düzey 0-1)
    var degerler: (Float, Float, Float) {
        switch self {
        case .kapali: return (0, 0, 0)
        case .studyo: return (0.50, 0.55, 0.10)
        case .kulup: return (0.68, 0.45, 0.15)
        case .salon: return (0.84, 0.30, 0.20)
        case .arena: return (0.93, 0.18, 0.26)
        }
    }
}

struct SesAyari: Codable, Equatable {
    static let grafikFrekanslar: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let varsayilanParametrik: [ParamBant] = [
        // Frekanslar ve Q, Cowon D2 yüzündeki seçeneklerle aynı (60 · 400 · 1k · 4k · 12k, "N" genişlik).
        ParamBant(frekans: 60, kazanc: 0, q: 1.2), ParamBant(frekans: 400, kazanc: 0, q: 1.2),
        ParamBant(frekans: 1000, kazanc: 0, q: 1.2), ParamBant(frekans: 4000, kazanc: 0, q: 1.2),
        ParamBant(frekans: 12000, kazanc: 0, q: 1.2),
    ]

    /// A/B: açıkken bütün efektler atlanır, yalnız ses düzeyi kalır.
    var atla = false
    var onKazanc: Float = 0              // dB −12…+12
    var otomatikBosluk = true            // efektlerin eklediği kazancı önden geri alır
    var replayGain = true
    var denge: Float = 0                 // −1 sol … +1 sağ

    var eqAcik = true
    var eqKipi: EQKipi = .grafik
    var grafik: [Float] = Array(repeating: 0, count: 10)
    var parametrik: [ParamBant] = SesAyari.varsayilanParametrik

    var maximizer = false                // Sonic Maximizer (BBE tarzı)
    var maxBas: Float = 0                // "Lo contour" 0…10
    var maxNetlik: Float = 0             // "Process" 0…10

    var bas: BasKipi = .kapali
    var basSeviye: Float = 5             // 0…10
    var basFrekans: Float = 60           // Mach3Bass kesim frekansı 20…150
    var psikoBas: Float = 0              // psikoakustik bas (harmonik) 0…10

    var tiz: Float = 0                   // tiz onarımı 0…10

    var genislik: Float = 1              // 0 mono … 1 doğal … 2 geniş
    var surround: Float = 0              // 3D 0…10
    var crossfeed: Float = 0             // 0…10
    var yanki: YankiOda = .kapali
    var yankiSeviye: Float = 5           // 0…10 (odanın ıslak düzeyini ölçekler)

    var dengeleyici = false              // dinamik dengeleyici (Sony Dynamic Normalizer tarzı)

    /// Otomatik boşluk için: efektlerin en çok kaç dB eklediği (kabaca).
    var ekKazanc: Float {
        var en: Float = 0
        if eqAcik {
            en = eqKipi == .grafik ? (grafik.max() ?? 0) : (parametrik.map(\.kazanc).max() ?? 0)
        }
        var basEk: Float = 0
        switch bas {
        case .kapali: break
        case .megaBass: basEk = basSeviye * 1.0
        case .groove: basEk = basSeviye * 1.3
        case .mach3: basEk = basSeviye * 1.2
        }
        if maximizer { basEk = max(basEk, maxBas * 0.6); en = max(en, maxNetlik * 0.8) }
        return max(0, max(en, basEk))
    }
}

// MARK: - Biquad (RBJ)

struct Katsayi {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    static let gecir = Katsayi()
}

struct BiquadDurum { var z1 = 0.0, z2 = 0.0 }

@inline(__always)
func biquad(_ x: Double, _ k: Katsayi, _ s: inout BiquadDurum) -> Double {
    let y = k.b0 * x + s.z1
    s.z1 = k.b1 * x - k.a1 * y + s.z2
    s.z2 = k.b2 * x - k.a2 * y
    return y
}

enum Tasarim {
    private static func ortak(_ f: Double, _ sr: Double) -> (Double, Double) {
        let w = 2 * Double.pi * min(f, sr * 0.45) / sr
        return (cos(w), sin(w))
    }

    static func tepe(_ f: Double, q: Double, dB: Double, sr: Double) -> Katsayi {
        if abs(dB) < 0.01 { return .gecir }
        let A = pow(10, dB / 40), (c, s) = ortak(f, sr), al = s / (2 * max(q, 0.05))
        let a0 = 1 + al / A
        return Katsayi(b0: (1 + al * A) / a0, b1: -2 * c / a0, b2: (1 - al * A) / a0, a1: -2 * c / a0, a2: (1 - al / A) / a0)
    }

    static func alcakRaf(_ f: Double, dB: Double, sr: Double) -> Katsayi {
        if abs(dB) < 0.01 { return .gecir }
        let A = pow(10, dB / 40), (c, s) = ortak(f, sr), al = s / 2 * sqrt(2), r = 2 * sqrt(A) * al
        let a0 = (A + 1) + (A - 1) * c + r
        return Katsayi(b0: A * ((A + 1) - (A - 1) * c + r) / a0, b1: 2 * A * ((A - 1) - (A + 1) * c) / a0,
                       b2: A * ((A + 1) - (A - 1) * c - r) / a0, a1: -2 * ((A - 1) + (A + 1) * c) / a0,
                       a2: ((A + 1) + (A - 1) * c - r) / a0)
    }

    static func yuksekRaf(_ f: Double, dB: Double, sr: Double) -> Katsayi {
        if abs(dB) < 0.01 { return .gecir }
        let A = pow(10, dB / 40), (c, s) = ortak(f, sr), al = s / 2 * sqrt(2), r = 2 * sqrt(A) * al
        let a0 = (A + 1) - (A - 1) * c + r
        return Katsayi(b0: A * ((A + 1) + (A - 1) * c + r) / a0, b1: -2 * A * ((A - 1) + (A + 1) * c) / a0,
                       b2: A * ((A + 1) + (A - 1) * c - r) / a0, a1: 2 * ((A - 1) - (A + 1) * c) / a0,
                       a2: ((A + 1) - (A - 1) * c - r) / a0)
    }

    static func alcakGecir(_ f: Double, q: Double = 0.7071, sr: Double) -> Katsayi {
        let (c, s) = ortak(f, sr), al = s / (2 * q), a0 = 1 + al
        return Katsayi(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
    }

    static func yuksekGecir(_ f: Double, q: Double = 0.7071, sr: Double) -> Katsayi {
        let (c, s) = ortak(f, sr), al = s / (2 * q), a0 = 1 + al
        return Katsayi(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
    }

    /// Süzgecin `f` frekansındaki kazancı (dB). EQ eğrisini çizmek için.
    static func genlikDB(_ k: Katsayi, _ f: Double, sr: Double) -> Double {
        let w = 2 * Double.pi * f / sr
        let c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w)
        let nr = k.b0 + k.b1 * c1 + k.b2 * c2, ni = -(k.b1 * s1 + k.b2 * s2)
        let dr = 1 + k.a1 * c1 + k.a2 * c2, di = -(k.a1 * s1 + k.a2 * s2)
        let g = sqrt((nr * nr + ni * ni) / max(dr * dr + di * di, 1e-30))
        return 20 * log10(max(g, 1e-9))
    }

    /// Ayarın EQ + bas bölümünün süzgeçleri (eğri çizimi ve işleme aynı kaynaktan).
    static func eqSuzgecleri(_ a: SesAyari, sr: Double) -> [Katsayi] {
        var k: [Katsayi] = []
        if a.eqAcik {
            switch a.eqKipi {
            case .grafik:
                for (i, f) in SesAyari.grafikFrekanslar.enumerated() where abs(a.grafik[i]) > 0.05 {
                    k.append(tepe(Double(f), q: 1.41, dB: Double(a.grafik[i]), sr: sr))
                }
            case .parametrik:
                for b in a.parametrik where abs(b.kazanc) > 0.05 {
                    k.append(tepe(Double(b.frekans), q: Double(b.q), dB: Double(b.kazanc), sr: sr))
                }
            }
        }
        return k
    }

    /// Maximizer'ın eğrideki yaklaşık hâli (tiz rafı gerçekte müziğe göre oynar; burada orta değeri).
    static func maximizerSuzgecleri(_ a: SesAyari, sr: Double) -> [Katsayi] {
        guard a.maximizer else { return [] }
        return [alcakRaf(120, dB: Double(a.maxBas) * 0.8, sr: sr), yuksekRaf(3000, dB: Double(a.maxNetlik) * 0.78, sr: sr)]
    }

    static func basSuzgecleri(_ a: SesAyari, sr: Double) -> [Katsayi] {
        let s = Double(a.basSeviye)
        switch a.bas {
        case .kapali: return []
        case .megaBass:
            // Kasetli Walkman'ın Mega Bass'ı: 60-80 Hz civarında geniş bir tümsek.
            return [tepe(70, q: 0.8, dB: s * 1.0, sr: sr), yuksekGecir(22, sr: sr)]
        case .groove:
            // Groove: daha derin bas + hafif üst orta (vokal kaybolmasın).
            return [alcakRaf(110, dB: s * 1.3, sr: sr), tepe(2800, q: 0.9, dB: s * 0.25, sr: sr), yuksekGecir(22, sr: sr)]
        case .mach3:
            // Cowon Mach3Bass: kesim frekansı seçilebilen raf + alt sınır.
            return [alcakRaf(Double(a.basFrekans), dB: s * 1.2, sr: sr), yuksekGecir(18, sr: sr)]
        }
    }
}

// MARK: - Gecikme hattı

struct Gecikme {
    private(set) var buf: UnsafeMutablePointer<Float>
    let n: Int
    private var i = 0

    init(ornek: Int) {
        n = max(1, ornek)
        buf = .allocate(capacity: n)
        buf.initialize(repeating: 0, count: n)
    }

    func birak() { buf.deallocate() }
    mutating func sifirla() { buf.update(repeating: 0, count: n); i = 0 }

    /// Yazar ve `n` örnek önceki değeri döndürür.
    @inline(__always) mutating func it(_ x: Float) -> Float {
        let y = buf[i]
        buf[i] = x
        i += 1
        if i >= n { i = 0 }
        return y
    }
}

// MARK: - Freeverb (VPT yankısı)

private struct Tarak {
    var hat: Gecikme
    var suzgec: Float = 0
    @inline(__always) mutating func isle(_ x: Float, geri: Float, d1: Float, d2: Float) -> Float {
        var cikan: Float = 0
        // Gecikme.it yazmadan önce okur; tarakta çıkışın kendisini geri beslemek gerekir, o yüzden iki adım.
        let i = hatIndeks
        cikan = hat.buf[i]
        suzgec = cikan * d2 + suzgec * d1
        hat.buf[i] = x + suzgec * geri
        hatIndeks = i + 1 >= hat.n ? 0 : i + 1
        return cikan
    }
    var hatIndeks = 0
}

private struct TumGecir {
    var hat: Gecikme
    var hatIndeks = 0
    @inline(__always) mutating func isle(_ x: Float) -> Float {
        let i = hatIndeks
        let b = hat.buf[i]
        hat.buf[i] = x + b * 0.5
        hatIndeks = i + 1 >= hat.n ? 0 : i + 1
        return b - x
    }
}

private struct Yanki {
    var taraklarL: [Tarak], taraklarR: [Tarak], tumL: [TumGecir], tumR: [TumGecir]

    init(sr: Double) {
        let o = sr / 44100
        let t = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let a = [556, 441, 341, 225]
        taraklarL = t.map { Tarak(hat: Gecikme(ornek: Int(Double($0) * o))) }
        taraklarR = t.map { Tarak(hat: Gecikme(ornek: Int(Double($0 + 23) * o))) }
        tumL = a.map { TumGecir(hat: Gecikme(ornek: Int(Double($0) * o))) }
        tumR = a.map { TumGecir(hat: Gecikme(ornek: Int(Double($0 + 23) * o))) }
    }

    func birak() {
        taraklarL.forEach { $0.hat.birak() }; taraklarR.forEach { $0.hat.birak() }
        tumL.forEach { $0.hat.birak() }; tumR.forEach { $0.hat.birak() }
    }

    @inline(__always) mutating func isle(_ giris: Float, geri: Float, d1: Float, d2: Float) -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        for j in 0..<8 {
            l += taraklarL[j].isle(giris, geri: geri, d1: d1, d2: d2)
            r += taraklarR[j].isle(giris, geri: geri, d1: d1, d2: d2)
        }
        for j in 0..<4 { l = tumL[j].isle(l); r = tumR[j].isle(r) }
        return (l, r)
    }
}

// MARK: - Zincir

/// Gerçek zamanlı ses iş parçacığından çağrılır. Ana iş parçacığı ayarı `ayarla`, sesi `kazancaSol` ile verir;
/// ses iş parçacığı bunları bir sonraki blokta, kilidi bekletmeden (`trylock`) alır.
final class Zincir {
    // Aktarım
    private let kilit: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    private var bekleyenAyar: SesAyari?
    private var bekleyenKazanc: (Float, Double)?
    private var bekleyenParcaKazanci: Float?
    private var sifirlaIstek = false

    // Ses iş parçacığının durumu
    private var a = SesAyari()
    private var sr: Double = 48000
    private var hazir = false

    private var eqK: [Katsayi] = [], eqL: [BiquadDurum] = [], eqR: [BiquadDurum] = []
    private var basK: [Katsayi] = [], basL: [BiquadDurum] = [], basR: [BiquadDurum] = []

    // Maximizer: bas konturu (alçak raf) + programa göre açılan tiz rafı
    private var mxBasRaf = Katsayi(), mxTizRaf = Katsayi(), mxOlcer = Katsayi()
    private var mxBL = BiquadDurum(), mxBR = BiquadDurum(), mxTL = BiquadDurum(), mxTR = BiquadDurum(), mxO = BiquadDurum()
    private var mxZarfY: Double = 0, mxZarfT: Double = 0, mxTizDB: Double = -100

    // Psikoakustik bas
    private var pbAlcak = Katsayi(), pbBant1 = Katsayi(), pbBant2 = Katsayi()
    private var pbA = BiquadDurum(), pbB1 = BiquadDurum(), pbB2 = BiquadDurum()

    // Tiz onarımı
    private var tzY1 = Katsayi(), tzY2 = Katsayi()
    private var tzL1 = BiquadDurum(), tzR1 = BiquadDurum(), tzL2 = BiquadDurum(), tzR2 = BiquadDurum()

    // 3D
    private var sdY = Katsayi(), sdD = BiquadDurum(), sdGec = Gecikme(ornek: 1)

    // Crossfeed
    private var cfA = Katsayi(), cfL = BiquadDurum(), cfR = BiquadDurum()

    // Yankı
    private var yanki: Yanki?
    private var yankiAktif = false

    // Dengeleyici
    private var dgRms: Double = 0, dgKazanc: Double = 1, dgSayac = 0, dgHedef: Double = 1

    // Ses ve limiter
    private var kazanc: Float = 0, hedefKazanc: Float = 0, kazancAdim: Float = 0, kazancKalan = 0
    private var parcaKazanci: Float = 1
    private var limKazanc: Float = 1, limBirak: Float = 0.9995

    // Ölçüm (arayüz okur; yarışa açık, yalnız görsel)
    static let halkaBoyu = 4096
    let halka: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: Zincir.halkaBoyu)
        p.initialize(repeating: 0, count: Zincir.halkaBoyu)
        return p
    }()
    private(set) var halkaYaz = 0
    private(set) var tepeL: Float = 0, tepeR: Float = 0
    private(set) var limiterCalisiyor: Float = 0
    var ornekleme: Double { sr }

    deinit {
        serbestBirak()
        kilit.deallocate()
        halka.deallocate()
    }

    // MARK: Ana iş parçacığından

    func ayarla(_ yeni: SesAyari) {
        os_unfair_lock_lock(kilit); bekleyenAyar = yeni; os_unfair_lock_unlock(kilit)
    }

    /// Çıkış kazancını `sure` saniyede doğrusal olarak `hedef`e taşır (0…1).
    func kazancaSol(_ hedef: Float, sure: Double) {
        os_unfair_lock_lock(kilit); bekleyenKazanc = (hedef, sure); os_unfair_lock_unlock(kilit)
    }

    /// ReplayGain gibi parçaya özgü kazanç (doğrusal).
    func parcaKazanciAyarla(_ g: Float) {
        os_unfair_lock_lock(kilit); bekleyenParcaKazanci = g; os_unfair_lock_unlock(kilit)
    }

    /// Yeni parçaya atlarken süzgeç kuyruklarını temizler.
    func sifirla() {
        os_unfair_lock_lock(kilit); sifirlaIstek = true; os_unfair_lock_unlock(kilit)
    }

    /// Ses birimi kaynak ayırırken (render başlamadan) çağrılır.
    func hazirla(ornekleme: Double) {
        serbestBirak()
        sr = ornekleme
        sdGec = Gecikme(ornek: Int(sr * 0.009))
        yanki = Yanki(sr: sr)
        limBirak = Float(exp(-1 / (sr * 0.08)))
        os_unfair_lock_lock(kilit)
        if bekleyenAyar == nil { bekleyenAyar = a }
        os_unfair_lock_unlock(kilit)
        hazir = true
        katsayilariKur()
    }

    func serbestBirak() {
        guard hazir else { return }
        hazir = false
        sdGec.birak()
        yanki?.birak(); yanki = nil
    }

    // MARK: Ses iş parçacığından

    private func katsayilariKur() {
        eqK = Tasarim.eqSuzgecleri(a, sr: sr)
        if eqL.count != eqK.count {
            eqL = Array(repeating: BiquadDurum(), count: eqK.count)
            eqR = Array(repeating: BiquadDurum(), count: eqK.count)
        }
        basK = Tasarim.basSuzgecleri(a, sr: sr)
        if basL.count != basK.count {
            basL = Array(repeating: BiquadDurum(), count: basK.count)
            basR = Array(repeating: BiquadDurum(), count: basK.count)
        }
        mxBasRaf = Tasarim.alcakRaf(120, dB: Double(a.maxBas) * 0.8, sr: sr)
        mxOlcer = Tasarim.yuksekGecir(2400, sr: sr)
        mxTizDB = -100   // tiz rafı bir sonraki blokta yeniden kurulur
        pbAlcak = Tasarim.alcakGecir(110, sr: sr)
        pbBant1 = Tasarim.yuksekGecir(110, sr: sr)
        pbBant2 = Tasarim.alcakGecir(420, sr: sr)
        tzY1 = Tasarim.yuksekGecir(3200, sr: sr)
        tzY2 = Tasarim.yuksekGecir(6500, sr: sr)
        sdY = Tasarim.yuksekGecir(320, sr: sr)
        cfA = Tasarim.alcakGecir(700, q: 0.5, sr: sr)
        let yeniYanki = a.yanki != .kapali
        if yeniYanki && !yankiAktif { yanki?.birak(); yanki = Yanki(sr: sr) }   // eski kuyruk duyulmasın
        yankiAktif = yeniYanki
    }

    private func bekleyenleriAl() {
        guard os_unfair_lock_trylock(kilit) else { return }
        let ayar = bekleyenAyar; bekleyenAyar = nil
        let kz = bekleyenKazanc; bekleyenKazanc = nil
        let pk = bekleyenParcaKazanci; bekleyenParcaKazanci = nil
        let sf = sifirlaIstek; sifirlaIstek = false
        os_unfair_lock_unlock(kilit)
        if let ayar { a = ayar; katsayilariKur() }
        if let (h, s) = kz {
            hedefKazanc = h
            kazancKalan = max(1, Int(s * sr))
            kazancAdim = (h - kazanc) / Float(kazancKalan)
        }
        if let pk { parcaKazanci = pk }
        if sf {
            for i in eqL.indices { eqL[i] = BiquadDurum(); eqR[i] = BiquadDurum() }
            for i in basL.indices { basL[i] = BiquadDurum(); basR[i] = BiquadDurum() }
            mxBL = BiquadDurum(); mxBR = BiquadDurum(); mxTL = BiquadDurum(); mxTR = BiquadDurum(); sdGec.sifirla()
            if yankiAktif { yanki?.birak(); yanki = Yanki(sr: sr) }
        }
    }

    func isle(_ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>?, _ n: Int) {
        bekleyenleriAl()
        guard hazir else { return }
        let R = R ?? L
        let atla = a.atla

        var onDB = a.onKazanc
        if a.otomatikBosluk { onDB -= min(12, a.ekKazanc * 0.6) }
        let on = Double(pow(10, onDB / 20) * (a.replayGain ? parcaKazanci : 1))

        let zarfKatsayi = exp(-1 / (sr * 0.05))
        if a.maximizer {
            // Tiz rafı blok başına bir kez: program tizce zayıfsa daha çok açılır (en çok netlik × 0,96 dB).
            let oran = min(1, mxZarfY / (mxZarfT * 0.35 + 1e-9))
            let hedef = Double(a.maxNetlik) * 0.6 * (1 + 0.6 * (1 - oran))
            if abs(hedef - mxTizDB) > 0.2 {
                mxTizDB = mxTizDB < -50 ? hedef : mxTizDB + (hedef - mxTizDB) * 0.3
                mxTizRaf = Tasarim.yuksekRaf(3000, dB: mxTizDB, sr: sr)
            }
        }
        let pb = Double(a.psikoBas) * 0.09
        let tz = Double(a.tiz) * 0.045
        let gen = Double(a.genislik)
        let sd = Double(a.surround) * 0.07
        let cf = Double(a.crossfeed) * 0.045
        let (oda, sonum, islak0) = a.yanki.degerler
        let islak = islak0 * a.yankiSeviye / 5
        let geri = oda * 0.28 + 0.7, d1 = sonum * 0.4, d2 = 1 - sonum * 0.4
        let dgSaldiri = exp(-1 / (sr * 0.010)), dgBirak = exp(-1 / (sr * 0.300)), dgOrt = exp(-1 / (sr * 0.020))
        let solK = Float(min(1, 1 - a.denge)), sagK = Float(min(1, 1 + a.denge))
        var tL: Float = 0, tR: Float = 0, limEn: Float = 1

        for i in 0..<n {
            var l = Double(L[i]), r = Double(R[i])

            if !atla {
                l *= on; r *= on

                for j in 0..<eqK.count { l = biquad(l, eqK[j], &eqL[j]); r = biquad(r, eqK[j], &eqR[j]) }

                if a.maximizer {
                    // Sonic Maximizer: bas konturu + dinamik tiz rafı. Ölçer yalnız zarfı izler, sesi değiştirmez.
                    let y = biquad((l + r) * 0.5, mxOlcer, &mxO)
                    mxZarfY = zarfKatsayi * mxZarfY + (1 - zarfKatsayi) * abs(y)
                    mxZarfT = zarfKatsayi * mxZarfT + (1 - zarfKatsayi) * abs((l + r) * 0.5)
                    l = biquad(biquad(l, mxBasRaf, &mxBL), mxTizRaf, &mxTL)
                    r = biquad(biquad(r, mxBasRaf, &mxBR), mxTizRaf, &mxTR)
                }

                for j in 0..<basK.count { l = biquad(l, basK[j], &basL[j]); r = biquad(r, basK[j], &basR[j]) }

                if pb > 0 {
                    // Psikoakustik bas: 110 Hz altını doğrultup üst harmoniklerini üret; küçük kulaklık temel
                    // frekansı veremese de kulak harmoniklerden bası "duyar".
                    let m = biquad((l + r) * 0.5, pbAlcak, &pbA)
                    var h = abs(m) * 1.6 + tanh(m * 3) * 0.4
                    h = biquad(biquad(h, pbBant1, &pbB1), pbBant2, &pbB2)
                    l += h * pb; r += h * pb
                }

                if tz > 0 {
                    // Tiz onarımı: 3,2 kHz üstünü yumuşak doyurup 6,5 kHz üstüne düşen harmonikleri ekler;
                    // sıkıştırılmış dosyada kesilen havayı geri getirir.
                    let hl = biquad(l, tzY1, &tzL1), hr = biquad(r, tzY1, &tzR1)
                    let sl = biquad(tanh(hl * 4) * 0.25 + hl * abs(hl) * 2, tzY2, &tzL2)
                    let sr2 = biquad(tanh(hr * 4) * 0.25 + hr * abs(hr) * 2, tzY2, &tzR2)
                    l += sl * tz; r += sr2 * tz
                }

                if gen != 1 || sd > 0 {
                    let m = (l + r) * 0.5
                    var s = (l - r) * 0.5 * gen
                    if sd > 0 {
                        let sy = biquad(s, sdY, &sdD)
                        s += sy * sd * 1.2 + Double(sdGec.it(Float(sy))) * sd
                    }
                    l = m + s; r = m - s
                }

                if cf > 0 {
                    // Kulaklık crossfeed (bs2b tarzı): öbür kanalın 700 Hz altı hafifçe karışır,
                    // hoparlörde olduğu gibi; "kafanın içinde" sesi öne alır.
                    let xl = biquad(r, cfA, &cfL), xr = biquad(l, cfA, &cfR)
                    l = (l + xl * cf) / (1 + cf * 0.5); r = (r + xr * cf) / (1 + cf * 0.5)
                }

                if yankiAktif, islak > 0, yanki != nil {
                    let (yl, yr) = yanki!.isle(Float((l + r) * 0.015), geri: geri, d1: d1, d2: d2)
                    l += Double(yl * islak * 3); r += Double(yr * islak * 3)
                }

                if a.dengeleyici {
                    let x = max(l * l, r * r)
                    dgRms = dgOrt * dgRms + (1 - dgOrt) * x
                    dgSayac += 1
                    if dgSayac >= 16 {
                        dgSayac = 0
                        let duzey = 10 * log10(dgRms + 1e-12)
                        let asim = duzey - (-22)
                        let azalt = asim > 0 ? asim * (1 - 1 / 3.0) : 0
                        dgHedef = pow(10, (-azalt + 6) / 20)
                    }
                    let k = dgHedef < dgKazanc ? dgSaldiri : dgBirak
                    dgKazanc = k * dgKazanc + (1 - k) * dgHedef
                    l *= dgKazanc; r *= dgKazanc
                }
            }

            // Ses (solmalar burada; arka planda zamanlayıcıya ihtiyaç kalmaz)
            if kazancKalan > 0 {
                kazanc += kazancAdim
                kazancKalan -= 1
                if kazancKalan == 0 { kazanc = hedefKazanc }
            }
            var fl = Float(l) * kazanc * solK, fr = Float(r) * kazanc * sagK

            // Limiter: anında yakala, 80 ms'de bırak. Tavan −0,3 dBFS.
            let tepe = max(abs(fl), abs(fr))
            var g = 1 - (1 - limKazanc) * limBirak
            if tepe * g > 0.966 { g = 0.966 / tepe }
            limKazanc = g
            fl *= limKazanc; fr *= limKazanc
            limEn = min(limEn, limKazanc)

            L[i] = fl
            if R != L { R[i] = fr }
            tL = max(tL, abs(fl)); tR = max(tR, abs(fr))
            halka[halkaYaz] = (fl + fr) * 0.5
            halkaYaz = (halkaYaz + 1) & (Zincir.halkaBoyu - 1)
        }
        tepeL = tL; tepeR = tR
        limiterCalisiyor = 1 - limEn
    }
}
