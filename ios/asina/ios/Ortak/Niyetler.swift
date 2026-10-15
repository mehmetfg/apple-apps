// Widget düğmeleri (iOS 17 etkileşimli widget). Yalnız paylaşılan ayarı değiştirir; widget kendini yeniler.
import AppIntents
import WidgetKit

struct SonrakiKelime: AppIntent {
    static var title: LocalizedStringResource = "Sonraki kelime"
    static var description = IntentDescription("Widget'ta bugünün sıradaki kelimesine geçer.")

    func perform() async throws -> some IntentResult {
        let a = Paylasim.ayar
        a.set(a.integer(forKey: Paylasim.siraAnahtari) + 1, forKey: Paylasim.siraAnahtari)
        a.set(false, forKey: Paylasim.acikAnahtari)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.widgetTuru)
        return .result()
    }
}

struct AnlaminiGoster: AppIntent {
    static var title: LocalizedStringResource = "Anlamını göster"
    static var description = IntentDescription("Önce hatırla kipinde gizli anlamı açar ya da kapatır.")

    func perform() async throws -> some IntentResult {
        let a = Paylasim.ayar
        a.set(!a.bool(forKey: Paylasim.acikAnahtari), forKey: Paylasim.acikAnahtari)
        WidgetCenter.shared.reloadTimelines(ofKind: Paylasim.widgetTuru)
        return .result()
    }
}

/// Widget'taki hoparlör düğmesi. `AudioPlaybackIntent`: sistem bunu uygulamanın kendi sürecinde çalıştırır,
/// bu yüzden uygulama açılmadan ses çalabilir (Info.plist'te `audio` arka plan kipi gerekir).
struct SeslendirKelime: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Kelimeyi seslendir"
    static var description = IntentDescription("Widget'taki kelimeyi İngiliz aksanıyla okur.")

    @Parameter(title: "Kelime") var kelime: String
    @Parameter(title: "Ses adresi") var ses: String

    init() {}
    init(kelime: String, ses: String?) {
        self.kelime = kelime
        self.ses = ses ?? ""
    }

    func perform() async throws -> some IntentResult {
        let oxford = (Paylasim.ayar.object(forKey: Paylasim.oxfordAnahtari) as? Bool) ?? true
        await MainActor.run { Ses.ortak.soyle(ad: kelime, url: ses, oxford: oxford) }
        await Ses.ortak.bekle()
        return .result()
    }
}
