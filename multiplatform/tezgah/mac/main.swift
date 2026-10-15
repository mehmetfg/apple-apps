// Tezgâh — tezgâhların ortak masaüstü uygulaması.
//
// Tek pencere, beş sekme (Pano · Cümle · Mühendis · İdrak · Vault), menü çubuğunda daima
// duran bir ikon. Sayfalar vault'taki yerlerinden, ortak yerel sunucudan
// (Artifacts/_ortak/tezgah_sunucu.py) açılır; ilerleme o sunucunun durum köprüsüyle
// iCloud'a (Artifacts/_ortak/durum/) yazılır. Uygulama yalnız bir kabuktur: veri tutmaz.
//
// Derleme: Artifacts/_ortak/app/derle.sh

import Carbon.HIToolbox
import Cocoa
import ServiceManagement
import WebKit

let VAULT = NSHomeDirectory() + "/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management"
let ORTAK = VAULT + "/Artifacts/_ortak"
let LOG_KLASOR = NSHomeDirectory() + "/Library/Logs/Tezgah"

struct Sayfa {
    let kod: String
    let ad: String
    let yol: String
    let simge: String
}

let SAYFALAR = [
    Sayfa(kod: "pano", ad: "Pano", yol: "/Artifacts/pano.html", simge: "square.grid.2x2"),
    Sayfa(kod: "cumle", ad: "Cümle", yol: "/01 - English Learning/Artifacts/cumle-tezgahi.html", simge: "text.quote"),
    Sayfa(kod: "muhendis", ad: "Mühendis", yol: "/Artifacts/muhendis-tezgahi.html", simge: "hammer"),
    Sayfa(kod: "idrak", ad: "İdrak", yol: "/Artifacts/idrak-tezgahi.html", simge: "books.vertical"),
    Sayfa(kod: "vault", ad: "Vault", yol: "/Artifacts/vault-tezgahi.html", simge: "archivebox"),
]

// MARK: - Menü çubuğu ikonu: tezgâh (tabla + iki ayak) ve üstünde üç blok

func tezgahSimgesi(boy: CGFloat = 18) -> NSImage {
    let img = NSImage(size: NSSize(width: boy, height: boy), flipped: false) { r in
        let s = r.width / 18
        NSColor.black.setFill()
        // tabla
        NSBezierPath(roundedRect: NSRect(x: 1.5 * s, y: 6.5 * s, width: 15 * s, height: 2.2 * s),
                     xRadius: 0.8 * s, yRadius: 0.8 * s).fill()
        // ayaklar
        NSBezierPath(rect: NSRect(x: 3.2 * s, y: 1.5 * s, width: 1.8 * s, height: 5.2 * s)).fill()
        NSBezierPath(rect: NSRect(x: 13 * s, y: 1.5 * s, width: 1.8 * s, height: 5.2 * s)).fill()
        // üç tezgâh
        let bloklar: [(CGFloat, CGFloat)] = [(3.2, 5.5), (7.6, 8.0), (12.0, 4.0)]
        for (x, h) in bloklar {
            NSBezierPath(roundedRect: NSRect(x: x * s, y: 9.4 * s, width: 3.0 * s, height: h * s),
                         xRadius: 0.7 * s, yRadius: 0.7 * s).fill()
        }
        return true
    }
    img.isTemplate = true
    return img
}

// MARK: - Sunucu

final class Sunucu {
    private(set) var port: Int?
    private var surec: Process?
    var hazir: ((Int) -> Void)?
    var hata: ((String) -> Void)?
    var dustu: (() -> Void)?

    var basarisiz = 0

    func baslat() {
        DispatchQueue.global().async {
            for p in 8780..<8790 {
                guard let v = self.pingSurum(p) else { continue }
                if v < 2 {   // eski sürüm sunucu: yeni uçları bilmez → kapat, yenisini başlat
                    self.eskiyiKapat(p)
                    continue
                }
                DispatchQueue.main.async { self.port = p; self.hazir?(p) }
                return
            }
            let (py, ileti) = self.pythonBul()
            DispatchQueue.main.async {
                if let py = py { self.surecBaslat(py) } else { self.hata?(ileti) }
            }
        }
    }

    /// Tezgâh sunucusuysa uygulama sürümünü (yoksa 1), değilse nil döner.
    func pingSurum(_ p: Int) -> Int? {
        guard let url = URL(string: "http://127.0.0.1:\(p)/api/ping") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.8
        let sem = DispatchSemaphore(value: 0)
        var surum: Int?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               j["tezgah"] as? Bool == true { surum = j["uyg"] as? Int ?? 1 }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.2)
        return surum
    }

    func eskiyiKapat(_ p: Int) {
        let l = Process()
        l.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        l.arguments = ["-ti", "tcp:\(p)", "-sTCP:LISTEN"]
        let c = Pipe()
        l.standardOutput = c
        try? l.run()
        l.waitUntilExit()
        let s = String(data: c.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for pid in s.split(whereSeparator: \.isNewline).compactMap({ Int32($0) }) { kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 1.2)
    }

    /// Çalışan ilk Python'u bulur. /usr/bin/python3 Xcode lisansı onaylanmamışsa "var ama çalışmaz"
    /// (kabuk betiği hata verir) — o yüzden her adayı gerçekten çalıştırıp sınarız.
    func pythonBul() -> (String?, String) {
        let adaylar = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                       "/Library/Developer/CommandLineTools/usr/bin/python3", "/usr/bin/python3"]
        var sonHata = ""
        for a in adaylar where FileManager.default.isExecutableFile(atPath: a) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: a)
            p.arguments = ["-c", "pass"]
            let e = Pipe()
            p.standardError = e
            p.standardOutput = FileHandle.nullDevice
            do { try p.run() } catch { continue }
            p.waitUntilExit()
            if p.terminationStatus == 0 { return (a, "") }
            sonHata = String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        if sonHata.contains("license") {
            return (nil, "Python çalışmıyor: Xcode lisansı onaylanmamış.\nTerminal'de bir kez çalıştır:\n  sudo xcodebuild -license accept")
        }
        return (nil, "Python bulunamadı.\nTerminal'de çalıştır:\n  xcode-select --install")
    }

    /// Her 20 sn'de çağrılır: sunucu art arda iki kez yanıt vermezse yeniden başlatılır.
    func nabiz() {
        guard let p = port else { return }
        DispatchQueue.global().async {
            let ok = self.pingSurum(p) != nil
            DispatchQueue.main.async {
                if ok { self.basarisiz = 0; return }
                self.basarisiz += 1
                guard self.basarisiz >= 2 else { return }
                self.basarisiz = 0
                if let s = self.surec { s.terminate() } else { self.port = nil; self.dustu?() }
            }
        }
    }

    private func surecBaslat(_ py: String) {
        try? FileManager.default.createDirectory(atPath: LOG_KLASOR, withIntermediateDirectories: true)
        let logYol = LOG_KLASOR + "/sunucu.log"
        FileManager.default.createFile(atPath: logYol, contents: nil)
        let log = FileHandle(forWritingAtPath: logYol)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [ORTAK + "/tezgah_sunucu.py"]
        p.currentDirectoryURL = URL(fileURLWithPath: ORTAK)
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"   // iCloud'a __pycache__ düşmesin
        env["PYTHONUNBUFFERED"] = "1"
        p.environment = env
        let cikis = Pipe()
        p.standardOutput = cikis
        p.standardError = log ?? FileHandle.nullDevice
        var tampon = ""
        cikis.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            log?.write(d)
            tampon += s
            if self?.port == nil, let r = tampon.range(of: #"PORT (\d+)"#, options: .regularExpression),
               let n = Int(tampon[r].dropFirst(5)) {
                DispatchQueue.main.async { self?.port = n; self?.hazir?(n) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let vardi = self.port != nil
                self.port = nil
                self.surec = nil
                if vardi { self.dustu?() } else {
                    let son = (try? String(contentsOfFile: logYol, encoding: .utf8)) ?? ""
                    self.hata?(String(son.suffix(1200)))
                }
            }
        }
        do {
            try p.run()
            surec = p
        } catch {
            hata?("Python başlatılamadı: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            if self?.port == nil && self?.surec != nil {
                self?.hata?("Sunucu 25 saniyede açılmadı. Günlük: ~/Library/Logs/Tezgah/sunucu.log")
            }
        }
    }

    func durdur() {
        surec?.terminate()
        surec = nil
    }
}

// MARK: - Uygulama

@MainActor
final class Uygulama: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate,
    WKUIDelegate, WKDownloadDelegate, NSToolbarDelegate {

    let sunucu = Sunucu()
    var pencere: NSWindow!
    var kap: NSView!
    var bekleme: NSTextField!
    var secici: NSSegmentedControl!
    var simge: NSStatusItem!
    var gorunumler: [String: WKWebView] = [:]
    var paletPanel: Palet!
    var yakalaPanel: Yakala!
    var saglikOgesi: NSMenuItem!
    var saglikSon: [String: Any] = [:]
    var cokmeler: [String: [Date]] = [:]
    var yenidenBaslatmalar: [Date] = []
    var gorunumGozlem: NSKeyValueObservation?
    var etkin = UserDefaults.standard.string(forKey: "etkin") ?? "pano"
    let ayar: WKWebViewConfiguration = {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = .default()
        c.preferences.javaScriptCanOpenWindowsAutomatically = true
        c.mediaTypesRequiringUserActionForPlayback = []
        c.preferences.setValue(true, forKey: "developerExtrasEnabled")
        return c
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuKur()
        pencereKur()
        simgeKur()
        girisIlkKez()
        sunucu.hazir = { [weak self] _ in self?.sunucuHazir() }
        sunucu.hata = { [weak self] m in self?.sunucuHata(m) }
        sunucu.dustu = { [weak self] in self?.yenidenBaslatmaDene("Sunucu durdu") }
        sunucu.baslat()
        ekKur()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ n: Notification) {
        for w in gorunumler.values {   // bekleyen yazımları gönder
            w.evaluateJavaScript("window.__ORTAK && __ORTAK.gonder && __ORTAK.gonder(true)")
        }
        let son = Date().addingTimeInterval(0.6)
        while Date() < son { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        sunucu.durdur()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        pencereGoster()
        return true
    }

    // MARK: pencere

    func pencereKur() {
        pencere = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 880),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        pencere.title = "Tezgâh"
        pencere.titleVisibility = .hidden
        pencere.minSize = NSSize(width: 760, height: 520)
        pencere.delegate = self
        pencere.isReleasedWhenClosed = false
        pencere.setFrameAutosaveName("TezgahPencere")
        if !pencere.setFrameUsingName("TezgahPencere") { pencere.center() }
        pencereyiGorunurYap()

        let tb = NSToolbar(identifier: "tezgah")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.centeredItemIdentifier = NSToolbarItem.Identifier("secici")
        pencere.toolbar = tb
        pencere.toolbarStyle = .unified

        kap = NSView()
        kap.wantsLayer = true
        kap.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        pencere.contentView = kap

        bekleme = NSTextField(labelWithString: "Tezgâh açılıyor…")
        bekleme.font = .systemFont(ofSize: 15, weight: .medium)
        bekleme.textColor = .secondaryLabelColor
        bekleme.alignment = .center
        bekleme.maximumNumberOfLines = 0
        bekleme.translatesAutoresizingMaskIntoConstraints = false
        kap.addSubview(bekleme)
        NSLayoutConstraint.activate([
            bekleme.centerXAnchor.constraint(equalTo: kap.centerXAnchor),
            bekleme.centerYAnchor.constraint(equalTo: kap.centerYAnchor),
            bekleme.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])
        pencere.makeKeyAndOrderFront(nil)
    }

    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("secici")]
    }

    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, NSToolbarItem.Identifier("secici"), .flexibleSpace]
    }

    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar f: Bool) -> NSToolbarItem? {
        guard id.rawValue == "secici" else { return nil }
        secici = NSSegmentedControl(labels: SAYFALAR.map { $0.ad }, trackingMode: .selectOne,
                                    target: self, action: #selector(seciciDegisti(_:)))
        for (i, s) in SAYFALAR.enumerated() {
            secici.setImage(NSImage(systemSymbolName: s.simge, accessibilityDescription: s.ad), forSegment: i)
            secici.setImageScaling(.scaleProportionallyDown, forSegment: i)
            secici.setWidth(108, forSegment: i)
        }
        secici.segmentStyle = .automatic
        secici.selectedSegment = SAYFALAR.firstIndex { $0.kod == etkin } ?? 0
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = secici
        item.label = "Tezgâhlar"
        return item
    }

    @objc func seciciDegisti(_ s: NSSegmentedControl) { goster(SAYFALAR[s.selectedSegment].kod) }

    func windowShouldClose(_ s: NSWindow) -> Bool {
        pencere.orderOut(nil)   // kapatınca gizle; menü çubuğu ikonu ve sunucu açık kalır
        return false
    }

    func pencereGoster() {
        NSApp.activate(ignoringOtherApps: true)
        pencere.makeKeyAndOrderFront(nil)
    }

    func durumYaz(_ m: String) {
        pencere.subtitle = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.pencere.subtitle == m { self?.pencere.subtitle = "" }
        }
    }

    // MARK: sekmeler

    func url(_ s: Sayfa) -> URL? {
        guard let p = sunucu.port else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = p
        c.path = s.yol
        return c.url
    }

    func sunucuHazir() {
        bekleme.isHidden = true
        for (kod, w) in gorunumler {   // sunucu yeniden başladıysa sayfaları yeni porta bağla
            if let s = SAYFALAR.first(where: { $0.kod == kod }), let u = url(s), w.url?.port != u.port {
                w.load(URLRequest(url: u))
            }
        }
        goster(etkin)
        kuyrukBosalt()
        saglikYenile()
    }

    func sunucuHata(_ m: String) {
        bekleme.isHidden = false
        bekleme.stringValue = "Sunucu açılamadı.\n\n\(m)\n\nmacOS iCloud Drive izni sorduysa izin verip menüden “Sunucuyu yeniden başlat”ı seç."
        gorunumler.values.forEach { $0.isHidden = true }
    }

    func gorunum(_ kod: String) -> WKWebView {
        if let w = gorunumler[kod] { return w }
        let w = WKWebView(frame: kap.bounds, configuration: ayar)
        w.autoresizingMask = [.width, .height]
        w.navigationDelegate = self
        w.uiDelegate = self
        w.allowsBackForwardNavigationGestures = true
        w.allowsMagnification = true
        if #available(macOS 13.3, *) { w.isInspectable = true }
        w.pageZoom = CGFloat(UserDefaults.standard.double(forKey: "zoom-\(kod)").nonZero ?? 1)
        gorunumler[kod] = w
        if let s = SAYFALAR.first(where: { $0.kod == kod }), let u = url(s) {
            w.load(URLRequest(url: u))
        }
        return w
    }

    func goster(_ kod: String) {
        // Cümle artık yerli Mac uygulaması (2026-10-09): kuruluysa onu öne getir, sekme yerinde kalsın.
        // Kurulu değilse (ör. öteki Mac) eski HTML Tezgâh açılır.
        if kod == "cumle", let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.fatihgocgun.cumle") {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
            if let i = SAYFALAR.firstIndex(where: { $0.kod == (etkin == "cumle" ? "pano" : etkin) }) { secici?.selectedSegment = i }
            if etkin == "cumle" { goster("pano") }
            return
        }
        guard sunucu.port != nil else { etkin = kod; return }
        let tazele = kod == "pano" && gorunumler["pano"] != nil && etkin != "pano"
        etkin = kod
        UserDefaults.standard.set(kod, forKey: "etkin")
        let w = gorunum(kod)
        for (k, v) in gorunumler where k != kod { v.removeFromSuperview() }
        if w.superview == nil {
            w.frame = kap.bounds
            kap.addSubview(w)
        }
        w.isHidden = false
        pencere.makeFirstResponder(w)
        if tazele { w.reload() }   // pano öteki tezgâhların son hâlini okusun
        if let i = SAYFALAR.firstIndex(where: { $0.kod == kod }) { secici?.selectedSegment = i }
        pencere.title = "Tezgâh — " + (SAYFALAR.first { $0.kod == kod }?.ad ?? "")
    }

    func etkinGorunum() -> WKWebView? { gorunumler[etkin] }

    func sayfaKodu(_ u: URL) -> String? {
        guard u.host == "127.0.0.1", u.port == sunucu.port else { return nil }
        return SAYFALAR.first { $0.yol == u.path }?.kod
    }

    func kodu(_ w: WKWebView) -> String? { gorunumler.first { $0.value === w }?.key }

    // MARK: gezinme

    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction,
                 decisionHandler karar: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if a.shouldPerformDownload { return karar(.download) }
        guard let u = a.request.url else { return karar(.allow) }
        if ["blob", "data", "about", "javascript"].contains(u.scheme ?? "") { return karar(.allow) }
        let anaCerceve = a.targetFrame?.isMainFrame ?? true
        if let kod = sayfaKodu(u), anaCerceve, kod != kodu(w), a.navigationType == .linkActivated {
            goster(kod)            // panodaki bağlantı: ilgili sekmeye geç
            return karar(.cancel)
        }
        if u.host == "127.0.0.1" && u.port == sunucu.port { return karar(.allow) }
        if anaCerceve && (a.navigationType == .linkActivated || a.targetFrame == nil) {
            NSWorkspace.shared.open(u)   // dış bağlantılar varsayılan tarayıcıda
            return karar(.cancel)
        }
        karar(.allow)
    }

    func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse,
                 decisionHandler karar: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        karar(r.canShowMIMEType ? .allow : .download)
    }

    func webView(_ w: WKWebView, navigationAction a: WKNavigationAction, didBecome d: WKDownload) {
        d.delegate = self
    }

    func webView(_ w: WKWebView, navigationResponse r: WKNavigationResponse, didBecome d: WKDownload) {
        d.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        guard let kod = kodu(w) else { w.reload(); return }
        let simdi = Date()
        var l = (cokmeler[kod] ?? []).filter { simdi.timeIntervalSince($0) < 30 }
        l.append(simdi)
        cokmeler[kod] = l
        if l.count > 3 {   // sayfa tekrar tekrar çöküyorsa yenileme döngüsüne girme
            hataSayfasi(w, "Sayfa art arda çöktü. Menüden “Sunucuyu yeniden başlat”ı dene; sürerse ⌘⌥I ile konsola bak.")
        } else { w.reload() }
    }

    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { gezinmeHatasi(w, e) }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { gezinmeHatasi(w, e) }

    func gezinmeHatasi(_ w: WKWebView, _ e: Error) {
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }   // indirmeye çevrilen gezinme
        hataSayfasi(w, ns.localizedDescription)
    }

    /// Boş beyaz pencere yerine yeniden dene düğmeli bir sayfa gösterir.
    func hataSayfasi(_ w: WKWebView, _ ileti: String) {
        guard let kod = kodu(w), let s = SAYFALAR.first(where: { $0.kod == kod }), let u = url(s),
              let p = sunucu.port else { return }
        func kac(_ t: String) -> String {
            t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        let html = """
        <meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <body style="font:15px -apple-system;display:grid;place-items:center;height:100vh;margin:0;text-align:center">
        <div style="max-width:440px"><h2 style="font-weight:600">\(kac(s.ad)) açılamadı</h2>
        <p style="opacity:.7;line-height:1.5">\(kac(ileti))</p>
        <p><a href="\(u.absoluteString)" style="padding:8px 18px;border-radius:8px;background:#3b73c9;color:#fff;text-decoration:none">Yeniden dene</a></p>
        <p style="opacity:.5;font-size:12px">Günlük: ~/Library/Logs/Tezgah/sunucu.log</p></div></body>
        """
        w.loadHTMLString(html, baseURL: URL(string: "http://127.0.0.1:\(p)/"))
    }

    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration,
                 for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
        if let u = a.request.url {
            if let kod = sayfaKodu(u) { goster(kod) } else if u.scheme == "http" || u.scheme == "https" {
                NSWorkspace.shared.open(u)
            } else { w.load(a.request) }
        }
        return nil
    }

    // MARK: indirme → ~/Downloads (tezgâh sonuç JSON'ları; /muhendis topla, isle.py oradan okur)

    func download(_ d: WKDownload, decideDestinationUsing r: URLResponse, suggestedFilename ad: String,
                  completionHandler tamam: @escaping @MainActor (URL?) -> Void) {
        let kl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let temiz = ad.isEmpty ? "tezgah-indirme" : ad
        var hedef = kl.appendingPathComponent(temiz)
        let kok = (temiz as NSString).deletingPathExtension
        let uz = (temiz as NSString).pathExtension
        var i = 2
        while FileManager.default.fileExists(atPath: hedef.path) {
            hedef = kl.appendingPathComponent(uz.isEmpty ? "\(kok) \(i)" : "\(kok) \(i).\(uz)")
            i += 1
        }
        indirilen[ObjectIdentifier(d)] = hedef
        tamam(hedef)
    }

    var indirilen: [ObjectIdentifier: URL] = [:]

    func downloadDidFinish(_ d: WKDownload) {
        if let u = indirilen.removeValue(forKey: ObjectIdentifier(d)) {
            durumYaz("İndirildi: \(u.lastPathComponent)")
            NSSound(named: "Glass")?.play()
        }
    }

    func download(_ d: WKDownload, didFailWithError e: Error, resumeData r: Data?) {
        durumYaz("İndirme olmadı: \(e.localizedDescription)")
    }

    // MARK: sayfa pencereleri (alert / confirm / prompt / dosya / mikrofon)

    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String,
                 initiatedByFrame f: WKFrameInfo, completionHandler tamam: @escaping @MainActor () -> Void) {
        let a = NSAlert()
        a.messageText = m
        a.addButton(withTitle: "Tamam")
        a.beginSheetModal(for: pencere) { _ in tamam() }
    }

    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage m: String,
                 initiatedByFrame f: WKFrameInfo, completionHandler tamam: @escaping @MainActor (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = m
        a.addButton(withTitle: "Tamam")
        a.addButton(withTitle: "Vazgeç")
        a.beginSheetModal(for: pencere) { r in tamam(r == .alertFirstButtonReturn) }
    }

    func webView(_ w: WKWebView, runJavaScriptTextInputPanelWithPrompt m: String, defaultText d: String?,
                 initiatedByFrame f: WKFrameInfo, completionHandler tamam: @escaping @MainActor (String?) -> Void) {
        let a = NSAlert()
        a.messageText = m
        let alan = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alan.stringValue = d ?? ""
        a.accessoryView = alan
        a.addButton(withTitle: "Tamam")
        a.addButton(withTitle: "Vazgeç")
        a.window.initialFirstResponder = alan
        a.beginSheetModal(for: pencere) { r in tamam(r == .alertFirstButtonReturn ? alan.stringValue : nil) }
    }

    func webView(_ w: WKWebView, runOpenPanelWith p: WKOpenPanelParameters, initiatedByFrame f: WKFrameInfo,
                 completionHandler tamam: @escaping @MainActor ([URL]?) -> Void) {
        let o = NSOpenPanel()
        o.allowsMultipleSelection = p.allowsMultipleSelection
        o.canChooseDirectories = p.allowsDirectories
        o.beginSheetModal(for: pencere) { r in tamam(r == .OK ? o.urls : nil) }
    }

    @available(macOS 12.0, *)
    func webView(_ w: WKWebView, requestMediaCapturePermissionFor o: WKSecurityOrigin, initiatedByFrame f: WKFrameInfo,
                 type t: WKMediaCaptureType, decisionHandler karar: @escaping @MainActor (WKPermissionDecision) -> Void) {
        karar(o.host == "127.0.0.1" ? .grant : .prompt)
    }

    // MARK: menü çubuğu ikonu

    func simgeKur() {
        simge = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        simge.button?.image = tezgahSimgesi()
        simge.button?.toolTip = "Tezgâh"
        let m = NSMenu()
        for (i, s) in SAYFALAR.enumerated() {
            let it = NSMenuItem(title: s.ad, action: #selector(menudenAc(_:)), keyEquivalent: "\(i + 1)")
            it.representedObject = s.kod
            it.image = NSImage(systemSymbolName: s.simge, accessibilityDescription: s.ad)
            it.target = self
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(oge("Komut paleti…", #selector(paletAc), "k"))
        m.addItem(oge("Hızlı fikir yakala…  ⌃⌥Boşluk", #selector(yakalaAc)))
        saglikOgesi = NSMenuItem(title: "Eşitleme: kontrol ediliyor…", action: nil, keyEquivalent: "")
        saglikOgesi.submenu = NSMenu()
        m.addItem(saglikOgesi)
        m.addItem(.separator())
        m.addItem(oge("Tarayıcıda aç", #selector(tarayicidaAc)))
        m.addItem(oge("Durum klasörünü göster", #selector(durumKlasoru)))
        m.addItem(oge("Chrome'daki ilerlemeyi al…", #selector(chromeAl)))
        m.addItem(oge("Sunucuyu yeniden başlat", #selector(sunucuYeniden)))
        m.addItem(.separator())
        let g = oge("Girişte aç", #selector(girisDegistir(_:)))
        g.state = girisAcik() ? .on : .off
        m.addItem(g)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Tezgâh'tan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        simge.menu = m
    }

    func oge(_ t: String, _ s: Selector, _ k: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        return i
    }

    @objc func menudenAc(_ i: NSMenuItem) {
        pencereGoster()
        if let k = i.representedObject as? String { goster(k) }
    }

    @objc func tarayicidaAc() {
        if let u = etkinGorunum()?.url ?? SAYFALAR.first(where: { $0.kod == etkin }).flatMap({ url($0) }) {
            NSWorkspace.shared.open(u)
        }
    }

    @objc func durumKlasoru() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: ORTAK + "/durum")])
    }

    @objc func sunucuYeniden() {
        bekleme.isHidden = false
        bekleme.stringValue = "Sunucu yeniden başlatılıyor…"
        yenidenBaslatmalar = []
        sunucu.dustu = nil
        sunucu.durdur()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.sunucu.dustu = { [weak self] in self?.yenidenBaslatmaDene("Sunucu durdu") }
            self?.sunucu.baslat()
        }
    }

    @objc func chromeAl() {
        let a = NSAlert()
        a.messageText = "Chrome'daki ilerleme alınsın mı?"
        a.informativeText = "Tezgâhları bu Mac'te Chrome'da dosyadan açıp çalıştıysan, oradaki kayıtlardan iCloud'dakinden daha yeni olanlar alınır. Daha eski olanlara dokunulmaz, Chrome'daki veri silinmez."
        a.addButton(withTitle: "Yeni olanları al")
        a.addButton(withTitle: "Vazgeç")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: sunucu.pythonBul().0 ?? "/usr/bin/python3")
        p.arguments = [ORTAK + "/chrome_aktar.py", "--yaz", "--akilli"]
        p.environment = ["PYTHONDONTWRITEBYTECODE": "1", "HOME": NSHomeDirectory()]
        let c = Pipe()
        p.standardOutput = c
        p.standardError = c
        p.terminationHandler = { _ in
            let s = String(data: c.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let b = NSAlert()
                b.messageText = p.terminationStatus == 0 ? "Chrome'daki ilerleme alındı" : "Alınamadı"
                b.informativeText = String(s.suffix(900))
                b.runModal()
                for w in self.gorunumler.values { w.reload() }
            }
        }
        try? p.run()
    }

    // MARK: girişte aç

    func girisAcik() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    func girisIlkKez() {
        guard !UserDefaults.standard.bool(forKey: "giris-ayarlandi") else { return }
        UserDefaults.standard.set(true, forKey: "giris-ayarlandi")
        if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
        simge?.menu?.items.first { $0.action == #selector(girisDegistir(_:)) }?.state = girisAcik() ? .on : .off
    }

    @objc func girisDegistir(_ i: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }
        if girisAcik() { try? SMAppService.mainApp.unregister() } else { try? SMAppService.mainApp.register() }
        i.state = girisAcik() ? .on : .off
    }

    // MARK: ana menü

    func menuKur() {
        let ana = NSMenu()

        let uyg = NSMenu()
        uyg.addItem(withTitle: "Tezgâh Hakkında", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        uyg.addItem(.separator())
        uyg.addItem(withTitle: "Tezgâh'ı Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let digerleri = uyg.addItem(withTitle: "Diğerlerini Gizle", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        digerleri.keyEquivalentModifierMask = [.command, .option]
        uyg.addItem(.separator())
        uyg.addItem(withTitle: "Tezgâh'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        ekle(ana, "Tezgâh", uyg)

        let duz = NSMenu(title: "Düzen")
        duz.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let yi = duz.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        yi.keyEquivalentModifierMask = [.command, .shift]
        duz.addItem(.separator())
        duz.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        duz.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        duz.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        duz.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        ekle(ana, "Düzen", duz)

        let gor = NSMenu(title: "Görünüm")
        for (i, s) in SAYFALAR.enumerated() {
            let it = gor.addItem(withTitle: s.ad, action: #selector(menudenAc(_:)), keyEquivalent: "\(i + 1)")
            it.representedObject = s.kod
            it.target = self
        }
        gor.addItem(.separator())
        gor.addItem(oge("Yenile", #selector(yenile), "r"))
        gor.addItem(oge("Geri", #selector(geri), "["))
        gor.addItem(oge("İleri", #selector(ileri), "]"))
        gor.addItem(.separator())
        gor.addItem(oge("Büyüt", #selector(buyut), "+"))
        gor.addItem(oge("Küçült", #selector(kucult), "-"))
        gor.addItem(oge("Gerçek Boyut", #selector(gercek), "0"))
        gor.addItem(.separator())
        gor.addItem(oge("Komut Paleti…", #selector(paletAc), "k"))
        let yk = oge("Hızlı Fikir Yakala…", #selector(yakalaAc), "n")
        yk.keyEquivalentModifierMask = [.command, .shift]
        gor.addItem(yk)
        gor.addItem(oge("Yazdır…", #selector(yazdir), "p"))
        gor.addItem(.separator())
        gor.addItem(oge("Tarayıcıda Aç", #selector(tarayicidaAc)))
        ekle(ana, "Görünüm", gor)

        let pen = NSMenu(title: "Pencere")
        pen.addItem(withTitle: "Küçült", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        pen.addItem(withTitle: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        pen.addItem(withTitle: "Tam Ekran", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        ekle(ana, "Pencere", pen)
        NSApp.windowsMenu = pen

        NSApp.mainMenu = ana
    }

    func ekle(_ ana: NSMenu, _ ad: String, _ m: NSMenu) {
        let i = NSMenuItem(title: ad, action: nil, keyEquivalent: "")
        i.submenu = m
        ana.addItem(i)
    }

    @objc func yenile() { etkinGorunum()?.reload() }
    @objc func geri() { etkinGorunum()?.goBack() }
    @objc func ileri() { etkinGorunum()?.goForward() }
    @objc func buyut() { zoom(1.1) }
    @objc func kucult() { zoom(1 / 1.1) }
    @objc func gercek() { zoom(0) }

    func zoom(_ k: CGFloat) {
        guard let w = etkinGorunum() else { return }
        w.pageZoom = k == 0 ? 1 : min(3, max(0.5, w.pageZoom * k))
        UserDefaults.standard.set(Double(w.pageZoom), forKey: "zoom-\(etkin)")
    }
}

// MARK: - Modernizasyon: palet, yakalama, eşitleme sağlığı, kenar durumları

extension Uygulama {
    var istemci: Istemci? { sunucu.port.map { Istemci(port: $0) } }

    func ekKur() {
        paletPanel = Palet()
        yakalaPanel = Yakala()
        paletPanel.komutlar = { [weak self] in self?.komutListesi() ?? [] }
        paletPanel.notAra = { [weak self] q, tamam in self?.notAra(q, tamam) }
        yakalaPanel.kaydet = { [weak self] m, bitti in self?.yakalaKaydet(m, bitti) }
        genelKisayolKaydet(tus: kVK_Space, degistirici: controlKey | optionKey) { [weak self] in self?.yakalaAc() }

        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sunucu.nabiz() }
        }
        Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.saglikYenile() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // ağ/iCloud kendine gelsin
                    self?.sunucu.nabiz()
                    self?.saglikYenile()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pencereyiGorunurYap() }
        }
        gorunumGozlem = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.kap.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        }
        gunKontrol()
    }

    // gün çıpası: günün ilk açılışında Pano (bugünün işi) karşılar
    func gunKontrol() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let bugun = f.string(from: Date())
        guard UserDefaults.standard.string(forKey: "son-gun") != bugun else { return }
        UserDefaults.standard.set(bugun, forKey: "son-gun")
        if sunucu.port != nil { goster("pano") } else { etkin = "pano" }
    }

    func applicationDidBecomeActive(_ n: Notification) {
        gunKontrol()
        if sunucu.port != nil && saglikSon.isEmpty { saglikYenile() }
    }

    func pencereyiGorunurYap() {
        let sigan = NSScreen.screens.contains {
            let k = $0.visibleFrame.intersection(pencere.frame)
            return k.width > 120 && k.height > 120
        }
        if !sigan { pencere.center() }
    }

    func yenidenBaslatmaDene(_ neden: String) {
        let simdi = Date()
        yenidenBaslatmalar = yenidenBaslatmalar.filter { simdi.timeIntervalSince($0) < 600 }
        if yenidenBaslatmalar.count >= 4 {
            sunucuHata("Sunucu 10 dakikada 4 kez düştü; yeniden denemeyi bıraktım.\nGünlük: ~/Library/Logs/Tezgah/sunucu.log")
            return
        }
        yenidenBaslatmalar.append(simdi)
        durumYaz("\(neden) — yeniden başlatılıyor…")
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(yenidenBaslatmalar.count)) { [weak self] in
            self?.sunucu.baslat()
        }
    }

    // MARK: komut paleti

    func komutListesi() -> [Komut] {
        var k: [Komut] = []
        for (i, s) in SAYFALAR.enumerated() {
            k.append(Komut(baslik: s.ad, alt: "Tezgâhı aç · ⌘\(i + 1)", simge: s.simge) { [weak self] in
                self?.pencereGoster(); self?.goster(s.kod)
            })
        }
        k.append(Komut(baslik: "Hızlı fikir yakala", alt: "Her yerden ⌃⌥Boşluk · Fikirler klasörüne düşer", simge: "lightbulb") { [weak self] in self?.yakalaAc() })
        k.append(Komut(baslik: "Eşitleme durumu", alt: saglikOzeti(), simge: "arrow.triangle.2.circlepath") { [weak self] in self?.saglikGoster() })
        k.append(Komut(baslik: "Yazdır / PDF", alt: "Açık tezgâhı yazdır", simge: "printer") { [weak self] in self?.yazdir() })
        k.append(Komut(baslik: "Tarayıcıda aç", alt: "Açık sekmeyi varsayılan tarayıcıda göster", simge: "safari") { [weak self] in self?.tarayicidaAc() })
        k.append(Komut(baslik: "Chrome'daki ilerlemeyi al", alt: "Yalnız daha yeni kayıtlar", simge: "square.and.arrow.down") { [weak self] in self?.chromeAl() })
        k.append(Komut(baslik: "Sunucuyu yeniden başlat", alt: "Takılırsa", simge: "arrow.clockwise") { [weak self] in self?.sunucuYeniden() })
        k.append(Komut(baslik: "Sunucu günlüğünü aç", alt: LOG_KLASOR + "/sunucu.log", simge: "doc.plaintext") {
            NSWorkspace.shared.open(URL(fileURLWithPath: LOG_KLASOR + "/sunucu.log"))
        })
        k.append(Komut(baslik: "Durum klasörünü göster", alt: "iCloud'daki tezgâh ilerlemesi", simge: "folder") { [weak self] in self?.durumKlasoru() })
        return k
    }

    func notAra(_ q: String, _ tamam: @escaping ([Komut]) -> Void) {
        guard let ist = istemci else { return tamam([]) }
        let izin = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let enc = q.addingPercentEncoding(withAllowedCharacters: izin) ?? q
        ist.istek("/api/uyg/ara?q=\(enc)") { [weak self] kod, j in
            guard kod == 200, let l = j["sonuc"] as? [[String: Any]] else { return tamam([]) }
            tamam(l.compactMap { r in
                guard let p = r["p"] as? String else { return nil }
                let ad = (r["ad"] as? String) ?? p
                return Komut(baslik: ad, alt: p, simge: "doc.text") { self?.obsidianAc(p) }
            })
        }
    }

    func obsidianAc(_ p: String) {
        let izin = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let v = (VAULT as NSString).lastPathComponent.addingPercentEncoding(withAllowedCharacters: izin) ?? ""
        let f = (p.hasSuffix(".md") ? String(p.dropLast(3)) : p).addingPercentEncoding(withAllowedCharacters: izin) ?? ""
        if let u = URL(string: "obsidian://open?vault=\(v)&file=\(f)") { NSWorkspace.shared.open(u) }
    }

    @objc func paletAc() { paletPanel.ac() }

    // MARK: hızlı yakalama

    @objc func yakalaAc() { yakalaPanel.ac() }

    func yakalaKaydet(_ metin: String, _ bitti: @escaping (String, Bool) -> Void) {
        let kimlik = UUID().uuidString
        guard let ist = istemci else {
            kuyrugaAl(kimlik, metin)
            return bitti("", true)
        }
        ist.istek("/api/uyg/yakala", yontem: "POST", govde: ["metin": metin, "kimlik": kimlik], sure: 8) { [weak self] kod, j in
            guard let self = self else { return }
            if kod == 200 {
                self.yakalandi()
                bitti("", true)
            } else if kod == 0 {   // sunucuya ulaşılamadı: fikir kaybolmasın, sıraya alınır
                self.kuyrugaAl(kimlik, metin)
                bitti("", true)
            } else {
                bitti("Kaydedilemedi: \((j["hata"] as? String) ?? "kod \(kod)")", false)
            }
        }
    }

    func yakalandi() {
        NSSound(named: "Pop")?.play()
        durumYaz("Fikir kaydedildi → 05 - Notlar/Fikirler")
        simge.button?.title = " ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.saglikMenuKur() }
    }

    func kuyrugaAl(_ kimlik: String, _ metin: String) {
        var q = UserDefaults.standard.array(forKey: "yakala-bekleyen") as? [[String: String]] ?? []
        q.append(["kimlik": kimlik, "metin": metin])
        UserDefaults.standard.set(q, forKey: "yakala-bekleyen")
        durumYaz("Sunucu kapalı — fikir sıraya alındı (\(q.count)); sunucu gelince kaydedilecek")
    }

    func kuyrukBosalt() {
        guard let ist = istemci,
              var q = UserDefaults.standard.array(forKey: "yakala-bekleyen") as? [[String: String]],
              let ilk = q.first else { return }
        ist.istek("/api/uyg/yakala", yontem: "POST", govde: ["metin": ilk["metin"] ?? "", "kimlik": ilk["kimlik"] ?? ""], sure: 8) { [weak self] kod, _ in
            guard kod == 200 || kod == 400 else { return }   // 400: boş metin, tekrar denemenin anlamı yok
            q.removeFirst()
            UserDefaults.standard.set(q, forKey: "yakala-bekleyen")
            if kod == 200 { self?.yakalandi() }
            self?.kuyrukBosalt()
        }
    }

    // MARK: eşitleme sağlığı

    func saglikYenile() {
        guard let ist = istemci else { return }
        ist.istek("/api/uyg/saglik", sure: 10) { [weak self] kod, j in
            guard let self = self else { return }
            self.saglikSon = kod == 200 ? j : ["uyari": [["kod": "sunucu", "ileti": "Sunucu sağlık sorgusuna yanıt vermiyor"]]]
            self.saglikMenuKur()
        }
    }

    func uyarilar() -> [[String: Any]] { saglikSon["uyari"] as? [[String: Any]] ?? [] }

    func saglikOzeti() -> String {
        if saglikSon.isEmpty { return "Henüz kontrol edilmedi" }
        let n = uyarilar().count
        return n == 0 ? "Her şey yerinde" : "\(n) uyarı"
    }

    func saglikMenuKur() {
        let u = uyarilar()
        simge.button?.title = u.isEmpty ? "" : " \(u.count)"
        simge.button?.imagePosition = u.isEmpty ? .imageOnly : .imageLeft
        guard let o = saglikOgesi else { return }
        o.title = saglikSon.isEmpty ? "Eşitleme: kontrol ediliyor…" : (u.isEmpty ? "Eşitleme: ✓ sağlıklı" : "Eşitleme: ⚠︎ \(u.count) uyarı")
        let m = NSMenu()
        for x in u {
            let it = NSMenuItem(title: (x["ileti"] as? String) ?? "?", action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
        }
        if u.contains(where: { $0["onar"] as? Bool == true }) {
            m.addItem(oge("Gelecek tarihli kayıtları düzelt…", #selector(saglikOnar)))
        }
        if !u.isEmpty { m.addItem(.separator()) }
        let b = saglikSon["bilgi"] as? [String: Any] ?? [:]
        if let z = b["son_yazim"] as? Double ?? (b["son_yazim"] as? Int).map(Double.init) {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            let it = NSMenuItem(title: "Son yazım: " + f.string(from: Date(timeIntervalSince1970: z / 1000)), action: nil, keyEquivalent: "")
            it.isEnabled = false; m.addItem(it)
        }
        for ot in b["oteki"] as? [[String: Any]] ?? [] {
            let sy = (ot["sayfalar"] as? [String] ?? []).joined(separator: ", ")
            let it = NSMenuItem(title: "Öteki Mac açık: \(ot["makine"] as? String ?? "?") (\(sy))", action: nil, keyEquivalent: "")
            it.isEnabled = false; m.addItem(it)
        }
        if let mb = b["serbest_mb"] as? Int {
            let it = NSMenuItem(title: String(format: "Boş disk: %.1f GB", Double(mb) / 1000), action: nil, keyEquivalent: "")
            it.isEnabled = false; m.addItem(it)
        }
        m.addItem(oge("Şimdi yeniden kontrol et", #selector(saglikTazele)))
        o.submenu = m
    }

    @objc func saglikTazele() { saglikYenile() }

    func saglikGoster() {
        let a = NSAlert()
        let u = uyarilar()
        a.messageText = u.isEmpty ? "Eşitleme sağlıklı" : "\(u.count) uyarı"
        a.informativeText = u.isEmpty ? "iCloud'daki tezgâh durumunda sorun görünmüyor."
            : u.map { "• " + ((($0["ileti"]) as? String) ?? "?") }.joined(separator: "\n")
        a.runModal()
    }

    @objc func saglikOnar() {
        let a = NSAlert()
        a.messageText = "Gelecek tarihli kayıtlar düzeltilsin mi?"
        a.informativeText = "Saati ileri olan bir Mac, kayıtlara gelecek bir zaman damgası yazmış; bu yüzden bu Mac'in yeni yazımları onların üstüne geçemiyor. Kayıtların içeriği aynen kalır, yalnız zaman damgası şimdiye çekilir."
        a.addButton(withTitle: "Düzelt")
        a.addButton(withTitle: "Vazgeç")
        guard a.runModal() == .alertFirstButtonReturn, let ist = istemci else { return }
        ist.istek("/api/uyg/saglik-onar", yontem: "POST", sure: 15) { [weak self] kod, j in
            self?.durumYaz(kod == 200 ? "\(j["duzeltilen"] ?? 0) kayıt düzeltildi" : "Düzeltilemedi")
            self?.saglikYenile()
        }
    }

    // MARK: yazdır, dock menüsü, tezgah:// bağlantıları

    @objc func yazdir() {
        guard let w = etkinGorunum() else { return }
        let op = w.printOperation(with: NSPrintInfo.shared)
        op.view?.frame = w.bounds
        op.runModal(for: pencere, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func applicationDockMenu(_ s: NSApplication) -> NSMenu? {
        let m = NSMenu()
        for s in SAYFALAR {
            let it = oge(s.ad, #selector(menudenAc(_:)))
            it.representedObject = s.kod
            it.image = NSImage(systemSymbolName: s.simge, accessibilityDescription: s.ad)
            m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(oge("Hızlı fikir yakala…", #selector(yakalaAc)))
        m.addItem(oge("Komut paleti…", #selector(paletAc)))
        return m
    }

    func application(_ a: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == "tezgah" {
            switch u.host ?? "" {
            case "yakala": yakalaAc()
            case "palet": paletAc()
            case let h where SAYFALAR.contains { $0.kod == h }:
                pencereGoster(); goster(h)
            default: pencereGoster()
            }
        }
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

let app = NSApplication.shared
let temsilci = MainActor.assumeIsolated { Uygulama() }
app.delegate = temsilci
app.run()
