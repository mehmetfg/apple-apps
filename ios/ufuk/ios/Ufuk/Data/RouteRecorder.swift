// Rota kaydı: start, go, stop. GPS keeps running with the screen locked (background location + a
// background activity session); points closer than 10 m are skipped. When it stops, the route is
// saved with the weather of that hour and every own place it passed counts as visited.
import CoreLocation
import Foundation

struct RoutePoint: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var t: Date
    var alt: Double?
}

struct RouteRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var start: Date
    var end: Date
    var km: Double
    var mode: String                 // "walk" / "bike", guessed from the average speed
    var spots: [String]              // names of own places passed
    var temp: Double?
    var rain: Double?
    var code: Int?
    var points: [RoutePoint] = []    // empty in the index; full in routes/<id>.json

    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    var title: String { spots.isEmpty ? (mode == "bike" ? "Bisiklet turu" : "Yürüyüş") : spots.joined(separator: " · ") }
}

@MainActor
final class RouteRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = RouteRecorder()
    private let m = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    @Published private(set) var recording = false
    @Published private(set) var started: Date?
    @Published private(set) var points: [RoutePoint] = []
    @Published private(set) var km = 0.0
    @Published var denied = false

    override init() {
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
        m.distanceFilter = 10
        m.activityType = .fitness
        m.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !recording else { return }
        let st = m.authorizationStatus
        if st == .denied || st == .restricted { denied = true; return }
        if st == .notDetermined { m.requestWhenInUseAuthorization() }
        points = []; km = 0; started = .now; recording = true
        session = CLBackgroundActivitySession()
        m.allowsBackgroundLocationUpdates = true
        m.showsBackgroundLocationIndicator = true
        m.startUpdatingLocation()
    }

    /// Stops and hands back what was recorded; nil when it was too short to keep (under 50 m or 1 minute).
    func stop() -> RouteRecord? {
        guard recording, let s = started else { return nil }
        m.stopUpdatingLocation()
        m.allowsBackgroundLocationUpdates = false
        session?.invalidate(); session = nil
        recording = false; started = nil
        let end = Date.now
        guard km >= 0.05, end.timeIntervalSince(s) >= 60 else { return nil }
        let kmh = km / max(end.timeIntervalSince(s) / 3600, 0.01)
        return RouteRecord(start: s, end: end, km: km, mode: kmh > 9 ? "bike" : "walk", spots: [], points: points)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 40 }
        Task { @MainActor in
            for l in good {
                if let last = self.points.last {
                    let d = CLLocation(latitude: last.lat, longitude: last.lon).distance(from: l)
                    guard d >= 8 else { continue }
                    self.km += d / 1000
                }
                self.points.append(RoutePoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude, t: l.timestamp,
                                              alt: l.verticalAccuracy >= 0 ? l.altitude : nil))
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in self.denied = st == .denied || st == .restricted }
    }
}
