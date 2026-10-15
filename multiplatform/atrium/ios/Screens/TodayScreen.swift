// Today: the calendar page, activity rings, quick capture, what changed since the last visit.
import SwiftUI

struct TodayScreen: View {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    @State private var journalLine = ""
    @State private var sending = false
    @FocusState private var lineFocused: Bool

    var body: some View {
        let now = Date()
        let today = TurkishCalendar.dayKey(now)
        let activity = store.activity(days: 35)
        let touchedToday = store.touched(on: today)
        let createdToday = store.created(on: today)
        let mineToday = touchedToday.filter { $0.origin == .me || $0.origin == .shared }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(now)
                hero(now: now, activity: activity, touched: touchedToday.count, mine: mineToday.count, created: createdToday.count).appear(0.02)
                captureRow.appear(0.06)
                journalBox.appear(0.1)
                sinceLastVisit.appear(0.14)
                weekCard(activity: activity, today: today).appear(0.18)
                ideasCard.appear(0.22)
                originCard.appear(0.26)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .refreshable { await store.refresh() }
        .noteLinks()
    }

    private func header(_ now: Date) -> some View {
        let hour = TurkishCalendar.calendar.component(.hour, from: now)
        let greeting = hour < 5 ? "İyi geceler" : hour < 12 ? "Günaydın" : hour < 18 ? "İyi günler" : "İyi akşamlar"
        return VStack(alignment: .leading, spacing: 2) {
            Text("ATRIUM · PERSONEL DATA MANAGEMENT").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Palette.accent)
            Text(greeting).font(.largeTitle.weight(.bold)).fontDesign(.rounded)
            HStack(spacing: 6) {
                Text("\(Format.number(store.records.count)) not · \(Format.compact(store.totalWords)) kelime")
                if store.isScanning { ProgressView().controlSize(.mini); Text("taranıyor \(store.scanCount)") }
                else if let s = store.lastScan { Text("· güncel \(TurkishCalendar.relative(s))") }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func hero(now: Date, activity: [String: (all: Int, mine: Int)], touched: Int, mine: Int, created: Int) -> some View {
        let past = (1...30).map { TurkishCalendar.dayKey(TurkishCalendar.calendar.date(byAdding: .day, value: -$0, to: now)!) }
        let avgAll = max(1, Double(past.reduce(0) { $0 + (activity[$1]?.all ?? 0) }) / 30)
        let avgMine = max(1, Double(past.reduce(0) { $0 + (activity[$1]?.mine ?? 0) }) / 30)
        let avgNew = max(1, Double(past.reduce(0) { $0 + store.created(on: $1).count }) / 30)
        let words = store.ledger[TurkishCalendar.dayKey(now)]?.wordsAddedMine ?? 0
        return Card {
            HStack(alignment: .center, spacing: 18) {
                CalendarPage(date: now, badge: touched)
                ActivityRings(rings: [
                    .init(label: "Dokunulan", value: Double(touched) / avgAll, color: Palette.rose),
                    .init(label: "Senin", value: Double(mine) / avgMine, color: Palette.amber),
                    .init(label: "Yeni", value: Double(created) / avgNew, color: Palette.teal),
                ], lineWidth: 11)
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    ringLegend("Dokunulan", touched, Palette.rose)
                    ringLegend("Senin yazdığın", mine, Palette.amber)
                    ringLegend("Yeni not", created, Palette.teal)
                    if words > 0 { Text("+\(Format.number(words)) kelime yazdın").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            Text("Halka, son 30 günün ortalamasına göre dolar; tam tur = olağan bir gün.")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
        }
    }

    private func ringLegend(_ label: String, _ n: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(n)").font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(color)
        }
    }

    private var captureRow: some View {
        HStack(spacing: 10) {
            captureButton("Günlük", "book.closed.fill", Palette.amber) {
                Task {
                    if let p = try? await store.ensureJournal() { router.open(p) }
                }
            }
            captureButton("Fikir", "lightbulb.fill", Color(hex: "#E8B21A")) { router.composeKind = .idea }
            captureButton("Ses", "mic.fill", Palette.rose) { router.showVoice = true }
            captureButton("Yazı", "square.and.pencil", Palette.accent) { router.composeKind = .note }
        }
    }

    private func captureButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .foregroundStyle(.white)
                    .shadow(color: color.opacity(0.35), radius: 6, y: 3)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var journalBox: some View {
        Card(padding: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "text.append").foregroundStyle(Palette.amber).padding(.bottom, 8)
                TextField("Günlüğe bir satır… (saatle eklenir)", text: $journalLine, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($lineFocused)
                    .padding(.vertical, 6)
                Button {
                    let line = journalLine
                    sending = true
                    Task {
                        do {
                            _ = try await store.appendToJournal(line)
                            journalLine = ""
                            lineFocused = false
                            store.message = "Bugünün günlüğüne eklendi."
                        } catch { store.message = error.localizedDescription }
                        sending = false
                    }
                } label: {
                    Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill").font(.title2)
                }
                .disabled(journalLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .buttonStyle(.plain)
                .foregroundStyle(Palette.amber)
            }
        }
    }

    @ViewBuilder
    private var sinceLastVisit: some View {
        let list = store.sinceLastVisit
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Son bakışından beri", detail: "\(list.count) not · \(TurkishCalendar.relative(store.lastVisit))")
            if list.isEmpty {
                Card { Label("Vault'ta yeni bir şey yok.", systemImage: "checkmark.seal").foregroundStyle(.secondary) }
            } else {
                let areas = Dictionary(grouping: list, by: \.area).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(areas, id: \.0) { a in
                            NavigationLink(value: FolderRoute(path: a.0)) {
                                Pill(text: "\(a.0) · \(a.1)", color: Palette.area(a.0))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(list.prefix(7)) { n in
                            NavigationLink(value: NoteRoute(path: n.path)) { NoteRow(note: n).padding(10) }.buttonStyle(.plain)
                            if n.id != list.prefix(7).last?.id { Divider().padding(.leading, 58) }
                        }
                        if list.count > 7 {
                            NavigationLink(value: DayRoute(day: TurkishCalendar.dayKey(Date()))) {
                                Text("Bugünün hepsi →").font(.subheadline.weight(.semibold)).padding(12)
                            }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        }
                    }
                }
            }
        }
    }

    private func weekCard(activity: [String: (all: Int, mine: Int)], today: String) -> some View {
        let counts = activity.mapValues(\.all)
        let week = (0..<7).reduce(0) { $0 + (counts[TurkishCalendar.dayKey(TurkishCalendar.calendar.date(byAdding: .day, value: -$1, to: Date())!)] ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Bu hafta", detail: "\(week) dokunuş")
            Card {
                WeekStrip(counts: counts)
                Button { router.section = .timeline } label: {
                    Label("Akış'ta bütün takvim", systemImage: "calendar").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.accent).padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var ideasCard: some View {
        let sparks = Array(store.sparks.prefix(4))
        let ideas = store.recent(kind: .idea, limit: 4).filter { !$0.path.hasPrefix(VaultStore.sparkFolder) }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Fikirler", detail: "Kıvılcım + Fikirler")
            Card(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(sparks) { s in
                        sparkRow(s).padding(10)
                        Divider().padding(.leading, 58)
                    }
                    ForEach(ideas) { n in
                        NavigationLink(value: NoteRoute(path: n.path)) { NoteRow(note: n, showFolder: false).padding(10) }.buttonStyle(.plain)
                    }
                    if sparks.isEmpty && ideas.isEmpty {
                        Text("Henüz fikir yok. Ses ya da Fikir düğmesiyle başla.").font(.subheadline).foregroundStyle(.secondary).padding(12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sparkRow(_ s: SparkItem) -> some View {
        let content = HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.rose.opacity(0.15))
                Image(systemName: s.state == "hazir" ? "waveform" : "hourglass").foregroundStyle(Palette.rose)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title ?? "Ses kaydı").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(s.text?.isEmpty == false ? s.text! : "Mac'te yazıya dökülmeyi bekliyor")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(sparkDate(s.date)).font(.caption2).foregroundStyle(.secondary)
        }
        if let note = s.notePath {
            NavigationLink(value: NoteRoute(path: VaultStore.sparkFolder + "/" + note)) { content }.buttonStyle(.plain)
        } else { content }
    }

    private func sparkDate(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        f.timeZone = .current
        guard let d = f.date(from: s) else { return "" }
        return TurkishCalendar.relative(d)
    }

    private var originCard: some View {
        let counts = store.originCounts()
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Kim yazdı")
            Card {
                HStack(spacing: 20) {
                    OriginDonut(counts: counts, size: 118)
                    OriginLegend(counts: counts)
                }
            }
        }
    }
}
