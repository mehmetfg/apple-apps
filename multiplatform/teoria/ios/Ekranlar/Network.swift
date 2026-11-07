// PDM Ağı bridge (iPhone). The package is linked to the iOS app target only; the Mac app compiles this file
// without it, where every call is a no-op. One bus for the app: "opened today" + sync on becoming active,
// live state out (the book in the reader, TTS playing or not), live state in (what Wise Path has open).
import SwiftUI
#if canImport(PDMBus)
import PDMBus
#endif

/// The book another app has open now (read from the shared container, never from iCloud).
struct ElsewhereBook: Equatable {
    var title: String
    var percent: Int?
    var link: URL?
    var teoriaBook: String?     // the same book's id in Teoria's library, when the other app knows it
}

@MainActor
enum Network {
    #if canImport(PDMBus)
    /// The vault ROOT is the folder the user picked for Teoria (Kasa keeps its bookmark under this key).
    private static let bus = PDMBus(app: "teoria", vaultRoot: {
        guard let v = UserDefaults.standard.data(forKey: "teoria.kasa.yerimi") else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: v, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    })
    #endif

    /// After the app's own sync, each time it becomes active.
    static func becameActive() async {
        #if canImport(PDMBus)
        bus.emitOpenedToday()
        _ = await bus.sync()
        #endif
    }

    /// The book open in the reader; `playing` while it is read aloud.
    static func publish(book id: String, title: String, percent: Int?, playing: Bool) {
        #if canImport(PDMBus)
        bus.publishLive(PDMLive(app: "teoria", kind: "book", id: id, title: title,
                                progress: percent.map { Double($0) / 100 }, active: playing,
                                link: "teoria://kitap/\(id)", refs: isWisePathID(id) ? ["wisepath": id] : nil))
        #endif
    }

    /// What Wise Path has open (last 7 days), or nil.
    static func wisePath() -> ElsewhereBook? {
        #if canImport(PDMBus)
        guard let l = PDMBus.live(of: "wisepath", maxAge: 7 * 86_400), let t = l.title, !t.isEmpty else { return nil }
        return ElsewhereBook(title: t, percent: l.progress.map { Int(($0 * 100).rounded()) },
                             link: l.link.flatMap { URL(string: $0) }, teoriaBook: l.refs?["teoria"])
        #else
        return nil
        #endif
    }

    static func isWisePathID(_ id: String) -> Bool { id.hasPrefix("vr-") && id.count > 3 }

    /// wisepath://book/<vr id> — Wise Path accepts the vr- prefixed form.
    static func wisePathLink(_ id: String) -> URL? {
        guard isWisePathID(id), let e = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "wisepath://book/\(e)")
    }

    /// kivilcim://kaydet?topic=<book id> — Kıvılcım starts a recording about this book.
    static func talkLink(_ id: String) -> URL? {
        var c = URLComponents()
        c.scheme = "kivilcim"; c.host = "kaydet"
        c.queryItems = [URLQueryItem(name: "topic", value: id)]
        return c.url
    }
}

/// Bugün (iPhone): one compact row for the book open in Wise Path.
struct ElsewhereRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @ObservedObject private var library = LibraryStore.shared
    @State private var book: ElsewhereBook?

    var body: some View {
        Group {
            if let b = book {
                HStack(spacing: 10) {
                    Image(systemName: "headphones").foregroundStyle(Tema.ikincil)
                    Text("Wise Path'te: \(b.title)" + (b.percent.map { " · %\($0)" } ?? ""))
                        .font(.footnote).foregroundStyle(Tema.metin).lineLimit(1)
                    Spacer(minLength: 4)
                    if let id = b.teoriaBook, library.entry(id) != nil, let u = URL(string: "teoria://kitap/\(id)") {
                        Button("Teoria'da aç") { openURL(u) }
                    }
                    if let u = b.link { Button("Sürdür") { openURL(u) } }
                }
                .font(.footnote.weight(.semibold)).buttonStyle(.borderless).tint(Tema.vurgu)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Tema.yuzey))
            }
        }
        .onAppear { refresh() }
        .onChange(of: phase) { _, p in if p == .active { refresh() } }
    }

    private func refresh() {
        let b = Network.wisePath()
        if b != book { book = b }
    }
}
