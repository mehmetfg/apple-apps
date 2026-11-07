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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Wood.frame, lineWidth: 5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .padding(.horizontal, 14)
    }
}

// MARK: - wood

private enum Wood {
    static let frame = Color(red: 0.30, green: 0.18, blue: 0.10)
    static let plankTop = Color(red: 0.55, green: 0.36, blue: 0.20)
    static let plankEdge = Color(red: 0.36, green: 0.22, blue: 0.12)
    static var back: some View {
        LinearGradient(colors: [Color(red: 0.17, green: 0.11, blue: 0.07), Color(red: 0.24, green: 0.15, blue: 0.09)],
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
    }
}

private struct Plank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Wood.plankTop, Wood.plankEdge], startPoint: .top, endPoint: .bottom).frame(height: 9)
            Wood.plankEdge.opacity(0.9).frame(height: 4)
        }
        .shadow(color: .black.opacity(0.45), radius: 4, y: 3)
    }
}

// MARK: - a spine

/// 2026-11-04: every spine the same height and thickness (the row reads as a row, not a skyline). The title runs down
/// the spine on two lines in a type large enough to read; a series book shows its subject, not the long series title.
/// A plate at the top carries a short key (F 04, B 03, or the title's initials) in the series colour, so a book is
/// found even before its title is read; at the foot its state in words: %42, Yeni or ✓.
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

    private var ink: Color { Color(red: 0.97, green: 0.93, blue: 0.84) }

    var body: some View {
        let w = Self.thickness, h = Self.height
        let titleLength = h - 64
        ZStack(alignment: .top) {
            LinearGradient(stops: [.init(color: color.blend(.black, 0.35), location: 0),
                                   .init(color: color.blend(.white, 0.12), location: 0.35),
                                   .init(color: color, location: 0.6),
                                   .init(color: color.blend(.black, 0.4), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                // the plate
                Text(key)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(color.blend(.black, 0.5))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: w - 10, height: 20)
                    .background(ink.opacity(0.92), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(.top, 8)
                band.padding(.horizontal, 3).padding(.top, 5)
                // the title: two lines down the spine
                Text(spineTitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .lineSpacing(-1)
                    .frame(width: titleLength, height: w - 10, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: w, height: titleLength)
                Spacer(minLength: 0)
                band.padding(.horizontal, 3).padding(.bottom, 3)
                Text(state)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(doc.isFinished ? Color(red: 0.95, green: 0.80, blue: 0.40) : ink.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: w, height: h)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 3))
        .overlay(alignment: .top) {
            if !doc.isFinished, !doc.isUnread {
                Ribbon().fill(Color(red: 0.75, green: 0.12, blue: 0.16))
                    .frame(width: 7, height: 18)
                    .offset(x: w * 0.30, y: -8)
            }
        }
        .contentShape(Rectangle())
    }

    private var state: String {
        if doc.isFinished { return doc.finishes.count >= 2 ? "✓ \(doc.finishes.count)" : "✓" }
        if doc.isUnread { return "Yeni" }
        return "%\(Int((doc.progress * 100).rounded()))"
    }

    private var band: some View {
        let gold = Color(red: 0.88, green: 0.72, blue: 0.38)
        return VStack(spacing: 2) {
            Rectangle().fill(doc.isFinished ? gold : .black.opacity(0.35)).frame(height: doc.isFinished ? 2.5 : 1.5)
            Rectangle().fill(doc.isFinished ? gold.opacity(0.8) : .white.opacity(0.18)).frame(height: 1)
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
