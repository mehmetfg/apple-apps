import AppKit
import SwiftUI

/// Kıvılcım ↔ Kurultay: records go to Kurultay's selection (kurultay://kivilcim?ids=…);
/// Kurultay writes back which sessions used which record (_araçlar/kurultay/durum/kivilcim-baglar.json).
enum KurultayBag {
    static func send(_ ids: [String]) {
        var c = URLComponents(); c.scheme = "kurultay"; c.host = "kivilcim"
        c.queryItems = [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]
        guard let u = c.url else { return }
        if !NSWorkspace.shared.open(u) {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Kurultay.app"))
        }
    }

    static func openSession(_ id: String) {
        var c = URLComponents(); c.scheme = "kurultay"; c.host = "oturum"; c.queryItems = [URLQueryItem(name: "id", value: id)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }

    static func stateLabel(_ s: [String: String]) -> String {
        switch s["decision"] ?? "" {
        case "onaylandi": "onaylandı"
        case "duzelt": "düzeltme istendi"
        case "reddedildi": "reddedildi"
        case "uygulandi": "uygulandı"
        case "bekliyor": "onay bekliyor"
        default: s["report"] == "1" ? "rapor yazıldı" : "rapor bekleniyor"
        }
    }

    static func links(_ vault: URL) -> [String: [[String: String]]] {
        let u = vault.appendingPathComponent("_araçlar/kurultay/durum/kivilcim-baglar.json")
        guard let d = try? Data(contentsOf: u), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o["baglar"] as? [String: [[String: String]]] ?? [:]
    }
}

/// Under a record: the Kurultay sessions it was asked in, and a button to ask about it.
struct KurultayRow: View {
    @EnvironmentObject var depo: Depo
    let o: Oge

    var body: some View {
        let used = KurultayBag.links(depo.vault)[o.id] ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Kurultay", systemImage: "person.3.sequence").font(.headline)
                Spacer()
                Button { KurultayBag.send([o.id]) } label: { Label("Kurultay'a sor", systemImage: "paperplane") }
                    .help("Kaydı Kurultay'ın seçimine ekler; başka kayıtları da ekleyip birlikte sorabilirsin")
            }
            if used.isEmpty {
                Text("Bu kayıt henüz Kurultay'a sorulmadı.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(used, id: \.self) { s in
                Button { KurultayBag.openSession(s["session"] ?? "") } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: s["report"] == "1" ? "checkmark.seal" : "hourglass").foregroundStyle(s["report"] == "1" ? .green : .orange)
                            Text(s["title"] ?? "").lineLimit(1)
                            Spacer()
                            Text(KurultayBag.stateLabel(s)).font(.caption).foregroundStyle(.secondary)
                            Text(String((s["date"] ?? "").prefix(10))).font(.caption).foregroundStyle(.tertiary)
                        }
                        if let sum = s["summary"], !sum.isEmpty {
                            Text(sum).font(.callout).foregroundStyle(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("Kurultay'da bu oturumu aç")
            }
        }
        .padding(12)
        .background { RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)) }
    }
}
