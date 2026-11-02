// Uygulama içi ada: kayıt sürerken ekranın tepesinde Dynamic Island'ın küçük ve açık hâlinin aynısı.
// Adalı telefonda gerçek adanın yerine oturur (uygulama öndeyken sistem kendi Canlı Etkinliğini adada göstermez).
// Adasız telefonda (13 Pro Max) çentiğin altından sarkar; durum çubuğundaki saat ve pille çakışmasın diye çentiğin yanına taşmaz.
// Dokun → açılır; dışına dokun ya da yukarı it → kapanır. Kayıt başlarken bir an kendiliğinden açılır, bitince "Kaydedildi" der.
import SwiftUI
import UIKit

/// Adanın penceresi: durum çubuğu seviyesinde, saydam. Dokunuşları yalnız adanın kapladığı alanda tutar (açıkken tüm
/// ekranda — dışına dokununca kapanır); gerisi alttaki uygulamaya geçer.
final class AdaPenceresi: UIWindow {
    /// Adanın ekrandaki alanı (SwiftUI bildirir); boşsa pencere hiç dokunuş almaz.
    static var etkinAlan: CGRect = .zero
    static var tumEkran = false

    static func kur(_ ws: UIWindowScene) -> AdaPenceresi {
        let p = AdaPenceresi(windowScene: ws)
        let h = UIHostingController(rootView: UygulamaAdasi()
            .environmentObject(KayitMerkezi.shared).environmentObject(TelefonDeposu.shared))
        h.view.backgroundColor = .clear
        p.rootViewController = h
        p.windowLevel = .statusBar
        p.backgroundColor = .clear
        p.isHidden = false
        return p
    }

    override func hitTest(_ nokta: CGPoint, with olay: UIEvent?) -> UIView? {
        guard AdaPenceresi.tumEkran || AdaPenceresi.etkinAlan.insetBy(dx: -8, dy: -8).contains(nokta) else { return nil }
        return super.hitTest(nokta, with: olay)
    }
}

struct UygulamaAdasi: View {
    @EnvironmentObject var merkez: KayitMerkezi
    @State private var acik = false
    @State private var bitis: KayitMerkezi.Bitis?
    @State private var kapatGorevi: Task<Void, Never>?

    /// Gerçek adanın çerçevesi (iPhone 14 Pro ve sonrası); adasız telefonda nil.
    private var adaCercevesi: CGRect? {
        guard let w = pencere, w.safeAreaInsets.top >= 51 else { return nil }
        return CGRect(x: (w.bounds.width - 126) / 2, y: 11, width: 126, height: 37)
    }

    private var durum: KayitEtkinligi.ContentState {
        KayitEtkinligi.ContentState(baslangic: Date(), bitti: bitis != nil, duraklama: merkez.duraklatildi ? Date() : nil)
    }

    private var pencere: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    var body: some View {
        // GeometryReader kullanılmaz: içi ilk çizimde takılı kalıp kayıt durumunu görmüyordu (2026-10-30 sınaması)
        let gorunur = merkez.kayitta || bitis != nil
        let ada = adaCercevesi
        let genislik = pencere?.bounds.width ?? 390
        // adalıda saat ve pil simgelerine binmesin diye gerçek adanın ancak iki yanına taşar (sistem adası onları iter, biz itemeyiz)
        let kucukBoy = ada.map { CGSize(width: $0.width + 78, height: $0.height) } ?? CGSize(width: 150, height: 34)
        // adasızda: küçükken çentiğin altından (≈30 pt) sarkar; açıkken çentikle birleşip en tepeden aşağı uzar
        let ust: CGFloat = ada?.minY ?? (acik ? 0 : 30)
        let kose: CGFloat = acik ? 40 : kucukBoy.height / 2
        ZStack(alignment: .top) {
            if acik {
                Color.black.opacity(0.001).onTapGesture { kapat() }
            }
            if gorunur {
                VStack(spacing: 0) {
                    if acik { acikIcerik.padding(.horizontal, 18).padding(.top, ada == nil ? 40 : 16).padding(.bottom, 16) }
                    else {
                        Button { ac(sure: nil) } label: {
                            kucukIcerik(ada != nil).frame(width: kucukBoy.width, height: kucukBoy.height).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kayıt adasını aç")
                    }
                }
                .frame(width: acik ? genislik - 20 : kucukBoy.width)
                .background { RoundedRectangle(cornerRadius: kose, style: .continuous).fill(.black) }
                .clipShape(RoundedRectangle(cornerRadius: kose, style: .continuous))
                .shadow(color: .black.opacity(acik ? 0.3 : 0), radius: 18, y: 8)
                .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { g in
                    if g.translation.height < -15 { kapat() } else if g.translation.height > 15 { ac(sure: nil) }
                })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { AdaPenceresi.etkinAlan = $0 }
                .padding(.top, ust)
                .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: acik)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: gorunur)
        .animation(.easeInOut(duration: 0.2), value: merkez.duraklatildi)
        .onChange(of: merkez.kayitta) { _, k in
            if k { bitis = nil; ac(sure: 2.5) }      // başlarken gerçek ada gibi bir an açılır
        }
        .onChange(of: merkez.sonBitis) { _, b in
            guard let b else { return }
            acik = false; bitis = b
            kapatGorevi?.cancel()
            kapatGorevi = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { bitis = nil } }
        }
        .onChange(of: gorunur) { _, g in if !g { AdaPenceresi.etkinAlan = .zero } }
        .onChange(of: acik) { _, a in AdaPenceresi.tumEkran = a }
    }

    private func ac(sure: Double?) {
        guard merkez.kayitta else { return }
        acik = true
        kapatGorevi?.cancel()
        guard let sure else { return }
        kapatGorevi = Task { try? await Task.sleep(for: .seconds(sure)); if !Task.isCancelled { acik = false } }
    }

    private func kapat() { kapatGorevi?.cancel(); acik = false }

    // MARK: Küçük hâl: solda durum simgesi, sağda sayaç (adalıda kameranın iki yanı, adasızda çentiğin altı)

    @ViewBuilder private func kucukIcerik(_ adali: Bool) -> some View {
        let renk = etkinlikRengi(durum)
        HStack(spacing: 6) {
            Image(systemName: bitis != nil ? "checkmark" : (merkez.duraklatildi ? "pause.fill" : "waveform"))
                .font(.system(size: 14, weight: .bold)).foregroundStyle(renk)
                .symbolEffect(.variableColor.iterative, isActive: merkez.kayitta && !merkez.duraklatildi)
            if adali { Spacer(minLength: 0) }
            else if bitis == nil {
                Dalga(seviyeler: merkez.seviyeler.map(Double.init), duraklatildi: merkez.duraklatildi, adet: 8)
                    .frame(width: 34, height: 14)
            }
            Text(Zaman.sure(bitis?.sure ?? merkez.sure))
                .font(.system(adali ? .caption : .subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(renk).contentTransition(.numericText())
        }
        .padding(.horizontal, adali ? 10 : 14)
    }

    // MARK: Açık hâl: Canlı Etkinliğin genişletilmiş adasıyla aynı düzen

    private var acikIcerik: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Kure(d: durum, boy: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(durumYazisi(durum)).font(.caption.weight(.bold)).foregroundStyle(etkinlikRengi(durum))
                    Text("Kıvılcım").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Text(Zaman.sure(merkez.sure))
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).contentTransition(.numericText())
            }
            Dalga(seviyeler: merkez.seviyeler.map(Double.init), duraklatildi: merkez.duraklatildi, adet: 28).frame(height: 22)
            HStack(spacing: 10) {
                Button { Task { await merkez.vazgec() } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .frame(width: 44, height: 44).background { DugmeZemini() }
                }
                .accessibilityLabel("Vazgeç")
                Button { Task { await merkez.duraklatDegistir() } } label: {
                    Label(merkez.duraklatildi ? "Devam" : "Duraklat", systemImage: merkez.duraklatildi ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44).background { DugmeZemini() }
                }
                Button { Task { await merkez.bitir() } } label: {
                    Label("Bitir", systemImage: "stop.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44).background { DugmeZemini(renk: .kivilcim) }
                }
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }
}
