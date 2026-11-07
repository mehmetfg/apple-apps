// The commute decision: rain in the window, the driest departure, what to wear and what can hurt.
import Foundation

struct Hazard: Hashable, Sendable {
    enum Level: Int, Comparable, Sendable { case note, caution, danger; static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue } }
    var level: Level
    var text: String
    var symbol: String
}

struct Leg: Sendable, Identifiable {
    var id: String { kind.rawValue }
    var kind: LegKind
    var day: Date
    var title: String
    var windowStart: Date
    var windowEnd: Date
    var slots: [Slot]                 // all slots of the window
    var planned: Date
    var best: Date
    var rideMinutes: Int
    var rideSlots: [Slot]             // slots of the planned ride
    var bestSlots: [Slot]
    var feel: Double?
    var baseLayer: Bool
    var windproof: Bool
    var hazards: [Hazard]
    var verdict: String
    var detail: String

    var plannedMax: Double { rideSlots.map(\.prob).max() ?? 0 }
    var bestMax: Double { bestSlots.map(\.prob).max() ?? 0 }
    var windowMax: Double { slots.map(\.prob).max() ?? 0 }
    var confidence: Double { rideSlots.isEmpty ? 0 : rideSlots.map(\.confidence).reduce(0, +) / Double(rideSlots.count) }
    /// First quarter in the window where rain becomes likely.
    var rainStart: Date? { slots.first { $0.prob >= 0.4 }?.time }

    func summary() -> LegSummary {
        LegSummary(kind: kind, title: title, windowStart: windowStart, windowEnd: windowEnd, slotStart: slots.first?.time ?? windowStart,
                   probs: slots.map(\.prob), bestDeparture: best, plannedDeparture: planned, maxProb: windowMax, rideFeel: feel,
                   baseLayer: baseLayer, windproof: windproof, hazards: hazards.filter { $0.level >= .caution }.map(\.text), verdict: verdict)
    }
}

struct Settings: Sendable {
    var morningStart = 7 * 60, morningEnd = 9 * 60, morningDepart = 7 * 60 + 30
    var eveningStart = 16 * 60, eveningEnd = 19 * 60, eveningDepart = 17 * 60 + 30
    var lunchStart = 12 * 60, lunchEnd = 13 * 60
    var rideMinutes = 30
    var rideSpeed = 18.0
}

enum Decision {
    static func at(_ day: Date, _ minutes: Int) -> Date {
        Calendar.current.startOfDay(for: day).addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func leg(_ kind: LegKind, day: Date, f: Forecast, s: Settings, sun: SunDay, th: Thresholds) -> Leg {
        let (ws, we, dep, title): (Int, Int, Int, String) = kind == .morning
            ? (s.morningStart, s.morningEnd, s.morningDepart, "Sabah · işe gidiş")
            : (s.eveningStart, s.eveningEnd, s.eveningDepart, "Akşam · eve dönüş")
        let wStart = at(day, ws), wEnd = at(day, we)
        let ride = TimeInterval(s.rideMinutes * 60)
        let slots = f.slots(from: wStart, to: wEnd)
        let planned = at(day, dep)

        func rideSlots(_ d: Date) -> [Slot] { f.slots(from: d, to: d.addingTimeInterval(ride)) }
        func dark(_ d: Date) -> Bool {
            kind == .evening ? (sun.dusk.map { d.addingTimeInterval(ride) > $0 } ?? false) : (sun.dawn.map { d < $0 } ?? false)
        }
        func risk(_ d: Date) -> Double {
            let r = rideSlots(d)
            guard !r.isEmpty else { return 9 }
            let rain = r.map(\.prob).max() ?? 0
            let mm = r.map { $0.precipMean * $0.prob }.reduce(0, +)
            let gust = max(0, (r.map(\.gust).max() ?? 0) - 35) / 60
            return rain + 0.4 * mm + gust + (dark(d) ? 0.12 : 0) + abs(d.timeIntervalSince(planned)) / 60 * 0.0015
        }
        var cands: [Date] = []
        var t = wStart
        while t.addingTimeInterval(ride) <= wEnd { cands.append(t); t.addTimeInterval(900) }
        if !cands.contains(planned) { cands.append(planned) }
        var best = cands.min { risk($0) < risk($1) } ?? planned
        if risk(planned) - risk(best) < 0.06 { best = planned }

        let rs = rideSlots(planned), bs = rideSlots(best)
        let mid = rs.isEmpty ? f.slot(at: planned) : rs[rs.count / 2]
        let wet = rs.contains { $0.prob >= 0.5 && $0.precipMean >= 0.05 }
        let feel = mid.map { Clothing.rideFeel(temp: $0.temp, wind: $0.wind, speed: s.rideSpeed, wet: wet) }
        let hz = hazards(rs, kind: kind, depart: planned, ride: ride, sun: sun, feel: feel)

        let pm = rs.map(\.prob).max() ?? 0, bm = bs.map(\.prob).max() ?? 0
        var verdict: String, detail: String
        if rs.isEmpty {
            verdict = "Tahmin yok"; detail = "Bu saatler için veri gelmedi."
        } else if pm < 0.2 {
            verdict = "Kuru · \(Fmt.at(planned)) çık"
            detail = "Yol boyu yağış ihtimali en çok \(Fmt.pct(pm))."
        } else if best != planned, pm - bm >= 0.15 {
            verdict = "\(Fmt.at(best)) çık · \(Fmt.pct(bm))"
            detail = "\(Fmt.at(planned)) çıkarsan yağış ihtimali \(Fmt.pct(pm)); \(Fmt.at(best)) \(Fmt.pct(bm))."
        } else if pm >= 0.6 {
            verdict = "Yağmurlu · \(Fmt.pct(pm))"
            detail = "Pencerenin tamamı ıslak görünüyor. Yağmurluk, çamurluk ya da toplu taşıma."
        } else {
            verdict = "Belirsiz · \(Fmt.pct(pm))"
            detail = "Yağmur gelebilir; yağmurluğu çantaya koy."
        }
        return Leg(kind: kind, day: day, title: title, windowStart: wStart, windowEnd: wEnd, slots: slots, planned: planned, best: best,
                   rideMinutes: s.rideMinutes, rideSlots: rs, bestSlots: bs, feel: feel,
                   baseLayer: (feel ?? 99) < th.baseLayer, windproof: (feel ?? 99) < th.windproof,
                   hazards: hz, verdict: verdict, detail: detail)
    }

    static func hazards(_ rs: [Slot], kind: LegKind, depart: Date, ride: TimeInterval, sun: SunDay, feel: Double?) -> [Hazard] {
        var h: [Hazard] = []
        if rs.contains(where: { $0.temp <= 1.5 && ($0.precipMean > 0.01 || $0.humidity >= 92) }) {
            h.append(.init(level: .danger, text: "Buzlanma riski: köprü ve gölgede kayabilir", symbol: "snowflake"))
        }
        if rs.contains(where: { $0.code >= 95 }) {
            h.append(.init(level: .danger, text: "Gök gürültülü fırtına", symbol: "cloud.bolt.fill"))
        }
        if rs.contains(where: { $0.precipMax >= 1.0 && $0.prob >= 0.4 }) {
            h.append(.init(level: .danger, text: "Sağanak: görüş ve fren mesafesi düşer", symbol: "cloud.heavyrain.fill"))
        }
        let gust = rs.map(\.gust).max() ?? 0
        if gust >= 50 { h.append(.init(level: .danger, text: "Sert rüzgâr: hamle \(Int(gust)) km/sa", symbol: "wind")) }
        else if gust >= 38 { h.append(.init(level: .caution, text: "Rüzgârlı: hamle \(Int(gust)) km/sa", symbol: "wind")) }
        if let v = rs.compactMap(\.visibility).min(), v < 1000 {
            h.append(.init(level: .caution, text: "Sis: görüş \(Int(v)) m", symbol: "cloud.fog.fill"))
        }
        if let f = feel, f <= -3 { h.append(.init(level: .caution, text: "Dondurucu: el ve kulak koru", symbol: "thermometer.snowflake")) }
        if kind == .evening, let dusk = sun.dusk, depart.addingTimeInterval(ride) > dusk {
            h.append(.init(level: .caution, text: "Karanlıkta dönüş: ön ve arka ışık", symbol: "light.beacon.max.fill"))
        } else if kind == .evening, let sunset = sun.sunset, depart.addingTimeInterval(ride) > sunset {
            h.append(.init(level: .note, text: "Alacakaranlıkta varış: ışığı aç", symbol: "sunset.fill"))
        }
        if kind == .morning, let dawn = sun.dawn, depart < dawn {
            h.append(.init(level: .caution, text: "Karanlıkta gidiş: ön ve arka ışık", symbol: "light.beacon.max.fill"))
        }
        return h.sorted { $0.level > $1.level }
    }

    /// The next morning and evening that are still ahead (today, or tomorrow once today's window is over).
    static func nextDay(for kind: LegKind, s: Settings, now: Date = .now) -> Date {
        let end = kind == .morning ? s.morningEnd : s.eveningEnd
        let today = Calendar.current.startOfDay(for: now)
        return now < at(today, end) ? today : today.addingTimeInterval(86400 + 3600).startOfDay
    }
}

struct Lunch: Sendable {
    var start: Date?
    var minutes: Int
    var verdict: String
    var outdoor: Bool
    var slots: [Slot]
    var feels: Double?

    static func make(day: Date, f: Forecast, s: Settings) -> Lunch {
        let slots = f.slots(from: Decision.at(day, s.lunchStart), to: Decision.at(day, s.lunchEnd))
        var best = (start: nil as Date?, len: 0), cur = (start: nil as Date?, len: 0)
        for x in slots {
            let ok = x.prob < 0.3 && x.feels >= 2 && x.gust < 45 && x.code < 95
            if ok { cur = (cur.start ?? x.time, cur.len + 1); if cur.len > best.len { best = cur } } else { cur = (nil, 0) }
        }
        let m = best.len * 15
        let v: String = switch m {
        case 45...: "Uzun yürüyüş havası · \(m) dk"
        case 25..<45: "\(m) dk yürüyüş uygun"
        case 15..<25: "Kısa bir tur · \(m) dk"
        default: "İçeride kal · yakın bir yer"
        }
        let feels = slots.isEmpty ? nil : slots.map(\.feels).reduce(0, +) / Double(slots.count)
        return Lunch(start: best.start, minutes: m, verdict: v, outdoor: m >= 15, slots: slots, feels: feels)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
