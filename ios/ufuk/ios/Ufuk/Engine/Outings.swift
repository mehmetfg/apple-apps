// Dışarı Planı: the person's own places (the park nearby, Kavaklık Parkı, the market, the old
// neighbourhood) with a weekly target for each. Every day Ufuk orders them: what this week still lacks
// first, then whether the weather holds and the light lasts for the way there and back.
import CoreLocation
import Foundation

struct Spot: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var symbol: String
    var weeklyTarget: Int
    var lat: Double?
    var lon: Double?
    var radius: Double = 150         // metres: inside this the place counts as visited

    var coordinate: CLLocationCoordinate2D? { lat.flatMap { a in lon.map { .init(latitude: a, longitude: $0) } } }

    static let defaults: [Spot] = [
        Spot(name: "Yakındaki park", symbol: "tree.fill", weeklyTarget: 2),
        Spot(name: "Kavaklık Parkı", symbol: "leaf.fill", weeklyTarget: 1),
        Spot(name: "Çarşı", symbol: "basket.fill", weeklyTarget: 1),
        Spot(name: "Eski yerim", symbol: "house.lodge.fill", weeklyTarget: 1),
    ]
    static let symbols = ["tree.fill", "leaf.fill", "basket.fill", "house.lodge.fill", "cup.and.saucer.fill",
                          "water.waves", "building.columns.fill", "books.vertical.fill", "figure.walk", "mountain.2.fill"]
}

struct Visit: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var spot: UUID
    var date: Date
    var auto: Bool                   // found by location, not tapped
    var route: UUID?
}

struct OutingOption: Identifiable, Hashable, Sendable {
    var id: UUID { spot.id }
    var spot: Spot
    var done: Int                    // visits this week
    var meters: Double?
    var minutes: Int?                // one way
    var bike: Bool
    var lightLeft: Int?              // minutes until dark after getting back
    var rain: Double                 // highest chance from now until back home
    var visitedToday: Bool
    var score: Double
    var reason: String

    var progress: String { "\(done)/\(spot.weeklyTarget)" }
}

enum Outings {
    /// Weeks start on Monday, as the person counts them.
    static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; c.locale = Locale(identifier: "tr_TR"); return c }

    static func weekStart(_ d: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d.startOfDay }

    static func thisWeek(_ visits: [Visit], now: Date = .now) -> [Visit] {
        let s = weekStart(now); return visits.filter { $0.date >= s && $0.date <= now.addingTimeInterval(60) }
    }

    /// Orders the places for today. Remaining weekly need, spread over the days left, matters most;
    /// rain on the way and coming back in the dark pull a place down; a place already visited today sinks.
    static func rank(spots: [Spot], visits: [Visit], from: CLLocationCoordinate2D?, forecast: Forecast?, dusk: Date?,
                     rideSpeed: Double, now: Date = .now) -> [OutingOption] {
        let week = thisWeek(visits, now: now)
        let daysLeft = Double(max(1, 7 - (cal.dateComponents([.day], from: weekStart(now), to: now.startOfDay).day ?? 0)))
        return spots.map { sp -> OutingOption in
            let done = week.filter { $0.spot == sp.id }.count
            let today = week.contains { $0.spot == sp.id && Calendar.current.isDateInToday($0.date) }
            var meters: Double?, minutes: Int?, bike = false
            if let a = from, let b = sp.coordinate {
                let m = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) * 1.25
                meters = m
                bike = m > 2000
                minutes = Int((m / 1000 / (bike ? rideSpeed : 4.8) * 60).rounded(.up))
            }
            let stay = 45.0                                   // minutes at the place
            let back = now.addingTimeInterval(Double(2 * (minutes ?? 15)) * 60 + stay * 60)
            let rain = forecast?.slots(from: now, to: back).map(\.prob).max() ?? 0
            let light = dusk.map { Int($0.timeIntervalSince(back) / 60) }
            let need = Double(max(0, sp.weeklyTarget - done))
            var score = need / daysLeft * 2 + (need > 0 ? 0.6 : -0.6)
            score -= rain * 1.2
            if let l = light, l < 0 { score -= min(1, Double(-l) / 60) * 0.8 }
            if today { score -= 2 }
            score -= Double(done) / Double(max(1, sp.weeklyTarget)) * 0.3     // ties: the less visited place first
            if sp.coordinate == nil { score -= 0.2 }

            var bits: [String] = []
            if let m = meters, let mn = minutes {
                bits.append(Fmt.km(m))
                bits.append("\(mn) dk \(bike ? "bisiklet" : "yürüme")")
            } else if sp.coordinate == nil {
                bits.append("yeri işaretlenmedi")
            }
            if rain >= 0.4 { bits.append("yağış \(Fmt.pct(rain))") } else if forecast != nil { bits.append("kuru") }
            if let l = light { bits.append(l >= 0 ? "dönüşte \(Fmt.span(TimeInterval(l * 60))) ışık" : "dönüş karanlıkta") }
            return OutingOption(spot: sp, done: done, meters: meters, minutes: minutes, bike: bike, lightLeft: light, rain: rain,
                                visitedToday: today, score: score, reason: bits.joined(separator: " · "))
        }
        .sorted { $0.score > $1.score }
    }

    /// Places within their radius of any of the points.
    static func reached(_ spots: [Spot], along pts: [CLLocationCoordinate2D]) -> [Spot] {
        spots.filter { sp in
            guard let c = sp.coordinate else { return false }
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            return pts.contains { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= sp.radius }
        }
    }
}
