// Her sabah otomatik duvar: iOS duvar kâğıdını uygulamaların ayarlamasına izin vermez, Kestirmeler'e verir.
// Vitrin bir eylem sunar ("Günün duvarını üret"); otomasyon onu "Duvar Kâğıdı Fotoğrafını Ayarla"ya bağlar.
import AppIntents
import SwiftUI

struct GununDuvariNiyeti: AppIntent {
    static var title: LocalizedStringResource = "Günün duvarını üret"
    static var description = IntentDescription("Vitrin'in bugünkü duvar kâğıdını (günlük listedeki sıradaki tasarım + günün içeriği) görsel olarak verir. 'Duvar Kâğıdı Fotoğrafını Ayarla' eylemine bağla.")
    static var openAppWhenRun = false

    @Parameter(title: "Gün kaydır", description: "0 bugün, 1 yarın", default: 0) var kaydir: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let tarih = Calendar.current.date(byAdding: .day, value: kaydir, to: .now) ?? .now
        guard let (img, d) = Cizer.gununDuvari(tarih: tarih), let veri = img.jpegData(compressionQuality: 0.95) else {
            throw NiyetHatasi.tasarimYok
        }
        let ad = "vitrin-\(Secici.gunAnahtari(tarih)).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ad)
        try veri.write(to: url, options: .atomic)
        Depo.ayar.set(Date.now.timeIntervalSince1970, forKey: "sonKestirme")
        Depo.ayar.set(d.ad, forKey: "sonKestirmeAd")
        return .result(value: IntentFile(fileURL: url, filename: ad, type: .jpeg))
    }
}

enum NiyetHatasi: Error, CustomLocalizedStringResourceConvertible {
    case tasarimYok
    var localizedStringResource: LocalizedStringResource { "Vitrin'de duvar tasarımı yok. Uygulamada bir tema ekle." }
}

struct VitrinKestirmeleri: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GununDuvariNiyeti(),
                    phrases: ["\(.applicationName) günün duvarı", "\(.applicationName) duvarını üret"],
                    shortTitle: "Günün duvarı",
                    systemImageName: "photo.on.rectangle.angled")
    }
}

struct KestirmeRehberi: View {
    @EnvironmentObject var m: Merkez
    @Environment(\.dismiss) var kapat
    @Environment(\.openURL) var ac

    private let adimlar: [(String, String)] = [
        ("app.connected.to.app.below.fill", "**Kestirmeler** › alttan **Otomasyon** › sağ üstte **+** › **Günün Saati** › 06:00 · **Her Gün** · **Hemen Çalıştır** › İleri"),
        ("plus.square.on.square", "**Yeni Boş Otomasyon** › **İşlem Arayın**'a \"Vitrin\" yaz › **Günün duvarını üret**"),
        ("photo.on.rectangle", "Yine **İşlem Arayın** › \"duvar\" yaz › **Duvar Kâğıdı Fotoğrafını Ayarla**. Fotoğraf yerine kendiliğinden \"Günün duvarını üret\" gelir."),
        ("lock.iphone", "Mavi **Kilitli Ekran ve Ana Ekran** yazısına dokun: yalnız kilit ekranı istiyorsan **Kilitli Ekran**'ı seç."),
        ("slider.horizontal.3", "Satır sonundaki **⌄** okuna dokun › **Önizlemeyi Göster** kapalı (yoksa her sabah onay bekler) · **Nesneye Kadar Kırp** kapalı · **Okunurluk Bulanıklığı** kapalı › **Bitti**"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bir kez kurulur; sonra her sabah günlük listedeki sıradaki tasarım, günün kelimesi/alıntısıyla kilit ekranına gelir.")
                        .foregroundStyle(Renkler.ikincil)
                    ForEach(adimlar.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle().fill(Renkler.vurgu).frame(width: 30, height: 30)
                                Text("\(i + 1)").font(.subheadline.bold()).foregroundStyle(.black)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Image(systemName: adimlar[i].0).foregroundStyle(Renkler.vurgu)
                                Text(.init(adimlar[i].1)).font(.subheadline)
                            }
                        }
                    }
                    Kart {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Bilmekte yarar var").font(.subheadline.weight(.semibold))
                            Text("• Duvar kâğıdı odağına (Focus) bağlıysa eylem o anki duvarı değiştirir.\n• Yeni bir duvar çifti oluşmaz; mevcut kilit ekranının fotoğrafı değişir, widget'lar yerinde kalır.\n• Günlük listede birden çok tasarım varsa her gün sıradakine geçer (Duvar sekmesi › basılı tut › Günlük listeye ekle).")
                                .font(.footnote).foregroundStyle(Renkler.ikincil)
                        }
                    }
                    if let son = Depo.ayar.object(forKey: "sonKestirme") as? Double {
                        Label("Son çalışma: \(Date(timeIntervalSince1970: son).formatted(date: .abbreviated, time: .shortened)) · \(Depo.ayar.string(forKey: "sonKestirmeAd") ?? "")",
                              systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.green)
                    } else {
                        Label("Kestirme henüz hiç çalışmadı", systemImage: "circle.dashed").font(.footnote).foregroundStyle(Renkler.ikincil)
                    }
                }
                .padding(20)
            }
            .background(Renkler.zemin)
            .navigationTitle("Her sabah yeni duvar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { kapat() } } }
            .safeAreaInset(edge: .bottom) {
                Button { if let u = URL(string: "shortcuts://") { ac(u) } } label: {
                    Label("Kestirmeler'i aç", systemImage: "arrow.up.forward.app").fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Renkler.vurgu)).foregroundStyle(.black)
                }
                .padding(16).background(.ultraThinMaterial)
            }
        }
    }
}
