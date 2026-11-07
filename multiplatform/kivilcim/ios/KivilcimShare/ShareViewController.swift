// Paylaş › Kıvılcım (2026-11-04): Chrome, X, Safari, GitHub ya da herhangi bir uygulamadan gelen bağlantıyı, seçili metni,
// yazılı ve sesli notla birlikte bir "işaret" olarak saklar. İşaret önce App Group'a yazılır (isaret/<ay>/<id>.json + .m4a);
// Kıvılcım uygulaması açılınca vault'a gönderir, Mac de telefon bağlıyken doğrudan alır. Sayfanın metnini Mac çeker
// (Safari'de sayfa metni de gelir). Yapay zekâ sohbet bağlantıları da aynı yoldan gelir.
// Sesli not: iOS Paylaş uzantısına mikrofon vermiyor (ilk sürümde kayıt boş çıktı, 557 bayt). "Kaydet ve sesli not"
// işareti `ses_bekliyor` ile yazar ve Kıvılcım'ı kivilcim://isaret-ses/<id> ile açar; kaydı uygulama yapar.
import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = IsaretModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.bitir = { [weak self] iptal in
            if iptal { self?.extensionContext?.cancelRequest(withError: NSError(domain: "Kivilcim", code: 0)) }
            else { self?.extensionContext?.completeRequest(returningItems: nil) }
        }
        model.uygulamayiAc = { [weak self] url in self?.ac(url) ?? false }
        let h = UIHostingController(rootView: IsaretView(model: model))
        addChild(h)
        h.view.frame = view.bounds
        h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(h.view)
        h.didMove(toParent: self)
        Task { await model.yukle(extensionContext?.inputItems as? [NSExtensionItem] ?? []) }
    }

    /// Opens the containing app. Extensions have no UIApplication.shared; the app object is reached through the
    /// responder chain and its open(_:options:completionHandler:) is called dynamically.
    @discardableResult
    func ac(_ url: URL) -> Bool {
        var r: UIResponder? = self
        let sel = NSSelectorFromString("openURL:options:completionHandler:")
        while let x = r {
            if x.responds(to: sel), x.isKind(of: NSClassFromString("UIApplication")!) {
                typealias Ac = @convention(c) (AnyObject, Selector, URL, NSDictionary, Any?) -> Void
                let f = unsafeBitCast(x.method(for: sel), to: Ac.self)
                f(x, sel, url, NSDictionary(), nil)
                return true
            }
            r = x.next
        }
        return false
    }
}

@MainActor
final class IsaretModel: ObservableObject {
    @Published var url = ""
    @Published var baslik = ""
    @Published var secili = ""
    @Published var metin = ""
    @Published var not = ""
    @Published var hata: String?
    var bitir: (Bool) -> Void = { _ in }
    var uygulamayiAc: (URL) -> Bool = { _ in false }

    let id: String = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(f.string(from: Date()))-iphone-" + String(UUID().uuidString.prefix(4)).lowercased()
    }()

    static var klasor: URL? {
        guard let g = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.fatihgocgun.kivilcim") else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"
        let u = g.appendingPathComponent("isaret/\(f.string(from: Date()))")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    var tur: String {
        let h = (URL(string: url)?.host ?? "").replacingOccurrences(of: "www.", with: "")
        if ["x.com", "twitter.com", "mobile.twitter.com"].contains(h) { return url.contains("/i/grok") ? "Yapay zekâ sohbeti" : "X postu" }
        if h.hasSuffix("github.com") || h == "raw.githubusercontent.com" { return "GitHub" }
        if ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com", "g.co", "share.gemini.google", "grok.com",
            "perplexity.ai", "chat.deepseek.com", "copilot.microsoft.com", "chat.mistral.ai", "aistudio.google.com"].contains(h) {
            return "Yapay zekâ sohbeti"
        }
        if h.contains("youtube") || h == "youtu.be" { return "Video" }
        return url.isEmpty ? "Metin" : "Bağlantı"
    }

    func yukle(_ items: [NSExtensionItem]) async {
        for item in items {
            if baslik.isEmpty, let t = item.attributedContentText?.string, !t.isEmpty { baslik = t }
            for p in item.attachments ?? [] {
                if p.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let d = try? await p.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? [String: Any],
                   let r = d[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                    url = (r["url"] as? String) ?? url
                    baslik = (r["baslik"] as? String) ?? baslik
                    secili = (r["secili"] as? String) ?? secili
                    metin = (r["metin"] as? String) ?? metin
                } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    if u.isFileURL { if let s = try? String(contentsOf: u, encoding: .utf8) { metin = String(s.prefix(300_000)) } }
                    else if url.isEmpty { url = u.absoluteString }
                } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let s = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    // X and many apps share "text + link": keep the link as the url, the rest as the selection
                    if url.isEmpty, let m = s.range(of: #"https?://\S+"#, options: .regularExpression) {
                        url = String(s[m])
                        let kalan = s.replacingCharacters(in: m, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !kalan.isEmpty && secili.isEmpty { secili = kalan }
                    } else if secili.isEmpty { secili = s }
                }
            }
        }
        if baslik == url { baslik = "" }
    }

    func kaydet(sesli: Bool = false) {
        guard let k = IsaretModel.klasor else { hata = "App Group açılamadı"; return }
        var d: [String: Any] = [
            "id": id, "zaman": ISO8601DateFormatter.yerel.string(from: Date()), "cihaz": "iphone", "kaynak": "paylas",
            "url": url, "baslik": baslik, "secili": secili, "metin": metin,
            "not": not.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if sesli { d["ses_bekliyor"] = true }
        do {
            let v = try JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted])
            try v.write(to: k.appendingPathComponent(id + ".json"), options: .atomic)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if sesli { _ = uygulamayiAc(URL(string: "kivilcim://isaret-ses/\(id)?ay=\(k.lastPathComponent)")!) }
            bitir(false)
        } catch { hata = error.localizedDescription }
    }

    func vazgec() { bitir(true) }
}

extension ISO8601DateFormatter {
    static let yerel: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.timeZone = .current; f.formatOptions = [.withInternetDateTime]; return f
    }()
}

struct IsaretView: View {
    @ObservedObject var model: IsaretModel
    @FocusState private var odak: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Başlık", text: $model.baslik, axis: .vertical).font(.headline)
                    if !model.url.isEmpty {
                        Label(URL(string: model.url)?.host ?? model.url, systemImage: "link")
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !model.secili.isEmpty {
                        Text(model.secili).font(.callout).italic().lineLimit(5)
                    }
                } header: { Text(model.tur) }
                Section("Notun") {
                    TextField("Neden işaretliyorsun, ne yapacaksın?", text: $model.not, axis: .vertical)
                        .lineLimit(3...8).focused($odak)
                }
                Section {
                    Button { model.kaydet(sesli: true) } label: {
                        Label("İşaretle ve sesli not ekle", systemImage: "mic.fill")
                    }.tint(.orange)
                } footer: {
                    Text("Sesli not Kıvılcım'da kaydedilir: işaret kaydedilir, uygulama bu işaret için kayıt ekranıyla açılır. Açılmazsa Kıvılcım'ı aç, kayıt ekranı kendisi gelir.")
                }
                if let h = model.hata { Text(h).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Kıvılcım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { model.vazgec() } }
                ToolbarItem(placement: .confirmationAction) { Button("İşaretle") { model.kaydet() }.bold() }
            }
        }
        .onAppear { odak = true }
    }
}
