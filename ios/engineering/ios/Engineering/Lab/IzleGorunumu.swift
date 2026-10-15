import SwiftUI

/// İzle: algoritmayı kare kare oynatır; yanan Python satırı, açıklama, sayaçlar.
/// Derste algoritma sabittir; Lab'da seçilir.
struct IzleGorunumu: View {
    @State var algoritma: Algoritma
    var secilebilir = false
    var baslangicBoyu = 10

    @State private var girdi: Girdi = .rastgele
    @State private var boy = 10
    @State private var kareler: [Kare] = []
    @State private var maks = 10
    @State private var indeks = 0
    @State private var oynuyor = false
    @State private var hiz = 1.0
    @State private var gorev: Task<Void, Never>?

    private var kod: Kod? { Kutuphane.shared.ders(algoritma: algoritma)?.kod }
    private var kare: Kare { kareler.indices.contains(indeks) ? kareler[indeks] : Kare(dizi: []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if secilebilir {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Algoritma.allCases) { a in
                            Button(a.kisa) { algoritma = a; yenile() }
                                .buttonStyle(SecimCipi(secili: a == algoritma))
                        }
                    }
                }
            }
            HStack {
                Menu {
                    Picker("Input", selection: $girdi) { ForEach(Girdi.allCases) { Text($0.rawValue).tag($0) } }
                } label: { menuEtiketi(girdi.rawValue, "dice") }
                if secilebilir {
                    Menu {
                        Picker("Size", selection: $boy) { ForEach([6, 8, 10, 16, 24, 32], id: \.self) { Text("\($0) items").tag($0) } }
                    } label: { menuEtiketi("\(boy)", "chart.bar") }
                }
                Spacer()
                Menu {
                    Picker("Speed", selection: $hiz) {
                        ForEach([0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                    }
                } label: { menuEtiketi(String(format: "%g×", hiz), "speedometer") }
            }

            Sahne(algoritma: algoritma, kare: kare, maks: maks)

            Text(kare.aciklama)
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(Tema.murekkep)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .contentTransition(.opacity)
            Sayaclar(kare: kare, adim: (indeks, max(kareler.count - 1, 0)))

            HStack(spacing: 12) {
                kontrol("backward.end.fill") { durdur(); indeks = 0 }
                kontrol("backward.frame.fill") { durdur(); indeks = max(0, indeks - 1) }
                Button { oynuyor ? durdur() : oynat() } label: {
                    Image(systemName: oynuyor ? "pause.fill" : "play.fill")
                        .font(.title2).foregroundStyle(Tema.zemin)
                        .frame(width: 60, height: 60).background(Tema.murekkep, in: Circle())
                }
                .buttonStyle(.plain)
                kontrol("forward.frame.fill") { durdur(); indeks = min(kareler.count - 1, indeks + 1) }
                kontrol("arrow.clockwise") { yenile() }
            }
            .frame(maxWidth: .infinity)

            if let kod {
                KodPaneli(kod: kod, satir: kare.etiket.flatMap { kod.etiketler[$0] })
            }
        }
        .onAppear { if kareler.isEmpty { boy = baslangicBoyu; yenile() } }
        .onChange(of: girdi) { _, _ in yenile() }
        .onChange(of: boy) { _, _ in yenile() }
        .onDisappear { durdur() }
    }

    private func yenile() {
        durdur()
        let g = girdi.uret(boy)
        kareler = Iz(algoritma, g).kareler
        maks = max(g.max() ?? 1, 1)
        indeks = 0
    }

    private func oynat() {
        if indeks >= kareler.count - 1 { indeks = 0 }
        oynuyor = true
        gorev = Task { @MainActor in
            while !Task.isCancelled && indeks < kareler.count - 1 {
                try? await Task.sleep(for: .milliseconds(Int(520 / hiz)))
                if Task.isCancelled { break }
                indeks += 1
            }
            oynuyor = false
        }
    }

    private func durdur() { gorev?.cancel(); gorev = nil; oynuyor = false }

    private func kontrol(_ simge: String, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Image(systemName: simge).font(.body).foregroundStyle(Tema.murekkep)
                .frame(width: 44, height: 44).background(Tema.kart2, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func menuEtiketi(_ metin: String, _ simge: String) -> some View {
        Label(metin, systemImage: simge)
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(Tema.murekkep)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Tema.kart2, in: Capsule())
    }
}

struct SecimCipi: ButtonStyle {
    var secili: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(secili ? Tema.zemin : Tema.murekkep)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(secili ? Tema.murekkep : Tema.kart2, in: Capsule())
    }
}

// MARK: - Sen CPU'sun

/// İzle'nin karelerinden oynar; karar karesinde durur, hamleyi sana sorar.
struct CPUOyunu: View {
    let algoritma: Algoritma
    var bitti: ((Int, Int) -> Void)? = nil

    @State private var kareler: [Kare] = []
    @State private var maks = 9
    @State private var indeks = 0
    @State private var bekleyen = false
    @State private var secim: Int?
    @State private var dogru = 0
    @State private var toplam = 0
    @State private var gorev: Task<Void, Never>?
    @State private var sonuc = false

    private var kare: Kare { kareler.indices.contains(indeks) ? kareler[indeks] : Kare(dizi: []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Etiket(metin: "YOU ARE THE CPU", renk: Tema.vurgu)
                Spacer()
                Text("\(dogru) / \(toplam)").font(.system(.headline, design: .rounded)).monospacedDigit()
            }
            Sahne(algoritma: algoritma, kare: kare, maks: maks, yukseklik: 160)
            if sonuc {
                sonucKarti
            } else if bekleyen, let k = kare.karar {
                Text(k.soru).font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(Tema.murekkep)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(Array(k.secenekler.enumerated()), id: \.offset) { i, s in
                        SecenekDugme(metin: s, durum: durum(i, k)) { sec(i, k) }
                    }
                }
                if let secim {
                    Text(k.aciklama)
                        .font(.callout).foregroundStyle(secim == k.dogru ? Tema.dogru : Tema.yanlis)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Continue") { devam() }.buttonStyle(AnaDugme())
                }
            } else {
                Text(kare.aciklama).font(.callout).foregroundStyle(Tema.soluk).frame(minHeight: 40, alignment: .top)
                Button("Skip to the end") { sona() }.buttonStyle(IkinciDugme())
            }
        }
        .onAppear { if kareler.isEmpty { basla() } }
        .onDisappear { gorev?.cancel() }
    }

    private var sonucKarti: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dogru == toplam ? "Flawless. You ran \(algoritma.ad) by hand." : "\(dogru) of \(toplam) moves were right.")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("\(kare.karsilastirma) comparisons, \(kare.yazma) writes for \(kare.dizi.count) items.")
                .font(.callout).foregroundStyle(Tema.soluk)
            HStack {
                Button("Play again") { basla() }.buttonStyle(IkinciDugme())
                Spacer()
            }
        }
        .kartYuzey()
    }

    private func durum(_ i: Int, _ k: Karar) -> SecenekDugme.Durum {
        guard let secim else { return .notr }
        if i == k.dogru { return .dogru }
        if i == secim { return .yanlis }
        return .soluk
    }

    private func basla() {
        gorev?.cancel()
        let g = oyunGirdisi(algoritma, n: algoritma == .heap ? 7 : 6)
        kareler = Iz(algoritma, g).kareler
        maks = max(g.max() ?? 1, 1)
        indeks = 0; dogru = 0; toplam = 0; secim = nil; bekleyen = false; sonuc = false
        ilerle()
    }

    /// Bir sonraki karar karesine kadar oynat.
    private func ilerle() {
        gorev = Task { @MainActor in
            while !Task.isCancelled && indeks < kareler.count - 1 {
                try? await Task.sleep(for: .milliseconds(380))
                if Task.isCancelled { return }
                indeks += 1
                if kareler[indeks].karar != nil { bekleyen = true; return }
            }
            if indeks >= kareler.count - 1 { bitir() }
        }
    }

    private func sec(_ i: Int, _ k: Karar) {
        guard secim == nil else { return }
        secim = i; toplam += 1
        if i == k.dogru { dogru += 1; Dokunma.basari() } else { Dokunma.hata() }
        if i == k.dogru {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                if secim == i && bekleyen { devam() }
            }
        }
    }

    private func devam() { secim = nil; bekleyen = false; ilerle() }

    private func sona() { gorev?.cancel(); indeks = kareler.count - 1; bitir() }

    private func bitir() {
        sonuc = true
        bitti?(dogru, toplam)
    }
}
