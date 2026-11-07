// Apple Health on the phone: the last 30 days as day summaries, and the hand-entered measurements
// (weight, waist). SBS reads everything that Health has; it writes only weight and waist.
import Foundation
import HealthKit

struct HealthWorkout: Codable, Hashable {
    var kind: String
    var minutes: Double
    var source: String?
    var start: String?
}

struct HealthDay: Codable, Identifiable, Hashable {
    var date: String
    var sleepH: Double?
    var inBedOnly: Bool?
    var bed: String?
    var wake: String?
    var deepMin: Double?
    var remMin: Double?
    var coreMin: Double?
    var awakeMin: Double?
    var steps: Double?
    var walkKm: Double?
    var cycleKm: Double?
    var flights: Double?
    var activeKcal: Double?
    var restingHr: Double?
    var hrv: Double?
    var weightKg: Double?
    var waistCm: Double?
    var systolic: Double?
    var diastolic: Double?
    var workouts: [HealthWorkout]?

    var id: String { date }
    var hasData: Bool {
        sleepH != nil || steps != nil || restingHr != nil || weightKg != nil || waistCm != nil || systolic != nil || !(workouts ?? []).isEmpty
    }
}

struct Sample: Identifiable, Hashable {
    var date: Date
    var value: Double
    var id: Date { date }
}

@MainActor
final class Health: ObservableObject {
    static let shared = Health()
    private let store = HKHealthStore()

    @Published var days: [HealthDay] = []        // oldest first; the last one is today
    @Published var weight: [Sample] = []
    @Published var waist: [Sample] = []
    @Published var systolic: [Sample] = []
    @Published var diastolic: [Sample] = []
    @Published var loaded = false

    var today: HealthDay? { days.last }
    /// The last finished night (today's entry holds the night that ended this morning).
    var lastNight: HealthDay? { days.last(where: { $0.sleepH != nil }) }
    var hasAnyData: Bool { days.contains { $0.hasData } }

    private static let readIDs: [HKQuantityTypeIdentifier] = [
        .stepCount, .distanceWalkingRunning, .distanceCycling, .flightsClimbed, .activeEnergyBurned,
        .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass, .waistCircumference,
        .bloodPressureSystolic, .bloodPressureDiastolic]

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = Set(Self.readIDs.map { HKQuantityType($0) })
        read.insert(HKCategoryType(.sleepAnalysis))
        read.insert(HKObjectType.workoutType())
        let share: Set<HKSampleType> = [HKQuantityType(.bodyMass), HKQuantityType(.waistCircumference)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func refresh() async {
        if ProcessInfo.processInfo.arguments.contains("-demoHealth") {   // preview data for screenshots, never written to the vault
            loadDemo()
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else { loaded = true; return }
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        async let steps = sums(.stepCount, .count(), from)
        async let walk = sums(.distanceWalkingRunning, .meterUnit(with: .kilo), from)
        async let cycle = sums(.distanceCycling, .meterUnit(with: .kilo), from)
        async let flights = sums(.flightsClimbed, .count(), from)
        async let kcal = sums(.activeEnergyBurned, .kilocalorie(), from)
        async let rhr = averages(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), from)
        async let hrv = averages(.heartRateVariabilitySDNN, .secondUnit(with: .milli), from)
        async let nights = sleep(from: cal.date(byAdding: .hour, value: -8, to: from)!)
        async let workouts = workouts(from)
        async let w = samples(.bodyMass, .gramUnit(with: .kilo))
        async let wa = samples(.waistCircumference, .meterUnit(with: .centi))
        async let sys = samples(.bloodPressureSystolic, .millimeterOfMercury())
        async let dia = samples(.bloodPressureDiastolic, .millimeterOfMercury())
        let (s, wk, cy, fl, kc, rh, hv, ni, wo) = await (steps, walk, cycle, flights, kcal, rhr, hrv, nights, workouts)
        (weight, waist, systolic, diastolic) = await (w, wa, sys, dia)

        func lastOf(_ xs: [Sample], _ key: String) -> Double? { xs.last(where: { Day.key($0.date) == key })?.value }
        var out: [HealthDay] = []
        for i in 0..<30 {
            let key = Day.key(cal.date(byAdding: .day, value: i, to: from)!)
            var d = HealthDay(date: key)
            if let n = ni[key] {
                d.sleepH = n.hours; d.inBedOnly = n.inBedOnly ? true : nil; d.bed = n.bed; d.wake = n.wake
                d.deepMin = n.deep; d.remMin = n.rem; d.coreMin = n.core; d.awakeMin = n.awake
            }
            d.steps = s[key]; d.walkKm = wk[key].map { ($0 * 10).rounded() / 10 }; d.cycleKm = cy[key].map { ($0 * 10).rounded() / 10 }
            d.flights = fl[key]; d.activeKcal = kc[key]?.rounded(); d.restingHr = rh[key]?.rounded(); d.hrv = hv[key]?.rounded()
            d.weightKg = lastOf(weight, key); d.waistCm = lastOf(waist, key)
            d.systolic = lastOf(systolic, key); d.diastolic = lastOf(diastolic, key)
            d.workouts = wo[key]
            out.append(d)
        }
        days = out
        loaded = true
    }

    // MARK: queries

    private func sums(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ from: Date) async -> [String: Double] {
        await statistics(id, unit, from, .cumulativeSum) { $0.sumQuantity() }
    }

    private func averages(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ from: Date) async -> [String: Double] {
        await statistics(id, unit, from, .discreteAverage) { $0.averageQuantity() }
    }

    private func statistics(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ from: Date, _ options: HKStatisticsOptions,
                            _ pick: @escaping (HKStatistics) -> HKQuantity?) async -> [String: Double] {
        let type = HKQuantityType(id)
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil)
        let q = HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: type, predicate: pred), options: options,
                                                      anchorDate: from, intervalComponents: DateComponents(day: 1))
        guard let coll = try? await q.result(for: store) else { return [:] }
        var out: [String: Double] = [:]
        coll.enumerateStatistics(from: from, to: .now) { s, _ in
            if let v = pick(s)?.doubleValue(for: unit) { out[Day.key(s.startDate)] = v }
        }
        return out
    }

    private func samples(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> [Sample] {
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id))],
                                        sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 60)
        let got = (try? await q.result(for: store)) ?? []
        return got.map { Sample(date: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }.reversed()
    }

    struct Night { var hours: Double; var inBedOnly: Bool; var bed: String; var wake: String; var deep, rem, core, awake: Double? }

    private func sleep(from: Date) async -> [String: Night] {
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil)
        let q = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: pred)],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        let got = (try? await q.result(for: store)) ?? []
        // A sleep that starts at 23:30 belongs to the next morning: the night key is the day of start + 6 hours.
        var groups: [String: [HKCategorySample]] = [:]
        for s in got { groups[Day.key(s.startDate.addingTimeInterval(6 * 3600)), default: []].append(s) }
        func union(_ xs: [HKCategorySample]) -> Double {   // minutes; two sources (phone and watch) can overlap
            var total = 0.0
            var end = Date.distantPast
            for s in xs.sorted(by: { $0.startDate < $1.startDate }) {
                let a = max(s.startDate, end)
                if s.endDate > a { total += s.endDate.timeIntervalSince(a) / 60; end = s.endDate }
            }
            return total
        }
        let hm = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        var out: [String: Night] = [:]
        for (key, xs) in groups {
            func of(_ v: HKCategoryValueSleepAnalysis) -> [HKCategorySample] { xs.filter { $0.value == v.rawValue } }
            let asleep = xs.filter { [HKCategoryValueSleepAnalysis.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].map(\.rawValue).contains($0.value) }
            let base = asleep.isEmpty ? of(.inBed) : asleep
            let minutes = union(base)
            guard minutes >= 60, let first = base.map(\.startDate).min(), let last = base.map(\.endDate).max() else { continue }
            func stage(_ v: HKCategoryValueSleepAnalysis) -> Double? { let m = union(of(v)); return m > 0 ? m.rounded() : nil }
            out[key] = Night(hours: (minutes / 6).rounded() / 10, inBedOnly: asleep.isEmpty, bed: first.formatted(hm), wake: last.formatted(hm),
                             deep: stage(.asleepDeep), rem: stage(.asleepREM), core: stage(.asleepCore), awake: stage(.awake))
        }
        return out
    }

    private func workouts(_ from: Date) async -> [String: [HealthWorkout]] {
        let pred = HKQuery.predicateForSamples(withStart: from, end: nil)
        let q = HKSampleQueryDescriptor(predicates: [.workout(pred)], sortDescriptors: [SortDescriptor(\.startDate)])
        let got = (try? await q.result(for: store)) ?? []
        var out: [String: [HealthWorkout]] = [:]
        for w in got {
            let kind: String
            switch w.workoutActivityType {
            case .walking, .hiking: kind = "walking"
            case .cycling: kind = "cycling"
            case .running: kind = "running"
            case .traditionalStrengthTraining, .functionalStrengthTraining: kind = "strength"
            case .flexibility, .yoga: kind = "stretch"
            default: kind = "other"
            }
            out[Day.key(w.startDate), default: []].append(
                HealthWorkout(kind: kind, minutes: (w.duration / 60).rounded(), source: w.sourceRevision.source.name,
                              start: ISO8601DateFormatter().string(from: w.startDate)))
        }
        return out
    }

    // MARK: hand-entered measurements

    func save(weightKg: Double? = nil, waistCm: Double? = nil) async -> Bool {
        var objects: [HKQuantitySample] = []
        if let weightKg {
            objects.append(HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg), start: .now, end: .now))
        }
        if let waistCm {
            objects.append(HKQuantitySample(type: HKQuantityType(.waistCircumference), quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: waistCm), start: .now, end: .now))
        }
        guard !objects.isEmpty, HKHealthStore.isHealthDataAvailable() else { return false }
        do { try await store.save(objects) } catch { return false }
        await refresh()
        return true
    }

    // MARK: preview data (launch argument -demoHealth)

    private func loadDemo() {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now))!
        var g = SystemRandomNumberGenerator()
        days = (0..<30).map { i in
            var d = HealthDay(date: Day.key(cal.date(byAdding: .day, value: i, to: from)!))
            d.sleepH = (Double.random(in: 5.6...8.1, using: &g) * 10).rounded() / 10
            d.bed = "23:\(Int.random(in: 10...55, using: &g))"; d.wake = "06:\(Int.random(in: 10...55, using: &g))"
            d.deepMin = 48; d.remMin = 96; d.coreMin = 230; d.awakeMin = 12
            d.steps = Double(Int.random(in: 3800...12400, using: &g))
            d.walkKm = (d.steps! / 1350 * 10).rounded() / 10
            d.restingHr = Double(Int.random(in: 55...63, using: &g))
            d.activeKcal = Double(Int.random(in: 280...620, using: &g))
            return d
        }
        weight = (0..<8).map { Sample(date: cal.date(byAdding: .day, value: -7 * (7 - $0), to: .now)!, value: 84.2 - Double($0) * 0.3) }
        waist = (0..<5).map { Sample(date: cal.date(byAdding: .day, value: -7 * (4 - $0), to: .now)!, value: 98 - Double($0) * 0.4) }
        loaded = true
    }
}
