// The centre: settings, fetching, the decisions, the person's answers and everything that leaves the app
// (snapshot for the widget, notifications, Live Activity, PDM bus events).
import CoreLocation
import Foundation
import PDMBus
import SwiftUI
import WidgetKit

struct SavedPlace: Codable, Hashable, Sendable {
    var name: String
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    let bus = PDMBus(app: "ufuk")

    // MARK: settings
    @AppStorage("home") private var homeData = Data()
    @AppStorage("work") private var workData = Data()
    @AppStorage("morningDepart") var morningDepart = 7 * 60 + 30
    @AppStorage("eveningDepart") var eveningDepart = 17 * 60 + 30
    @AppStorage("rideMinutes") var rideMinutes = 30
    @AppStorage("rideSpeed") var rideSpeed = 18.0
    @AppStorage("lunchStart") var lunchStart = 12 * 60
    @AppStorage("lunchEnd") var lunchEnd = 13 * 60
    @AppStorage("notifyMorning") var notifyMorning = 6 * 60 + 30
    @AppStorage("notifyDusk") var notifyDusk = 15 * 60
    @AppStorage("notifySunrise") var notifySunrise = 21 * 60
    @AppStorage("askFeedback") var askFeedback = true
    @AppStorage("weekendRides") var weekendRides = false
    @AppStorage("emittedDays") private var emittedDays = ""

    var home: SavedPlace? {
        get { try? JSONDecoder().decode(SavedPlace.self, from: homeData) }
        set { homeData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }
    var work: SavedPlace? {
        get { try? JSONDecoder().decode(SavedPlace.self, from: workData) }
        set { workData = (try? JSONEncoder().encode(newValue)) ?? Data(); objectWillChange.send() }
    }

    var settings: Settings {
        var s = Settings()
        s.morningDepart = morningDepart; s.eveningDepart = eveningDepart
        s.rideMinutes = rideMinutes; s.rideSpeed = rideSpeed
        s.lunchStart = lunchStart; s.lunchEnd = lunchEnd
        return s
    }

    /// The commute forecast is taken halfway between home and work; models are 9–25 km grids anyway.
    var commutePoint: CLLocationCoordinate2D {
        switch (home, work) {
        case let (h?, w?): .init(latitude: (h.lat + w.lat) / 2, longitude: (h.lon + w.lon) / 2)
        case let (h?, nil): h.coordinate
        case let (nil, w?): w.coordinate
        default: Location.shared.last ?? .init(latitude: 41.0082, longitude: 28.9784)   // İstanbul until places are set
        }
    }

    // MARK: state
    @Published private(set) var forecast: Forecast?
    @Published private(set) var morning: Leg?
    @Published private(set) var evening: Leg?
    @Published private(set) var lunch: Lunch?
    @Published private(set) var sunToday = SunDay()
    @Published private(set) var sunTomorrow = SunDay()
    @Published private(set) var appleNow: AppleNow?
    @Published private(set) var appleStatus: AppleWeather.Status = .unknown
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var feedback: [RideFeedback] = []
    @Published private(set) var moods: [String: Int] = [:]
    @Published private(set) var records: [DayRecord] = []
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var waitingFindings = 0
    @Published private(set) var days: [DaySummary] = []
    @Published private(set) var wardrobe: [GarmentChange] = []
    @Published var spots: [Spot] = Spot.defaults
    @Published private(set) var visits: [Visit] = []
    @Published private(set) var routes: [RouteRecord] = []
    @Published var lunchPlaces: [PlaceOption] = []
    @Published var eveningPlaces: [PlaceOption] = []

    var thresholds: Thresholds { Clothing.learn(feedback) }

    private var folder: URL {
        let d = URL.applicationSupportDirectory.appending(path: "Ufuk", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private init() {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: folder.appending(path: "feedback.json")) { feedback = (try? dec.decode([RideFeedback].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: folder.appending(path: "moods.json")) { moods = (try? dec.decode([String: Int].self, from: d)) ?? [:] }
        if let d = try? Data(contentsOf: folder.appending(path: "wardrobe.json")) { wardrobe = (try? dec.decode([GarmentChange].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: folder.appending(path: "spots.json")), let v = try? dec.decode([Spot].self, from: d) { spots = v }
        if let d = try? Data(contentsOf: folder.appending(path: "visits.json")) { visits = (try? dec.decode([Visit].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: folder.appending(path: "routes.json")) { routes = (try? dec.decode([RouteRecord].self, from: d)) ?? [] }
        recomputeSun()
    }

    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = .prettyPrinted
        try? enc.encode(feedback).write(to: folder.appending(path: "feedback.json"), options: .atomic)
        try? enc.encode(moods).write(to: folder.appending(path: "moods.json"), options: .atomic)
        try? enc.encode(wardrobe).write(to: folder.appending(path: "wardrobe.json"), options: .atomic)
        try? enc.encode(spots).write(to: folder.appending(path: "spots.json"), options: .atomic)
        try? enc.encode(visits).write(to: folder.appending(path: "visits.json"), options: .atomic)
        try? enc.encode(routes).write(to: folder.appending(path: "routes.json"), options: .atomic)
    }

    private var routeFolder: URL {
        let d = folder.appending(path: "routes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let dayKey: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()

    func recomputeSun() {
        let p = commutePoint
        sunToday = Sun.day(.now, lat: p.latitude, lon: p.longitude)
        sunTomorrow = Sun.day(.now.addingTimeInterval(86400), lat: p.latitude, lon: p.longitude)
    }

    func sun(on day: Date) -> SunDay {
        let p = commutePoint
        return Sun.day(day, lat: p.latitude, lon: p.longitude)
    }

    // MARK: refresh

    /// Fetches the forecast (Open-Meteo + ensemble + WeatherKit) and rebuilds every decision.
    func refresh(background: Bool = false) async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        let p = commutePoint
        recomputeSun()
        do {
            async let det = OpenMeteo.forecast(lat: p.latitude, lon: p.longitude)
            async let apple = AppleWeather.fetch(lat: p.latitude, lon: p.longitude)
            async let daily = OpenMeteo.daily(lat: p.latitude, lon: p.longitude)
            var f = try await det
            if let d = try? await daily { days = d }
            let a = await apple
            appleStatus = a.status; appleNow = a.now
            if !a.hourly.isEmpty {
                for i in f.slots.indices {
                    let hour = Calendar.current.dateInterval(of: .hour, for: f.slots[i].time)?.start ?? f.slots[i].time
                    f.slots[i].appleProb = a.hourly[hour]
                    f.slots[i].prob = OpenMeteo.blend(f.slots[i])
                }
            }
            let previous = (morning, evening)
            forecast = f
            error = nil
            rebuild()
            await Notifier.checkChange(old: previous, new: (morning, evening), store: self)
        } catch {
            self.error = "Tahmin alınamadı: \(error.localizedDescription)"
        }
        writeSnapshot()
        await Notifier.schedule(self)
        await RideActivity.updateAll(self)
        emitDay()
        if !background { await bus.sync() }
    }

    func rebuild() {
        guard let f = forecast else { return }
        let s = settings, th = thresholds
        let md = Decision.nextDay(for: .morning, s: s), ed = Decision.nextDay(for: .evening, s: s)
        morning = Decision.leg(.morning, day: md, f: f, s: s, sun: sun(on: md), th: th)
        evening = Decision.leg(.evening, day: ed, f: f, s: s, sun: sun(on: ed), th: th)
        let ld = Date.now < Decision.at(.now, s.lunchEnd) ? Date.now.startOfDay : Date.now.addingTimeInterval(86400).startOfDay
        lunch = Lunch.make(day: ld, f: f, s: s)
    }

    func writeSnapshot() {
        let c = forecast?.current
        Snapshot(generated: .now, placeName: home?.name ?? "Konum", temperature: appleNow?.temperature ?? c?.temp,
                 weatherCode: c?.code, legs: [morning, evening].compactMap { $0?.summary() },
                 lunchMinutes: lunch?.minutes ?? 0, lunchVerdict: lunch?.verdict ?? "—",
                 today: sunToday, tomorrow: sunTomorrow, hours: nextHours(12),
                 outing: outings.first.map { "\($0.spot.name) · bu hafta \($0.progress)" },
                 nowProb: c?.prob, todayMax: todayRange?.max, todayMin: todayRange?.min, days: days).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: the next hours

    /// The next six hours from the start of this hour: highest rain chance, temperature, wind, weather, dark.
    var hours: [HourSummary] { nextHours(6) }

    /// The widget gets twelve so its six columns still fill hours after the last refresh.
    func nextHours(_ n: Int) -> [HourSummary] {
        guard let f = forecast else { return [] }
        let p = commutePoint
        let h0 = Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
        return (0..<n).compactMap { i -> HourSummary? in
            let a = h0.addingTimeInterval(Double(i) * 3600)
            let ss = f.slots(from: a, to: a.addingTimeInterval(3600))
            guard let first = ss.first else { return nil }
            let code = ss.map(\.code).max() ?? first.code
            return HourSummary(time: a, prob: ss.map(\.prob).max() ?? 0, temp: first.temp, wind: ss.map(\.wind).max() ?? first.wind,
                               code: code, dark: Sun.elevation(a.addingTimeInterval(1800), lat: p.latitude, lon: p.longitude) < -6)
        }
    }

    /// Today's high and low: the daily forecast first, the 15-minute slots of today otherwise.
    var todayRange: (min: Double, max: Double)? {
        if let d = days.first(where: { Calendar.current.isDateInToday($0.day) }) { return (d.tMin, d.tMax) }
        let t = forecast?.slots(from: Date.now.startOfDay, to: Date.now.startOfDay.addingTimeInterval(86400)).map(\.temp) ?? []
        guard let lo = t.min(), let hi = t.max() else { return nil }
        return (lo, hi)
    }

    /// The next leg that has not ended: the departure the screen and the widget put first.
    var nextLeg: Leg? { [morning, evening].compactMap { $0 }.filter { $0.windowEnd > .now }.min { $0.windowStart < $1.windowStart } }

    // MARK: Giyim Defteri

    var currentGarment: Garment? { wardrobe.max { $0.date < $1.date }?.to }

    /// Lowest apparent temperature between 07 and 19 in the forecast days ahead (today excluded after 19:00).
    var coldestFeelAhead: Double? {
        forecast?.slots.filter { $0.time > .now && (7..<19).contains(Calendar.current.component(.hour, from: $0.time)) }.map(\.feels).min()
    }

    var wardrobeHint: WardrobeHint? { Wardrobe.hint(wardrobe, coldestFeelAhead: coldestFeelAhead) }

    func recordGarment(_ g: Garment, date: Date = .now, note: String? = nil) {
        let before = wardrobe.filter { $0.date < date }.max { $0.date < $1.date }?.to
        guard before != g else { return }
        let slot = forecast?.slot(at: date)
        let day = forecast?.slots(from: date.startOfDay, to: date.startOfDay.addingTimeInterval(86400)) ?? []
        let c = GarmentChange(date: date, from: before, to: g, temp: (abs(date.timeIntervalSinceNow) < 3600 ? appleNow?.temperature : nil) ?? slot?.temp, feels: slot?.feels, wind: slot?.wind,
                              tMin: day.map(\.temp).min(), tMax: day.map(\.temp).max(), daylightMin: Int(sun(on: date).daylight / 60), note: note)
        wardrobe.append(c); wardrobe.sort { $0.date < $1.date }
        persist()
        var data: [String: PDMValue] = ["to": .string(String(describing: g)), "daylight_min": .int(c.daylightMin)]
        if let b = before { data["from"] = .string(String(describing: b)) }
        if let t = c.temp { data["temp"] = .double((t * 10).rounded() / 10) }
        if let f = c.feels { data["feels"] = .double((f * 10).rounded() / 10) }
        if let w = c.wind { data["wind"] = .double((w * 10).rounded() / 10) }
        if let lo = c.tMin, let hi = c.tMax { data["t_min"] = .double((lo * 10).rounded() / 10); data["t_max"] = .double((hi * 10).rounded() / 10) }
        bus.emit("clothing.changed", subject: "day:\(Self.dayKey.string(from: date))", data: data)
    }

    func removeGarment(_ c: GarmentChange) { wardrobe.removeAll { $0.id == c.id }; persist() }

    // MARK: Dışarı Planı

    var outings: [OutingOption] {
        Outings.rank(spots: spots, visits: visits, from: Location.shared.last ?? home?.coordinate, forecast: forecast,
                     dusk: sunToday.dusk, rideSpeed: rideSpeed)
    }

    var weekVisits: [Visit] { Outings.thisWeek(visits) }
    var weekKm: Double { routes.filter { $0.start >= Outings.weekStart(.now) }.map(\.km).reduce(0, +) }

    func saveSpots(_ v: [Spot]) { spots = v; persist(); writeSnapshot() }

    func markVisit(_ sp: Spot, auto: Bool = false, route: UUID? = nil, date: Date = .now) {
        // one visit per place per day
        guard !visits.contains(where: { $0.spot == sp.id && Calendar.current.isDate($0.date, inSameDayAs: date) }) else { return }
        visits.append(Visit(spot: sp.id, date: date, auto: auto, route: route))
        persist()
        bus.emit("place.visited", subject: "place:\(sp.name)", data: ["auto": .bool(auto), "weekly_target": .int(sp.weeklyTarget)])
        writeSnapshot()
    }

    func removeVisit(_ v: Visit) { visits.removeAll { $0.id == v.id }; persist(); writeSnapshot() }

    /// On opening the app: if the person is standing at one of their places, it counts.
    func checkArrival() {
        guard let here = Location.shared.last else { return }
        for sp in Outings.reached(spots, along: [here]) { markVisit(sp, auto: true) }
    }

    func finishRoute() {
        guard var r = RouteRecorder.shared.stop() else { return }
        let passed = Outings.reached(spots, along: r.points.map { .init(latitude: $0.lat, longitude: $0.lon) })
        r.spots = passed.map(\.name)
        let mid = forecast?.slot(at: r.start.addingTimeInterval(r.end.timeIntervalSince(r.start) / 2))
        r.temp = mid?.temp; r.rain = mid?.prob; r.code = mid?.code
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(r).write(to: routeFolder.appending(path: "\(r.id.uuidString).json"), options: .atomic)
        var index = r; index.points = []
        routes.insert(index, at: 0)
        for sp in passed { markVisit(sp, auto: true, route: r.id, date: r.end) }
        persist()
        bus.emit("route.recorded", subject: "route:\(r.id.uuidString)", data: [
            "km": .double((r.km * 100).rounded() / 100), "minutes": .int(r.minutes), "mode": .string(r.mode),
            "places": .string(r.spots.joined(separator: ", ")), "start": .string(ISO8601DateFormatter().string(from: r.start)),
        ])
    }

    func routePoints(_ r: RouteRecord) -> [RoutePoint] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let d = try? Data(contentsOf: routeFolder.appending(path: "\(r.id.uuidString).json")) else { return [] }
        return (try? dec.decode(RouteRecord.self, from: d))?.points ?? []
    }

    func removeRoute(_ r: RouteRecord) {
        routes.removeAll { $0.id == r.id }
        try? FileManager.default.removeItem(at: routeFolder.appending(path: "\(r.id.uuidString).json"))
        persist()
    }

    // MARK: places

    func loadPlaces() async {
        if let w = work?.coordinate ?? home?.coordinate, let l = lunch {
            lunchPlaces = await Places.lunch(work: w, minutes: l.minutes, outdoor: l.outdoor)
        }
        let start = work?.coordinate ?? home?.coordinate ?? commutePoint
        let depart = Decision.at(.now, eveningDepart)
        let from = max(depart, .now)
        let light = Int(((sunToday.dusk ?? from).timeIntervalSince(from)) / 60)
        let mid = forecast?.slot(at: from)
        eveningPlaces = await Places.evening(from: start, lightMinutes: max(light, 0), speed: rideSpeed,
                                             windFrom: mid?.windDir, wind: mid?.wind ?? 0)
    }

    // MARK: the person's answers

    func addFeedback(_ feel: Feel, leg kind: LegKind, baseLayer: Bool?, mood: Int? = nil, date: Date = .now) {
        let l = kind == .morning ? morning : evening
        let mid = l?.rideSlots.isEmpty == false ? l!.rideSlots[l!.rideSlots.count / 2] : forecast?.slot(at: date)
        let wet = l?.rideSlots.contains { $0.prob >= 0.5 && $0.precipMean >= 0.05 } ?? false
        let rf = l?.feel ?? mid.map { Clothing.rideFeel(temp: $0.temp, wind: $0.wind, speed: rideSpeed, wet: wet) } ?? 10
        let fb = RideFeedback(date: date, leg: kind, feel: feel, baseLayer: baseLayer ?? (l?.baseLayer ?? false), rideFeel: rf,
                              temp: mid?.temp ?? rf, wind: mid?.wind ?? 0, wet: wet, mood: mood)
        feedback.append(fb)
        if let mood { moods[Self.dayKey.string(from: date)] = mood }
        persist()
        bus.emit("ride.feedback", subject: "leg:\(kind.rawValue)", data: [
            "feel": .string(feel.rawValue), "base_layer": .bool(fb.baseLayer), "ride_feel": .double((rf * 10).rounded() / 10),
            "temp": .double((fb.temp * 10).rounded() / 10), "wind": .double((fb.wind * 10).rounded() / 10), "wet": .bool(wet),
        ])
        rebuild(); writeSnapshot()
    }

    func removeFeedback(_ fb: RideFeedback) {
        feedback.removeAll { $0.id == fb.id }; persist(); rebuild(); writeSnapshot()
    }

    func setMood(_ m: Int, day: Date = .now) {
        moods[Self.dayKey.string(from: day)] = m
        persist()
        bus.emit("mood.logged", subject: "day:\(Self.dayKey.string(from: day))", data: ["mood": .int(m)])
        Task { await loadInsights() }
    }

    func mood(on day: Date) -> Int? { moods[Self.dayKey.string(from: day)] }

    // MARK: weather and behaviour

    @AppStorage("insightsAt") private var insightsAt = 0.0

    @AppStorage("healthAsked") private var healthAsked = false

    func loadInsights(force: Bool = false) async {
        if !healthAsked { healthAsked = true; await HealthReader.shared.requestAccess() }
        let p = commutePoint
        async let past = OpenMeteo.past(lat: p.latitude, lon: p.longitude)
        async let health = HealthReader.shared.days()
        let pd = (try? await past) ?? []
        let hd = await health
        let prod = Production.minutesByDay()
        let rideDays = Dictionary(grouping: feedback, by: { $0.date.startOfDay }).mapValues(\.count)
        records = pd.filter { $0.day < Date.now.startOfDay }.map { w in
            DayRecord(day: w.day, weather: w, health: hd[w.day], mood: mood(on: w.day), productionMin: prod[w.day], rides: rideDays[w.day] ?? 0)
        }.sorted { $0.day > $1.day }
        let r = Insights.findings(records)
        findings = r.found; waitingFindings = r.waiting
        insightsAt = Date.now.timeIntervalSince1970
    }

    /// One `weather.day` event per day for the hub, written the first time the app sees that day's morning forecast.
    private func emitDay() {
        guard let m = morning, let e = evening, let f = forecast else { return }
        let key = Self.dayKey.string(from: .now)
        guard !emittedDays.split(separator: ",").contains(Substring(key)), Calendar.current.isDateInToday(m.day) || Calendar.current.isDateInToday(e.day) else { return }
        let today = f.slots(from: Date.now.startOfDay, to: Date.now.startOfDay.addingTimeInterval(86400))
        bus.emit("weather.day", subject: "day:\(key)", data: [
            "rain_mm": .double((today.map(\.precipMean).reduce(0, +) * 10).rounded() / 10),
            "t_min": .double(today.map(\.temp).min() ?? 0), "t_max": .double(today.map(\.temp).max() ?? 0),
            "morning_rain": .double((m.windowMax * 100).rounded() / 100), "evening_rain": .double((e.windowMax * 100).rounded() / 100),
            "base_layer": .bool(m.baseLayer), "daylight_min": .int(Int(sunToday.daylight / 60)),
            "dusk": .string(Fmt.t(sunToday.dusk)),
        ])
        emittedDays = (emittedDays.split(separator: ",").suffix(30).map(String.init) + [key]).joined(separator: ",")
    }
}

/// Production minutes from Tekne's events in the vault (`_bus/events/tekne/*.jsonl`), when the vault is selected.
enum Production {
    static func minutesByDay() -> [Date: Double] {
        guard let root = PDMVault.resolve() else { return [:] }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let dir = root.appending(path: "_bus/events/tekne", directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        let iso = ISO8601DateFormatter()
        var out: [Date: Double] = [:]
        for f in files where f.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      (o["type"] as? String) == "production.session", let d = o["data"] as? [String: Any],
                      let m = (d["minutes"] as? NSNumber)?.doubleValue,
                      let s = (d["start"] as? String).flatMap(iso.date(from:)) else { continue }
                out[s.startOfDay, default: 0] += m
            }
        }
        return out
    }
}

/// When-in-use location: only to centre the map and as a fallback before home and work are set.
@MainActor
final class Location: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Location()
    private let m = CLLocationManager()
    @Published private(set) var last: CLLocationCoordinate2D?

    override init() { super.init(); m.delegate = self; m.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() { m.requestWhenInUseAuthorization(); m.requestLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        Task { @MainActor in self.last = c; Store.shared.checkArrival() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
}
