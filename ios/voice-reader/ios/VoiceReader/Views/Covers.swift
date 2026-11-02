// Book covers (the real one when the document has it, a designed one when it does not), the animated sound-wave
// mark of the document being read, and the app's dark backdrop that Liquid Glass sits on.
import SwiftUI
import UIKit

// MARK: - cover

@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(at url: URL, version: Int) async -> UIImage? {
        let key = "\(url.path)#\(version)" as NSString
        if let i = cache.object(forKey: key) { return i }
        let img = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let d = try? Data(contentsOf: url), let i = UIImage(data: d) else { return nil }
            return i.preparingForDisplay() ?? i
        }.value
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

struct CoverView: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord
    var width: CGFloat
    var showsPlaying = true
    @State private var image: UIImage?

    private var height: CGFloat { width * 1.5 }
    private var isPlaying: Bool { showsPlaying && model.player.documentID == doc.id && model.player.isPlaying }

    var body: some View {
        ZStack {
            if let series = SeriesBook(title: doc.title) {
                // Bir Yöne books: drawn here so the title reads at every size (the epub's own cover is a print cover)
                SeriesCover(book: series, width: width)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GeneratedCover(doc: doc, width: width)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.06, style: .continuous))
        .overlay {
            // book edge: a light spine line on the left and a soft rim, so flat images read as books
            RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.28), .white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * 0.07)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.06, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if isPlaying {
                PlayingBars(height: max(10, width * 0.14))
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .modifier(GlassPanel(cornerRadius: 10))
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: .black.opacity(0.45), radius: width * 0.06, y: width * 0.04)
        .animation(.snappy, value: isPlaying)
        .task(id: "\(doc.id)-\(model.store.coverVersion)") {
            image = await CoverCache.shared.image(at: model.store.coverURL(doc.id), version: model.store.coverVersion)
        }
        .accessibilityHidden(true)
    }
}

/// A Bir Yöne book read from its title: "Felsefe 04 — Arkhe: Başlangıca Dönüş…" or "Felsefe 01 · Üçüncü Gün · Leibniz".
struct SeriesBook {
    enum Series: String { case felsefe = "Felsefe", bilimler = "Bilimler", muhendislik = "Mühendislik" }
    let series: Series
    let number: Int
    let issue: String
    let subtitle: String?

    init?(title: String) {
        let parts = title.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3, let s = Series(rawValue: parts[0]), let n = Int(parts[1]) else { return nil }
        var rest = parts[2].trimmingCharacters(in: .whitespaces)
        for mark in ["—", "–", "·", "-"] where rest.hasPrefix(mark) {
            rest = String(rest.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !rest.isEmpty else { return nil }
        series = s
        number = n
        if let colon = rest.firstIndex(of: ":") {
            issue = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
            subtitle = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else if rest.contains(" · ") {
            // a single day of a book: the last piece is its subject
            let pieces = rest.components(separatedBy: " · ")
            issue = pieces.last ?? rest
            subtitle = pieces.dropLast().joined(separator: " · ")
        } else {
            issue = rest
            subtitle = nil
        }
    }

    /// Cloth and foil of each series; Mühendislik is closed (2026-10-27) but its books stay on the shelf.
    var cloth: (Color, Color) {
        switch series {
        case .felsefe: (Color(red: 0.16, green: 0.22, blue: 0.48), Color(red: 0.08, green: 0.11, blue: 0.27))
        case .bilimler: (Color(red: 0.09, green: 0.40, blue: 0.36), Color(red: 0.03, green: 0.20, blue: 0.19))
        case .muhendislik: (Color(red: 0.30, green: 0.32, blue: 0.35), Color(red: 0.14, green: 0.15, blue: 0.17))
        }
    }

    var foil: Color {
        switch series {
        case .felsefe: Color(red: 0.96, green: 0.80, blue: 0.45)
        case .bilimler: Color(red: 0.98, green: 0.72, blue: 0.52)
        case .muhendislik: Color(red: 0.85, green: 0.86, blue: 0.88)
        }
    }
}

/// The series cover: the series and its number on a band at the top, the book's issue in large capitals in the middle,
/// nothing small that has to be read. At list size (under 70 pt) only the number and the issue remain.
struct SeriesCover: View {
    let book: SeriesBook
    let width: CGFloat

    private static let tr = Locale(identifier: "tr_TR")
    private var small: Bool { width < 70 }
    private var paper: Color { Color(red: 0.98, green: 0.96, blue: 0.91) }

    var body: some View {
        let (top, bottom) = book.cloth
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            // the book number, large and faint, so the order of the series shows on the shelf
            Text("\(book.number)")
                .font(.system(size: width * 0.95, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.07))
                .lineLimit(1)
                .fixedSize()
                .offset(x: width * 0.38, y: width * 0.62)
            VStack(alignment: .leading, spacing: 0) {
                band
                Spacer(minLength: width * 0.06)
                Text(book.issue.uppercased(with: Self.tr))
                    .font(.system(size: width * (small ? 0.2 : 0.17), weight: .heavy, design: .serif))
                    .foregroundStyle(paper)
                    .lineLimit(small ? 2 : 3)
                    .minimumScaleFactor(0.35)
                    .lineSpacing(-width * 0.01)
                    .padding(.horizontal, width * 0.1)
                if !small {
                    Rectangle().fill(book.foil).frame(width: width * 0.22, height: max(1.5, width * 0.018))
                        .padding(.horizontal, width * 0.1).padding(.top, width * 0.07)
                    if let s = book.subtitle, !s.isEmpty {
                        Text(s)
                            .font(.system(size: width * 0.085, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(paper.opacity(0.82))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, width * 0.1).padding(.top, width * 0.05)
                    }
                }
                Spacer(minLength: width * 0.06)
                if width >= 90 {
                    Text("BİR YÖNE")
                        .font(.system(size: width * 0.055, weight: .semibold))
                        .tracking(width * 0.02)
                        .foregroundStyle(book.foil.opacity(0.75))
                        .padding(.horizontal, width * 0.1).padding(.bottom, width * 0.08)
                }
            }
        }
    }

    /// Series name and book number on the series' foil colour: the first thing the eye reads.
    private var band: some View {
        HStack(alignment: .firstTextBaseline, spacing: width * 0.04) {
            if !small {
                Text(book.series.rawValue.uppercased(with: Self.tr))
                    .font(.system(size: width * 0.085, weight: .bold))
                    .tracking(width * 0.008)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            Text("\(book.number)")
                .font(.system(size: width * (small ? 0.24 : 0.15), weight: .heavy, design: .serif))
                .monospacedDigit()
        }
        .foregroundStyle(book.cloth.1)
        .padding(.horizontal, width * 0.1)
        .padding(.vertical, width * (small ? 0.04 : 0.05))
        .frame(maxWidth: .infinity)
        .background(book.foil)
    }
}

/// A cover for documents without one: colour from the title, the format shown as an object (book, page, sheet).
struct GeneratedCover: View {
    let doc: DocumentRecord
    let width: CGFloat

    private var palette: (Color, Color) {
        let pairs: [(Color, Color)] = [
            (Color(red: 0.17, green: 0.20, blue: 0.42), Color(red: 0.36, green: 0.27, blue: 0.62)),
            (Color(red: 0.10, green: 0.30, blue: 0.33), Color(red: 0.18, green: 0.52, blue: 0.50)),
            (Color(red: 0.40, green: 0.16, blue: 0.20), Color(red: 0.70, green: 0.33, blue: 0.30)),
            (Color(red: 0.22, green: 0.24, blue: 0.27), Color(red: 0.42, green: 0.45, blue: 0.50)),
            (Color(red: 0.36, green: 0.27, blue: 0.10), Color(red: 0.68, green: 0.52, blue: 0.24)),
            (Color(red: 0.12, green: 0.26, blue: 0.46), Color(red: 0.25, green: 0.50, blue: 0.80)),
        ]
        let h = doc.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return pairs[h % pairs.count]
    }

    var body: some View {
        let (a, b) = palette
        ZStack {
            LinearGradient(colors: [b, a], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: width * 0.05) {
                Rectangle().fill(.white.opacity(0.55)).frame(width: width * 0.22, height: max(1, width * 0.012))
                Text(doc.title)
                    .font(.system(size: max(9, width * 0.115), weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .minimumScaleFactor(0.6)
                if let a = doc.author, width > 70 {
                    Text(a).font(.system(size: max(7, width * 0.075), design: .serif)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack {
                    Image(systemName: symbol).font(.system(size: max(8, width * 0.1)))
                    Spacer()
                    if width >= 70 {
                        Text(doc.format.badge).font(.system(size: max(6, width * 0.065), weight: .bold)).tracking(1).lineLimit(1)
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(width * 0.11)
            .padding(.leading, width * 0.04)
        }
    }

    private var symbol: String {
        switch doc.format {
        case .epub: "book.closed.fill"
        case .pdf: "doc.richtext.fill"
        case .docx: "doc.text.fill"
        case .html: "globe"
        case .clipboard: "doc.on.clipboard.fill"
        default: "text.alignleft"
        }
    }
}

// MARK: - playing mark

/// Five bars moving like a voice: the document being read right now.
struct PlayingBars: View {
    var height: CGFloat = 14
    var active = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: height * 0.16) {
                ForEach(0..<5, id: \.self) { i in
                    let phase = t * (5.2 + Double(i) * 0.9) + Double(i) * 1.7
                    let level = active ? 0.28 + 0.72 * abs(sin(phase) * 0.6 + sin(phase * 0.47) * 0.4) : 0.3
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 1.0, green: 0.42, blue: 0.55)],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: height * 0.17, height: height * level)
                }
            }
            .frame(height: height)
        }
        .accessibilityLabel("Okunuyor")
    }
}

// MARK: - backdrop

/// The library backdrop: Voice Dream's light grey, or a deep neutral in dark mode, with a faint wash of the accent.
struct InkBackground: View {
    @Environment(\.accent) private var accent
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.ground, Palette.groundDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [accent.fill.opacity(0.14), .clear],
                           center: UnitPoint(x: 0.2, y: 0.0), startRadius: 10, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}
