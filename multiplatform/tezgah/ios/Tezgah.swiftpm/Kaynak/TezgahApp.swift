// Tezgâh — iPhone okuyucusu. Salt okunur: Mac'teki tezgâhların iCloud'a düşen özetini gösterir.
import SwiftUI

#if os(iOS)
@main
struct TezgahApp: App {
    @StateObject private var depo = VeriDeposu()
    @Environment(\.scenePhase) private var faz

    var body: some Scene {
        WindowGroup {
            Kok()
                .environmentObject(depo)
                .task { await depo.yukle() }
                .onChange(of: faz) { _, yeni in
                    if yeni == .active { Task { await depo.yukle() } }
                }
        }
    }
}
#endif

/// Otomatik = telefonun ayarı; Gece = her zaman koyu.
enum Gorunum: String, CaseIterable, Identifiable {
    case oto, acik, gece
    var id: String { rawValue }
    var ad: String { self == .oto ? "Otomatik" : self == .acik ? "Açık" : "Gece" }
    var sema: ColorScheme? { self == .oto ? nil : self == .acik ? .light : .dark }
}

enum Sekme: String, CaseIterable, Identifiable {
    case bugun, ingilizce, idrak, vault
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .bugun: return "Bugün"
        case .ingilizce: return "İngilizce"
        case .idrak: return "İdrak"
        case .vault: return "Vault"
        }
    }
    var simge: String {
        switch self {
        case .bugun: return "sun.max.fill"
        case .ingilizce: return "text.quote"
        case .idrak: return "books.vertical.fill"
        case .vault: return "square.stack.3d.up.fill"
        }
    }
    var renk: Color {
        switch self {
        case .bugun: return T.murekkep
        case .ingilizce: return T.cumle
        case .idrak: return T.idrak
        case .vault: return T.vault
        }
    }
}

struct Kok: View {
    @EnvironmentObject var depo: VeriDeposu
    @State private var sekme: Sekme = .bugun
    @AppStorage("gorunum") private var gorunum = Gorunum.oto.rawValue

    var body: some View {
        Group {
            switch depo.durum {
            case .kurulmadi:
                Kurulum()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .yukleniyor where depo.veri == nil:
                Yukleniyor()
            case .hata(let m) where depo.veri == nil:
                YuklemeHatasi(mesaj: m)
            default:
                TabView(selection: $sekme) {
                    ForEach(Sekme.allCases) { s in
                        NavigationStack { ekran(s) }
                            .tabItem { Label(s.ad, systemImage: s.simge) }
                            .tag(s)
                    }
                }
                .tint(sekme.renk)
                .transition(.opacity)
            }
        }
        .animation(T.yay, value: depo.durum)
        .environment(\.locale, Bicim.tr)  // grafik tarihleri ve sayılar Türkçe
        .preferredColorScheme(Gorunum(rawValue: gorunum)?.sema)
        .environment(\.sekmeyeGit, { s in withAnimation(T.yay) { sekme = s } })
    }

    @ViewBuilder
    func ekran(_ s: Sekme) -> some View {
        switch s {
        case .bugun: BugunEkrani()
        case .ingilizce: IngilizceEkrani()
        case .idrak: IdrakEkrani()
        case .vault: VaultEkrani()
        }
    }
}

private struct SekmeyeGitAnahtar: EnvironmentKey {
    static let defaultValue: (Sekme) -> Void = { _ in }
}

extension EnvironmentValues {
    var sekmeyeGit: (Sekme) -> Void {
        get { self[SekmeyeGitAnahtar.self] }
        set { self[SekmeyeGitAnahtar.self] = newValue }
    }
}

/// Her ekranın ortak kabuğu: zemin rengi, aşağı çekip yenileme, sağ üstte ayarlar.
struct Ekran<Icerik: View>: View {
    @EnvironmentObject var depo: VeriDeposu
    @ViewBuilder var icerik: () -> Icerik
    @State private var ayarlar = false
    @AppStorage("gorunum") private var gorunum = Gorunum.oto.rawValue
    @Environment(\.colorScheme) private var sema

    @Environment(\.statik) private var statik

    var body: some View {
        if statik {  // Mac'teki ön izleme: kaydırma kabuğu olmadan bütün sayfa
            govde.background(T.zemin)
        } else {
            kabuk
        }
    }

    var govde: some View {
        VStack(alignment: .leading, spacing: 14) {
            icerik()
            Guncellik().padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    var kabuk: some View {
        ScrollView {
            govde.overlay(alignment: .topTrailing) {  // gece düğmesi + ayarlar başlıkla birlikte kayar
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            gorunum = (sema == .dark ? Gorunum.acik : Gorunum.gece).rawValue
                        }
                    } label: {
                        Image(systemName: sema == .dark ? "sun.max.fill" : "moon.stars.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(sema == .dark ? Color.hex(0xF5C04A) : T.vault)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 20, height: 20)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: gorunum)
                    Button { ayarlar = true } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                            .foregroundStyle(T.yumusak)
                            .frame(width: 20, height: 20)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 4)
            }
        }
        .background(T.zemin.ignoresSafeArea())
        .refreshable { await depo.yukle() }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .overlay(alignment: .top) {  // saat çubuğunun altında içerik yumuşakça kaybolur
            GeometryReader { g in
                LinearGradient(colors: [T.zemin, T.zemin.opacity(0.9), T.zemin.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: g.safeAreaInsets.top + 16)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $ayarlar) { Ayarlar() }
    }
}

/// "Son güncelleme" satırı; Mac bir günden uzun süredir yazmadıysa uyarır.
struct Guncellik: View {
    @EnvironmentObject var depo: VeriDeposu
    var body: some View {
        let v = depo.veri
        let tarih = Bicim.zaman(v?.uretildi)
        let eski = tarih.map { Date().timeIntervalSince($0) > 36 * 3600 } ?? false
        VStack(spacing: 4) {
            if eski {
                Label("Mac \(Bicim.once(v?.uretildi)) yazdı — Mac açılınca tazelenir", systemImage: "clock.badge.exclamationmark")
                    .font(.caption.weight(.medium)).foregroundStyle(T.idrak)
            }
            Text("Mac'te üretildi \(Bicim.saat(v?.uretildi))" + ((v?.makine).map { $0.isEmpty ? "" : " · \($0)" } ?? ""))
                .font(.caption2).foregroundStyle(T.soluk)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Yukleniyor: View {
    @State private var don = false
    var body: some View {
        VStack(spacing: 16) {
            TezgahIsareti(boy: 84).rotationEffect(.degrees(don ? 4 : -4))
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: don)
            Text("iCloud'dan okunuyor…").font(.callout).foregroundStyle(T.yumusak)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.zemin.ignoresSafeArea())
        .onAppear { don = true }
    }
}

struct YuklemeHatasi: View {
    @EnvironmentObject var depo: VeriDeposu
    let mesaj: String
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "icloud.slash").font(.system(size: 44)).foregroundStyle(T.idrak)
            Text("Veri okunamadı").font(.title2.bold())
            Text(mesaj).font(.callout).foregroundStyle(T.yumusak).multilineTextAlignment(.center)
            HStack {
                Button("Yeniden dene") { Task { await depo.yukle() } }.buttonStyle(.borderedProminent)
                Button("Klasörü değiştir") { depo.klasoruUnut() }.buttonStyle(.bordered)
            }
            .tint(T.cumle)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.zemin.ignoresSafeArea())
    }
}

/// Uygulama ikonundaki tezgâh (mavi/siyah ikonla aynı renkler): tabla, iki ayak, üç blok.
struct TezgahIsareti: View {
    var boy: CGFloat = 120
    @State private var kalk = false
    @Environment(\.statik) private var statik

    var body: some View {
        let s = boy / 100
        let kalk = self.kalk || statik
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 6 * s) {
                blok(Color.hex(0x38BDF8), 18 * s, 26 * s, 0)
                blok(Color.hex(0x2563EB), 18 * s, 38 * s, 1)
                blok(Color.hex(0x93C5FD), 18 * s, 31 * s, 2)
            }
            .padding(.bottom, 26 * s)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4 * s).fill(Color.hex(0x3B82F6)).frame(width: 82 * s, height: 10 * s)
                HStack {
                    RoundedRectangle(cornerRadius: 2 * s).fill(Color.hex(0x1E3A8A)).frame(width: 8 * s, height: 16 * s)
                    Spacer()
                    RoundedRectangle(cornerRadius: 2 * s).fill(Color.hex(0x1E3A8A)).frame(width: 8 * s, height: 16 * s)
                }
                .frame(width: 66 * s)
            }
        }
        .frame(width: boy, height: boy)
        .onAppear { self.kalk = true }
        .environment(\.kalk, kalk)
    }

    func blok(_ c: Color, _ w: CGFloat, _ h: CGFloat, _ i: Int) -> some View {
        BlokParca(renk: c, en: w, boy: h, sira: i)
    }
}

private struct KalkAnahtar: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    fileprivate var kalk: Bool {
        get { self[KalkAnahtar.self] }
        set { self[KalkAnahtar.self] = newValue }
    }
}

private struct BlokParca: View {
    let renk: Color
    let en: CGFloat
    let boy: CGFloat
    let sira: Int
    @Environment(\.kalk) private var kalk
    var body: some View {
        RoundedRectangle(cornerRadius: en * 0.22, style: .continuous)
            .fill(renk)
            .frame(width: en, height: kalk ? boy : 2)
            .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15 + Double(sira) * 0.12), value: kalk)
    }
}

struct Ayarlar: View {
    @EnvironmentObject var depo: VeriDeposu
    @AppStorage("gorunum") private var gorunum = Gorunum.oto.rawValue
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Görünüm", selection: $gorunum.animation(.easeInOut(duration: 0.35))) {
                        ForEach(Gorunum.allCases) { Text($0.ad).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Görünüm") } footer: {
                    Text("Otomatik telefonun açık/koyu ayarını izler; Gece her zaman koyu.")
                }
                Section("Kaynak") {
                    LabeledContent("Klasör", value: depo.klasorAdi ?? "—")
                    LabeledContent("Mac'te üretildi", value: Bicim.saat(depo.veri?.uretildi))
                    if let s = depo.veri?.son_calisma, !s.isEmpty {
                        LabeledContent("Son tezgâh çalışması", value: Bicim.saat(s))
                    }
                    Button("Şimdi yeniden oku") { Task { await depo.yukle(); kapat() } }
                    Button("Klasörü değiştir", role: .destructive) { depo.klasoruUnut(); kapat() }
                }
                Section("Nasıl çalışır") {
                    Text("Uygulama yalnız okur. Mac'teki pano her çalıştığında (sabah görevleri, Tezgâh.app açıkken 20 dakikada bir) vault'taki Artifacts/_ortak/ios/tezgah.json dosyasını yeniler; iCloud onu buraya taşır. Mac kapalıyken son yazılan anı görürsün.")
                        .font(.footnote).foregroundStyle(T.yumusak)
                }
            }
            .navigationTitle("Ayarlar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { kapat() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
