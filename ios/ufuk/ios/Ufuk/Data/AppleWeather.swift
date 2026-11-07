// WeatherKit as the second opinion: hourly rain chance and the current observation-based conditions.
// Minute-by-minute rain is not offered for Türkiye, so Ufuk does not depend on it. Any failure (no
// entitlement, no network, region) leaves Open-Meteo alone in charge.
import CoreLocation
import Foundation
import WeatherKit

struct AppleNow: Sendable {
    var temperature: Double
    var condition: String
    var precipitationIntensity: Double   // mm/h now
    var symbol: String
    var minuteAvailable: Bool
}

enum AppleWeather {
    enum Status: Equatable { case unknown, ok, failed(String) }

    static func fetch(lat: Double, lon: Double) async -> (hourly: [Date: Double], now: AppleNow?, status: Status) {
        do {
            let loc = CLLocation(latitude: lat, longitude: lon)
            let (cur, hours, minute) = try await WeatherService.shared.weather(for: loc, including: .current, .hourly, .minute)
            var h: [Date: Double] = [:]
            for x in hours.forecast { h[x.date] = x.precipitationChance }
            let now = AppleNow(temperature: cur.temperature.converted(to: .celsius).value,
                               condition: cur.condition.description,
                               // WeatherKit gives a speed; m/s of water depth × 3 600 000 = mm/h
                               precipitationIntensity: cur.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000,
                               symbol: cur.symbolName, minuteAvailable: minute != nil)
            return (h, now, .ok)
        } catch {
            return ([:], nil, .failed(error.localizedDescription))
        }
    }

    /// Apple asks for its mark and a link to the data sources next to the data.
    static func attribution() async -> (logo: URL, legal: URL)? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return (a.combinedMarkDarkURL, a.legalPageURL)
    }
}
