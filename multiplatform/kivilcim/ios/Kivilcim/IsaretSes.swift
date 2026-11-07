// Voice note for a Dikkat mark (2026-11-04). iOS gives share extensions no microphone, so Paylaş › Kıvılcım saves the
// mark with "ses_bekliyor" and opens kivilcim://isaret-ses/<id>?ay=<YYYY-MM>; this sheet records it. The .m4a goes next to
// the mark in the App Group (isaret/<ay>/), the mark's JSON gets "ses", and depo.gonder() sends both to the vault again.
// If the app could not be opened from the share sheet, the newest waiting mark (last 30 min) opens this sheet itself.
import SwiftUI
import AVFoundation

struct BekleyenIsaret: Identifiable, Equatable {
    let id: String
    let ay: String
    var baslik: String = ""
}

enum IsaretSesDeposu {
    static var kok: URL? { SharedStore.container?.appendingPathComponent("isaret") }

    /// The mark's JSON: still waiting in isaret/<ay>/ or already sent (gonderildi/<ay>/).
    static func json(_ m: BekleyenIsaret) -> URL? {
        guard let k = kok else { return nil }
        for u in [k.appendingPathComponent("\(m.ay)/\(m.id).json"), k.appendingPathComponent("gonderildi/\(m.ay)/\(m.id).json")]
        where FileManager.default.fileExists(atPath: u.path) { return u }
        return nil
    }

    static func oku(_ m: BekleyenIsaret) -> [String: Any]? {
        guard let u = json(m), let v = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: v) as? [String: Any]
    }

    /// Newest mark that asked for a voice note in the last 30 minutes and has none yet.
    static func sonBekleyen() -> BekleyenIsaret? {
        guard let k = kok else { return nil }
        let fm = FileManager.default
        var aday: (Date, BekleyenIsaret)?
        for dir in [k, k.appendingPathComponent("gonderildi")] {
            for ay in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where ay.lastPathComponent.count == 7 {
                for f in (try? fm.contentsOfDirectory(at: ay, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                where f.pathExtension == "json" {
                    let t = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    guard Date().timeIntervalSince(t) < 30 * 60,
                          let v = try? Data(contentsOf: f), let d = try? JSONSerialization.jsonObject(with: v) as? [String: Any],
                          d["ses_bekliyor"] as? Bool == true, d["ses"] == nil else { continue }
                    let m = BekleyenIsaret(id: f.deletingPathExtension().lastPathComponent, ay: ay.lastPathComponent,
                                           baslik: d["baslik"] as? String ?? "")
                    if aday == nil || t > aday!.0 { aday = (t, m) }
                }
            }
        }
        return aday?.1
    }

    static func sesURL(_ m: BekleyenIsaret) -> URL? {
        guard let k = kok?.appendingPathComponent(m.ay) else { return nil }
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        return k.appendingPathComponent(m.id + ".m4a")
    }

    /// Writes the JSON back into isaret/<ay>/ (so it is sent again) with the voice note attached, or without the request.
    static func bitir(_ m: BekleyenIsaret, sesVar: Bool) {
        guard let k = kok, let eski = json(m), var d = oku(m) else { return }
        d.removeValue(forKey: "ses_bekliyor")
        if sesVar { d["ses"] = m.id + ".m4a" }
        let hedef = k.appendingPathComponent("\(m.ay)/\(m.id).json")
        if let v = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted]),
           (try? v.write(to: hedef, options: .atomic)) != nil, eski != hedef {
            try? FileManager.default.removeItem(at: eski)
        }
        Tani.yaz("işaret sesli notu \(sesVar ? "eklendi" : "atlandı") \(m.id)")
    }
}

struct IsaretSesEkrani: View {
    let isaret: BekleyenIsaret
    @Environment(\.dismiss) private var kapat
    @EnvironmentObject var depo: TelefonDeposu
    @State private var kaydedici: AVAudioRecorder?
    @State private var sure: TimeInterval = 0
    @State private var hata: String?
    @State private var bitti = false
    private let tik = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(isaret.baslik.isEmpty ? "İşaret" : isaret.baslik)
                    .font(.headline).multilineTextAlignment(.center).lineLimit(3)
                Text(String(format: "%d:%02d", Int(sure) / 60, Int(sure) % 60))
                    .font(.system(size: 54, weight: .light, design: .rounded)).monospacedDigit()
                Button { if kaydedici == nil { basla() } else { Task { await kaydet() } } } label: {
                    Image(systemName: kaydedici == nil ? "mic.circle.fill" : "stop.circle.fill")
                        .font(.system(size: 88)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(kaydedici == nil ? Color.orange : Color.red)
                }
                .accessibilityLabel(kaydedici == nil ? "Kaydı başlat" : "Kaydı bitir ve kaydet")
                Text(kaydedici == nil ? "Bu işarete sesli not ekle" : "Konuş, bitince ■")
                    .foregroundStyle(.secondary)
                if let h = hata { Text(h).foregroundStyle(.red).font(.footnote) }
            }
            .padding()
            .navigationTitle("Sesli not").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Notsuz bırak") {
                        kaydedici?.stop(); kaydedici = nil
                        if let u = IsaretSesDeposu.sesURL(isaret) { try? FileManager.default.removeItem(at: u) }
                        IsaretSesDeposu.bitir(isaret, sesVar: false)
                        Task { await depo.gonder() }
                        kapat()
                    }
                }
            }
            .onReceive(tik) { _ in if let k = kaydedici { sure = k.currentTime } }
            .onAppear { basla() }
        }
    }

    private func basla() {
        guard kaydedici == nil, !bitti, let u = IsaretSesDeposu.sesURL(isaret) else { return }
        guard !KayitMerkezi.shared.kayitta else { hata = "Şu an başka bir kayıt sürüyor."; return }
        do {
            let o = AVAudioSession.sharedInstance()
            try o.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try o.setActive(true)
            let k = try AVAudioRecorder(url: u, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16000,
                                                          AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000])
            guard k.record(forDuration: 15 * 60) else { hata = "Kayıt başlamadı."; return }
            kaydedici = k
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch { hata = error.localizedDescription }
    }

    private func kaydet() async {
        guard let k = kaydedici else { return }
        let gecen = k.currentTime
        k.stop(); kaydedici = nil; bitti = true
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let sesVar = gecen >= 1
        if !sesVar, let u = IsaretSesDeposu.sesURL(isaret) { try? FileManager.default.removeItem(at: u) }
        IsaretSesDeposu.bitir(isaret, sesVar: sesVar)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        await depo.gonder()
        kapat()
    }
}
