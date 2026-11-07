// Hekim raporu: three A4 pages as one PDF. Page 1: what to ask and the out-of-range values with their history.
// Page 2: every marker. Page 3: conditions, recent episodes, supplements, measurements.
import SwiftUI

private let ink = Color.black
private let soft = Color(white: 0.42)

struct ReportPage<Content: View>: View {
    var number: Int
    var total: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sağlık özeti").font(.system(size: 20, weight: .bold))
                Spacer()
                Text(Date.now.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR")))).font(.system(size: 10)).foregroundStyle(soft)
            }
            Rectangle().fill(ink).frame(height: 1).padding(.top, 6).padding(.bottom, 12)
            content
            Spacer(minLength: 0)
            HStack {
                Text("SBS · kişisel kayıt. Teşhis içermez; değerler e-Nabız tahlillerinden ve kişinin kendi kayıtlarından alınmıştır.").font(.system(size: 7.5)).foregroundStyle(soft)
                Spacer()
                Text("\(number) / \(total)").font(.system(size: 8)).foregroundStyle(soft)
            }
        }
        .foregroundStyle(ink)
        .padding(36)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

private struct Head: View {
    var text: String
    var body: some View { Text(text).font(.system(size: 12, weight: .bold)).padding(.top, 10).padding(.bottom, 5) }
}

struct ReportPages {
    var d: Derived

    private func history(_ m: Marker) -> String {
        m.points.suffix(4).map { "\($0.shown) (\(String($0.date.prefix(7))))" }.joined(separator: "  →  ")
    }

    @MainActor var pages: [AnyView] {
        let s = d.state
        let out = s.markers.filter { ["watch", "attention"].contains($0.status) }
            .sorted { ($0.status == "attention" ? 0 : 1, $0.name) < ($1.status == "attention" ? 0 : 1, $1.name) }
        let order = ["heart", "metabolism", "liver", "kidney", "blood", "immune", "thyroid", "muscle", "infection", "other"]
        let names = ["heart": "Kalp ve damar", "metabolism": "Metabolizma", "liver": "Karaciğer", "kidney": "Böbrek ve mineraller", "blood": "Kan",
                     "immune": "Bağışıklık ve iltihap", "thyroid": "Tiroid", "muscle": "Kas", "infection": "Enfeksiyon ve bağışıklık kaydı", "other": "Diğer"]
        let sorted = order.flatMap { a in s.markers.filter { $0.area == a } }
        let half = (sorted.count + 1) / 2
        let recent = s.episodes.filter { (Day.daysAgo($0.date) ?? 999) < 90 }

        let one = ReportPage(number: 1, total: 3) {
            Head(text: "Hekime sorulacaklar")
            ForEach(s.highlights.filter { $0.tone != "good" }.prefix(10)) { h in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(h.tone == "alert" ? Color.attention : Color.watch).frame(width: 5, height: 5)
                    Text(h.title).font(.system(size: 10, weight: .semibold))
                    Text(h.detail).font(.system(size: 9)).foregroundStyle(soft).lineLimit(1)
                }
                .padding(.vertical, 1.5)
            }
            Head(text: "Aralık dışındaki değerler ve seyri")
            ForEach(out) { m in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(m.name).font(.system(size: 10, weight: .semibold))
                        Text(m.status == "attention" ? "aralık dışında" : "sınırda").font(.system(size: 8)).foregroundStyle(m.status == "attention" ? Color.attention : Color.watch)
                        Spacer()
                        Text("aralık \(m.refText.isEmpty ? "—" : m.refText) \(m.unit)").font(.system(size: 8.5)).foregroundStyle(soft)
                    }
                    Text(history(m)).font(.system(size: 9.5).monospacedDigit())
                }
                .padding(.vertical, 3)
                Rectangle().fill(Color(white: 0.88)).frame(height: 0.5)
            }
            Head(text: "İyileşenler")
            Text(s.highlights.filter { $0.tone == "good" }.map { "\($0.title): \($0.detail)" }.joined(separator: "\n")).font(.system(size: 9))
        }

        func column(_ ms: ArraySlice<Marker>) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(ms.enumerated()), id: \.element.id) { i, m in
                    if i == 0 || ms[ms.startIndex + i - 1].area != m.area {
                        Text(names[m.area] ?? m.area).font(.system(size: 8.5, weight: .bold)).padding(.top, 6).padding(.bottom, 2)
                    }
                    HStack(spacing: 4) {
                        Text(m.name).font(.system(size: 8.5)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(m.lastShown).font(.system(size: 8.5, weight: ["watch", "attention"].contains(m.status) ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(m.status == "attention" ? Color.attention : (m.status == "watch" ? Color.watch : ink))
                        Text(m.unit).font(.system(size: 7)).foregroundStyle(soft).frame(width: 40, alignment: .leading).lineLimit(1)
                        Text(m.refText.components(separatedBy: " (").first ?? "").font(.system(size: 7)).foregroundStyle(soft).frame(width: 52, alignment: .leading).lineLimit(1)
                        Text(String(m.lastDate.prefix(7))).font(.system(size: 7)).foregroundStyle(soft).frame(width: 36, alignment: .trailing)
                    }
                    .frame(height: 13.2)
                }
            }
        }
        let two = ReportPage(number: 2, total: 3) {
            Head(text: "Bütün göstergeler (son değer · birim · aralık · tarih)")
            HStack(alignment: .top, spacing: 18) { column(sorted.prefix(half)); column(sorted.dropFirst(half)) }
        }

        let three = ReportPage(number: 3, total: 3) {
            Head(text: "Süregelen ve tekrarlayan durumlar")
            ForEach(s.conditions) { c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(c.name).font(.system(size: 9.5, weight: .semibold)).frame(width: 150, alignment: .leading)
                    Text((c.symptoms.prefix(4).joined(separator: ", ")) + (c.episodeCount > 0 ? " · \(c.episodeCount) kayıtlı olay" : "")).font(.system(size: 9)).foregroundStyle(soft).lineLimit(2)
                }
                .padding(.vertical, 1.5)
            }
            Head(text: "Son 90 günün olayları")
            if recent.isEmpty { Text("Kayıt yok.").font(.system(size: 9)).foregroundStyle(soft) }
            ForEach(recent) { e in
                Text("\(Day.short(e.date)) · \(e.title ?? "") · \(e.text ?? "")" + ((e.triggers ?? []).isEmpty ? "" : " Tetikleyen: " + e.triggers!.joined(separator: ", ") + ".") + (e.outcome.map { " Sonuç: \($0)." } ?? ""))
                    .font(.system(size: 9)).padding(.vertical, 1.5).fixedSize(horizontal: false, vertical: true)
            }
            Head(text: "Düzenli kullanılan besin ve takviyeler")
            Text(s.supplements.filter { $0.active ?? true }.map { "\($0.name) (\($0.dose ?? "—"))" }.joined(separator: " · ")).font(.system(size: 9)).fixedSize(horizontal: false, vertical: true)
            Head(text: "Gerektiğinde kullanılan ilaçlar")
            Text(s.medications.map { "\($0.name): \($0.use ?? "")" }.joined(separator: " · ")).font(.system(size: 9))
            Head(text: "Ölçümler ve alışkanlıklar")
            Text([
                d.weight.last.map { "Kilo \($0.value.clean) kg (\($0.date.formatted(.dateTime.day().month(.abbreviated))))" },
                d.waist.last.map { "Bel çevresi \($0.value.clean) cm" },
                d.systolic.last.map { "Büyük tansiyon \(Int($0.value)) mmHg" },
                d.sleep7.map { "Uyku (son geceler) ortalama \(Derived.hours($0))" },
                d.steps30.map { "Adım (30 gün) günde ortalama \(Int($0).formatted())" },
                d.resting7.map { "Dinlenik nabız \(Int($0)) atım/dk" },
            ].compactMap { $0 }.joined(separator: " · ").ifEmpty("Apple Sağlık'tan ölçüm gelmedi.")).font(.system(size: 9)).fixedSize(horizontal: false, vertical: true)
        }
        return [AnyView(one), AnyView(two), AnyView(three)]
    }

    @MainActor func makePDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SBS Hekim Raporu \(Day.key(.now)).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}

struct ReportView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health
    @State private var file: URL?

    var body: some View {
        let report = ReportPages(d: Derived(store, health))
        ScrollView {
            VStack(spacing: 14) {
                Text("Üç sayfa: hekime sorulacaklar ve aralık dışı değerlerin seyri, bütün göstergeler, rahatsızlıklar ve son olaylar. Paylaşmadan önce oku.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let file {
                    ShareLink(item: file) { Label("PDF'i paylaş", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glassProminent)
                }
                GeometryReader { g in
                    let scale = g.size.width / 595
                    VStack(spacing: 12 / scale) {
                        ForEach(Array(report.pages.enumerated()), id: \.offset) { _, page in
                            page.clipShape(RoundedRectangle(cornerRadius: 10)).shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        }
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: 595, alignment: .topLeading)
                }
                .frame(height: (842 * 3 + 12 * 2 + 20) * (UIScreen.main.bounds.width - 36) / 595)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Hekim raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task { file = report.makePDF() }
    }
}
