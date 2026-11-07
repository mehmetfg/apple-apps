// The ride on the lock screen: the next 90 minutes of rain, when it gets dark, how it feels.
// Started by the person ("Yola çıkıyorum"), refreshed whenever the app refreshes, gone after arrival.
import ActivityKit
import Foundation

enum RideActivity {
    @MainActor
    static func state(_ s: Store, leg: Leg?) -> RideAttributes.ContentState {
        let now = Date.now
        let start = Calendar.current.dateInterval(of: .hour, for: now).map { h in
            h.start.addingTimeInterval(floor(now.timeIntervalSince(h.start) / 900) * 900)
        } ?? now
        let slots = s.forecast?.slots(from: start, to: start.addingTimeInterval(90 * 60)) ?? []
        let note: String
        if let r = slots.first(where: { $0.prob >= 0.4 }) {
            note = r.time <= now ? "Yağış var · \(Fmt.pct(r.prob))" : "Yağış \(Fmt.t(r.time)) civarı"
        } else {
            note = "Yol boyu kuru"
        }
        return .init(slotStart: start, probs: slots.map(\.prob), dusk: s.sunToday.dusk, note: note, rideFeel: leg?.feel)
    }

    @MainActor
    static func start(_ s: Store, kind: LegKind) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for a in Activity<RideAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        let leg = kind == .morning ? s.morning : s.evening
        let arrival = Date.now.addingTimeInterval(TimeInterval(s.rideMinutes * 60))
        let attrs = RideAttributes(leg: kind == .morning ? "Sabah" : "Akşam", arrival: arrival)
        _ = try? Activity.request(attributes: attrs, content: .init(state: state(s, leg: leg), staleDate: arrival.addingTimeInterval(1800)))
    }

    @MainActor
    static func updateAll(_ s: Store) async {
        for a in Activity<RideAttributes>.activities {
            if a.attributes.arrival.addingTimeInterval(1800) < .now {
                await a.end(nil, dismissalPolicy: .immediate)
            } else {
                let leg = a.attributes.leg == "Sabah" ? s.morning : s.evening
                await a.update(.init(state: state(s, leg: leg), staleDate: a.attributes.arrival.addingTimeInterval(1800)))
            }
        }
    }

    static var running: Bool { !Activity<RideAttributes>.activities.isEmpty }
}
