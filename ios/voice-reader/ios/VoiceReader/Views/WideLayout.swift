// The reading column of the wide layout (2026-11-17): on an iPad, an unfolded phone or a wide Stage Manager window
// the library sits in a sidebar and this page fills the other side until a book is opened: the book to go on with,
// large, and a key that opens it.
import SwiftUI

struct WideReadingWelcome: View {
    @Environment(AppModel.self) private var model
    var onOpen: (UUID) -> Void

    private var book: DocumentRecord? {
        if let id = model.player.documentID, let d = model.store.document(id) { return d }
        return model.store.documents.filter { $0.lastOpenedAt != nil && !$0.isFinished }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    var body: some View {
        ZStack {
            InkBackground()
            if let d = book {
                VStack(spacing: 18) {
                    Button { onOpen(d.id) } label: {
                        CoverView(doc: d, width: 220)
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d.title), aç")
                    VStack(spacing: 6) {
                        Text(d.title).font(.title2.weight(.semibold)).fontDesign(.serif)
                            .multilineTextAlignment(.center).lineLimit(3)
                        if let a = d.author { Text(a).font(.body).foregroundStyle(.secondary) }
                        StateLabel(doc: d)
                    }
                    .frame(maxWidth: 420)
                    Button { onOpen(d.id) } label: {
                        Label("Kaldığın yerden", systemImage: "book.pages")
                            .font(.headline)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
            } else {
                ContentUnavailableView("Bir kitap seç", systemImage: "books.vertical",
                                       description: Text("Kütüphaneden bir kitaba dokun; burada açılır."))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
