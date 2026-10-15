// Sesle yaz — recall'da konuşarak hatırla. Kayıt Teoria'nın sesli notuyla aynı düşük kalitede (AAC 16 kHz mono 24 kbit ≈ 180 KB/dk):
// anlaşılır, yer kaplamaz. Kayıt bitince telefonun içinde (tr-TR, mümkünse çevrimdışı) yazıya döner ve metin kutusuna eklenir;
// yazıyı düzeltebilirsin. Ses dosyası saklanır: kaydedince sesli not olarak vault'a gider, Mac'te Whisper daha temiz döküm çıkarır.
import SwiftUI
#if canImport(Speech)
import Speech
#endif

enum Dokum {
    /// Ses dosyasını yazıya çevirir. İzin yoksa ya da tanıyıcı yoksa nil.
    static func yaziya(_ u: URL) async -> String? {
        #if canImport(Speech)
        let izin = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard izin == .authorized, let r = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")), r.isAvailable else { return nil }
        let q = SFSpeechURLRecognitionRequest(url: u)
        if r.supportsOnDeviceRecognition { q.requiresOnDeviceRecognition = true }
        q.shouldReportPartialResults = false
        q.addsPunctuation = true
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let kilit = NSLock()
            var bitti = false
            func son(_ s: String?) {
                kilit.lock(); defer { kilit.unlock() }
                guard !bitti else { return }
                bitti = true; c.resume(returning: s)
            }
            _ = r.recognitionTask(with: q) { sonuc, hata in
                _ = r   // tanıyıcı iş bitene dek yaşasın
                if let s = sonuc, s.isFinal { son(s.bestTranscription.formattedString) }
                else if hata != nil { son(sonuc?.bestTranscription.formattedString) }
            }
        }
        #else
        return nil
        #endif
    }
}

struct SesleYaz: View {
    @EnvironmentObject var depo: Depo
    @Binding var metin: String
    @Binding var dosya: URL?
    var renk: Color = Tema.vurgu
    @StateObject private var ses = SesKayit()
    @State private var cevriliyor = false
    @State private var uyari: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { Task { await dokun() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: ses.hal == .kayit ? "stop.fill" : "mic.fill")
                        Text(ses.hal == .kayit ? "Bitir · \(SesKayit.sureYazi(ses.sure))" : (cevriliyor ? "Yazıya çevriliyor…" : "Sesle anlat"))
                            .monospacedDigit()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Capsule().fill(ses.hal == .kayit ? Tema.uyari : renk.opacity(0.14)))
                    .foregroundStyle(ses.hal == .kayit ? Color.white : renk)
                }
                .buttonStyle(.plain)
                .disabled(cevriliyor)
                if ses.hal == .kayit {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(ses.seviyeler.suffix(30).enumerated()), id: \.offset) { _, s in
                            Capsule().fill(Tema.uyari.opacity(0.7)).frame(width: 2.5, height: max(3, CGFloat(s) * 26))
                        }
                    }
                    .frame(height: 28)
                } else if cevriliyor {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            if let uyari { Text(uyari).font(.footnote).foregroundStyle(Tema.uyari) }
        }
    }

    private func dokun() async {
        if ses.hal == .kayit {
            ses.durdur()
            guard let u = ses.dosya else { return }
            dosya = u
            cevriliyor = true
            let y = await Dokum.yaziya(u)
            cevriliyor = false
            if let y, !y.isEmpty {
                metin = metin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? y : metin + " " + y
                uyari = nil
            } else {
                uyari = "Yazıya çevrilemedi (konuşma tanıma izni ya da Türkçe paketi yok). Ses saklandı; Mac'te Whisper döker."
            }
        } else {
            uyari = nil
            await ses.baslat(klasor: depo.sesKlasoru)
            if case .hata(let h) = ses.hal { uyari = h }
            if ses.hal == .izinYok { uyari = "Mikrofon izni yok: Ayarlar › Teoria › Mikrofon." }
        }
    }
}
