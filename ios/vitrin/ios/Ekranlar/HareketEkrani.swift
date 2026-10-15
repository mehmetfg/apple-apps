// Hareket: kilit ekranında oynayan duvar = Live Photo. İki yol: kendi videon ya da Vitrin'in hareketli zemini.
import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct Film: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { gelen in
            let hedef = FileManager.default.temporaryDirectory.appendingPathComponent("kaynak-\(UUID().uuidString.prefix(6)).\(gelen.file.pathExtension)")
            try? FileManager.default.removeItem(at: hedef)
            try FileManager.default.copyItem(at: gelen.file, to: hedef)
            return Film(url: hedef)
        }
    }
}

struct HareketEkrani: View {
    @EnvironmentObject var m: Merkez
    @State private var secim: PhotosPickerItem?
    @State private var film: URL?
    @State private var filmSure: Double = 0
    @State private var bas: Double = 0
    @State private var sure: Double = 3
    @State private var oynatici: AVPlayer?
    @State private var zeminDuvar: Duvar.ID?
    @State private var calisiyor = false
    @State private var ilerleme: Double = 0
    @State private var hata: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Kilit ekranında hareket yalnız Live Photo ile olur: telefonu uyandırınca ya da ekrana basılı tutunca oynar.")
                        .font(.footnote).foregroundStyle(Renkler.ikincil)
                    zeminKarti
                    videoKarti
                    if let hata { Text(hata).font(.footnote).foregroundStyle(.orange) }
                    nasil
                    widgetNotu
                }
                .padding(16)
            }
            .background(Renkler.zemin)
            .navigationTitle("Hareket")
            .overlay {
                if calisiyor {
                    VStack(spacing: 12) {
                        ProgressView(value: ilerleme).frame(width: 200)
                        Text("Live Photo hazırlanıyor…").font(.footnote)
                    }
                    .padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .onChange(of: secim) { _, yeni in yukle(yeni) }
        }
    }

    // MARK: hareketli zemin
    private var seciliDuvar: Duvar? {
        m.kayit.duvarlar.first { $0.id == zeminDuvar } ?? m.gunlukDuvar()
    }

    private var zeminKarti: some View {
        Kart {
            VStack(alignment: .leading, spacing: 14) {
                Label("Hareketli zemin", systemImage: "circle.hexagongrid.fill").font(.headline)
                Text("Duvar tasarımın kendi içinde akar: mesh dalgalanır, desen kayar, yıldızlar parlar, fotoğraf yavaşça yaklaşır. Yazı yerinde kalır.")
                    .font(.footnote).foregroundStyle(Renkler.ikincil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(m.kayit.duvarlar) { d in
                            Button { zeminDuvar = d.id } label: {
                                VStack(spacing: 4) {
                                    DuvarGorunum(duvar: d, g: m.gosterilen(d), fotoBoyu: 400)
                                        .frame(width: 58, height: 126)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(seciliDuvar?.id == d.id ? Renkler.vurgu : Renkler.cizgi, lineWidth: 2))
                                    Text(d.ad).font(.caption2).lineLimit(1).frame(width: 66)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let d = seciliDuvar {
                    HStack {
                        Spacer()
                        Canli(acik: true, sure: 3) { faz in
                            Telefon(yukseklik: 320) { u in
                                ZStack {
                                    DuvarGorunum(duvar: d, g: m.gosterilen(d), faz: faz, fotoBoyu: 1200)
                                    KilitKatmani(u: u)
                                }
                            }
                        }
                        Spacer()
                    }
                    Button { zemindenUret(d) } label: {
                        Label("Live Photo yap · Fotoğraflar'a kaydet", systemImage: "livephoto").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Renkler.vurgu).foregroundStyle(.black)
                    .disabled(calisiyor)
                }
            }
        }
    }

    // MARK: videodan
    private var videoKarti: some View {
        Kart {
            VStack(alignment: .leading, spacing: 14) {
                Label("Kendi videondan", systemImage: "video").font(.headline)
                Text("Videodan en çok 3 saniyelik bir kesit seçilir, dikey ekrana kırpılır.").font(.footnote).foregroundStyle(Renkler.ikincil)
                PhotosPicker(selection: $secim, matching: .videos) {
                    Label(film == nil ? "Video seç" : "Başka video", systemImage: "film.stack")
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Renkler.kart2))
                }
                .buttonStyle(.plain)
                if let oynatici, film != nil {
                    HStack {
                        Spacer()
                        VideoPlayer(player: oynatici)
                            .aspectRatio(Cizer.ekran.width / Cizer.ekran.height, contentMode: .fit)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .disabled(true)
                        Spacer()
                    }
                    Kaydirici(ad: "Başlangıç", deger: $bas, aralik: 0...max(0.01, filmSure - sure), bicim: { String(format: "%.1f sn", $0) })
                        .onChange(of: bas) { _, _ in dongu() }
                    Picker("Süre", selection: $sure) {
                        Text("1,5 sn").tag(1.5); Text("2 sn").tag(2.0); Text("3 sn").tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: sure) { _, _ in bas = min(bas, max(0, filmSure - sure)); dongu() }
                    Button { videodanUret() } label: {
                        Label("Live Photo yap · Fotoğraflar'a kaydet", systemImage: "livephoto").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Renkler.vurgu).foregroundStyle(.black)
                    .disabled(calisiyor)
                }
            }
        }
    }

    private var nasil: some View {
        Kart {
            VStack(alignment: .leading, spacing: 8) {
                Label("Kilit ekranına koymak", systemImage: "lock.iphone").font(.headline)
                Group {
                    Text("1. Kilit ekranına basılı tut › **+** › **Fotoğraflar**")
                    Text("2. Albümlerde **Live Photos**'u aç, Vitrin'in kaydettiğini seç")
                    Text("3. Sol alttaki **▶︎ Live Photo** düğmesi açık olsun › **Ekle**")
                    Text("Düğme soluk görünürse iOS o kesiti oynatmaya uygun bulmamıştır; daha kısa (1,5–2 sn) kesitle yeniden dene.")
                        .foregroundStyle(Renkler.ikincil)
                }
                .font(.footnote)
            }
        }
    }

    private var widgetNotu: some View {
        Kart {
            VStack(alignment: .leading, spacing: 8) {
                Label("Widget'larda hareket", systemImage: "square.grid.2x2").font(.headline)
                Text("iOS widget'ı sürekli oynatmaz; Vitrin widget'ları şu anlarda hareket eder: kelime ya da alıntı değişirken aşağıdan kayar, göz düğmesiyle anlam açılır, saat saniye saniye işler, geri sayım rakamı yuvarlanır.")
                    .font(.footnote).foregroundStyle(Renkler.ikincil)
            }
        }
    }

    // MARK: işler
    private func yukle(_ s: PhotosPickerItem?) {
        guard let s else { return }
        hata = nil
        Task {
            do {
                guard let f = try await s.loadTransferable(type: Film.self) else { return }
                let d = try await AVURLAsset(url: f.url).load(.duration).seconds
                film = f.url; filmSure = d; bas = 0; sure = min(3, max(1.5, d))
                oynatici = AVPlayer(url: f.url)
                oynatici?.isMuted = true
                dongu()
            } catch { hata = "Video açılamadı: \(error.localizedDescription)" }
            secim = nil
        }
    }

    private func dongu() {
        guard let o = oynatici else { return }
        o.seek(to: CMTime(seconds: bas, preferredTimescale: 600))
        o.play()
        let son = CMTime(seconds: bas + sure, preferredTimescale: 600)
        o.currentItem?.forwardPlaybackEndTime = son
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: o.currentItem, queue: .main) { _ in
            o.seek(to: CMTime(seconds: bas, preferredTimescale: 600)); o.play()
        }
    }

    private func videodanUret() {
        guard let film else { return }
        calisiyor = true; ilerleme = 0.3; hata = nil
        let boy = CanliFoto.hedefBoy
        Task {
            do {
                let (f, v) = try await CanliFoto.videodan(film, bas: bas, sure: sure, boy: boy)
                ilerleme = 0.9
                try await Fotograflar.canliKaydet(foto: f, video: v)
                m.duyur("Live Photo Fotoğraflar'da")
            } catch { hata = error.localizedDescription }
            calisiyor = false
        }
    }

    private func zemindenUret(_ d: Duvar) {
        calisiyor = true; ilerleme = 0; hata = nil
        Task {
            do {
                let (f, v) = try await CanliFoto.zeminden(d, g: m.gosterilen(d)) { ilerleme = $0 * 0.95 }
                try await Fotograflar.canliKaydet(foto: f, video: v)
                m.duyur("Live Photo Fotoğraflar'da")
            } catch { hata = error.localizedDescription }
            calisiyor = false
        }
    }
}
