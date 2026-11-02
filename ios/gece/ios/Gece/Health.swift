// Apple Health: what the day held (steps, walking, cycling, workouts from Wise Path or Demir), last night's sleep,
// and writing the night routine as a flexibility workout. Nothing leaves the phone except through the PDM bus.
import Foundation
import HealthKit

struct DaySummary: Codable, Hashable {
    var date: String                    // yyyy-MM-dd
    var steps: Int = 0
    var walkKm: Double = 0
    var cycleKm: Double = 0
    var activeKcal: Double = 0
    var restingHR: Double?
    var hrv: Double?
    var weightKg: Double?
    var sleepHours: Double?             // the night that ended on this date's morning
    var sleepStart: Date?
    var sleepEnd: Date?
    var workouts: [WorkoutLine] = []

    struct WorkoutLine: Codable, Hashable {
        var kind: String
        var minutes: Int
        var km: Double?
        var source: String
    }

    /// A lot of leg work: the night takes the knee · leg module.
    var legHeavy: Bool { steps >= 10_000 || walkKm + cycleKm >= 6 || workouts.contains { $0.kind == "Bisiklet" && $0.minutes >= 30 } }
}

@MainActor
final class Health: ObservableObject {
    static let shared = Health()
    let store = HKHealthStore()
    @Published var today: DaySummary?
    @Published var authorized = UserDefaults.standard.bool(forKey: "health.asked")

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis)]
        for q: HKQuantityTypeIdentifier in [.stepCount, .distanceWalkingRunning, .distanceCycling, .activeEnergyBurned,
                                            .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass] {
            s.insert(HKQuantityType(q))
        }
        return s
    }

    func requestAccess() async {
        guard available else { return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: readTypes)
            UserDefaults.standard.set(true, forKey: "health.asked")
            authorized = true
        } catch {
            authorized = false
        }
    }

    func refreshToday() async {
        guard available, authorized else { return }
        today = await summary(for: .now)
    }

    // MARK: reading

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func summary(for day: Date) async -> DaySummary {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? day
        var s = DaySummary(date: Self.dayFormat.string(from: start))
        s.steps = Int(await sum(.stepCount, .count(), start, end))
        s.walkKm = await sum(.distanceWalkingRunning, .meterUnit(with: .kilo), start, end)
        s.cycleKm = await sum(.distanceCycling, .meterUnit(with: .kilo), start, end)
        s.activeKcal = await sum(.activeEnergyBurned, .kilocalorie(), start, end)
        s.restingHR = await latest(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), start, end)
        s.hrv = await latest(.heartRateVariabilitySDNN, .secondUnit(with: .milli), start, end)
        s.weightKg = await latest(.bodyMass, .gramUnit(with: .kilo), cal.date(byAdding: .day, value: -30, to: end) ?? start, end)
        // last night: from 18:00 the day before until 14:00 of this day
        let nightFrom = cal.date(byAdding: .hour, value: -6, to: start) ?? start
        let nightTo = cal.date(byAdding: .hour, value: 14, to: start) ?? end
        (s.sleepHours, s.sleepStart, s.sleepEnd) = await sleep(nightFrom, nightTo)
        s.workouts = await workouts(start, end)
        return s
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ a: Date, _ b: Date) async -> Double {
        await withCheckedContinuation { c in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: a, end: b),
                                      options: .cumulativeSum) { _, r, _ in
                c.resume(returning: r?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ a: Date, _ b: Date) async -> Double? {
        await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: a, end: b),
                                  limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, r, _ in
                c.resume(returning: (r?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Asleep time (all asleep stages), merged so that two sources (watch + phone) are not counted twice.
    private func sleep(_ a: Date, _ b: Date) async -> (Double?, Date?, Date?) {
        let samples: [HKCategorySample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: a, end: b),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, r, _ in
                c.resume(returning: (r as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep = samples.filter { HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains($0.value) }
        guard !asleep.isEmpty else { return (nil, nil, nil) }
        var merged: [(Date, Date)] = []
        for x in asleep.sorted(by: { $0.startDate < $1.startDate }) {
            if let last = merged.last, x.startDate <= last.1 {
                merged[merged.count - 1].1 = max(last.1, x.endDate)
            } else {
                merged.append((x.startDate, x.endDate))
            }
        }
        let secs = merged.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
        return (secs / 3600, merged.first?.0, merged.last?.1)
    }

    private func workouts(_ a: Date, _ b: Date) async -> [DaySummary.WorkoutLine] {
        let list: [HKWorkout] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForSamples(withStart: a, end: b),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, r, _ in
                c.resume(returning: (r as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        return list.filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }.map { w in
            let km = (w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                      ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity())?.doubleValue(for: .meterUnit(with: .kilo))
            return .init(kind: Self.kindName(w.workoutActivityType), minutes: Int(w.duration / 60), km: km, source: w.sourceRevision.source.name)
        }
    }

    static func kindName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .walking, .hiking: return "Yürüyüş"
        case .cycling: return "Bisiklet"
        case .running: return "Koşu"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Ağırlık"
        case .flexibility, .yoga, .pilates: return "Esneme"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Antrenman"
        }
    }

    // MARK: writing

    /// The routine goes to Health as a flexibility workout (Fitness rings count it).
    func saveRoutine(start: Date, end: Date) async {
        guard available, authorized, store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .flexibility
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {}
    }
}
