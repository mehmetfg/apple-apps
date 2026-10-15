import SwiftUI

/// Cowon D2'nin yüzü: 320×240 dokunmatik ekran (yatay), üst kenarda fiziksel düğmeler, JetEffect menüsü ve
/// D2'nin kullanıcı EQ'su gibi frekansı ve genişliği seçilen 5 bant. Ekran gerçek 320×240 ölçüde çizilip büyütülür.
struct CowonDeri: View {
    @EnvironmentObject var calar: Calar
    @EnvironmentObject var ses: Ses
    @EnvironmentObject var gezinti: Gezinti
    enum Ekran { case muzik, jet, kullanici }
    @State private var ekran: Ekran = .muzik
    @State private var tik = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.15), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            GeometryReader { g in
                let w = min(g.size.width - 20, 520)
                let olcek = (w - 36) / 320
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    fizikselDugmeler.frame(width: w * 0.8)
                    cihaz(w: w, olcek: olcek)
                    alt
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: tik)
    }

    private func cihaz(w: CGFloat, olcek: CGFloat) -> some View {
        VStack(spacing: 6) {
            ekranIcerik
                .frame(width: 320, height: 240)
                .scaleEffect(olcek, anchor: .topLeading)
                .frame(width: 320 * olcek, height: 240 * olcek, alignment: .topLeading)
                .clipped()
                .overlay(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center).allowsHitTesting(false))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            HStack {
                Text("COWON").font(.system(size: 11, weight: .heavy)).tracking(2)
                Spacer()
                Text("D2").font(.system(size: 12, weight: .black).italic())
            }
            .foregroundStyle(Color(white: 0.55))
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.3), Color(white: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5))
        )
        .shadow(color: .black.opacity(0.8), radius: 18, y: 10)
        .frame(width: w)
    }

    private var fizikselDugmeler: some View {
        HStack(spacing: 10) {
            UstDugme(yazi: "◀◀") { tik += 1; calar.onceki() }
            UstDugme(yazi: "▶❙❙", genis: true) { tik += 1; calar.acKapa() }
            UstDugme(yazi: "▶▶") { tik += 1; calar.sonraki() }
            UstDugme(yazi: "VOL−") { tik += 1; calar.ses = max(0, calar.ses - 1 / 40) }
            UstDugme(yazi: "VOL+") { tik += 1; calar.ses = min(1, calar.ses + 1 / 40) }
            UstDugme(yazi: "M") { tik += 1; ekran = ekran == .muzik ? .jet : .muzik }
        }
    }

    private var alt: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("JetEffect").font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1))
                Text(ses.ad).font(.caption).foregroundStyle(.secondary)
                Spacer()
                ABDugmesi()
            }
            EQEgrisi(ayar: ses.ayar, renk: Color(red: 0.4, green: 0.7, blue: 1)).frame(height: 60)
            HStack(spacing: 20) {
                Button("Kitaplık") { gezinti.sayfa = .kutuphane }
                Button("Ses Lab") { gezinti.sayfa = .sesLab }
                Button("Ayarlar") { gezinti.sayfa = .ayarlar }
            }
            .font(.footnote)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Ekran

    @ViewBuilder private var ekranIcerik: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.13), Color(red: 0.0, green: 0.0, blue: 0.03)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                durumCubugu
                switch ekran {
                case .muzik: muzikEkrani
                case .jet: JetListesi(ekran: $ekran)
                case .kullanici: KullaniciEQ(ekran: $ekran)
                }
            }
        }
        .foregroundStyle(.white)
        .font(.system(size: 12))
    }

    private var durumCubugu: some View {
        HStack(spacing: 5) {
            Image(systemName: calar.caliyorMu ? "play.fill" : "pause.fill").font(.system(size: 8))
            Text(ses.ayar.atla ? "Normal" : ses.ad).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
            Spacer()
            if calar.karisik { Image(systemName: "shuffle").font(.system(size: 8)) }
            if calar.tekrar != .kapali { Image(systemName: calar.tekrar == .tek ? "repeat.1" : "repeat").font(.system(size: 8)) }
            Text("VOL \(Int(calar.ses * 40))").font(.system(size: 9, weight: .medium).monospacedDigit())
            Text(Date.now.formatted(date: .omitted, time: .shortened)).font(.system(size: 9).monospacedDigit())
            Image(systemName: "battery.75percent").font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
    }

    private var muzikEkrani: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                KapakGorunumu(parca: calar.simdiki, kose: 2)
                    .frame(width: 104, height: 104)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.3), lineWidth: 1))
                VStack(alignment: .leading, spacing: 5) {
                    D2Satir(simge: "music.note", yazi: calar.simdiki?.baslik ?? "Parça yok", kalin: true)
                    D2Satir(simge: "person.fill", yazi: calar.simdiki?.sanatci ?? "-")
                    D2Satir(simge: "opticaldisc", yazi: calar.simdiki?.album ?? "-")
                    D2Satir(simge: "waveform", yazi: calar.simdiki.map { "\($0.bicim)" } ?? "-")
                    Text("\(calar.sira + 1) / \(max(calar.kuyruk.count, 1))").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.top, 8)
            SpektrumCubuklari(bant: 32, renkler: [Color(red: 0.5, green: 0.85, blue: 1), Color(red: 0.15, green: 0.4, blue: 0.9)], tepeRengi: .white, bosluk: 1.5)
                .frame(height: 22).padding(.horizontal, 10)
            VStack(spacing: 2) {
                IlerlemeCubugu(renk: Color(red: 0.45, green: 0.75, blue: 1))
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                D2Dokunma(yazi: "JET") { ekran = .jet }
                D2Dokunma(simge: "backward.end.fill") { calar.onceki() }
                D2Dokunma(simge: calar.caliyorMu ? "pause.fill" : "play.fill") { calar.acKapa() }
                D2Dokunma(simge: "forward.end.fill") { calar.sonraki() }
                D2Dokunma(simge: "list.bullet") { gezinti.sayfa = .kutuphane }
            }
            .frame(height: 30)
            .background(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
        }
    }
}

private struct D2Satir: View {
    let simge: String, yazi: String
    var kalin = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: simge).font(.system(size: 9)).foregroundStyle(Color(red: 0.5, green: 0.75, blue: 1)).frame(width: 12)
            Text(yazi).font(.system(size: kalin ? 13 : 11, weight: kalin ? .bold : .regular)).lineLimit(1)
        }
    }
}

private struct D2Dokunma: View {
    var yazi: String? = nil
    var simge: String? = nil
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Group {
                if let simge { Image(systemName: simge).font(.system(size: 14)) } else { Text(yazi ?? "").font(.system(size: 10, weight: .heavy)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1) }
    }
}

private struct UstDugme: View {
    let yazi: String
    var genis = false
    let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Text(yazi).font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.8))
                .frame(maxWidth: .infinity).frame(height: 24)
                .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(Color(white: 0.5), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: genis ? 70 : 50)
    }
}

// MARK: - JetEffect listesi

private struct JetListesi: View {
    @EnvironmentObject var ses: Ses
    @Binding var ekran: CowonDeri.Ekran
    private let adlar = ["Normal", "BBE", "BBE ViVA", "BBE Mach3Bass", "BBE Headphone", "Mach3Bass", "MP Enhance", "3D Surround", "Wide",
                         "Reverb Hall", "Rock", "Jazz", "Klasik", "Pop", "Balad", "Kulüp", "Funk", "Hip Hop", "Techno", "Blues", "Metal", "Vokal", "Kitap altında"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { ekran = .muzik } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)) }.buttonStyle(.plain)
                Text("JetEffect 3.0").font(.system(size: 12, weight: .bold))
                Spacer()
                Button { ekran = .kullanici } label: { Text("User EQ ›").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
            }
            .padding(.horizontal, 8).frame(height: 24)
            ScrollViewReader { kaydir in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<4) { i in
                            satir("User \(i + 1)", secili: ses.ad == "Kullanıcı \(i + 1)", bos: ses.yuvalar[i] == nil) { ses.yuvadanYukle(i) }
                        }
                        ForEach(adlar, id: \.self) { ad in
                            satir(ad, secili: ses.ad == ad, bos: false) {
                                if let h = Hazir.hepsi.first(where: { $0.ad == ad }) { ses.uygula(h) }
                            }
                            .id(ad)
                        }
                    }
                }
                .onAppear { kaydir.scrollTo(ses.ad, anchor: .center) }
            }
        }
    }

    private func satir(_ ad: String, secili: Bool, bos: Bool, eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            HStack {
                Text(ad).font(.system(size: 13, weight: secili ? .bold : .regular))
                if bos { Text("(boş)").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                if secili { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(secili ? LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.1, green: 0.3, blue: 0.7)], startPoint: .top, endPoint: .bottom)
                               : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(bos)
    }
}

// MARK: - Kullanıcı EQ ve efektler (D2'nin User ekranı)

private struct KullaniciEQ: View {
    @EnvironmentObject var ses: Ses
    @Binding var ekran: CowonDeri.Ekran
    enum Sekme: String, CaseIterable { case eq = "EQ", bbe = "BBE", mach3 = "Mach3", mp = "MP Enh.", d3 = "3D", reverb = "Reverb" }
    @State private var sekme: Sekme = .eq
    @State private var yuva = 0

    static let frekanslar: [[Float]] = [[40, 60, 80, 100, 150], [150, 250, 400, 600, 800], [800, 1000, 1500, 2000, 3000],
                                        [3000, 4000, 5000, 6000, 8000], [8000, 10000, 12000, 14000, 16000]]
    static let genislikler: [(String, Float)] = [("W", 0.7), ("N", 1.2), ("NR", 2.5)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { ekran = .jet } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).frame(width: 22) }.buttonStyle(.plain)
                ForEach(Sekme.allCases, id: \.self) { s in
                    Button { sekme = s } label: {
                        Text(s.rawValue).font(.system(size: 10, weight: .bold)).frame(maxWidth: .infinity).frame(height: 22)
                            .background(sekme == s ? Color(red: 0.2, green: 0.45, blue: 0.85) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(white: 0.12))
            Group {
                switch sekme {
                case .eq: eqPaneli
                case .bbe: deger("BBE", $ses.ayar.maxNetlik, ac: { ses.ayar.maximizer = true })
                case .mach3: mach3Paneli
                case .mp: deger("MP Enhance", $ses.ayar.tiz)
                case .d3: VStack { deger("3D Surround", $ses.ayar.surround); genislikPaneli }
                case .reverb: reverbPaneli
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text("Kaydet:").font(.system(size: 10))
                ForEach(0..<4) { i in
                    Button("U\(i + 1)") { ses.yuvayaKaydet(i) }.font(.system(size: 10, weight: .bold)).buttonStyle(.bordered).controlSize(.mini)
                }
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 26)
        }
    }

    private var eqPaneli: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { i in
                let b = ses.ayar.parametrik[i]
                VStack(spacing: 3) {
                    Text(String(format: "%+.0f", b.kazanc)).font(.system(size: 9).monospacedDigit())
                    DikeySurgu(deger: Binding(get: { ses.ayar.parametrik[i].kazanc }, set: {
                        ses.ayar.eqAcik = true; ses.ayar.eqKipi = .parametrik; ses.ayar.parametrik[i].kazanc = $0
                    }), aralik: -12...12, renk: Color(red: 0.4, green: 0.7, blue: 1))
                    Button {
                        let liste = Self.frekanslar[i]
                        let j = ((liste.firstIndex(of: b.frekans) ?? -1) + 1) % liste.count
                        ses.ayar.eqKipi = .parametrik; ses.ayar.parametrik[i].frekans = liste[j]
                    } label: {
                        Text(b.frekans >= 1000 ? String(format: "%gk", b.frekans / 1000) : "\(Int(b.frekans))").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    Button {
                        let g = Self.genislikler
                        let j = ((g.firstIndex { abs($0.1 - b.q) < 0.05 } ?? 0) + 1) % g.count
                        ses.ayar.eqKipi = .parametrik; ses.ayar.parametrik[i].q = g[j].1
                    } label: {
                        Text(Self.genislikler.first { abs($0.1 - b.q) < 0.05 }?.0 ?? "Q").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
    }

    private var mach3Paneli: some View {
        VStack(spacing: 6) {
            deger("Mach3Bass", $ses.ayar.basSeviye, ac: { ses.ayar.bas = .mach3 })
            HStack {
                Text("Frekans").font(.system(size: 11))
                Slider(value: Binding(get: { ses.ayar.basFrekans }, set: { ses.ayar.bas = .mach3; ses.ayar.basFrekans = $0.rounded() }), in: 20...150, step: 5)
                Text("\(Int(ses.ayar.basFrekans)) Hz").font(.system(size: 10).monospacedDigit()).frame(width: 46)
            }
            .padding(.horizontal, 12)
        }
    }

    private var genislikPaneli: some View {
        HStack {
            Text("Stereo Enh.").font(.system(size: 11))
            Slider(value: $ses.ayar.genislik, in: 0...2, step: 0.05)
            Text(String(format: "%.2f", ses.ayar.genislik)).font(.system(size: 10).monospacedDigit()).frame(width: 34)
        }
        .padding(.horizontal, 12)
    }

    private var reverbPaneli: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(YankiOda.allCases) { o in
                    Button { ses.ayar.yanki = o } label: {
                        Text(o == .kapali ? "Off" : o.ad).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 24)
                            .background(ses.ayar.yanki == o ? Color(red: 0.2, green: 0.45, blue: 0.85) : Color(white: 0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.top, 10)
            deger("Level", $ses.ayar.yankiSeviye)
        }
    }

    private func deger(_ ad: String, _ d: Binding<Float>, ac: (() -> Void)? = nil) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(ad).font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(Int(d.wrappedValue.rounded()))").font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1))
            }
            HStack(spacing: 2) {
                ForEach(0..<11) { i in
                    Rectangle().fill(i <= Int(d.wrappedValue.rounded()) && d.wrappedValue > 0 ? Color(red: 0.35, green: 0.65, blue: 1) : Color(white: 0.18))
                        .frame(height: 14 + CGFloat(i) * 2)
                        .onTapGesture { ac?(); d.wrappedValue = Float(i) }
                }
            }
            .frame(height: 36, alignment: .bottom)
        }
        .padding(.horizontal, 12).padding(.top, 10)
    }
}
