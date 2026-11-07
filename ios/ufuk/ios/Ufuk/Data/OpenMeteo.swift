// Open-Meteo: three deterministic models in 15-minute steps, the multi-model ensemble (≈120 members)
// for hourly rain probability, and the past days for the weather-and-behaviour view. No key needed.
import Foundation

/// One 15-minute slot after the sources are merged.
struct Slot: Hashable, Sendable {
    var time: Date
    var precipMean: Double         // mm in 15 minutes, mean of the models
    var precipMax: Double
    var modelAgree: Double         // 0…1, how many models see measurable rain
    var ensembleProb: Double?      // 0…1, share of ensemble members with rain in that hour
    var appleProb: Double?         // WeatherKit hourly chance
    var prob: Double               // the blend Ufuk uses
    var temp: Double
    var feels: Double
    var wind: Double               // km/h
    var gust: Double
    var humidity: Double
    var code: Int
    var visibility: Double?        // m
    var windDir: Double?           // degrees, where the wind comes from
    var cloud: Double?             // %

    /// High when the sources say the same thing.
    var confidence: Double {
        var probs = [modelAgree]
        if let e = ensembleProb { probs.append(e) }
        if let a = appleProb { probs.append(a) }
        let spread = (probs.max() ?? 0) - (probs.min() ?? 0)
        return max(0, 1 - spread * 1.4)
    }
}

struct Forecast: Sendable {
    var fetched: Date
    var lat: Double
    var lon: Double
    var slots: [Slot]
    var models: [String]
    var members: Int

    func slots(from a: Date, to b: Date) -> [Slot] { slots.filter { $0.time >= a && $0.time < b } }
    func slot(at d: Date) -> Slot? { slots.last { $0.time <= d } }
    var current: Slot? { slot(at: .now) }
}

struct PastDay: Codable, Hashable, Sendable {
    var day: Date                  // local midnight
    var rainMM: Double
    var tMax: Double
    var tMin: Double
    var sunshineH: Double
    var daylightH: Double
    var windMax: Double
    var cloud: Double
}

enum OpenMeteo {
    static let models = ["ecmwf_ifs025", "icon_seamless", "gfs_seamless"]
    static let modelNames = ["ecmwf_ifs025": "ECMWF", "icon_seamless": "ICON", "gfs_seamless": "GFS"]
    private static let vars15 = ["precipitation", "temperature_2m", "apparent_temperature", "wind_speed_10m",
                                 "wind_gusts_10m", "relative_humidity_2m", "weather_code", "visibility"]

    enum Failure: Error { case bad(String) }

    private static func json(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url); req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.bad(String(data: data, encoding: .utf8)?.prefix(200).description ?? "boş yanıt")
        }
        return obj
    }

    private static func nums(_ any: Any?) -> [Double?] {
        (any as? [Any])?.map { ($0 as? NSNumber)?.doubleValue } ?? []
    }

    static func forecast(lat: Double, lon: Double) async throws -> Forecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "minutely_15", value: vars15.joined(separator: ",")),
            .init(name: "hourly", value: "wind_direction_10m,cloud_cover"),
            .init(name: "models", value: models.joined(separator: ",")),
            .init(name: "forecast_days", value: "3"), .init(name: "past_days", value: "1"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "timezone", value: "auto"),
        ]
        async let detReq = json(c.url!)
        async let ensReq = ensemble(lat: lat, lon: lon)
        let det = try await detReq
        let ens = (try? await ensReq) ?? ([:], 0)

        guard let m = det["minutely_15"] as? [String: Any], let h = det["hourly"] as? [String: Any] else {
            throw Failure.bad("minutely_15 yok")
        }
        let times = nums(m["time"]).map { Date(timeIntervalSince1970: $0 ?? 0) }
        let hTimes = nums(h["time"]).map { Date(timeIntervalSince1970: $0 ?? 0) }
        func series(_ v: String) -> [[Double?]] { models.map { nums(m["\(v)_\($0)"]) } }
        func hourly(_ v: String) -> [Date: Double] {
            var out: [Date: Double] = [:]
            let cols = models.map { nums(h["\(v)_\($0)"]) }
            for (i, t) in hTimes.enumerated() {
                let vals = cols.compactMap { $0.indices.contains(i) ? $0[i] : nil }
                if !vals.isEmpty { out[t] = vals.reduce(0, +) / Double(vals.count) }
            }
            return out
        }
        let p = series("precipitation"), te = series("temperature_2m"), fe = series("apparent_temperature")
        let wi = series("wind_speed_10m"), gu = series("wind_gusts_10m"), hu = series("relative_humidity_2m")
        let co = series("weather_code"), vi = series("visibility")
        let dir = hourly("wind_direction_10m"), cloud = hourly("cloud_cover")

        func at(_ s: [[Double?]], _ i: Int) -> [Double] { s.compactMap { $0.indices.contains(i) ? $0[i] : nil } }
        func mean(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        /// 0 below 0.02 mm, 1 from 0.2 mm in 15 minutes: "this model sees rain here".
        func wet(_ mm: Double) -> Double { min(1, max(0, (mm - 0.02) / 0.18)) }

        var slots: [Slot] = []
        for (i, t) in times.enumerated() {
            let pr = at(p, i)
            guard !pr.isEmpty, let temp = mean(at(te, i)) else { continue }
            let hour = Calendar.current.dateInterval(of: .hour, for: t)?.start ?? t
            let codes = at(co, i).map { Int($0) }
            // The most significant weather among the models that also see rain; otherwise the most common code.
            let wetCodes = zip(pr, codes).filter { $0.0 >= 0.05 }.map(\.1)
            let code = wetCodes.max() ?? Dictionary(grouping: codes, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 0
            let agree = pr.map(wet).reduce(0, +) / Double(pr.count)
            let ensP = ens.0[hour]
            var s = Slot(time: t, precipMean: mean(pr) ?? 0, precipMax: pr.max() ?? 0, modelAgree: agree,
                         ensembleProb: ensP, appleProb: nil, prob: 0, temp: temp, feels: mean(at(fe, i)) ?? temp,
                         wind: mean(at(wi, i)) ?? 0, gust: at(gu, i).max() ?? 0, humidity: mean(at(hu, i)) ?? 70,
                         code: code, visibility: at(vi, i).min(), windDir: dir[hour], cloud: cloud[hour])
            s.prob = blend(s)
            slots.append(s)
        }
        return Forecast(fetched: .now, lat: lat, lon: lon, slots: slots, models: models.compactMap { modelNames[$0] }, members: ens.1)
    }

    /// Weighted mean of the sources that answered: the ensemble knows the uncertainty, the deterministic
    /// models know the timing within the hour, Apple is a second opinion.
    static func blend(_ s: Slot) -> Double {
        var w = 0.35, sum = 0.35 * s.modelAgree
        if let e = s.ensembleProb { w += 0.45; sum += 0.45 * e }
        if let a = s.appleProb { w += 0.2; sum += 0.2 * a }
        var p = sum / w
        // Inside an hour the ensemble cannot place the rain; when no model sees rain in this quarter, ease it down.
        if s.modelAgree == 0, s.precipMax < 0.02 { p *= 0.7 }
        return min(1, max(0, p))
    }

    /// Share of ensemble members with at least 0.2 mm in the hour.
    static func ensemble(lat: Double, lon: Double) async throws -> ([Date: Double], Int) {
        var c = URLComponents(string: "https://ensemble-api.open-meteo.com/v1/ensemble")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "hourly", value: "precipitation"), .init(name: "models", value: "icon_seamless,gfs_seamless,ecmwf_ifs025"),
            .init(name: "forecast_days", value: "3"), .init(name: "past_days", value: "1"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "timezone", value: "auto"),
        ]
        let o = try await json(c.url!)
        guard let h = o["hourly"] as? [String: Any] else { throw Failure.bad("ensemble yok") }
        let times = nums(h["time"]).map { Date(timeIntervalSince1970: $0 ?? 0) }
        let cols = h.filter { $0.key.hasPrefix("precipitation") }.map { nums($0.value) }
        var out: [Date: Double] = [:]
        for (i, t) in times.enumerated() {
            let v = cols.compactMap { $0.indices.contains(i) ? $0[i] : nil }
            if !v.isEmpty { out[t] = Double(v.filter { $0 >= 0.2 }.count) / Double(v.count) }
        }
        return (out, cols.count)
    }

    /// Today and the next five days from the best-match model: high, low, rain chance and amount, weather.
    static func daily(lat: Double, lon: Double) async throws -> [DaySummary] {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,weather_code"),
            .init(name: "forecast_days", value: "6"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "timezone", value: "auto"),
        ]
        let o = try await json(c.url!)
        guard let d = o["daily"] as? [String: Any] else { throw Failure.bad("daily yok") }
        let t = nums(d["time"]), mx = nums(d["temperature_2m_max"]), mn = nums(d["temperature_2m_min"])
        let pp = nums(d["precipitation_probability_max"]), ps = nums(d["precipitation_sum"]), wc = nums(d["weather_code"])
        return t.indices.compactMap { i in
            guard let ts = t[i], let hi = mx[i], let lo = mn[i] else { return nil }
            let local = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ts + 3600))
            return DaySummary(day: local, tMax: hi, tMin: lo, rainProb: (pp[i] ?? 0) / 100, rainMM: ps[i] ?? 0, code: Int(wc[i] ?? 0))
        }
    }

    /// Past days (model analysis, close to what happened) for the relation view.
    static func past(lat: Double, lon: Double, days: Int = 60) async throws -> [PastDay] {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)), .init(name: "longitude", value: String(lon)),
            .init(name: "daily", value: "precipitation_sum,temperature_2m_max,temperature_2m_min,sunshine_duration,daylight_duration,wind_speed_10m_max,cloud_cover_mean"),
            .init(name: "past_days", value: String(days)), .init(name: "forecast_days", value: "1"),
            .init(name: "timeformat", value: "unixtime"), .init(name: "timezone", value: "auto"),
        ]
        let o = try await json(c.url!)
        guard let d = o["daily"] as? [String: Any] else { throw Failure.bad("daily yok") }
        let t = nums(d["time"]), r = nums(d["precipitation_sum"]), mx = nums(d["temperature_2m_max"]), mn = nums(d["temperature_2m_min"])
        let su = nums(d["sunshine_duration"]), dl = nums(d["daylight_duration"]), wm = nums(d["wind_speed_10m_max"]), cc = nums(d["cloud_cover_mean"])
        return t.indices.compactMap { i in
            guard let ts = t[i], let tx = mx[i] else { return nil }
            // unixtime days are the instant of the place's local midnight; an hour later is safely inside that day
            let local = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: ts + 3600))
            return PastDay(day: local, rainMM: r[i] ?? 0, tMax: tx, tMin: mn[i] ?? tx, sunshineH: (su[i] ?? 0) / 3600,
                           daylightH: (dl[i] ?? 0) / 3600, windMax: wm[i] ?? 0, cloud: cc[i] ?? 50)
        }
    }
}
