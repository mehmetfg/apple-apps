// The mark key: a tap marks the sentence being read (or the one that just ended); held, the mark grows back over the
// sentences already heard, one more every 0.6 s, with a tick and a count on the key.
import SwiftUI

struct MarkHold: ViewModifier {
    @Environment(AppModel.self) private var model
    var mark: () -> Void
    @Binding var count: Int                  // sentences in the mark while held (0 = not holding)
    @State private var task: Task<Void, Never>?

    static let firstStep = 0.45
    static let step = 0.6

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { mark() }
            .onLongPressGesture(minimumDuration: Self.firstStep, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
                task?.cancel()
                guard pressing else {
                    if count > 0 { Task { try? await Task.sleep(for: .seconds(1.2)); count = 0 } }
                    return
                }
                task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.firstStep))
                    guard !Task.isCancelled else { return }
                    if !model.spokenSentenceMarked { mark() }
                    count = model.markChain?.count ?? 1
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(Self.step))
                        guard !Task.isCancelled, let n = model.extendMarkBack() else { return }
                        count = n
                    }
                }
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Bir önceki cümleyi de ekle") { _ = model.extendMarkBack() }
    }
}
