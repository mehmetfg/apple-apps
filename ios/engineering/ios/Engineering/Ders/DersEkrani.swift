import SwiftUI

enum Adim: Hashable {
    case kanca, kart(Int), izle, cpu, tahmin, oyun(String), kod, parsons, quiz, sozluk, bitis

    var etkilesimli: Bool {
        switch self {
        case .cpu, .tahmin, .oyun, .parsons, .quiz: true
        default: false
        }
    }
    var ad: String {
        switch self {
        case .kanca: "Question"
        case .kart: "Learn"
        case .izle: "Watch"
        case .cpu: "Be the CPU"
        case .tahmin: "Predict"
        case .oyun(let o): ["buyume": "Growth race", "dedektif": "Detective", "yariya": "Halving game",
                            "durumlar": "Case lab", "yaris": "Race"][o] ?? "Play"
        case .kod: "Code"
        case .parsons: "Build it"
        case .quiz: "Quiz"
        case .sozluk: "Engineer's English"
        case .bitis: "Done"
        }
    }
}

struct DersEkrani: View {
    let ders: Ders
    var baslangic = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(Ilerleme.self) private var ilerleme
    @State private var i = 0
    @State private var tamam: Set<Int> = []
    @State private var quiz: (Int, Int)?
    @State private var cpu: (Int, Int)?

    private var renk: Color { Tema.alan(Kutuphane.shared.alan(ofMesele: ders.mesele)?.renk ?? "") }

    private var adimlar: [Adim] {
        var a: [Adim] = [.kanca]
        a += ders.kartlar.indices.map { .kart($0) }
        if ders.lab != nil { a += [.izle, .cpu, .tahmin] }
        if let o = ders.oyun { a.append(.oyun(o)) }
        a.append(.kod)
        if ders.parsons != nil { a.append(.parsons) }
        a += [.quiz, .sozluk, .bitis]
        return a
    }

    var body: some View {
        VStack(spacing: 0) {
            ust
            ScrollView {
                icerik(adimlar[i])
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(i)
            .scrollDismissesKeyboard(.interactively)
            if adimlar[i] != .bitis { alt }
        }
        .background(Tema.zemin.ignoresSafeArea())
        .terimSecimi()
        .onAppear { if baslangic > 0 { i = min(baslangic, adimlar.count - 1) } }
    }

    // MARK: üst ve alt çubuk

    private var ust: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Tema.murekkep)
                        .frame(width: 36, height: 36).background(Tema.kart2, in: Circle())
                }
                HStack(spacing: 3) {
                    ForEach(adimlar.indices, id: \.self) { k in
                        Capsule().fill(k <= i ? renk : Tema.cizgi).frame(height: 5)
                    }
                }
            }
            HStack {
                Text(adimlar[i].ad.uppercased()).font(.system(.caption, design: .rounded, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(renk)
                Spacer()
                Text(ders.baslik).font(.caption).foregroundStyle(Tema.soluk).lineLimit(1)
            }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
    }

    private var alt: some View {
        HStack(spacing: 12) {
            if i > 0 {
                Button { withAnimation(.snappy) { i -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.headline).foregroundStyle(Tema.murekkep)
                        .frame(width: 52, height: 52).background(Tema.kart2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            let hazir = !adimlar[i].etkilesimli || tamam.contains(i)
            Button(hazir ? "Continue" : "Skip") { ilerle() }
                .buttonStyle(AnaDugme(renk: hazir ? Tema.murekkep : Tema.soluk.opacity(0.6)))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Tema.zemin)
    }

    private func ilerle() {
        Dokunma.hafif()
        withAnimation(.snappy) { i = min(i + 1, adimlar.count - 1) }
    }

    private func bitti(_ k: Int) { tamam.insert(k) }

    // MARK: adımlar

    @ViewBuilder
    private func icerik(_ a: Adim) -> some View {
        switch a {
        case .kanca: KancaAdimi(ders: ders, renk: renk, adimlar: adimlar)
        case .kart(let k): KartAdimi(kart: ders.kartlar[k], sira: k + 1, toplam: ders.kartlar.count)
        case .izle:
            VStack(alignment: .leading, spacing: 10) {
                Text("Press play. Watch the colors and the yellow line of code.")
                    .font(.callout).foregroundStyle(Tema.soluk)
                if let al = ders.lab.flatMap({ Algoritma(rawValue: $0.algoritma) }) { IzleGorunumu(algoritma: al) }
                Renkler()
            }
        case .cpu:
            if let al = ders.lab.flatMap({ Algoritma(rawValue: $0.algoritma) }) {
                CPUOyunu(algoritma: al) { d, t in cpu = (d, t); bitti(i) }
            }
        case .tahmin:
            if let al = ders.lab.flatMap({ Algoritma(rawValue: $0.algoritma) }) {
                TahminOyunu(algoritma: al) { _, _ in bitti(i) }
            }
        case .oyun(let o): oyun(o)
        case .kod: KodAdimi(kod: ders.kod, c: ders.c)
        case .parsons: if let p = ders.parsons { ParsonsAdimi(parsons: p) { bitti(i) } }
        case .quiz:
            QuizGorunumu(sorular: ders.quiz.indices.map { (ders, $0) }) { d, t in quiz = (d, t); bitti(i) }
        case .sozluk: SozlukAdimi(ders: ders)
        case .bitis:
            BitisAdimi(ders: ders, quiz: quiz, cpu: cpu, renk: renk) {
                ilerleme.bitir(ders.id, quiz: quiz?.0 ?? 0, quizToplam: quiz?.1 ?? 0, cpu: cpu?.0, cpuToplam: cpu?.1)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func oyun(_ o: String) -> some View {
        switch o {
        case "buyume": BuyumeOyunu().onAppear { bitti(i) }
        case "dedektif": DedektifOyunu(turlar: ders.dedektif ?? []) { _, _ in bitti(i) }
        case "yariya": YariyaOyunu { bitti(i) }
        case "durumlar": DurumlarOyunu().onAppear { bitti(i) }
        case "yaris": YarisOyunu().onAppear { bitti(i) }
        default: EmptyView()
        }
    }
}

struct Renkler: View {
    var body: some View {
        HStack(spacing: 12) {
            nokta(Tema.karsilastir, "compare"); nokta(Tema.takas, "swap"); nokta(Tema.pivot, "pivot")
            nokta(Tema.yaz, "write/key"); nokta(Tema.sirali, "in place")
        }
        .font(.caption2).foregroundStyle(Tema.soluk)
    }
    private func nokta(_ r: Color, _ ad: String) -> some View {
        HStack(spacing: 4) { Circle().fill(r).frame(width: 7, height: 7); Text(ad) }
    }
}

// MARK: - Kanca

struct KancaAdimi: View {
    let ders: Ders
    let renk: Color
    let adimlar: [Adim]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Etiket(metin: "\(ders.mesele) · \(Kutuphane.shared.alan(ofMesele: ders.mesele)?.en.uppercased() ?? "")", renk: renk)
            VStack(alignment: .leading, spacing: 4) {
                Text(ders.baslik).font(Tema.baslik(.largeTitle)).foregroundStyle(Tema.murekkep)
                Text(ders.baslik_tr).font(.callout).foregroundStyle(Tema.soluk)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(ders.kanca)
                    .font(.system(.title2, design: .serif, weight: .medium))
                    .foregroundStyle(Tema.murekkep)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TurkceDestek(metin: ders.kanca_tr)
                    Spacer()
                    Button { Ses.shared.soyle(ders.kanca) } label: { Image(systemName: "speaker.wave.2") }
                        .foregroundStyle(Tema.soluk)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(renk.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.top, 10)

            Text("THE PATH").font(.system(.caption, design: .rounded, weight: .heavy)).foregroundStyle(Tema.soluk).padding(.top, 8)
            let gruplu = adimlar.dropFirst().reduce(into: [String]()) { s, a in if s.last != a.ad { s.append(a.ad) } }
            FlowYazi(ogeler: gruplu)
            Text("Tip: dotted words are tappable — meaning, pronunciation, example.")
                .font(.caption).foregroundStyle(Tema.soluk)
        }
    }
}

struct FlowYazi: View {
    let ogeler: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(ogeler.enumerated()), id: \.offset) { k, o in
                HStack(spacing: 5) {
                    Text("\(k + 1)").font(.caption2.weight(.heavy)).foregroundStyle(Tema.soluk)
                    Text(o).font(.system(.caption, design: .rounded, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tema.kart, in: Capsule())
            }
        }
    }
}

// MARK: - Kart

struct KartAdimi: View {
    let kart: Kart
    let sira: Int
    let toplam: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(sira) / \(toplam)").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Tema.soluk)
            Text(kart.baslik).font(Tema.baslik(.title)).foregroundStyle(Tema.murekkep)
            BagliText(metin: kart.metin, font: .system(size: 19))
            HStack {
                TurkceDestek(metin: kart.tr)
                Spacer()
                SesDugmeleri(metin: kart.metin)
            }
            if kart.gorsel == "buyume" { BuyumeOyunu(kompakt: true).padding(.top, 6) }
        }
    }
}

// MARK: - Kod

struct KodAdimi: View {
    let kod: Kod
    let c: CPerdesi?
    @State private var secili: Int?
    @State private var cAcik = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Read the Python").font(Tema.baslik()).foregroundStyle(Tema.murekkep)
            Text("Tap a line with a dot.").font(.callout).foregroundStyle(Tema.soluk)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(kod.satirlar.enumerated()), id: \.offset) { k, s in
                    let notlu = kod.notlar.contains { $0.satir == k + 1 }
                    Button { if notlu { withAnimation(.snappy) { secili = k + 1 } } } label: {
                        HStack(spacing: 8) {
                            Circle().fill(notlu ? Tema.vurgu : .clear).frame(width: 5, height: 5)
                            Text("\(k + 1)").foregroundStyle(Tema.kodYazi.opacity(0.35)).frame(width: 18, alignment: .trailing)
                            Text(s.isEmpty ? " " : s).foregroundStyle(Tema.kodYazi).lineLimit(1).fixedSize()
                            Spacer(minLength: 0)
                        }
                        .font(Tema.kodKucuk)
                        .padding(.vertical, 3).padding(.horizontal, 8)
                        .background(secili == k + 1 ? Tema.vurgu.opacity(0.3) : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.kodZemin, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ForEach(kod.notlar, id: \.satir) { n in
                VStack(alignment: .leading, spacing: 6) {
                    Text("LINE \(n.satir)").font(.system(.caption2, design: .rounded, weight: .heavy))
                        .foregroundStyle(secili == n.satir ? Tema.vurgu : Tema.soluk)
                    BagliText(metin: n.en, font: .callout)
                    TurkceDestek(metin: n.tr)
                }
                .kartYuzey(14)
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Tema.vurgu, lineWidth: secili == n.satir ? 1.5 : 0))
                .onTapGesture { withAnimation(.snappy) { secili = n.satir } }
            }

            if let c {
                VStack(alignment: .leading, spacing: 12) {
                    Button { withAnimation(.snappy) { cAcik.toggle() } } label: {
                        HStack {
                            Image(systemName: "cpu")
                            Text("Under the hood: the same idea in C").font(.system(.headline, design: .rounded))
                            Spacer()
                            Image(systemName: cAcik ? "chevron.up" : "chevron.down").font(.footnote)
                        }
                        .foregroundStyle(Tema.murekkep)
                    }
                    .buttonStyle(.plain)
                    if cAcik {
                        KodBlogu(metin: c.metin)
                        BagliText(metin: c.en, font: .callout)
                        TurkceDestek(metin: c.tr)
                    }
                }
                .kartYuzey()
            }
        }
    }
}

// MARK: - Parsons

struct ParsonsAdimi: View {
    let parsons: Parsons
    var bitti: () -> Void

    struct Satir: Identifiable, Hashable { let id = UUID(); let metin: String }
    @State private var havuz: [Satir] = []
    @State private var cevap: [Satir] = []
    @State private var sonuc: [Bool]?
    @State private var basarili = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Build the code").font(Tema.baslik()).foregroundStyle(Tema.murekkep)
            Text("Tap the lines in the right order. One line is a trap and does not belong.")
                .font(.callout).foregroundStyle(Tema.soluk)

            VStack(alignment: .leading, spacing: 4) {
                if cevap.isEmpty {
                    Text("Your program").font(Tema.kodKucuk).foregroundStyle(Tema.kodYazi.opacity(0.4)).padding(10)
                }
                ForEach(Array(cevap.enumerated()), id: \.element.id) { k, s in
                    Button {
                        guard !basarili else { return }
                        withAnimation(.snappy) { cevap.remove(at: k); havuz.append(s); sonuc = nil }
                    } label: { satir(s.metin, renk: sonuc.map { $0[k] ? Tema.dogru : Tema.yanlis }) }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(Tema.kodZemin, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !basarili {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(havuz) { s in
                        Button {
                            Dokunma.hafif()
                            withAnimation(.snappy) { havuz.removeAll { $0.id == s.id }; cevap.append(s); sonuc = nil }
                        } label: { satir(s.metin, renk: nil, acik: true) }
                        .buttonStyle(.plain)
                    }
                }
                Button("Check") { kontrol() }
                    .buttonStyle(AnaDugme(renk: Tema.vurgu))
                    .disabled(cevap.count != parsons.satirlar.count)
                    .opacity(cevap.count != parsons.satirlar.count ? 0.4 : 1)
            } else {
                Label("It runs. Every line is in its place.", systemImage: "checkmark.seal.fill")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(Tema.dogru)
            }
        }
        .onAppear {
            guard havuz.isEmpty && cevap.isEmpty else { return }
            havuz = (parsons.satirlar + (parsons.yanlis ?? [])).map { Satir(metin: $0) }.shuffled()
        }
    }

    private func satir(_ m: String, renk: Color?, acik: Bool = false) -> some View {
        Text(m)
            .font(Tema.kodKucuk)
            .foregroundStyle(acik ? Tema.murekkep : Tema.kodYazi)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(acik ? Tema.kart : (renk?.opacity(0.28) ?? Color.white.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(acik ? Tema.cizgi : .clear, lineWidth: 0.5))
    }

    private func kontrol() {
        let s = cevap.enumerated().map { $0.element.metin == parsons.satirlar[$0.offset] }
        withAnimation(.snappy) { sonuc = s }
        if s.allSatisfy({ $0 }) { basarili = true; Dokunma.basari(); bitti() } else { Dokunma.hata() }
    }
}

// MARK: - Quiz

struct QuizGorunumu: View {
    let sorular: [(Ders, Int)]
    var bitti: (Int, Int) -> Void
    @Environment(Ilerleme.self) private var ilerleme
    @State private var k = 0
    @State private var secim: Int?
    @State private var dogru = 0
    @State private var son = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if son || sorular.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(dogru) / \(sorular.count)").font(.system(size: 54, weight: .bold, design: .rounded))
                    Text(dogru == sorular.count ? "Clean sheet." : (dogru * 2 >= sorular.count ? "Solid. The misses will come back in Mixed review."
                                                                                               : "The misses will come back in Mixed review."))
                        .font(.callout).foregroundStyle(Tema.soluk)
                }
                .kartYuzey(20)
            } else {
                let (d, n) = sorular[k]
                let s = d.quiz[n]
                HStack {
                    Text("\(k + 1) / \(sorular.count)").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Tema.soluk)
                    Spacer()
                    if sorular.contains(where: { $0.0.id != sorular[0].0.id }) {
                        Text(d.baslik).font(.caption).foregroundStyle(Tema.soluk)
                    }
                }
                BagliText(metin: s.soru, font: .system(.title3, design: .rounded, weight: .semibold))
                if let kod = s.kod { KodBlogu(metin: kod) }
                VStack(spacing: 8) {
                    ForEach(Array(s.secenekler.enumerated()), id: \.offset) { j, sec in
                        SecenekDugme(metin: sec.replacingOccurrences(of: "`", with: ""), kod: sec.hasPrefix("`") || sec.hasPrefix("["),
                                     durum: durum(j, s.dogru)) {
                            guard secim == nil else { return }
                            secim = j
                            let iyi = j == s.dogru
                            if iyi { dogru += 1; Dokunma.basari() } else { Dokunma.hata() }
                            ilerleme.cevap("\(d.id)#\(n)", dogru: iyi)
                        }
                    }
                }
                if secim != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        BagliText(metin: s.aciklama, font: .callout)
                        if let tr = s.aciklama_tr { TurkceDestek(metin: tr) }
                    }
                    .kartYuzey(14)
                    Button(k == sorular.count - 1 ? "Finish quiz" : "Next question") {
                        secim = nil
                        if k == sorular.count - 1 { son = true; bitti(dogru, sorular.count) } else { withAnimation(.snappy) { k += 1 } }
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

// MARK: - Mühendis İngilizcesi

struct SozlukAdimi: View {
    let ders: Ders
    @Environment(Ilerleme.self) private var ilerleme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Engineer's English").font(Tema.baslik()).foregroundStyle(Tema.murekkep)
            Text("Five words to keep, one sentence to say out loud, one trap to avoid.")
                .font(.callout).foregroundStyle(Tema.soluk)

            ForEach(ders.sozluk) { t in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(t.terim).font(.system(.title3, design: .rounded, weight: .bold))
                        Text(t.ipa).font(.system(.footnote, design: .serif)).foregroundStyle(Tema.soluk)
                        Spacer()
                        Button { Ses.shared.soyle(t.terim) } label: { Image(systemName: "speaker.wave.2.fill") }
                            .foregroundStyle(Tema.murekkep)
                        Button { ilerleme.bilinenDegistir(t) } label: {
                            Image(systemName: ilerleme.biliyor(t) ? "checkmark.seal.fill" : "seal")
                        }
                        .foregroundStyle(ilerleme.biliyor(t) ? Tema.dogru : Tema.soluk)
                    }
                    Text(t.tr).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.vurgu)
                    Text(t.kalip).font(.system(.callout, design: .monospaced)).foregroundStyle(Tema.murekkep)
                    Button { Ses.shared.soyle(t.ornek) } label: {
                        Text(t.ornek).font(.callout).foregroundStyle(Tema.soluk).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                .kartYuzey(14)
            }

            VStack(alignment: .leading, spacing: 10) {
                Etiket(metin: "SAY IT IN THE INTERVIEW", renk: Tema.yaz)
                Text(ders.cumle.en).font(.system(.title3, design: .serif)).foregroundStyle(Tema.murekkep)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TurkceDestek(metin: ders.cumle.tr)
                    Spacer()
                    SesDugmeleri(metin: ders.cumle.en)
                }
                Text("Listen, then say it twice without looking.").font(.caption).foregroundStyle(Tema.soluk)
            }
            .kartYuzey()

            VStack(alignment: .leading, spacing: 10) {
                Etiket(metin: "TRAP FOR TURKISH SPEAKERS", renk: Tema.takas)
                Label { Text(ders.tuzak.yanlis).strikethrough(color: Tema.yanlis) } icon: {
                    Image(systemName: "xmark").foregroundStyle(Tema.yanlis)
                }
                Label { Text(ders.tuzak.dogru).fontWeight(.semibold) } icon: {
                    Image(systemName: "checkmark").foregroundStyle(Tema.dogru)
                }
                Text(ders.tuzak.not).font(.callout).foregroundStyle(Tema.soluk).fixedSize(horizontal: false, vertical: true)
            }
            .kartYuzey()
        }
    }
}

// MARK: - Bitiş

struct BitisAdimi: View {
    let ders: Ders
    let quiz: (Int, Int)?
    let cpu: (Int, Int)?
    let renk: Color
    let kaydet: () -> Void
    @Environment(Ilerleme.self) private var ilerleme
    @State private var cumle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(renk).padding(.top, 20)
            Text("Lesson complete").font(Tema.baslik(.largeTitle))
            Text(ders.ozet).font(.system(.title3, design: .serif)).foregroundStyle(Tema.murekkep)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let quiz { kutu("\(quiz.0)/\(quiz.1)", "quiz") }
                if let cpu, cpu.1 > 0 { kutu("\(cpu.0)/\(cpu.1)", "CPU moves") }
                kutu("\(ders.sozluk.count)", "new words")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("In your own words").font(.system(.headline, design: .rounded))
                Text("One sentence. English if you can, Turkish if you must. Optional.").font(.caption).foregroundStyle(Tema.soluk)
                TextField("e.g. \(ders.cumle.en.prefix(48))…", text: $cumle, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(Tema.kart, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tema.cizgi, lineWidth: 0.5))
            }
            Button("Finish") {
                ilerleme.cumleYaz(ders.id, cumle)
                Dokunma.basari()
                kaydet()
            }
            .buttonStyle(AnaDugme(renk: renk))
        }
        .onAppear { cumle = ilerleme.cumle(ders.id) }
    }

    private func kutu(_ d: String, _ ad: String) -> some View {
        VStack(spacing: 2) {
            Text(d).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text(ad).font(.caption).foregroundStyle(Tema.soluk)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 16))
    }
}
