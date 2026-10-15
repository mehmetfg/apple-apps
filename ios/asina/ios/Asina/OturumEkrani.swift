// Oturum ekranı: tek soru, büyük yazı, altta Duolingo tarzı geri bildirim paneli.
import SwiftUI

struct OturumEkrani: View {
    @EnvironmentObject var depo: Depo
    @StateObject var oturum: Oturum
    @Environment(\.dismiss) private var kapat
    @State private var yazilan = ""
    @State private var acik = false          // hatırla kartı çevrildi mi
    @FocusState private var odak: Bool

    var body: some View {
        VStack(spacing: 0) {
            ustSerit
            if oturum.bitti {
                OturumOzeti(oturum: oturum) { kapat() }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let s = oturum.soru {
                ScrollView {
                    soruGovdesi(s)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .id(s.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .scrollDismissesKeyboard(.interactively)
                altPanel(s)
            }
        }
        .background(R.zemin.ignoresSafeArea())
        .sensoryFeedback(trigger: oturum.cevap) { _, y in
            guard let y else { return nil }
            return y.dogru ? .success : .error
        }
        .onChange(of: oturum.konum) { _, _ in
            yazilan = ""
            acik = false
            otomatikSes()
        }
        .onAppear { otomatikSes() }
        .onChange(of: oturum.bitti) { _, b in
            if b { depo.oturumSuresi(Date().timeIntervalSince(oturum.baslangic)) }
        }
    }

    private func otomatikSes() {
        guard let s = oturum.soru, depo.ayar.otomatikSes else { return }
        if s.tur == .tanit || s.tur == .dinle {
            Ses.ortak.soyle(s.kelime, oxford: depo.ayar.oxfordSesi)
        }
    }

    // MARK: Üst şerit

    private var ustSerit: some View {
        HStack(spacing: 14) {
            Button { kapat() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(R.ikincil)
                    .frame(width: 36, height: 36)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(R.cizgi)
                    Capsule().fill(R.vurgu)
                        .frame(width: max(10, g.size.width * (oturum.bitti ? 1 : oturum.ilerleme)))
                        .animation(.spring(response: 0.5), value: oturum.konum)
                }
            }
            .frame(height: 10)
            Text("\(min(oturum.konum + 1, oturum.sira.count))/\(oturum.sira.count)")
                .font(.footnote.monospacedDigit()).foregroundStyle(R.soluk)
                .frame(minWidth: 40)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: Soru gövdeleri

    @ViewBuilder
    private func soruGovdesi(_ s: Soru) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(s.yineleme ? "Bir daha" : s.tur.baslik)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(s.tur == .tanit ? R.vurgu : R.ikincil)
                Spacer()
                RozetKelime(k: s.kelime)
            }
            switch s.tur {
            case .tanit: TanitKarti(k: s.kelime)
            case .anlam: anlamSorusu(s)
            case .dinle: dinleSorusu(s)
            case .bosluk: boslukSorusu(s)
            case .yaz: yazSorusu(s)
            case .hatirla: hatirlaSorusu(s)
            case .parcacik: parcacikSorusu(s)
            }
        }
    }

    private func anlamSorusu(_ s: Soru) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.kelime.w).font(.kelime(44)).foregroundStyle(R.murekkep)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(s.kelime.ipa.isEmpty ? s.kelime.turAdi : s.kelime.ipa).font(.callout).foregroundStyle(R.soluk)
                }
                Spacer()
                SesDugmesi(kelime: s.kelime)
            }
            .padding(.top, 20)
            secenekler(s) { $0.tr }
        }
    }

    private func dinleSorusu(_ s: Soru) -> some View {
        VStack(spacing: 26) {
            Button { Ses.ortak.soyle(s.kelime, oxford: depo.ayar.oxfordSesi) } label: {
                ZStack {
                    Circle().fill(R.vurgu.opacity(0.12)).frame(width: 130, height: 130)
                    Circle().fill(R.vurgu).frame(width: 92, height: 92)
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(Bas())
            .padding(.top, 16)
            Button("Yavaş dinle") { Ses.ortak.oku(s.kelime.w, yavas: true) }
                .font(.footnote.weight(.medium)).foregroundStyle(R.ikincil)
            secenekler(s, serif: true) { $0.w }
        }
        .frame(maxWidth: .infinity)
    }

    private func boslukSorusu(_ s: Soru) -> some View {
        let cumle = s.kelime.x.lazy.compactMap { Vurgu.bosluk($0, s.kelime.w) }.first
        return VStack(alignment: .leading, spacing: 22) {
            Text(cumle?.0 ?? s.kelime.d)
                .font(.kelime(25, .regular))
                .foregroundStyle(R.murekkep)
                .lineSpacing(5)
                .padding(.top, 12)
            Label(s.kelime.tr, systemImage: "lightbulb")
                .font(.subheadline).foregroundStyle(R.ikincil)
            secenekler(s, serif: true) { $0.w }
        }
    }

    private func parcacikSorusu(_ s: Soru) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(s.bosCumle ?? s.kelime.d)
                .font(.kelime(26, .regular))
                .foregroundStyle(R.murekkep)
                .lineSpacing(5)
                .padding(.top, 12)
            HStack(spacing: 8) {
                Text(s.kelime.taban).font(.kelime(15)).foregroundStyle(R.pv)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(R.pv.opacity(0.12), in: Capsule())
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(R.soluk)
                Text(s.kelime.tr).font(.subheadline).foregroundStyle(R.ikincil)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(s.parcacikSec, id: \.self) { p in
                    let c = oturum.cevap
                    let buDogru = p == s.kelime.parcacik
                    let buSecilen = c?.verilen == p
                    Button { oturum.secParcacik(p) } label: {
                        Text(p).font(.kelime(22, .medium)).foregroundStyle(R.murekkep)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(c != nil && buDogru ? R.dogru.opacity(0.12)
                                          : c != nil && buSecilen ? R.yanlis.opacity(0.12) : R.yuzey))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(c != nil && buDogru ? R.dogru : c != nil && buSecilen ? R.yanlis : R.cizgi,
                                        lineWidth: c != nil && (buDogru || buSecilen) ? 1.5 : 1))
                            .opacity(c != nil && !buDogru && !buSecilen ? 0.5 : 1)
                    }
                    .buttonStyle(Bas())
                    .disabled(c != nil)
                }
            }
        }
    }

    private func yazSorusu(_ s: Soru) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(s.kelime.tr)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(R.murekkep)
                .padding(.top, 16)
            Text(s.kelime.d).font(.callout).foregroundStyle(R.ikincil)
            HStack(spacing: 6) {
                Text(String(s.kelime.w.prefix(1)))
                    .font(.kelime(15)).foregroundStyle(R.vurgu)
                Text("· \(s.kelime.w.count) harf · \(s.kelime.turAdi)")
                    .font(.footnote).foregroundStyle(R.soluk)
            }
            TextField("İngilizcesi…", text: $yazilan)
                .font(.kelime(28, .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($odak)
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(R.yuzey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(oturum.cevap == nil ? R.cizgi : (oturum.cevap!.dogru ? R.dogru : R.yanlis), lineWidth: 1.5))
                .disabled(oturum.cevap != nil)
                .onSubmit { if !yazilan.isEmpty { oturum.yaz(yazilan) } }
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { odak = true } }
        }
    }

    private func hatirlaSorusu(_ s: Soru) -> some View {
        VStack(spacing: 18) {
            ZStack {
                if acik {
                    VStack(spacing: 10) {
                        Text(s.kelime.tr).font(.system(size: 26, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                        if let x = s.kelime.ilkCumle {
                            Text(Vurgu.metin(x, s.kelime.w, renk: R.vurgu))
                                .font(.kelime(17, .regular)).foregroundStyle(R.ikincil)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                } else {
                    VStack(spacing: 6) {
                        Text(s.kelime.w).font(.kelime(44)).minimumScaleFactor(0.5).lineLimit(1)
                        Text(s.kelime.ipa.isEmpty ? s.kelime.turAdi : s.kelime.ipa).foregroundStyle(R.soluk)
                        Text("Anlamını düşün, sonra çevir").font(.footnote).foregroundStyle(R.soluk).padding(.top, 14)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(20)
            .background(R.yuzey, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
            .rotation3DEffect(.degrees(acik ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)
            .onTapGesture {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { acik = true }
                Ses.ortak.soyle(s.kelime, oxford: depo.ayar.oxfordSesi)
            }
            .padding(.top, 20)
        }
    }

    private func secenekler(_ s: Soru, serif: Bool = false, _ etiket: @escaping (Kelime) -> String) -> some View {
        VStack(spacing: 10) {
            ForEach(s.secenekler, id: \.i) { k in
                let c = oturum.cevap
                let buDogru = k.w == s.kelime.w
                let buSecilen = c?.verilen == k.w
                Button { oturum.sec(k) } label: {
                    HStack {
                        Text(etiket(k))
                            .font(serif ? .kelime(20, .medium) : .body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(R.murekkep)
                        Spacer()
                        if c != nil && buDogru { Image(systemName: "checkmark.circle.fill").foregroundStyle(R.dogru) }
                        if c != nil && buSecilen && !buDogru { Image(systemName: "xmark.circle.fill").foregroundStyle(R.yanlis) }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(c != nil && buDogru ? R.dogru.opacity(0.12)
                                  : c != nil && buSecilen ? R.yanlis.opacity(0.12) : R.yuzey))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(c != nil && buDogru ? R.dogru : c != nil && buSecilen ? R.yanlis : R.cizgi,
                                lineWidth: c != nil && (buDogru || buSecilen) ? 1.5 : 1))
                    .opacity(c != nil && !buDogru && !buSecilen ? 0.5 : 1)
                }
                .buttonStyle(Bas())
                .disabled(c != nil)
            }
        }
    }

    // MARK: Alt panel

    @ViewBuilder
    private func altPanel(_ s: Soru) -> some View {
        Group {
            if s.tur == .tanit {
                HStack(spacing: 12) {
                    Button { oturum.zatenBiliyorum() } label: {
                        Text("Zaten biliyorum")
                            .font(.headline).foregroundStyle(R.ikincil)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(R.yuzey2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(Bas())
                    AnaDugme(baslik: "Öğrenelim", simge: "arrow.right") { oturum.tanidim() }
                }
            } else if let c = oturum.cevap {
                geriBildirim(s, c)
            } else if s.tur == .yaz {
                HStack(spacing: 12) {
                    Button { oturum.yaz("") } label: {
                        Text("Bilmiyorum").font(.headline).foregroundStyle(R.ikincil)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(R.yuzey2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(Bas())
                    AnaDugme(baslik: "Kontrol et", renk: yazilan.isEmpty ? R.soluk : R.vurgu) {
                        if !yazilan.isEmpty { oturum.yaz(yazilan) }
                    }
                }
            } else if s.tur == .hatirla, acik {
                HStack(spacing: 8) {
                    notDugmesi("Unuttum", .unuttum, R.yanlis)
                    notDugmesi("Zor", .zor, R.zor)
                    notDugmesi("İyi", .iyi, R.dogru)
                    notDugmesi("Kolay", .kolay, Color.iki(0x4C5DB8, 0x8C9BFF))
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: oturum.cevap)
    }

    private func notDugmesi(_ ad: String, _ n: Not, _ renk: Color) -> some View {
        Button { oturum.degerlendir(n) } label: {
            Text(ad).font(.subheadline.weight(.semibold)).foregroundStyle(renk)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(renk.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Bas())
    }

    private func geriBildirim(_ s: Soru, _ c: Oturum.Cevap) -> some View {
        let renk = c.dogru ? R.dogru : R.yanlis
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: c.dogru ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.title2)
                Text(c.dogru ? (c.yakin ? "Neredeyse — yazımı:" : ["Güzel!", "Doğru.", "Aynen.", "Oldu."].randomElement()!)
                     : "Doğrusu:")
                    .font(.headline)
                Spacer()
                if c.dogru {
                    Button { oturum.kolaydi() } label: {
                        Label("Çok kolaydı", systemImage: c.not == .kolay ? "bolt.fill" : "bolt")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(renk.opacity(c.not == .kolay ? 0.25 : 0.1), in: Capsule())
                    }
                }
            }
            .foregroundStyle(renk)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.kelime.w).font(.kelime(24)).foregroundStyle(R.murekkep)
                    Text("\(s.kelime.ipa.isEmpty ? s.kelime.turAdi : s.kelime.ipa)  ·  \(s.kelime.tr)").font(.subheadline).foregroundStyle(R.ikincil)
                        .lineLimit(2)
                }
                Spacer()
                SesDugmesi(kelime: s.kelime, boyut: 36)
            }
            if let x = s.kelime.ilkCumle {
                Text(Vurgu.metin(x, s.kelime.w, renk: renk))
                    .font(.kelime(15, .regular)).foregroundStyle(R.ikincil).lineLimit(3)
            }
            if s.kelime.isPV {
                let digerleri = Array(depo.ayniFiil(s.kelime).prefix(2))
                if !digerleri.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(s.kelime.taban.uppercased()) — AYIRT ET").font(.caption2.weight(.bold))
                            .foregroundStyle(R.pv).tracking(0.5)
                        ForEach(digerleri) { d in
                            HStack(spacing: 6) {
                                Text(d.w).font(.kelime(14)).foregroundStyle(R.murekkep)
                                Text("= \(d.tr)").font(.footnote).foregroundStyle(R.ikincil).lineLimit(1)
                            }
                        }
                    }
                }
            }
            AnaDugme(baslik: "Devam", renk: renk) { oturum.devam() }
        }
        .padding(16)
        .background(renk.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear { if depo.ayar.otomatikSes && s.tur != .dinle { Ses.ortak.soyle(s.kelime, oxford: depo.ayar.oxfordSesi) } }
    }
}

/// Yeni kelimeyle tanışma kartı: anlam, söyleniş, kalıplar, gerçek cümleler.
struct TanitKarti: View {
    @EnvironmentObject var depo: Depo
    let k: Kelime
    @State private var goster = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text(k.w).font(.kelime(46)).foregroundStyle(R.murekkep)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Spacer()
                    SesDugmesi(kelime: k, boyut: 46)
                }
                HStack(spacing: 8) {
                    if !k.ipa.isEmpty {
                        Text(k.ipa).foregroundStyle(R.soluk)
                        Text("·").foregroundStyle(R.soluk)
                    }
                    Text(k.turAdi).italic().foregroundStyle(k.isPV ? R.pv : R.soluk)
                }
                .font(.callout)
            }
            Text(k.tr)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(R.vurgu)
            Text(k.d).font(.body).foregroundStyle(R.ikincil)
            if let n = k.ayrilmaNotu {
                VStack(alignment: .leading, spacing: 5) {
                    Text(n.baslik.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(R.pv).tracking(0.6)
                    HStack(spacing: 14) {
                        Label(n.dogru, systemImage: "checkmark.circle.fill").foregroundStyle(R.dogru)
                        if let y = n.yanlis {
                            Label(y, systemImage: "xmark.circle.fill").foregroundStyle(R.yanlis)
                        }
                    }
                    .font(.kelime(15, .regular))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(R.pv.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !k.k.isEmpty {
                Akis { ForEach(k.k, id: \.self) { Cip(metin: $0, renk: R.murekkep) } }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(k.x.prefix(3).enumerated()), id: \.offset) { i, x in
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(R.bant(k.c).opacity(0.6)).frame(width: 3)
                        Text(Vurgu.metin(x, k.w, renk: R.murekkep))
                            .font(.kelime(17, .regular)).foregroundStyle(R.ikincil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(goster ? 1 : 0)
                    .offset(y: goster ? 0 : 8)
                    .animation(.easeOut(duration: 0.4).delay(0.15 + Double(i) * 0.12), value: goster)
                }
            }
            if !k.syn.isEmpty || !k.ant.isEmpty {
                HStack(spacing: 16) {
                    if !k.syn.isEmpty { Text("≈ " + k.syn.prefix(3).joined(separator: ", ")) }
                    if !k.ant.isEmpty { Text("≠ " + k.ant.prefix(2).joined(separator: ", ")) }
                }
                .font(.footnote).foregroundStyle(R.soluk)
            }
            if k.isPV, !depo.ayniFiil(k).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AYNI FİİL, BAŞKA ANLAM").font(.caption2.weight(.bold)).foregroundStyle(R.soluk).tracking(0.6)
                    ForEach(Array(depo.ayniFiil(k).prefix(3))) { d in
                        HStack(spacing: 6) {
                            Text(d.w).font(.kelime(14)).foregroundStyle(R.murekkep)
                            Text("= \(d.tr)").font(.footnote).foregroundStyle(R.ikincil).lineLimit(1)
                        }
                    }
                }
            }
        }
        .kart(22)
        .padding(.top, 6)
        .onAppear { goster = true }
    }
}

struct OturumOzeti: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject var oturum: Oturum
    let bitir: () -> Void
    @State private var goster = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Halka(oran: oturum.dogruOrani, kalinlik: 14, renk: R.dogru)
                        .frame(width: 150, height: 150)
                    VStack(spacing: 0) {
                        Text("%\(Int((oturum.dogruOrani * 100).rounded()))")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("ilk denemede").font(.caption).foregroundStyle(R.soluk)
                    }
                }
                .padding(.top, 30)
                .scaleEffect(goster ? 1 : 0.7).opacity(goster ? 1 : 0)
                Text(baslik).font(.title2.weight(.bold))
                HStack(spacing: 12) {
                    kutu("\(oturum.yeniSayisi)", "yeni")
                    kutu("\(oturum.sonuc.count - max(0, oturum.yeniSayisi))", "tekrar")
                    kutu(sure, "süre")
                }
                if !oturum.biliyorumDenen.isEmpty {
                    Text("\(oturum.biliyorumDenen.count) kelimeyi zaten biliyordun — depodan düştü, Cümle Tezgâhı da artık sormayacak.")
                        .font(.footnote).foregroundStyle(R.ikincil).multilineTextAlignment(.center)
                }
                VStack(spacing: 0) {
                    ForEach(oturum.sonuc.sorted { $0.key < $1.key }, id: \.key) { ad, dogru in
                        if let k = depo.kelime(ad: ad) {
                            HStack {
                                Image(systemName: dogru ? "checkmark" : "arrow.counterclockwise")
                                    .foregroundStyle(dogru ? R.dogru : R.zor).frame(width: 22)
                                Text(k.w).font(.kelime(17))
                                Spacer()
                                Text(k.tr).font(.footnote).foregroundStyle(R.ikincil).lineLimit(1)
                            }
                            .padding(.vertical, 9)
                            Divider()
                        }
                    }
                }
                .kart(16)
                VStack(spacing: 10) {
                    if !depo.bekleyenYeniler.isEmpty || !depo.bekleyenTekrarlar.isEmpty {
                        Text("Bugün \(depo.bekleyenYeniler.count + depo.bekleyenTekrarlar.count) kelime daha var — istersen sonra.")
                            .font(.footnote).foregroundStyle(R.soluk)
                    }
                    AnaDugme(baslik: "Bitir", simge: "checkmark") { bitir() }
                }
            }
            .padding(20)
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { goster = true } }
        .sensoryFeedback(.success, trigger: goster)
    }

    private var baslik: String {
        switch oturum.dogruOrani {
        case 0.9...: return "Çok iyi gitti"
        case 0.7...: return "İyi bir tur"
        default: return "Zor kelimelerdi — tekrar gelecekler"
        }
    }

    private var sure: String {
        let s = Int(Date().timeIntervalSince(oturum.baslangic))
        return s < 60 ? "\(s) sn" : "\(s / 60) dk"
    }

    private func kutu(_ deger: String, _ ad: String) -> some View {
        VStack(spacing: 2) {
            Text(deger).font(.title3.weight(.bold).monospacedDigit())
            Text(ad).font(.caption).foregroundStyle(R.soluk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(R.yuzey, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
