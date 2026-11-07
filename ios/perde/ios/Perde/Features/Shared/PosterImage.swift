import SwiftUI

struct PosterImage: View {
    let path: String?
    var width: CGFloat = 64

    var body: some View {
        AsyncImage(url: ServiceEndpoints.poster(path: path)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
