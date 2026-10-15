// Görsel dil (GramerApp v2): kâğıt zemin, yumuşak ve kırık renkler. Doygun mavi/kırmızı/mor yok.
// Renk = mekanizma: bir yasa ya da bölge her ekranda aynı tonla görünür. Dolgular bu tonların açık hâli (opaklık),
// yazılar ve çizgiler tonun kendisi — böylece hem pastel kalır hem okunur.
// Başlıklar SF Rounded, İngilizce cümleler New York serif.
import SwiftUI

enum Tema {
    static func renk(_ ad: String) -> Color {
        switch ad {
        case "mavi": Color(red: 0.36, green: 0.50, blue: 0.64)      // sis mavisi
        case "mor": Color(red: 0.50, green: 0.43, blue: 0.68)       // lavanta
        case "turuncu": Color(red: 0.80, green: 0.50, blue: 0.36)   // şeftali
        case "kehribar": Color(red: 0.72, green: 0.56, blue: 0.30)  // kum
        case "yesil": Color(red: 0.40, green: 0.58, blue: 0.46)     // adaçayı
        case "sari": Color(red: 0.58, green: 0.57, blue: 0.33)      // zeytin
        case "kirmizi": Color(red: 0.74, green: 0.43, blue: 0.41)   // gül kurusu
        case "turkuaz": Color(red: 0.31, green: 0.57, blue: 0.56)   // su yeşili
        case "gul": Color(red: 0.72, green: 0.45, blue: 0.56)       // pembe kurusu
        case "indigo": Color(red: 0.42, green: 0.46, blue: 0.63)    // arduvaz
        default: vurgu
        }
    }

    // Fiil motorunun parçaları (Gramer Motoru v2 ile aynı anlam)
    static let zaman = renk("mavi")
    static let modal = renk("mor")
    static let perfect = renk("kehribar")
    static let surec = renk("turkuaz")
    static let edilgen = renk("gul")

    static let dogru = Color(red: 0.36, green: 0.58, blue: 0.44)
    static let yanlis = Color(red: 0.78, green: 0.45, blue: 0.38)   // kiremit, alarm kırmızısı değil
    /// Ana vurgu: mürekkep. Düğmelerde dolgu, üstünde beyaz yazı.
    static let vurgu = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.58, green: 0.57, blue: 0.76, alpha: 1)
        : UIColor(red: 0.31, green: 0.33, blue: 0.46, alpha: 1) })

    static let kagit = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.075, blue: 0.085, alpha: 1)
        : UIColor(red: 0.972, green: 0.962, blue: 0.945, alpha: 1) })
    static let yuzey = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.135, green: 0.135, blue: 0.15, alpha: 1)
        : UIColor(red: 1, green: 0.998, blue: 0.994, alpha: 1) })
    static let cizgi = Color.primary.opacity(0.07)

    static let egim = LinearGradient(colors: [renk("mor").opacity(0.22), renk("turuncu").opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Kalıp yuvasının rengi (veri/kalip.py'nin türleri)
    static func yuva(_ t: String) -> Color {
        switch t {
        case "modal": modal
        case "perfect": perfect
        case "surec": surec
        case "be": edilgen
        case "zaman": zaman
        case "ozne", "isim": renk("yesil")
        case "bag": renk("turuncu")
        case "fiil": renk("indigo")
        default: Color.secondary
        }
    }

    static func ingilizce(_ stil: Font.TextStyle = .body, _ agirlik: Font.Weight = .regular) -> Font {
        .system(stil, design: .serif).weight(agirlik)
    }
    static func baslik(_ stil: Font.TextStyle = .title2) -> Font { .system(stil, design: .rounded).weight(.bold) }

    static func kademeAdi(_ k: Int) -> String {
        ["dokunmadım", "gördüm", "taklit", "üretim", "özerk"][max(0, min(4, k))]
    }
}

extension View {
    /// Kart zemini: kâğıdın üstünde hafif yükselmiş yüzey, ince çizgi.
    func kart(_ ic: CGFloat = 16, yaricap: CGFloat = 22) -> some View {
        self.padding(ic)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: yaricap, style: .continuous).fill(Tema.yuzey)
                    .overlay(RoundedRectangle(cornerRadius: yaricap, style: .continuous).stroke(Tema.cizgi, lineWidth: 1))
                    .shadow(color: .black.opacity(0.035), radius: 6, y: 2)
            )
    }
}

/// Arka plan: kâğıt + çok soluk iki leke. Ekranın tonu o ekranın bağlamından gelir.
struct Lekeler: View {
    var renkler: [Color] = [Tema.renk("mor"), Tema.renk("turuncu")]
    var body: some View {
        GeometryReader { g in
            ZStack {
                Tema.kagit
                ForEach(Array(renkler.prefix(2).enumerated()), id: \.offset) { i, r in
                    Circle().fill(r.opacity(0.09))
                        .frame(width: g.size.width * 0.95)
                        .blur(radius: 80)
                        .offset(x: [-0.4, 0.45][i] * g.size.width, y: [-0.42, 0.38][i] * g.size.height)
                }
            }
        }
        .ignoresSafeArea()
    }
}
