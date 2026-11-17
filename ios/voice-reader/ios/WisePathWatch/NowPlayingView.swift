import SwiftUI

/// The book the phone is reading, how far it has got, and the three keys.
struct NowPlayingView: View {
    let link: WristLink

    var body: some View {
        VStack(spacing: 6) {
            if let state = link.state, let title = state.title {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    Circle().trim(from: 0, to: state.progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Yüzde \(Int(state.progress * 100))")
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let author = state.author {
                    Text(author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack {
                    key("gobackward", label: "Geri") { link.send(.back) }
                    key(state.isPlaying ? "pause.fill" : "play.fill", label: state.isPlaying ? "Duraklat" : "Oynat", large: true) {
                        link.send(.toggle)
                    }
                    key("goforward", label: "İleri") { link.send(.forward) }
                }
            } else {
                ContentUnavailableView("Kitap yok", systemImage: "iphone",
                                       description: Text("iPhone'da Wise Path'te bir kitap aç."))
            }
        }
        .navigationTitle("Wise Path")
    }

    private func key(_ symbol: String, label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(large ? .title2 : .body)
                .frame(maxWidth: .infinity, minHeight: large ? 44 : 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

/// Today's listening and the week, as the widgets show it.
struct TodayView: View {
    let link: WristLink

    var body: some View {
        let state = link.state
        VStack(alignment: .leading, spacing: 8) {
            Text("Bugün").font(.caption).foregroundStyle(.secondary)
            Text(minutes(state?.todayMinutes ?? 0))
                .font(.system(.title, design: .rounded).weight(.semibold))
            let week = state?.week ?? []
            let top = max(week.map(\.minutes).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(week, id: \.self) { day in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(day.today ? Color.accentColor : .white.opacity(0.35))
                            .frame(height: max(3, 50 * day.minutes / top))
                        Text(day.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Son yedi gün")
        }
        .padding(.horizontal, 4)
        .navigationTitle("Dinleme")
    }

    private func minutes(_ value: Double) -> String {
        let total = Int(value.rounded())
        return total >= 60 ? "\(total / 60) sa \(total % 60) dk" : "\(total) dk"
    }
}
