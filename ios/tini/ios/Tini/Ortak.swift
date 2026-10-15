import Accelerate
import SwiftUI

// MARK: - Gezinti (derilerin ortak sayfaları)

enum Deri: String, CaseIterable, Identifiable {
    case modern, walkman, cowon
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .modern: return "Modern"
        case .walkman: return "Walkman WM-GX"
        case .cowon: return "Cowon D2"
        }
    }
    var aciklama: String {
        switch self {
        case .modern: return "Kapak, spektrum, bütün efektler tek dokunuşta"
        case .walkman: return "Kasetli Walkman: dönen makaralar, LCD, Mega Bass anahtarı, AVLS"
        case .cowon: return "D2'nin ekranı ve JetEffect menüsü: BBE, Mach3Bass, MP Enhance, 3D, 5 bant EQ"
        }
    }
    var simge: String {
        switch self {
        case .modern: return "sparkles.rectangle.stack"
        case .walkman: return "recordingtape"
        case .cowon: return "ipod"
        }
    }
}

enum Sayfa: String, Identifiable {
    case kutuphane, sesLab, ayarlar, deriler
    var id: String { rawValue }
}

final class Gezinti: ObservableObject {
    @Published var sayfa: Sayfa?
}

// MARK: - Biçimleme

func sureYazi(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

// MARK: - Kapak

struct KapakGorunumu: View {
    let parca: Parca?
    var kose: CGFloat = 10
    var body: some View {
        ZStack {
            if let r = parca?.kapakResmi {
                Image(uiImage: r).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: kose, style: .continuous))
    }
}

// MARK: - Spektrum

/// Zincirin halka tamponundan son 2048 örneği alıp FFT ile logaritmik bantlara böler.
final class Analizor {
    private let n = 2048
    private let dft: vDSP.DFT<Float>?
    private var pencere: [Float]
    private var gercek: [Float], sanal: [Float], cikR: [Float], cikI: [Float]
    private var degerler: [Float] = []
    private var tepeler: [Float] = []

    init() {
        dft = vDSP.DFT(count: n, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        pencere = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        gercek = Array(repeating: 0, count: n); sanal = Array(repeating: 0, count: n)
        cikR = Array(repeating: 0, count: n); cikI = Array(repeating: 0, count: n)
    }

    /// 0…1 aralığında `bant` değer; `tepe` yavaş düşen tepe izleri.
    func olc(_ z: Zincir?, bant: Int, calıyor: Bool) -> (degerler: [Float], tepeler: [Float]) {
        if degerler.count != bant { degerler = Array(repeating: 0, count: bant); tepeler = degerler }
        guard let z, calıyor, let dft else {
            for i in 0..<bant { degerler[i] = max(0, degerler[i] - 0.05); tepeler[i] = max(0, tepeler[i] - 0.02) }
            return (degerler, tepeler)
        }
        let son = z.halkaYaz
        for i in 0..<n { gercek[i] = z.halka[(son - n + i + Zincir.halkaBoyu * 2) & (Zincir.halkaBoyu - 1)] * pencere[i] }
        for i in 0..<n { sanal[i] = 0 }
        dft.transform(inputReal: gercek, inputImaginary: sanal, outputReal: &cikR, outputImaginary: &cikI)
        let sr = Float(z.ornekleme)
        let alt: Float = 40, ust: Float = min(18000, sr / 2)
        for b in 0..<bant {
            let f0 = alt * pow(ust / alt, Float(b) / Float(bant)), f1 = alt * pow(ust / alt, Float(b + 1) / Float(bant))
            let i0 = max(1, Int(f0 * Float(n) / sr)), i1 = max(i0 + 1, Int(f1 * Float(n) / sr))
            var en: Float = 0
            for i in i0..<min(i1, n / 2) { en = max(en, cikR[i] * cikR[i] + cikI[i] * cikI[i]) }
            let db = 10 * log10(en / Float(n) + 1e-12)
            let v = min(1, max(0, (db + 58) / 58))
            degerler[b] = v > degerler[b] ? v : max(v, degerler[b] - 0.035)
            tepeler[b] = v > tepeler[b] ? v : max(0, tepeler[b] - 0.008)
        }
        return (degerler, tepeler)
    }
}

/// Çubuk spektrum. `renk` dikey degrade.
struct SpektrumCubuklari: View {
    @EnvironmentObject var calar: Calar
    var bant = 28
    var renkler: [Color] = [.cyan, .blue, .purple]
    var tepeRengi: Color = .white
    var bosluk: CGFloat = 2
    @State private var analizor = Analizor()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !calar.caliyorMu)) { _ in
            Canvas { c, boyut in
                let (d, t) = analizor.olc(calar.zincir, bant: bant, calıyor: calar.caliyorMu)
                let g = (boyut.width - bosluk * CGFloat(bant - 1)) / CGFloat(bant)
                let degrade = Gradient(colors: renkler.reversed())
                for i in 0..<bant {
                    let x = CGFloat(i) * (g + bosluk)
                    if d[i] < 0.01 && t[i] < 0.01 { continue }
                    let h = max(1, CGFloat(d[i]) * boyut.height)
                    let r = CGRect(x: x, y: boyut.height - h, width: g, height: h)
                    c.fill(Path(r), with: .linearGradient(degrade, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: boyut.height)))
                    let ty = boyut.height - CGFloat(t[i]) * boyut.height
                    c.fill(Path(CGRect(x: x, y: max(0, ty - 2), width: g, height: 2)), with: .color(tepeRengi.opacity(0.8)))
                }
            }
        }
    }
}

// MARK: - EQ eğrisi

/// Geçerli ayarın EQ + bas süzgeçlerinin toplam frekans yanıtı (DSP ile aynı katsayılar).
struct EQEgrisi: View {
    let ayar: SesAyari
    var renk: Color = .accentColor
    var izgara = true

    var body: some View {
        Canvas { c, b in
            let sr = 48000.0
            let k = ayar.atla ? [] : Tasarim.eqSuzgecleri(ayar, sr: sr) + Tasarim.maximizerSuzgecleri(ayar, sr: sr) + Tasarim.basSuzgecleri(ayar, sr: sr)
            let aralik = 15.0
            func y(_ db: Double) -> CGFloat { b.height / 2 - CGFloat(db / aralik) * b.height / 2 }
            func x(_ f: Double) -> CGFloat { CGFloat(log10(f / 20) / log10(1000)) * b.width }
            if izgara {
                for f in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] {
                    c.stroke(Path { $0.move(to: CGPoint(x: x(f), y: 0)); $0.addLine(to: CGPoint(x: x(f), y: b.height)) },
                             with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                }
                c.stroke(Path { $0.move(to: CGPoint(x: 0, y: y(0))); $0.addLine(to: CGPoint(x: b.width, y: y(0))) },
                         with: .color(.secondary.opacity(0.35)), lineWidth: 0.5)
            }
            var yol = Path()
            for i in 0...120 {
                let f = 20 * pow(1000, Double(i) / 120)
                let db = k.reduce(0) { $0 + Tasarim.genlikDB($1, f, sr: sr) }
                let p = CGPoint(x: x(f), y: y(max(-aralik, min(aralik, db))))
                i == 0 ? yol.move(to: p) : yol.addLine(to: p)
            }
            var dolgu = yol
            dolgu.addLine(to: CGPoint(x: b.width, y: y(0))); dolgu.addLine(to: CGPoint(x: 0, y: y(0))); dolgu.closeSubpath()
            c.fill(dolgu, with: .color(renk.opacity(0.18)))
            c.stroke(yol, with: .color(renk), lineWidth: 2)
        }
    }
}

// MARK: - Ses düzeyi göstergesi (VU)

struct TepeGostergesi: View {
    @EnvironmentObject var calar: Calar
    var renk: Color = .green
    private final class Iz { var l: Float = 0; var r: Float = 0 }
    @State private var iz = Iz()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !calar.caliyorMu)) { _ in
            Canvas { c, b in
                let z = calar.zincir
                let yl = calar.caliyorMu ? (z?.tepeL ?? 0) : 0, yr = calar.caliyorMu ? (z?.tepeR ?? 0) : 0
                iz.l = yl > iz.l ? yl : max(0, iz.l - 0.03)
                iz.r = yr > iz.r ? yr : max(0, iz.r - 0.03)
                for (i, v) in [iz.l, iz.r].enumerated() {
                    let db = 20 * log10(max(v, 1e-4)), oran = CGFloat(max(0, min(1, (db + 40) / 40)))
                    let h = (b.height - 2) / 2
                    let ry = CGFloat(i) * (h + 2)
                    let adet = 20
                    let g = b.width / CGFloat(adet)
                    for s in 0..<adet {
                        let yanik = CGFloat(s) / CGFloat(adet) < oran
                        let renkS: Color = s >= adet - 3 ? .red : (s >= adet - 7 ? .yellow : renk)
                        c.fill(Path(CGRect(x: CGFloat(s) * g, y: ry, width: g - 1.5, height: h)),
                               with: .color(renkS.opacity(yanik ? 0.95 : 0.12)))
                    }
                }
            }
        }
    }
}
