// Widget düğmeleri (etkileşimli widget). Durum App Group'ta; widget kendini yeniler, içerik geçiş animasyonuyla değişir.
import AppIntents
import AVFoundation
import WidgetKit
import PDMBus

/// "Biliyorum" düğmesi: kelime Vitrin'de bir daha çıkmaz ve PDM Ağı'na `word.known` gider
/// (olay App Group kutusunda bekler, Vitrin açılınca vault'a yazılır). Öteki uygulamalar da artık göstermez.
struct BiliyorumNiyeti: AppIntent {
    static var title: LocalizedStringResource = "Biliyorum"
    static var description = IntentDescription("Kelimeyi bilinenlere ekler; Vitrin ve öteki uygulamalar bir daha göstermez.")
    static var isDiscoverable = false

    @Parameter(title: "Kelime") var kelime: String
    init() {}
    init(kelime: String) { self.kelime = kelime }

    func perform() async throws -> some IntentResult {
        if var k = Depo.tasarimOku(), !k.bilinen.contains(kelime) {
            k.bilinen.append(kelime)
            Depo.tasarimYaz(k)
        }
        PDMBus(app: "vitrin").emit("word.known", subject: PDMSubject.word(kelime), data: ["via": "widget"])
        AgOdak.sifirla()
        WidgetCenter.shared.reloadTimelines(ofKind: Depo.widgetTuru)
        return .result()
    }
}

struct CevirNiyeti: AppIntent {
    static var title: LocalizedStringResource = "Kartı çevir"
    static var description = IntentDescription("Widget'taki anlamı açar ya da gizler.")
    static var isDiscoverable = false

    @Parameter(title: "Tasarım") var tasarim: String
    init() {}
    init(_ id: UUID) { tasarim = id.uuidString }

    func perform() async throws -> some IntentResult {
        let k = "cevrik.\(tasarim)"
        Depo.ayar.set(!Depo.ayar.bool(forKey: k), forKey: k)
        WidgetCenter.shared.reloadTimelines(ofKind: Depo.widgetTuru)
        return .result()
    }
}

struct SonrakiNiyeti: AppIntent {
    static var title: LocalizedStringResource = "Sonraki"
    static var description = IntentDescription("Widget'ta bugünün sıradaki kelimesine, alıntısına ya da kavramına geçer.")
    static var isDiscoverable = false

    @Parameter(title: "Tasarım") var tasarim: String
    init() {}
    init(_ id: UUID) { tasarim = id.uuidString }

    func perform() async throws -> some IntentResult {
        let a = Depo.ayar
        let bugun = Secici.gunAnahtari(.now)
        let n = a.string(forKey: "ileriGun.\(tasarim)") == bugun ? a.integer(forKey: "ileri.\(tasarim)") : 0
        a.set(n + 1, forKey: "ileri.\(tasarim)")
        a.set(bugun, forKey: "ileriGun.\(tasarim)")
        a.set(false, forKey: "cevrik.\(tasarim)")
        WidgetCenter.shared.reloadTimelines(ofKind: Depo.widgetTuru)
        return .result()
    }
}

/// Hoparlör düğmesi. `AudioPlaybackIntent` uygulamanın kendi sürecinde çalışır; uygulama açılmadan ses verir
/// (Info.plist'te `audio` arka plan kipi var). Önce Oxford'un gerçek kaydı, ağ yoksa cihazın İngiliz sesi.
struct SeslendirNiyeti: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Seslendir"
    static var description = IntentDescription("Widget'taki kelimeyi İngiliz aksanıyla okur.")
    static var isDiscoverable = false

    @Parameter(title: "Metin") var metin: String
    @Parameter(title: "Ses adresi") var ses: String
    init() {}
    init(metin: String, ses: String) { self.metin = metin; self.ses = ses }

    func perform() async throws -> some IntentResult {
        await Ses.ortak.soyle(metin, url: ses)
        return .result()
    }
}

@MainActor
final class Ses: NSObject, AVSpeechSynthesizerDelegate {
    static let ortak = Ses()
    private let sentez = AVSpeechSynthesizer()
    private var oynatici: AVPlayer?
    /// One waiter per utterance: two quick taps queue two utterances, and each must end its own wait.
    private var bekleyenler: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    override init() {
        super.init()
        sentez.delegate = self
    }

    func soyle(_ metin: String, url: String) async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        defer { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        if let u = URL(string: url), !url.isEmpty, await oxford(u) { return }
        guard !metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let s = AVSpeechUtterance(string: metin)
        s.voice = AVSpeechSynthesisVoice(language: "en-GB")
        s.rate = 0.42
        await withCheckedContinuation { c in
            bekleyenler[ObjectIdentifier(s)] = c
            sentez.speak(s)
        }
    }

    /// Oxford kaydını indirip çalar; 3 sn içinde inmezse false (cihaz sesi devralır)
    private func oxford(_ u: URL) async -> Bool {
        var istek = URLRequest(url: u, timeoutInterval: 3)
        istek.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (veri, yanit) = try? await URLSession.shared.data(for: istek),
              (yanit as? HTTPURLResponse)?.statusCode == 200, veri.count > 1000 else { return false }
        let dosya = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-ses.mp3")
        guard (try? veri.write(to: dosya)) != nil else { return false }
        let o = AVPlayer(url: dosya)
        oynatici = o
        o.play()
        let sure = (try? await AVURLAsset(url: dosya).load(.duration).seconds) ?? 1.5
        try? await Task.sleep(for: .seconds((min(sure, 4) + 0.2)))
        return true
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in bekleyenler.removeValue(forKey: id)?.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in bekleyenler.removeValue(forKey: id)?.resume() }
    }
}
