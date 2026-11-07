// Özet: glass chips on top (Bu ay · Sabit yük · Yaklaşan · Sözleşmeler · Garantiler), one large graphic under each.
import Charts
import SwiftUI

enum OverviewChip: String, CaseIterable, Identifiable {
    case month, load, upcoming, contracts, warranty
    var id: String { rawValue }
    var name: String {
        switch self {
        case .month: return "Bu ay"
        case .load: return "Sabit yük"
        case .upcoming: return "Yaklaşan"
        case .contracts: return "Taahhütler"
        case .warranty: return "Garantiler"
        }
    }
    var symbol: String {
        switch self {
        case .month: return "chart.pie.fill"
        case .load: return "repeat.circle.fill"
        case .upcoming: return "bell.fill"
        case .contracts: return "doc.text.fill"
        case .warranty: return "checkmark.shield.fill"
        }
    }
    var color: Color {
        switch self {
        case .month: return .money
        case .load: return .calm
        case .upcoming: return .watch
        case .contracts: return .sleep
        case .warranty: return Color(light: 0x00968F, dark: 0x2FC0B8)
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @State private var chip = OverviewChip(rawValue: ProcessInfo.processInfo.environment["FBS_CHIP"] ?? "") ?? .month
    @State private var month = Derived.monthStart(.now)

    var body: some View {
        let d = Derived(store)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TabHeader(title: "Özet", subtitle: Day.month(.now).capitalized(with: Day.tr))
                    if store.isEmpty {
                        StartCard()
                    } else {
                        chips(d)
                        switch chip {
                        case .month: monthView(d)
                        case .load: loadView(d)
                        case .upcoming: upcomingView(d)
                        case .contracts: commitmentsView(d)
                        case .warranty: warrantyView(d)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: chips

    private func chips(_ d: Derived) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(OverviewChip.allCases) { c in
                        Button { withAnimation(.snappy) { chip = c } } label: {
                            HStack(spacing: 9) {
                                Image(systemName: c.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(c.color.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.name).font(.caption2).foregroundStyle(.secondary)
                                    Text(value(c, d)).font(.footnote.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
                                }
                            }
                            .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(chip == c ? .regular.tint(c.color.opacity(0.28)).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
    }

    private func value(_ c: OverviewChip, _ d: Derived) -> String {
        switch c {
        case .month: return TL.compact(d.month(Derived.monthStart(.now)).expense)
        case .load: return TL.compact(d.monthlyLoad) + "/ay"
        case .upcoming: return "\(d.events(from: Day.today, days: 30).filter { !$0.paid }.count) olay"
        case .contracts: return "\(d.active.count) aktif"
        case .warranty: return "\(d.products.filter { (Day.parse($0.warrantyEnd) ?? .distantPast) >= Day.today }.count) sürüyor"
        }
    }

    private func headline(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: this month

    @ViewBuilder private func monthView(_ d: Derived) -> some View {
        let m = d.month(month)
        let isNow = Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
        HStack {
            Button { month = Day.cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Önceki ay")
            Spacer()
            Text(Day.month(month).capitalized(with: Day.tr)).font(.headline)
            Spacer()
            Button { month = Day.cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34) }
                .buttonStyle(.glass).buttonBorderShape(.circle).disabled(isNow).accessibilityLabel("Sonraki ay")
        }
        UnitRing(parts: m.byCategory.map { .init(id: $0.0, value: $0.1, color: Catalog.category($0.0).color) },
                 center: TL.compact(m.expense), caption: isNow ? "bu ayki gider" : "gider")
            .frame(maxWidth: 320).frame(maxWidth: .infinity)
        HStack(spacing: 10) {
            tile("Gelir", TL.compact(m.income), .money)
            tile("Gider", TL.compact(m.expense), .spend)
            tile("Kalan", TL.compact(m.net), m.net >= 0 ? .money : .spend)
        }
        let share = m.income > 0 ? Int((m.expense / m.income * 100).rounded()) : nil
        headline(m.expense == 0 ? "Bu ay gider kaydı yok" : "Gelirin \(share.map { "%\($0)'i" } ?? "tamamı") gitti",
                 m.byCategory.isEmpty ? "Gider ekledikçe halka dolar: her nokta ayın giderinin yüzde biri." :
                    "En büyük kalem \(Catalog.category(m.byCategory[0].0).name.lowercased(with: Day.tr)): \(TL.text(m.byCategory[0].1)). Her nokta ayın giderinin yüzde biri.")
        if !m.byCategory.isEmpty {
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(m.byCategory, id: \.0) { id, v in
                        let c = Catalog.category(id)
                        NavigationLink { CategoryView(category: id) } label: {
                            HStack(spacing: 12) {
                                TileIcon(symbol: c.symbol, color: c.color, size: 30)
                                Text(c.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                Spacer()
                                Text("%\(Int((v / max(m.expense, 1) * 100).rounded()))").font(.caption).foregroundStyle(.secondary)
                                Text(TL.text(v)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        SectionTitle(text: "Son 6 ay", trailing: "gelir · gider")
        Card { MonthBars(months: d.lastMonths(6), selected: month) { month = $0 } }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
            }
        }
    }

    // MARK: fixed load

    @ViewBuilder private func loadView(_ d: Derived) -> some View {
        SegmentRing(parts: d.loadByKind.map { .init(value: $0.1, color: Catalog.category($0.0).color) },
                    center: TL.text(d.monthlyLoad, decimals: false).replacingOccurrences(of: " ₺", with: ""), caption: "₺ her ay")
            .frame(maxWidth: 300).frame(maxWidth: .infinity).padding(.top, 4)
        headline("Ayda \(TL.text(d.monthlyLoad)) sabit ödüyorsun",
                 "\(d.active.count) aktif sözleşme ve abonelik. Yıllık olanlar on ikiye bölündü. Yılda \(TL.text(d.monthlyLoad * 12, decimals: false)).")
        Card(padding: 6) {
            VStack(spacing: 0) {
                ForEach(d.loadByKind, id: \.0) { id, v in
                    let c = Catalog.category(id)
                    HStack(spacing: 12) {
                        TileIcon(symbol: c.symbol, color: c.color, size: 30)
                        Text(c.name).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(TL.text(v)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
        }
        if d.loadByHolder.count > 1 {
            SectionTitle(text: "Kimin adına")
            Card {
                VStack(spacing: 10) {
                    ForEach(d.loadByHolder, id: \.0) { n, v in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(n).font(.subheadline.weight(.medium)); Spacer(); Text(TL.text(v)).font(.subheadline.weight(.semibold)).monospacedDigit() }
                            GeometryReader { g in
                                Capsule().fill(Color.calm.gradient).frame(width: max(g.size.width * v / max(d.monthlyLoad, 1), 6))
                            }
                            .frame(height: 8)
                        }
                    }
                }
            }
        }
        let rising = d.active.compactMap { c in d.priceChange(c).map { (c, $0) } }.filter { $0.1 > 0 }
        if !rising.isEmpty {
            SectionTitle(text: "Fiyatı artanlar")
            ForEach(rising, id: \.0.id) { c, pct in
                NavigationLink { ContractDetail(contractID: c.id) } label: {
                    Card(padding: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.provider).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(Catalog.kind(c.kind).name + " · " + d.name(c.holder)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Sparkline(values: d.payments(c).map(\.amount), low: nil, high: nil, color: .spend).frame(width: 70, height: 28)
                            Text("%\(String(format: "%+.0f", pct))").font(.subheadline.weight(.bold)).foregroundStyle(Color.spend).frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: upcoming

    @ViewBuilder private func upcomingView(_ d: Derived) -> some View {
        let list = d.events(from: Day.cal.date(byAdding: .day, value: -5, to: Day.today)!, days: 65)
        let due = list.filter { $0.type == .bill && !$0.paid && $0.date <= Day.cal.date(byAdding: .day, value: 30, to: Day.today)! }
        UnitRing(parts: [.init(id: "paid", value: Double(list.filter { $0.type == .bill && $0.paid }.count), color: .money),
                         .init(id: "due", value: Double(due.count), color: .watch)],
                 center: "\(due.count)", caption: "ödenecek fatura", units: 60, rows: 3)
            .frame(maxWidth: 260).frame(maxWidth: .infinity)
        headline(due.isEmpty ? "Önümüzdeki 30 günde bekleyen fatura yok" : "30 günde \(TL.text(due.compactMap(\.amount).reduce(0, +))) ödenecek",
                 "Yeşil noktalar ödendi olarak işaretlenen faturalar. Ödediğinde satırdaki düğmeye dokun; ödeme gider olarak kaydedilir.")
        VStack(spacing: 10) {
            ForEach(list.filter { $0.date >= Day.cal.date(byAdding: .day, value: -5, to: Day.today)! }) { EventRow(event: $0) }
        }
    }

    // MARK: commitments

    @ViewBuilder private func commitmentsView(_ d: Derived) -> some View {
        let withEnd = d.active.filter { $0.commitmentEnd != nil }.sorted { ($0.commitmentEnd ?? "") < ($1.commitmentEnd ?? "") }
        headline(withEnd.isEmpty ? "Taahhüt tarihi girilmiş sözleşme yok" : "\(withEnd.count) taahhüt sürüyor",
                 "Şerit taahhüdün başından sonuna; nokta bugün. Bitişe 30 ve 7 gün kala hatırlatılır: o an fiyat ve yenileme şartına bakmanın zamanı.")
            .padding(.top, 6)
        VStack(spacing: 10) {
            ForEach(withEnd) { c in
                NavigationLink { ContractDetail(contractID: c.id) } label: {
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TileIcon(symbol: Catalog.kind(c.kind).symbol, color: Catalog.category(Catalog.kind(c.kind).category).color, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.provider).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(Catalog.kind(c.kind).name + " · " + d.name(c.holder)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let e = Day.parse(c.commitmentEnd) {
                                    let n = Day.daysFromToday(e)
                                    Text(n >= 0 ? "\(n) gün" : "bitti").font(.subheadline.weight(.bold)).monospacedDigit()
                                        .foregroundStyle(n < 0 ? Color.secondary : (n <= 30 ? Color.attention : (n <= 90 ? Color.watch : Color.primary)))
                                }
                            }
                            if let p = d.commitmentProgress(c) {
                                TimeStrip(progress: p, color: (Day.parse(c.commitmentEnd).map(Day.daysFromToday) ?? 99) <= 30 ? .attention : .sleep)
                                HStack { Text(Day.short(c.start)).font(.caption2); Spacer(); Text(Day.short(c.commitmentEnd)).font(.caption2) }.foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: warranties

    @ViewBuilder private func warrantyView(_ d: Derived) -> some View {
        let list = d.products.sorted { ($0.warrantyEnd ?? "") < ($1.warrantyEnd ?? "") }
        headline(list.isEmpty ? "Garanti kaydı yok" : "\(list.filter { (Day.parse($0.warrantyEnd) ?? .distantPast) >= Day.today }.count) ürünün garantisi sürüyor",
                 "Şerit alıştan garantinin sonuna. Bitişe 30 gün kala hatırlatılır: arızası varsa garanti bitmeden servise götür.")
            .padding(.top, 6)
        VStack(spacing: 10) {
            ForEach(list) { p in
                NavigationLink { ProductDetail(productID: p.id) } label: { ProductCard(product: p) }.buttonStyle(.plain)
            }
        }
    }
}

struct ProductCard: View {
    var product: Product
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = Derived(store)
        let left = Day.parse(product.warrantyEnd).map(Day.daysFromToday)
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TileIcon(symbol: "checkmark.shield.fill", color: (left ?? -1) < 0 ? .secondary : Color(light: 0x00968F, dark: 0x2FC0B8), size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text([product.seller, product.price.map { TL.text($0) }].compactMap { $0 }.joined(separator: " · ").ifEmpty("Alış: " + Day.short(product.bought)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(left.map { $0 >= 0 ? "\($0) gün" : "bitti" } ?? "—").font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle((left ?? -1) < 0 ? Color.secondary : ((left ?? 99) <= 30 ? Color.attention : Color.primary))
                }
                if let p = d.warrantyProgress(product) {
                    TimeStrip(progress: p, color: (left ?? -1) < 0 ? .secondary : Color(light: 0x00968F, dark: 0x2FC0B8))
                    HStack { Text(Day.short(product.bought)).font(.caption2); Spacer(); Text(Day.short(product.warrantyEnd)).font(.caption2) }.foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One row of the upcoming list and the calendar: icon, title, date, amount, and "Ödendi" for an unpaid bill.
struct EventRow: View {
    var event: FinEvent
    @EnvironmentObject private var store: Store

    var body: some View {
        let c = Catalog.category(event.category)
        let symbol: String = {
            switch event.type {
            case .commitmentEnd: return "hourglass"
            case .warrantyEnd: return "checkmark.shield.fill"
            case .income: return "arrow.down.circle.fill"
            default: return c.symbol
            }
        }()
        let color: Color = event.type == .commitmentEnd ? .attention : (event.type == .warrantyEnd ? .watch : (event.type == .income ? .money : c.color))
        Card(padding: 12) {
            HStack(spacing: 12) {
                TileIcon(symbol: symbol, color: color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(Day.dayMonth(event.date)) · \(Day.relative(event.date)) · \(event.detail)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    if let a = event.amount {
                        Text((event.type == .income ? "+" : "") + TL.text(a)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(event.type == .income ? Color.money : .primary)
                    }
                    if event.type == .bill {
                        if event.paid {
                            Label("Ödendi", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.money).labelStyle(.titleAndIcon)
                        } else if let contract = store.contracts.first(where: { $0.id == event.ref }) {
                            Button("Ödendi") { withAnimation { store.markPaid(contract, on: min(event.date, .now)) } }
                                .font(.caption.weight(.semibold)).buttonStyle(.glass).controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

/// Shown when there is nothing yet: the three ways in.
struct StartCard: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UnitRing(parts: [], center: "0 ₺", caption: "henüz kayıt yok").frame(maxWidth: 280).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text("Paranın nereye gittiğini gör").font(.title2.bold())
                Text("Önce sözleşmelerini gir: hatlar, internet, kira, aidat, sigorta, abonelikler. Fatura günleri ve taahhüt bitişleri takvime düşer, aylık sabit yükün hesaplanır. Sonra gelir ve giderlerini ekle.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    start(.contract, "Sözleşme ya da abonelik ekle", "Fatura günü, taahhüt bitişi, cayma bedeli")
                    start(.expense, "Gider ekle", "Fatura, market, alışveriş")
                    start(.income, "Gelir ekle", "Maaş, ek gelir, iade")
                    start(.product, "Garantili ürün ekle", "Alış tarihi, garanti bitişi")
                    start(.document, "Belge ekle", "Fatura ya da sözleşme PDF'i, fotoğraf; Claude okur")
                }
            }
            Text("Mac'te: belgeyi Downloads › FBS klasörüne at, Claude'a \"FBS'yi düzenle\" de. Okunan sözleşme ve ödemeler buraya kendiliğinden gelir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func start(_ m: AddMode, _ title: String, _ detail: String) -> some View {
        Button { router.add = m } label: {
            HStack(spacing: 12) {
                Image(systemName: m.symbol).font(.title3).foregroundStyle(Color.money).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
