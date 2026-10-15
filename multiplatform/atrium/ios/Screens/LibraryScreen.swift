// Library: the vault's areas as tiles, folders, and search.
import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject var store: VaultStore

    var body: some View {
        let areas = store.areas().sorted { $0.lastTouched > $1.lastTouched }
        let rootNotes = store.children(of: "").notes
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Alanlar", detail: "\(areas.count) klasör")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(Array(areas.enumerated()), id: \.element.id) { i, a in
                        NavigationLink(value: FolderRoute(path: a.name)) { AreaTile(area: a) }
                            .buttonStyle(.plain)
                            .appear(Double(min(i, 12)) * 0.03)
                    }
                }
                if !rootNotes.isEmpty {
                    SectionTitle(title: "Kökteki notlar", detail: "\(rootNotes.count)")
                    NoteList(notes: rootNotes.sorted { $0.modified > $1.modified })
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .refreshable { await store.refresh() }
    }
}

struct AreaTile: View {
    var area: AreaSummary
    var body: some View {
        let color = Palette.area(area.name)
        let total = max(1, area.origins.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill").font(.title3).foregroundStyle(color)
                Spacer()
                if area.touchedThisWeek > 0 {
                    Text("\(area.touchedThisWeek) bu hafta").font(.caption2.weight(.bold)).foregroundStyle(color)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.14), in: Capsule())
                }
            }
            Text(area.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .topLeading)
            GeometryReader { g in
                HStack(spacing: 1.5) {
                    ForEach(Origin.allCases.filter { (area.origins[$0] ?? 0) > 0 }) { o in
                        Rectangle().fill(Palette.origin(o)).frame(width: max(3, g.size.width * CGFloat(area.origins[o]!) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack {
                Text("\(Format.number(area.notes)) not").font(.caption.weight(.semibold))
                Spacer()
                Text(TurkishCalendar.relative(area.lastTouched)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [color.opacity(0.13), Palette.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.18)))
    }
}

struct NoteList: View {
    var notes: [NoteRecord]
    var showFolder = false
    var body: some View {
        Card(padding: 6) {
            LazyVStack(spacing: 0) {
                ForEach(notes) { n in
                    NavigationLink(value: NoteRoute(path: n.path)) { NoteRow(note: n, showFolder: showFolder).padding(10) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FolderScreen: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    var path: String
    @State private var sort = 0

    var body: some View {
        let content = store.children(of: path)
        let notes = sort == 0 ? content.notes.sorted { $0.modified > $1.modified } : content.notes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(path.split(separator: "/").dropLast().joined(separator: " › "))
                    .font(.caption).foregroundStyle(.secondary)
                if !content.folders.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(content.folders) { f in
                            NavigationLink(value: FolderRoute(path: path + "/" + f.name)) { AreaTile(area: f) }.buttonStyle(.plain)
                        }
                    }
                }
                if !notes.isEmpty {
                    HStack {
                        SectionTitle(title: "Notlar", detail: "\(notes.count)")
                        Picker("", selection: $sort) {
                            Image(systemName: "clock").tag(0)
                            Image(systemName: "textformat").tag(1)
                        }
                        .pickerStyle(.segmented).frame(width: 100)
                    }
                    NoteList(notes: notes)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .navigationTitle(path.split(separator: "/").last.map(String.init) ?? path)
        .toolbar {
            ToolbarItem {
                Button { router.composeKind = .note; UserDefaults.standard.set(path, forKey: "composeFolder") } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }
}

struct SearchScreen: View {
    @EnvironmentObject var store: VaultStore
    @State private var query = ""
    @State private var contentHits: [(NoteRecord, String)] = []
    @State private var searching = false
    @State private var kind: NoteKind?

    var body: some View {
        let names = store.search(query).filter { kind == nil || $0.kind == kind }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(nil, "Hepsi", "square.grid.2x2")
                        ForEach(NoteKind.allCases) { k in chip(k, k.label, k.symbol) }
                    }
                }
                if query.isEmpty {
                    SectionTitle(title: kind == nil ? "Son dokunulanlar" : kind!.label)
                    NoteList(notes: Array(store.records.filter { kind == nil || $0.kind == kind }.prefix(40)), showFolder: true)
                } else {
                    if !names.isEmpty {
                        SectionTitle(title: "Adında geçenler", detail: "\(names.count)")
                        NoteList(notes: names, showFolder: true)
                    }
                    SectionTitle(title: "Metninde geçenler", detail: searching ? "aranıyor…" : "\(contentHits.count)")
                    Card(padding: 6) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(contentHits, id: \.0.id) { hit in
                                NavigationLink(value: NoteRoute(path: hit.0.path)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        NoteRow(note: hit.0)
                                        Text(hit.1).font(.caption).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 48)
                                    }
                                    .padding(10)
                                }
                                .buttonStyle(.plain)
                            }
                            if contentHits.isEmpty && !searching {
                                Text(query.count < 3 ? "Metin araması için en az 3 harf." : "Metinde bulunamadı.")
                                    .font(.subheadline).foregroundStyle(.secondary).padding(12)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .searchable(text: $query, prompt: "Not adı ya da metin")
        .task(id: query) {
            contentHits = []
            guard query.count >= 3 else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            searching = true
            let hits = await store.searchContents(query)
            if !Task.isCancelled { contentHits = hits.filter { kind == nil || $0.0.kind == kind } }
            searching = false
        }
    }

    private func chip(_ k: NoteKind?, _ title: String, _ symbol: String) -> some View {
        let on = kind == k
        let color = k.map(Palette.kind) ?? Palette.accent
        return Button { kind = k } label: {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(on ? color : color.opacity(0.12), in: Capsule())
                .foregroundStyle(on ? .white : color)
        }
        .buttonStyle(.plain)
    }
}
