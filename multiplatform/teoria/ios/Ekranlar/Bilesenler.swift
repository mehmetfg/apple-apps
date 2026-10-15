// Ortak görsel parçalar: yüzey kartı, canlı kavram gökyüzü, haptik, küçük etiketler.
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

struct Yuzey<Icerik: View>: View {
    var dolgu: CGFloat = 18
    @ViewBuilder var icerik: Icerik

    var body: some View {
        icerik
            .padding(dolgu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Tema.cizgi.opacity(0.6), lineWidth: 0.5))
    }
}

struct Bolumbasi: View {
    let metin: String
    var sembol: String? = nil
    var renk: Color = Tema.ikincil

    var body: some View {
        HStack(spacing: 6) {
            if let s = sembol { Image(systemName: s).font(.system(size: 11, weight: .bold)) }
            Text(metin.uppercased(with: Dil.tr)).font(.system(size: 12, weight: .bold)).tracking(0.7)
        }
        .foregroundStyle(renk)
    }
}

struct Hap: View {
    let metin: String
    var renk: Color = Tema.vurgu
    var dolu = false

    var body: some View {
        Text(metin)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(dolu ? renk : renk.opacity(0.12)))
            .foregroundStyle(dolu ? Color.white : renk)
    }
}

// MARK: - Kavram gökyüzü (canlı)

/// Her kavram bir yıldız: oturmuş olan altın ve parlak, öğrenilmekte olan soluk, hiç görülmemiş yalnız bir nokta.
/// Yavaşça döner; "Hareketi azalt" açıksa durur.
struct GokyuzuGorunum: View {
    struct Yildiz: Identifiable {
        let id: String
        let ad: String
        let parlaklik: Double    // 0 görülmedi · 0.4 öğreniliyor · 1 oturdu
        let renk: Color
    }

    let yildizlar: [Yildiz]
    var hareket = true
    @Environment(\.accessibilityReduceMotion) private var azalt
    @State private var secili: Yildiz?

    static func kur(_ p: Paket, _ d: Durum) -> [Yildiz] {
        p.kavramlar.map { k in
            let kart = d.kartlar["hatirla:\(k.id)"]
            let pr: Double = kart.map { $0.oturmus ? 1 : 0.25 + min(0.5, $0.kararlilik / 40) } ?? 0
            return Yildiz(id: k.id, ad: k.terim, parlaklik: pr, renk: Tema.renk(p.kitap(k.kitap)?.renk))
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: azalt || !hareket)) { z in
            let t = azalt || !hareket ? 0 : z.date.timeIntervalSinceReferenceDate
            Canvas { c, boyut in
                let merkez = CGPoint(x: boyut.width / 2, y: boyut.height / 2)
                let yaricap = min(boyut.width, boyut.height) * 0.48
                // Bağ çizgileri: aynı kitabın oturmuş yıldızları arasında ince bir takımyıldız
                var konum: [String: CGPoint] = [:]
                for (i, y) in yildizlar.enumerated() {
                    konum[y.id] = nokta(i, t, merkez, yaricap, boyut)
                }
                let parlak = yildizlar.filter { $0.parlaklik >= 1 }
                for (a, b) in zip(parlak, parlak.dropFirst()) {
                    guard let p1 = konum[a.id], let p2 = konum[b.id] else { continue }
                    var yol = Path(); yol.move(to: p1); yol.addLine(to: p2)
                    c.stroke(yol, with: .color(Tema.altin.opacity(0.18)), lineWidth: 0.7)
                }
                for (i, y) in yildizlar.enumerated() {
                    let p = konum[y.id] ?? merkez
                    let kirp = 0.75 + 0.25 * sin(t * 1.3 + Double(i))
                    let r: CGFloat = y.parlaklik >= 1 ? 3.2 : (y.parlaklik > 0 ? 2.0 : 1.1)
                    let renk: Color = y.parlaklik >= 1 ? Tema.altin : (y.parlaklik > 0 ? y.renk : Tema.soluk)
                    if y.parlaklik >= 1 {
                        let h = r * 4.5
                        c.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: h * 2, height: h * 2)),
                               with: .radialGradient(Gradient(colors: [Tema.altin.opacity(0.35 * kirp), .clear]),
                                                     center: p, startRadius: 0, endRadius: h))
                    }
                    c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(renk.opacity(y.parlaklik > 0 ? max(0.55, y.parlaklik) * kirp : 0.45)))
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Kavram gökyüzü: \(yildizlar.filter { $0.parlaklik >= 1 }.count) kavram oturdu, \(yildizlar.count) kavramdan.")
    }

    private func nokta(_ i: Int, _ t: Double, _ m: CGPoint, _ r: CGFloat, _ b: CGSize) -> CGPoint {
        let aci = Gokyuzu.hash(i * 7 + 3) * .pi * 2 + t * 0.02 * (0.5 + Gokyuzu.hash(i))
        let uzak = CGFloat(sqrt(Gokyuzu.hash(i * 13 + 5))) * r
        let yatay: CGFloat = b.width / max(b.height, 1) > 1.4 ? 1.6 : 1
        let x: CGFloat = m.x + CGFloat(cos(aci)) * uzak * yatay
        let y: CGFloat = m.y + CGFloat(sin(aci)) * uzak * 0.85
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Haptik

/// Bütün dokunsal geri bildirim buradan geçer ve Ayarlar › "Dokunsal geri bildirim" anahtarına uyar.
/// Bildirimsel (beyan) olanlar `.dokun(...)` ile, eylem içinden çağrılanlar `Dokunus.x()` ile.
enum Dokunus {
    static var acik: Bool { UserDefaults.standard.object(forKey: "teoria.haptik") as? Bool ?? true }

    #if os(iOS) && canImport(CoreHaptics)
    nonisolated(unsafe) private static var motor: CHHapticEngine?
    #endif

    @MainActor static func secim() {
        #if os(iOS)
        guard acik else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    @MainActor static func hafif(_ guc: CGFloat = 0.7) {
        #if os(iOS)
        guard acik else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: guc)
        #endif
    }

    @MainActor static func sert() {
        #if os(iOS)
        guard acik else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
        #endif
    }

    @MainActor static func basari() {
        #if os(iOS)
        guard acik else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    @MainActor static func uyari() {
        #if os(iOS)
        guard acik else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// Kalp: kısa çift vuruş (favori).
    @MainActor static func kalp() {
        desen([(0, 0.55, 0.5), (0.12, 0.9, 0.6)])
    }

    /// Kür başlıyor: yavaş yükselen nabız, sonra yumuşak bir dalga — "nefes al, başlıyoruz".
    @MainActor static func kurBasla() {
        desen([(0, 0.35, 0.2), (0.22, 0.55, 0.3), (0.42, 0.8, 0.45)], kuyruk: (0.5, 0.3, 0.35))
    }

    /// Kitap açılışı: sayfa çevirir gibi kısa, kumlu bir sürtünme.
    @MainActor static func sayfa() {
        desen([(0, 0.4, 0.9)], kuyruk: (0.02, 0.22, 0.12))
    }

    /// Kayıt başladı / bitti.
    @MainActor static func kayit(_ basladi: Bool) {
        basladi ? desen([(0, 0.9, 0.7), (0.09, 0.5, 0.3)]) : desen([(0, 0.5, 0.3), (0.09, 0.9, 0.7)])
    }

    /// Kademe atlayışı: yükselen üç vuruş ve yumuşak bir titreşim kuyruğu.
    @MainActor static func kademeAtladi() {
        desen([(0, 0.45, 0.4), (0.11, 0.7, 0.6), (0.22, 1.0, 0.8)], kuyruk: (0.36, 0.45, 0.35))
    }

    /// (zaman, şiddet, keskinlik) vuruşları; isteğe bağlı sürekli kuyruk (başlangıç, süre, şiddet).
    @MainActor private static func desen(_ vurus: [(Double, Double, Double)], kuyruk: (Double, Double, Double)? = nil) {
        #if os(iOS) && canImport(CoreHaptics)
        guard acik, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if motor == nil {
                motor = try CHHapticEngine()
                motor?.isAutoShutdownEnabled = true
                motor?.resetHandler = { try? motor?.start() }
            }
            try motor?.start()
            var olay: [CHHapticEvent] = vurus.map { t, g, k in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(g)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(k)),
                ], relativeTime: t)
            }
            if let (t, sure, g) = kuyruk {
                olay.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(g)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
                ], relativeTime: t, duration: sure))
            }
            let oyuncu = try motor?.makePlayer(with: CHHapticPattern(events: olay, parameters: []))
            try oyuncu?.start(atTime: 0)
        } catch {}
        #endif
    }
}

/// `sensoryFeedback`'in ayara uyan hâli.
private struct Dokun<T: Equatable>: ViewModifier {
    let geri: SensoryFeedback
    let tetik: T
    @AppStorage("teoria.haptik") private var acik = true
    func body(content: Content) -> some View {
        content.sensoryFeedback(geri, trigger: tetik) { _, _ in acik }
    }
}

extension View {
    func dokun<T: Equatable>(_ geri: SensoryFeedback, _ tetik: T) -> some View { modifier(Dokun(geri: geri, tetik: tetik)) }
}

// MARK: - İkonlu sekme seçici

/// Üst sekmeler ve bölüm seçicileri: her seçenekte SF simgesi + ad. Seçili olan cam bir hapın içinde,
/// hap seçimler arasında kayar (matchedGeometry). Dar yerde (`sikisik`) seçili olmayanlarda yalnız simge kalır.
struct SimgeSecici<T: Hashable>: View {
    struct Secenek: Identifiable { let deger: T; let ad: String; let sembol: String; var id: String { ad } }
    let secenekler: [Secenek]
    @Binding var secili: T
    var sikisik = false
    var esit = true
    @Namespace private var hap

    var body: some View {
        HStack(spacing: 2) {
            ForEach(secenekler) { s in
                let on = s.deger == secili
                Button {
                    guard !on else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { secili = s.deger }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? dolu(s.sembol) : s.sembol)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                        if !sikisik || on {
                            Text(s.ad).font(.system(size: 13.5, weight: on ? .semibold : .medium)).lineLimit(1).fixedSize()
                        }
                    }
                    .foregroundStyle(on ? Tema.vurgu : Tema.ikincil)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: esit ? .infinity : nil)
                    .background {
                        if on {
                            Capsule().fill(Tema.yuzey)
                                .overlay(Capsule().strokeBorder(Tema.vurgu.opacity(0.18)))
                                .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "hap", in: hap)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.ad)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Tema.yuzey2))
        .dokun(.selection, secili)
    }

    /// Seçili simgenin dolu hâli (varsa): "heart" → "heart.fill".
    private func dolu(_ s: String) -> String {
        let doluOlur = ["heart", "bell", "bookmark", "book", "person.crop.circle", "checkmark.seal", "sun.max",
                        "text.bubble", "character.book.closed", "shippingbox", "books.vertical", "star"]
        return doluOlur.contains(s) ? s + ".fill" : s
    }
}

// MARK: - Görünüm yardımcıları

extension View {
    @ViewBuilder func eger<V: View>(_ k: Bool, _ d: (Self) -> V) -> some View {
        if k { d(self) } else { self }
    }

    func tamGenislik() -> some View { frame(maxWidth: .infinity, alignment: .leading) }
}

struct AnaDugme: ButtonStyle {
    var renk: Color = Tema.vurgu
    func makeBody(configuration: Configuration) -> some View { AnaDugmeGovde(configuration: configuration, renk: renk) }
}

private struct AnaDugmeGovde: View {
    let configuration: ButtonStyle.Configuration
    let renk: Color
    @Environment(\.isEnabled) private var etkin
    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Capsule().fill(renk.gradient))
            .foregroundStyle(.white)
            .opacity(etkin ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct IkinciDugme: ButtonStyle {
    var renk: Color = Tema.vurgu
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Capsule().fill(renk.opacity(configuration.isPressed ? 0.22 : 0.13)))
            .foregroundStyle(renk)
    }
}
