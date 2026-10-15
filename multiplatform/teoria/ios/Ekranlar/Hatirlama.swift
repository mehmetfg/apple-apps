// Hatırlama — yeniden üretim yüzeyleri.
// İlke: yazarken ya da konuşurken asıl metin önünde durmaz. Önce zihinden çağır, sonra istersen bak.
// Perde açıldıysa olay `deger: true` (bakıldı) ile yazılır; bu bir puan değil, değerlendirmenin ham verisidir.
import SwiftUI

/// Asıl metnin üstüne çekilebilen buzlu perde. Kullanıcı isterse "Buzlandır"a basar; kendiliğinden kapanmaz.
/// "İpucu" ilk birkaç kelimeyi verir, "Göster" metni açar. `kilitli` iken (ses kaydı sürerken) açılamaz.
struct HatirlamaPerdesi<Icerik: View>: View {
    @Binding var acik: Bool
    @Binding var bakti: Bool
    var kilitli = false
    var ipucu: String? = nil
    @ViewBuilder var icerik: Icerik
    @State private var ipucuAcik = false

    private var gorunur: Bool { acik && !kilitli }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            icerik
                .redacted(reason: gorunur ? [] : .placeholder)   // bulanıklık çizilemese de metin okunmaz
                .blur(radius: gorunur ? 0 : 10)
                .opacity(gorunur ? 1 : 0.5)
                .allowsHitTesting(gorunur)
                .accessibilityHidden(!gorunur)
                .overlay { if !gorunur { etiket.transition(.opacity) } }
                .animation(.snappy(duration: 0.35), value: gorunur)
            HStack(spacing: 10) {
                if let ipucu, !gorunur, !ipucu.isEmpty {
                    Button {
                        withAnimation(.snappy) { ipucuAcik.toggle() }
                        Dokunus.secim()
                    } label: {
                        Label(ipucuAcik ? "“\(ipucu)…”" : "İpucu", systemImage: "lightbulb")
                            .lineLimit(1)
                    }
                    .buttonStyle(PerdeDugmesi())
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { acik.toggle() }
                    if acik { bakti = true }
                    Dokunus.secim()
                } label: {
                    Label(gorunur ? "Buzlandır" : "Göster", systemImage: gorunur ? "eye.slash" : "eye")
                }
                .buttonStyle(PerdeDugmesi(vurgulu: !gorunur))
                .disabled(kilitli)
                #if os(macOS)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help("Asıl metni göster/kapat (⇧⌘G)")
                #endif
            }
        }
        .onChange(of: kilitli) { _, k in if k { withAnimation(.snappy) { acik = false } } }
    }

    private var etiket: some View {
        HStack(spacing: 6) {
            Image(systemName: kilitli ? "waveform" : "brain.head.profile").font(.system(size: 12, weight: .semibold))
            Text(kilitli ? "Kayıt sürüyor · zihninden anlat" : "Önce hatırla, sonra bak")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Tema.cizgi.opacity(0.6), lineWidth: 0.5))
        .foregroundStyle(Tema.ikincil)
    }

    /// Metnin ilk birkaç kelimesi — ipucu merdiveninin ilk basamağı.
    static func ilkKelimeler(_ m: String, _ n: Int = 4) -> String {
        m.split(whereSeparator: \.isWhitespace).prefix(n).joined(separator: " ")
    }
}

struct PerdeDugmesi: ButtonStyle {
    var vurgulu = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(vurgulu ? Tema.vurgu.opacity(0.13) : Tema.yuzey2))
            .foregroundStyle(vurgulu ? Tema.vurgu : Tema.ikincil)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Her yeri güncelleyen tek düğme: Mac'te Voice Dream senkronu + akış betiği, iPhone'da vault'tan çekme.
struct GuncelleDugmesi: View {
    @EnvironmentObject var depo: Depo
    var cam = false

    var body: some View {
        Button {
            Dokunus.hafif(0.6)
            Task { await depo.guncelle() }
        } label: {
            ZStack {
                if depo.guncelleniyor {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tema.metin)
                }
            }
            .frame(width: 38, height: 38)
            .background { if cam { Circle().fill(.ultraThinMaterial) } }
            .overlay { if cam { Circle().strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5) } }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(depo.guncelleniyor)
        .accessibilityLabel("Güncelle")
        .help("Voice Dream'den güncelle: yeni işaretler, okuma yüzdesi, yeni metinler")
    }
}

/// Ekranın üstünde kısa, kendiliğinden kaybolan bilgi şeridi (güncelleme özeti, hata).
struct BildirimSeridi: ViewModifier {
    @EnvironmentObject var depo: Depo

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let b = depo.bildirim {
                Label(b, systemImage: b.contains("hata") || b.contains("açılamadı") ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(Tema.cizgi.opacity(0.7), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .foregroundStyle(Tema.metin)
                    .padding(.top, 8).padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { depo.bildirim = nil } }
                    .task(id: b) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        withAnimation(.snappy) { if depo.bildirim == b { depo.bildirim = nil } }
                    }
            }
        }
        .animation(.snappy, value: depo.bildirim)
    }
}

extension View {
    func bildirimSeridi() -> some View { modifier(BildirimSeridi()) }
}

/// Akışta gün değişince araya giren sessiz başlık: "Bugün", "Dün", "5 Ekim Pazar".
struct GunAyraci: View {
    let gun: Date
    var body: some View {
        HStack(spacing: 10) {
            Text(ad).font(.system(size: 12.5, weight: .bold)).tracking(0.5).foregroundStyle(Tema.ikincil).fixedSize()
            Rectangle().fill(Tema.cizgi).frame(height: 0.5)
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
    }

    private var ad: String {
        let t = Tarih.takvim
        if t.isDateInToday(gun) { return "BUGÜN" }
        if t.isDateInYesterday(gun) { return "DÜN" }
        return gun.formatted(.dateTime.day().month(.wide).weekday(.wide).locale(Dil.tr)).uppercased(with: Dil.tr)
    }
}

/// Claude'un genel değerlendirmesi — Benim sekmesinin başında.
struct GenelDegerlendirmeKarti: View {
    let d: GenelDegerlendirme
    @State private var ayrinti = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Tema.vurgu)
                Text("Değerlendirme").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.metin)
                Text("· \(d.tarih)").font(.system(size: 13)).foregroundStyle(Tema.soluk)
                Spacer()
            }
            if let k = d.kapsam { Text(k).font(.system(size: 12.5)).foregroundStyle(Tema.ikincil) }
            Text(d.ozet).font(.system(size: 15.5, design: .serif)).foregroundStyle(Tema.metin).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if let h = d.hatirlama { olcek("Hatırlama", h) }
                if let u = d.uretim { olcek("Yeniden üretim", u) }
            }
            if ayrinti {
                VStack(alignment: .leading, spacing: 10) {
                    liste("Güçlü", d.guclu, "checkmark.circle", Tema.basari)
                    liste("Eksik", d.eksik, "circle.dashed", Tema.uyari)
                    if let o = d.oruntu { liste("Örüntü", [o], "point.3.connected.trianglepath.dotted", Tema.vurgu) }
                    liste("Sıradaki", d.oneri, "arrow.forward.circle", Tema.vurgu)
                }
                .transition(.opacity)
            }
            Button(ayrinti ? "Daha az" : "Ayrıntı") { withAnimation(.snappy) { ayrinti.toggle() } }
                .font(.system(size: 13, weight: .semibold)).buttonStyle(.plain).foregroundStyle(Tema.vurgu)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Tema.vurgu.opacity(0.25), lineWidth: 0.8))
    }

    private func olcek(_ ad: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Text(ad).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Circle().fill(i <= n ? Tema.vurgu : Tema.cizgi).frame(width: 7, height: 7)
                }
            }
        }
    }

    @ViewBuilder
    private func liste(_ baslik: String, _ l: [String]?, _ s: String, _ r: Color) -> some View {
        if let l, !l.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label(baslik, systemImage: s).font(.system(size: 12.5, weight: .bold)).foregroundStyle(r)
                ForEach(l, id: \.self) { m in
                    Text(m).font(.system(size: 14)).foregroundStyle(Tema.metin).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
