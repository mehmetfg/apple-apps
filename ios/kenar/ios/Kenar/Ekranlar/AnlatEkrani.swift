// Anlat: Feynman dakikası. Kitabı kapat, 60 saniye sesli anlat. Telefon önce kendi içinde yazıya döker (ağa gitmez) ve
// hangi kanıtı atladığını hemen gösterir; gece Mac Whisper ile yeniden döker, istenirse Claude dört maddelik not düşer.
import AVFoundation
import Speech
import SwiftUI

struct AnlatEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @StateObject private var kayitci = Kayitci()
    @State private var hedef: String = ""          // "b:<bölüm>" | "k:<kitap>"
    @State private var secili: Anlatim?

    private var hedefAdi: String {
        if hedef.hasPrefix("b:"), let b = merkez.d.metin?.bolumler.first(where: { $0.id == hedef.dropFirst(2) }) { return "§\(b.no) \(b.baslik)" }
        if hedef.hasPrefix("k:") { return merkez.d.oturumlar.last { $0.kitap == hedef.dropFirst(2) }?.kitapAdi ?? "kitap" }
        return "seç"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hedefSecici
                    if let b = seciliBolum { Text(b.iddia).font(.serif(16).italic()).foregroundStyle(Color.soluk).multilineTextAlignment(.center) }
                    dugme
                    Text(kayitci.kayitta ? "Anlat. Kitaba bakma." : "Dokun: 60 saniye başlar. Erken bitirmek için yine dokun.")
                        .font(.footnote).foregroundStyle(Color.soluk)
                    if let h = kayitci.hata { Text(h).font(.footnote).foregroundStyle(.red) }
                    gecmis
                }
                .padding(20)
            }
            .kagitZemin()
            .navigationTitle("Feynman dakikası")
            .sheet(item: $secili) { AnlatimDetayi(an: $0) }
        }
        .onAppear { hedefiKur() }
        .onChange(of: rota.anlatBolum) { _, _ in hedefiKur() }
        .onChange(of: rota.anlatKitap) { _, _ in hedefiKur() }
    }

    private var seciliBolum: Bolum? { hedef.hasPrefix("b:") ? merkez.d.metin?.bolumler.first { $0.id == hedef.dropFirst(2) } : nil }

    private func hedefiKur() {
        if let b = rota.anlatBolum { hedef = "b:" + b; rota.anlatBolum = nil }
        else if let k = rota.anlatKitap { hedef = "k:" + k; rota.anlatKitap = nil }
        else if hedef.isEmpty, let b = merkez.d.metin?.bolumler.first(where: { !$0.bitti }) { hedef = "b:" + b.id }
    }

    private var hedefSecici: some View {
        Menu {
            Section("Bölüm") {
                ForEach(merkez.d.metin?.bolumler ?? []) { b in Button("§\(b.no) \(b.baslik)") { hedef = "b:" + b.id } }
            }
            let kitaplar = Array(Dictionary(merkez.d.oturumlar.map { ($0.kitap, $0) }, uniquingKeysWith: { _, y in y }).values).sorted { $0.baslangic > $1.baslangic }.prefix(5)
            if !kitaplar.isEmpty {
                Section("Son okuduğun") { ForEach(kitaplar) { o in Button(o.kitapAdi) { hedef = "k:" + o.kitap } } }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Anlatılan:").foregroundStyle(Color.soluk)
                Text(hedefAdi).foregroundStyle(Color.murekkep).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption)
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Color.kart))
        }
        .disabled(kayitci.kayitta)
    }

    private var dugme: some View {
        Button {
            if kayitci.kayitta { kayitci.bitir() } else {
                let id = Kimlik.yeni()
                let bolum = hedef.hasPrefix("b:") ? String(hedef.dropFirst(2)) : nil
                let kitap = hedef.hasPrefix("k:") ? String(hedef.dropFirst(2)) : nil
                Task {
                    await kayitci.baslat(id: id, sinir: 60) { sure in
                        merkez.anlatimEkle(id: id, sure: sure, bolum: bolum, kitap: kitap)
                        Task {
                            if let metin = await Kayitci.cihazdaDok(Depo.sesKlasoru.appendingPathComponent(id + ".m4a")) {
                                merkez.onDokumYaz(id, metin)
                            }
                            secili = merkez.d.anlatimlar.first { $0.id == id }
                        }
                    }
                }
            }
        } label: {
            ZStack {
                Halka(oran: kayitci.gecen / 60, renk: .kalem, kalinlik: 10).frame(width: 210, height: 210)
                Circle().fill(kayitci.kayitta ? Color.kalem : Color.kart).frame(width: 170, height: 170)
                    .shadow(color: Color.kalem.opacity(kayitci.kayitta ? 0.35 : 0.1), radius: 18 + kayitci.seviye * 30)
                VStack(spacing: 4) {
                    Image(systemName: kayitci.kayitta ? "stop.fill" : "mic.fill").font(.system(size: 40, weight: .semibold))
                    Text(kayitci.kayitta ? "\(max(0, 60 - Int(kayitci.gecen)))" : "60 sn").font(.system(size: 22, weight: .semibold, design: .serif)).monospacedDigit()
                }
                .foregroundStyle(kayitci.kayitta ? .white : Color.kalem)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .heavy), trigger: kayitci.kayitta)
        .disabled(hedef.isEmpty)
    }

    private var gecmis: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !merkez.d.anlatimlar.isEmpty { Text("Anlatımların").font(.headline) }
            ForEach(merkez.d.anlatimlar.reversed()) { an in
                Button { secili = an } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ad(an)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.murekkep)
                            Text("\(an.tarih.formatted(date: .abbreviated, time: .shortened)) · \(Int(an.sure)) sn · \(an.durum)").font(.caption).foregroundStyle(Color.soluk)
                        }
                        Spacer()
                        if !an.atlanan.isEmpty || !an.kapsanan.isEmpty {
                            Text("\(an.kapsanan.count)/\(an.kapsanan.count + an.atlanan.count)").font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(an.atlanan.isEmpty ? .green : Color.kalem)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                }
                .buttonStyle(.plain)
                .contextMenu { Button(role: .destructive) { merkez.anlatimSil(an.id) } label: { Label("Sil", systemImage: "trash") } }
            }
        }
    }

    private func ad(_ an: Anlatim) -> String {
        if let b = an.bolum, let x = merkez.d.metin?.bolumler.first(where: { $0.id == b }) { return "§\(x.no) \(x.baslik)" }
        if let k = an.kitap { return merkez.d.oturumlar.last { $0.kitap == k }?.kitapAdi ?? "Kitap" }
        return "Anlatım"
    }
}

struct AnlatimDetayi: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    let an: Anlatim
    @StateObject private var calar = Calar()

    private var guncel: Anlatim { merkez.d.anlatimlar.first { $0.id == an.id } ?? an }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { calar.degistir(Depo.sesKlasoru.appendingPathComponent(an.id + ".m4a")) } label: {
                        Label(calar.caliyor ? "Durdur" : "Dinle (\(Int(an.sure)) sn)", systemImage: calar.caliyor ? "stop.fill" : "play.fill")
                    }
                }
                let atlanan = merkez.d.isaretler.filter { guncel.atlanan.contains($0.id) }
                let kapsanan = merkez.d.isaretler.filter { guncel.kapsanan.contains($0.id) }
                if !atlanan.isEmpty {
                    Section {
                        ForEach(atlanan) { x in Text(x.metin).font(.serif(14)).lineLimit(4) }
                    } header: { Label("Atladığın kanıtlar · \(atlanan.count)", systemImage: "exclamationmark.circle").foregroundStyle(Color.kalem) }
                      footer: { Text("Kaba ölçü: kanıtın ayırt edici kelimelerinden ikisi anlatımda geçmiyorsa atlanmış sayılır.") }
                }
                if !kapsanan.isEmpty {
                    Section("Anlattıkların · \(kapsanan.count)") { ForEach(kapsanan) { x in Text(x.metin).font(.serif(14)).lineLimit(2).foregroundStyle(Color.soluk) } }
                }
                if let c = guncel.claude {
                    Section("Claude'un notu") { Text(c).font(.callout) }
                }
                Section(guncel.dokum != nil ? "Döküm (Mac · Whisper)" : "Ön döküm (telefon)") {
                    Text(guncel.dokum ?? guncel.onDokum ?? "Henüz yok. Telefonda Türkçe cihaz içi döküm yoksa Mac'in dökümünü bekler.")
                        .font(.serif(15)).foregroundStyle(guncel.dokum ?? guncel.onDokum == nil ? Color.soluk : Color.murekkep)
                }
            }
            .navigationTitle("Anlatım")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
        }
    }
}

// MARK: kayıt

@MainActor
final class Kayitci: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var kayitta = false
    @Published var gecen: Double = 0
    @Published var seviye: Double = 0
    @Published var hata: String?

    private var kaydedici: AVAudioRecorder?
    private var zamanlayici: Timer?
    private var bitince: ((Double) -> Void)?
    private var sinir: Double = 60

    func baslat(id: String, sinir: Double, bitince: @escaping (Double) -> Void) async {
        hata = nil
        guard await AVAudioApplication.requestRecordPermission() else { hata = "Mikrofon izni yok: Ayarlar › Kenar › Mikrofon."; return }
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try s.setActive(true)
            let ayar: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
            let k = try AVAudioRecorder(url: Depo.sesKlasoru.appendingPathComponent(id + ".m4a"), settings: ayar)
            k.isMeteringEnabled = true
            k.delegate = self
            k.record(forDuration: sinir + 30)
            kaydedici = k
        } catch { hata = "Kayıt açılamadı: \(error.localizedDescription)"; return }
        self.bitince = bitince
        self.sinir = sinir
        gecen = 0; kayitta = true
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tik() }
        }
    }

    private func tik() {
        guard let k = kaydedici, kayitta else { return }
        gecen = k.currentTime
        k.updateMeters()
        seviye = Double(max(0, min(1, (k.averagePower(forChannel: 0) + 50) / 50)))
        if gecen >= sinir { bitir() }
    }

    func bitir() {
        guard kayitta, let k = kaydedici else { return }
        let sure = k.currentTime
        k.stop()
        zamanlayici?.invalidate()
        kayitta = false; seviye = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if sure >= 3 { bitince?(sure) } else { hata = "Kayıt çok kısa (3 sn altı) — sayılmadı." }
        bitince = nil
    }

    /// Cihaz içi Türkçe döküm. Cihaz içi destek yoksa nil döner — ses Apple'a gönderilmez; Mac'in dökümü beklenir.
    static func cihazdaDok(_ url: URL) async -> String? {
        let durum = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard durum == .authorized, let t = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR")), t.supportsOnDeviceRecognition else { return nil }
        let istek = SFSpeechURLRecognitionRequest(url: url)
        istek.requiresOnDeviceRecognition = true
        istek.addsPunctuation = true
        istek.contextualStrings = ["Kant", "a priori", "a posteriori", "sentetik", "analitik", "kategori", "kendinde şey", "Kopernik", "numen", "fenomen"]
        return await withCheckedContinuation { c in
            var bitti = false
            t.recognitionTask(with: istek) { sonuc, hata in
                guard !bitti else { return }
                if let sonuc, sonuc.isFinal { bitti = true; c.resume(returning: sonuc.bestTranscription.formattedString) }
                else if hata != nil { bitti = true; c.resume(returning: nil) }
            }
        }
    }
}

@MainActor
final class Calar: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var caliyor = false
    private var oynatici: AVAudioPlayer?

    func degistir(_ url: URL) {
        if caliyor { oynatici?.stop(); caliyor = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        oynatici = try? AVAudioPlayer(contentsOf: url)
        oynatici?.delegate = self
        caliyor = oynatici?.play() ?? false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.caliyor = false }
    }
}
