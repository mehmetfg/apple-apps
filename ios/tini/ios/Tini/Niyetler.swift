import AppIntents

// Kestirmeler, Siri ve otomasyonlar için. `AudioPlaybackIntent` uygulamayı ön plana getirmeden
// arka planda çalıştırır; "Voice Dream açıldığında Tını'yı çal" otomasyonu bunun üstüne kurulur.

struct TiniCal: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Tını'yı çal"
    static var description = IntentDescription("Müziği, dinlediğin şeyi kesmeden başlatır.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.yenile()
        Calar.shared.baslat()
        return .result()
    }
}

struct TiniDurdur: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Tını'yı durdur"
    static var description = IntentDescription("Arka plan müziğini yavaşça kısıp durdurur.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.durdur()
        return .result()
    }
}

struct TiniAcKapa: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Tını'yı aç/kapat"
    static var description = IntentDescription("Çalıyorsa durdurur, duruyorsa başlatır. Arkaya Dokunma için uygundur.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.yenile()
        Calar.shared.acKapa()
        return .result()
    }
}

struct TiniSonraki: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Tını'da sonraki parça"

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.sonraki()
        return .result()
    }
}

struct TiniSesi: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Tını sesini ayarla"
    static var description = IntentDescription("Müziğin sesini konuşmadan bağımsız ayarlar (0-100).")

    @Parameter(title: "Ses (yüzde)", default: 30, inclusiveRange: (0, 100))
    var yuzde: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        Calar.shared.ses = Float(yuzde) / 100
        return .result()
    }
}

struct TiniKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TiniCal(), phrases: ["\(.applicationName) çal", "\(.applicationName) başlat"],
                    shortTitle: "Çal", systemImageName: "play.fill")
        AppShortcut(intent: TiniDurdur(), phrases: ["\(.applicationName) durdur", "\(.applicationName) kapat"],
                    shortTitle: "Durdur", systemImageName: "stop.fill")
        AppShortcut(intent: TiniAcKapa(), phrases: ["\(.applicationName) aç kapat"],
                    shortTitle: "Aç/Kapat", systemImageName: "playpause.fill")
        AppShortcut(intent: TiniSonraki(), phrases: ["\(.applicationName) sonraki"],
                    shortTitle: "Sonraki", systemImageName: "forward.fill")
    }
}
