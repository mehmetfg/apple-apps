// Shortcuts, Siri, widget and Live Activity actions on items (2026-11-02): done · priority · note · journal recording.
// Compiled in the app and the widget extension. LiveActivityIntent makes the system run perform() in the app process,
// so the app's list and the vault are updated at once; inside the extension the same write goes to the App Group file.
// Snippets (pop-up cards in Shortcuts / Siri / Action Button) live only in the app target.
import Foundation
import AppIntents
import SwiftUI
#if !WIDGET
import UIKit
#endif

// MARK: Entity

enum PriorityChoice: Int, AppEnum {
    case low = 0, normal = 1, high = 2, urgent = 3
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Öncelik"
    static let caseDisplayRepresentations: [PriorityChoice: DisplayRepresentation] = [
        .urgent: DisplayRepresentation(title: "Acil", image: .init(systemName: "exclamationmark.3")),
        .high: DisplayRepresentation(title: "Yüksek", image: .init(systemName: "exclamationmark")),
        .normal: DisplayRepresentation(title: "Normal", image: .init(systemName: "minus")),
        .low: DisplayRepresentation(title: "Düşük", image: .init(systemName: "arrow.down")),
    ]
    var priority: Priority { Priority(rawValue: rawValue) ?? .normal }
}

struct SparkEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Kıvılcım"
    static let defaultQuery = SparkQuery()
    var id: String
    var title: String
    var priority: Int
    var done: Bool

    init(_ s: ItemSnapshot) { id = s.id; title = s.title; priority = s.priority; done = s.isDone }

    var displayRepresentation: DisplayRepresentation {
        let p = Priority(rawValue: priority) ?? .normal
        return DisplayRepresentation(title: "\(title)", subtitle: "\(done ? "Yapıldı" : p.name)",
                                     image: .init(systemName: done ? "checkmark.circle.fill" : p.symbol))
    }
}

struct SparkQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SparkEntity] {
        let all = SharedStore.items()
        return identifiers.compactMap { id in all.first { $0.id == id }.map(SparkEntity.init) }
    }
    func suggestedEntities() async throws -> [SparkEntity] { SharedStore.openItems().prefix(30).map(SparkEntity.init) }
    func entities(matching string: String) async throws -> [SparkEntity] {
        let q = Arama.katla(string)
        return SharedStore.items().filter { $0.kind != "journal" && Arama.katla($0.title).contains(q) }.prefix(30).map(SparkEntity.init)
    }
}

/// The most recent spark (for "edit the last one" without choosing).
private func latestSpark() -> ItemSnapshot? {
    SharedStore.items().filter { $0.kind == "spark" }.max { $0.date < $1.date }
}

// MARK: Actions

struct MarkDoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Kıvılcımı yapıldı işaretle"
    static let description = IntentDescription("Bir kıvılcımı yapıldı olarak işaretler; 30 gün sonra vault'taki arşive taşınır.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Kıvılcım") var target: SparkEntity
    @Parameter(title: "Yapıldı", default: true) var done: Bool

    init() {}
    init(id: String, done: Bool = true) {
        let s = SharedStore.items().first { $0.id == id }
        target = s.map(SparkEntity.init) ?? SparkEntity(ItemSnapshot(id: id, title: "", priority: 1, status: "open", kind: "spark", area: "", color: "", date: "", noteCount: 0))
        self.done = done
    }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$target) yapıldı: \(\.$done)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SharedStore.setStatus(target.id, done: done)
        await afterEdit()
        return .result(dialog: done ? "Yapıldı: \(target.title)" : "Yeniden açık: \(target.title)")
    }
}

struct SetPriorityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Kıvılcıma öncelik ver"
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Kıvılcım") var target: SparkEntity?
    @Parameter(title: "Öncelik", default: .urgent) var priority: PriorityChoice

    init() {}
    init(id: String, priority: Priority) {
        target = SharedStore.items().first { $0.id == id }.map(SparkEntity.init)
        self.priority = PriorityChoice(rawValue: priority.rawValue) ?? .normal
    }

    static var parameterSummary: some ParameterSummary { Summary("\(\.$target) önceliği \(\.$priority)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = target ?? latestSpark().map(SparkEntity.init) else { return .result(dialog: "Kıvılcım yok.") }
        SharedStore.setPriority(s.id, priority.priority)
        await afterEdit()
        return .result(dialog: "\(priority.priority.name): \(s.title)")
    }
}

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Kıvılcıma not ekle"
    static let description = IntentDescription("Yazılı notu kıvılcımın Obsidian notundaki Notlarım bölümüne ekler.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Kıvılcım") var target: SparkEntity?
    @Parameter(title: "Not", inputOptions: String.IntentInputOptions(multiline: true), requestValueDialog: "Notun ne?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("\(\.$target) için not: \(\.$text)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = target ?? latestSpark().map(SparkEntity.init) else { return .result(dialog: "Kıvılcım yok.") }
        SharedStore.addNote(s.id, text)
        await afterEdit()
        return .result(dialog: "Not eklendi: \(s.title)")
    }
}

/// Long spoken diary: goes to the day's journal in the vault; "kıvılcım" said aloud marks an idea to pull out.
struct StartJournalIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Sesli günlük kaydet"
    static let description = IntentDescription("Uzun sesli günlüğü başlatır ya da bitirir (en çok 60 dk). Kayıt o günün günlüğüne yazılır.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    #if !WIDGET
    func perform() async throws -> some IntentResult {
        Tani.yaz("niyet: günlük (uygulama süreci)")
        if !(await KayitMerkezi.shared.degistir(kaynak: "günlük", tur: "journal")) { try await oneGecipBaslat(tur: "journal") }
        return .result()
    }
    #else
    func perform() async throws -> some IntentResult & OpensIntent {
        Tani.yaz("niyet: günlük UZANTIDA çalıştı → uygulama açılıyor")
        return .result(opensIntent: AcVeKaydetNiyeti())
    }
    #endif
}

/// In the app process: rebuild the list, send the edit to the vault, refresh open pop-up cards.
private func afterEdit() async {
    #if !WIDGET
    await MainActor.run { TelefonDeposu.shared.kur() }
    Task { await TelefonDeposu.shared.gonder() }
    OpenSparksSnippet.reload()
    LastSparkSnippet.reload()
    #endif
}

#if !WIDGET

// MARK: Pop-up cards (iOS 26 interactive snippets: Shortcuts, Siri, Action Button, Spotlight)

struct ShowOpenSparksIntent: AppIntent {
    static let title: LocalizedStringResource = "Açık kıvılcımları göster"
    static let description = IntentDescription("Açık işleri öncelik sırasıyla küçük bir pencerede gösterir; ✓ ile bitirilir.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: OpenSparksSnippet())
    }
}

struct OpenSparksSnippet: SnippetIntent {
    static let title: LocalizedStringResource = "Açık kıvılcımlar"
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: OpenSparksCard(items: Array(SharedStore.openItems().prefix(7))))
    }
}

struct OpenSparksCard: View {
    let items: [ItemSnapshot]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Açık · \(SharedStore.openItems().count)", systemImage: "flame.fill")
                .font(.headline).foregroundStyle(Color.kivilcim)
            if items.isEmpty { Text("Açık iş yok.").foregroundStyle(.secondary) }
            ForEach(items) { s in
                HStack(spacing: 10) {
                    Button(intent: MarkDoneIntent(id: s.id)) {
                        Image(systemName: "circle").font(.title3).foregroundStyle(Color(hex: s.prio.hex))
                    }.buttonStyle(.plain)
                    Text(s.title).font(.subheadline).lineLimit(2)
                    Spacer(minLength: 0)
                    if s.priority >= Priority.high.rawValue {
                        Image(systemName: s.prio.symbol).font(.caption.weight(.bold)).foregroundStyle(Color(hex: s.prio.hex))
                    }
                }
            }
        }
        .padding()
    }
}

struct EditLastSparkIntent: AppIntent {
    static let title: LocalizedStringResource = "Son kıvılcımı düzenle"
    static let description = IntentDescription("Son kaydı küçük bir pencerede açar: öncelik, yapıldı, not.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        .result(snippetIntent: LastSparkSnippet())
    }
}

struct LastSparkSnippet: SnippetIntent {
    static let title: LocalizedStringResource = "Son kıvılcım"
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: LastSparkCard(item: latestSpark()))
    }
}

struct LastSparkCard: View {
    let item: ItemSnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = item {
                Text(s.title).font(.headline).lineLimit(3)
                Text("\(s.area) · \(s.isDone ? "Yapıldı" : s.prio.name)\(s.noteCount > 0 ? " · \(s.noteCount) not" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Priority.allCases.reversed()) { p in
                        Button(intent: SetPriorityIntent(id: s.id, priority: p)) {
                            Text(p.name).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .foregroundStyle(s.priority == p.rawValue ? .white : Color(hex: p.hex))
                                .background(Capsule().fill(Color(hex: p.hex).opacity(s.priority == p.rawValue ? 1 : 0.15)))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Button(intent: MarkDoneIntent(id: s.id, done: !s.isDone)) {
                        Label(s.isDone ? "Yeniden aç" : "Yapıldı", systemImage: s.isDone ? "arrow.uturn.backward" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.green)
                    Button(intent: AddNoteIntent()) {
                        Label("Not ekle", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            } else {
                Text("Henüz kıvılcım yok.").foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#endif
