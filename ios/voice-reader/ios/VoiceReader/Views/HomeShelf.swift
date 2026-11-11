// Home pieces of 2026-11-04 ("ne var elimde ne yok bilmek"): the last three books side by side on top, an inventory
// line (how many books, how many going on, waiting, finished, and the hours still to listen; each count a key to
// that shelf), the state of a book in words instead of a progress bar (%42 · Yeni · ✓ Bitti), and Akış: the covers
// flowing left and right like the old iPhone's albums, tilted, with a reflection, the one in the middle named below.
import SwiftUI

/// A book's state in one short word: "Yeni", "%42" or "✓ Bitti" (no bar).
struct StateLabel: View {
    let doc: DocumentRecord
    var compact = false

    var body: some View {
        Group {
            if doc.isFinished {
                Text(compact ? "✓" : (doc.finishes.count >= 2 ? "✓ \(doc.finishes.count) kez" : "✓ Bitti"))
                    .foregroundStyle(.green)
            } else if doc.isUnread {
                Text("Yeni")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(Color.accentColor, in: Capsule())
            } else {
                Text("%\(Int(doc.progress * 100))").foregroundStyle(.secondary)      // floored, as the reader shows it
            }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .lineLimit(1)
    }
}

// MARK: - the last three

struct RecentBooks: View {
    @Environment(AppModel.self) private var model
    var open: (UUID) -> Void

    /// The book in the player first, then the last opened ones (unfinished first), three in all.
    static func pick(_ model: AppModel) -> [DocumentRecord] {
        var out: [DocumentRecord] = []
        if let id = model.player.documentID, let d = model.store.document(id) { out.append(d) }
        let opened = model.store.documents.filter { $0.lastOpenedAt != nil && !out.map(\.id).contains($0.id) }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        out += opened.filter { !$0.isFinished }.prefix(3 - out.count)
        if out.count < 3 { out += opened.filter(\.isFinished).prefix(3 - out.count) }
        return Array(out.prefix(3))
    }

    var body: some View {
        let books = Self.pick(model)
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kaldığın kitaplar").font(.title3.weight(.bold))
                    .padding(.horizontal, 20)
                GeometryReader { g in
                    let w = (g.size.width - 40 - 24) / 3
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(books) { d in RecentBook(doc: d, width: w) { open(d.id) } }
                        if books.count < 3 { Spacer(minLength: 0) }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: Self.height)
            }
        }
    }

    /// Cover (width × 1.5) + two title lines + the state, for a third of an iPhone's width.
    static var height: CGFloat {
        let w = (UIScreen.main.bounds.width - 64) / 3
        return w * 1.5 + 64
    }
}

private struct RecentBook: View {
    @Environment(AppModel.self) private var model
    let doc: DocumentRecord
    let width: CGFloat
    var open: () -> Void

    private var inPlayer: Bool { model.player.documentID == doc.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: open) { CoverView(doc: doc, width: width) }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomTrailing) {
                    Button { if inPlayer { model.player.toggle() } else { open() } } label: {
                        Image(systemName: inPlayer && model.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Palette.play, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .accessibilityLabel(inPlayer && model.player.isPlaying ? "Duraklat: \(doc.title)" : "Oku: \(doc.title)")
                }
            Text(doc.title).font(.system(size: 13, weight: .semibold, design: .serif)).lineLimit(2)
                .frame(width: width, alignment: .leading)
            HStack(spacing: 5) {
                StateLabel(doc: doc)
                if !doc.isFinished, !doc.isUnread {
                    Text(Format.duration(model.duration(characters: max(0, doc.length - doc.position), speed: doc.speed)))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - inventory

/// "34 kitap · 5 süren · 20 okunacak · 9 bitti · 41 sa kaldı": what is at hand. A tap on a count shows that shelf.
struct InventoryStrip: View {
    @Environment(AppModel.self) private var model
    /// Since 2026-11-10 the strip lives in İstatistik (the home shows the day instead): a tap on a count chooses that
    /// shelf on the home and closes the page.
    var onPick: () -> Void = {}

    var body: some View {
        let all = model.store.documents
        let reading = all.filter { !$0.isUnread && !$0.isFinished }
        let unread = all.filter(\.isUnread)
        let finished = all.filter(\.isFinished)
        let left = all.filter { !$0.isFinished }.reduce(0.0) { $0 + model.duration(characters: $1.length - $1.position, speed: $1.speed) }
        let words = all.filter { !$0.isFinished }.reduce(0) { $0 + Int(Double($1.wordCount) * (1 - $1.progress)) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                cell("\(all.count)", "kitap", "all")
                cell("\(reading.count)", "süren", "reading")
                cell("\(unread.count)", "okunacak", "unread")
                cell("\(finished.count)", "bitti", "finished")
            }
            // the share of each shelf as one thin line of three colours
            GeometryReader { g in
                let n = max(1, all.count)
                HStack(spacing: 2) {
                    Capsule().fill(Color.orange).frame(width: max(0, g.size.width * CGFloat(reading.count) / CGFloat(n) - 2))
                    Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: max(0, g.size.width * CGFloat(unread.count) / CGFloat(n) - 2))
                    Capsule().fill(Color.green).frame(width: max(0, g.size.width * CGFloat(finished.count) / CGFloat(n) - 2))
                }
            }
            .frame(height: 4)
            Text("Dinlenecek \(Self.hours(left)) · ≈ \(StatFormat.pages(words)) sayfa")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func cell(_ n: String, _ label: String, _ shelf: String) -> some View {
        let on = model.settings.homeShelf == shelf
        return Button { withAnimation(.smooth(duration: 0.25)) { model.settings.homeShelf = shelf }; onPick() } label: {
            VStack(spacing: 1) {
                Text(n).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Text(label).font(.caption2.weight(on ? .bold : .regular)).foregroundStyle(on ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n) \(label)\(on ? ", seçili" : "")")
    }

    static func hours(_ t: TimeInterval) -> String {
        let h = Int(t / 3600)
        return h >= 1 ? "\(h) sa \(Int(t.truncatingRemainder(dividingBy: 3600) / 60)) dk" : "\(Int(t / 60)) dk"
    }
}

// MARK: - Akış

/// The covers in a flowing row: the one in the middle faces you, the others turn away and stand back, each above its
/// reflection. Its title, author and state sit under the row; a tap on the middle one opens it, on another brings it
/// to the middle.
struct CoverFlowView: View {
    @Environment(AppModel.self) private var model
    let docs: [DocumentRecord]
    var onOpen: (UUID) -> Void
    @State private var current: UUID?

    private let coverWidth: CGFloat = 150

    var body: some View {
        let shown = docs.first { $0.id == current } ?? docs.first
        VStack(spacing: 14) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(docs) { d in
                        FlowCover(doc: d, width: coverWidth)
                            .visualEffect { content, proxy in
                                let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                                let mid = proxy.bounds(of: .scrollView(axis: .horizontal)).map { $0.width / 2 } ?? 200
                                let dx = (frame.midX - mid) / coverWidth
                                let t = max(-1, min(1, dx))
                                return content
                                    .rotation3DEffect(.degrees(-t * 58), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                                    .scaleEffect(1 - abs(t) * 0.18)
                                    .offset(x: -t * 34)          // drawn closer to the middle; the tap areas stay apart
                            }
                            .zIndex(d.id == (shown?.id) ? 10 : 0)
                            .onTapGesture {
                                if d.id == shown?.id { onOpen(d.id) } else { withAnimation(.smooth(duration: 0.4)) { current = d.id } }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(d.title), \(model.statusText(d))")
                            .accessibilityAddTraits(.isButton)
                            .id(d.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current, anchor: .center)
            .contentMargins(.horizontal, (UIScreen.main.bounds.width - coverWidth) / 2, for: .scrollContent)
            .frame(height: coverWidth * 1.5 + 70)
            .sensoryFeedback(.selection, trigger: current)
            if let d = shown {
                VStack(spacing: 4) {
                    Text(d.title).font(.system(size: 17, weight: .semibold, design: .serif))
                        .multilineTextAlignment(.center).lineLimit(2)
                    HStack(spacing: 8) {
                        if let a = d.author { Text(a).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                        StateLabel(doc: d)
                        if !d.highlights.isEmpty { MarksChip(doc: d) }
                    }
                    if let i = docs.firstIndex(where: { $0.id == d.id }) {
                        Text("\(i + 1) / \(docs.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 30)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.2), value: d.id)
            }
        }
        .padding(.bottom, 12)
        .onChange(of: docs.map(\.id)) { _, ids in if let c = current, !ids.contains(c) { current = ids.first } }
    }
}

/// A cover standing on a black floor with its reflection fading under it.
private struct FlowCover: View {
    let doc: DocumentRecord
    let width: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            CoverView(doc: doc, width: width)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 6)
            CoverView(doc: doc, width: width, showsPlaying: false)
                .scaleEffect(x: 1, y: -1)
                .frame(height: 60, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
