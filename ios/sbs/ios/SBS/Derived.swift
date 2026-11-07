// What the screens compute from sbs.json and Apple Health together: lifestyle areas, typical ranges,
// and the list of assessments that are still open.
import SwiftUI

struct Assessment: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var done: Bool
    var symbol: String
}

struct Derived {
    var state: SBSState
    var days: [HealthDay]
    var weight: [Sample]
    var waist: [Sample]
    var systolic: [Sample]
    var vaultLinked: Bool

    @MainActor
    init(_ store: Store, _ health: Health) {
        state = store.state ?? SBSState(highlights: [], areas: [], markers: [], conditions: [], crisisLevels: [], episodes: [],
                                        supplements: [], medications: [], documents: [], days: [], ledger: [])
        days = health.days
        weight = health.weight
        waist = health.waist
        systolic = health.systolic
        vaultLinked = store.vaultLinked
    }

    // MARK: markers

    /// Markers measured in the last year that have a range.
    var current: [Marker] { state.markers.filter { !$0.stale && ["in", "watch", "attention"].contains($0.status) && $0.area != "infection" } }
    var outOfRange: [Marker] { current.filter { $0.status != "in" } }
    var lastLab: String? { state.labDates?.last }

    // MARK: typical ranges (the person's own last 30 days)

    static func typical(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 7 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let sd = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot()
        return (mean - sd)...(mean + sd)
    }

    static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

    var last7: [HealthDay] { Array(days.suffix(7)) }
    var before: [HealthDay] { Array(days.dropLast()) }
    var sleep7: Double? { Self.mean(last7.compactMap(\.sleepH)) }
    var steps7: Double? { Self.mean(days.dropLast().suffix(7).compactMap(\.steps)) }
    var steps30: Double? { Self.mean(before.compactMap(\.steps)) }
    var resting7: Double? { Self.mean(last7.compactMap(\.restingHr)) }

    func dots(_ key: KeyPath<HealthDay, Double?>) -> [TypicalBand.Dot] {
        last7.map { d in
            let date = Day.parse(d.date) ?? .now
            return .init(id: d.date, label: date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "tr_TR"))), value: d[keyPath: key])
        }
    }

    // MARK: lifestyle areas for the petal wheel

    var sleepArea: PetalItem {
        guard let avg = sleep7 else {
            return .init(id: "sleep", name: "Uyku", symbol: "bed.double.fill", color: .sleep, tone: .unknown, detail: "Apple Sağlık'ta uyku verisi yok.")
        }
        let tone: Tone = avg >= 7 ? .good : (avg >= 6 ? .watch : .attention)
        return .init(id: "sleep", name: "Uyku", symbol: "bed.double.fill", color: .sleep, tone: tone,
                     detail: "Son gecelerde ortalama \(Self.hours(avg)). Yetişkin için önerilen en az 7 saat.")
    }

    var moveArea: PetalItem {
        guard let a7 = steps7, let a30 = steps30 else {
            return .init(id: "move", name: "Hareket", symbol: "figure.walk", color: .move, tone: .unknown, detail: "Apple Sağlık'ta adım verisi yok.")
        }
        let tone: Tone = a7 >= a30 * 0.9 ? .good : .watch
        return .init(id: "move", name: "Hareket", symbol: "figure.walk", color: .move, tone: tone,
                     detail: "Son 7 günde günde ortalama \(Int(a7).formatted()) adım; 30 günlük tipiğin \(Int(a30).formatted()).")
    }

    var foodArea: PetalItem {
        let recent = state.days.filter { (Day.daysAgo($0.date) ?? 99) < 7 && ($0.planned ?? 0) > 0 }
        guard !recent.isEmpty else {
            return .init(id: "food", name: "Beslenme", symbol: "leaf.fill", color: .food, tone: .unknown, detail: "Son 7 günde Özen'den kayıt gelmedi.")
        }
        let taken = recent.reduce(0) { $0 + ($1.supplements ?? 0) }, planned = recent.reduce(0) { $0 + ($1.planned ?? 0) }
        let share = Double(taken) / Double(max(planned, 1))
        return .init(id: "food", name: "Beslenme", symbol: "leaf.fill", color: .food, tone: share >= 0.7 ? .good : (share >= 0.4 ? .watch : .attention),
                     detail: "Son 7 günde \(recent.count) gün kayıt: rutinin \(taken)/\(planned) kalemi işaretli.")
    }

    var mindArea: PetalItem {
        let recent = state.episodes.filter { $0.region == "mind" && (Day.daysAgo($0.date) ?? 99) < 14 }
        guard !recent.isEmpty else {
            return .init(id: "mind", name: "Zihin", symbol: "brain.head.profile", color: .mind, tone: .unknown, detail: "Son 14 günde zihinle ilgili kayıt yok.")
        }
        return .init(id: "mind", name: "Zihin", symbol: "brain.head.profile", color: .mind, tone: .watch,
                     detail: "Son 14 günde \(recent.count) kayıt: " + recent.compactMap(\.title).joined(separator: ", ") + ".")
    }

    static let areaLook: [String: (String, Color)] = [
        "heart": ("heart.fill", .heart), "metabolism": ("flame.fill", Color(light: 0xFF9500, dark: 0xFFB340)),
        "liver": ("drop.fill", Color(light: 0xA2845E, dark: 0xC4A27A)), "kidney": ("drop.halffull", Color(light: 0x30B0C7, dark: 0x5AC8DC)),
        "blood": ("drop.circle.fill", Color(light: 0xD70015, dark: 0xFF4D5E)), "immune": ("shield.lefthalf.filled", Color(light: 0x34C759, dark: 0x5BD778)),
        "thyroid": ("waveform.path.ecg", Color(light: 0x5E5CE6, dark: 0x8482FF))]

    var petals: [PetalItem] {
        let lab = state.areas.map { a -> PetalItem in
            let look = Self.areaLook[a.id] ?? ("circle.fill", .calm)
            return PetalItem(id: a.id, name: a.name, symbol: look.0, color: look.1, tone: Tone(status: a.state), detail: a.detail)
        }
        return lab + [moveArea, sleepArea, foodArea, mindArea]
    }

    /// "Karaciğer, böbrek ve kan iyi yerde. Kalp ve damar ile bağışıklık tarafına bakman gerekiyor."
    var standing: String {
        let tr = Locale(identifier: "tr_TR")
        func join(_ names: [String]) -> String {   // sentence case: only the first name keeps its capital
            let xs = names.enumerated().map { $0.offset == 0 ? $0.element : $0.element.lowercased(with: tr) }
            return xs.count <= 1 ? xs.joined() : xs.dropLast().joined(separator: ", ") + " ve " + xs.last!
        }
        let all = petals
        let good = all.filter { $0.tone == .good }.map(\.name), bad = all.filter { $0.tone == .attention }.map(\.name)
        let watch = all.filter { $0.tone == .watch }.map(\.name), none = all.filter { $0.tone == .unknown }.map(\.name)
        var s: [String] = []
        if !good.isEmpty { s.append("\(join(good)) iyi yerde.") }
        if !bad.isEmpty { s.append("\(join(bad)) tarafına bakman gerekiyor.") }
        if !watch.isEmpty { s.append("\(join(watch)) sınırda, tekrar bakılacak.") }
        if !none.isEmpty { s.append("\(join(none)) için veri yok.") }
        return s.joined(separator: " ")
    }

    // MARK: assessments

    var assessments: [Assessment] {
        func recent(_ xs: [Sample], _ within: Int) -> Sample? {
            xs.last.flatMap { Calendar.current.dateComponents([.day], from: $0.date, to: .now).day ?? 999 <= within ? $0 : nil }
        }
        let labAge = Day.daysAgo(lastLab)
        let hb = state.marker("hbsag")
        let nights = last7.compactMap(\.sleepH).count
        let stepDays = last7.compactMap(\.steps).count
        let foodDays = state.days.filter { (Day.daysAgo($0.date) ?? 99) < 7 && (($0.supplements ?? 0) > 0 || ($0.proteinG ?? 0) > 0) }.count
        let workouts = state.ledger.filter { ["workout", "walk", "ride"].contains($0.type) && (Day.daysAgo($0.day) ?? 99) < 14 }.count
            + days.suffix(14).reduce(0) { $0 + ($1.workouts?.count ?? 0) }
        let episodes = state.episodes.filter { (Day.daysAgo($0.date) ?? 99) < 30 }.count
        return [
            .init(id: "lab", title: "Güncel tahlil", detail: labAge.map { "Son tahlil \(Day.short(lastLab)) · \($0) gün önce" } ?? "Tahlil kaydı yok",
                  done: (labAge ?? 999) <= 183, symbol: "testtube.2"),
            .init(id: "hbv", title: "Hepatit B paneli", detail: hb.map { "Son ölçüm \(Day.short($0.lastDate)); o tarihte pozitifti" } ?? "Hiç ölçülmedi",
                  done: hb.map { !$0.stale } ?? false, symbol: "cross.vial"),
            .init(id: "weight", title: "Kilo", detail: recent(weight, 30).map { "\($0.value.clean) kg" } ?? "Son 30 günde ölçüm yok",
                  done: recent(weight, 30) != nil, symbol: "scalemass"),
            .init(id: "waist", title: "Bel çevresi", detail: recent(waist, 30).map { "\($0.value.clean) cm" } ?? "Son 30 günde ölçüm yok",
                  done: recent(waist, 30) != nil, symbol: "ruler"),
            .init(id: "bp", title: "Tansiyon", detail: recent(systolic, 90).map { "Büyük tansiyon \($0.value.clean)" } ?? "Son 90 günde ölçüm yok",
                  done: recent(systolic, 90) != nil, symbol: "heart.text.square"),
            .init(id: "sleep", title: "Uyku verisi", detail: "Son 7 gecenin \(nights) tanesinde veri var", done: nights >= 4, symbol: "bed.double"),
            .init(id: "steps", title: "Hareket verisi", detail: "Son 7 günün \(stepDays) tanesinde adım var", done: stepDays >= 4, symbol: "figure.walk"),
            .init(id: "rhr", title: "Dinlenik nabız", detail: resting7.map { "Ortalama \(Int($0)) atım/dk" } ?? "Veri yok (saat gerekir)",
                  done: resting7 != nil, symbol: "heart"),
            .init(id: "food", title: "Beslenme ve takviye kaydı", detail: "Son 7 günde \(foodDays) gün kayıt (Özen)", done: foodDays >= 4, symbol: "leaf"),
            .init(id: "workout", title: "Antrenman kaydı", detail: "Son 14 günde \(workouts) kayıt", done: workouts >= 2, symbol: "dumbbell"),
            .init(id: "episode", title: "Belirti kaydı", detail: "Son 30 günde \(episodes) olay kayıtlı (Kıvılcım)", done: episodes > 0, symbol: "waveform"),
            .init(id: "vault", title: "Vault bağlantısı", detail: vaultLinked ? "Bağlı" : "Klasör seçilmedi (Göz At › Ayarlar)", done: vaultLinked, symbol: "folder"),
        ]
    }

    static func hours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return m % 60 == 0 ? "\(m / 60) sa" : "\(m / 60) sa \(m % 60) dk"
    }
}
