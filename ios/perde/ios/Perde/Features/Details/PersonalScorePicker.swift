import SwiftData
import SwiftUI

struct PersonalScorePicker: View {
    @Bindable var entry: LibraryEntry

    var body: some View {
        Picker("Benim puanım", selection: $entry.personalScore) {
            Text("Puanlamadım").tag(Int?.none)
            ForEach((1...10).reversed(), id: \.self) { score in
                Text(String(score)).tag(Int?.some(score))
            }
        }
        .pickerStyle(.menu)
    }
}
