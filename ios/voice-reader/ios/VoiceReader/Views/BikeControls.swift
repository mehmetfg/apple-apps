// Bicycle mode's bottom bar: three equal glass keys a gloved thumb can hit (voice note · play · mark), a thin progress
// line, and the colour sets they can wear (Görsel Ayarlar › Bisiklet Düğmeleri).
import SwiftUI

/// The bicycle keys' colours. Crystal is clear glass with coloured symbols; the others are tinted glass.
enum BikeStyle: String, CaseIterable, Identifiable, Sendable {
    case crystal, classic, ocean, forest, sunset, graphite
    var id: String { rawValue }
    var name: String {
        switch self {
        case .crystal: "Kristal"
        case .classic: "Klasik"
        case .ocean: "Okyanus"
        case .forest: "Orman"
        case .sunset: "Gün batımı"
        case .graphite: "Grafit"
        }
    }
    var solid: Bool { self != .crystal }

    enum Key { case mic, play, mark }

    func tint(_ k: Key, accent: Accent) -> Color {
        switch (self, k) {
        case (.crystal, .mic): Self.c(0x0A84FF)
        case (.crystal, .play): Palette.play
        case (.crystal, .mark): Self.c(0xE8B400)
        case (.classic, .mic): accent.ink
        case (.classic, .play): Palette.play
        case (.classic, .mark): Self.c(0xFFED33)
        case (.ocean, .mic): Self.c(0x12355B)
        case (.ocean, .play): Self.c(0x1B998B)
        case (.ocean, .mark): Self.c(0x8EDCE6)
        case (.forest, .mic): Self.c(0x2D4A35)
        case (.forest, .play): Self.c(0x4F7942)
        case (.forest, .mark): Self.c(0xC5D86D)
        case (.sunset, .mic): Self.c(0x6A2C70)
        case (.sunset, .play): Self.c(0xE84545)
        case (.sunset, .mark): Self.c(0xF9D56E)
        case (.graphite, .mic): Self.c(0x3A3A3C)
        case (.graphite, .play): Self.c(0x636366)
        case (.graphite, .mark): Self.c(0xD1D1D6)
        }
    }

    /// Symbol and label colour on the key.
    func ink(_ k: Key, accent: Accent) -> Color {
        if !solid { return tint(k, accent: accent) }
        return k == .mark ? .black.opacity(0.85) : .white
    }

    private static func c(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The glass of one key: Liquid Glass on iOS 26 (tinted for the coloured sets), a material with a fine edge before.
private struct BikeGlass: ViewModifier {
    let tint: Color
    let solid: Bool
    var dimmed = false
    static let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    func body(content: Content) -> some View {
        let amount = solid ? (dimmed ? 0.42 : 0.86) : (dimmed ? 0.06 : 0.13)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(amount)).interactive(), in: Self.shape)
        } else {
            content
                .background {
                    Self.shape.fill(.ultraThinMaterial)
                    Self.shape.fill(tint.opacity(amount))
                }
                .overlay(Self.shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)],
                                                                startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        }
    }
}

/// A key's face: symbol over a short label, all keys the same size.
private struct KeyFace: View {
    let symbol: String
    let label: String
    let ink: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(height: 34)
            Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, minHeight: 88)
        .contentShape(BikeGlass.shape)
    }
}

/// Bicycle mode's bar: voice note · play · mark, equal in size, and a thin progress line.
struct BikeBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let theme: ReaderTheme
    @State private var marked = 0
    @State private var held = 0

    var body: some View {
        let p = model.player
        let style = model.settings.bikeStyle
        VStack(spacing: 0) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: theme.hairline).opacity(0.35))
                    Capsule().fill(accent.fill).frame(width: max(4, g.size.width * Double(p.cursor) / Double(max(1, p.length))))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            HStack(spacing: 10) {
                BikeMicButton(style: style)
                Button { p.toggle() } label: {
                    KeyFace(symbol: p.isPlaying ? "pause.fill" : "play.fill", label: p.isPlaying ? "Duraklat" : "Oynat",
                            ink: style.ink(.play, accent: accent))
                }
                .contextMenu { ActivePauseMenu() }
                .modifier(BikeGlass(tint: style.tint(.play, accent: accent), solid: style.solid))
                .accessibilityLabel(p.isPlaying ? "Duraklat" : "Oynat")
                // a second press on the same sentence takes its mark away
                let on = model.spokenSentenceMarked
                ZStack {
                    KeyFace(symbol: held > 1 ? "text.line.first.and.arrowtriangle.forward" : on ? "eraser" : "highlighter",
                            label: held > 1 ? "\(held) cümle" : on ? "Kaldır" : "İşaretle", ink: style.ink(.mark, accent: accent))
                }
                .modifier(BikeGlass(tint: style.tint(.mark, accent: accent), solid: style.solid, dimmed: on))
                .modifier(MarkHold(mark: { model.markSpokenSentence(); marked += 1 }, count: $held))
                .overlay {
                    if on {
                        BikeGlass.shape.strokeBorder(style.ink(.mark, accent: accent).opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .padding(3).allowsHitTesting(false)
                    }
                }
                .sensoryFeedback(.success, trigger: marked)
                .accessibilityLabel(on ? "Okunan cümlenin işaretini kaldır" : "Okunan cümleyi işaretle")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(Color(uiColor: theme.chrome).ignoresSafeArea(edges: .bottom))
    }
}

/// Bicycle microphone: hold one second to start (a ring runs round the key while holding), tap to stop.
struct BikeMicButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent
    let style: BikeStyle
    @State private var holding = false
    @State private var started = 0

    var body: some View {
        let rec = model.recorder
        let on = rec.isRecording
        let ink: Color = on ? .white : style.ink(.mic, accent: accent)
        KeyFace(symbol: on ? "stop.fill" : "mic.fill", label: on ? "Bitir" : "Basılı tut", ink: ink)
            .background {
                if on {
                    BikeGlass.shape.fill(Color.red.opacity(0.25)).scaleEffect(1 + CGFloat(rec.level) * 0.08)
                        .animation(.easeOut(duration: 0.12), value: rec.level)
                }
            }
            .modifier(BikeGlass(tint: on ? .red : style.tint(.mic, accent: accent), solid: on || style.solid))
            .overlay {
                BikeGlass.shape.trim(from: 0, to: holding ? 1 : 0)
                    .stroke(ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(3)
                    .animation(holding ? .linear(duration: MicHold.seconds) : .easeOut(duration: 0.15), value: holding)
                    .allowsHitTesting(false)
            }
            .onTapGesture { if on { model.finishVoiceNote() } }
            .onLongPressGesture(minimumDuration: MicHold.seconds, perform: {
                guard !model.recorder.isRecording else { return }
                started += 1
                model.startVoiceNote()
            }, onPressingChanged: { p in holding = p && !model.recorder.isRecording })
            .sensoryFeedback(.impact(weight: .heavy), trigger: started)
            .accessibilityLabel(on ? "Sesli notu bitir" : "Sesli not: yarım saniye basılı tut")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleVoiceNote() }
    }
}

/// Görsel Ayarlar › Bisiklet Düğmeleri: the colour sets, each shown as its three keys.
struct BikeStylePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accent) private var accent

    var body: some View {
        @Bindable var s = model.settings
        List {
            Section {
                ForEach(BikeStyle.allCases) { st in
                    Button { s.bikeStyle = st } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                swatch(st, .mic, "mic.fill")
                                swatch(st, .play, "play.fill")
                                swatch(st, .mark, "highlighter")
                            }
                            .frame(width: 168)
                            Text(st.name).foregroundStyle(.primary)
                            Spacer()
                            if s.bikeStyle == st { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(accent.ink) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(s.bikeStyle == st ? .isSelected : [])
                }
            } footer: {
                Text("Kristal saydam camdır, simgeler renklidir. Ötekiler renkli camdır. Klasik'te mikrofon uygulama rengini alır.")
            }
        }
        .navigationTitle("Bisiklet Düğmeleri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func swatch(_ st: BikeStyle, _ k: BikeStyle.Key, _ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(st.ink(k, accent: accent))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(st.tint(k, accent: accent).opacity(st.solid ? 0.88 : 0.14))
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 0.8)
            }
    }
}
