// Giyim Defteri: the person writes down the day they move from short sleeves to long (or back, or to a base
// layer, or a coat). Ufuk keeps the weather of that moment, and a year later shows when and at what
// temperature the same change came, so the next one can be seen coming.
import Foundation

enum Garment: Int, Codable, CaseIterable, Comparable, Sendable {
    case shortSleeve = 0, longSleeve, baseLayer, coat

    static func < (a: Garment, b: Garment) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self { case .shortSleeve: "Kısa kol"; case .longSleeve: "Uzun kol"; case .baseLayer: "İçlik"; case .coat: "Mont" }
    }
    /// "kısa kola", "uzun kola", "içliğe", "monta"
    var dative: String {
        switch self { case .shortSleeve: "kısa kola"; case .longSleeve: "uzun kola"; case .baseLayer: "içliğe"; case .coat: "monta" }
    }
    var symbol: String {
        switch self { case .shortSleeve: "tshirt"; case .longSleeve: "tshirt.fill"; case .baseLayer: "square.stack.3d.up.fill"; case .coat: "cloud.snow.fill" }
    }
}

struct GarmentChange: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var from: Garment?
    var to: Garment
    var temp: Double?             // air at that moment
    var feels: Double?            // apparent temperature
    var wind: Double?
    var tMin: Double?             // the day's low and high from the forecast
    var tMax: Double?
    var daylightMin: Int          // minutes between sunrise and sunset that day
    var note: String?

    var warmer: Bool { from.map { to < $0 } ?? false }
}

/// What last year says about now.
struct WardrobeHint: Hashable, Sendable {
    var title: String             // "Geçen yıl 14 Ekim'de uzun kola geçtin"
    var detail: String            // "hissedilen 13° · gün 10 sa 52 dk"
    var soon: Bool                // the change is ahead within the coming days
    var reached: String?          // "Bu hafta en düşük hissedilen 11°: o eşiğe geldi"
}

enum Wardrobe {
    static let dm: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM"; return f }()

    /// "14 Ekim'de", "12 Kasım'da", "3 Mart'ta": the suffix follows the month's last vowel and consonant.
    static func onDay(_ d: Date) -> String {
        let sfx = ["", "ta", "ta", "ta", "da", "ta", "da", "da", "ta", "de", "de", "da", "ta"]
        return "\(dm.string(from: d))'\(sfx[Calendar.current.component(.month, from: d)])"
    }

    /// Day of year distance that wraps around the new year.
    static func dayGap(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        let x = cal.ordinality(of: .day, in: .year, for: a) ?? 0, y = cal.ordinality(of: .day, in: .year, for: b) ?? 0
        var d = y - x
        if d > 182 { d -= 365 }; if d < -182 { d += 365 }
        return d
    }

    /// Changes from earlier years near today's date: the ones just behind (−10 days) and the ones ahead (+30).
    /// The nearest one ahead becomes the hint; if none is ahead, the most recent one behind.
    static func hint(_ changes: [GarmentChange], now: Date = .now, coldestFeelAhead: Double?) -> WardrobeHint? {
        let year = Calendar.current.component(.year, from: now)
        let past = changes.filter { Calendar.current.component(.year, from: $0.date) < year }
        let near = past.map { ($0, dayGap(now, $0.date)) }.filter { $0.1 >= -10 && $0.1 <= 30 }
        guard let (c, gap) = near.filter({ $0.1 >= 0 }).min(by: { $0.1 < $1.1 }) ?? near.max(by: { $0.1 < $1.1 }) else { return nil }
        let y = Calendar.current.component(.year, from: c.date)
        let ago = year - y == 1 ? "Geçen yıl" : "\(y)'de"
        let title = "\(ago) \(onDay(c.date)) \(c.to.dative) geçtin"
        var parts: [String] = []
        if let f = c.feels { parts.append("hissedilen \(Fmt.deg(f))") }
        if let lo = c.tMin, let hi = c.tMax { parts.append("gün \(Fmt.deg(lo))–\(Fmt.deg(hi))") }
        parts.append("gün ışığı \(Fmt.span(TimeInterval(c.daylightMin * 60)))")
        let when = gap == 0 ? "bugün" : (gap > 0 ? "\(gap) gün sonrası" : "\(-gap) gün önce")
        var reached: String?
        if let f = c.feels, let ahead = coldestFeelAhead, !c.warmer, ahead <= f {
            reached = "Önümüzdeki günlerde hissedilen \(Fmt.deg(ahead)) iniyor: geçen yılki eşiğin \(Fmt.deg(f))."
        }
        return WardrobeHint(title: title, detail: "\(when) · " + parts.joined(separator: " · "), soon: gap >= 0, reached: reached)
    }

    /// Changes grouped by year, newest year first.
    static func byYear(_ changes: [GarmentChange]) -> [(year: Int, items: [GarmentChange])] {
        Dictionary(grouping: changes) { Calendar.current.component(.year, from: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.0 > $1.0 }
    }
}
