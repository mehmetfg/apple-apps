import SwiftUI

/// Küçük etiket: gramer yapısı, kelime türü.
struct Cip: View {
    var metin: String
    var renk: Color = Tema.vurgu
    var simge: String?
    var body: some View {
        HStack(spacing: 4) {
            if let simge { Image(systemName: simge).font(.caption2.weight(.semibold)) }
            Text(metin).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(renk)
        .background(Capsule().fill(renk.opacity(0.13)))
    }
}

/// Adım halkası: dolu = yapıldı. Sayı varsa ortada yazar (dinleme 2×).
struct AdimHalkasi: View {
    var dolu: Double          // 0…1
    var renk: Color
    var simge: String
    var sayi: Int? = nil
    var body: some View {
        ZStack {
            Circle().stroke(renk.opacity(0.16), lineWidth: 5)
            Circle().trim(from: 0, to: dolu).stroke(renk, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: dolu)
            if let sayi, sayi > 0 {
                Text("\(sayi)×").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(renk)
            } else {
                Image(systemName: dolu >= 1 ? "checkmark" : simge).font(.system(size: 17, weight: .semibold)).foregroundStyle(renk)
            }
        }
        .frame(width: 46, height: 46)
    }
}

/// Kayıt sırasında canlı ses dalgası.
struct Dalga: View {
    var seviyeler: [Float]
    var renk: Color = Tema.vurgu
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(seviyeler.suffix(48).enumerated()), id: \.offset) { _, s in
                Capsule().fill(renk.gradient).frame(width: 4, height: max(4, CGFloat(s) * 54))
            }
        }
        .frame(height: 58)
        .animation(.easeOut(duration: 0.08), value: seviyeler.count)
    }
}

/// Bölüm işaretli ilerleme çubuğu (açıklama · metin · kelimeler).
struct BolumCubugu: View {
    var paket: Paket
    var zaman: Double
    var sure: Double
    var git: (Double) -> Void
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 3) {
                    ForEach(paket.bolumler ?? []) { b in
                        let oran = sure > 0 ? (b.bitis - b.baslangic) / sure : 0
                        RoundedRectangle(cornerRadius: 3).fill(Tema.bolumRengi(b.ad).opacity(0.22))
                            .frame(width: max(4, w * oran - 3))
                    }
                }
                HStack(spacing: 3) {
                    ForEach(paket.bolumler ?? []) { b in
                        let oran = sure > 0 ? (b.bitis - b.baslangic) / sure : 0
                        let ic = min(1, max(0, (zaman - b.baslangic) / max(b.bitis - b.baslangic, 0.1)))
                        RoundedRectangle(cornerRadius: 3).fill(Tema.bolumRengi(b.ad))
                            .frame(width: max(0, (w * oran - 3) * ic))
                            .frame(width: max(4, w * oran - 3), alignment: .leading)
                    }
                }
            }
            .frame(height: 8)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { e in
                git(max(0, min(1, e.location.x / w)) * sure)
            })
        }
        .frame(height: 8)
    }
}

/// Boş durum: sakin, suçlamayan.
struct BosDurum: View {
    var simge: String
    var baslik: String
    var metin: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: simge).font(.system(size: 40, weight: .light)).foregroundStyle(Tema.vurgu.gradient)
            Text(baslik).font(.title3.weight(.semibold))
            Text(metin).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Dokunsal geri bildirim yalnız ayar açıksa.
extension View {
    func dokun<T: Equatable>(_ depo: Depo, _ deger: T, _ tur: SensoryFeedback = .impact(weight: .light)) -> some View {
        sensoryFeedback(tur, trigger: deger) { _, _ in depo.haptik }
    }
}
