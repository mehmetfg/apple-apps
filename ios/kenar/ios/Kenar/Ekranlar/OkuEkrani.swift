// Oku: önce soru, sonra okuma. Oturum açıkken kilit ekranında Canlı Etkinlik (kitap · soru · süre · işaret sayısı) durur.
// Kâğıt kitapta kamerayla cümle seçilir; ISBN barkodu kitabı ekler. Bitince: "kitabı kapat, 60 sn anlat".
import SwiftUI
import VisionKit

struct OkuEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    let odakKipi: Bool

    @State private var secilenKitap: KitapKaydi?
    @State private var soru = ""
    @State private var kamera = false
    @State private var elle = false
    @State private var bitirSorusu = false
    @State private var kitapAdiYaz = false
    @State private var yeniKitapAdi = ""
    @FocusState private var soruOdak: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let o = merkez.d.aktifOturum { aktif(o) } else { basla }
                if odakKipi {
                    Label("Okuma Odağı açık: Kenar yalnız bu ekranı gösteriyor. Odak kapanınca her şey geri gelir.", systemImage: "moon.fill")
                        .font(.footnote).foregroundStyle(Color.soluk)
                }
                gecmis
                ipuclari
            }
            .padding(18)
        }
        .kagitZemin()
        .navigationTitle("Oku")
        .sheet(isPresented: $kamera) { KameraEkrani() }
        .sheet(isPresented: $elle) { ElleIsaret() }
        .onChange(of: rota.kamera) { _, v in if v { kamera = true; rota.kamera = false } }
        .onChange(of: rota.oturumAc) { _, v in if v { soruOdak = true; rota.oturumAc = false } }
        .onAppear {
            if rota.kamera { kamera = true; rota.kamera = false }
            if rota.oturumAc { soruOdak = true; rota.oturumAc = false }
            if soru.isEmpty { soru = merkez.d.metin?.soru ?? "" }
        }
        .alert("Kitabın adı", isPresented: $kitapAdiYaz) {
            TextField("Ör. Saf Aklın Eleştirisi", text: $yeniKitapAdi)
            Button("Ekle") {
                let ad = yeniKitapAdi.trimmingCharacters(in: .whitespaces)
                guard !ad.isEmpty else { return }
                let k = KitapKaydi(id: "kagit-" + Kimlik.yeni(), ad: ad, kagit: true)
                merkez.kitapEkle(k); secilenKitap = k; yeniKitapAdi = ""
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    // MARK: oturum yokken
    private var basla: some View {
        VStack(alignment: .leading, spacing: 14) {
            Baslik(ust: "Okumaya başla", ana: "Hangi soruyla giriyorsun?")
            Menu {
                let kagit = merkez.d.kitaplar.filter(\.kagit)
                if !kagit.isEmpty {
                    Section("Kâğıt kitaplarım") { ForEach(kagit) { k in Button(k.ad) { secilenKitap = k } } }
                }
                Section("Voice Dream") { ForEach(merkez.vdKitaplar.prefix(25)) { k in Button(k.ad) { secilenKitap = k } } }
                Section {
                    Button { kamera = true } label: { Label("ISBN barkoduyla kâğıt kitap ekle", systemImage: "barcode.viewfinder") }
                    Button { kitapAdiYaz = true } label: { Label("Adını yazarak ekle", systemImage: "pencil") }
                }
            } label: {
                HStack {
                    Image(systemName: secilenKitap?.kagit == true ? "book.closed" : "headphones")
                    Text(secilenKitap?.ad ?? "Kitap seç").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .font(.body.weight(.medium)).foregroundStyle(Color.murekkep)
                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.kart))
            }
            TextField("Bu metne hangi soruyla giriyorsun?", text: $soru, axis: .vertical)
                .font(.serif(18).italic()).lineLimit(2...4).focused($soruOdak)
                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.kart))
            Text("Soru, metnin sorusuyla aynı olmak zorunda değil; ama ona hizmet etmeli.").font(.caption).foregroundStyle(Color.soluk)
            Button {
                guard let k = secilenKitap else { return }
                merkez.oturumBaslat(kitap: k, soru: soru.trimmingCharacters(in: .whitespacesAndNewlines))
                soruOdak = false
            } label: { Label("Oturumu aç", systemImage: "book.fill").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(secilenKitap == nil || soru.trimmingCharacters(in: .whitespaces).isEmpty)
            Button { kamera = true } label: { Label("Oturumsuz, kamerayla tek işaret", systemImage: "camera.viewfinder").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
    }

    // MARK: oturum açıkken
    private func aktif(_ o: Oturum) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OKUYORSUN").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(Color.kalem)
            Text(o.kitapAdi).font(.serif(26, .semibold)).foregroundStyle(Color.murekkep)
            Text(o.soru).font(.serif(18).italic()).foregroundStyle(Color.soluk)
            HStack(alignment: .firstTextBaseline) {
                Text(o.baslangic, style: .timer).font(.system(size: 54, weight: .light, design: .serif)).monospacedDigit()
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(o.isaret)").font(.system(size: 34, weight: .semibold, design: .serif))
                    Text("işaret").font(.caption).foregroundStyle(Color.soluk)
                }
            }
            HStack(spacing: 10) {
                Button { kamera = true } label: { Label("Kamerayla", systemImage: "camera.viewfinder").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { elle = true } label: { Label("Elle", systemImage: "pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Button(role: .destructive) { bitirSorusu = true } label: { Label("Oturumu bitir", systemImage: "stop.circle").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .confirmationDialog("Kitabı kapat. 60 saniye anlatmak ister misin?", isPresented: $bitirSorusu, titleVisibility: .visible) {
                    Button("Bitir ve 60 sn anlat") { merkez.oturumuBitir(); rota.anlatKitap = o.kitap; rota.git("kenar://anlat") }
                    Button("Yalnız bitir") { merkez.oturumuBitir() }
                }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.kart))
    }

    private var gecmis: some View {
        let son = merkez.d.oturumlar.filter { $0.bitis != nil }.suffix(6).reversed()
        return Group {
            if !son.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Son oturumlar").font(.headline)
                    ForEach(Array(son)) { o in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.kitapAdi).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(o.soru).font(.caption).foregroundStyle(Color.soluk).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Duration.seconds((o.bitis ?? o.baslangic).timeIntervalSince(o.baslangic)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                    .font(.caption.monospacedDigit())
                                Text("\(o.isaret) işaret").font(.caption2).foregroundStyle(Color.soluk)
                            }
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                    }
                }
            }
        }
    }

    private var ipuclari: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Telefonun öteki kapıları").font(.headline)
            Label("Ayraca NFC etiketi: Kestirmeler › Otomasyon › NFC › “Okumaya başla (Kenar)”. Telefonu dokundurunca oturum açılır.", systemImage: "wave.3.right")
            Label("Okuma Odağı: Ayarlar › Odak › bir odak › Odak Süzgeçleri › Kenar. Odak açıkken yalnız bu ekran.", systemImage: "moon")
            Label("Kitaplar, Kindle, Safari: cümleyi seç › Paylaş › Kenar. Kutu'ya düşer.", systemImage: "square.and.arrow.up")
            Label("Uygulama simgesine basılı tut: Oku · Kamera · Anlat · Kutu.", systemImage: "hand.tap")
        }
        .font(.footnote).foregroundStyle(Color.soluk)
        .padding(14).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cizgi))
    }
}

// MARK: Kamera — Canlı Metin ile satır seç, ya da ISBN barkodu oku

struct KameraEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    @State private var kip = 0
    @State private var secilen: [String] = []
    @State private var metin = ""
    @State private var isbnDurum: String?
    @State private var bulunanKitap: KitapKaydi?

    private var destekli: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $kip) { Text("Cümle").tag(0); Text("ISBN").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                if destekli {
                    Tarayici(kip: kip) { s in
                        if kip == 0 {
                            secilen.append(s); metin = secilen.joined(separator: " "); Haptik.secim()
                        } else { Task { await isbnBul(s) } }
                    }
                    .id(kip)
                    .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Kamera metin tanıma bu cihazda yok", systemImage: "camera.badge.ellipsis",
                                           description: Text("Simülatörde çalışmaz. iPhone'da Canlı Metin açık olmalı (Ayarlar › Genel › Dil ve Bölge › Canlı Metin)."))
                        .frame(maxHeight: .infinity)
                }
                alt
            }
            .navigationTitle(kip == 0 ? "Satırlara dokun" : "Barkodu göster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
        }
    }

    @ViewBuilder private var alt: some View {
        VStack(alignment: .leading, spacing: 10) {
            if kip == 0 {
                Text(merkez.d.aktifOturum.map { "Kaynak: \($0.kitapAdi)" } ?? "Oturum yok — kaynak: kâğıt kitap").font(.caption).foregroundStyle(Color.soluk)
                TextField("Dokunduğun satırlar burada birleşir; düzelt, kırp.", text: $metin, axis: .vertical)
                    .font(.serif(16)).lineLimit(2...6)
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                HStack {
                    Button("Temizle") { secilen = []; metin = "" }.disabled(metin.isEmpty)
                    Spacer()
                    Button {
                        merkez.isaretEkle(metin, kaynak: .kamera, kitap: merkez.d.aktifOturum?.kitap ?? "kagit", kitapAdi: merkez.d.aktifOturum?.kitapAdi ?? "Kâğıt kitap")
                        secilen = []; metin = ""
                    } label: { Label("İşaret yap", systemImage: "bookmark.fill") }
                    .buttonStyle(.borderedProminent).disabled(metin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                if let k = bulunanKitap {
                    Text(k.ad).font(.serif(18, .semibold))
                    if let y = k.yazar { Text(y).font(.footnote).foregroundStyle(Color.soluk) }
                    Button { merkez.kitapEkle(k); kapat() } label: { Label("Kâğıt kitaplarıma ekle", systemImage: "plus").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(isbnDurum ?? "Arka kapaktaki barkodu çerçeveye getir. Bilgi Open Library'den alınır; yalnız ISBN gider.")
                        .font(.footnote).foregroundStyle(Color.soluk)
                }
            }
        }
        .padding()
        .background(Color.kagit)
    }

    private func isbnBul(_ kod: String) async {
        let isbn = kod.filter(\.isNumber)
        guard isbn.count == 13 || isbn.count == 10, bulunanKitap?.isbn != isbn else { return }
        Haptik.orta()
        isbnDurum = "ISBN \(isbn) aranıyor…"
        struct Kayit: Decodable { struct Yazar: Decodable { var name: String? }; var title: String?; var authors: [Yazar]? }
        do {
            let u = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!
            let (veri, _) = try await URLSession.shared.data(from: u)
            let s = try JSONDecoder().decode([String: Kayit].self, from: veri)
            if let k = s["ISBN:\(isbn)"], let ad = k.title {
                bulunanKitap = KitapKaydi(id: "isbn-" + isbn, ad: ad, yazar: k.authors?.compactMap(\.name).joined(separator: ", "), isbn: isbn, kagit: true)
            } else {
                isbnDurum = "Open Library'de yok (ISBN \(isbn)). Oku ekranında \"Adını yazarak ekle\"yi kullan."
                bulunanKitap = nil
            }
        } catch { isbnDurum = "Bağlantı yok: \(error.localizedDescription)" }
    }
}

/// VisionKit DataScanner: satırlar parlar, dokunulan satır seçilir. ISBN kipinde EAN-13 barkodu yakalanır.
struct Tarayici: UIViewControllerRepresentable {
    let kip: Int
    let bulundu: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let diller = ["tr-TR", "en-US", "de-DE", "fr-FR"].filter { DataScannerViewController.supportedTextRecognitionLanguages.contains($0) }
        let tur: Set<DataScannerViewController.RecognizedDataType> = kip == 0
            ? [.text(languages: diller.isEmpty ? [] : diller, textContentType: nil)]
            : [.barcode(symbologies: [.ean13, .ean8])]
        let v = DataScannerViewController(recognizedDataTypes: tur, qualityLevel: kip == 0 ? .accurate : .balanced,
                                          recognizesMultipleItems: kip == 0, isHighFrameRateTrackingEnabled: false,
                                          isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        v.delegate = context.coordinator
        try? v.startScanning()
        return v
    }

    func updateUIViewController(_ v: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Yonetici { Yonetici(self) }

    final class Yonetici: NSObject, DataScannerViewControllerDelegate {
        let ust: Tarayici
        init(_ u: Tarayici) { ust = u }

        func dataScanner(_ d: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let t) = item { ust.bulundu(t.transcript) }
            if case .barcode(let b) = item, let s = b.payloadStringValue { ust.bulundu(s) }
        }

        func dataScanner(_ d: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard ust.kip == 1 else { return }
            for i in items { if case .barcode(let b) = i, let s = b.payloadStringValue { ust.bulundu(s) } }
        }
    }
}
