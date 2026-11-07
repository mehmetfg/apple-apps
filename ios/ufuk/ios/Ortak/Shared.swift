// Shared by the app and the widget extension: the snapshot the app writes after every forecast,
// the Live Activity attributes, the sun calculator and the colours.
import ActivityKit
import Foundation
import SwiftUI

enum Shared {
    /// The PDM App Group is already registered for the team; Ufuk keeps its own file there.
    static let appGroup = "group.com.fatihgocgun.pdm"
    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "ufuk-snapshot.json")
    }
}

// MARK: - Snapshot (app → widget)

enum LegKind: String, Codable, Hashable, Sendable { case morning, lunch, evening }

struct LegSummary: Codable, Hashable, Sendable {
    var kind: LegKind
    var title: String              // "Sabah · işe gidiş"
    var windowStart: Date
    var windowEnd: Date
    var slotStart: Date            // first 15-minute slot of `probs`
    var probs: [Double]            // rain chance per 15 minutes, 0…1
    var bestDeparture: Date?
    var plannedDeparture: Date?
    var maxProb: Double
    var rideFeel: Double?          // °C felt on the bike
    var baseLayer: Bool
    var windproof: Bool
    var hazards: [String]
    var verdict: String            // one line: "Kuru · 07:45 çık"
}

/// One hour ahead, for the "next hours" strip in the app and the widget.
struct HourSummary: Codable, Hashable, Sendable {
    var time: Date
    var prob: Double               // highest rain chance in the hour
    var temp: Double
    var wind: Double
    var code: Int
    var dark: Bool                 // the sun is below civil twilight at the start of the hour
}

/// One day ahead for the five-day widget.
struct DaySummary: Codable, Hashable, Sendable {
    var day: Date                  // local midnight
    var tMax: Double
    var tMin: Double
    var rainProb: Double           // 0…1, highest hourly chance of the day
    var rainMM: Double
    var code: Int
}

struct SunDay: Codable, Hashable, Sendable {
    var dawn: Date?                // civil twilight begins
    var sunrise: Date?
    var sunset: Date?
    var dusk: Date?                // civil twilight ends: it is dark
    var daylight: TimeInterval { guard let a = sunrise, let b = sunset else { return 0 }; return b.timeIntervalSince(a) }
}

struct Snapshot: Codable, Sendable {
    var generated: Date
    var placeName: String
    var temperature: Double?
    var weatherCode: Int?
    var legs: [LegSummary]
    var lunchMinutes: Int
    var lunchVerdict: String
    var today: SunDay
    var tomorrow: SunDay
    var hours: [HourSummary]? = nil      // optional: snapshots written before 2026-11-03 have none
    var outing: String? = nil            // "Kavaklık Parkı · bu hafta 0/1"
    var nowProb: Double? = nil           // rain chance in the current quarter hour
    var todayMax: Double? = nil
    var todayMin: Double? = nil
    var days: [DaySummary]? = nil        // today and the next days, from the daily forecast

    /// The sun of the day that still has light ahead: today until dusk, then tomorrow.
    func lightDay(at d: Date) -> SunDay { (today.dusk.map { d < $0 } ?? true) ? today : tomorrow }

    /// When light comes next: today's dawn, or tomorrow's once today's has passed.
    func nextLight(after d: Date) -> Date? { (today.dawn.map { d < $0 } ?? false) ? today.dawn : tomorrow.dawn }
    /// When dark comes next: today's dusk, or tomorrow's.
    func nextDark(after d: Date) -> Date? { (today.dusk.map { d < $0 } ?? false) ? today.dusk : tomorrow.dusk }

    func leg(_ k: LegKind) -> LegSummary? { legs.first { $0.kind == k } }

    static func load() -> Snapshot? {
        guard let u = Shared.snapshotURL, let d = try? Data(contentsOf: u) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Snapshot.self, from: d)
    }

    func save() {
        guard let u = Shared.snapshotURL else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(self) { try? d.write(to: u, options: .atomic) }
    }

    static let preview = Snapshot(
        generated: .now, placeName: "Ev", temperature: 9, weatherCode: 61,
        legs: [LegSummary(kind: .evening, title: "Akşam · eve dönüş", windowStart: .now, windowEnd: .now.addingTimeInterval(10800),
                          slotStart: .now, probs: [0.05, 0.1, 0.2, 0.6, 0.8, 0.4, 0.1, 0.05], bestDeparture: .now.addingTimeInterval(1800),
                          plannedDeparture: .now.addingTimeInterval(3600), maxProb: 0.8, rideFeel: 6, baseLayer: true, windproof: false,
                          hazards: ["Karanlıkta dönüş"], verdict: "17:30'da çık · sonra yağmur")],
        lunchMinutes: 35, lunchVerdict: "35 dk yürüyüş uygun",
        today: SunDay(dawn: .now, sunrise: .now, sunset: .now.addingTimeInterval(3600), dusk: .now.addingTimeInterval(5400)),
        tomorrow: SunDay(dawn: .now, sunrise: .now.addingTimeInterval(50000), sunset: nil, dusk: nil),
        hours: (0..<6).map { HourSummary(time: .now.addingTimeInterval(Double($0) * 3600), prob: [0.05, 0.1, 0.6, 0.3, 0.1, 0.05][$0],
                                         temp: 11 - Double($0), wind: 12, code: [1, 3, 61, 80, 3, 1][$0], dark: $0 > 3) },
        outing: "Kavaklık Parkı · bu hafta 0/1", nowProb: 0.2, todayMax: 18, todayMin: 11,
        days: (0..<6).map { DaySummary(day: Calendar.current.startOfDay(for: .now).addingTimeInterval(Double($0) * 86400 + 3600),
                                       tMax: [18, 15, 13, 16, 19, 17][$0], tMin: [11, 10, 8, 9, 12, 11][$0],
                                       rainProb: [0.66, 0.91, 0.4, 0.1, 0.05, 0.3][$0], rainMM: [3, 12, 1, 0, 0, 0.4][$0],
                                       code: [61, 63, 80, 2, 0, 3][$0]) })
}

// MARK: - Live Activity

struct RideAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var slotStart: Date
        var probs: [Double]        // next 90 minutes, 15-minute steps
        var dusk: Date?
        var note: String           // "Yağış 08:15'te başlıyor" / "Yol boyu kuru"
        var rideFeel: Double?
    }
    var leg: String                // "Sabah" / "Akşam"
    var arrival: Date
}

// MARK: - Sun

/// NOAA solar position. Times come from scanning the day minute by minute for the elevation crossings,
/// which is simple and exact enough (±1 minute) for every latitude the person will ride at.
enum Sun {
    static func elevation(_ date: Date, lat: Double, lon: Double) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545) / 36525
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let mr = m * .pi / 180
        let c = sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * mr) * (0.019993 - 0.000101 * t) + sin(3 * mr) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * .pi / 180)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = (eps0 + 0.00256 * cos(omega * .pi / 180)) * .pi / 180
        let decl = asin(sin(eps) * sin(lambda * .pi / 180))
        let y = pow(tan(eps / 2), 2)
        let l0r = l0 * .pi / 180
        let eqTime = 4 * (y * sin(2 * l0r) - 2 * e * sin(mr) + 4 * e * y * sin(mr) * cos(2 * l0r)
                          - 0.5 * y * y * sin(4 * l0r) - 1.25 * e * e * sin(2 * mr)) * 180 / .pi
        let utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
        let trueSolar = (utcMinutes + eqTime + 4 * lon).truncatingRemainder(dividingBy: 1440)
        var hourAngle = trueSolar / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }
        let latr = lat * .pi / 180
        let cosZen = sin(latr) * sin(decl) + cos(latr) * cos(decl) * cos(hourAngle * .pi / 180)
        return 90 - acos(max(-1, min(1, cosZen))) * 180 / .pi
    }

    static func day(_ date: Date, lat: Double, lon: Double, calendar: Calendar = .current) -> SunDay {
        let start = calendar.startOfDay(for: date)
        var prev = elevation(start, lat: lat, lon: lon)
        var r = SunDay()
        for minute in 1...1440 {
            let t = start.addingTimeInterval(Double(minute) * 60)
            let e = elevation(t, lat: lat, lon: lon)
            func crossed(_ h: Double) -> Bool? { prev < h && e >= h ? true : (prev >= h && e < h ? false : nil) }
            // linear interpolation inside the minute puts the time within seconds
            func at(_ h: Double) -> Date { t.addingTimeInterval(-60 + 60 * (h - prev) / (e - prev)) }
            if crossed(-6) == true, r.dawn == nil { r.dawn = at(-6) }
            if crossed(-0.833) == true, r.sunrise == nil { r.sunrise = at(-0.833) }
            if crossed(-0.833) == false { r.sunset = at(-0.833) }
            if crossed(-6) == false { r.dusk = at(-6) }
            prev = e
        }
        return r
    }
}

// MARK: - Look

enum Palette {
    static func rain(_ p: Double) -> Color {
        switch p {
        case ..<0.15: Color(red: 0.45, green: 0.85, blue: 0.75)
        case ..<0.35: Color(red: 0.98, green: 0.82, blue: 0.40)
        case ..<0.6: Color(red: 0.99, green: 0.58, blue: 0.30)
        default: Color(red: 0.95, green: 0.33, blue: 0.40)
        }
    }
    static let ink = Color.white
    static let soft = Color.white.opacity(0.72)
}

enum Fmt {
    static let hm: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"; return f }()
    static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMMM EEEE"; return f }()
    static let short: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "EEE d"; return f }()
    static func t(_ d: Date?) -> String { d.map { hm.string(from: $0) } ?? "—" }
    /// "07:45'te", "18:30'da": the locative suffix follows how the last number is read aloud.
    static func at(_ d: Date?) -> String {
        guard let d else { return "—" }
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let n = (c.minute ?? 0) > 0 ? c.minute! : (c.hour ?? 0)
        let ones = ["da", "de", "de", "te", "te", "te", "da", "de", "de", "da"]
        let tens = [0: "da", 1: "da", 2: "de", 3: "da", 4: "ta", 5: "de"]
        let sfx = n % 10 != 0 ? ones[n % 10] : (tens[n / 10] ?? "da")
        return "\(hm.string(from: d))'\(sfx)"
    }
    static func deg(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))°" } ?? "—" }
    /// "2,2 km", "480 m"
    static func km(_ meters: Double, digits: Int = 1) -> String {
        meters >= 1000 ? (meters / 1000).formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "tr_TR"))) + " km" : "\(Int(meters)) m"
    }
    static func pct(_ p: Double) -> String { "%\(Int((p * 100).rounded()))" }
    static func span(_ s: TimeInterval) -> String {
        let m = Int(s / 60); return m >= 60 ? "\(m / 60) sa \(m % 60) dk" : "\(m) dk"
    }
}

/// WMO weather code → SF Symbol and a short Turkish word.
enum WMO {
    static func symbol(_ c: Int?, night: Bool = false) -> String {
        switch c ?? 0 {
        case 0: night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
    static func word(_ c: Int?) -> String {
        switch c ?? 0 {
        case 0: "Açık"
        case 1, 2: "Parçalı bulutlu"
        case 3: "Kapalı"
        case 45, 48: "Sis"
        case 51...57: "Çiseleme"
        case 61, 80: "Hafif yağmur"
        case 63, 81: "Yağmur"
        case 65, 82: "Sağanak"
        case 66, 67: "Donan yağmur"
        case 71...77, 85, 86: "Kar"
        case 95...99: "Gök gürültülü"
        default: "Bulutlu"
        }
    }
}
