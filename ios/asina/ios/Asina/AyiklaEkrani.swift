// Hızlı ayıklama: 20'lik deste, sağa = biliyorum (depodan düşer), sola = bilmiyorum (sırada kalır).
// Lingvist'in ilk dakikalardaki seviye taraması ve Cümle Tezgâhı'nın Kelime Deposu ile aynı fikir:
// depo 2.614 kelime ama bunların bir kısmını zaten biliyorsun; onlara günlük yuva harcanmasın.
import SwiftUI

struct AyiklaEkrani: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    @State private var deste: [Kelime] = []
    @State private var gecmis: [(Kelime, Bool)] = []
    @State private var surukle: CGSize = .zero
    @State private var anlam = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { kapat() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(R.ikincil)
                        .frame(width: 36, height: 36)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("Ayıkla").font(.headline)
                    Text("\(depo.depoKalan.formatted()) kelime sırada").font(.caption).foregroundStyle(R.soluk)
                }
                Spacer()
                Button { geriAl() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.body.weight(.semibold))
                        .foregroundStyle(gecmis.isEmpty ? R.soluk : R.murekkep)
                        .frame(width: 36, height: 36)
                }
                .disabled(gecmis.isEmpty)
            }
            .padding(.horizontal, 16).padding(.top, 8)

            ZStack {
                if deste.isEmpty {
                    ozet
                } else {
                    ForEach(Array(deste.prefix(3).enumerated().reversed()), id: \.element.i) { i, k in
                        kart(k, ust: i == 0)
                            .offset(y: CGFloat(i) * 10)
                            .scaleEffect(1 - CGFloat(i) * 0.04)
                            .zIndex(Double(3 - i))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 22)

            if !deste.isEmpty {
                HStack(spacing: 18) {
                    yuvarlak("xmark", "Bilmiyorum", R.yanlis) { karar(false) }
                    yuvarlak("checkmark", "Biliyorum", R.dogru) { karar(true) }
                }
                .padding(.bottom, 24)
            }
        }
        .background(R.zemin.ignoresSafeArea())
        .onAppear { if deste.isEmpty { deste = depo.ayiklamaDestesi() } }
        .sensoryFeedback(.impact(weight: .medium), trigger: gecmis.count)
    }

    private func kart(_ k: Kelime, ust: Bool) -> some View {
        let x = ust ? surukle.width : 0
        return VStack(spacing: 14) {
            HStack {
                BantRozeti(bant: k.c)
                Text(k.turAdi).font(.caption).italic().foregroundStyle(R.soluk)
                Spacer()
                if ust { SesDugmesi(kelime: k, boyut: 36) }
            }
            Spacer()
            Text(k.w).font(.kelime(46)).foregroundStyle(R.murekkep).minimumScaleFactor(0.4).lineLimit(1)
            Text(k.ipa).foregroundStyle(R.soluk)
            Spacer()
            Group {
                if anlam && ust {
                    VStack(spacing: 6) {
                        Text(k.tr).font(.title3.weight(.semibold)).foregroundStyle(R.vurgu)
                        if let c = k.ilkCumle {
                            Text(Vurgu.metin(c, k.w, renk: R.murekkep)).font(.kelime(14, .regular))
                                .foregroundStyle(R.ikincil).multilineTextAlignment(.center).lineLimit(3)
                        }
                    }
                    .transition(.opacity)
                } else {
                    Text("Emin değilsen dokun — anlamını gör").font(.footnote).foregroundStyle(R.soluk)
                }
            }
            .frame(minHeight: 80)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .frame(height: 420)
        .background(R.yuzey, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(x > 40 ? R.dogru : x < -40 ? R.yanlis : R.cizgi, lineWidth: abs(x) > 40 ? 3 : 1)
        )
        .overlay(alignment: .top) {
            if ust && abs(x) > 40 {
                Text(x > 0 ? "BİLİYORUM" : "BİLMİYORUM")
                    .font(.headline.weight(.heavy)).tracking(1)
                    .foregroundStyle(x > 0 ? R.dogru : R.yanlis)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(Capsule().stroke(x > 0 ? R.dogru : R.yanlis, lineWidth: 2))
                    .rotationEffect(.degrees(x > 0 ? -8 : 8))
                    .padding(.top, 70)
            }
        }
        .shadow(color: .black.opacity(ust ? 0.08 : 0.03), radius: 18, y: 10)
        .offset(x: x, y: ust ? surukle.height * 0.2 : 0)
        .rotationEffect(.degrees(Double(x) / 22))
        .onTapGesture { if ust { withAnimation(.easeOut(duration: 0.2)) { anlam.toggle() } } }
        .gesture(ust ? DragGesture()
            .onChanged { surukle = $0.translation }
            .onEnded { d in
                if abs(d.translation.width) > 110 { karar(d.translation.width > 0) }
                else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { surukle = .zero } }
            } : nil)
    }

    private func karar(_ biliyor: Bool) {
        guard let k = deste.first else { return }
        withAnimation(.easeIn(duration: 0.22)) { surukle = CGSize(width: biliyor ? 600 : -600, height: 40) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            depo.ayikla(k, biliyor: biliyor)
            gecmis.append((k, biliyor))
            deste.removeFirst()
            surukle = .zero
            anlam = false
        }
    }

    private func geriAl() {
        guard let (k, _) = gecmis.popLast() else { return }
        depo.ayiklamaGeriAl(k)
        withAnimation(.spring) { deste.insert(k, at: 0) }
    }

    private var ozet: some View {
        let bil = gecmis.filter { $0.1 }.count
        return VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(R.vurgu)
            Text("Deste bitti").font(.title2.weight(.bold))
            Text("\(bil) kelimeyi biliyordun, depodan düştü.\n\(gecmis.count - bil) kelime sırada bekliyor.")
                .multilineTextAlignment(.center).foregroundStyle(R.ikincil)
            AnaDugme(baslik: "20 kelime daha", simge: "rectangle.stack") {
                gecmis = []
                withAnimation(.spring) { deste = depo.ayiklamaDestesi() }
            }
            .padding(.top, 10)
            Button("Kapat") { kapat() }.foregroundStyle(R.ikincil)
        }
        .padding(30)
    }

    private func yuvarlak(_ simge: String, _ ad: String, _ renk: Color, _ e: @escaping () -> Void) -> some View {
        Button(action: e) {
            VStack(spacing: 6) {
                Image(systemName: simge).font(.system(size: 26, weight: .bold)).foregroundStyle(renk)
                    .frame(width: 72, height: 72)
                    .background(R.yuzey, in: Circle())
                    .overlay(Circle().stroke(renk.opacity(0.35), lineWidth: 1.5))
                    .shadow(color: renk.opacity(0.18), radius: 10, y: 4)
                Text(ad).font(.caption.weight(.semibold)).foregroundStyle(R.ikincil)
            }
        }
        .buttonStyle(Bas())
        .frame(maxWidth: .infinity)
    }
}
