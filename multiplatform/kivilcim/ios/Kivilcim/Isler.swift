// İşler · Günlük · quick edit sheet · shared pieces for priority, done and notes (2026-11-02).
// Open items are sorted by priority (red urgent first), then by age; done items sink to "Yapıldı" and leave the app
// 30 days later (isle.py moves their note to Kıvılcım/Arşiv/ in the vault).
import SwiftUI

// MARK: Shared pieces

extension Priority { var color: Color { Color(hex: hex) } }

/// Four capsules: Acil · Yüksek · Normal · Düşük.
struct PrioritySelector: View {
    let selected: Int
    let pick: (Priority) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Priority.allCases.reversed()) { p in
                let on = selected == p.rawValue
                Button { pick(p) } label: {
                    Label(p.name, systemImage: p.symbol).labelStyle(.titleOnly)
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(on ? .white : p.color)
                        .background(Capsule().fill(p.color.opacity(on ? 1 : 0.14)))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Round check: tap = done / open again.
struct DoneCheck: View {
    let o: Oge
    var size: CGFloat = 24
    @EnvironmentObject var depo: TelefonDeposu
    var body: some View {
        Button { withAnimation(.snappy) { depo.duzelt(o, "status", o.isDone ? "open" : "done") } } label: {
            Image(systemName: o.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(o.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(o.prio.color))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: o.isDone)
        .accessibilityLabel(o.isDone ? "Yeniden aç" : "Yapıldı işaretle")
    }
}

struct ItemRow: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    var sorgu = ""
    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 12) {
            DoneCheck(o: o).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(o.baslik).font(.body.weight(.semibold)).lineLimit(2)
                    .strikethrough(o.isDone, color: .secondary).foregroundStyle(o.isDone ? .secondary : .primary)
                let alt = sorgu.isEmpty ? (o.ozet.isEmpty ? o.metin : o.ozet) : Arama.parca(o, sorgu)
                if !alt.isEmpty && !o.isDone { Text(alt).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    Label(al.ad, systemImage: al.simge).foregroundStyle(al.color).lineLimit(1)
                    Image(systemName: depo.siniflar.amac(o.amac).simge)
                    if o.kind == "extract" { Image(systemName: "book.pages").help("Sesli günlükten") }
                    if !o.notes.isEmpty { Label("\(o.notes.count)", systemImage: "note.text") }
                    Spacer()
                    if let g = o.daysToArchive { Text("arşive \(g) gün") }
                    else { Text(Zaman.goreli(o.zaman)) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if o.priority >= Priority.high.rawValue && !o.isDone {
                Image(systemName: o.prio.symbol).font(.caption.weight(.heavy)).foregroundStyle(o.prio.color)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(o.priority == Priority.urgent.rawValue && !o.isDone ? Priority.urgent.color.opacity(0.08) : nil)
    }
}

// MARK: İşler

struct IslerEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @State private var gorunum = 0          // 0 açık · 1 yapıldı (Tatbik and Akış live in Merkez since 2026-11-07)
    @State private var suzgec: String?      // alan id or "yazilim-fikir"
    @State private var notIcin: Oge?

    private func uyar(_ l: [Oge]) -> [Oge] {
        guard let s = suzgec else { return l }
        if s == "yazilim-fikir" { return l.filter { $0.alan == "yazilim" && ($0.amac == "fikir" || $0.amac == "yapilacak") } }
        return l.filter { $0.alan == s }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Görünüm", selection: $gorunum) {
                        Text("Açık · \(depo.acik.count)").tag(0)
                        Text("Yapıldı · \(depo.biten.count)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    if gorunum < 2 { suzgecler.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                }
                if gorunum == 0 {
                    ForEach(Priority.allCases.reversed()) { p in
                        let bu = uyar(depo.acik).filter { $0.priority == p.rawValue }
                        if !bu.isEmpty {
                            Section {
                                ForEach(bu) { o in satir(o) }
                            } header: {
                                Label("\(p.name) · \(bu.count)", systemImage: p.symbol).foregroundStyle(p.color)
                            }
                        }
                    }
                } else {
                    Section {
                        ForEach(uyar(depo.biten)) { o in satir(o) }
                    } footer: {
                        Text("Yapıldı işaretinden \(Priority.archiveDays) gün sonra not vault'ta Kıvılcım/Arşiv klasörüne taşınır ve buradan kalkar. Obsidian'da Arşiv Dizini'nden ulaşılır.")
                    }
                }
            }
            .overlay {
                if gorunum < 2, (gorunum == 0 ? depo.acik : depo.biten).isEmpty {
                    ContentUnavailableView(gorunum == 0 ? "Açık iş yok" : "Henüz biten yok",
                                           systemImage: gorunum == 0 ? "checkmark.seal" : "tray",
                                           description: Text(gorunum == 0 ? "Yeni bir kıvılcım kaydet ya da günlükte “kıvılcım” de." : "Bir işi bitirince ✓'e dokun."))
                }
            }
            .animation(.snappy, value: depo.acik.map(\.id))
            .navigationTitle("İşler")
            .navigationDestination(for: String.self) { DetayEkrani(id: $0) }
            .navigationDestination(for: TatbikItem.self) { TatbikPhoneDetail(id: $0.id) }
            .navigationDestination(for: FeedItem.self) { FeedPhoneDetail(id: $0.id) }
            .refreshable { await depo.gonder() }
            .sheet(item: $notIcin) { o in NotSayfasi(o: o).presentationDetents([.height(260)]) }
        }
    }

    private func satir(_ o: Oge) -> some View {
        NavigationLink(value: o.id) { ItemRow(o: o) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { depo.duzelt(o, "status", o.isDone ? "open" : "done") } label: {
                    Label(o.isDone ? "Aç" : "Yapıldı", systemImage: o.isDone ? "arrow.uturn.backward" : "checkmark")
                }.tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { depo.duzelt(o, "sil", true) } label: { Label("Çöpe", systemImage: "trash") }
                Button { notIcin = o } label: { Label("Not", systemImage: "square.and.pencil") }.tint(.indigo)
                Button { depo.duzelt(o, "priority", o.priority == 3 ? 1 : o.priority + 1) } label: {
                    Label("Öncelik ↑", systemImage: "flag.fill")
                }.tint(.orange)
            }
            .contextMenu {
                Menu("Öncelik") {
                    ForEach(Priority.allCases.reversed()) { p in
                        Button { depo.duzelt(o, "priority", p.rawValue) } label: { Label(p.name, systemImage: p.symbol) }
                    }
                }
                Button { notIcin = o } label: { Label("Not ekle", systemImage: "square.and.pencil") }
                SinifMenusu(o: o)
            }
    }

    private var suzgecler: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Cip(ad: "Yazılım fikirleri", simge: "chevron.left.forwardslash.chevron.right", renk: .green,
                    secili: suzgec == "yazilim-fikir") { suzgec = suzgec == "yazilim-fikir" ? nil : "yazilim-fikir" }
                ForEach(depo.siniflar.alanlar) { a in
                    let n = (gorunum == 0 ? depo.acik : depo.biten).filter { $0.alan == a.id }.count
                    if n > 0 { Cip(ad: "\(a.ad) \(n)", simge: a.simge, renk: a.color, secili: suzgec == a.id) { suzgec = suzgec == a.id ? nil : a.id } }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: Not

struct NotSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.dismiss) private var kapat
    let o: Oge
    @State private var metin = ""
    @FocusState private var odak: Bool
    var body: some View {
        NavigationStack {
            TextField("Not yaz…", text: $metin, axis: .vertical)
                .lineLimit(3...8).focused($odak).padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))).padding()
                .navigationTitle(o.baslik).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç", role: .cancel) { kapat() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle") { depo.duzelt(o, "note", metin.trimmingCharacters(in: .whitespacesAndNewlines)); kapat() }
                            .disabled(metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { odak = true }
        }
    }
}

/// Opens right after a spark ends in the app: title, priority, kind, a note. Everything optional; "Tamam" closes.
struct HizliDuzenSayfasi: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.dismiss) private var kapat
    let id: String
    @State private var baslik = ""
    @State private var not = ""

    var body: some View {
        NavigationStack {
            if let o = depo.oge(id) {
                Form {
                    Section {
                        TextField("Başlık (boş kalırsa Mac koyar)", text: $baslik, axis: .vertical)
                            .font(.headline)
                    }
                    Section("Öncelik") {
                        PrioritySelector(selected: o.priority) { depo.duzelt(o, "priority", $0.rawValue) }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    Section("Tür") {
                        Picker("Amaç", selection: Binding(get: { o.amac }, set: { depo.duzelt(o, "amac", $0) })) {
                            ForEach(depo.siniflar.amaclar) { a in Label(a.ad, systemImage: a.simge).tag(a.id) }
                        }
                        .pickerStyle(.menu)
                        Picker("Alan", selection: Binding(get: { o.alan }, set: { depo.duzelt(o, "alan", $0) })) {
                            ForEach(depo.siniflar.alanlar) { a in Label(a.ad, systemImage: a.simge).tag(a.id) }
                        }
                        .pickerStyle(.menu)
                    }
                    Section("Not") { TextField("İsteğe bağlı", text: $not, axis: .vertical).lineLimit(2...5) }
                }
                .navigationTitle("Kaydedildi · \(o.sureMetni)").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { depo.duzelt(o, "status", "done"); bitir(o) } label: { Label("Yapıldı", systemImage: "checkmark") }
                            .tint(.green)
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Tamam") { bitir(o) } }
                }
            }
        }
    }

    private func bitir(_ o: Oge) {
        let b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty { depo.duzelt(o, "baslik", b) }
        let n = not.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { depo.duzelt(o, "note", n) }
        kapat()
    }
}

// MARK: Günlük

/// The journal button's label; the running time comes from the meter, so only this label redraws while recording.
private struct JournalRecordLabel: View {
    let kayitta: Bool
    @ObservedObject var meter: RecordingMeter
    var body: some View {
        Label(kayitta ? "Kaydı bitir · \(Zaman.sure(meter.sure))" : "Sesli günlüğe başla",
              systemImage: kayitta ? "stop.fill" : "book.pages.fill")
    }
}

struct GunlukEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @EnvironmentObject var merkez: KayitMerkezi

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await merkez.degistir(kaynak: "günlük sekmesi", tur: "journal") }
                    } label: {
                        JournalRecordLabel(kayitta: merkez.kayitta, meter: merkez.meter)
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent).tint(.indigo)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } footer: {
                    Text("En çok 60 dk. Konuşma o günün günlüğüne (Seyir Defteri) yazılır. İçinden ayrı tutmak istediğin bir fikirde “kıvılcım” de: o cümle İşler'e düşer, günlüğe bağlı kalır.")
                }
                ForEach(depo.gunlukler.gunlere(), id: \.0) { gun, liste in
                    Section(gun) {
                        ForEach(liste) { j in
                            NavigationLink(value: j.id) { GunlukSatiri(j: j) }
                        }
                    }
                }
            }
            .navigationTitle("Günlük")
            .navigationDestination(for: String.self) { DetayEkrani(id: $0) }
            .refreshable { await depo.gonder() }
        }
    }
}

struct GunlukSatiri: View {
    @EnvironmentObject var depo: TelefonDeposu
    let j: Oge
    var body: some View {
        let c = depo.cocuklar(j)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(j.baslik).font(.body.weight(.semibold)).lineLimit(2)
                Spacer()
                Text("\(Zaman.saat(j.zaman)) · \(j.sureMetni)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if !j.metin.isEmpty { Text(j.metin).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            else { Text(j.durum == "yerel" ? "Vault'a gidecek" : "Mac'te dökülmeyi bekliyor").font(.caption).foregroundStyle(.orange) }
            if !c.isEmpty {
                Label("\(c.count) kıvılcım ayıklandı · \(c.filter(\.isDone).count) yapıldı", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(Color.kivilcim)
            }
        }
        .padding(.vertical, 2)
    }
}


// MARK: Akış (2026-11-06)

/// İşler › Akış: the day's chosen items, with an end. Tap opens the link; a marked item becomes a Dikkat mark.
struct FeedSections: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.openURL) private var openURL
    @State private var refreshing = false
    private var issue: FeedIssue { depo.feed }

    private var refreshButton: some View {
        Section {
            Button {
                refreshing = true
                Task { await depo.feedRefresh(); refreshing = false }
            } label: {
                HStack {
                    Label(refreshing ? "Mac'ten isteniyor…" : "Güncelle", systemImage: "arrow.clockwise")
                    if refreshing { Spacer(); ProgressView() }
                }
            }
            .disabled(refreshing)
        } footer: {
            Text("Baskıyı Mac getirir ve tamamlar; Mac uyanık ve Kıvılcım açık olmalı.")
        }
    }

    var body: some View {
        refreshButton
        if issue.isToday {
            ForEach(issue.sections, id: \.topic.id) { s in
                Section(s.topic.name) {
                    ForEach(s.items) { row($0) }
                }
            }
            Section {
                Text(issue.openCount == 0 && !issue.items.isEmpty
                     ? "Bugünlük bu kadar. Yeni baskı yarın \(issue.readyAt)'da."
                     : "Listenin sonu burası. Yeni baskı yarın \(issue.readyAt)'da.")
                    .font(.footnote).foregroundStyle(.secondary)
                if !issue.skipped.isEmpty {
                    DisclosureGroup("Geçilenler · \(issue.skipped.count)") {
                        ForEach(issue.skipped) { i in
                            HStack {
                                Text(i.title).font(.footnote).lineLimit(2).foregroundStyle(.secondary)
                                Spacer()
                                Button("Geri al") { depo.feedTouch(i.id, "open") }.font(.footnote).buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        } else {
            Section {
                ContentUnavailableView("Bugünün baskısı \(issue.readyAt)'da", systemImage: "newspaper",
                                       description: Text("Hacker News, Reddit ve X'te beğendiklerinden en çok 10 madde. Mac hazırlar, buraya eşitlenir."))
            }
        }
    }

    private func row(_ i: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink(value: i) {
                VStack(alignment: .leading, spacing: 6) {
                    FeedPicture(item: i)
                    Text(i.community + (i.numbers.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary)
                    Text(i.shownTitle).font(.system(.body, design: .serif).weight(.semibold))
                    if !i.shownBody.isEmpty, i.shownBody != i.shownTitle {
                        Text(i.shownBody).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            HStack(spacing: 18) {
                if i.isMarked {
                    Label("İşaretlendi", systemImage: "checkmark").font(.footnote).foregroundStyle(.orange)
                } else {
                    Button("İşaretle") { withAnimation(.snappy) { depo.feedTouch(i.id, "marked") } }
                    Button("Geç") { withAnimation(.snappy) { depo.feedTouch(i.id, "skipped") } }.tint(.secondary)
                }
            }
            .font(.footnote).buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// The picture of an item, loaded by hand: AsyncImage inside a List cancels its own load while the row settles.
struct FeedPicture: View {
    let item: FeedItem
    var height: CGFloat = 170
    @State private var image: UIImage?

    var body: some View {
        // always a real view, even before the picture arrives: an empty one would never start its task
        Color.clear
            .frame(height: image == nil ? 1 : height).frame(maxWidth: .infinity)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: item.image) {
                guard let u = item.imageLink, image == nil,
                      let (d, _) = try? await URLSession.shared.data(from: u) else { return }
                image = UIImage(data: d)
            }
    }
}

/// One item: picture, Turkish title and text, the original beneath, links.
struct FeedPhoneDetail: View {
    @EnvironmentObject var depo: TelefonDeposu
    @Environment(\.openURL) private var openURL
    let id: String

    /// Split out of `body`: inline, the Xcode 26.3 compiler gave up type-checking the whole view.
    private static func byline(_ i: FeedItem) -> String {
        var s = i.community
        if let a = i.author, !a.isEmpty { s += " · " + a }
        if let n = i.numbers { s += " · " + n }
        return s
    }

    var body: some View {
        if let i = depo.feed.items.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FeedPicture(item: i, height: 240)
                    Text(Self.byline(i))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(i.shownTitle).font(.system(.title2, design: .serif).weight(.bold)).textSelection(.enabled)
                    if let o = i.originalTitle { Text(o).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !i.shownBody.isEmpty, i.shownBody != i.shownTitle {
                        Text(i.shownBody).font(.system(.body, design: .serif)).textSelection(.enabled)
                    }
                    if i.hasTurkishBody, let b = i.body {
                        DisclosureGroup("Özgün metin") {
                            Text(b).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 6)
                        }
                        .font(.footnote)
                    }
                    HStack(spacing: 12) {
                        Button("Kaynağı aç") { i.link.map { openURL($0) } }.buttonStyle(.borderedProminent)
                        if let d = i.discussionLink { Button("Tartışma") { openURL(d) }.buttonStyle(.bordered) }
                    }
                    if i.isMarked {
                        Label("İşaretlendi: notu Dikkat'te.", systemImage: "checkmark").font(.footnote).foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 12) {
                            Button("İşaretle") { depo.feedTouch(i.id, "marked") }.buttonStyle(.bordered)
                            Button(i.isSkipped ? "Geri al" : "Geç") { depo.feedTouch(i.id, i.isSkipped ? "open" : "skipped") }.buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: Tatbik (2026-11-05)

extension TatbikStatus { var color: Color { Color(hex: hex) } }

struct TatbikPhoneRow: View {
    @EnvironmentObject var depo: TelefonDeposu
    let m: TatbikItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { withAnimation(.snappy) { depo.tatbikDuzelt(m.id, "status", m.status == .tamam ? "acik" : "tamam") } } label: {
                Image(systemName: m.status.symbol).font(.system(size: 22)).foregroundStyle(m.status.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: m.status == .tamam)
            .accessibilityLabel(m.status == .tamam ? "Yeniden aç" : "Tamamlandı işaretle")
            VStack(alignment: .leading, spacing: 3) {
                Text(m.baslik).font(.body.weight(.medium)).lineLimit(3)
                    .foregroundStyle(m.status.isClosed ? .secondary : .primary)
                    .strikethrough(m.status == .gerekYok, color: .secondary)
                HStack(spacing: 8) {
                    Text(m.status.short).foregroundStyle(m.status.color)
                    if !m.status.isClosed, let p = m.priorityName { Text(p) }
                    if !m.status.isClosed, let s = m.sizeName { Text(s) }
                    if m.byUser { Image(systemName: "pencil") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct TatbikPhoneDetail: View {
    @EnvironmentObject var depo: TelefonDeposu
    let id: String
    @State private var note = ""
    var body: some View {
        if let m = depo.tatbik.maddeler.first(where: { $0.id == id }) {
            List {
                Section {
                    Text(m.baslik).font(.title3.weight(.semibold))
                    Text("\(depo.tatbik.program(m.program)?.ad ?? m.program) · \(m.id)").font(.caption).foregroundStyle(.secondary)
                }
                Section("Durum") {
                    ForEach(TatbikStatus.allCases) { s in
                        Button { depo.tatbikDuzelt(m.id, "status", s.rawValue) } label: {
                            HStack {
                                Label(s.name, systemImage: s.symbol).foregroundStyle(s.color)
                                Spacer()
                                if m.status == s { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
                ForEach([("Ayrıntı", m.ayrinti), (m.status == .tamam ? "Kanıt" : "Şu an var olan", m.kanit), ("Eksik", m.eksik), ("Gerekçe", m.gerekce)], id: \.0) { t, v in
                    if let v, !v.isEmpty { Section(t) { Text(v) } }
                }
                Section("Notların") {
                    ForEach(m.notlar ?? [], id: \.self) { n in
                        VStack(alignment: .leading) {
                            Text(n.text)
                            Text(n.t.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("Not ekle", text: $note, axis: .vertical)
                        Button("Ekle") {
                            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !n.isEmpty { depo.tatbikDuzelt(m.id, "note", n); note = "" }
                        }
                    }
                }
                Section("Kaynak kayıtlar") {
                    ForEach(m.sources, id: \.self) { rid in
                        if let o = depo.oge(rid) {
                            NavigationLink(value: o.id) {
                                VStack(alignment: .leading) {
                                    Text(o.baslik).lineLimit(2)
                                    Text(o.tarih.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        } else { Text(rid).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button { UIPasteboard.general.string = m.prompt(depo.tatbik.program(m.program), m.sources.compactMap { depo.oge($0) }) } label: {
                        Label("“Bunu yap” istemini kopyala", systemImage: "doc.on.clipboard")
                    }
                }
            }
            .navigationTitle("Madde")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Madde bulunamadı", systemImage: "checklist")
        }
    }
}
