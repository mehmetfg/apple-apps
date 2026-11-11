// The mini player shown over the library, the glass panel style and the progress scrubber.
import SwiftUI

struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    var open: () -> Void

    var body: some View {
        let p = model.player
        let progress = Double(p.shownCursor) / Double(max(1, p.length))
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 11) {
                    if let d = model.currentDocument { CoverView(doc: d, width: 30, showsPlaying: false) }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(p.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        if p.breakEnds != nil { BreakBadge() }
                        else if model.automationRun != nil { AutomationBadge() }
                        else { ProgressBar(value: progress).frame(height: 2.5) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Okuma ekranını aç: \(p.title)")
            HStack(spacing: 2) {
                Button { p.skip(forward: false, unit: model.settings.navigationUnit) } label: {
                    SkipGlyph(forward: false, unit: model.settings.navigationUnit, size: 20).frame(width: 38, height: 38)
                }
                .accessibilityLabel("Geri: \(model.settings.navigationUnit.name)")
                Button { p.toggle() } label: {
                    Image(systemName: p.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: p.isPlaying ? 0 : 1)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 38, height: 38)
                        .background(Palette.playFill, in: Circle())
                        .padding(.horizontal, 2)
                }
                .contextMenu { ActivePauseMenu() }
                .accessibilityLabel(p.isPlaying ? "Duraklat" : "Oynat")
                Button { p.skip(forward: true, unit: model.settings.navigationUnit) } label: {
                    SkipGlyph(forward: true, unit: model.settings.navigationUnit, size: 20).frame(width: 38, height: 38)
                }
                .accessibilityLabel("İleri: \(model.settings.navigationUnit.name)")
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
        .modifier(GlassPanel(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// During a music break: what is happening and how long until reading goes on.
struct BreakBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((model.player.breakEnds ?? ctx.date).timeIntervalSince(ctx.date).rounded()))
            let p = model.player
            let clock = "\(left / 60):\(String(format: "%02d", left % 60))"
            Label(p.breakKind == .untilMusicStops ? "Müzik bitince sürecek" : p.breakKind == .hold ? "Bekleme · \(clock)" : "Müzik arası · \(clock)",
                  systemImage: p.breakKind == .music ? "music.note" : "hourglass")
                .font(.caption.weight(.medium)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Müzik arası")
    }
}

/// Liquid Glass on iOS 26, a material card before it.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(Palette.panel.opacity(0.55)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(Palette.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

/// The progress bar, Voice Dream style: a thin track, a filled part, a small rounded knob. The knob grows a little
/// while dragged; the new value is reported when the finger lifts.
struct Scrubber: View {
    var value: Double
    var fill: Color
    var knob: Color
    /// The reading place, drawn as a small tick while the knob shows another place (browsing the book).
    var mark: Double? = nil
    var onChanging: (Double) -> Void
    var onEnded: (Double) -> Void
    @State private var dragging = false
    /// True only while a finger is on the bar; it falls back by itself when the system cancels the drag (an alert, a
    /// system gesture), where `onEnded` is never called and the bar used to stay frozen at the dragged value.
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = max(0, min(w, w * value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14)).frame(height: 5)
                Capsule().fill(fill).frame(width: x, height: 5)
                if let m = mark {
                    Capsule().fill(knob.opacity(0.55)).frame(width: 3, height: 14)
                        .offset(x: min(max(0, w * m - 1.5), w - 3))
                }
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(knob)
                    .frame(width: dragging ? 11 : 8, height: dragging ? 24 : 20)
                    .offset(x: min(max(0, x - 4), w - 8))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($touching) { _, t, _ in t = true }
                .onChanged { v in
                    if !dragging { withAnimation(.snappy(duration: 0.15)) { dragging = true } }
                    onChanging(min(max(0, v.location.x / w), 1))
                }
                .onEnded { v in
                    withAnimation(.snappy(duration: 0.2)) { dragging = false }
                    onEnded(min(max(0, v.location.x / w), 1))
                })
        }
        .frame(height: 30)
        .onChange(of: touching) { _, t in
            if !t, dragging { withAnimation(.snappy(duration: 0.2)) { dragging = false }; onEnded(value) }
        }
        .accessibilityElement()
        .accessibilityLabel("Konum")
        .accessibilityValue("%\(Int(value * 100))")
        .accessibilityAdjustableAction { d in
            let step = 0.02
            onEnded(min(1, max(0, value + (d == .increment ? step : -step))))
        }
    }
}
