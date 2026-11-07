// Places for the lunch walk and the evening ride, found with Apple Maps around the saved points.
// Evening places are ranked by the wind: ride out into it while fresh, come home with it behind you.
import CoreLocation
import Foundation
import MapKit

struct PlaceOption: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(lat)|\(lon)" }
    var name: String
    var kind: String
    var symbol: String
    var lat: Double
    var lon: Double
    var meters: Double
    var bearing: Double             // degrees from the start point
    var minutes: Int                // walking or riding, one way
    var windNote: String?
    var score: Double
}

enum Places {
    static func label(_ c: MKPointOfInterestCategory?) -> (String, String) {
        switch c {
        case .park?, .nationalPark?: ("Park", "tree.fill")
        case .beach?: ("Sahil", "beach.umbrella.fill")
        case .marina?: ("Marina", "sailboat.fill")
        case .cafe?: ("Kafe", "cup.and.saucer.fill")
        case .bakery?: ("Fırın", "birthday.cake.fill")
        case .museum?: ("Müze", "building.columns.fill")
        case .library?: ("Kütüphane", "books.vertical.fill")
        case .store?: ("Dükkân", "bag.fill")
        default: ("Yer", "mappin")
        }
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180, Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compass(_ deg: Double) -> String {
        let n = ["kuzey", "kuzeydoğu", "doğu", "güneydoğu", "güney", "güneybatı", "batı", "kuzeybatı"]
        return n[Int(((deg + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }

    static func search(center: CLLocationCoordinate2D, radius: Double, categories: [MKPointOfInterestCategory]) async -> [MKMapItem] {
        let r = MKLocalPointsOfInterestRequest(center: center, radius: max(200, min(radius, 15_000)))
        r.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        return (try? await MKLocalSearch(request: r).start().mapItems) ?? []
    }

    /// Lunch: outdoors when the window is dry (park, sea, marina), indoors otherwise (café, museum, library).
    static func lunch(work: CLLocationCoordinate2D, minutes: Int, outdoor: Bool) async -> [PlaceOption] {
        let walk = 80.0                                    // m per minute
        let radius = outdoor ? Double(max(minutes, 20)) / 2 * walk : 700
        let cats: [MKPointOfInterestCategory] = outdoor ? [.park, .beach, .marina, .nationalPark, .museum] : [.cafe, .bakery, .museum, .library]
        let items = await search(center: work, radius: radius, categories: cats)
        let start = CLLocation(latitude: work.latitude, longitude: work.longitude)
        return items.compactMap { i -> PlaceOption? in
            guard let c = i.placemark.location?.coordinate else { return nil }
            let m = start.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            let (k, sym) = label(i.pointOfInterestCategory)
            let mins = Int((m / walk).rounded(.up))
            let fit = outdoor ? (Double(minutes) - 2 * Double(mins)) : -Double(mins)
            return PlaceOption(name: i.name ?? k, kind: k, symbol: sym, lat: c.latitude, lon: c.longitude, meters: m,
                               bearing: bearing(work, c), minutes: mins, windNote: nil, score: fit)
        }
        .filter { !outdoor || $0.minutes * 2 <= max(minutes, 20) + 5 }
        .sorted { $0.score > $1.score }
        .prefix(8).map { $0 }
    }

    /// Evening: places reachable before dark, best first when the way out faces the wind.
    static func evening(from start: CLLocationCoordinate2D, lightMinutes: Int, speed: Double, windFrom: Double?, wind: Double) async -> [PlaceOption] {
        let usable = max(20, min(lightMinutes, 120))
        let reachKm = Double(usable) / 2 / 60 * speed
        let items = await search(center: start, radius: reachKm * 1000, categories: [.park, .beach, .marina, .nationalPark])
        let s = CLLocation(latitude: start.latitude, longitude: start.longitude)
        return items.compactMap { i -> PlaceOption? in
            guard let c = i.placemark.location?.coordinate else { return nil }
            let m = s.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            guard m > 600 else { return nil }
            let b = bearing(start, c)
            let (k, sym) = label(i.pointOfInterestCategory)
            let mins = Int((m * 1.25 / 1000 / speed * 60).rounded(.up))      // roads are ~25% longer than the line
            var note: String?, windScore = 0.0
            if let w = windFrom, wind >= 8 {
                let into = cos((b - w) * .pi / 180)                            // 1: the way out is straight into the wind
                windScore = into * min(1, wind / 25)
                note = into > 0.5 ? "Gidiş rüzgâra karşı, dönüş rahat" : (into < -0.5 ? "Dönüşte rüzgâr karşında" : "Rüzgâr yandan")
            }
            let timeFit = mins * 2 <= usable ? 1.0 : -1.0
            return PlaceOption(name: i.name ?? k, kind: k, symbol: sym, lat: c.latitude, lon: c.longitude, meters: m,
                               bearing: b, minutes: mins, windNote: note, score: timeFit + windScore + min(1, m / 4000) * 0.3)
        }
        .sorted { $0.score > $1.score }
        .prefix(8).map { $0 }
    }
}
