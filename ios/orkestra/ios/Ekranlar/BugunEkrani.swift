// Bugün — şefin masası. Koyu zemin, üstte nabız parıltısı; az metin, çok görsel:
// büyük nabız halkası → alan nabızları → bütün süreçler tek ızgarada → bugünün üç hamlesi → boru hatları → Yön.
import SwiftUI

struct BugunEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var yol = NavigationPath()

    var body: some View {
        NavigationStack(path: $yol) {
            ZStack(alignment: .top) {
                Tema.zemin.ignoresSafeArea()
                if let d = merkez.durum { Parilti(renk: Tema.nabiz(d.nabiz)).ignoresSafeArea() }
                ScrollView {
                    if let d = merkez.durum {
                        VStack(spacing: 18) {
                            hero(d)
                            alanSeridi(d)
                            kafesKarti(d)
                            hamleler(d)
                            borular(d)
                            yonKarti(d)
                        }
                        .padding(.horizontal, 16).padding(.bottom, 30)
                    } else {
                        ProgressView().padding(.top, 160)
                    }
                }
                .refreshable { await merkez.tazele() }
            }
            .navigationDestination(for: String.self) { SurecDetay(id: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: rota.surec) { _, id in
                if let id, rota.sekme == 0 { yol.append(id); rota.surec = nil }
            }
        }
    }

    // MARK: hero
    func hero(_ d: Durumlar) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(d.simdi.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))))
                    .font(.system(size: 12, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                tazelik(d)
            }
            .padding(.top, 6)
            BuyukNabiz(nabiz: d.nabiz, boy: 188)
            Text(d.ozetCumlesi)
                .font(.system(size: 18, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                .foregroundStyle(.white).padding(.horizontal, 12)
            HStack(spacing: 8) {
                ForEach([Durum.tikali, .aksiyor, .gecikti, .akiyor], id: \.self) { s in
                    VStack(spacing: 2) {
                        Text("\(d.say(s))").font(.yuvarlak(22, .bold)).foregroundStyle(d.say(s) > 0 ? Tema.durum(s) : .white.opacity(0.25))
                        Text(s.ad).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Tema.durum(s).opacity(d.say(s) > 0 ? 0.13 : 0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.durum(s).opacity(d.say(s) > 0 ? 0.35 : 0.08), lineWidth: 1))
                }
            }
        }
    }

    func tazelik(_ d: Durumlar) -> some View {
        HStack(spacing: 5) {
            if merkez.yukleniyor { ProgressView().controlSize(.mini) }
            Image(systemName: d.veriEski ? "exclamationmark.icloud" : "checkmark.icloud")
            Text(d.veri.uretimZamani.map { Tarih.gorece($0, d.simdi) } ?? "—")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(d.veriEski ? Tema.durum(.aksiyor) : .white.opacity(0.6))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(.white.opacity(0.07), in: Capsule())
    }

    // MARK: alanlar — beşi eşit
    func alanSeridi(_ d: Durumlar) -> some View {
        HStack(spacing: 8) {
            ForEach(d.veri.alanlar) { a in
                let n = d.nabiz(alanId: a.id)
                Button {
                    rota.sekme = 1
                    NotificationCenter.default.post(name: .alanSec, object: a.id)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Halka(oran: Double(n ?? 0) / 100, renk: Tema.alan(a.id), kalinlik: 4.5)
                            Text(n.map { "\($0)" } ?? "—").font(.yuvarlak(14, .bold)).monospacedDigit().foregroundStyle(.white)
                        }
                        .frame(width: 46, height: 46)
                        Text(a.kisa).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Tema.kart, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Tema.cizgi, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: bütün süreçler
    func kafesKarti(_ d: Durumlar) -> some View {
        Kart(baslik: "Bütün süreçler", simge: "square.grid.3x3.fill") {
            SurecKafesi(d: d, karoG: 56, karoY: 38, punto: 10, araliklar: 7) { h, v in
                AnyView(NavigationLink(value: h.id) { v }.buttonStyle(.plain))
            }
            VStack(alignment: .leading, spacing: 4) {
                Tutti(d: d, gun: 28, yukseklik: 34)
                HStack {
                    Text("son 4 hafta · her gün kaç süreç çaldı")
                    Spacer()
                    Text("bugün")
                }
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: hamleler
    func kisaNeden(_ s: String) -> String {
        let ilk = s.components(separatedBy: ". ").first ?? s
        return ilk.count > 90 ? String(ilk.prefix(88)) + "…" : ilk
    }

    func hamleler(_ d: Durumlar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BUGÜNÜN SIRASI").font(.system(size: 11, weight: .heavy)).tracking(1.4).foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            if d.ilk3.isEmpty {
                Text("Bütün süreçler ritminde. Yeni bir şey eklemek yerine süren işi derinleştir.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)).padding(16)
            }
            ForEach(Array(d.ilk3.enumerated()), id: \.element.id) { i, h in
                let alan = d.hukum(h.surecId)?.surec.alan ?? ""
                let renk = h.tur == .onar ? Tema.durum(.tikali) : Tema.alan(alan)
                Button { yol.append(h.surecId) } label: {
                    HStack(spacing: 14) {
                        Text("\(i + 1)").font(.yuvarlak(17, .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(LinearGradient(colors: [renk, renk.opacity(0.6)], startPoint: .top, endPoint: .bottom), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.fiil.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(renk)
                            Text(h.baslik).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text(kisaNeden(h.neden)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: h.acilis == nil ? "laptopcomputer" : "arrow.up.forward.app")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [renk.opacity(0.20), renk.opacity(0.04)], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(renk.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Yarına bırak", systemImage: "moon") { merkez.ertele(h.surecId) } }
            }
            let kalan = d.hamleler.count - d.ilk3.count
            if kalan > 0 {
                Text("+\(kalan) hamle daha sırada — üçü bitmeden açılmaz").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35)).padding(.leading, 4)
            }
        }
    }

    // MARK: borular
    func borular(_ d: Durumlar) -> some View {
        Kart(baslik: "Sabah görevleri", simge: "gearshape.arrow.triangle.2.circlepath") {
            ForEach(d.veri.borular) { b in
                let renk: Color = b.durum == "tikali" ? Tema.durum(.tikali) : b.durum == "tamam" ? Tema.durum(.akiyor) : .white.opacity(0.4)
                HStack(spacing: 10) {
                    Circle().fill(renk).frame(width: 8, height: 8)
                    Text(b.saat).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    Text(b.ad).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text(b.durum == "tikali" ? "tıkalı" : b.durum == "tamam" ? "tamam" : "bekliyor")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(renk)
                }
            }
        }
    }

    // MARK: Yön
    func yonKarti(_ d: Durumlar) -> some View {
        let olcum = Tarih.coz(d.veri.yon.sonraki_olcum)
        let kalan = olcum.map { Tarih.gunFarki(d.simdi, $0) }
        let uretim = d.hukum("uretim")
        return Kart(baslik: "Yön", simge: "scope") {
            HStack(spacing: 14) {
                Halka(oran: uretim?.surec.ilerleme?.oran ?? 0, renk: Tema.alan("vault"), kalinlik: 6)
                    .frame(width: 54, height: 54)
                    .overlay(Text("\(uretim?.surec.ilerleme?.a ?? 0)/\(uretim?.surec.ilerleme?.b ?? 1)").font(.yuvarlak(13, .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.veri.yon.ana).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Hedef: " + d.veri.yon.hedef).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    if let kalan {
                        Text("Ölçüme \(kalan) gün").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(kalan <= 21 ? Tema.durum(.aksiyor) : .white.opacity(0.55))
                    }
                }
            }
        }
    }
}

/// Nabız: parlayan ana halka — üstte büyük sayı.
struct BuyukNabiz: View {
    var nabiz: Int
    var boy: CGFloat
    var body: some View {
        let renk = Tema.nabiz(nabiz)
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: boy * 0.07).frame(width: boy, height: boy)
            Circle().trim(from: 0, to: max(0.01, Double(nabiz) / 100))
                .stroke(AngularGradient(colors: [renk.opacity(0.35), renk], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Double(nabiz) / 100)),
                        style: StrokeStyle(lineWidth: boy * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: boy, height: boy)
                .shadow(color: renk.opacity(0.55), radius: 9)
            VStack(spacing: -4) {
                Text("\(nabiz)").font(.system(size: boy * 0.4, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Text("NABIZ").font(.system(size: 10, weight: .heavy)).tracking(2).foregroundStyle(.white.opacity(0.5))
            }
        }
        .background(Circle().fill(RadialGradient(colors: [renk.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: boy * 0.75))
            .frame(width: boy * 1.5, height: boy * 1.5))
        .frame(width: boy, height: boy)
    }
}

/// Ekranın üstündeki yumuşak renkli ışık.
struct Parilti: View {
    var renk: Color
    var body: some View {
        RadialGradient(colors: [renk.opacity(0.40), renk.opacity(0.12), .clear],
                       center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 520)
            .frame(height: 620)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension Notification.Name {
    static let alanSec = Notification.Name("orkestra.alanSec")
}
