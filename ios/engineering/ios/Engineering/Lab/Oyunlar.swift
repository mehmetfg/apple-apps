import SwiftUI

// MARK: - Tahmin et

struct TahminOyunu: View {
    let algoritma: Algoritma
    var turSayisi = 3
    var bitti: ((Int, Int) -> Void)? = nil

    @State private var soru: TahminSorusu?
    @State private var tur = 1
    @State private var secim: Int?
    @State private var dogru = 0
    @State private var son = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Etiket(metin: "PREDICT", renk: Tema.pivot)
                Spacer()
                Text(son ? "\(dogru) / \(turSayisi)" : "Round \(tur) of \(turSayisi)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Tema.soluk)
            }
            if son {
                VStack(alignment: .leading, spacing: 10) {
                    Text(dogru == turSayisi ? "You can see the algorithm in your head." : "\(dogru) of \(turSayisi) predictions were right.")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Predicting the state after a pass is how engineers check an invariant without running the code.")
                        .font(.callout).foregroundStyle(Tema.soluk)
                    Button("Three more") { yeniden() }.buttonStyle(IkinciDugme())
                }
                .kartYuzey()
            } else if let soru {
                Text("Start").font(.caption).foregroundStyle(Tema.soluk)
                DiziSatiri(dizi: soru.baslangic)
                Text(soru.ekMi ? "What are the counters after counting?"
                               : "What does the list look like after \(soru.durak)?")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(Array(soru.secenekler.enumerated()), id: \.offset) { i, s in
                        SecenekDugme(metin: "[" + s.map(String.init).joined(separator: ", ") + "]", kod: true,
                                     durum: durum(i, soru.dogru)) {
                            guard secim == nil else { return }
                            secim = i
                            if i == soru.dogru { dogru += 1; Dokunma.basari() } else { Dokunma.hata() }
                        }
                    }
                }
                if secim != nil {
                    Button(tur == turSayisi ? "See result" : "Next") { sonraki() }.buttonStyle(AnaDugme())
                }
            }
        }
        .onAppear { if soru == nil { soru = tahminSorusu(algoritma) } }
    }

    private func durum(_ i: Int, _ d: Int) -> SecenekDugme.Durum {
        guard let secim else { return .notr }
        return i == d ? .dogru : (i == secim ? .yanlis : .soluk)
    }

    private func sonraki() {
        secim = nil
        if tur == turSayisi { son = true; bitti?(dogru, turSayisi) } else { tur += 1; soru = tahminSorusu(algoritma) }
    }

    private func yeniden() { tur = 1; dogru = 0; son = false; secim = nil; soru = tahminSorusu(algoritma) }
}

struct DiziSatiri: View {
    let dizi: [Int]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(dizi.enumerated()), id: \.offset) { _, v in
                Text("\(v)").font(.system(.headline, design: .rounded)).monospacedDigit()
                    .frame(width: 36, height: 36)
                    .background(Tema.kart2, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}

// MARK: - Gizemli algoritma

struct GizemOyunu: View {
    @State private var algoritma: Algoritma = .bubble
    @State private var secenekler: [Algoritma] = []
    @State private var kareler: [Kare] = []
    @State private var indeks = 0
    @State private var secim: Algoritma?
    @State private var tur = 1
    @State private var dogru = 0
    @State private var gorev: Task<Void, Never>?
    private let turSayisi = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Etiket(metin: "MYSTERY SORT", renk: Tema.min)
                Spacer()
                Text(tur > turSayisi ? "\(dogru) / \(turSayisi)" : "Round \(min(tur, turSayisi)) of \(turSayisi)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Tema.soluk)
            }
            if tur > turSayisi {
                VStack(alignment: .leading, spacing: 10) {
                    Text(dogru >= 4 ? "You read algorithms by their movement." : "\(dogru) of \(turSayisi). Watch the patterns again.")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Clues: bubble moves neighbors; selection makes one long swap per pass; insertion grows a sorted left part; merge writes from a buffer; quick works around a purple pivot; heap shrinks from the right; counting never compares.")
                        .font(.callout).foregroundStyle(Tema.soluk)
                    Button("Play again") { tur = 1; dogru = 0; yeniTur() }.buttonStyle(IkinciDugme())
                }
                .kartYuzey()
            } else {
                Text("Which algorithm is this?").font(.system(.title3, design: .rounded, weight: .semibold))
                if kareler.indices.contains(indeks) {
                    Sahne(algoritma: algoritma, kare: gizli(kareler[indeks]), maks: 14, yukseklik: 170, agac: false)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(secenekler) { a in
                        SecenekDugme(metin: a.ad, durum: durum(a)) {
                            guard secim == nil else { return }
                            secim = a
                            if a == algoritma { dogru += 1; Dokunma.basari() } else { Dokunma.hata() }
                        }
                    }
                }
                if secim != nil {
                    Button(tur == turSayisi ? "See result" : "Next round") { tur += 1; if tur <= turSayisi { yeniTur() } else { gorev?.cancel() } }
                        .buttonStyle(AnaDugme())
                }
            }
        }
        .onAppear { if kareler.isEmpty { yeniTur() } }
        .onDisappear { gorev?.cancel() }
    }

    /// Ağaç ve sayaç şeridi ipucu vermesin diye heap/counting'de ek görseller saklanır; renkler kalır.
    private func gizli(_ k: Kare) -> Kare {
        var k = k
        k.ek = nil
        return k
    }

    private func durum(_ a: Algoritma) -> SecenekDugme.Durum {
        guard let secim else { return .notr }
        return a == algoritma ? .dogru : (a == secim ? .yanlis : .soluk)
    }

    private func yeniTur() {
        gorev?.cancel()
        algoritma = Algoritma.allCases.randomElement()!
        secenekler = ([algoritma] + Algoritma.allCases.filter { $0 != algoritma }.shuffled().prefix(3)).shuffled()
        let g = algoritma == .counting ? (0..<14).map { _ in Int.random(in: 1...14) } : Array(1...14).shuffled()
        kareler = Iz(algoritma, g).kareler
        indeks = 0; secim = nil
        gorev = Task { @MainActor in
            while !Task.isCancelled && indeks < kareler.count - 1 {
                try? await Task.sleep(for: .milliseconds(secim == nil ? 70 : 25))
                indeks += 1
            }
        }
    }
}

// MARK: - Yarış

struct Serit: Identifiable {
    let id = UUID()
    let ad: String
    let kareler: [Kare]
    let maks: Int
}

struct YarisGorunumu: View {
    let seritler: [Serit]
    @State private var adim = 0
    @State private var gorev: Task<Void, Never>?

    private var uzun: Int { seritler.map { $0.kareler.count }.max() ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(seritler) { s in
                let k = s.kareler[min(adim, s.kareler.count - 1)]
                let bitti = adim >= s.kareler.count - 1
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(s.ad).font(.system(.subheadline, design: .rounded, weight: .bold))
                        Spacer()
                        if bitti {
                            Label("\(s.kareler.count - 1) steps", systemImage: "flag.checkered")
                                .font(.caption.weight(.semibold)).foregroundStyle(Tema.sirali)
                        }
                    }
                    CubukAlani(kare: k, maks: s.maks, degerler: false).frame(height: 62)
                    Sayaclar(kare: k)
                }
                .kartYuzey(12)
            }
            HStack {
                Button(gorev == nil ? "Race" : "Restart") { basla() }.buttonStyle(AnaDugme(renk: Tema.vurgu))
            }
        }
        .onDisappear { gorev?.cancel() }
        .onChange(of: seritler.map(\.id)) { _, _ in gorev?.cancel(); gorev = nil; adim = 0 }
    }

    private func basla() {
        gorev?.cancel()
        adim = 0
        gorev = Task { @MainActor in
            while !Task.isCancelled && adim < uzun - 1 {
                try? await Task.sleep(for: .milliseconds(28))
                adim += 1
            }
        }
    }
}

struct YarisOyunu: View {
    @State private var a: Algoritma = .insertion
    @State private var b: Algoritma = .merge
    @State private var girdi: Girdi = .rastgele
    @State private var boy = 24
    @State private var seritler: [Serit] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                secici($a)
                Text("vs").font(.caption.weight(.bold)).foregroundStyle(Tema.soluk)
                secici($b)
            }
            HStack(spacing: 8) {
                Picker("Input", selection: $girdi) { ForEach(Girdi.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).tint(Tema.murekkep)
                Picker("Size", selection: $boy) { ForEach([12, 24, 32], id: \.self) { Text("\($0) items").tag($0) } }
                    .pickerStyle(.menu).tint(Tema.murekkep)
            }
            Text("Same input, one step per tick. A step is a comparison or a write.")
                .font(.caption).foregroundStyle(Tema.soluk)
            YarisGorunumu(seritler: seritler)
        }
        .onAppear { if seritler.isEmpty { kur() } }
        .onChange(of: a) { _, _ in kur() }
        .onChange(of: b) { _, _ in kur() }
        .onChange(of: girdi) { _, _ in kur() }
        .onChange(of: boy) { _, _ in kur() }
    }

    private func kur() {
        let g = girdi.uret(boy)
        let m = g.max() ?? 1
        seritler = [Serit(ad: a.ad, kareler: Iz(a, g).kareler, maks: m), Serit(ad: b.ad, kareler: Iz(b, g).kareler, maks: m)]
    }

    private func secici(_ s: Binding<Algoritma>) -> some View {
        Menu {
            Picker("Algorithm", selection: s) { ForEach(Algoritma.allCases) { Text($0.ad).tag($0) } }
        } label: {
            Text(s.wrappedValue.ad).font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Tema.murekkep).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Tema.kart2, in: Capsule())
        }
    }
}

/// KRM-04: aynı insertion sort, üç girdi.
struct DurumlarOyunu: View {
    @State private var seritler: [Serit] = []
    /// Bir kez hesaplanır; görünüm her yeniden kurulduğunda 12 iz yeniden üretilmesin.
    private static let tablo: [(Int, Int, Int, Int)] = [8, 16, 32, 64].map { n in
        let s = Iz(.insertion, Girdi.sirali.uret(n)).kareler.last!.karsilastirma
        let r = Iz(.insertion, Girdi.rastgele.uret(n)).kareler.last!.karsilastirma
        let t = Iz(.insertion, Girdi.ters.uret(n)).kareler.last!.karsilastirma
        return (n, s, r, t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Etiket(metin: "SAME CODE · THREE INPUTS", renk: Tema.yaz)
            YarisGorunumu(seritler: seritler)
            VStack(spacing: 6) {
                HStack {
                    Text("n").frame(width: 34, alignment: .leading)
                    Text("sorted").frame(maxWidth: .infinity)
                    Text("random").frame(maxWidth: .infinity)
                    Text("reversed").frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.bold)).foregroundStyle(Tema.soluk)
                ForEach(Self.tablo, id: \.0) { n, s, r, t in
                    HStack {
                        Text("\(n)").frame(width: 34, alignment: .leading)
                        Text("\(s)").frame(maxWidth: .infinity).foregroundStyle(Tema.sirali)
                        Text("\(r)").frame(maxWidth: .infinity)
                        Text("\(t)").frame(maxWidth: .infinity).foregroundStyle(Tema.takas)
                    }
                    .font(.system(.callout, design: .monospaced))
                }
                Text("Comparisons made by insertion sort. Double n: the sorted column doubles, the reversed column grows four times.")
                    .font(.caption).foregroundStyle(Tema.soluk).padding(.top, 4)
            }
            .kartYuzey()
        }
        .onAppear {
            guard seritler.isEmpty else { return }
            seritler = [(Girdi.sirali, "Best · sorted"), (.rastgele, "Average · random"), (.ters, "Worst · reversed")].map { g, ad in
                let d = g.uret(14)
                return Serit(ad: ad, kareler: Iz(.insertion, d).kareler, maks: 14)
            }
        }
    }
}

// MARK: - Büyüme yarışı

struct BuyumeOyunu: View {
    var kompakt = false
    @State private var us: Double = 1          // n = 10^us
    @State private var sira: [String] = []
    @State private var secilen: [String] = []

    private struct Sinif { let ad: String; let lg: (Double) -> Double }   // lg = log10(işlem sayısı)
    private let siniflar: [Sinif] = [
        Sinif(ad: "O(1)") { _ in 0 },
        Sinif(ad: "O(log n)") { n in log10(max(1, log2(n))) },
        Sinif(ad: "O(n)") { n in log10(n) },
        Sinif(ad: "O(n log n)") { n in log10(n * max(1, log2(n))) },
        Sinif(ad: "O(n²)") { n in 2 * log10(n) },
        Sinif(ad: "O(2ⁿ)") { n in n * log10(2) },
    ]

    private var n: Double { pow(10, us) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("n = \(Int(n.rounded()).formatted())").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                Spacer()
                Text("1 step = 1 nanosecond").font(.caption).foregroundStyle(Tema.soluk)
            }
            Slider(value: $us, in: 0...6, step: 0.25).tint(Tema.vurgu)
            ForEach(siniflar, id: \.ad) { s in
                let lg = s.lg(n)
                HStack(spacing: 10) {
                    Text(s.ad).font(Tema.kodKucuk).frame(width: 78, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(renk(lg)).frame(width: max(6, g.size.width * min(1, lg / 13)))
                            .animation(.snappy, value: us)
                    }
                    .frame(height: 12)
                    Text(sure(lg)).font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit()
                        .frame(width: 92, alignment: .trailing)
                }
            }
            if !kompakt { siralamaOyunu }
        }
        .kartYuzey()
    }

    private var siralamaOyunu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 4)
            Text("Tap from slowest growth to fastest").font(.system(.subheadline, design: .rounded, weight: .semibold))
            FlowCips(ogeler: sira.isEmpty ? siniflar.map(\.ad).shuffled() : sira, secilen: secilen) { ad in
                guard !secilen.contains(ad) else { return }
                let beklenen = siniflar[secilen.count].ad
                if ad == beklenen { secilen.append(ad); Dokunma.hafif(); if secilen.count == siniflar.count { Dokunma.basari() } }
                else { Dokunma.hata() }
            }
            .onAppear { if sira.isEmpty { sira = siniflar.map(\.ad).shuffled() } }
            if secilen.count == siniflar.count {
                Text("1 < log n < n < n log n < n² < 2ⁿ — learn this line by heart.")
                    .font(.callout.weight(.semibold)).foregroundStyle(Tema.dogru)
            }
        }
    }

    private func renk(_ lg: Double) -> Color {
        lg < 3 ? Tema.sirali : (lg < 6 ? Tema.karsilastir : (lg < 9 ? Tema.vurgu : Tema.takas))
    }

    private func sure(_ lg: Double) -> String {
        let s = lg - 9                                   // log10(saniye)
        if s > 17.64 { return "> universe" }
        let sn = pow(10, s)
        switch sn {
        case ..<1e-6: return "\(Int((sn * 1e9).rounded())) ns"
        case ..<1e-3: return String(format: "%.0f µs", sn * 1e6)
        case ..<1: return String(format: "%.0f ms", sn * 1e3)
        case ..<60: return String(format: "%.1f s", sn)
        case ..<3600: return String(format: "%.0f min", sn / 60)
        case ..<86_400: return String(format: "%.0f hours", sn / 3600)
        case ..<31_557_600: return String(format: "%.0f days", sn / 86_400)
        default: return String(format: "%.0e years", sn / 31_557_600)
        }
    }
}

struct FlowCips: View {
    let ogeler: [String]
    let secilen: [String]
    let dokun: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(ogeler, id: \.self) { o in
                let sira = secilen.firstIndex(of: o)
                Button { dokun(o) } label: {
                    HStack(spacing: 4) {
                        if let sira { Text("\(sira + 1)").font(.caption2.weight(.heavy)) }
                        Text(o).font(Tema.kodKucuk)
                    }
                    .foregroundStyle(sira != nil ? Tema.zemin : Tema.murekkep)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(sira != nil ? Tema.dogru : Tema.kart2, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Yarıya böl (ikili arama oyunu)

struct YariyaOyunu: View {
    var bitti: (() -> Void)? = nil
    @State private var hedef = Int.random(in: 1...1000)
    @State private var lo = 1
    @State private var hi = 1000
    @State private var metin = ""
    @State private var gecmis: [(Int, String)] = []
    @State private var bulundu = false
    @State private var bilgisayar: [(Int, Int, Int)] = []
    @FocusState private var odak: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Etiket(metin: "GUESS MY NUMBER · 1–1000", renk: Tema.yaz)
            aralikCubugu
            Text(bulundu ? "Found \(hedef) in \(gecmis.count) tries." : "It is between \(lo) and \(hi).")
                .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
            if !bulundu {
                HStack(spacing: 10) {
                    TextField("Your guess", text: $metin)
                        .keyboardType(.numberPad).focused($odak)
                        .font(.system(.title3, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Tema.kart2, in: RoundedRectangle(cornerRadius: 12))
                    Button("Guess") { tahmin() }.buttonStyle(IkinciDugme())
                }
                Button("Use the middle: \((lo + hi) / 2)") { metin = "\((lo + hi) / 2)"; tahmin() }
                    .font(.footnote.weight(.semibold)).tint(Tema.vurgu)
            } else {
                Text(gecmis.count <= 10 ? "Binary search never needs more than 10 tries here, because 2¹⁰ = 1024 > 1000."
                                        : "Halving every time would need at most 10. Try always guessing the middle.")
                    .font(.callout).foregroundStyle(Tema.soluk)
                HStack {
                    Button("Play again") { sifirla() }.buttonStyle(IkinciDugme())
                    Button("Computer: 1 to 1,000,000") { bilgisayarOyna() }.buttonStyle(IkinciDugme())
                }
            }
            ForEach(Array(gecmis.enumerated().reversed()), id: \.offset) { i, g in
                HStack {
                    Text("\(i + 1).").foregroundStyle(Tema.soluk).frame(width: 26, alignment: .leading)
                    Text("\(g.0)").monospacedDigit().fontWeight(.semibold)
                    Text(g.1).foregroundStyle(g.1 == "found!" ? Tema.dogru : Tema.soluk)
                }
                .font(.system(.callout, design: .rounded))
            }
            if !bilgisayar.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(bilgisayar.enumerated()), id: \.offset) { i, s in
                        Text("\(i + 1). range \(s.0.formatted())–\(s.1.formatted()) → try \(s.2.formatted())")
                            .font(Tema.kodKucuk).foregroundStyle(i == bilgisayar.count - 1 ? Tema.dogru : Tema.murekkep)
                    }
                    Text("\(bilgisayar.count) steps for a million numbers.").font(.callout.weight(.semibold)).padding(.top, 4)
                }
                .kartYuzey(12)
            }
        }
    }

    private var aralikCubugu: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.kart2)
                Capsule().fill(bulundu ? Tema.dogru : Tema.vurgu)
                    .frame(width: max(8, g.size.width * CGFloat(hi - lo + 1) / 1000))
                    .offset(x: g.size.width * CGFloat(lo - 1) / 1000)
            }
            .animation(.snappy, value: lo).animation(.snappy, value: hi)
        }
        .frame(height: 14)
    }

    private func tahmin() {
        guard let t = Int(metin.trimmingCharacters(in: .whitespaces)), (1...1000).contains(t) else { metin = ""; return }
        metin = ""
        if t == hedef {
            gecmis.append((t, "found!")); lo = t; hi = t; bulundu = true; odak = false; Dokunma.basari(); bitti?()
        } else if t < hedef {
            gecmis.append((t, "→ higher")); lo = max(lo, t + 1); Dokunma.hafif()
        } else {
            gecmis.append((t, "→ lower")); hi = min(hi, t - 1); Dokunma.hafif()
        }
    }

    private func sifirla() { hedef = Int.random(in: 1...1000); lo = 1; hi = 1000; gecmis = []; bulundu = false; bilgisayar = [] }

    private func bilgisayarOyna() {
        let h = Int.random(in: 1...1_000_000)
        var l = 1, r = 1_000_000, adimlar: [(Int, Int, Int)] = []
        while l <= r {
            let m = (l + r) / 2
            adimlar.append((l, r, m))
            if m == h { break }
            if m < h { l = m + 1 } else { r = m - 1 }
        }
        withAnimation { bilgisayar = adimlar }
    }
}

// MARK: - Döngü dedektifi

struct DedektifOyunu: View {
    let turlar: [DedektifTuru]
    var bitti: ((Int, Int) -> Void)? = nil
    @State private var i = 0
    @State private var secim: Int?
    @State private var dogru = 0
    @State private var son = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Etiket(metin: "LOOP DETECTIVE", renk: Tema.takas)
                Spacer()
                Text(son ? "\(dogru) / \(turlar.count)" : "\(i + 1) / \(turlar.count)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Tema.soluk)
            }
            if son {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dogru == turlar.count ? "Case closed. Every growth rate found." : "\(dogru) of \(turlar.count) cases solved.")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Side by side: add. Nested: multiply. Halving: log n. Hidden loops hide in library calls.")
                        .font(.callout).foregroundStyle(Tema.soluk)
                    Button("Again") { i = 0; dogru = 0; son = false; secim = nil }.buttonStyle(IkinciDugme())
                }
                .kartYuzey()
            } else {
                let t = turlar[i]
                KodBlogu(metin: t.kod)
                Text("What is the time complexity?").font(.system(.headline, design: .rounded))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(t.secenekler.enumerated()), id: \.offset) { j, s in
                        SecenekDugme(metin: s, kod: true, durum: durum(j, t.dogru)) {
                            guard secim == nil else { return }
                            secim = j
                            if j == t.dogru { dogru += 1; Dokunma.basari() } else { Dokunma.hata() }
                        }
                    }
                }
                if secim != nil {
                    Text(t.aciklama).font(.callout).foregroundStyle(Tema.murekkep)
                    Button(i == turlar.count - 1 ? "See result" : "Next case") {
                        secim = nil
                        if i == turlar.count - 1 { son = true; bitti?(dogru, turlar.count) } else { i += 1 }
                    }
                    .buttonStyle(AnaDugme())
                }
            }
        }
    }

    private func durum(_ j: Int, _ d: Int) -> SecenekDugme.Durum {
        guard let secim else { return .notr }
        return j == d ? .dogru : (j == secim ? .yanlis : .soluk)
    }
}

struct KodBlogu: View {
    let metin: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(metin).font(Tema.kod).foregroundStyle(Tema.kodYazi)
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.kodZemin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
