// New-model checklist (2026-11-10): the standard tasks and prompts to run whenever a strong new model comes out.
// Source: vault 05 - Notlar/Fikirler/Kıvılcım/NewModel/checklist.json (edited in Obsidian or by Claude); the phone
// keeps a copy that iCloud or the Mac (isle.py, over USB/Wi-Fi) refreshes. Which task ran on which model is kept on
// this phone only (UserDefaults): it is a personal tick list, not shared state.
import SwiftUI
import UIKit

struct NewModelTask: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var why: String = ""
    var prompt: String
    var area: String = "genel"

    enum CodingKeys: String, CodingKey { case id, title, why, prompt, area }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        why = (try? c.decode(String.self, forKey: .why)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        area = (try? c.decode(String.self, forKey: .area)) ?? "genel"
    }
}

struct NewModelChecklist: Codable, Sendable {
    var updated: String
    var items: [NewModelTask]
    static let empty = NewModelChecklist(updated: "", items: [])
}

/// Reads the local copy, remembers the current model and which tasks were run on which model.
@MainActor final class NewModelStore: ObservableObject {
    static let shared = NewModelStore()
    @Published private(set) var list = NewModelChecklist.empty
    @Published var current: String { didSet { UserDefaults.standard.set(current, forKey: Self.currentKey) } }
    /// task id → model name → day it was run (yyyy-MM-dd)
    @Published private(set) var runs: [String: [String: String]]

    private static let currentKey = "newModelCurrent", runsKey = "newModelRuns"
    nonisolated static var copyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kivilcim/newmodel.json")
    }
    static let vaultPath = "NewModel/checklist.json"

    private init() {
        current = UserDefaults.standard.string(forKey: Self.currentKey) ?? ""
        runs = UserDefaults.standard.dictionary(forKey: Self.runsKey) as? [String: [String: String]] ?? [:]
        load()
    }

    func load() {
        guard let v = try? Data(contentsOf: Self.copyURL), let l = try? JSONDecoder().decode(NewModelChecklist.self, from: v),
              l.updated != list.updated || list.items.isEmpty else { return }
        list = l
    }

    /// iCloud's copy replaces the local one only if it is not older (the Mac may have pushed a newer one straight).
    nonisolated static func takeFromVault(_ data: Data) {
        guard let new = try? JSONDecoder().decode(NewModelChecklist.self, from: data) else { return }
        let old = (try? Data(contentsOf: copyURL)).flatMap { try? JSONDecoder().decode(NewModelChecklist.self, from: $0) }
        if new.updated >= (old?.updated ?? "") { try? data.write(to: copyURL, options: .atomic) }
    }

    func isDone(_ t: NewModelTask) -> Bool { !current.isEmpty && runs[t.id]?[current] != nil }
    var doneCount: Int { list.items.filter(isDone).count }
    var progress: Double { list.items.isEmpty ? 0 : Double(doneCount) / Double(list.items.count) }

    func toggle(_ t: NewModelTask) {
        guard !current.isEmpty else { return }
        var r = runs[t.id] ?? [:]
        if r[current] != nil { r[current] = nil } else { r[current] = Zaman.formatter("yyyy-MM-dd", posix: true).string(from: Date()) }
        runs[t.id] = r
        UserDefaults.standard.set(runs, forKey: Self.runsKey)
    }

    /// Models a task was already run on, newest first.
    func history(_ t: NewModelTask) -> [(model: String, day: String)] {
        (runs[t.id] ?? [:]).map { ($0.key, $0.value) }.sorted { $0.day > $1.day }
    }
}

private let newModelColor = Color(hex: "#2F6FEB")

struct NewModelKarti: View {
    @ObservedObject private var store = NewModelStore.shared
    var body: some View {
        MCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Yeni model listesi", systemImage: "sparkles.rectangle.stack").font(.headline).foregroundStyle(newModelColor)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if store.list.items.isEmpty {
                    Text("Liste vault'tan henüz gelmedi: NewModel/checklist.json").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 14) {
                        StatusRing(value: store.progress, color: newModelColor, size: 52, line: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.current.isEmpty ? "Model seçilmedi" : store.current)
                                .font(.system(.title3, design: .serif).weight(.semibold))
                            Text("\(store.doneCount) / \(store.list.items.count) görev denendi")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let next = store.list.items.first(where: { !store.isDone($0) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle").foregroundStyle(newModelColor)
                            Text(next.title).font(.subheadline).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct NewModelSayfasi: View {
    @ObservedObject private var store = NewModelStore.shared
    @State private var editing = false
    @State private var draft = ""
    @State private var copied: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    StatusRing(value: store.progress, color: newModelColor, size: 56, line: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.current.isEmpty ? "Hangi modeli deniyorsun?" : store.current)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                        Text("Yeni ve güçlü bir model çıktığında bu görevleri ona sırayla ver; sonuçları önceki modellerle karşılaştır.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button(store.current.isEmpty ? "Modeli yaz" : "Modeli değiştir") { draft = store.current; editing = true }
            }
            Section("Görevler") {
                ForEach(store.list.items) { t in row(t) }
            }
            if !store.list.updated.isEmpty {
                Section { Text("Liste: vault › Kıvılcım › NewModel/checklist.json · \(store.list.updated.prefix(10))").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Yeni model")
        .alert("Model adı", isPresented: $editing) {
            TextField("ör. Opus 5.5", text: $draft)
            Button("Kaydet") { store.current = draft.trimmingCharacters(in: .whitespaces) }
            Button("Vazgeç", role: .cancel) {}
        }
        .onAppear { store.load() }
    }

    private func row(_ t: NewModelTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button { store.toggle(t) } label: {
                    Image(systemName: store.isDone(t) ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(store.isDone(t) ? newModelColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(store.current.isEmpty)
                .accessibilityLabel(store.isDone(t) ? "Denendi işaretini kaldır" : "Denendi olarak işaretle")
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.title).font(.body.weight(.semibold))
                    if !t.why.isEmpty { Text(t.why).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            DisclosureGroup("İstem") {
                Text(t.prompt).font(.callout).textSelection(.enabled).padding(.vertical, 4)
            }
            .font(.footnote)
            HStack {
                Button {
                    UIPasteboard.general.string = t.prompt
                    copied = t.id
                    Task { try? await Task.sleep(for: .seconds(1.5)); if copied == t.id { copied = nil } }
                } label: {
                    Label(copied == t.id ? "Kopyalandı" : "İstemi kopyala", systemImage: copied == t.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small)
                Spacer()
                let h = store.history(t)
                if !h.isEmpty {
                    Text(h.prefix(3).map(\.model).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
