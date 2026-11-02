// Canlı Etkinlik ile uygulama içi adanın ortak parçaları: renk, durum yazısı, simge, dalga, düğme zemini.
// Hem uygulamada hem widget uzantısında derlenir; adasız telefonda (13 Pro Max) uygulama içi ada da bunlarla çizilir.
import SwiftUI

func durumYazisi(_ d: KayitEtkinligi.ContentState) -> String {
    d.bitti ? "Kaydedildi" : (d.duraklatildi ? "Duraklatıldı" : "Dinliyor")
}

func etkinlikRengi(_ d: KayitEtkinligi.ContentState) -> Color {
    d.bitti ? Color(hex: "#5FD68A") : (d.duraklatildi ? Color(hex: "#FFC14D") : .kivilcim)
}

/// Durum simgesi: düz renkli daire (halka ve parlama yok).
struct Kure: View {
    let d: KayitEtkinligi.ContentState
    var boy: CGFloat
    var body: some View {
        Image(systemName: d.bitti ? "checkmark" : (d.duraklatildi ? "pause.fill" : "waveform"))
            .font(.system(size: boy * 0.42, weight: .semibold)).foregroundStyle(etkinlikRengi(d))
            .symbolEffect(.variableColor.iterative, isActive: !d.bitti && !d.duraklatildi)
            .frame(width: boy, height: boy)
            .background { Circle().fill(etkinlikRengi(d).opacity(0.2)) }
    }
}

/// Canlı ses dalgası: ortadan iki yana açılan çubuklar; duraklatınca söner.
struct Dalga: View {
    let seviyeler: [Double]
    let duraklatildi: Bool
    var adet = 18
    var body: some View {
        let son = Array(seviyeler.suffix(adet))
        let dolu = Array(repeating: 0.06, count: max(0, adet - son.count)) + son
        GeometryReader { g in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<adet, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: "#FFC29A"), .kivilcim], startPoint: .top, endPoint: .bottom))
                        .opacity(duraklatildi ? 0.3 : 0.5 + dolu[i] * 0.5)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(4, g.size.height * dolu[i]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Düğme zemini: düz dolgu, hafif köşe (sistem düğmeleri gibi); kenar çizgisi ve parlama yok.
struct DugmeZemini: View {
    var renk: Color? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(renk ?? Color.white.opacity(0.16))
    }
}

