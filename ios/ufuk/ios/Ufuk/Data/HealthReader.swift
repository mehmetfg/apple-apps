// Apple Health, read only: daily steps, walking and cycling distance, sleep. Used to relate the weather
// to what the person actually did; nothing is written back.
import Foundation
import HealthKit

struct HealthDay: Codable, Hashable, Sendable {
    var steps: Double?
    var walkKm: Double?
    var cycleKm: Double?
    var sleepH: Double?
}

@MainActor
final class HealthReader {
    static let shared = HealthReader()
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async {
        guard available else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
                                       HKQuantityType(.distanceCycling), HKCategoryType(.sleepAnalysis)]
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    /// Day (local midnight) → values, for the last `days` days.
    func days(_ days: Int = 60) async -> [Date: HealthDay] {
        guard available else { return [:] }
        let cal = Calendar.current
        let end = cal.startOfDay(for: .now).addingTimeInterval(86400)
        let start = end.addingTimeInterval(-Double(days) * 86400)
        var out: [Date: HealthDay] = [:]
        func put(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ scale: Double, _ set: (inout HealthDay, Double) -> Void) async {
            let q = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            guard let r = try? await q.result(for: store) else { return }
            for s in r.statistics() {
                guard let v = s.sumQuantity()?.doubleValue(for: unit) else { continue }
                set(&out[cal.startOfDay(for: s.startDate), default: HealthDay()], v * scale)
            }
        }
        await put(.stepCount, .count(), 1) { $0.steps = $1 }
        await put(.distanceWalkingRunning, .meter(), 0.001) { $0.walkKm = $1 }
        await put(.distanceCycling, .meter(), 0.001) { $0.cycleKm = $1 }

        // Sleep counts for the day you wake up on.
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue]
        let sq = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
                                         sortDescriptors: [])
        if let samples = try? await sq.result(for: store) {
            var hours: [Date: Double] = [:]
            for s in samples where asleep.contains(s.value) {
                hours[cal.startOfDay(for: s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
            }
            for (d, h) in hours { out[d, default: HealthDay()].sleepH = h }
        }
        return out
    }
}
