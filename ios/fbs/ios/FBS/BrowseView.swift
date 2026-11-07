// Göz At: every category in one list, and the detail screens (contract, product, category, ledger, documents, settings).
import Charts
import PDMBus
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BrowseView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        let ins = d.records.filter(\.isIncome).count, outs = d.records.count - ins
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TabHeader(title: "Göz At")
                    SectionTitle(text: "Varlıklar")
                    group {
                        row("Sözleşmeler ve abonelikler", "\(d.active.count) aktif · ayda \(TL.text(d.monthlyLoad))", "doc.text.fill", .sleep) { ContractList() }
                        row("Garantiler", "\(d.products.count) ürün", "checkmark.shield.fill", Color(light: 0x00968F, dark: 0x2FC0B8)) { ProductList() }
                        row("Hane", store.household.map(\.name).joined(separator: " · "), "person.2.fill", .calm) { HouseholdView() }
                    }
                    SectionTitle(text: "Para")
                    group {
                        row("Kayıt defteri", "Girdi \(ins) · Süreç \(d.contracts.count + d.products.count) · Çıktı \(outs)", "list.bullet.rectangle.fill", .money) { LedgerView() }
                        row("Kategoriler", "Son 12 ayın giderleri", "square.grid.3x3.fill", .watch) { CategoryList() }
                        row("Belgeler", store.inboxWaiting > 0 ? "\(store.inboxWaiting) belge telefonda bekliyor" : "Fatura, sözleşme, fiş ekle", "doc.viewfinder.fill",
                            Color(light: 0x8E8E93, dark: 0xAEAEB2)) { DocumentsView() }
                    }
                    SectionTitle(text: "Sistem")
                    group { row("Ayarlar ve kaynaklar", store.origin.isEmpty ? "—" : store.origin, "gearshape.fill", Color(light: 0x636366, dark: 0x8E8E93)) { SettingsView() } }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View { Card(padding: 4) { VStack(spacing: 0) { content() } } }

    private func row<D: View>(_ title: String, _ detail: String, _ symbol: String, _ color: Color, @ViewBuilder to: @escaping () -> D) -> some View {
        NavigationLink(destination: to) {
            HStack(spacing: 12) {
                TileIcon(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - contracts

struct ContractRow: View {
    var contract: Contract
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        let k = Catalog.kind(contract.kind)
        NavigationLink { ContractDetail(contractID: contract.id) } label: {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    TileIcon(symbol: k.symbol, color: Catalog.category(k.category).color, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contract.provider.ifEmpty(k.name)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text([k.name, d.name(contract.holder), contract.label].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TL.text(contract.amount, currency: contract.currency)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                        Text(contract.yearly ? "yılda" : (d.nextBill(contract).map { "fatura " + Day.dayMonth($0) } ?? "ayda")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .opacity(contract.isActive ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ContractList: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router

    var body: some View {
        let groups = Dictionary(grouping: store.contracts) { Catalog.kind($0.kind).name }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.contracts.isEmpty {
                    Text("Henüz sözleşme yok. Hatlar, internet, kira, aidat, sigorta ve dijital abonelikler buraya girer.").foregroundStyle(.secondary)
                }
                ForEach(groups.keys.sorted(), id: \.self) { k in
                    SectionTitle(text: k, trailing: "\(groups[k]!.count)")
                    ForEach(groups[k]!.sorted { $0.provider < $1.provider }) { ContractRow(contract: $0) }
                }
                Button { router.add = .contract } label: { Label("Sözleşme ekle", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.glassProminent).padding(.top, 8)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Sözleşmeler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContractDetail: View {
    var contractID: String
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var askDelete = false

    var body: some View {
        let d = Derived(store)
        if let c = store.contracts.first(where: { $0.id == contractID }) {
            let k = Catalog.kind(c.kind)
            let pays = d.payments(c)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        TileIcon(symbol: k.symbol, color: Catalog.category(k.category).color, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.provider.ifEmpty(k.name)).font(.title2.bold())
                            Text([k.name, d.name(c.holder), c.label].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TL.text(c.amount, currency: c.currency)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(c.yearly ? "yılda" : "ayda").font(.title3).foregroundStyle(.secondary)
                        if let pct = d.priceChange(c) {
                            Text("%\(String(format: "%+.0f", pct))").font(.footnote.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background((pct > 0 ? Color.spend : Color.money).opacity(0.15), in: Capsule()).foregroundStyle(pct > 0 ? Color.spend : Color.money)
                        }
                    }
                    if let p = d.commitmentProgress(c), let e = Day.parse(c.commitmentEnd) {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Taahhüt").font(.headline)
                                    Spacer()
                                    let n = Day.daysFromToday(e)
                                    Text(n >= 0 ? "\(n) gün kaldı" : "bitti").font(.subheadline.weight(.semibold)).foregroundStyle(n <= 30 ? Color.attention : .secondary)
                                }
                                TimeStrip(progress: p, color: Day.daysFromToday(e) <= 30 ? .attention : .sleep)
                                HStack { Text(Day.short(c.start)); Spacer(); Text(Day.short(c.commitmentEnd)) }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let next = d.nextBill(c) {
                        Card(padding: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sıradaki fatura").font(.caption).foregroundStyle(.secondary)
                                    Text("\(Day.dayMonth(next)) · \(Day.relative(next))").font(.headline)
                                }
                                Spacer()
                                Button("Bu ayı ödendi say") { store.markPaid(c, on: .now) }.buttonStyle(.glass)
                                    .disabled(d.payment(for: c, near: next) != nil || d.payment(for: c, near: Day.cal.date(byAdding: .month, value: -1, to: next)!) != nil && Day.daysFromToday(next) > 20)
                            }
                        }
                    }
                    SectionTitle(text: "Künye")
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            line("Kimin adına", d.name(c.holder))
                            line("Başlangıç", Day.short(c.start))
                            line("Taahhüt bitişi", c.commitmentEnd.map { Day.short($0) } ?? "Taahhüt yok")
                            line("Dönem", c.yearly ? "Yıllık" : "Aylık")
                            if let bd = c.billDay { line("Fatura günü", "Her ayın \(bd)'i") }
                            line("Ödeme", c.payMethod ?? "—")
                            line("Cayma bedeli", c.exitFee ?? "—")
                            line("Fiyat şartı", c.priceClause ?? "—")
                            line("Durum", c.isActive ? "Aktif" : "Sona erdi")
                            line("Kaynak", c.isPhone ? "Telefonda girildi" : "Belgeden (Mac)")
                        }
                    }
                    if let terms = c.keyTerms, !terms.isEmpty {
                        SectionTitle(text: "Ana maddeler")
                        Card {
                            VStack(alignment: .leading, spacing: 8) { ForEach(terms, id: \.self) { Bullet(text: $0, color: .sleep) } }
                        }
                    }
                    if pays.count > 1 {
                        SectionTitle(text: "Ödemelerin seyri")
                        Card {
                            Chart(pays) { p in
                                LineMark(x: .value("Tarih", Day.parse(p.date) ?? .now), y: .value("Tutar", p.amount))
                                    .foregroundStyle(Color.sleep).interpolationMethod(.stepEnd).lineStyle(StrokeStyle(lineWidth: 3))
                                PointMark(x: .value("Tarih", Day.parse(p.date) ?? .now), y: .value("Tutar", p.amount)).foregroundStyle(Color.sleep)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 160)
                        }
                    }
                    if !pays.isEmpty {
                        SectionTitle(text: "Ödemeler", trailing: "\(pays.count)")
                        Card(padding: 4) { VStack(spacing: 0) { ForEach(pays.reversed()) { MoneyRow(money: $0) } } }
                    }
                    if let n = c.note, !n.isEmpty { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    if c.isPhone {
                        HStack {
                            Button { editing = true } label: { Label("Düzenle", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                            Button(role: .destructive) { askDelete = true } label: { Label("Sil", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                        }
                    } else {
                        Text("Bu sözleşme bir belgeden okundu; düzeltmesi Mac'te (\"FBS'yi düzenle\").").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .sbsGround()
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { AddSheet(mode: .contract, contract: c).environmentObject(store) }
            .confirmationDialog("Sözleşme silinsin mi?", isPresented: $askDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) { store.delete(contract: c.id); dismiss() }
            } message: { Text("Ödeme kayıtları durur; yalnız sözleşme kalkar.") }
        } else {
            Text("Sözleşme bulunamadı.").foregroundStyle(.secondary)
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(v).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

// MARK: - products

struct ProductList: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.products.isEmpty { Text("Henüz garanti kaydı yok.").foregroundStyle(.secondary) }
                ForEach(store.products.sorted { ($0.warrantyEnd ?? "") > ($1.warrantyEnd ?? "") }) { p in
                    NavigationLink { ProductDetail(productID: p.id) } label: { ProductCard(product: p) }.buttonStyle(.plain)
                }
                Button { router.add = .product } label: { Label("Garantili ürün ekle", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 6) }
                    .buttonStyle(.glassProminent).padding(.top, 8)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Garantiler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProductDetail: View {
    var productID: String
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        if let p = store.products.first(where: { $0.id == productID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProductCard(product: p)
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            ForEach([("Alış", Day.short(p.bought)), ("Fiyat", TL.text(p.price)), ("Satıcı", p.seller ?? "—"),
                                     ("Garanti bitişi", Day.short(p.warrantyEnd)), ("Kaynak", p.isPhone ? "Telefonda girildi" : "Belgeden (Mac)")], id: \.0) { k, v in
                                HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(.medium) }.font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                            }
                        }
                    }
                    if let n = p.note, !n.isEmpty { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    if p.isPhone {
                        HStack {
                            Button { editing = true } label: { Label("Düzenle", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                            Button(role: .destructive) { store.delete(product: p.id); dismiss() } label: { Label("Sil", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 4) }.buttonStyle(.glass)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .sbsGround()
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { AddSheet(mode: .product, product: p).environmentObject(store) }
        }
    }
}

// MARK: - money

struct MoneyRow: View {
    var money: Money
    @EnvironmentObject private var store: Store
    @State private var editing = false

    var body: some View {
        let c = Catalog.category(money.category)
        HStack(spacing: 12) {
            Image(systemName: money.isIncome ? "arrow.down.circle.fill" : c.symbol).font(.footnote.weight(.semibold))
                .foregroundStyle(money.isIncome ? Color.money : c.color).frame(width: 28, height: 28)
                .background((money.isIncome ? Color.money : c.color).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(money.party?.ifEmpty(c.name) ?? c.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text([Day.short(money.date), c.name, money.method].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text((money.isIncome ? "+" : "−") + TL.text(money.amount, currency: money.currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(money.isIncome ? Color.money : .primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if money.isPhone { editing = true } }
        .contextMenu {
            if money.isPhone {
                Button { editing = true } label: { Label("Düzenle", systemImage: "pencil") }
                Button(role: .destructive) { store.delete(money: money.id) } label: { Label("Sil", systemImage: "trash") }
            }
        }
        .sheet(isPresented: $editing) { AddSheet(mode: money.isIncome ? .income : .expense, money: money).environmentObject(store) }
    }
}

struct LedgerView: View {
    @EnvironmentObject private var store: Store
    @State private var kind = "output"
    @State private var query = ""

    var body: some View {
        let d = Derived(store)
        let text = ["input": "Gelen para: maaş, ek gelir, iade.", "process": "Zamana yayılanlar: sözleşmeler ve garantiler.",
                    "output": "Giden para: faturalar, ödemeler, alışveriş.", "asset": "Kayıtların dayandığı kalıcı şeyler."]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Tür", selection: $kind) {
                    Text("Girdi").tag("input"); Text("Süreç").tag("process"); Text("Çıktı").tag("output"); Text("Varlık").tag("asset")
                }
                .pickerStyle(.segmented)
                Text(text[kind] ?? "").font(.subheadline).foregroundStyle(.secondary)
                switch kind {
                case "process":
                    ForEach(d.contracts.filter { $0.commitmentEnd != nil || $0.start != nil }) { ContractRow(contract: $0) }
                    ForEach(d.products) { ProductCard(product: $0) }
                case "asset":
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            asset("Sözleşme ve abonelik", d.contracts.count, "doc.text.fill")
                            asset("Garantili ürün", d.products.count, "checkmark.shield.fill")
                            asset("Hane", store.household.count, "person.2.fill")
                        }
                    }
                default:
                    let rows = d.records.filter { ($0.kind == kind) && (query.isEmpty || ($0.party ?? "").localizedCaseInsensitiveContains(query) || Catalog.category($0.category).name.localizedCaseInsensitiveContains(query)) }
                    let months = Dictionary(grouping: rows) { String($0.date.prefix(7)) }
                    ForEach(months.keys.sorted(by: >), id: \.self) { m in
                        let sum = months[m]!.reduce(0) { $0 + $1.amount }
                        SectionTitle(text: Day.month(Day.parse(m + "-01") ?? .now).capitalized(with: Day.tr), trailing: TL.text(sum))
                        Card(padding: 4) { VStack(spacing: 0) { ForEach(months[m]!) { MoneyRow(money: $0) } } }
                    }
                    if rows.isEmpty { Text("Kayıt yok.").foregroundStyle(.secondary).padding(.top, 20) }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .searchable(text: $query, prompt: "Karşı taraf ya da kategori")
        .navigationTitle("Kayıt defteri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func asset(_ name: String, _ n: Int, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.money).frame(width: 26)
            Text(name).font(.subheadline.weight(.medium)); Spacer(); Text("\(n)").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct CategoryList: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        let months = d.lastMonths(12)
        var totals: [String: Double] = [:]
        for m in months { for (k, v) in m.byCategory { totals[k, default: 0] += v } }
        let sorted = totals.sorted { $0.value > $1.value }
        let all = sorted.reduce(0) { $0 + $1.value }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                UnitRing(parts: sorted.map { .init(id: $0.key, value: $0.value, color: Catalog.category($0.key).color) },
                         center: TL.compact(all), caption: "12 ayın gideri", units: 160, rows: 5)
                    .frame(maxWidth: 320).frame(maxWidth: .infinity)
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(sorted, id: \.key) { k, v in
                            let c = Catalog.category(k)
                            NavigationLink { CategoryView(category: k) } label: {
                                HStack(spacing: 12) {
                                    TileIcon(symbol: c.symbol, color: c.color, size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text("ayda ortalama \(TL.text(v / Double(max(months.filter { $0.expense > 0 }.count, 1)), decimals: false))").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(TL.text(v, decimals: false)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Kategoriler")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CategoryView: View {
    var category: String
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        let c = Catalog.category(category)
        let rows = d.records.filter { ($0.category ?? "diğer") == category && !$0.isIncome }
        let months = d.lastMonths(12).map { m in (m.start, m.byCategory.first { $0.0 == category }?.1 ?? 0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TileIcon(symbol: c.symbol, color: c.color, size: 44)
                    VStack(alignment: .leading) {
                        Text(c.name).font(.title2.bold())
                        Text("12 ayda \(TL.text(months.reduce(0) { $0 + $1.1 }, decimals: false))").foregroundStyle(.secondary)
                    }
                }
                Card {
                    Chart(months, id: \.0) { m in
                        BarMark(x: .value("Ay", m.0, unit: .month), y: .value("Tutar", m.1)).foregroundStyle(c.color.gradient).cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 170)
                }
                SectionTitle(text: "Kayıtlar", trailing: "\(rows.count)")
                Card(padding: 4) { VStack(spacing: 0) { ForEach(rows) { MoneyRow(money: $0) } } }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - household, documents, settings

struct HouseholdView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sözleşmenin kimin adına olduğu. Kişiler Mac'teki `assets.json` › `household` listesinden gelir; telefonda girilen bir ad da kullanılabilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.household) { p in
                    let mine = d.active.filter { $0.holder == p.id }
                    Card(padding: 14) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill").font(.title).foregroundStyle(Color.calm)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.headline)
                                Text("\(mine.count) sözleşme · ayda \(TL.text(mine.reduce(0) { $0 + ($1.monthly ?? 0) }))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Hane")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DocumentsView: View {
    @EnvironmentObject private var store: Store
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fatura, sözleşme, kart ekstresi ya da fiş ekle. Dosya vault'a gider; Mac'te Claude okur (\"FBS'yi düzenle\"), sözleşmenin ana maddelerini ve ödemeleri deftere işler. Sonuç buraya kendiliğinden gelir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { picking = true } label: { Label("Dosya", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glassProminent)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Fotoğraf", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glass)
                }
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(Color.money) }
                if store.inboxWaiting > 0 {
                    Text("\(store.inboxWaiting) belge telefonda bekliyor: vault klasörü seçilince gönderilir (Ayarlar).").font(.footnote).foregroundStyle(Color.watch)
                }
                Text("Mac'ten: belgeyi Downloads › FBS klasörüne atman yeter.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Belgeler")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, .commaSeparatedText, .plainText], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for u in urls { await store.addDocument(from: u, title: "") }
                note = "\(urls.count) belge eklendi."
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await store.addDocument(data: data, title: "Fotoğraf", ext: "jpg")
                    note = "Fotoğraf eklendi."
                }
                photo = nil
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        Form {
            Section("Veri") {
                LabeledContent("Mac'ten gelen", value: store.origin.isEmpty ? "Yok" : store.origin)
                LabeledContent("Telefonda girilen", value: "\(store.mine.contracts.count) sözleşme · \(store.mine.records.count) kayıt · \(store.mine.products.count) ürün")
                if let w = store.lastWrite { LabeledContent("Son yazım", value: w) }
                Button("Yenile") { Task { await store.load(); await store.pushEntries() } }
            }
            Section("Hatırlatma") {
                Toggle("Fatura, taahhüt ve garanti hatırlatması", isOn: $store.reminders)
                    .onChange(of: store.reminders) { _, _ in Task { await store.scheduleReminders() } }
                Text("Faturadan 2 gün önce, taahhüt bitişinden 30 ve 7 gün önce, garanti bitişinden 30 gün önce, saat 10:00.").font(.caption).foregroundStyle(.secondary)
            }
            PDMSettingsSection(bus: store.bus)
            Section("Gizlilik") {
                Text("Kart numarası, IBAN ya da kimlik numarası kaydedilmez: 9 haneden uzun her rakam dizisi son 4 hanesine indirilir. Kayıtlar yalnız senin vault'una gider.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ayarlar ve kaynaklar")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await store.load(); await store.pushEntries(); await store.flushInbox() } }
    }
}
