// Small pieces used on several screens.
import SwiftUI

/// Rain chance per 15 minutes as bars, with the planned and the best departure marked.
struct RainStrip: View {
    var slots: [Slot]
    var planned: Date?
    var best: Date?
    var rideMinutes: Int = 30
    var height: CGFloat = 54
    @State private var grown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let n = max(1, slots.count)
                let bw = g.size.width / CGFloat(n)
                ZStack(alignment: .bottomLeading) {
                    if let b = best, let i = index(of: b) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.16))
                            .frame(width: bw * CGFloat(max(1, rideMinutes / 15)), height: height + 8)
                            .offset(x: bw * CGFloat(i), y: 4)
                    }
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, s in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.rain(s.prob).gradient)
                                .frame(height: max(4, height * (grown ? s.prob : 0.02)))
                                .opacity(0.35 + 0.65 * s.confidence)
                        }
                    }
                    if let p = planned, let i = index(of: p) {
                        Rectangle().fill(.white).frame(width: 2, height: height + 10).offset(x: bw * CGFloat(i))
                    }
                }
            }
            .frame(height: height + 10)
            HStack {
                ForEach(labels, id: \.self) { d in
                    Text(Fmt.t(d)).font(.caption2.monospacedDigit()).foregroundStyle(Palette.soft)
                    if d != labels.last { Spacer() }
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) { grown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("En yüksek yağış ihtimali \(Fmt.pct(slots.map(\.prob).max() ?? 0))")
    }

    private func index(of d: Date) -> Int? { slots.firstIndex { $0.time >= d.addingTimeInterval(-60) } }
    private var labels: [Date] {
        guard let f = slots.first?.time, let l = slots.last?.time else { return [] }
        return stride(from: f.timeIntervalSince1970, through: l.timeIntervalSince1970 + 900, by: 3600).map { Date(timeIntervalSince1970: $0) }
    }
}

struct Tag: View {
    var text: String
    var symbol: String
    var tint: Color? = nil
    var body: some View {
        Label(text, systemImage: symbol).font(.footnote.weight(.semibold)).foregroundStyle(.white).glassPill(tint: tint)
    }
}

struct SectionTitle: View {
    var text: String
    var symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.soft).textCase(.uppercase)
    }
}

/// Minutes-since-midnight as a Date for DatePicker.
func minutesBinding(_ b: Binding<Int>) -> Binding<Date> {
    Binding(get: { Decision.at(.now, b.wrappedValue) },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); b.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) })
}
