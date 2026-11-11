// Teoria — Mac uygulaması (iş ve ev Mac'i). Aynı çekirdek, masaüstüne göre ayrı düzen:
// üstte sekmeler (⌘1…⌘8), bölüm bütün pencereyi kullanır; klavyeyle üretim Atölye'de (mac/Atolye.swift).
// Menü çubuğunda günün aforizması ve tek tıkla kür. Derleme: zsh mac/derle.sh (Xcode gerekmez).
import SwiftUI
import UserNotifications

final class MacTemsilci: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var rota: ((String) -> Void)?

    /// The whole app (window frame, toolbar, menus, sheets, settings) follows the choice, not only the SwiftUI content.
    static func temayiUygula(_ t: TemaSecimi) {
        NSApp.appearance = switch t {
        case .sistem: nil
        case .acik: NSAppearance(named: .aqua)
        case .koyu: NSAppearance(named: .darkAqua)
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Bildirim.kategorileriKaydet()
        AppUpdater.start()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let rota = Bildirim.eylem(r)
        await MainActor.run {
            NotificationCenter.default.post(name: .init("teoria.kutu"), object: nil)
            if let rota { MacTemsilci.rota?(rota) }
        }
    }
}

/// Üst sekmeler (pencere araç çubuğunun ortasında). Ayarlar ⌘, ile ayrı pencerede.
enum MacBolum: String, CaseIterable, Identifiable, Hashable {
    case sabah, bugun, atolye, kur, akis, kitaplar, mufredat, sozluk, ses, notlar, ikinci
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .sabah: "Sabah"
        case .bugun: "Bugün"
        case .atolye: "Atölye"
        case .kur: "Kür"
        case .akis: "Akış"
        case .kitaplar: "Kütüphane"
        case .mufredat: "Müfredat"
        case .sozluk: "Sözlük"
        case .ses: "Ses"
        case .notlar: "Notlarım"
        case .ikinci: "İkinci dikkat"
        }
    }
    var sembol: String {
        switch self {
        case .sabah: "sunrise"
        case .bugun: "sun.max"
        case .atolye: "pencil.and.outline"
        case .kur: "circle.dashed.inset.filled"
        case .akis: "text.bubble"
        case .kitaplar: "books.vertical"
        case .mufredat: "map"
        case .sozluk: "character.book.closed"
        case .ses: "waveform"
        case .notlar: "square.and.pencil"
        case .ikinci: "eye"
        }
    }
    var kisayol: KeyEquivalent { KeyEquivalent(Character("\(((MacBolum.allCases.firstIndex(of: self) ?? 0) + 1) % 10)")) }
}

@main
struct TeoriaMacApp: App {
    @NSApplicationDelegateAdaptor(MacTemsilci.self) var temsilci
    @StateObject private var depo = Depo()

    var body: some Scene {
        WindowGroup("Teoria", id: "ana") {
            MacKok()
                .environmentObject(depo)
                .preferredColorScheme(depo.tema.sema)
                .tint(Tema.vurgu)
                .environment(\.locale, Dil.tr)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .defaultSize(width: 1480, height: 940)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandMenu("Çalış") {
                Button("Kürü başlat") { NotificationCenter.default.post(name: .init("teoria.rota"), object: "kur") }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Sesli not") { NotificationCenter.default.post(name: .init("teoria.rota"), object: "ses") }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Defter · hızlı not") { NotificationCenter.default.post(name: .init("teoria.rota"), object: "defter") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                ForEach(MacBolum.allCases) { b in
                    Button(b.ad) { NotificationCenter.default.post(name: .init("teoria.rota"), object: "bolum:" + b.rawValue) }
                        .keyboardShortcut(b.kisayol, modifiers: .command)
                }
                Divider()
                Button("Temayı değiştir: Sistem → Açık → Koyu") {
                    let sira = TemaSecimi.allCases
                    let i = sira.firstIndex(of: depo.tema) ?? 0
                    depo.temaHam = sira[(i + 1) % sira.count].rawValue
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Divider()
                Button("Güncelle · Voice Reader + Voice Dream") { Task { await depo.guncelle() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Vault ile eşitle") { Task { await depo.esitleSimdi() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            AyarlarEkrani(kasa: depo.kasa)
                .environmentObject(depo)
                .preferredColorScheme(depo.tema.sema)
                .frame(width: 560, height: 680)
        }

        MenuBarExtra {
            MenuCubugu().environmentObject(depo)
        } label: {
            Image(systemName: depo.durum.bugunDakika >= Double(depo.kurDakika) ? "checkmark.seal" : "sparkle")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Mac penceresi: üstte sekmeler, altında bölüm bütün genişliği kullanır (kenar çubuğu yok).
/// Yalnız seçili bölüm kurulur; öbürleri bellekte tutulmaz.
struct MacKok: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.scenePhase) private var faz
    @State private var bolum: MacBolum = .bugun
    @State private var kurDakika: Int?
    @State private var sesHedef: String??
    @State private var seciliIsaret: Isaret?
    @State private var linkedBook: String?      // teoria://kitap/<id>: the library opens this book
    @AppStorage("defterAcik") private var defterAcik = false
    @State private var defterOdak = 0

    var body: some View {
        Group {
            switch bolum {
            case .sabah:
                MorningView(wide: true)
            case .ikinci:
                AfternoonView(wide: true)
            case .bugun:
                BugunEkrani(kurBaslat: { kurDakika = $0; bolum = .kur }, sesAc: { sesHedef = .some($0) }, genis: true)
            case .atolye:
                AtolyeEkrani()
            case .kur:
                // the new Kür (2026-11-03); the old three-line Kür lives on in Atölye
                DailyQuizView(wide: true) { kurDakika = nil; bolum = .bugun }
                    .id(kurDakika ?? 0)
            case .akis:
                MacAkis(secili: $seciliIsaret, sesAc: { sesHedef = .some($0) })
            case .kitaplar:
                KitaplarEkrani(sesAc: { sesHedef = .some($0) }, openBook: $linkedBook)
            case .mufredat:
                MufredatEkrani(genis: true)
            case .sozluk:
                SozlukEkrani(genis: true)
            case .ses:
                SesListesi(sesAc: { sesHedef = .some($0) })
            case .notlar:
                NotlarimEkrani(genis: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.arka)
        .bildirimSeridi()
        .inspector(isPresented: $defterAcik) {
            DefterPanel(focusRequest: defterOdak)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Text("θ").font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(Tema.vurgu)
                    Halka(oran: min(depo.durum.bugunDakika / Double(max(depo.kurDakika, 1)), 1), renk: Tema.vurgu, kalinlik: 3)
                        .frame(width: 16, height: 16)
                        .help("Bugün \(Int(depo.durum.bugunDakika.rounded())) / \(depo.kurDakika) dk")
                }
            }
            ToolbarItem(placement: .principal) {
                SimgeSecici(secenekler: MacBolum.allCases.map { .init(deger: $0, ad: $0.ad, sembol: $0.sembol) },
                            secili: $bolum, sikisik: true, esit: false)
                    .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Tema", selection: $depo.temaHam) {
                        ForEach(TemaSecimi.allCases) { t in Label(t.ad, systemImage: t.sembol).tag(t.rawValue) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: { Image(systemName: depo.tema.sembol) }
                    .menuIndicator(.hidden)
                    .help("Görünüm: Sistem · Açık · Koyu (⌥⌘T)")
                SyncAware(status: depo.sync) { d in
                    if d.syncing && !d.updating { ProgressView().controlSize(.small) }
                }
                SyncAware(status: depo.sync) { d in
                    Button { Task { await depo.guncelle() } } label: {
                        if d.updating { ProgressView().controlSize(.small) }
                        else { Label("Güncelle", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon) }
                    }
                    .disabled(d.updating)
                }
                .help("Voice Reader ve Voice Dream'den güncelle: yeni kitaplar, işaretler, dinleme yüzdesi (⌘R) · 10 dakikada bir kendiliğinden")
                Button { defterAc() } label: { Label("Defter", systemImage: "note.text") }
                    .help("Defter: her ekrandan hızlı not, ↩ ile kaydet (⇧⌘N)")
                Button { sesHedef = .some(nil) } label: { Label("Sesli not", systemImage: "mic") }
                    .help("Sesli not (⇧⌘R)")
                Button { kurDakika = depo.kurDakika; bolum = .kur } label: { Label("Kür", systemImage: "play.fill") }
                    .help("Kürü başlat (⌘K)")
            }
        }
        .sheet(item: Binding(get: { sesHedef.map { SesHedefiMac(hedef: $0) } }, set: { _ in sesHedef = nil })) { s in
            SesKayitSayfasi(hedef: s.hedef).environmentObject(depo).frame(minWidth: 520, minHeight: 620)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("teoria.rota"))) { n in rota(n.object as? String ?? "") }
        // Links from other apps, the same routes as on the iPhone: teoria://kitap/<id> opens the book,
        // teoria://isaret/<id> shows the highlight, the rest is the host alone (kur · ses · akis · mufredat · ikinci …).
        .onOpenURL { u in
            let h = u.host() ?? ""
            rota(h == "isaret" || h == "kitap" ? h + ":" + u.lastPathComponent : h)
        }
        // the window that is already open takes the link; without this macOS opens a second window for it
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .task { _ = AfternoonStore.shared }   // İkinci dikkat: the list starts refreshing as soon as Teoria opens
        .onReceive(NotificationCenter.default.publisher(for: .init("teoria.kutu"))) { _ in depo.kutuyuAl() }
        .onAppear {
            MacTemsilci.temayiUygula(depo.tema)
            MacTemsilci.rota = { rota($0) }
            Task { await depo.esitleSimdi(); await Bildirim.planla(depo) }
            // Sabah: until the day's session is closed, mornings open on it
            if Calendar.current.component(.hour, from: Date()) < 14, depo.durum.morningDone[MorningStore.todayKey] == nil { bolum = .sabah }
        }
        .onChange(of: depo.temaHam) { _, _ in MacTemsilci.temayiUygula(depo.tema) }
        .onChange(of: faz) { _, y in
            if y == .active { depo.kutuyuAl(); Task { await depo.esitleSimdi() } }
        }
        .task {
            // Voice Reader + Voice Dream → library every 10 minutes while the app runs (2026-10-20); quiet unless
            // something new arrived
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, !depo.guncelleniyor else { continue }
                await depo.guncelle()
                if let b = depo.bildirim, b == "Her şey güncel" || b.hasPrefix("Akış yenilendi") { depo.bildirim = nil }
            }
        }
    }

    /// Opens the notebook and puts the cursor in it; if it is already open with the cursor there, closes it.
    private func defterAc() {
        if defterAcik && NSApp.keyWindow?.firstResponder is NSTextView { defterAcik = false; return }
        defterAcik = true
        defterOdak += 1
    }

    private func rota(_ r: String) {
        switch r {
        case "kur", "hatirla": kurDakika = depo.kurDakika; bolum = .kur
        case "ikinci": bolum = .ikinci
        case "aksam":       // Akşam tekrarı (Evening.swift) opens over Bugün
            bolum = .bugun
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NotificationCenter.default.post(name: .init("teoria.aksam"), object: nil) }
        case "ses": sesHedef = .some(nil)
        case "defter": defterAc()
        case "akis": bolum = .akis
        case "kitaplar": bolum = .kitaplar
        case "mufredat": bolum = .mufredat
        case let x where x.hasPrefix("bolum:"): if let b = MacBolum(rawValue: String(x.dropFirst(6))) { bolum = b }
        case let x where x.hasPrefix("ses:"): let h = String(x.dropFirst(4)); sesHedef = .some(h.isEmpty ? nil : h)
        case let x where x.hasPrefix("isaret:"): bolum = .akis; seciliIsaret = depo.isaret(String(x.dropFirst(7)))
        case let x where x.hasPrefix("kitap:"):
            let id = String(x.dropFirst(6))
            if LibraryStore.shared.entry(id) != nil { linkedBook = id }
            bolum = .kitaplar
        default: break
        }
    }
}

struct SesHedefiMac: Identifiable { let id = UUID(); let hedef: String? }

/// Mac'te Kür sekmesinin karşılama yüzü: süre seç, başla.
struct KurBaslangic: View {
    @EnvironmentObject var depo: Depo
    var basla: (Int) -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Text("Kür").font(Tema.serif(.largeTitle, .bold))
            Text("Masaüstünde ağırlık yazmada: Dönüştür ve Kur hatları daha sık gelir.")
                .font(Tema.serif(.title3)).foregroundStyle(Tema.ikincil)
            HStack(spacing: 14) {
                ForEach([5, 10, 15], id: \.self) { d in
                    Button { depo.kurDakika = d; basla(d) } label: {
                        VStack(spacing: 6) {
                            Text("\(d)").font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("dakika").font(.callout)
                        }
                        .frame(width: 140, height: 120)
                        .background { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(d == depo.kurDakika ? Tema.vurgu : Tema.yuzey) }
                        .foregroundStyle(d == depo.kurDakika ? Color.white : Tema.metin)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 22) {
                ForEach(Hat.allCases) { h in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(h.ad, systemImage: h.sembol).foregroundStyle(Tema.hat(h)).font(.headline)
                        Text("K\(depo.durum.kademe(h)) · \(Evre.of(depo.durum.kademe(h)).rawValue)").font(.caption).foregroundStyle(.secondary)
                        Text(h.aciklama).font(.caption).foregroundStyle(Tema.ikincil).frame(width: 200, alignment: .leading)
                    }
                }
            }
            .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Menü çubuğu penceresi: günün aforizması, halka, tek tıkla kür.
struct MenuCubugu: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.openWindow) private var pencereAc

    var body: some View {
        let a = depo.anlik()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Halka(oran: min(a.bugunDakika / Double(max(a.hedefDakika, 1)), 1), renk: Tema.vurgu, kalinlik: 6)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teoria").font(Tema.serif(.headline))
                    Text("Bu hafta \(a.buHaftaKur) kür · \(a.oturmus) kavram oturdu").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let f = a.aforizmalar.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.metin).font(Tema.serif(.body))
                    Text(f.kaynak).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Kürü başlat") {
                    pencereAc(id: "ana")
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .init("teoria.rota"), object: "kur")
                }
                .buttonStyle(.borderedProminent)
                Button("Sesli not") {
                    pencereAc(id: "ana")
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .init("teoria.rota"), object: "ses")
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.accessibilityLabel("Çık").buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
