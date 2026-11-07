// Weather against the person's own days: steps, cycling, sleep, mood and production minutes.
// A finding is shown only when both sides have enough days; otherwise it says how many are missing.
import Foundation

struct DayRecord: Identifiable, Hashable, Sendable {
    var id: Date { day }
    var day: Date
    var weather: PastDay?
    var health: HealthDay?
    var mood: Int?
    var productionMin: Double?
    var rides: Int
}

struct Finding: Identifiable, Hashable, Sendable {
    var id: String { title + metric }
    var title: String          // "Yağmurlu günler"
    var metric: String         // "Adım"
    var a: Double              // mean in the condition
    var b: Double              // mean otherwise
    var na: Int
    var nb: Int
    var unit: String
    var text: String
    var change: Double { b == 0 ? 0 : (a - b) / b }
}

enum Insights {
    static let minEach = 5

    struct Metric { var name: String; var unit: String; var value: (DayRecord) -> Double? }

    static let metrics: [Metric] = [
        .init(name: "Adım", unit: "") { $0.health?.steps },
        .init(name: "Bisiklet", unit: "km") { $0.health?.cycleKm },
        .init(name: "Yürüyüş", unit: "km") { $0.health?.walkKm },
        .init(name: "Uyku", unit: "sa") { $0.health?.sleepH },
        .init(name: "Ruh hâli", unit: "/5") { $0.mood.map(Double.init) },
        .init(name: "Üretim", unit: "dk") { $0.productionMin },
    ]

    struct Split { var title: String; var test: (PastDay) -> Bool; var other: String }

    static func splits(_ days: [DayRecord]) -> [Split] {
        let dl = days.compactMap { $0.weather?.daylightH }.sorted()
        let mid = dl.isEmpty ? 11 : dl[dl.count / 2]
        let sun = days.compactMap { $0.weather?.sunshineH }.sorted()
        let sunMid = sun.isEmpty ? 5 : sun[sun.count / 2]
        return [
            Split(title: "Yağmurlu günler", test: { $0.rainMM >= 1 }, other: "kuru günler"),
            Split(title: "Kısa günler", test: { $0.daylightH < mid }, other: "uzun günler"),
            Split(title: "Güneşsiz günler", test: { $0.sunshineH < sunMid }, other: "güneşli günler"),
            Split(title: "Soğuk günler", test: { $0.tMax < 12 }, other: "ılık günler"),
        ]
    }

    static func findings(_ days: [DayRecord]) -> (found: [Finding], waiting: Int) {
        var out: [Finding] = []
        var waiting = 0
        for sp in splits(days) {
            for m in metrics {
                var a: [Double] = [], b: [Double] = []
                for d in days {
                    guard let w = d.weather, let v = m.value(d) else { continue }
                    if sp.test(w) { a.append(v) } else { b.append(v) }
                }
                guard a.count >= minEach, b.count >= minEach else {
                    if !a.isEmpty || !b.isEmpty { waiting += 1 }
                    continue
                }
                let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
                guard mb != 0 || ma != 0 else { continue }
                // Only differences larger than the day-to-day noise are worth a sentence.
                let all = a + b, mean = all.reduce(0, +) / Double(all.count)
                let sd = sqrt(all.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(1, all.count - 1)))
                let se = sd * sqrt(1 / Double(a.count) + 1 / Double(b.count))
                guard se > 0, abs(ma - mb) > 1.5 * se else { continue }
                let more = ma > mb
                let diff = fmt(abs(ma - mb), m.unit)
                // every title ends in "günler", so the locative is always "-de"
                let text = "\(sp.title)de \(m.name.lowercased(with: Locale(identifier: "tr_TR"))) \(more ? "artıyor" : "düşüyor"): ortalama \(fmt(ma, m.unit)), \(sp.other)de \(fmt(mb, m.unit)) (fark \(diff))."
                out.append(Finding(title: sp.title, metric: m.name, a: ma, b: mb, na: a.count, nb: b.count, unit: m.unit, text: text))
            }
        }
        return (out.sorted { abs($0.change) > abs($1.change) }, waiting)
    }

    static func fmt(_ v: Double, _ unit: String) -> String {
        switch unit {
        case "": v >= 1000 ? String(format: "%.1f bin", v / 1000) : String(Int(v.rounded()))
        case "/5": String(format: "%.1f/5", v)
        case "sa": String(format: "%.1f sa", v)
        case "km": String(format: "%.1f km", v)
        default: "\(Int(v.rounded())) \(unit)"
        }
    }
}

