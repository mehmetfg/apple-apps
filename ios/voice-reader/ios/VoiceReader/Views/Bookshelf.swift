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
            let w = Spine.width(d) + 2
            if used + w > inner, !rows[rows.count - 1].isEmpty { rows.append([]); used = 0 }
            rows[rows.count - 1].append(d)
            used += w
        }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 2) {
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

struct Spine: View {
    let doc: DocumentRecord

    /// 20 pt for a short text, up to 54 for a long book.
    static func width(_ d: DocumentRecord) -> CGFloat {
        CGFloat(20 + min(34, sqrt(Double(max(0, d.wordCount))) / 9))
    }

    /// A stable small difference in height and tone for each book, so the row looks like a real one.
    private var stableSeed: Int { doc.id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } }
    private var height: CGFloat { 150 + CGFloat(stableSeed % 25) - 12 }

    private var color: Color {
        // the series as on their covers: Felsefe navy, Bilimler green, Mühendislik graphite
        if let s = SeriesBook(title: doc.title) {
            switch s.series {
            case .felsefe: return Color(red: 0.11, green: 0.16, blue: 0.33)
            case .bilimler: return Color(red: 0.12, green: 0.32, blue: 0.24)
            case .muhendislik: return Color(red: 0.22, green: 0.23, blue: 0.25)
            }
        }
        if let f = doc.folder, FolderScope.named(f).tint != Color(white: 0.75) {
            return FolderScope.named(f).tint.blend(.black, 0.45)
        }
        // leather and cloth tones
        let tones: [Color] = [Color(red: 0.42, green: 0.12, blue: 0.12), Color(red: 0.12, green: 0.24, blue: 0.36),
                              Color(red: 0.16, green: 0.30, blue: 0.20), Color(red: 0.36, green: 0.26, blue: 0.14),
                              Color(red: 0.26, green: 0.18, blue: 0.32), Color(red: 0.20, green: 0.20, blue: 0.22)]
        return tones[stableSeed % tones.count]
    }

    var body: some View {
        let w = Self.width(doc)
        ZStack {
            // the cloth: a curve of light across the spine, as on a rounded back
            LinearGradient(stops: [.init(color: color.blend(.black, 0.35), location: 0),
                                   .init(color: color.blend(.white, 0.12), location: 0.35),
                                   .init(color: color, location: 0.6),
                                   .init(color: color.blend(.black, 0.4), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            // binding bands top and bottom; gold on a finished book
            VStack {
                band.padding(.top, 10)
                Spacer()
                band.padding(.bottom, 12)
            }
            // title down the spine, the author small near the foot
            VStack(spacing: 6) {
                Text(doc.title)
                    .font(.system(size: min(13, w * 0.42), weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.80))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: height - 58)
                    .rotationEffect(.degrees(90))
                    .frame(width: w, height: height - 58)
                if let a = doc.author, w > 28 {
                    Text(a.split(separator: " ").last.map(String.init) ?? a)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(Color(red: 0.96, green: 0.91, blue: 0.80).opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: w - 4)
                }
            }
            .padding(.vertical, 22)
            // how far: a thin strip of light up the spine's edge
            if !doc.isFinished, doc.progress > 0.005 {
                HStack {
                    VStack {
                        Spacer(minLength: 0)
                        Capsule().fill(Color(red: 1, green: 0.78, blue: 0.35)).frame(width: 2.5, height: (height - 8) * doc.progress)
                    }
                    Spacer()
                }
                .padding(.leading, 2).padding(.vertical, 4)
            }
        }
        .frame(width: w, height: height)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 3))
        .overlay(alignment: .top) {
            // a book being read: its ribbon marker hangs over the top
            if !doc.isFinished, !doc.isUnread {
                Ribbon().fill(Color(red: 0.75, green: 0.12, blue: 0.16))
                    .frame(width: 7, height: 22)
                    .offset(x: w * 0.18, y: -10)
            }
        }
        .overlay(alignment: .bottom) {
            if doc.finishes.count >= 2 {
                Text("\(doc.finishes.count)")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black.opacity(0.75))
                    .frame(width: 13, height: 13)
                    .background(Color(red: 0.95, green: 0.78, blue: 0.35), in: Circle())
                    .padding(.bottom, 26)
            }
        }
        .contentShape(Rectangle())
    }

    private var band: some View {
        let gold = Color(red: 0.88, green: 0.72, blue: 0.38)
        return VStack(spacing: 2) {
            Rectangle().fill(doc.isFinished ? gold : .black.opacity(0.35)).frame(height: doc.isFinished ? 3 : 1.5)
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

private extension Color {
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
