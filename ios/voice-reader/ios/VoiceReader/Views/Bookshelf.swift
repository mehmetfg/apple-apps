// Kitaplık (2026-10-28): the books as they stand in a real bookcase, spine out, on wooden shelves. The spine is as
// thick as the book is long and coloured by its series or folder; title and author run down it. A book being read
// has a ribbon marker hanging from its top and a strip of its progress along the spine; a finished one carries a
// gold band (and how many times it was read). The shelves can be grouped (Süren · Okunacak · Bitenler), the last
// one the archive. A tap takes the book off the shelf: it turns to its cover, with Aç and the marks.
import SwiftUI

struct BookshelfSection: Identifiable {
    var id: String { title }
    let title: String
    let docs: [DocumentRecord]
}

struct BookshelfView: View {
    @Environment(AppModel.self) private var model
    let sections: [BookshelfSection]
    var onOpen: (UUID) -> Void
    @State private var width: CGFloat = 360
    @State private var picked: DocumentRecord?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { s in
                if !s.docs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if sections.count > 1 {
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.title).font(.system(size: 15, weight: .semibold, design: .serif))
                                Text("\(s.docs.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                        }
                        bookcase(s.docs)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sheet(item: $picked) { d in PulledBook(doc: d, onOpen: { picked = nil; onOpen(d.id) }) }
    }

    /// The books packed into shelves as wide as the screen; each shelf a dark back, the spines, a plank.
    private func bookcase(_ docs: [DocumentRecord]) -> some View {
        let inner = max(200, width - 28 - 20)
        var rows: [[DocumentRecord]] = [[]]
        var used: CGFloat = 0
        for d in docs {
            let w = Spine.width(d) + 3
            if used + w > inner, !rows[rows.count - 1].isEmpty { rows.append([]); used = 0 }
            rows[rows.count - 1].append(d)
            used += w
        }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(rows[r]) { d in
                            Spine(doc: d)
                                .onTapGesture { picked = d }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(d.title), \(model.statusText(d))")
                                .accessibilityAddTraits(.isButton)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity)
                    .background(Wood.back)
                    Plank()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Wood.frame, lineWidth: 6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.30), radius: 12, y: 7)
        .padding(.horizontal, 14)
    }
}

// MARK: - wood

private enum Wood {
    static let frame = LinearGradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.14), Color(red: 0.24, green: 0.14, blue: 0.07)],
                                      startPoint: .top, endPoint: .bottom)
    static let plankTop = Color(red: 0.62, green: 0.42, blue: 0.24)
    static let plankEdge = Color(red: 0.36, green: 0.22, blue: 0.12)
    static var back: some View {
        LinearGradient(colors: [Color(red: 0.13, green: 0.08, blue: 0.05), Color(red: 0.24, green: 0.15, blue: 0.09)],
                       startPoint: .top, endPoint: .bottom)
            .overlay {
                // a faint grain, drawn once
                Canvas { g, size in
                    for i in 0..<14 {
                        let x = size.width * CGFloat(i) / 14 + CGFloat((i * 37) % 11)
                        var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 6, y: size.height))
                        g.stroke(p, with: .color(.black.opacity(0.12)), lineWidth: 1)
                    }
                }
            }
            // the shelf above throws its shadow on the back and on the books' heads; the sides are darker
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.06),
                                       .init(color: .clear, location: 0.94), .init(color: .black.opacity(0.35), location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}

/// The board the books stand on: its top catches the light, its front edge is rounded off into shadow.
private struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.28)).frame(height: 1)
            LinearGradient(colors: [Wood.plankTop, Wood.plankEdge], startPoint: .top, endPoint: .bottom).frame(height: 10)
            LinearGradient(colors: [Wood.plankEdge, Wood.plankEdge.blend(.black, 0.45)], startPoint: .top, endPoint: .bottom).frame(height: 5)
        }
        .shadow(color: .black.opacity(0.5), radius: 5, y: 4)
    }
}

// MARK: - a spine

/// 2026-11-04: every spine the same height and thickness (the row reads as a row, not a skyline). The title runs down
/// the spine on two lines in a type large enough to read; a series book shows its subject, not the long series title.
/// At the top a short key (F 04, B 03, or the title's initials) is stamped in gold, so a book is found even before
/// its title is read; at the foot its state: %42, YENİ or ✓.
struct Spine: View {
    let doc: DocumentRecord

    static let thickness: CGFloat = 46
    static let height: CGFloat = 172
    static func width(_ d: DocumentRecord) -> CGFloat { thickness }

    private var stableSeed: Int { doc.id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } }
    private var series: SeriesBook? { SeriesBook(title: doc.title) }

    private var color: Color {
        if let s = series {
            switch s.series {
            case .felsefe: return Color(red: 0.11, green: 0.16, blue: 0.33)
            case .bilimler: return Color(red: 0.12, green: 0.32, blue: 0.24)
            case .muhendislik: return Color(red: 0.22, green: 0.23, blue: 0.25)
            }
        }
        if let f = doc.folder, FolderScope.named(f).tint != Color(white: 0.75) {
            return FolderScope.named(f).tint.blend(.black, 0.45)
        }
        let tones: [Color] = [Color(red: 0.42, green: 0.12, blue: 0.12), Color(red: 0.12, green: 0.24, blue: 0.36),
                              Color(red: 0.16, green: 0.30, blue: 0.20), Color(red: 0.36, green: 0.26, blue: 0.14),
                              Color(red: 0.26, green: 0.18, blue: 0.32), Color(red: 0.20, green: 0.20, blue: 0.22)]
        return tones[stableSeed % tones.count]
    }

    /// The plate's key: the series letter and number, or the first letters of the title's first two words.
    var key: String {
        if let s = series { return "\(s.series.rawValue.prefix(1)) \(String(format: "%02d", s.number))" }
        let words = doc.title.split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 1 || $0.first?.isNumber == true }
        let k = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased(with: Locale(identifier: "tr")) }.joined()
        return k.isEmpty ? "•" : k
    }

    private var spineTitle: String {
        if let s = series { return s.issue }
        // "Genişletme · X": the expansion's own subject on the spine
        return doc.title.hasPrefix("Genişletme · ") ? String(doc.title.dropFirst(13)) : doc.title
    }

    /// Gold foil, as stamped into cloth or leather: the lettering, the rules, the label's edge.
    private static let foil = LinearGradient(colors: [Color(red: 0.98, green: 0.88, blue: 0.60), Color(red: 0.80, green: 0.62, blue: 0.30),
                                                      Color(red: 0.95, green: 0.82, blue: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let cream = Color(red: 0.97, green: 0.90, blue: 0.72)

    /// 2026-11-10: the white plate at the top is gone ("tepesindeki beyaz etiket çirkin; gerçekliğe uygun olsun").
    /// The spine is bound like a real book: a rounded back in cloth, raised bands across it, the volume's key
    /// stamped in gold between two gold rules, the title on a dark leather label with a gold edge, and the state
    /// stamped at the foot. Only gradients and text: nothing is drawn per pixel.
    var body: some View {
        let w = Self.thickness, h = Self.height
        let labelHeight = h - 78
        ZStack(alignment: .top) {
            // the rounded back: light falls on its left third, the right side turns away
            LinearGradient(stops: [.init(color: color.blend(.black, 0.50), location: 0),
                                   .init(color: color.blend(.white, 0.16), location: 0.28),
                                   .init(color: color, location: 0.55),
                                   .init(color: color.blend(.black, 0.55), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            // head and foot fall into shadow a little
            LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .clear, location: 0.07),
                                   .init(color: .clear, location: 0.93), .init(color: .black.opacity(0.35), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                rule.padding(.top, 7)
                Text(key)
                    .font(.system(size: 10.5, weight: .bold, design: .serif))
                    .tracking(0.6)
                    .foregroundStyle(Self.foil)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: w - 8, height: 17)
                rule
                hub.padding(.top, 4)
                // the title's label: darker leather let into the spine, a gold line round it
                Text(spineTitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Self.cream)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .lineSpacing(-1)
                    .frame(width: labelHeight - 12, height: w - 14, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: w - 8, height: labelHeight)
                    .background {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(LinearGradient(colors: [color.blend(.black, 0.62), color.blend(.black, 0.48)], startPoint: .leading, endPoint: .trailing))
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Self.foil, lineWidth: doc.isFinished ? 1.2 : 0.7)
                            .opacity(doc.isFinished ? 1 : 0.75)
                    }
                    .padding(.top, 4)
                hub.padding(.top, 4)
                Spacer(minLength: 0)
                Text(state)
                    .font(.system(size: 9.5, weight: .bold, design: .serif))
                    .foregroundStyle(doc.isFinished ? AnyShapeStyle(Self.foil) : AnyShapeStyle(Self.cream.opacity(0.9)))
                    .lineLimit(1).minimumScaleFactor(0.7)
                rule.padding(.top, 3).padding(.bottom, 6)
            }
            // a book being read shows how far it is: a gold thread up its right edge
            if !doc.isFinished, !doc.isUnread {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Self.foil).frame(width: 2, height: h * doc.progress)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 2)
                .opacity(0.9)
            }
        }
        .frame(width: w, height: h)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4))
        .overlay(alignment: .top) {
            if !doc.isFinished, !doc.isUnread {
                Ribbon().fill(LinearGradient(colors: [Color(red: 0.82, green: 0.14, blue: 0.18), Color(red: 0.55, green: 0.06, blue: 0.10)],
                                             startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: 20)
                    .offset(x: w * 0.28, y: -9)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 1, y: 1)
            }
        }
        // each book stands a little apart from its neighbour
        .shadow(color: .black.opacity(0.45), radius: 2.5, x: 1.5, y: 0)
        .contentShape(Rectangle())
    }

    private var state: String {
        if doc.isFinished { return doc.finishes.count >= 2 ? "✓ \(doc.finishes.count)" : "✓" }
        if doc.isUnread { return "YENİ" }
        return "%\(Int(doc.progress * 100))"
    }

    /// A gold rule stamped across the spine (two on a finished book).
    private var rule: some View {
        VStack(spacing: 1.5) {
            Rectangle().fill(Self.foil).frame(height: 1)
            if doc.isFinished { Rectangle().fill(Self.foil).frame(height: 1) }
        }
        .padding(.horizontal, 4)
        .opacity(0.9)
    }

    /// A raised band: the cord under the cloth, lit from above.
    private var hub: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            Rectangle().fill(color.blend(.white, 0.06)).frame(height: 2.5)
            Rectangle().fill(.black.opacity(0.45)).frame(height: 1.5)
        }
    }
}

private struct Ribbon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.width * 0.6))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - a book off the shelf

/// The tapped book, taken off the shelf: it turns from its spine to its cover, with its state and the ways in.
private struct PulledBook: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let doc: DocumentRecord
    var onOpen: () -> Void
    @State private var turned = false

    var body: some View {
        VStack(spacing: 16) {
            CoverView(doc: doc, width: 150)
                .rotation3DEffect(.degrees(turned ? 0 : 80), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
                .opacity(turned ? 1 : 0.4)
                .padding(.top, 24)
            VStack(spacing: 4) {
                Text(doc.title).font(.system(size: 19, weight: .semibold, design: .serif)).multilineTextAlignment(.center).lineLimit(3)
                if let a = doc.author { Text(a).font(.subheadline).foregroundStyle(.secondary) }
                Text(model.statusText(doc)).font(.footnote).foregroundStyle(.secondary).padding(.top, 2)
            }
            .padding(.horizontal, 24)
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    Label(doc.isUnread ? "Başla" : doc.isFinished ? "Aç" : "Devam et", systemImage: "book.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.settings.accent.solid)
                Button { dismiss(); model.bookSearchDoc = doc.id } label: {
                    Label("Ara", systemImage: "text.magnifyingglass").frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                if !doc.highlights.isEmpty {
                    Button { dismiss(); model.marksSheetDoc = doc.id } label: {
                        Label("\(doc.highlights.count) işaret", systemImage: "highlighter").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.05)) { turned = true } }
    }
}

extension Color {
    /// Part of the way towards another colour (iOS 17 has no `mix`).
    func blend(_ other: Color, _ t: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(t)
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k), blue: Double(b1 + (b2 - b1) * k))
    }
}
