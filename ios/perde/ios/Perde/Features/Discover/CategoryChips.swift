import SwiftUI

struct CategoryChips: View {
    @Binding var selection: TasteCategory

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(TasteCategory.allCases) { category in
                    Button(category.label) {
                        selection = category
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(selection == category ? Color.accentColor : Color.secondary.opacity(0.15), in: .capsule)
                    .foregroundStyle(selection == category ? Color.white : Color.primary)
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == category ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }
}
