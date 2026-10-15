// Süreçler — her süreç kendi ilerleme biçimiyle (halka · merdiven · depo · kitaplık · akış).
import SwiftUI

struct SureclerEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var alan = "hepsi"
    @State private var yol = NavigationPath()
    @State private var sessizAcik = false

    var body: some View {
        NavigationStack(path: $yol) {
            ScrollView {
                if let d = merkez.durum {
                    VStack(alignment: .leading, spacing: 14) {
                        suzgec(d)
                        let liste = d.hukumler.filter { (alan == "hepsi" || $0.surec.alan == alan) }
                        let aktif = liste.filter { $0.durum.hukumVar }
                            .sorted { ($0.durum.sira, -$0.agirlik) < ($1.durum.sira, -$1.agirlik) }
                        ForEach(aktif) { h in
                            NavigationLink(value: h.id) { SurecKarti(h: h) }.buttonStyle(.plain)
                        }
                        let sessiz = liste.filter { !$0.durum.hukumVar }
                        if !sessiz.isEmpty {
                            DisclosureGroup(isExpanded: $sessizAcik) {
                                VStack(spacing: 10) {
                                    ForEach(sessiz) { h in
                                        NavigationLink(value: h.id) { SurecSatiri(h: h) }.buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                Label("Uykuda ve görünmeyen · \(sessiz.count)", systemImage: "moon.zzz")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(Tema.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .background(Tema.zemin)
            .navigationTitle("Süreçler")
            .refreshable { await merkez.tazele() }
            .navigationDestination(for: String.self) { SurecDetay(id: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .alanSec)) { n in
                if let a = n.object as? String { alan = a }
            }
            .onChange(of: rota.surec) { _, id in
                if let id, rota.sekme == 1 { yol.append(id); rota.surec = nil }
            }
        }
    }

    func suzgec(_ d: Durumlar) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cip("hepsi", "Hepsi", "square.grid.2x2", .accentColor)
                ForEach(d.veri.alanlar) { a in cip(a.id, a.kisa, Tema.alanSimge(a.id), Tema.alan(a.id)) }
            }
        }
    }

    func cip(_ id: String, _ ad: String, _ simge: String, _ renk: Color) -> some View {
        Button { withAnimation(.snappy) { alan = id } } label: {
            Label(ad, systemImage: simge).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(alan == id ? renk : Tema.kart, in: Capsule())
                .foregroundStyle(alan == id ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct SurecKarti: View {
    var h: Hukum
    var body: some View {
        let s = h.surec
        let renk = Tema.alan(s.alan)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: Tema.alanSimge(s.alan)).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(renk).frame(width: 30, height: 30)
                    .background(renk.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.ad).font(.system(size: 16, weight: .bold))
                    Text(s.alt).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                DurumCipi(durum: h.durum)
            }
            HStack(alignment: .bottom, spacing: 12) {
                BicimGorseli(s: s, renk: renk).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(s.sonDokunus.map { Tarih.gorece($0) } ?? "iz yok")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.durum(h.durum))
                    Text(s.ritim == 1 ? "ritim: her gün" : "ritim: \(s.ritim) günde bir")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if let g = h.vadeGun, g >= 0 {
                        Text("vade \(g) gün").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(g <= 7 ? Tema.durum(.aksiyor) : .secondary)
                    }
                }
            }
            IzSeridi(iz: s.iz, gun: 28, renk: renk, yukseklik: 16)
            Text(s.bugun).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(16)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Tema.durum(h.durum)).frame(width: 4).padding(.vertical, 18)
        }
    }
}

struct SurecDetay: View {
    @EnvironmentObject var merkez: Merkez
    var id: String

    var body: some View {
        ScrollView {
            if let d = merkez.durum, let h = d.hukum(id) {
                let s = h.surec
                let renk = Tema.alan(s.alan)
                VStack(alignment: .leading, spacing: 14) {
                    kahraman(h, renk)
                    Kart(baslik: "Nasıl akışa döner", simge: "arrow.triangle.turn.up.right.diamond") {
                        ForEach(Array(Yol.oneri(h, d).filter { !$0.isEmpty }.enumerated()), id: \.offset) { i, m in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)").font(.yuvarlak(11, .bold)).foregroundStyle(renk)
                                    .frame(width: 20, height: 20).background(renk.opacity(0.14), in: Circle())
                                Text(m).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            AcButonu(acilis: s.acilis, ad: s.acilis_ad.map { "\($0)'yı aç" })
                            Spacer()
                            if h.durum.hukumVar {
                                Button("Yarına bırak", systemImage: "moon") { merkez.ertele(s.id) }
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                    if s.ilerleme != nil || !s.basamaklar.isEmpty || s.birikme != nil {
                        Kart(baslik: "İlerleme", simge: Tema.bicimSimge(s.bicim)) { buyukGorsel(s, renk) }
                    }
                    Kart(baslik: "12 haftalık iz", simge: "calendar") {
                        IzTakvimi(iz: s.iz, renk: renk, hucre: 15)
                        HStack {
                            Text("\(s.iz.filter { $0 > 0 }.count) gün dokunuldu").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("son 28 gün: \(s.iz.suffix(28).filter { $0 > 0 }.count)").font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    ritimKarti(h)
                    baglar(d, s)
                    if !s.ayrinti.isEmpty || s.hata != nil {
                        Kart(baslik: "Ayrıntı", simge: "list.bullet.rectangle") {
                            ForEach(s.ayrinti, id: \.self) { k in
                                HStack(alignment: .top) {
                                    Text(k.e).font(.system(size: 13)).foregroundStyle(.secondary)
                                    Spacer(minLength: 12)
                                    Text(k.d).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.trailing)
                                }
                            }
                            if let x = s.hata { Text(x).font(.system(size: 12)).foregroundStyle(.red) }
                            Text("Kaynak: \(s.kaynak)").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .background(Tema.zemin)
        .navigationBarTitleDisplayMode(.inline)
    }

    func kahraman(_ h: Hukum, _ renk: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(merkez.veri?.alanlar.first { $0.id == h.surec.alan }?.ad ?? "", systemImage: Tema.alanSimge(h.surec.alan))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(h.surec.kademe).font(.system(size: 11, weight: .bold)).textCase(.uppercase)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.2), in: Capsule())
                    .foregroundStyle(.white)
            }
            Text(h.surec.ad).font(.yuvarlak(30, .bold)).foregroundStyle(.white)
            Text(h.surec.alt).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                Image(systemName: Tema.durumSimge(h.durum))
                Text(h.durum.ad).fontWeight(.bold)
                Text("·")
                Text(h.neden).lineLimit(3)
            }
            .font(.system(size: 13)).foregroundStyle(.white)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18)
        .background(LinearGradient(colors: [renk, renk.opacity(0.7), Tema.durum(h.durum).opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 6)
    }

    @ViewBuilder
    func buyukGorsel(_ s: Surec, _ renk: Color) -> some View {
        switch s.bicim {
        case "merdiven": Merdiven(basamaklar: s.basamaklar, renk: renk, sinir: 12)
        case "kitaplik":
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.basamaklar) { b in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(b.ad).font(.system(size: 13)).lineLimit(1); Spacer(); Text("%\(b.a)").font(.system(size: 12).monospacedDigit()) }
                        MiniCubuk(oran: b.oran, renk: renk, yukseklik: 6)
                    }
                }
            }
        case "depo":
            HStack(alignment: .bottom, spacing: 18) {
                DepoGorseli(ilerleme: s.ilerleme, birikme: s.birikme, renk: renk).frame(width: 46, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    if let b = s.birikme {
                        Text("\(b.bekleyen ?? 0) \(b.birim)").font(.yuvarlak(22, .bold))
                            .foregroundStyle(b.asildi ? Tema.durum(.tikali) : .primary)
                        Text("Eşik \(b.esik) · kırmızı çizgi").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(b.not).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if let i = s.ilerleme {
                        MiniCubuk(oran: i.oran, renk: renk, yukseklik: 6)
                        Text("Üretilen \(i.a)/\(i.b) \(i.birim)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        default:
            if let i = s.ilerleme {
                HStack(spacing: 16) {
                    Halka(oran: i.oran, renk: renk, kalinlik: 10).frame(width: 90, height: 90)
                        .overlay(Text("%\(Int(i.oran * 100))").font(.yuvarlak(20, .bold)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(i.a) / \(i.b)").font(.yuvarlak(24, .bold))
                        Text(i.birim).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    func ritimKarti(_ h: Hukum) -> some View {
        let s = h.surec
        let gelecek = Motor.gelecek(s, .now)
        return Kart(baslik: "Ritim ve hüküm", simge: "metronome") {
            HStack(spacing: 0) {
                olcu("Ritim", s.ritim == 1 ? "her gün" : "\(s.ritim) günde 1")
                olcu("Sessizlik", h.sessizlik.map { $0 == 0 ? "bugün" : "\($0) gün" } ?? "—")
                olcu("Ağırlık", String(format: "%.1f", h.agirlik))
                if let v = s.vade, let g = h.vadeGun { olcu("Vade", g >= 0 ? "\(g) gün" : "geçti").help(v.olcut) }
            }
            if !gelecek.isEmpty {
                ForEach(Array(gelecek.enumerated()), id: \.offset) { _, x in
                    Label("Dokunulmazsa \(Tarih.kisa(x.0)) 09:00'da \(x.1.ad)", systemImage: Tema.durumSimge(x.1))
                        .font(.system(size: 12)).foregroundStyle(Tema.durum(x.1))
                }
            }
            if let v = s.vade { Text("Vade ölçütü: \(v.olcut) · \(v.tarih)").font(.system(size: 12)).foregroundStyle(.secondary) }
        }
    }

    func olcu(_ e: String, _ d: String) -> some View {
        VStack(spacing: 2) {
            Text(d).font(.yuvarlak(15, .bold))
            Text(e).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func baglar(_ d: Durumlar, _ s: Surec) -> some View {
        let giren = d.veri.kenarlar.filter { $0.b == s.id }
        let cikan = d.veri.kenarlar.filter { $0.a == s.id }
        if !giren.isEmpty || !cikan.isEmpty {
            Kart(baslik: "Akıştaki yeri", simge: "point.3.connected.trianglepath.dotted") {
                ForEach(giren, id: \.self) { k in bag(d, k.a, k.etiket, gelen: true) }
                ForEach(cikan, id: \.self) { k in bag(d, k.b, k.etiket, gelen: false) }
            }
        }
    }

    func bag(_ d: Durumlar, _ id: String, _ etiket: String?, gelen: Bool) -> some View {
        let ad = d.hukum(id)?.surec.ad ?? d.veri.boru(id)?.ad ?? id
        let durum = d.hukum(id)?.durum ?? (d.veri.boru(id)?.durum == "tikali" ? .tikali : .akiyor)
        return HStack(spacing: 8) {
            Image(systemName: gelen ? "arrow.down.right" : "arrow.up.right").foregroundStyle(.secondary)
            DurumNoktasi(durum: durum)
            Text(ad).font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(etiket ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
