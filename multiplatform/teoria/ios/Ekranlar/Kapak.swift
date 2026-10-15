// Kitap kapağı, akışın giriş animasyonu ve X'e paylaşım.
// Kapaklar uygulamaya gömülü küçük JPEG'ler (veri/kapak.py: kapak-<kitap-id>.jpg, 240 px).
// Yalnız ekrana gelen hücre kapağını çözer; çözülen kapak bellekte küçük bir önbellekte durur.
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias Resim = UIImage
#else
import AppKit
typealias Resim = NSImage
#endif

enum KapakDeposu {
    nonisolated(unsafe) private static let onbellek: NSCache<NSString, Resim> = {
        let c = NSCache<NSString, Resim>()
        c.countLimit = 40
        return c
    }()

    static func resim(_ id: String) -> Resim? {
        if let r = onbellek.object(forKey: id as NSString) { return r }
        guard let u = adres(id), let r = Resim(contentsOfFile: u.path) else { return nil }
        onbellek.setObject(r, forKey: id as NSString)
        return r
    }

    /// Uygulama paketinde; sınama ve önizlemede TEORIA_KAPAK klasöründe.
    static func adres(_ id: String) -> URL? {
        if let u = Bundle.main.url(forResource: "kapak-\(id)", withExtension: "jpg") { return u }
        guard let k = ProcessInfo.processInfo.environment["TEORIA_KAPAK"] else { return nil }
        let u = URL(fileURLWithPath: k).appendingPathComponent("kapak-\(id).jpg")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

/// Kitap kapağı (2:3) — Tezgâh uygulamasındaki İdrak raflarıyla aynı görünüm: düz yuvarlak köşe, ince kenar,
/// yumuşak tek gölge. Gerçek kapak yoksa kitabın rengiyle yazılı kapak (başlık üstte, altta kısa beyaz çizgi).
/// `egim` eski rafın üç boyutlu duruşuydu; artık yok sayılır (çağıranlar bozulmasın diye durur).
struct KitapKapagi: View {
    let id: String
    let baslik: String
    var genislik: CGFloat = 96
    var egim: Double = 0
    @State private var resim: Resim?
    @State private var yuklendi = false

    private var kose: CGFloat { max(4, genislik * 0.1) }

    var body: some View {
        let r = Tema.renk(Tema.renkAdi(id))
        let sekil = RoundedRectangle(cornerRadius: kose, style: .continuous)
        yuz(r)
            .frame(width: genislik, height: genislik * 1.5)
            .clipShape(sekil)
            .overlay(sekil.strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: max(1.5, genislik * 0.05), y: max(1, genislik * 0.032))
            .onAppear {
                guard !yuklendi else { return }
                yuklendi = true
                resim = KapakDeposu.resim(id)
            }
            .accessibilityLabel("\(baslik) kapağı")
    }

    @ViewBuilder
    private func yuz(_ r: Color) -> some View {
        if let resim {
            #if canImport(UIKit)
            Image(uiImage: resim).resizable().scaledToFill()
            #else
            Image(nsImage: resim).resizable().scaledToFill()
            #endif
        } else {
            ZStack {
                LinearGradient(colors: [r.opacity(0.95), r.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading) {
                    Text(kisaBaslik)
                        .font(.system(size: max(8, genislik * 0.11), weight: .bold, design: .serif))
                        .foregroundStyle(.white).lineLimit(5).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Rectangle().fill(.white.opacity(0.5)).frame(width: max(8, genislik * 0.16), height: 2)
                }
                .padding(max(4, genislik * 0.07))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// "2026-09-24-H01-G08 — Duhem-Quine…" gibi başlıklardan ders kodunu at.
    private var kisaBaslik: String { baslik.kodsuz }
}

extension String {
    /// "H01-G08 — Duhem-Quine ve Gerçekçilik" → "Duhem-Quine ve Gerçekçilik".
    /// Yalnız ders kodunu atar; "Zamanın Fiyatı — Para, Risk…" gibi alt başlıkta asıl ad kalır.
    var kodsuz: String {
        guard let r = range(of: " — ") else { return self }
        let bas = self[..<r.lowerBound]
        if bas.count <= 16, bas.contains(where: \.isNumber) { return String(self[r.upperBound...]) }
        return String(bas)
    }
}

// MARK: - Giriş animasyonu

/// Satır ilk kez ekrana gelince alttan kayarak ve solarak belirir. "Hareketi azalt" açıksa yalnız solar.
struct Belirme: ViewModifier {
    var sira: Int
    var etkin: Bool
    @Environment(\.accessibilityReduceMotion) private var azalt
    @State private var gorundu = false

    func body(content: Content) -> some View {
        content
            .opacity(gorundu || !etkin ? 1 : 0)
            .offset(y: gorundu || !etkin || azalt ? 0 : 22)
            .onAppear {
                guard etkin, !gorundu else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(min(sira, 8)) * 0.045)) { gorundu = true }
            }
    }
}

extension View {
    func belirme(_ sira: Int, etkin: Bool = true) -> some View { modifier(Belirme(sira: sira, etkin: etkin)) }
}
