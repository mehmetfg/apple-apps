// Yolda: a ride or a walk recorded while listening. The route comes from GPS, the climb from the barometer, the steps
// from the pedometer; calories from body weight, speed and slope. It runs as long as the bicycle or walking mode is
// on, also with the phone locked in a pocket (background location + the reader's audio), and is written every
// half minute so a closed app loses at most that much. Files: Application Support/VoiceReader/workouts/<id>.json,
// copied to the vault (durum/Workouts/) for the Mac.
import Foundation
import CoreLocation
import CoreMotion
import UIKit

enum MoveKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bike, walk
    var id: String { rawValue }
    var name: String { self == .bike ? "Bisiklet" : "Yürüyüş" }
    var symbol: String { self == .bike ? "bicycle" : "figure.walk" }
}

struct Workout: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: MoveKind
    var start = Date()
    var end: Date?
    var lastAt = Date()                 // the last moment recorded (an unfinished one is resumed if recent)
    var distance: Double = 0            // metres
    var moving: Double = 0              // seconds in motion
    var climb: Double = 0               // metres up
    var descent: Double = 0             // metres down
    var steps = 0
    var calories: Double = 0            // kcal
    var maxSpeed: Double = 0            // km/h
    var weight: Double = 0              // kg used for the calories
    var route: [[Double]] = []          // [latitude, longitude, altitude, seconds since start]
    var documents: [UUID] = []          // books listened to on the way

    var duration: Double { (end ?? lastAt).timeIntervalSince(start) }
    var averageSpeed: Double { moving > 0 ? distance / moving * 3.6 : 0 }
}

@MainActor
@Observable
final class WorkoutRecorder: NSObject, CLLocationManagerDelegate {
    private(set) var current: Workout?
    private(set) var speed: Double = 0          // km/h now, smoothed
    private(set) var grade: Double = 0          // slope now (0.05 = 5 %)
    private(set) var status = ""
    private(set) var history: [Workout] = []

    @ObservationIgnored var weight: () -> Double = { 0 }
    @ObservationIgnored var nowListening: () -> UUID? = { nil }
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let altimeter = CMAltimeter()
    @ObservationIgnored private var last: CLLocation?
    @ObservationIgnored private var lastAltitude: Double?          // barometric, metres relative to the start
    @ObservationIgnored private var stepsBefore = 0                 // steps of the earlier part of a resumed walk
    @ObservationIgnored private var savedAt = Date.distantPast
    @ObservationIgnored private var gradeWindow: [(d: Double, h: Double)] = []

    private var folder: URL {
        let d = URL.applicationSupportDirectory.appending(path: "VoiceReader/workouts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        loadHistory()
    }

    // MARK: starting and ending

    /// Starts recording, or goes on with the last one of the same kind if it stopped less than half an hour ago
    /// (the app was closed on the way).
    func start(_ kind: MoveKind) {
        if let c = current, c.kind == kind { return }
        if current != nil { finish() }
        if let open = history.first(where: { $0.end == nil && $0.kind == kind }), Date.now.timeIntervalSince(open.lastAt) < 1800 {
            current = open
            stepsBefore = open.steps
        } else {
            for i in history.indices where history[i].end == nil { history[i].end = history[i].lastAt; save(history[i]) }
            current = Workout(kind: kind, weight: weight())
            stepsBefore = 0
        }
        last = nil; lastAltitude = nil; gradeWindow = []
        UIDevice.current.isBatteryMonitoringEnabled = true
        startLocation()
        startMotion()
    }

    /// Ends the recording. A very short one (under a minute and 50 m) is not kept.
    func finish() {
        guard var w = current else { return }
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        w.end = .now
        w.lastAt = .now
        current = nil
        speed = 0; grade = 0
        if w.duration < 60 && w.distance < 50 {
            try? FileManager.default.removeItem(at: url(w.id))
            history.removeAll { $0.id == w.id }
            return
        }
        save(w)
    }

    private func startLocation() {
        switch manager.authorizationStatus {
        case .notDetermined: status = "Konum izni bekleniyor"; manager.requestWhenInUseAuthorization()
        case .denied, .restricted: status = "Konum izni yok: Ayarlar › Wise Path › Konum"
        default:
            status = "Konum aranıyor…"
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
        }
    }

    private func startMotion() {
        if CMPedometer.isStepCountingAvailable(), let w = current {
            // a resumed walk counts on from where it was: only steps after now are added
            let from = w.steps > 0 ? Date.now : w.start
            pedometer.startUpdates(from: from) { [weak self] data, _ in
                guard let n = data?.numberOfSteps.intValue else { return }
                Task { @MainActor in
                    guard let self, self.current != nil else { return }
                    self.current?.steps = self.stepsBefore + n
                }
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let h = data?.relativeAltitude.doubleValue else { return }
                MainActor.assumeIsolated { self?.altitude(h) }
            }
        }
    }

    // MARK: measuring

    /// Barometric height: climb and descent count steps of at least a metre (the sensor's noise stays out).
    private func altitude(_ h: Double) {
        guard current != nil else { return }
        guard let a = lastAltitude else { lastAltitude = h; return }
        let d = h - a
        if d >= 1 { current?.climb += d; lastAltitude = h } else if d <= -1 { current?.descent -= d; lastAltitude = h }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        MainActor.assumeIsolated {
            guard current != nil else { return }
            switch m.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: startLocation()
            case .denied, .restricted: status = "Konum izni yok: Ayarlar › Wise Path › Konum"
            default: break
            }
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { for l in locations { take(l) } }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { status = "Konum alınamadı, yeniden deneniyor…" }
    }

    /// One GPS fix: a poor one or a jump faster than a car is left out; the rest adds distance, time in motion,
    /// slope and calories, and every fourth second or so a point of the route.
    func take(_ l: CLLocation) {
        guard var w = current, l.horizontalAccuracy >= 0, l.horizontalAccuracy <= 30 else { return }
        status = "GPS · ±\(Int(l.horizontalAccuracy)) m"
        var kmh = max(0, l.speed) * 3.6
        // no speed in the fix (it happens with a weak signal): from the way since the last one
        if l.speed < 0, let p = last, l.timestamp > p.timestamp {
            kmh = l.distance(from: p) / l.timestamp.timeIntervalSince(p.timestamp) * 3.6
            if kmh > 90 { kmh = 0 }
        }
        speed = speed * 0.4 + kmh * 0.6
        defer { current = w; saveSoon() }
        w.lastAt = l.timestamp
        if let id = nowListening(), !w.documents.contains(id) { w.documents.append(id) }
        guard let p = last else {
            last = l
            w.route.append(point(l, w))
            return
        }
        let d = l.distance(from: p)
        let dt = l.timestamp.timeIntervalSince(p.timestamp)
        guard dt > 0 else { return }
        if d / dt * 3.6 > 90 { return }                                     // a jump, not a movement
        let movingNow = d / dt * 3.6 > (w.kind == .bike ? 3 : 1.5)
        if d < 3 && !movingNow { return }
        last = l
        w.distance += d
        if movingNow {
            w.moving += min(dt, 30)
            w.maxSpeed = max(w.maxSpeed, min(kmh, 80))
        }
        // slope over the last ~60 m, from the GPS height (the barometer gives the climb, this only the gradient)
        gradeWindow.append((d, l.altitude)); var sum = 0.0
        while gradeWindow.count > 2, gradeWindow.dropFirst().reduce(0, { $0 + $1.d }) > 60 { gradeWindow.removeFirst() }
        sum = gradeWindow.dropFirst().reduce(0) { $0 + $1.d }
        if sum > 20, l.verticalAccuracy >= 0, let first = gradeWindow.first {
            grade = max(-0.25, min(0.25, (l.altitude - first.h) / sum))
        }
        if movingNow { w.calories += Self.calories(kind: w.kind, metres: d, seconds: min(dt, 30), grade: grade, kg: w.weight > 0 ? w.weight : 75) }
        if let t = w.route.last?[3], l.timestamp.timeIntervalSince(w.start) - t >= 4 { w.route.append(point(l, w)) }
    }

    private func point(_ l: CLLocation, _ w: Workout) -> [Double] {
        [(l.coordinate.latitude * 1e6).rounded() / 1e6, (l.coordinate.longitude * 1e6).rounded() / 1e6,
         l.altitude.rounded(), l.timestamp.timeIntervalSince(w.start).rounded()]
    }

    /// kcal for one stretch. Walking: ACSM's equation (oxygen = 3.5 + 0.1·v + 1.8·v·grade ml/kg/min, v in m/min,
    /// 5 kcal a litre). Cycling: the Compendium's MET for the speed, plus the climb's work at 25 % efficiency.
    nonisolated static func calories(kind: MoveKind, metres: Double, seconds: Double, grade: Double, kg: Double) -> Double {
        let minutes = seconds / 60
        switch kind {
        case .walk:
            let v = metres / minutes
            let vo2 = 3.5 + 0.1 * v + 1.8 * v * max(0, grade)
            return vo2 * kg / 1000 * 5 * minutes
        case .bike:
            let kmh = metres / seconds * 3.6
            let met: Double = kmh < 16 ? 4 : kmh < 19 ? 6.8 : kmh < 22 ? 8 : kmh < 25 ? 10 : 12
            let climbWork = max(0, grade) * metres * (kg + 12) * 9.81 / 4184 / 0.25     // rider + ~12 kg bicycle
            return met * kg * minutes / 60 + climbWork
        }
    }

    // MARK: saving

    private func url(_ id: UUID) -> URL { folder.appending(path: "\(id.uuidString).json") }

    private func saveSoon() {
        guard let w = current, Date.now.timeIntervalSince(savedAt) >= 30 else { return }
        save(w)
    }

    func save(_ w: Workout) {
        savedAt = .now
        if let i = history.firstIndex(where: { $0.id == w.id }) { history[i] = w } else { history.insert(w, at: 0) }
        guard let data = try? JSONEncoder().encode(w) else { return }
        try? data.write(to: url(w.id), options: .atomic)
        Task.detached { await VaultMirror.shared.writeWorkout(data, id: w.id) }
    }

    func saveNow() { if let w = current { save(w) } }

    private func loadHistory() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        history = files.compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(Workout.self, from: $0) } }
            .sorted { $0.start > $1.start }
    }
}
