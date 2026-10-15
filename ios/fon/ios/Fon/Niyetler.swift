import AppIntents

// Kestirmeler, Siri ve otomasyonlar için. `AudioPlaybackIntent` uygulamayı ön plana getirmeden
// arka planda çalıştırır; "Voice Dream açıldığında Fon'u çal" otomasyonu bunun üstüne kurulur.

struct FonCal: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Fon'u çal"
    static var description = IntentDescription("Arka plan müziğini, dinlediğin şeyi kesmeden başlatır.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.yenile()
        Calar.shared.baslat()
        return .result()
    }
}

struct FonDurdur: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Fon'u durdur"
    static var description = IntentDescription("Arka plan müziğini yavaşça kısıp durdurur.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.durdur()
        return .result()
    }
}

struct FonAcKapa: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Fon'u aç/kapat"
    static var description = IntentDescription("Çalıyorsa durdurur, duruyorsa başlatır. Arkaya Dokunma için uygundur.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.yenile()
        Calar.shared.acKapa()
        return .result()
    }
}

struct FonSonraki: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Fon'da sonraki parça"

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.sonraki()
        return .result()
    }
}

struct FonSesi: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Fon sesini ayarla"
    static var description = IntentDescription("Müziğin sesini konuşmadan bağımsız ayarlar (0-100).")

    @Parameter(title: "Ses (yüzde)", default: 30, inclusiveRange: (0, 100))
    var yuzde: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.ses = Float(yuzde) / 100
        return .result()
    }
}

struct FonKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FonCal(), phrases: ["\(.applicationName) çal", "\(.applicationName) başlat"],
                    shortTitle: "Çal", systemImageName: "play.fill")
        AppShortcut(intent: FonDurdur(), phrases: ["\(.applicationName) durdur", "\(.applicationName) kapat"],
                    shortTitle: "Durdur", systemImageName: "stop.fill")
        AppShortcut(intent: FonAcKapa(), phrases: ["\(.applicationName) aç kapat"],
                    shortTitle: "Aç/Kapat", systemImageName: "playpause.fill")
        AppShortcut(intent: FonSonraki(), phrases: ["\(.applicationName) sonraki"],
                    shortTitle: "Sonraki", systemImageName: "forward.fill")
    }
}
