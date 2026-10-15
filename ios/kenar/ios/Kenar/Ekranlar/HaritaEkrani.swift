// Harita: metnin argümanı üç yakınlıkta. İki parmakla aç/kapat:
//   metin  — beş bölüm bir omurga üstünde, her bölümün kanıtları rolüne göre noktalar
//   bölüm  — kanıt kartları serbest tuval üstünde; sürükle (ızgaraya oturur, titrer), "Bağla" ile iki kartı ya da kartı iddiaya bağla
//   cümle  — tek kart büyük: rol, kenar notu, bağlı olduğu kartlar
import SwiftUI

enum Yakinlik: Int, CaseIterable { case metin, bolum, cumle
    var ad: String { switch self { case .metin: "Metin"; case .bolum: "Bölüm"; case .cumle: "Cümle" } }
}

struct HaritaEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var yakinlik: Yakinlik = .metin
    @State private var bolum: String?
    @State private var odak: String?
    @State private var olcek: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                switch yakinlik {
                case .metin: MetinHaritasi { b in withAnimation(.spring(duration: 0.45)) { bolum = b; yakinlik = .bolum }; Haptik.orta() }
                case .bolum: if let b = bolum { BolumTuvali(bolumId: b) { x in withAnimation(.spring(duration: 0.45)) { odak = x; yakinlik = .cumle }; Haptik.orta() } }
                case .cumle: if let o = odak { CumleGorunumu(isaretId: o) { odak = $0 } }
                }
            }
            .scaleEffect(olcek)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .kagitZemin()
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { olcek = min(1.15, max(0.85, $0.magnification)) }
                    .onEnded { g in
                        withAnimation(.spring(duration: 0.4)) { olcek = 1 }
                        if g.magnification > 1.2 { yaklas() } else if g.magnification < 0.83 { uzaklas() }
                    }
            )
            .navigationTitle(baslik)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: Binding(get: { yakinlik }, set: { y in git(y) })) {
                        ForEach(Yakinlik.allCases, id: \.self) { Text($0.ad).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 220)
                }
            }
        }
        .onChange(of: rota.haritaBolum) { _, b in if let b { bolum = b; yakinlik = .bolum; rota.haritaBolum = nil } }
        .onAppear { if let b = rota.haritaBolum { bolum = b; yakinlik = .bolum; rota.haritaBolum = nil } }
    }

    private var baslik: String {
        switch yakinlik {
        case .metin: merkez.d.metin?.baslik ?? "Harita"
        case .bolum: merkez.d.metin?.bolumler.first { $0.id == bolum }.map { "§\($0.no) \($0.baslik)" } ?? "Bölüm"
        case .cumle: "Cümle"
        }
    }

    private func varsayilanBolum() -> String? {
        let m = merkez.d.metin
        return bolum ?? m?.bolumler.first { !$0.bitti && !merkez.d.kanitlar($0.id).isEmpty }?.id ?? m?.bolumler.first?.id
    }

    private func git(_ y: Yakinlik) {
        switch y {
        case .metin: break
        case .bolum: bolum = varsayilanBolum()
        case .cumle:
            bolum = varsayilanBolum()
            if odak == nil, let b = bolum { odak = merkez.d.kanitlar(b).first?.id }
            if odak == nil { return }
        }
        withAnimation(.spring(duration: 0.45)) { yakinlik = y }
        Haptik.secim()
    }

    private func yaklas() { if let s = Yakinlik(rawValue: yakinlik.rawValue + 1) { git(s) } }
    private func uzaklas() { if let s = Yakinlik(rawValue: yakinlik.rawValue - 1) { git(s) } }
}

// MARK: metin — omurga

struct MetinHaritasi: View {
    @EnvironmentObject var merkez: Merkez
    let sec: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let m = merkez.d.metin {
                    Text(m.soru).font(.serif(18).italic()).foregroundStyle(Color.soluk).padding(.bottom, 18)
                    ForEach(Array(m.bolumler.enumerated()), id: \.element.id) { i, b in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                BolumRozeti(no: b.no, boy: 36, dolu: b.bitti)
                                if i < m.bolumler.count - 1 { Rectangle().fill(Color.cizgi).frame(width: 2).frame(maxHeight: .infinity) }
                            }
                            Button { sec(b.id) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(b.baslik).font(.serif(18, .semibold)).foregroundStyle(Color.murekkep)
                                    Text(b.iddia).font(.serif(14)).foregroundStyle(Color.soluk).multilineTextAlignment(.leading)
                                    noktalar(b)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 26)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("İki parmakla aç: bölüme gir. Bir daha aç: cümleye.").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
    }

    private func noktalar(_ b: Bolum) -> some View {
        let k = merkez.d.kanitlar(b.id)
        return HStack(spacing: 5) {
            ForEach(k) { x in
                Image(systemName: x.rol?.simge ?? "circle.fill").font(.system(size: x.rol == nil ? 7 : 12))
                    .foregroundStyle(x.rol == .itiraz ? Color.kalem : Color.bolum(b.no))
            }
            if k.isEmpty { Text("kanıt yok").font(.caption2).foregroundStyle(.tertiary) }
        }
    }
}

// MARK: bölüm — serbest tuval

struct BolumTuvali: View {
    @EnvironmentObject var merkez: Merkez
    let bolumId: String
    let ac: (String) -> Void

    @State private var surukle: [String: CGSize] = [:]
    @State private var baglama = false
    @State private var ilk: String?

    static let tuval = CGSize(width: 560, height: 1000)
    static let kart = CGSize(width: 170, height: 124)
    static let iddiaMerkez = CGPoint(x: 280, y: 80)

    private var b: Bolum? { merkez.d.metin?.bolumler.first { $0.id == bolumId } }
    private var kanit: [Isaret] { merkez.d.kanitlar(bolumId) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { c, _ in
                    for bag in merkez.d.baglar {
                        guard let a = uc(bag.kaynak), let h = uc(bag.hedef) else { continue }
                        ok(c, a, h, renk: Color.bolum(b?.no ?? 1))
                    }
                }
                .frame(width: Self.tuval.width, height: Self.tuval.height)
                .allowsHitTesting(false)

                if let b { iddiaDugumu(b).position(Self.iddiaMerkez) }
                ForEach(kanit) { x in
                    let p = konum(x)
                    kartGorunumu(x)
                        .frame(width: Self.kart.width, height: Self.kart.height)
                        .position(x: p.x + (surukle[x.id]?.width ?? 0), y: p.y + (surukle[x.id]?.height ?? 0))
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onChanged { g in surukle[x.id] = g.translation }
                                .onEnded { g in
                                    let yeni = CGPoint(x: izgara(p.x + g.translation.width, Self.tuval.width), y: izgara(p.y + g.translation.height, Self.tuval.height))
                                    surukle[x.id] = nil
                                    merkez.konum(x.id, yeni)
                                    Haptik.hafif()
                                }
                        )
                        .onTapGesture { dokun(x.id) }
                        .contextMenu { IsaretMenusu(x: x) }
                }
            }
            .frame(width: Self.tuval.width, height: Self.tuval.height)
            .background(nokta)
        }
        .overlay(alignment: .bottom) { altCubuk }
    }

    private func uc(_ id: String) -> CGPoint? {
        if id == "iddia:" + bolumId { return Self.iddiaMerkez }
        guard let x = kanit.first(where: { $0.id == id }) else { return nil }
        let p = konum(x)
        return CGPoint(x: p.x + (surukle[id]?.width ?? 0), y: p.y + (surukle[id]?.height ?? 0))
    }

    /// Varsayılan yer rolden gelir: öncüller üstte, örnekler ortada, itirazlar sağda, sonuç altta.
    private func konum(_ x: Isaret) -> CGPoint {
        if let a = x.x, let b = x.y { return CGPoint(x: a, y: b) }
        let ayni = kanit.filter { $0.rol == x.rol && $0.x == nil }
        let i = CGFloat(ayni.firstIndex(of: x) ?? 0)
        switch x.rol {
        case .oncul: return CGPoint(x: 100 + i * 190, y: 260)
        case .ornek: return CGPoint(x: 100 + i * 190, y: 440)
        case .itiraz: return CGPoint(x: 460, y: 330 + i * 150)
        case .sonuc: return CGPoint(x: 280, y: 820 + i * 140)
        case nil: return CGPoint(x: 100 + (i.truncatingRemainder(dividingBy: 3)) * 190, y: 620 + floor(i / 3) * 140)
        }
    }

    private func izgara(_ v: CGFloat, _ ust: CGFloat) -> CGFloat { min(ust - 110, max(110, (v / 20).rounded() * 20)) }

    private func dokun(_ id: String) {
        guard baglama else { ac(id); return }
        if let a = ilk { merkez.bagla(a, id); ilk = nil } else { ilk = id; Haptik.secim() }
    }

    private func iddiaDugumu(_ b: Bolum) -> some View {
        VStack(spacing: 4) {
            Text("İDDİA").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.white.opacity(0.8))
            Text(b.iddia).font(.serif(14, .medium)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(4)
        }
        .padding(12).frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bolum(b.no)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: ilk == "iddia:" + b.id ? 3 : 0))
        .onTapGesture { if baglama { dokun("iddia:" + b.id) } }
    }

    private func kartGorunumu(_ x: Isaret) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if let r = x.rol { Image(systemName: r.simge); Text(r.ad) } else { Text("rol yok") }
                Spacer()
            }
            .font(.caption2.weight(.bold)).foregroundStyle(x.rol == .itiraz ? Color.kalem : Color.bolum(b?.no ?? 1))
            Text(x.metin).font(.serif(12.5)).foregroundStyle(Color.murekkep).lineLimit(4)
            Spacer(minLength: 0)
            Text(x.kitapAdi).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.soluk).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.kart).shadow(color: .black.opacity(surukle[x.id] != nil ? 0.25 : 0.06), radius: surukle[x.id] != nil ? 12 : 3, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ilk == x.id ? Color.kalem : Color.cizgi, lineWidth: ilk == x.id ? 2.5 : 0.6))
        .scaleEffect(surukle[x.id] != nil ? 1.05 : 1)
    }

    private var nokta: some View {
        Canvas { c, s in
            for x in stride(from: 0, to: s.width, by: 40) {
                for y in stride(from: 0, to: s.height, by: 40) {
                    c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(Color.cizgi))
                }
            }
        }
    }

    private var altCubuk: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $baglama.animation()) { Label(baglama ? (ilk == nil ? "İlk kartı seç" : "İkinci kartı seç") : "Bağla", systemImage: "arrow.triangle.branch") }
                .toggleStyle(.button).buttonStyle(.bordered)
                .onChange(of: baglama) { _, _ in ilk = nil }
            Text("\(kanit.count) kanıt · uzun bas: rol").font(.caption).foregroundStyle(Color.soluk)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 10)
    }

    private func ok(_ c: GraphicsContext, _ a: CGPoint, _ h: CGPoint, renk: Color) {
        var p = Path(); p.move(to: a); p.addLine(to: h)
        c.stroke(p, with: .color(renk.opacity(0.55)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        let aci = atan2(h.y - a.y, h.x - a.x)
        let uc = CGPoint(x: (a.x + h.x) / 2, y: (a.y + h.y) / 2)
        var ucP = Path()
        ucP.move(to: CGPoint(x: uc.x + 9 * cos(aci), y: uc.y + 9 * sin(aci)))
        ucP.addLine(to: CGPoint(x: uc.x + 9 * cos(aci + 2.5), y: uc.y + 9 * sin(aci + 2.5)))
        ucP.addLine(to: CGPoint(x: uc.x + 9 * cos(aci - 2.5), y: uc.y + 9 * sin(aci - 2.5)))
        ucP.closeSubpath()
        c.fill(ucP, with: .color(renk))
    }
}

// MARK: cümle — tek kart

struct CumleGorunumu: View {
    @EnvironmentObject var merkez: Merkez
    let isaretId: String
    let degistir: (String) -> Void
    @State private var not = ""

    private var x: Isaret? { merkez.d.isaretler.first { $0.id == isaretId } }

    var body: some View {
        ScrollView {
            if let x {
                let kardesler = merkez.d.kanitlar(x.bolum ?? "")
                let sira = kardesler.firstIndex(of: x) ?? 0
                VStack(alignment: .leading, spacing: 18) {
                    Text(x.kitapAdi).font(.caption.weight(.semibold)).foregroundStyle(Color.soluk)
                    Text("“\(x.metin)”").font(.serif(22)).foregroundStyle(Color.murekkep).fixedSize(horizontal: false, vertical: true)
                    Picker("Rol", selection: Binding(get: { x.rol }, set: { merkez.rol(x.id, $0) })) {
                        Text("Rol yok").tag(Rol?.none)
                        ForEach(Rol.allCases, id: \.self) { Text($0.ad).tag(Rol?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Kenar notu: bu cümle iddiaya ne katıyor?", text: $not, axis: .vertical)
                        .font(.serif(16).italic()).lineLimit(2...6)
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                        .onSubmit { merkez.notYaz(x.id, not) }
                    let bagli = merkez.d.baglar.compactMap { b -> String? in b.kaynak == x.id ? b.hedef : (b.hedef == x.id ? b.kaynak : nil) }
                    if !bagli.isEmpty {
                        Text("Bağlı").font(.headline)
                        ForEach(bagli, id: \.self) { id in
                            if id.hasPrefix("iddia:") {
                                Label("Bölümün iddiası", systemImage: "flag").font(.subheadline)
                            } else if let y = merkez.d.isaretler.first(where: { $0.id == id }) {
                                Button { degistir(y.id) } label: { IsaretKarti(x: y, satir: 3) }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Button { if sira > 0 { degistir(kardesler[sira - 1].id) } } label: { Label("Önceki", systemImage: "chevron.left") }.disabled(sira == 0)
                        Spacer()
                        Text("\(sira + 1)/\(kardesler.count)").font(.caption.monospacedDigit()).foregroundStyle(Color.soluk)
                        Spacer()
                        Button { if sira < kardesler.count - 1 { degistir(kardesler[sira + 1].id) } } label: { Label("Sonraki", systemImage: "chevron.right") }.disabled(sira >= kardesler.count - 1)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .onAppear { not = x.not }
                .onChange(of: isaretId) { _, _ in not = merkez.d.isaretler.first { $0.id == isaretId }?.not ?? "" }
                .onDisappear { if not != x.not { merkez.notYaz(x.id, not) } }
            }
        }
    }
}
