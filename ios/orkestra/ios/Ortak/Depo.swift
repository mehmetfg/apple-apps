// Uygulama ile widget'ın ortak dolabı (App Group). Uygulama vault'tan okuduğunu buraya yazar; widget buradan okur.
// Saklananlar: son orkestra.json kopyası · bildirilmiş durumlar · ertelenen süreçler · ayarlar.
import Foundation

enum Depo {
    static let grup = "group.com.fatihgocgun.orkestra"

    static var klasor: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grup) { return u }
        // App Group imzası yoksa (önizleme/sınama) uygulamanın kendi belgeleri
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var ayar: UserDefaults { UserDefaults(suiteName: grup) ?? .standard }

    private static var veriURL: URL { klasor.appendingPathComponent("orkestra.json") }

    static func veriYaz(_ v: OrkestraVeri) {
        if let d = try? JSONEncoder().encode(v) { try? d.write(to: veriURL, options: .atomic) }
    }

    static func veriOku() -> OrkestraVeri? {
        guard let d = try? Data(contentsOf: veriURL) else { return nil }
        return try? JSONDecoder().decode(OrkestraVeri.self, from: d)
    }

    // MARK: ertelenen süreçler (bildirimden "Yarına bırak") — süre dolunca kendiliğinden düşer
    static func ertelenenler(_ simdi: Date = .now) -> Set<String> {
        let s = ayar.dictionary(forKey: "ertele") as? [String: Double] ?? [:]
        return Set(s.filter { $0.value > simdi.timeIntervalSince1970 }.keys)
    }

    static func ertele(_ id: String, saat: Double = 24) {
        var s = ayar.dictionary(forKey: "ertele") as? [String: Double] ?? [:]
        s = s.filter { $0.value > Date.now.timeIntervalSince1970 }
        s[id] = Date.now.addingTimeInterval(saat * 3600).timeIntervalSince1970
        ayar.set(s, forKey: "ertele")
    }

    static func erteleKaldir(_ id: String) {
        var s = ayar.dictionary(forKey: "ertele") as? [String: Double] ?? [:]
        s[id] = nil
        ayar.set(s, forKey: "ertele")
    }

    // MARK: en son bildirilen durumlar — "her olayda" bildirim, ama aynı olay bir kez
    static var bildirilen: [String: String] {
        get { ayar.dictionary(forKey: "bildirilen") as? [String: String] ?? [:] }
        set { ayar.set(newValue, forKey: "bildirilen") }
    }
}
