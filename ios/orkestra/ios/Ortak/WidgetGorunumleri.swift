// Widget görünümleri + uygulamayla ortak "durum ızgarası". Ortak'ta durur: widget eklentisi kullanır,
// uygulama da DEBUG'da PNG'ye çizip sınar. Tasarım ilkesi: tek alana odaklanma yok — her alan eşit satır,
// her süreç tek karo (renk = durum), altta tüm süreçlerin birleşik 4 haftalık nabzı.
import SwiftUI
import WidgetKit

enum WBoy { case kucuk, orta, buyuk, daire, dikdortgen, satir }

extension Surec {
    var kisaAd: String {
        switch id {
        case "kelime-eki": return "Kelime Eki"
        case "notlar": return "Notlar"
        case "gramer": return "Gramer"
        case "onkapi": return "On Kapı"
        case "mulakat": return "Mülakat"
        case "muhendis": return "Mühendis"
        default: return String(ad.split(separator: " ").first ?? Substring(ad))
        }
    }
}

/// Siyaha yakın zemin + üstte nabız renginde parıltı. Widget'ın tek zemini.
struct WidgetArkaPlan: View {
    var nabiz: Int
    var parilti: Double = 1
    var body: some View {
        let renk = Tema.nabiz(nabiz)
        ZStack {
            Tema.zemin
            RadialGradient(colors: [renk.opacity(0.30 * parilti), renk.opacity(0.07 * parilti), .clear],
                           center: UnitPoint(x: 0.5, y: -0.08), startRadius: 0, endRadius: 230)
            LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

/// Bir sürecin tek karosu: renk = durum, altında sessizlik.
struct SurecKaro: View {
    var h: Hukum
    var genislik: CGFloat
    var yukseklik: CGFloat
    var punto: CGFloat = 9
    var body: some View {
        let renk = Tema.durum(h.durum)
        let sessiz = !h.durum.hukumVar
        let alt: String = sessiz ? (h.durum == .uykuda ? "uykuda" : "—")
            : (h.sessizlik.map { $0 == 0 ? "bugün" : "\($0)g" } ?? "yeni")
        VStack(spacing: 1) {
            Text(h.surec.kisaAd).font(.system(size: punto, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Color.white.opacity(sessiz ? 0.45 : 0.95))
            Text(alt).font(.system(size: punto - 1.5, weight: .bold).monospacedDigit())
                .foregroundStyle(sessiz ? Color.white.opacity(0.3) : renk)
        }
        .frame(width: genislik, height: yukseklik)
        .background(renk.opacity(sessiz ? 0.06 : h.durum == .akiyor ? 0.16 : 0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(renk.opacity(sessiz ? 0.18 : 0.6), style: StrokeStyle(lineWidth: 1, dash: h.durum == .gorunmuyor ? [2, 2] : [])))
    }
}

/// Bütün süreçler: her alan bir satır, her süreç bir karo. Alan satırları eşit ağırlıkta — hiçbiri öne çıkmaz.
struct SurecKafesi: View {
    var d: Durumlar
    var karoG: CGFloat = 50
    var karoY: CGFloat = 32
    var punto: CGFloat = 9
    var araliklar: CGFloat = 5
    var sar: (Hukum, AnyView) -> AnyView = { h, v in
        AnyView(Link(destination: URL(string: "orkestra://surec/\(h.id)")!) { v })
    }

    var body: some View {
        VStack(spacing: araliklar) {
            ForEach(d.veri.alanlar) { a in
                let satir = d.hukumler.filter { $0.surec.alan == a.id }
                if !satir.isEmpty {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Image(systemName: Tema.alanSimge(a.id)).font(.system(size: punto + 1, weight: .bold))
                                .foregroundStyle(Tema.alan(a.id))
                            Text(a.kisa).font(.system(size: punto - 1, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 46, alignment: .leading)
                        HStack(spacing: 4) {
                            ForEach(satir) { h in sar(h, AnyView(SurecKaro(h: h, genislik: karoG, yukseklik: karoY, punto: punto))) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

/// Bütün süreçlerin birleşik nabzı: o gün kaç süreç çaldı (son N gün).
struct Tutti: View {
    var d: Durumlar
    var gun: Int = 28
    var yukseklik: CGFloat = 20
    var body: some View {
        let aktif = d.hukumler.filter { $0.durum.hukumVar }
        let izler = aktif.map { Array($0.surec.iz.suffix(gun)) }
        let sayi: [Int] = (0..<gun).map { i in izler.filter { i < $0.count && $0[i] > 0 }.count }
        let tepe = max(1, sayi.max() ?? 1)
        let renk = Tema.nabiz(d.nabiz)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(sayi.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LinearGradient(colors: [renk, renk.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                    .opacity(sayi[i] == 0 ? 0.15 : 1)
                    .frame(maxWidth: .infinity)
                    .frame(height: sayi[i] == 0 ? 2 : max(3, yukseklik * CGFloat(sayi[i]) / CGFloat(tepe)))
            }
        }
        .frame(height: yukseklik, alignment: .bottom)
    }
}

struct DurumSayaclari: View {
    var d: Durumlar
    var boy: CGFloat = 12
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Durum.tikali, .aksiyor, .gecikti, .akiyor], id: \.self) { s in
                HStack(spacing: 3) {
                    Circle().fill(Tema.durum(s)).frame(width: boy * 0.55, height: boy * 0.55)
                    Text("\(d.say(s))").font(.yuvarlak(boy, .bold)).monospacedDigit()
                        .foregroundStyle(d.say(s) > 0 ? Color.white : Color.white.opacity(0.3))
                }
            }
        }
    }
}

struct OrkestraWidgetGorunumu: View {
    var d: Durumlar?
    var boy: WBoy

    var body: some View {
        if let d {
            switch boy {
            case .kucuk: kucuk(d).environment(\.colorScheme, .dark)
            case .orta: orta(d).environment(\.colorScheme, .dark)
            case .buyuk: buyuk(d).environment(\.colorScheme, .dark)
            case .daire: daire(d)
            case .dikdortgen: dikdortgen(d)
            case .satir: Text("♪ \(d.nabiz) · \(d.say(.tikali)) tıkalı · \(d.say(.aksiyor)) aksıyor")
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note.list").font(.title2)
                Text("Orkestra'yı aç, vault klasörünü seç.").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white.opacity(0.6)).environment(\.colorScheme, .dark)
        }
    }

    // MARK: büyük — tek bakışta bütün tablo
    func buyuk(_ d: Durumlar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                NabizHalkasi(nabiz: d.nabiz, boy: 54)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("ORKESTRA").font(.system(size: 10, weight: .heavy)).tracking(1.6).foregroundStyle(Color.white.opacity(0.55))
                        Spacer()
                        DurumSayaclari(d: d, boy: 12)
                    }
                    Text(d.ozetMetni).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            SurecKafesi(d: d, karoG: 52, karoY: 33, punto: 9, araliklar: 5)
            VStack(alignment: .leading, spacing: 3) {
                Tutti(d: d, gun: 28, yukseklik: 22)
                HStack {
                    Text("son 4 hafta · her gün kaç süreç çaldı")
                    Spacer()
                    Text("bugün")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(d.ilk3.prefix(2).enumerated()), id: \.element.id) { i, h in
                    Link(destination: URL(string: "orkestra://surec/\(h.surecId)")!) { hamleSatiri(i + 1, h, d) }
                }
            }
        }
    }

    func hamleSatiri(_ n: Int, _ h: Hamle, _ d: Durumlar) -> some View {
        let r = renk(h, d)
        return HStack(spacing: 8) {
            Text("\(n)").font(.yuvarlak(10, .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(r, in: Circle())
            Text(h.baslik).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 4)
            Text(h.fiil).font(.system(size: 9, weight: .bold)).foregroundStyle(h.tur == .onar ? Tema.durum(.tikali) : r)
                .padding(.horizontal, 7).padding(.vertical, 2).background(r.opacity(0.18), in: Capsule())
        }
    }

    func renk(_ h: Hamle, _ d: Durumlar) -> Color {
        h.tur == .onar ? Tema.durum(.tikali) : Tema.alan(d.hukum(h.surecId)?.surec.alan ?? "")
    }

    // MARK: orta
    func orta(_ d: Durumlar) -> some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                NabizHalkasi(nabiz: d.nabiz, boy: 78)
                DurumSayaclari(d: d, boy: 11)
            }
            VStack(alignment: .leading, spacing: 9) {
                noktaIzgarasi(d)
                Tutti(d: d, gun: 28, yukseklik: 14)
                ForEach(Array(d.ilk3.prefix(2).enumerated()), id: \.element.id) { i, h in
                    Link(destination: URL(string: "orkestra://surec/\(h.surecId)")!) { hamleSatiri(i + 1, h, d) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Her süreç bir nokta, alanlar satır — kompakt genel görünüm.
    func noktaIzgarasi(_ d: Durumlar) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(d.veri.alanlar) { a in
                let satir = d.hukumler.filter { $0.surec.alan == a.id }
                if !satir.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: Tema.alanSimge(a.id)).font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Tema.alan(a.id)).frame(width: 12)
                        ForEach(satir) { h in
                            RoundedRectangle(cornerRadius: 3).fill(Tema.durum(h.durum).opacity(h.durum.hukumVar ? 1 : 0.35))
                                .frame(width: 16, height: 9)
                        }
                    }
                }
            }
        }
    }

    // MARK: küçük
    func kucuk(_ d: Durumlar) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                NabizHalkasi(nabiz: d.nabiz, boy: 56)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach([Durum.tikali, .aksiyor, .gecikti], id: \.self) { s in
                        HStack(spacing: 4) {
                            Text("\(d.say(s))").font(.yuvarlak(13, .bold)).monospacedDigit()
                            Circle().fill(Tema.durum(s)).frame(width: 7, height: 7)
                        }
                        .foregroundStyle(d.say(s) > 0 ? Color.white : Color.white.opacity(0.3))
                    }
                }
            }
            noktaIzgarasi(d)
            Spacer(minLength: 0)
        }
    }

    // MARK: kilit ekranı
    func daire(_ d: Durumlar) -> some View {
        Gauge(value: Double(d.nabiz), in: 0...100) {
            Image(systemName: "music.note")
        } currentValueLabel: {
            Text("\(d.nabiz)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    func dikdortgen(_ d: Durumlar) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("♪ Orkestra · \(d.nabiz)").font(.system(size: 13, weight: .bold))
            if let h = d.ilk3.first {
                Text("\(h.fiil): \(h.baslik)").font(.system(size: 12)).lineLimit(1)
            }
            Text("\(d.say(.tikali)) tıkalı · \(d.say(.aksiyor)) aksıyor · \(d.say(.gecikti)) gecikti")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

extension Durumlar {
    func nabiz(alanId: String) -> Int? {
        let a = aktif.filter { $0.surec.alan == alanId }
        let payda = a.reduce(0.0) { $0 + $1.agirlik }
        guard payda > 0 else { return nil }
        return Int((a.reduce(0.0) { $0 + $1.agirlik * $1.durum.puan } / payda * 100).rounded())
    }

    var ozetMetni: String {
        if let b = tikaliBorular.first { return "\(b.ad) tıkalı. \(say(.aksiyor)) süreç aksıyor." }
        let s = sorunlu
        return s.isEmpty ? "Bütün süreçler ritminde." : "\(s.count) süreç ilgi bekliyor: \(s.prefix(2).map(\.surec.kisaAd).joined(separator: ", "))."
    }
}
