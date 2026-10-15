// Tezgâh — yardımcı parçalar: uygulama anahtarı, sunucu istemcisi, komut paleti, hızlı yakalama
// paneli ve genel kısayol. main.swift'e bağımlı değildir; her şey kapanışlarla bağlanır.

import Carbon.HIToolbox
import Cocoa

// MARK: - Uygulama anahtarı (sunucunun /api/uyg/* uçları için; iCloud'da değil)

let ANAHTAR_YOL = NSHomeDirectory() + "/Library/Application Support/Tezgah/uygulama.anahtar"

func uygulamaAnahtari() -> String {
    if let s = try? String(contentsOfFile: ANAHTAR_YOL, encoding: .utf8) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 16 { return t }
    }
    var b = [UInt8](repeating: 0, count: 24)
    _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
    let t = b.map { String(format: "%02x", $0) }.joined()
    let kl = (ANAHTAR_YOL as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: kl, withIntermediateDirectories: true)
    try? t.write(toFile: ANAHTAR_YOL, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ANAHTAR_YOL)
    return t
}

// MARK: - Sunucu istemcisi

struct Istemci {
    let port: Int
    let anahtar = uygulamaAnahtari()

    /// kod 0 = ağ hatası / zaman aşımı
    func istek(_ yol: String, yontem: String = "GET", govde: [String: Any]? = nil, sure: TimeInterval = 4,
               tamam: @escaping (Int, [String: Any]) -> Void) {
        guard let u = URL(string: "http://127.0.0.1:\(port)\(yol)") else { return tamam(0, [:]) }
        var r = URLRequest(url: u)
        r.httpMethod = yontem
        r.timeoutInterval = sure
        r.setValue(anahtar, forHTTPHeaderField: "X-Tezgah-Uyg")
        if let g = govde {
            r.httpBody = try? JSONSerialization.data(withJSONObject: g)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            let kod = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let j = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            DispatchQueue.main.async { tamam(kod, j) }
        }.resume()
    }
}

// MARK: - Genel kısayol (Carbon: izin istemez)

nonisolated(unsafe) var genelKisayolEylemi: (() -> Void)?

func genelKisayolKaydet(tus: Int, degistirici: Int, eylem: @escaping () -> Void) {
    genelKisayolEylemi = eylem
    var tur = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { genelKisayolEylemi?() }
        return noErr
    }, 1, &tur, nil, nil)
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(tus), UInt32(degistirici), EventHotKeyID(signature: OSType(0x545A4748), id: 1),
                        GetApplicationEventTarget(), 0, &ref)
}

// MARK: - Yüzen panel tabanı

class YuzenPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(boy: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: boy),
                   styleMask: [.titled, .fullSizeContentView, .closable], backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        contentView = fx
    }

    func ortala() {
        if let e = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: e.midX - frame.width / 2, y: e.minY + e.height * 0.62 - frame.height / 2))
        }
    }

    override func resignKey() {
        super.resignKey()
        if isVisible && !(attachedSheet != nil) { kapanirken(); orderOut(nil) }
    }

    func kapanirken() {}
}

// MARK: - Komut paleti (⌘K)

struct Komut {
    let baslik: String
    let alt: String
    let simge: String
    let eylem: () -> Void
}

func sade(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr"))
}

final class Palet: YuzenPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var komutlar: () -> [Komut] = { [] }
    var notAra: ((String, @escaping ([Komut]) -> Void) -> Void)?
    private let alan = NSTextField()
    private let tablo = NSTableView()
    private var gorunen: [Komut] = []
    private var notlar: [Komut] = []
    private var bekleyen: DispatchWorkItem?
    private var surum = 0

    init() {
        super.init(boy: NSSize(width: 620, height: 400))
        let fx = contentView!
        alan.placeholderString = "Tezgâh, eylem ya da not ara…"
        alan.font = .systemFont(ofSize: 20, weight: .light)
        alan.isBordered = false
        alan.drawsBackground = false
        alan.focusRingType = .none
        alan.delegate = self
        alan.translatesAutoresizingMaskIntoConstraints = false
        let kol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("k"))
        kol.width = 580
        tablo.addTableColumn(kol)
        tablo.headerView = nil
        tablo.rowHeight = 44
        tablo.backgroundColor = .clear
        tablo.dataSource = self
        tablo.delegate = self
        tablo.target = self
        tablo.doubleAction = #selector(calistir)
        tablo.selectionHighlightStyle = .regular
        let kay = NSScrollView()
        kay.documentView = tablo
        kay.drawsBackground = false
        kay.hasVerticalScroller = true
        kay.translatesAutoresizingMaskIntoConstraints = false
        let cizgi = NSBox()
        cizgi.boxType = .separator
        cizgi.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(alan); fx.addSubview(cizgi); fx.addSubview(kay)
        NSLayoutConstraint.activate([
            alan.topAnchor.constraint(equalTo: fx.topAnchor, constant: 22),
            alan.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 22),
            alan.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -22),
            cizgi.topAnchor.constraint(equalTo: alan.bottomAnchor, constant: 14),
            cizgi.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            cizgi.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            kay.topAnchor.constraint(equalTo: cizgi.bottomAnchor, constant: 4),
            kay.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 8),
            kay.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -8),
            kay.bottomAnchor.constraint(equalTo: fx.bottomAnchor, constant: -8),
        ])
    }

    func ac() {
        alan.stringValue = ""
        notlar = []
        yenile()
        ortala()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(alan)
    }

    private func yenile() {
        let q = sade(alan.stringValue).split(separator: " ").map(String.init)
        let hepsi = komutlar()
        let eslesen = q.isEmpty ? hepsi : hepsi.filter { k in
            let h = sade(k.baslik + " " + k.alt)
            return q.allSatisfy { h.contains($0) }
        }
        gorunen = eslesen + notlar
        tablo.reloadData()
        if !gorunen.isEmpty { tablo.selectRowIndexes([0], byExtendingSelection: false) }
    }

    func controlTextDidChange(_ n: Notification) {
        yenile()
        bekleyen?.cancel()
        let q = alan.stringValue.trimmingCharacters(in: .whitespaces)
        surum += 1
        let bu = surum
        notlar = []
        guard q.count >= 2, let ara = notAra else { return }
        let w = DispatchWorkItem { [weak self] in
            ara(q) { sonuc in
                guard let self = self, bu == self.surum else { return }   // eski yanıt yeni aramanın üstüne yazmaz
                self.notlar = sonuc
                self.yenile()
            }
        }
        bekleyen = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: w)
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy s: Selector) -> Bool {
        switch s {
        case #selector(NSResponder.moveDown(_:)): tasi(1); return true
        case #selector(NSResponder.moveUp(_:)): tasi(-1); return true
        case #selector(NSResponder.insertNewline(_:)): calistir(); return true
        case #selector(NSResponder.cancelOperation(_:)): orderOut(nil); return true
        default: return false
        }
    }

    private func tasi(_ d: Int) {
        guard !gorunen.isEmpty else { return }
        let i = max(0, min(gorunen.count - 1, tablo.selectedRow + d))
        tablo.selectRowIndexes([i], byExtendingSelection: false)
        tablo.scrollRowToVisible(i)
    }

    @objc private func calistir() {
        let i = tablo.selectedRow
        guard i >= 0, i < gorunen.count else { return }
        let k = gorunen[i]
        orderOut(nil)
        k.eylem()
    }

    func numberOfRows(in t: NSTableView) -> Int { gorunen.count }

    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let k = gorunen[row]
        let h = NSTableCellView()
        let im = NSImageView(image: NSImage(systemSymbolName: k.simge, accessibilityDescription: nil) ?? NSImage())
        im.contentTintColor = .secondaryLabelColor
        let b = NSTextField(labelWithString: k.baslik)
        b.font = .systemFont(ofSize: 14, weight: .medium)
        b.lineBreakMode = .byTruncatingTail
        let a = NSTextField(labelWithString: k.alt)
        a.font = .systemFont(ofSize: 11)
        a.textColor = .secondaryLabelColor
        a.lineBreakMode = .byTruncatingTail
        let st = NSStackView(views: [b, a])
        st.orientation = .vertical
        st.alignment = .leading
        st.spacing = 1
        for v in [im, st] { v.translatesAutoresizingMaskIntoConstraints = false; h.addSubview(v) }
        NSLayoutConstraint.activate([
            im.leadingAnchor.constraint(equalTo: h.leadingAnchor, constant: 12),
            im.centerYAnchor.constraint(equalTo: h.centerYAnchor),
            im.widthAnchor.constraint(equalToConstant: 22),
            st.leadingAnchor.constraint(equalTo: im.trailingAnchor, constant: 12),
            st.trailingAnchor.constraint(equalTo: h.trailingAnchor, constant: -12),
            st.centerYAnchor.constraint(equalTo: h.centerYAnchor),
        ])
        return h
    }
}

// MARK: - Hızlı yakalama

final class Yakala: YuzenPanel, NSTextViewDelegate {
    /// metin → (sonuç ileti, başarı). Başarısızsa metin panelde kalır.
    var kaydet: ((String, @escaping (String, Bool) -> Void) -> Void)?
    private let metin = NSTextView()
    private let durum = NSTextField(labelWithString: "")
    private let taslakAnahtar = "yakala-taslak"
    private var kaydediyor = false

    init() {
        super.init(boy: NSSize(width: 560, height: 230))
        let fx = contentView!
        let baslik = NSTextField(labelWithString: "Fikir")
        baslik.font = .systemFont(ofSize: 11, weight: .semibold)
        baslik.textColor = .secondaryLabelColor
        metin.font = .systemFont(ofSize: 16)
        metin.drawsBackground = false
        metin.isRichText = false
        metin.isAutomaticQuoteSubstitutionEnabled = false
        metin.isAutomaticDashSubstitutionEnabled = false
        metin.textContainerInset = NSSize(width: 0, height: 4)
        metin.delegate = self
        let kay = NSScrollView()
        kay.documentView = metin
        kay.drawsBackground = false
        kay.hasVerticalScroller = true
        durum.font = .systemFont(ofSize: 11)
        durum.textColor = .secondaryLabelColor
        durum.stringValue = "⌘↩ kaydet · Esc kapat (yazdığın kaybolmaz)"
        for v in [baslik, kay, durum] { v.translatesAutoresizingMaskIntoConstraints = false; fx.addSubview(v) }
        NSLayoutConstraint.activate([
            baslik.topAnchor.constraint(equalTo: fx.topAnchor, constant: 18),
            baslik.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 22),
            kay.topAnchor.constraint(equalTo: baslik.bottomAnchor, constant: 6),
            kay.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 22),
            kay.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -22),
            kay.bottomAnchor.constraint(equalTo: durum.topAnchor, constant: -8),
            durum.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 22),
            durum.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -22),
            durum.bottomAnchor.constraint(equalTo: fx.bottomAnchor, constant: -14),
        ])
    }

    func ac() {
        metin.string = UserDefaults.standard.string(forKey: taslakAnahtar) ?? ""
        durum.stringValue = metin.string.isEmpty ? "⌘↩ kaydet · Esc kapat (yazdığın kaybolmaz)" : "Yarım kalan taslak geri geldi · ⌘↩ kaydet"
        ortala()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(metin)
        metin.selectAll(nil)
    }

    override func kapanirken() { UserDefaults.standard.set(metin.string, forKey: taslakAnahtar) }

    func textDidChange(_ n: Notification) { UserDefaults.standard.set(metin.string, forKey: taslakAnahtar) }

    func textView(_ t: NSTextView, doCommandBy s: Selector) -> Bool {
        if s == #selector(NSResponder.cancelOperation(_:)) { kapanirken(); orderOut(nil); return true }
        return false
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 36 && e.modifierFlags.contains(.command) { gonder() } else { super.keyDown(with: e) }
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.keyCode == 36 && e.modifierFlags.contains(.command) { gonder(); return true }
        return super.performKeyEquivalent(with: e)
    }

    private func gonder() {
        let m = metin.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { durum.stringValue = "Boş fikir kaydedilmez."; return }
        guard !kaydediyor else { return }     // çift ⌘↩ iki not açmasın
        kaydediyor = true
        durum.stringValue = "Kaydediliyor…"
        kaydet?(m) { [weak self] ileti, tamam in
            guard let self = self else { return }
            self.kaydediyor = false
            if tamam {
                self.metin.string = ""
                UserDefaults.standard.removeObject(forKey: self.taslakAnahtar)
                self.orderOut(nil)
            } else {
                self.durum.stringValue = ileti      // panel açık kalır, metin yerinde
            }
        }
    }
}
