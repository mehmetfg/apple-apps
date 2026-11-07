import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryEntry.addedAt, order: .reverse) private var entries: [LibraryEntry]
    @State private var segment = LibrarySegment.priority

    var body: some View {
        NavigationStack {
            List {
                Picker("Liste", selection: $segment) {
                    ForEach(LibrarySegment.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                ForEach(visibleEntries) { entry in
                    row(for: entry)
                        .moveDisabled(segment != .priority)
                }
                .onMove { source, destination in
                    movePriority(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .overlay { emptyState }
            .navigationTitle("Listem")
            .navigationDestination(for: CatalogTitle.self) { TitleDetailView(title: $0) }
            .toolbar(content: reorderToolbar)
        }
    }

    @ToolbarContentBuilder
    private func reorderToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if segment == .priority && visibleEntries.count > 1 {
                EditButton()
            }
        }
    }

    private var visibleEntries: [LibraryEntry] {
        switch segment {
        case .priority:
            entries.filter(\.isPriority).sorted { $0.priorityRank < $1.priorityRank }
        case .listed:
            entries.filter(\.isListed)
        case .watched:
            entries.filter(\.isWatched).sorted { ($0.watchedAt ?? .distantPast) > ($1.watchedAt ?? .distantPast) }
        }
    }

    private func row(for entry: LibraryEntry) -> some View {
        NavigationLink(value: entry.catalogTitle) {
            LibraryRow(entry: entry)
        }
        .swipeActions(edge: .leading) {
            if !entry.isWatched {
                Button("İzledim", systemImage: "checkmark") {
                    actions(for: entry).toggleWatched(title: entry.catalogTitle, entry: entry)
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            trailingActions(for: entry)
        }
    }

    @ViewBuilder
    private func trailingActions(for entry: LibraryEntry) -> some View {
        let library = actions(for: entry)
        switch segment {
        case .priority:
            Button("Öncelikten çıkar", systemImage: "flag.slash") {
                library.togglePriority(title: entry.catalogTitle, entry: entry)
            }
            .tint(.orange)
        case .listed:
            Button("Çıkar", systemImage: "trash", role: .destructive) {
                library.toggleListed(title: entry.catalogTitle, entry: entry)
            }
            Button(entry.isPriority ? "Öncelikten çıkar" : "Öncelikli", systemImage: "flag") {
                library.togglePriority(title: entry.catalogTitle, entry: entry)
            }
            .tint(.orange)
        case .watched:
            Button("İzlemedim", systemImage: "arrow.uturn.backward") {
                library.toggleWatched(title: entry.catalogTitle, entry: entry)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if visibleEntries.isEmpty {
            switch segment {
            case .priority:
                ContentUnavailableView(
                    "Öncelikli yapım yok",
                    systemImage: "flag",
                    description: Text("Bir yapımın sayfasında Öncelikli'ye dokun. Sıralamayı buradan değiştirebilirsin.")
                )
            case .listed:
                ContentUnavailableView(
                    "Listen boş",
                    systemImage: "bookmark",
                    description: Text("Keşfet'ten ya da kamerayla tarayarak yapım ekleyebilirsin.")
                )
            case .watched:
                ContentUnavailableView(
                    "Henüz izlenen yok",
                    systemImage: "checkmark.circle",
                    description: Text("İzlediklerin burada birikir ve önerilerini şekillendirir.")
                )
            }
        }
    }

    private func actions(for entry: LibraryEntry) -> LibraryActions {
        LibraryActions(context: modelContext, genreNames: entry.genreNames)
    }

    private func movePriority(from source: IndexSet, to destination: Int) {
        var ordered = visibleEntries
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in ordered.enumerated() {
            entry.priorityRank = index + 1
        }
    }
}
