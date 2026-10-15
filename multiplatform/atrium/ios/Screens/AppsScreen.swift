// Apps: every own app and workbench, classified by domain, role and status — editable in place.
import SwiftUI

struct AppsScreen: View {
    @EnvironmentObject var store: VaultStore
    @State private var platform: String?
    @State private var status: String?
    @State private var adding = false

    var body: some View {
        ScrollView {
            if let catalog = store.catalog {
                content(catalog)
            } else {
                ContentUnavailableView("Katalog yok", systemImage: "app.dashed",
                                       description: Text(store.catalogError ?? "\(VaultStore.catalogPath) bekleniyor."))
                    .padding(.top, 80)
            }
        }
        .background(Palette.page)
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Image(systemName: "plus") }.disabled(store.catalog == nil)
            }
        }
        .sheet(isPresented: $adding) {
            if let c = store.catalog {
                AppEditor(app: CatalogApp(id: "", name: "", domain: c.domains.first?.id ?? "system", role: "tool", status: "pilot",
                                          platforms: ["iphone"], purpose: "", since: TurkishCalendar.dayKey(Date())), isNew: true)
            }
        }
        .refreshable { store.loadCatalog() }
    }

    private func content(_ catalog: AppCatalog) -> some View {
        let apps = catalog.apps.filter { (platform == nil || $0.platforms.contains(platform!)) && (status == nil || $0.status == status) }
        return VStack(alignment: .leading, spacing: 16) {
            overview(catalog).appear()
            filters(catalog)
            ForEach(catalog.domains) { d in
                let list = apps.filter { $0.domain == d.id }
                if !list.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: d.symbol ?? "square").foregroundStyle(Color(hex: d.color ?? "#888"))
                        SectionTitle(title: d.label, detail: "\(list.count)")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(list) { app in
                            NavigationLink(value: AppRoute(id: app.id)) { AppCard(app: app, catalog: catalog) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity)
    }

    private func overview(_ c: AppCatalog) -> some View {
        let active = c.apps.filter { $0.status != "retired" }
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(active.count)").font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("canlı uygulama ve tezgâh").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(["iphone", "mac", "web"], id: \.self) { p in
                        Label("\(active.filter { $0.platforms.contains(p) }.count)", systemImage: Self.platformSymbol(p))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .foregroundStyle(.secondary)
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(c.domains) { d in
                        let n = active.filter { $0.domain == d.id }.count
                        if n > 0 {
                            Rectangle().fill(Color(hex: d.color ?? "#888"))
                                .frame(width: g.size.width * CGFloat(n) / CGFloat(max(1, active.count)) - 2)
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .padding(.top, 6)
            HStack(spacing: 10) {
                ForEach(c.domains) { d in
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: d.color ?? "#888")).frame(width: 7, height: 7)
                        Text(d.label).font(.caption2)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func filters(_ c: AppCatalog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Hepsi", on: platform == nil && status == nil) { platform = nil; status = nil }
                ForEach(["iphone", "mac", "web"], id: \.self) { p in
                    filterChip(Self.platformLabel(p), symbol: Self.platformSymbol(p), on: platform == p) { platform = platform == p ? nil : p }
                }
                Divider().frame(height: 20)
                ForEach(c.statuses) { s in
                    filterChip(s.label, on: status == s.id) { status = status == s.id ? nil : s.id }
                }
            }
        }
    }

    private func filterChip(_ title: String, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Palette.accent : Palette.card, in: Capsule())
            .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    static func platformSymbol(_ p: String) -> String {
        switch p { case "iphone": return "iphone"; case "mac": return "laptopcomputer"; default: return "globe" }
    }

    static func platformLabel(_ p: String) -> String {
        switch p { case "iphone": return "iPhone"; case "mac": return "Mac"; default: return "Web" }
    }

    static func statusColor(_ s: String) -> Color {
        switch s { case "active": return Palette.teal; case "pilot": return Palette.amber; case "idle": return .gray; default: return Palette.rose }
    }
}

struct AppCard: View {
    @EnvironmentObject var store: VaultStore
    var app: CatalogApp
    var catalog: AppCatalog

    var body: some View {
        let domain = catalog.domain(app.domain)
        let color = Color(hex: domain?.color ?? "#888")
        HStack(alignment: .top, spacing: 14) {
            AppGlyph(name: app.name, color: color, symbol: domain?.symbol)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(app.name).font(.headline)
                    ForEach(app.platforms, id: \.self) { Image(systemName: AppsScreen.platformSymbol($0)).font(.caption).foregroundStyle(.secondary) }
                }
                Text(app.purpose).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Pill(text: catalog.status(app.status)?.label ?? app.status, color: AppsScreen.statusColor(app.status))
                    Pill(text: catalog.role(app.role)?.label ?? app.role, color: color)
                    if let last = store.lastActivity(source: app.source) {
                        Text(TurkishCalendar.relative(last)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(app.status == "retired" ? 0.55 : 1)
    }
}

struct AppGlyph: View {
    var name: String
    var color: Color
    var symbol: String?
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)))
                .font(.system(size: size * 0.46, weight: .bold, design: .serif)).foregroundStyle(.white)
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.3), radius: 5, y: 3)
    }
}

struct AppDetailScreen: View {
    @EnvironmentObject var store: VaultStore
    var appId: String
    @State private var editing = false
    @State private var readme: String?

    var body: some View {
        if let catalog = store.catalog, let app = catalog.apps.first(where: { $0.id == appId }) {
            let domain = catalog.domain(app.domain)
            let color = Color(hex: domain?.color ?? "#888")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AppGlyph(name: app.name, color: color, symbol: domain?.symbol, size: 76)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name).font(.largeTitle.weight(.bold)).fontDesign(.rounded)
                            Text(app.purpose).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    Card {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            row("Alan", domain?.label ?? app.domain)
                            row("Rol", catalog.role(app.role)?.label ?? app.role)
                            row("Durum", catalog.status(app.status)?.label ?? app.status)
                            row("Cihaz", app.platforms.map(AppsScreen.platformLabel).joined(separator: " · "))
                            if let s = app.since { row("Kuruluş", s) }
                            if let b = app.bundleId { row("Paket", b) }
                            if let src = app.source { row("Kaynak", src) }
                            if let last = store.lastActivity(source: app.source) { row("Son not", TurkishCalendar.relative(last)) }
                        }
                        .font(.subheadline)
                        #if os(macOS)
                        if app.platforms.contains("mac") {
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(app.name).app")
                            if FileManager.default.fileExists(atPath: url.path) {
                                Button { NSWorkspace.shared.open(url) } label: { Label("Mac'te aç", systemImage: "arrow.up.forward.app") }
                                    .buttonStyle(.borderedProminent).tint(color).padding(.top, 8)
                            }
                        }
                        #endif
                    }
                    if let readme {
                        SectionTitle(title: "README")
                        Card { MarkdownView(text: readme, accent: color) }
                            .noteLinks(source: app.readme)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .navigationTitle(app.name)
            .toolbar { ToolbarItem { Button("Tasnif et") { editing = true } } }
            .sheet(isPresented: $editing) { AppEditor(app: app, isNew: false) }
            .task(id: app.readme) {
                guard let p = app.readme, let t = try? await store.read(p).text else { readme = nil; return }
                readme = Frontmatter.split(t).body
            }
        } else {
            ContentUnavailableView("Uygulama bulunamadı", systemImage: "questionmark.app")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}

struct AppEditor: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State var app: CatalogApp
    var isNew: Bool

    var body: some View {
        NavigationStack {
            if let c = store.catalog {
                Form {
                    Section("Ad") {
                        TextField("Ad", text: $app.name)
                        TextField("Ne işe yarar", text: $app.purpose, axis: .vertical).lineLimit(2...5)
                    }
                    Section("Tasnif") {
                        Picker("Alan", selection: $app.domain) { ForEach(c.domains) { Text($0.label).tag($0.id) } }
                        Picker("Rol", selection: $app.role) { ForEach(c.roles) { Text($0.label).tag($0.id) } }
                        Picker("Durum", selection: $app.status) { ForEach(c.statuses) { Text($0.label).tag($0.id) } }
                    }
                    Section("Cihaz") {
                        ForEach(["iphone", "mac", "web"], id: \.self) { p in
                            Toggle(isOn: Binding(get: { app.platforms.contains(p) }, set: { on in
                                if on { app.platforms.append(p) } else { app.platforms.removeAll { $0 == p } }
                            })) { Label(AppsScreen.platformLabel(p), systemImage: AppsScreen.platformSymbol(p)) }
                        }
                    }
                    Section("Vault'taki yeri") {
                        TextField("Kaynak klasör", text: Binding(get: { app.source ?? "" }, set: { app.source = $0.isEmpty ? nil : $0 }))
                        TextField("README yolu", text: Binding(get: { app.readme ?? "" }, set: { app.readme = $0.isEmpty ? nil : $0 }))
                    }
                }
                .navigationTitle(isNew ? "Yeni uygulama" : "Tasnif et")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            var updated = c
                            if isNew {
                                app.id = app.name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
                                    .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
                                updated.apps.append(app)
                            } else if let i = updated.apps.firstIndex(where: { $0.id == app.id }) {
                                updated.apps[i] = app
                            }
                            Task { await store.saveCatalog(updated); dismiss() }
                        }
                        .disabled(app.name.isEmpty)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
