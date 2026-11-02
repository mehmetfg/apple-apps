// Turning the five-move sets into a habit: four phases counted in practised nights, the weekly automaticity check (SRBAI)
// and the anchor (the thing the routine follows every night).
import Foundation

/// Phases follow practised nights, not calendar days: a missed night does not move you on.
/// 66 is the median days to automaticity in Lally et al. 2010 (range 18–254), so "settled" also asks the person (SRBAI).
enum HabitPhase: String, Codable, CaseIterable {
    case learn, recall, settle, settled

    static let learnUntil = 9, recallUntil = 42, settleUntil = 66

    var title: String {
        switch self {
        case .learn: return "Öğren"
        case .recall: return "Ezberle"
        case .settle: return "Oturt"
        case .settled: return "Yerleşti"
        }
    }

    var range: String {
        switch self {
        case .learn: return "1–9. gece"
        case .recall: return "10–42. gece"
        case .settle: return "43–66. gece"
        case .settled: return "66+ ve kendiliğinden"
        }
    }

    var summary: String {
        switch self {
        case .learn: return "Her beşli üç gece üst üste: A, A, A, sonra B, sonra C. Ekran ve ses her hareketi anlatır."
        case .recall: return "Beşliler her gece döner. Her duraktan önce uygulama sorar: sıradaki hareket ne? Önce sen hatırla, sonra bak."
        case .settle: return "Ses yalnızca durak numarasını söyler, ekrana bakmadan yaparsın. Haftada bir dört soruluk otomatiklik ölçümü."
        case .settled: return "Rutin düşünmeden başlıyor. Hedef artık sürdürmek: kötü gecede mini (2 dk), iki gece üst üste kaçırmamak."
        }
    }

    static func of(nights: Int, lastChecks: [HabitCheck]) -> HabitPhase {
        if nights < learnUntil { return .learn }
        if nights < recallUntil { return .recall }
        let recent = lastChecks.suffix(2)
        if nights >= settleUntil, recent.count == 2, recent.allSatisfy({ $0.score >= HabitCheck.settledScore }) { return .settled }
        return .settle
    }

    /// Which set tonight. Learn: blocked (three nights each), afterwards interleaved. Practice count, not the date.
    static func setKey(nights: Int, legHeavy: Bool) -> (String, String) {
        let order = Catalog.order
        if nights < learnUntil {
            let k = order[min(nights / 3, order.count - 1)]
            return (k, "Öğrenme: \(k) beşlisinin \(nights % 3 + 1). gecesi")
        }
        let k = order[nights % order.count]
        if legHeavy && k != "C" { return ("C", "Bugün çok yürüdün ya da pedal çevirdin: ÇEK (bacak) öne alındı") }
        return (k, "Sırası gelen beşli")
    }
}

/// Self-Report Behavioural Automaticity Index (Gardner et al. 2012): four items, 1–7.
struct HabitCheck: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var items: [Int]
    var nightNo: Int

    var score: Double { items.isEmpty ? 0 : Double(items.reduce(0, +)) / Double(items.count) }
    static let settledScore = 5.5
    static let questions = [
        "Gece rutinini otomatik olarak yapıyorum.",
        "Bilinçli olarak hatırlamak zorunda kalmadan yapıyorum.",
        "Üzerine düşünmeden yapıyorum.",
        "Farkına varmadan başlamış oluyorum.",
    ]
}
