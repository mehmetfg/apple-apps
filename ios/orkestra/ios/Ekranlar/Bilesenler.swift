// Ekranların ortak parçaları ve "nasıl akışa döner" önerileri.
import SwiftUI

struct DurumCipi: View {
    var durum: Durum
    var kucuk = false
    var body: some View {
        Label(durum.ad, systemImage: Tema.durumSimge(durum))
            .font(.system(size: kucuk ? 10 : 11, weight: .semibold))
            .padding(.horizontal, kucuk ? 6 : 8).padding(.vertical, kucuk ? 2 : 3)
            .background(Tema.durum(durum).opacity(0.16), in: Capsule())
            .foregroundStyle(Tema.durum(durum))
    }
}

struct Kart<Icerik: View>: View {
    var baslik: String? = nil
    var simge: String? = nil
    @ViewBuilder var icerik: Icerik
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let baslik {
                Label(baslik, systemImage: simge ?? "circle")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            icerik
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Tema.cizgi, lineWidth: 1))
    }
}

struct AcButonu: View {
    var acilis: String?
    var ad: String?
    var body: some View {
        if let acilis, let url = URL(string: acilis) {
            Link(destination: url) {
                Label("\(ad ?? "Aç")", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
        } else {
            Label("Mac'te", systemImage: "laptopcomputer")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }
}

struct SurecSatiri: View {
    var h: Hukum
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Tema.alan(h.surec.alan).opacity(0.15))
                Image(systemName: Tema.alanSimge(h.surec.alan)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.alan(h.surec.alan))
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .bottomTrailing) { DurumNoktasi(durum: h.durum, boy: 10).overlay(Circle().stroke(Tema.kart, lineWidth: 2)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(h.surec.ad).font(.system(size: 15, weight: .semibold))
                Text(h.neden).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let s = h.sessizlik, h.durum.hukumVar {
                Text(s == 0 ? "bugün" : "\(s)g").font(.yuvarlak(13)).monospacedDigit()
                    .foregroundStyle(Tema.durum(h.durum))
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

enum Yol {
    /// Bir süreç bu durumdayken akışa nasıl döner — kural tabanlı, kısa adımlar.
    static func oneri(_ h: Hukum, _ d: Durumlar) -> [String] {
        let s = h.surec
        switch h.durum {
        case .tikali:
            if let b = d.veri.boru(s.boru), b.durum == "tikali", b.besler.contains(s.id) {
                return ["Sorun senin çalışman değil, boru hattı: \(b.ad).",
                        b.not,
                        "Mac'te Tezgâh.app'i aç ya da Claude'a \"\(b.ad) koşmadı\" de; görev elle bir kez koşunca akış açılır.",
                        "Onarılana kadar bu süreç için yeni iş üretilmez — beklemen doğru."]
            }
            if let bk = s.birikme {
                return ["Üretim tüketimi geçti: \(bk.bekleyen ?? 0) \(bk.birim) bekliyor, eşik \(bk.esik).",
                        "Yeni metin isteme. Bekleyenlerden en kısasını seç ve bitir.",
                        "Eşiğin altına inince durum kendiliğinden \"akıyor\"a döner; borç sayılmaz, silinmez.",
                        "Bekleyenler eskidiyse arşivlemek de geçerli bir karardır — o karar senin."]
            }
            return [h.neden]
        case .aksiyor:
            return ["\(h.sessizlik ?? 0) gündür sessiz. Kopuşu kapatmanın yolu tam oturum değil, en küçük dokunuş.",
                    "Bugün yalnız şu: \(s.bugun).",
                    "Beş dakika yeter; Orkestra dokunuşu ölçer, süreyi değil.",
                    s.kademe == "bakim" ? "Bakım kademesinde: amaç ilerlemek değil, geri gitmemek." :
                        "Bu süreç Yön Belgesi'nde \(s.kademe) kademesinde; öncelik buradan geliyor."]
        case .gecikti:
            return ["Ritim \(s.ritim == 1 ? "her gün" : "\(s.ritim) günde bir"); \(h.sessizlik ?? 0) gün geçti.",
                    "Henüz kopmadı. Bugün tek dokunuş ritmi geri getirir: \(s.bugun)."]
        case .baslamadi:
            return ["Kurulmuş ama ilk iz yok.", "İlk adımı küçült: \(s.bugun)."]
        case .akiyor:
            return ["Ritminde. Artırma, koru.", h.bugunDokunuldu ? "Bugünkü dokunuş yapıldı." : "Sırada: \(s.bugun)."]
        case .uykuda:
            return ["Senin kararınla bekliyor: \(s.durdu_neden).",
                    "Devam ya da arşiv — karar verilene kadar Orkestra uyarmaz, sayaç işletmez."]
        case .gorunmuyor:
            return ["Bu süreç telefonda yaşıyor; vault'a iz bırakmadığı için Orkestra hüküm veremiyor.",
                    s.ayrinti.first?.d ?? "",
                    "Görünür olması için uygulamanın ilerlemesini vault'a yazması gerekir (sonraki aşama)."]
        }
    }
}

extension Durumlar {
    var ozetCumlesi: String {
        if let b = tikaliBorular.first { return "\(b.ad) tıkalı — bugünün ilk işi onu açmak." }
        let ana = aktif.filter { $0.surec.kademe == "ana" }
        let anaKotu = ana.filter { $0.durum.sorunlu }
        if !anaKotu.isEmpty { return "Ana odakta \(anaKotu.map(\.surec.ad).joined(separator: ", ")) \(anaKotu[0].durum.ad)." }
        let s = sorunlu
        if s.isEmpty { return "Bütün süreçler ritminde." }
        return "Ana odak akıyor; \(s.count) süreç ilgi bekliyor."
    }
}
