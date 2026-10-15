// Uygulamalarım — menü çubuğunda tek ikon (⌃⌥U): kendi Mac uygulamalarım ve tezgâhlarım tek listede.
// Hiçbir uygulamaya bağlı değil, onlar da buna bağlı değil: listeyi her açılışta
// _araçlar/cekmece/uygulamalar.json'dan okur, öğeyi macOS'a "aç" der. Yeni öğe = JSON'a bir satır.
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

// MARK: kayıt

struct Oge: Decodable, Identifiable, Hashable {
    let id, ad, alan, tur, hedef, simge, renk, ne: String
    let anahtar: String?
}

private struct Kayit: Decodable { let ogeler: [Oge] }

enum Kaynak {
    static let vault = NSHomeDirectory() + "/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management"
    static let dosya = URL(fileURLWithPath: vault + "/_araçlar/cekmece/uygulamalar.json")
    static let alanSirasi = ["Felsefe", "İngilizce", "Yazılım", "Sistem"]

    /// Önce vault'taki liste; okunamazsa uygulamanın içindeki son derleme kopyası.
    static func oku() -> (ogeler: [Oge], uyari: String?) {
        do {
            return (try JSONDecoder().decode(Kayit.self, from: Data(contentsOf: dosya)).ogeler, nil)
        } catch {
            let neden = (error as? DecodingError).map { "biçim hatası (\($0))" } ?? error.localizedDescription
            if let y = Bundle.main.url(forResource: "uygulamalar", withExtension: "json"),
               let d = try? Data(contentsOf: y), let k = try? JSONDecoder().decode(Kayit.self, from: d) {
                return (k.ogeler, "Vault'taki liste okunamadı — yedek gösteriliyor. \(neden)")
            }
            return ([], "Liste okunamadı: \(neden)")
        }
    }
}

private func esit(_ a: String, _ b: String) -> Bool {
    a.precomposedStringWithCanonicalMapping == b.precomposedStringWithCanonicalMapping
}

extension Oge {
    var yol: String {
        tur == "dosya" ? Kaynak.vault + "/" + hedef : (hedef as NSString).expandingTildeInPath
    }
    var var_: Bool {
        switch tur {
        case "uygulama", "dosya": return FileManager.default.fileExists(atPath: yol)
        default: return URL(string: hedef).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
        }
    }
    var calisiyor: Bool {
        guard tur == "uygulama" else { return false }
        let hedefYol = URL(fileURLWithPath: yol).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL.map { esit($0.standardizedFileURL.path, hedefYol) } ?? false
        }
    }
    var tonu: Color {
        let h = UInt32(renk.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        return Color(red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255)
    }
    func ac() {
        switch tur {
        case "uygulama":
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: yol), configuration: NSWorkspace.OpenConfiguration())
        case "dosya":
            NSWorkspace.shared.open(URL(fileURLWithPath: yol))
        default:
            if let u = URL(string: hedef) { NSWorkspace.shared.open(u) }
        }
    }
}

// MARK: model

final class Model: ObservableObject {
    @Published var ogeler: [Oge] = []
    @Published var uyari: String?
    @Published var arama = "" { didSet { secili = suzulmus.first?.id } }
    @Published var secili: String?
    @Published var tazelik = 0   // açılıp kapanan uygulamaları yeniden çizmek için

    func yenile() {
        (ogeler, uyari) = Kaynak.oku()
        arama = ""
        tazelik += 1
    }

    var suzulmus: [Oge] {
        let liste = arama.isEmpty ? ogeler : ogeler.filter { o in
            [o.ad, o.ne, o.alan, o.anahtar ?? ""].contains { $0.localizedStandardContains(arama) }
        }
        let sira = Kaynak.alanSirasi
        return liste.enumerated().sorted { a, b in
            let x = sira.firstIndex(of: a.element.alan) ?? sira.count, y = sira.firstIndex(of: b.element.alan) ?? sira.count
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    var gruplar: [(alan: String, ogeler: [Oge])] {
        var sonuc: [(alan: String, ogeler: [Oge])] = []
        for o in suzulmus {
            if sonuc.last?.alan == o.alan { sonuc[sonuc.count - 1].ogeler.append(o) } else { sonuc.append((o.alan, [o])) }
        }
        return sonuc
    }

    func kaydir(_ adim: Int) {
        let l = suzulmus
        guard !l.isEmpty else { return }
        let i = l.firstIndex { $0.id == secili } ?? -adim
        secili = l[max(0, min(l.count - 1, i + adim))].id
    }
}

// MARK: görünüm

struct Liste: View {
    @ObservedObject var m: Model
    let kapat: () -> Void
    @FocusState private var odak: Bool

    private func ac(_ o: Oge?) {
        guard let o, o.var_ else { return }
        o.ac(); kapat()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Ne arıyorsun? (gramer, kitap, fikir…)", text: $m.arama)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .focused($odak)
                    .onSubmit { ac(m.suzulmus.first { $0.id == m.secili }) }
                    .onKeyPress(.downArrow) { m.kaydir(1); return .handled }
                    .onKeyPress(.upArrow) { m.kaydir(-1); return .handled }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            if let u = m.uyari {
                Text(u).font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 14).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollViewReader { kaydirici in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(m.gruplar, id: \.alan) { g in
                            Text(g.alan.uppercased())
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 2)
                            ForEach(g.ogeler) { o in
                                Satir(o: o, secili: o.id == m.secili, tazelik: m.tazelik)
                                    .id(o.id)
                                    .onTapGesture { ac(o) }
                                    .onHover { if $0 { m.secili = o.id } }
                            }
                        }
                        if m.suzulmus.isEmpty {
                            Text(m.ogeler.isEmpty ? "Liste boş." : "“\(m.arama)” ile eşleşen yok.")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(30)
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 8)
                }
                .onChange(of: m.secili) { _, y in if let y { kaydirici.scrollTo(y) } }
            }
            Divider()
            HStack {
                Text("⌃⌥U  ·  ↑↓ seç  ·  ↩ aç").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Listeyi düzenle") { NSWorkspace.shared.open(Kaynak.dosya); kapat() }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 400, height: 500)
        .onAppear { odak = true; if m.secili == nil { m.secili = m.suzulmus.first?.id } }
    }
}

struct Satir: View {
    let o: Oge
    let secili: Bool
    let tazelik: Int

    var body: some View {
        let var_ = o.var_
        HStack(spacing: 11) {
            Image(systemName: o.simge)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(o.tonu.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(var_ ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 1) {
                Text(o.ad).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(var_ ? .primary : .secondary)
                Text(o.ne).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if !var_ {
                Text("bulunamadı").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            } else if o.calisiyor {
                Circle().fill(.green).frame(width: 7, height: 7).help("Açık")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(secili ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: menü çubuğu

final class Temsilci: NSObject, NSApplicationDelegate {
    static var shared: Temsilci?
    let model = Model()
    var simge: NSStatusItem!
    let pencere = NSPopover()
    var kisayol: EventHotKeyRef?

    func applicationDidFinishLaunching(_ n: Notification) {
        Temsilci.shared = self
        simge = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        simge.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Uygulamalarım")
        simge.button?.toolTip = "Uygulamalarım (⌃⌥U)"
        simge.button?.target = self
        simge.button?.action = #selector(tiklandi)
        simge.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        pencere.behavior = .transient
        pencere.animates = true
        pencere.contentViewController = NSHostingController(rootView: Liste(m: model) { [weak self] in self?.pencere.close() })

        kisayolKur()
        let d = UserDefaults.standard
        if !d.bool(forKey: "girisAyarlandi") {
            d.set(true, forKey: "girisAyarlandi")
            try? SMAppService.mainApp.register()
        }
    }

    @objc func tiklandi() {
        if NSApp.currentEvent?.type == .rightMouseUp { menuGoster() } else { degistir() }
    }

    func degistir() {
        if pencere.isShown { pencere.close(); return }
        guard let b = simge.button else { return }
        model.yenile()
        NSApp.activate(ignoringOtherApps: true)
        pencere.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        pencere.contentViewController?.view.window?.makeKey()
    }

    func menuGoster() {
        let m = NSMenu()
        let giris = NSMenuItem(title: "Girişte aç", action: #selector(girisDegistir), keyEquivalent: "")
        giris.target = self
        giris.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(giris)
        let duzenle = NSMenuItem(title: "Listeyi düzenle…", action: #selector(listeyiDuzenle), keyEquivalent: "")
        duzenle.target = self
        m.addItem(duzenle)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        simge.menu = m
        simge.button?.performClick(nil)
        simge.menu = nil
    }

    @objc func girisDegistir() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }

    @objc func listeyiDuzenle() { NSWorkspace.shared.open(Kaynak.dosya) }

    /// ⌃⌥U — her yerden aç/kapat.
    func kisayolKur() {
        var tur = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Temsilci.shared?.degistir() }
            return noErr
        }, 1, &tur, nil, nil)
        let kimlik = EventHotKeyID(signature: OSType(0x434D4345), id: 1)   // 'CMCE'
        RegisterEventHotKey(UInt32(kVK_ANSI_U), UInt32(controlKey | optionKey), kimlik, GetApplicationEventTarget(), 0, &kisayol)
    }
}

// Ön izleme: Cekmece -onizle <çıktı.png> [arama] [koyu] — menüyü ekran dışında PNG'ye çizer, açılmaz.
if let i = CommandLine.arguments.firstIndex(of: "-onizle"), i + 1 < CommandLine.arguments.count {
    let args = CommandLine.arguments
    MainActor.assumeIsolated {
        let m = Model(); m.yenile()
        if args.count > i + 2, args[i + 2] != "koyu" { m.arama = args[i + 2] }
        let koyu = args.contains("koyu")
        let gorunum = Liste(m: m) {}
            .background(koyu ? Color(white: 0.16) : Color(white: 0.97))
            .environment(\.colorScheme, koyu ? .dark : .light)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.appearance = NSAppearance(named: koyu ? .darkAqua : .aqua)
        let h = NSHostingView(rootView: gorunum)
        h.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        let w = NSWindow(contentRect: h.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = h
        w.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        w.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        h.layoutSubtreeIfNeeded()
        if let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) {
            h.cacheDisplay(in: h.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
    }
    exit(0)
}

let uygulama = NSApplication.shared
let temsilci = Temsilci()
uygulama.delegate = temsilci
uygulama.setActivationPolicy(.accessory)
uygulama.run()
