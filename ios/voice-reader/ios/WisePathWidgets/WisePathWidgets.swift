// Wise Path's widgets (2026-10-28), read from the snapshot the app writes (Shared/WidgetSnapshot.swift):
// Okumaya devam (the book to go on with; small, medium, lock screen) · Okuduklarım (the books being read, each a
// link) · Okuma (today and the week) · Kitap ve alıntı (a book chosen in the widget's settings, or the current one:
// its cover and its marked passages, one at a time, changing every half hour and with the → key).
import WidgetKit
import SwiftUI
import AppIntents

@main
struct WisePathWidgets: WidgetBundle {
    var body: some Widget {
        ContinueWidget()
        ReadingWidget()
        StatsWidget()
        QuoteWidget()
    }
}

// MARK: - the look

private enum Look {
    static let amber = Color(red: 0.93, green: 0.62, blue: 0.22)
    static func paper(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.09), Color(red: 0.07, green: 0.06, blue: 0.06)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(red: 0.99, green: 0.97, blue: 0.93), Color(red: 0.95, green: 0.91, blue: 0.84)], startPoint: .top, endPoint: .bottom)
    }
}

private struct Cover: View {
    let id: UUID
    var width: CGFloat
    var body: some View {
        Group {
            if let u = WidgetShared.coverURL(id), let img = UIImage(contentsOfFile: u.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.45), Color(red: 0.4, green: 0.3, blue: 0.6)], startPoint: .top, endPoint: .bottom)
                    .overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.7)))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

private struct Bar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Look.amber).frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 4)
    }
}

private struct Paper: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { Look.paper(scheme) }
    }
}

private struct Empty: View {
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(Look.amber)
            Text(text).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: - one snapshot for the plain widgets

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snap: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snap: WidgetShared.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // the app asks for a redraw whenever it changes something; this is only the fallback
        completion(Timeline(entries: [SnapshotEntry(date: .now, snap: WidgetShared.load())], policy: .after(.now.addingTimeInterval(1800))))
    }
}

// MARK: - Okumaya devam

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind.continue, provider: SnapshotProvider()) { e in ContinueView(entry: e) }
            .configurationDisplayName("Okumaya devam")
            .description("Kaldığın kitap; dokun, kaldığın yerden okusun.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct ContinueView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        Group {
            if let b = entry.snap?.current {
                switch family {
                case .accessoryCircular:
                    Gauge(value: b.progress) { Image(systemName: "book.fill") } currentValueLabel: { Text("\(Int(b.progress * 100))") }
                        .gaugeStyle(.accessoryCircularCapacity)
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Okumaya devam", systemImage: "play.fill").font(.caption2.weight(.semibold))
                        Text(b.title).font(.headline).lineLimit(1)
                        ProgressView(value: b.progress)
                    }
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Cover(id: b.id, width: 46)
                            Spacer()
                            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Look.amber)
                        }
                        Spacer(minLength: 0)
                        Text(b.title).font(.system(size: 13, weight: .semibold, design: .serif)).lineLimit(2)
                        Bar(value: b.progress)
                        Text("%\(Int(b.progress * 100))").font(.caption2).foregroundStyle(.secondary)
                    }
                default:
                    HStack(spacing: 14) {
                        Cover(id: b.id, width: 74)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("OKUMAYA DEVAM").font(.caption2.weight(.bold)).foregroundStyle(Look.amber)
                            Text(b.title).font(.system(size: 16, weight: .semibold, design: .serif)).lineLimit(2)
                            if let a = b.author { Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(minLength: 0)
                            Bar(value: b.progress)
                            HStack {
                                Text(b.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(Look.amber)
                            }
                        }
                    }
                }
            } else {
                Empty(text: "Bir kitap aç, burada kalsın.")
            }
        }
        .widgetURL(URL(string: "wisepath://resume"))
        .modifier(Paper())
    }
}

// MARK: - Okuduklarım

struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind.reading, provider: SnapshotProvider()) { e in ReadingView(entry: e) }
            .configurationDisplayName("Okuduklarım")
            .description("Süren kitapların; birine dokun, o açılsın.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ReadingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        let books = Array((entry.snap?.reading ?? []).prefix(family == .systemLarge ? 6 : 3))
        Group {
            if books.isEmpty {
                Empty(text: "Süren kitap yok.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OKUDUKLARIM").font(.caption2.weight(.bold)).foregroundStyle(Look.amber)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3), spacing: 10) {
                        ForEach(books) { b in
                            Link(destination: URL(string: "wisepath://book/\(b.id.uuidString)")!) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Cover(id: b.id, width: family == .systemLarge ? 70 : 50)
                                    if family == .systemLarge {
                                        Text(b.title).font(.system(size: 11, weight: .medium, design: .serif)).lineLimit(2)
                                    }
                                    Bar(value: b.progress).frame(width: family == .systemLarge ? 70 : 50)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .modifier(Paper())
    }
}

// MARK: - Okuma (statistics)

struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind.stats, provider: SnapshotProvider()) { e in StatsView(entry: e) }
            .configurationDisplayName("Okuma")
            .description("Bugün ne kadar dinledin; son yedi gün.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct StatsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private func minutes(_ m: Double) -> String {
        m >= 60 ? "\(Int(m) / 60) sa \(Int(m) % 60) dk" : "\(Int(m.rounded())) dk"
    }

    var body: some View {
        let s = entry.snap
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Bugün", systemImage: "headphones").font(.caption2.weight(.semibold))
                    Text(minutes(s?.todayMinutes ?? 0)).font(.headline)
                    Text("\(Int((s?.todayPages ?? 0).rounded())) sayfa").font(.caption2)
                }
            case .systemSmall:
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUGÜN").font(.caption2.weight(.bold)).foregroundStyle(Look.amber)
                    Text(minutes(s?.todayMinutes ?? 0)).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                    Text("\(Int((s?.todayPages ?? 0).rounded())) sayfa").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    week(s?.week ?? [], height: 34)
                }
            default:
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BUGÜN DİNLEDİĞİN").font(.caption2.weight(.bold)).foregroundStyle(Look.amber)
                        Text(minutes(s?.todayMinutes ?? 0)).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("\(Int((s?.todayPages ?? 0).rounded())) sayfa").font(.caption).foregroundStyle(.secondary)
                        if let c = s?.current { Text(c.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    week(s?.week ?? [], height: 70)
                }
            }
        }
        .widgetURL(URL(string: "wisepath://stats"))
        .modifier(Paper())
    }

    private func week(_ days: [WidgetSnapshot.Day], height: CGFloat) -> some View {
        let peak = max(1, days.map(\.minutes).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                VStack(spacing: 2) {
                    Capsule().fill(d.today ? Look.amber : Color.primary.opacity(0.35))
                        .frame(width: 7, height: max(3, (height - 12) * d.minutes / peak))
                    Text(d.label).font(.system(size: 7)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: - Kitap ve alıntı

struct BookEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kitap"
    static var defaultQuery = BookQuery()
    let id: UUID
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct BookQuery: EntityQuery {
    private func all() -> [BookEntity] {
        (WidgetShared.load()?.books ?? []).map { BookEntity(id: $0.id, title: $0.title) }
    }
    func entities(for identifiers: [UUID]) async throws -> [BookEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [BookEntity] { all() }
}

struct QuoteConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Kitap ve alıntı"
    static var description = IntentDescription("Bir kitabın kapağı ve işaretlediğin cümleler.")
    @Parameter(title: "Kitap (boşsa okuduğun kitap)")
    var book: BookEntity?
}

/// The → key on the widget: the next marked passage, at once.
struct NextQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Sonraki alıntı"
    func perform() async throws -> some IntentResult {
        WidgetShared.quoteShift += 1
        return .result()
    }
}

struct QuoteEntry: TimelineEntry {
    let date: Date
    let book: WidgetSnapshot.Book?
    let quote: String?
    let index: Int
}

struct QuoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(date: .now, book: nil, quote: "Okuduğun kitaptan işaretlediğin bir cümle burada durur.", index: 0)
    }

    private func book(_ c: QuoteConfiguration) -> WidgetSnapshot.Book? {
        let s = WidgetShared.load()
        if let id = c.book?.id { return s?.books.first { $0.id == id } }
        if let cur = s?.current, !cur.quotes.isEmpty { return cur }
        return s?.books.first
    }

    func snapshot(for configuration: QuoteConfiguration, in context: Context) async -> QuoteEntry {
        let b = book(configuration)
        return QuoteEntry(date: .now, book: b, quote: b?.quotes.first, index: 0)
    }

    /// One passage every half hour for six hours, starting from where the → key left it.
    func timeline(for configuration: QuoteConfiguration, in context: Context) async -> Timeline<QuoteEntry> {
        let b = book(configuration)
        let quotes = b?.quotes ?? []
        let shift = WidgetShared.quoteShift
        let base = Int(Date.now.timeIntervalSince1970 / 1800)
        let entries = (0..<12).map { k -> QuoteEntry in
            let i = quotes.isEmpty ? 0 : (base + k + shift) % quotes.count
            return QuoteEntry(date: .now.addingTimeInterval(Double(k) * 1800), book: b, quote: quotes.isEmpty ? nil : quotes[i], index: i)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct QuoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetShared.kind.quote, intent: QuoteConfiguration.self, provider: QuoteProvider()) { e in QuoteView(entry: e) }
            .configurationDisplayName("Kitap ve alıntı")
            .description("Seçtiğin kitabın kapağı ve işaretlediğin cümleler; yarım saatte bir ya da → ile değişir.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct QuoteView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuoteEntry

    var body: some View {
        Group {
            if let b = entry.book, let q = entry.quote {
                switch family {
                case .accessoryRectangular:
                    Text("“\(q)”").font(.caption).lineLimit(3)
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“\(q)”").font(.system(size: 13, design: .serif)).lineLimit(6).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        HStack {
                            Text(b.title).font(.caption2.weight(.semibold)).foregroundStyle(Look.amber).lineLimit(1)
                            Spacer(minLength: 0)
                            next
                        }
                    }
                case .systemLarge:
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            Cover(id: b.id, width: 86)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(b.title).font(.system(size: 17, weight: .semibold, design: .serif)).lineLimit(3)
                                if let a = b.author { Text(a).font(.caption).foregroundStyle(.secondary) }
                                Text("\(entry.index + 1) / \(b.quotes.count) işaret").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text("“\(q)”").font(.system(size: 18, design: .serif)).lineSpacing(3).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        HStack { Spacer(); next }
                    }
                default:
                    HStack(alignment: .top, spacing: 12) {
                        Cover(id: b.id, width: 58)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("“\(q)”").font(.system(size: 14, design: .serif)).lineLimit(5).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            HStack {
                                Text(b.title).font(.caption2.weight(.semibold)).foregroundStyle(Look.amber).lineLimit(1)
                                Spacer(minLength: 0)
                                next
                            }
                        }
                    }
                }
            } else {
                Empty(text: entry.book == nil ? "İşaretli bir kitap aç." : "Bu kitapta henüz işaret yok.")
            }
        }
        .widgetURL(URL(string: entry.book.map { "wisepath://book/\($0.id.uuidString)" } ?? "wisepath://resume"))
        .modifier(Paper())
    }

    private var next: some View {
        Button(intent: NextQuoteIntent()) {
            Image(systemName: "arrow.right.circle.fill").font(.title3).foregroundStyle(Look.amber)
        }
        .buttonStyle(.plain)
    }
}
