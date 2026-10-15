import SwiftUI

/// Bütün ses ayarlarının tek ekranı. Her deri buraya açılır; derilerin kendi panelleri bunun kısa yollarıdır.
struct SesLab: View {
    @EnvironmentObject var calar: Calar
    @EnvironmentObject var ses: Ses
    @Environment(\.dismiss) private var kapat
    @State private var yuvaSor = false

    var body: some View {
        NavigationStack {
            Form {
                ustBolum
                eqBolumu
                Section {
                    Toggle(isOn: $ses.ayar.maximizer) { Etiket("Sonic Maximizer", "BBE tarzı: bas konturu + müziğe göre açılan tiz; netlik ve parlaklık") }
                    if ses.ayar.maximizer {
                        Surgu("Bas konturu", $ses.ayar.maxBas, 0...10)
                        Surgu("Netlik (process)", $ses.ayar.maxNetlik, 0...10)
                    }
                } header: { Text("Netlik") }

                Section {
                    Picker("Bas kipi", selection: $ses.ayar.bas) {
                        ForEach(BasKipi.allCases) { Text($0.ad).tag($0) }
                    }
                    if ses.ayar.bas != .kapali { Surgu("Seviye", $ses.ayar.basSeviye, 0...10) }
                    if ses.ayar.bas == .mach3 { Surgu("Kesim frekansı", $ses.ayar.basFrekans, 20...150, birim: " Hz", adim: 5) }
                    Surgu("Psikoakustik bas", $ses.ayar.psikoBas, 0...10)
                } header: { Text("Bas") } footer: {
                    Text("Mega Bass ve Groove kasetli Walkman'dan, Mach3Bass Cowon'dan. Psikoakustik bas, küçük kulaklığın veremediği derin bası harmoniklerle duyurur.")
                }

                Section {
                    Surgu("Tiz onarımı", $ses.ayar.tiz, 0...10)
                } header: { Text("Sıkıştırılmış dosya") } footer: {
                    Text("DSEE / MP Enhance tarzı: MP3 ve AAC'de kesilen üst frekansları harmoniklerle geri getirir. FLAC'ta düşük tut.")
                }

                Section {
                    Surgu("Stereo genişlik", $ses.ayar.genislik, 0...2, adim: 0.05, ondalik: true)
                    Surgu("3D Surround", $ses.ayar.surround, 0...10)
                    Surgu("Kulaklık crossfeed", $ses.ayar.crossfeed, 0...10)
                    Picker("VPT yankı", selection: $ses.ayar.yanki) {
                        ForEach(YankiOda.allCases) { Text($0.ad).tag($0) }
                    }
                    if ses.ayar.yanki != .kapali { Surgu("Yankı düzeyi", $ses.ayar.yankiSeviye, 0...10) }
                } header: { Text("Sahne") } footer: {
                    Text("Crossfeed, kulaklıkta sesin \"kafanın içinde\" durmasını giderir: hoparlörde olduğu gibi kanalları hafifçe karıştırır.")
                }

                Section {
                    Toggle(isOn: $ses.ayar.dengeleyici) { Etiket("Dinamik dengeleyici", "Sessiz ve gürültülü yerleri yaklaştırır; kitap altında, gece") }
                    Toggle(isOn: $calar.avls) { Etiket("AVLS", "Walkman'ın ses sınırlayıcısı: en yüksek ses yarıda kalır") }
                    Toggle(isOn: $ses.ayar.replayGain) { Etiket("ReplayGain", "Etiketli parçaların ses düzeyini eşitler") }
                    Toggle(isOn: $ses.ayar.otomatikBosluk) { Etiket("Otomatik boşluk", "Efekt eklediği kadar önden kısar, taşma (clipping) olmaz") }
                    Surgu("Ön kazanç", $ses.ayar.onKazanc, -12...12, birim: " dB", adim: 0.5, ondalik: true)
                    Surgu("Denge (sol–sağ)", $ses.ayar.denge, -1...1, adim: 0.05, ondalik: true)
                } header: { Text("Düzey") }
            }
            .navigationTitle("Ses Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Kapat") { kapat() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(0..<4) { i in
                            Button("Kullanıcı \(i + 1)'e kaydet") { ses.yuvayaKaydet(i) }
                        }
                    } label: { Image(systemName: "square.and.arrow.down") }
                }
            }
        }
    }

    private var ustBolum: some View {
        Section {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ses.ad).font(.title3.weight(.semibold))
                        if let p = calar.simdiki { Text("\(p.baslik) · \(p.bicim)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer()
                    ABDugmesi()
                }
                SpektrumCubuklari(bant: 36, renkler: [.orange, .pink, .purple]).frame(height: 54)
            }
            HazirSecici()
        }
    }

    private var eqBolumu: some View {
        Section {
            Toggle("Ekolayzır", isOn: $ses.ayar.eqAcik)
            if ses.ayar.eqAcik {
                Picker("Kip", selection: $ses.ayar.eqKipi) {
                    ForEach(EQKipi.allCases) { Text($0.ad).tag($0) }
                }
                .pickerStyle(.segmented)
                EQEgrisi(ayar: ses.ayar).frame(height: 90)
                if ses.ayar.eqKipi == .grafik {
                    GrafikEQ(degerler: $ses.ayar.grafik).frame(height: 200)
                    Button("Düzle") { ses.ayar.grafik = Array(repeating: 0, count: 10) }.font(.footnote)
                } else {
                    ForEach(0..<5) { i in ParametrikBant(bant: $ses.ayar.parametrik[i], no: i + 1) }
                    Button("Düzle") { ses.ayar.parametrik = SesAyari.varsayilanParametrik }.font(.footnote)
                }
            }
        } header: { Text("EQ") } footer: {
            Text("Parametrik kip Cowon D2'nin kullanıcı EQ'su gibi: her bandın frekansını ve genişliğini (Q) sen seçersin.")
        }
    }
}

struct ABDugmesi: View {
    @EnvironmentObject var ses: Ses
    var body: some View {
        Button { ses.abDegistir() } label: {
            Text(ses.ayar.atla ? "B · ham" : "A · Tını")
                .font(.footnote.weight(.bold).monospaced())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(ses.ayar.atla ? Color.gray.opacity(0.25) : Color.accentColor.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Efektleri anında açıp kapatır; farkı duymak için")
    }
}

struct HazirSecici: View {
    @EnvironmentObject var ses: Ses
    var body: some View {
        Menu {
            ForEach(Hazir.Grup.allCases, id: \.self) { g in
                Section(g.rawValue) {
                    ForEach(Hazir.hepsi.filter { $0.grup == g }) { h in
                        Button { ses.uygula(h) } label: {
                            if ses.ad == h.ad { Label(h.ad, systemImage: "checkmark") } else { Text(h.ad) }
                        }
                    }
                }
            }
            Section("Kullanıcı") {
                ForEach(0..<4) { i in
                    Button("Kullanıcı \(i + 1)\(ses.yuvalar[i] == nil ? " (boş)" : "")") { ses.yuvadanYukle(i) }
                        .disabled(ses.yuvalar[i] == nil)
                }
            }
        } label: {
            HStack {
                Label("Hazır ayar", systemImage: "slider.horizontal.3")
                Spacer()
                Text(ses.ad).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct GrafikEQ: View {
    @Binding var degerler: [Float]
    var renk: Color = .accentColor
    var etiketRengi: Color = .secondary

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(String(format: "%+.0f", degerler[i])).font(.system(size: 9).monospacedDigit()).foregroundStyle(etiketRengi)
                        DikeySurgu(deger: $degerler[i], aralik: -12...12, renk: renk)
                        Text(etiket(SesAyari.grafikFrekanslar[i])).font(.system(size: 9)).foregroundStyle(etiketRengi)
                    }
                    .frame(width: g.size.width / 10)
                }
            }
        }
    }

    private func etiket(_ f: Float) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }
}

struct DikeySurgu: View {
    @Binding var deger: Float
    let aralik: ClosedRange<Float>
    var renk: Color = .accentColor

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let oran = CGFloat((deger - aralik.lowerBound) / (aralik.upperBound - aralik.lowerBound))
            let y = h * (1 - oran)
            let orta = h / 2
            ZStack(alignment: .top) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(width: 4)
                Rectangle().fill(renk).frame(width: 4, height: abs(y - orta)).offset(y: min(y, orta))
                Circle().fill(.white).shadow(radius: 1.5).frame(width: 18, height: 18).offset(y: y - 9)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let o = Float(1 - min(max(d.location.y / h, 0), 1))
                let v = aralik.lowerBound + o * (aralik.upperBound - aralik.lowerBound)
                deger = (v * 2).rounded() / 2
            })
            .onTapGesture(count: 2) { deger = 0 }
        }
    }
}

struct ParametrikBant: View {
    @Binding var bant: ParamBant
    let no: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Bant \(no)").font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(bant.frekans)) Hz · \(String(format: "%+.1f", bant.kazanc)) dB · Q \(String(format: "%.1f", bant.q))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack { Text("Frekans").font(.caption2).frame(width: 52, alignment: .leading)
                Slider(value: Binding(get: { log10(Double(bant.frekans)) }, set: { bant.frekans = Float(pow(10, $0)).rounded() }), in: log10(20)...log10(18000)) }
            HStack { Text("Kazanç").font(.caption2).frame(width: 52, alignment: .leading)
                Slider(value: $bant.kazanc, in: -12...12, step: 0.5) }
            HStack { Text("Genişlik").font(.caption2).frame(width: 52, alignment: .leading)
                Slider(value: $bant.q, in: 0.3...4, step: 0.1) }
        }
    }
}

struct Surgu: View {
    let ad: String
    @Binding var deger: Float
    let aralik: ClosedRange<Float>
    var birim = ""
    var adim: Float = 0.5
    var ondalik = false

    init(_ ad: String, _ deger: Binding<Float>, _ aralik: ClosedRange<Float>, birim: String = "", adim: Float = 0.5, ondalik: Bool = false) {
        self.ad = ad; _deger = deger; self.aralik = aralik; self.birim = birim; self.adim = adim; self.ondalik = ondalik
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(ad)
                Spacer()
                Text((ondalik ? String(format: "%.2f", deger) : String(format: "%.1f", deger)) + birim)
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $deger, in: aralik, step: adim)
        }
    }
}

struct Etiket: View {
    let ad: String, alt: String
    init(_ ad: String, _ alt: String) { self.ad = ad; self.alt = alt }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ad)
            Text(alt).font(.caption).foregroundStyle(.secondary)
        }
    }
}
