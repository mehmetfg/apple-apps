// The reading card on the lock screen and in the Dynamic Island, and the keys for Control Center, the lock screen
// corners and the Action Button (2026-11-06).
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let cardAmber = Color(red: 0.93, green: 0.62, blue: 0.22)

private struct CardKeys: View {
    let state: ReadingActivity.ContentState
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ToggleReadingIntent()) {
                Image(systemName: state.playing ? "pause.fill" : "play.fill").frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel(state.playing ? "Durdur" : "Oku")
            Button(intent: MarkSentenceIntent()) {
                Label(state.marks > 0 ? "\(state.marks)" : "İşaretle", systemImage: "highlighter").frame(maxWidth: .infinity, minHeight: 36)
            }
            .tint(cardAmber)
            .accessibilityLabel("Cümleyi işaretle")
            Button(intent: VoiceNoteIntent()) {
                Image(systemName: state.recording ? "stop.fill" : "mic.fill").frame(maxWidth: .infinity, minHeight: 36)
            }
            .tint(state.recording ? .red : nil)
            .accessibilityLabel(state.recording ? "Notu bitir" : "Sesli not")
        }
        .buttonStyle(.bordered)
    }
}

struct ReadingCardWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivity.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Spacer()
                    Text(context.state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                }
                if !context.state.chapter.isEmpty {
                    Text(context.state.chapter).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                ProgressView(value: context.state.progress).tint(cardAmber)
                CardKeys(state: context.state)
            }
            .padding(14)
            .foregroundStyle(.white)
            .tint(.white)
            .activityBackgroundTint(Color.black.opacity(0.72))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.fill").foregroundStyle(cardAmber)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) { CardKeys(state: context.state) }
            } compactLeading: {
                Image(systemName: context.state.recording ? "mic.fill" : "book.fill")
                    .foregroundStyle(context.state.recording ? .red : cardAmber)
            } compactTrailing: {
                Text(context.state.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.caption2)
            } minimal: {
                Image(systemName: "book.fill").foregroundStyle(cardAmber)
            }
        }
    }
}

@available(iOS 18.0, *)
struct ToggleReadingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.okur.control.toggle") {
            ControlWidgetButton(action: ToggleReadingIntent()) { Label("Oku / Durdur", systemImage: "playpause.fill") }
                .tint(cardAmber)
        }
        .displayName("Oku / Durdur")
        .description("Wise Path okumayı kaldığın yerden sürdürür ya da durdurur.")
    }
}

@available(iOS 18.0, *)
struct MarkSentenceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.okur.control.mark") {
            ControlWidgetButton(action: MarkSentenceIntent()) { Label("Cümleyi işaretle", systemImage: "highlighter") }
                .tint(cardAmber)
        }
        .displayName("Cümleyi işaretle")
        .description("Wise Path'te o an okunan cümleyi işaretler.")
    }
}

@available(iOS 18.0, *)
struct VoiceNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.fatihgocgun.okur.control.note") {
            ControlWidgetButton(action: VoiceNoteIntent()) { Label("Sesli not", systemImage: "mic.fill") }
                .tint(.red)
        }
        .displayName("Sesli not")
        .description("Wise Path'te okunan cümleye sesli not alır.")
    }
}
