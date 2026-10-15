import SwiftUI

/// Lab: derslerden bağımsız oyun parkı. Kayıt tutmaz.
struct LabEkrani: View {
    enum Oyun: String, Identifiable, CaseIterable {
        case izle, yaris, gizem, cpu, tahmin, buyume, yariya, kopya
        var id: String { rawValue }
        var ad: String {
            switch self {
            case .izle: "Playground"
            case .yaris: "Sort race"
            case .gizem: "Mystery sort"
            case .cpu: "Be the CPU"
            case .tahmin: "Predict the pass"
            case .buyume: "Growth race"
            case .yariya: "Guess my number"
            case .kopya: "Cheat sheet"
            }
        }
        var alt: String {
            switch self {
            case .izle: "Any sort, any input, step by step"
            case .yaris: "Two algorithms, same input"
            case .gizem: "Name the sort by its movement"
            case .cpu: "Make every move yourself"
            case .tahmin: "What does the list look like after…?"
            case .buyume: "1, log n, n, n log n, n², 2ⁿ"
            case .yariya: "Binary search, by hand"
            case .kopya: "Time, memory, stability"
            }
        }
        var simge: String {
            switch self {
            case .izle: "play.square.stack"
            case .yaris: "flag.checkered.2.crossed"
            case .gizem: "questionmark.diamond"
            case .cpu: "cpu"
            case .tahmin: "eye"
            case .buyume: "chart.line.uptrend.xyaxis"
            case .yariya: "divide.circle"
            case .kopya: "tablecells"
            }
        }
        var renk: Color {
            switch self {
            case .izle: Tema.yaz
            case .yaris: Tema.vurgu
            case .gizem: Tema.min
            case .cpu: Tema.takas
            case .tahmin: Tema.pivot
            case .buyume: Tema.karsilastir
            case .yariya: Tema.sirali
            case .kopya: Tema.soluk
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lab").font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text("Play with the ideas. Nothing here is graded.").font(.footnote).foregroundStyle(Tema.soluk)
                    }
                    .padding(.top, 12)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Oyun.allCases) { o in
                            NavigationLink(value: o) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: o.simge).font(.title2).foregroundStyle(o.renk)
                                        .frame(width: 46, height: 46).background(o.renk.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                                    Text(o.ad).font(.system(.headline, design: .rounded)).foregroundStyle(Tema.murekkep)
                                    Text(o.alt).font(.caption).foregroundStyle(Tema.soluk).multilineTextAlignment(.leading)
                                        .lineLimit(2, reservesSpace: true)
                                }
                                .kartYuzey(14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(Tema.zemin.ignoresSafeArea())
            .navigationDestination(for: Oyun.self) { o in
                ScrollView {
                    oyun(o).padding(18)
                }
                .background(Tema.zemin.ignoresSafeArea())
                .navigationTitle(o.ad)
                .navigationBarTitleDisplayMode(.inline)
                .terimSecimi()
            }
        }
    }

    @ViewBuilder
    private func oyun(_ o: Oyun) -> some View {
        switch o {
        case .izle: IzleGorunumu(algoritma: .quick, secilebilir: true, baslangicBoyu: 16)
        case .yaris: YarisOyunu()
        case .gizem: GizemOyunu()
        case .cpu: AlgoritmaSecici { CPUOyunu(algoritma: $0).id($0) }
        case .tahmin: AlgoritmaSecici { TahminOyunu(algoritma: $0).id($0) }
        case .buyume: BuyumeOyunu()
        case .yariya: YariyaOyunu()
        case .kopya: KopyaKagidi()
        }
    }
}

struct AlgoritmaSecici<Icerik: View>: View {
    @ViewBuilder let icerik: (Algoritma) -> Icerik
    @State private var a: Algoritma = .bubble
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Algoritma.allCases) { x in
                        Button(x.kisa) { a = x }.buttonStyle(SecimCipi(secili: x == a))
                    }
                }
            }
            icerik(a)
        }
    }
}

struct KopyaKagidi: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("")
                    Text("best"); Text("avg"); Text("worst"); Text("mem"); Text("stable")
                }
                .font(.caption2.weight(.heavy)).foregroundStyle(Tema.soluk)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Algoritma.allCases) { a in
                    let o = a.ozellik
                    GridRow {
                        Text(a.kisa).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        hucre(o.iyi); hucre(o.ort); hucre(o.kotu); hucre(o.bellek)
                        Image(systemName: o.kararli ? "checkmark" : "xmark").foregroundStyle(o.kararli ? Tema.dogru : Tema.yanlis)
                            .font(.caption.weight(.bold))
                    }
                }
            }
            .kartYuzey()
            VStack(alignment: .leading, spacing: 8) {
                satir("Small or nearly sorted", "Insertion")
                satir("General purpose", "Library sort (Timsort · introsort)")
                satir("Guaranteed n log n, stable", "Merge")
                satir("n log n, O(1) memory", "Heap")
                satir("Small integer keys", "Counting")
                satir("Learning only", "Bubble · Selection")
            }
            .kartYuzey()
            Text("Any sort that only compares items needs about n log n comparisons in the worst case. Counting sort escapes that because it never compares.")
                .font(.caption).foregroundStyle(Tema.soluk)
        }
    }
    private func hucre(_ s: String) -> some View {
        Text(s).font(Tema.kodKucuk).foregroundStyle(renk(s))
    }
    private func renk(_ s: String) -> Color {
        if s == "n²" { return Tema.takas }
        if s == "n" || s == "1" || s == "n + k" { return Tema.dogru }
        return Tema.murekkep
    }
    private func satir(_ a: String, _ b: String) -> some View {
        HStack(alignment: .top) {
            Text(a).font(.callout).foregroundStyle(Tema.soluk).frame(width: 150, alignment: .leading)
            Text(b).font(.system(.callout, design: .rounded, weight: .semibold))
        }
    }
}
