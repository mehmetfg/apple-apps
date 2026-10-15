// Ayarlar: zorluk, kür süresi, tema, haptik, bildirimler, vault, merdiveni elle çevirme, cihaz adı.
import SwiftUI
import UniformTypeIdentifiers

struct AyarlarEkrani: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject var kasa: Kasa
    @State private var klasorSec = false
    @State private var bildirimAcik = Bildirim.acik
    @State private var bildirimSayi = Bildirim.gunluk
    @State private var bas = Bildirim.basSaat
    @State private var son = Bildirim.sonSaat
    @State private var aksam = Bildirim.aksam
    @State private var sesli = Bildirim.sesli
    @State private var izin: Bildirim.Izin = .verildi
    @State private var planli = UserDefaults.standard.integer(forKey: "teoria.bildirim.planli")
    @State private var denemeSonuc: String?
    @Environment(\.openURL) private var ac
    @State private var cihaz = Cihaz.ad

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zorluk", selection: $depo.zorlukHam) {
                        ForEach(Zorluk.allCases) { Text($0.ad).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(depo.zorluk.aciklama).font(.footnote).foregroundStyle(.secondary)
                    Picker("Kür süresi", selection: $depo.kurDakika) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) dakika").tag($0) }
                    }
                } header: { Text("Çalışma") } footer: {
                    Text("Bir hat, üç kür üst üste hedef başarıyı tutarsa bir kademe çıkar; çok zorlanırsa sessizce bir kademe iner.")
                }

                Section("Merdiven (elle)") {
                    ForEach(Hat.allCases) { h in
                        Stepper(value: Binding(get: { depo.durum.kademe(h) }, set: { depo.kademeAyarla(h, $0) }), in: 1...6) {
                            HStack {
                                Text(h.ad)
                                Spacer()
                                Text("K\(depo.durum.kademe(h)) · \(Evre.of(depo.durum.kademe(h)).rawValue)")
                                    .foregroundStyle(Tema.hat(h)).font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }

                Section("Görünüm") {
                    Picker("Tema", selection: $depo.temaHam) {
                        ForEach(TemaSecimi.allCases) { Text($0.ad).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(isOn: $depo.haptik) { Label("Dokunsal geri bildirim", systemImage: "hand.tap") }
                        .onChange(of: depo.haptik) { _, a in if a { Dokunus.hafif() } }
                    Toggle("Gökyüzü hareket etsin", isOn: $depo.hareket)
                }

                Section {
                    Toggle(isOn: $bildirimAcik) { Label("Bildirimler", systemImage: "bell.badge") }
                    if bildirimAcik && izin == .reddedildi {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Bildirim izni kapalı", systemImage: "bell.slash").foregroundStyle(Tema.uyari).font(.subheadline.weight(.semibold))
                            Text("iPhone Ayarlar › Teoria › Bildirimler'den açmadan hiçbir bildirim gelmez.").font(.footnote).foregroundStyle(.secondary)
                            #if os(iOS)
                            Button("Ayarlar'ı aç") { if let u = URL(string: UIApplication.openNotificationSettingsURLString) { ac(u) } }
                            #endif
                        }
                    }
                    if bildirimAcik {
                        Toggle(isOn: $sesli) { Label("Sesle gelsin", systemImage: "speaker.wave.2") }
                        Stepper("Günde \(bildirimSayi) bildirim", value: $bildirimSayi, in: 1...8)
                        Stepper("Başlangıç \(bas):00", value: $bas, in: 6...(son - 1))
                        Stepper("Bitiş \(son):00", value: $son, in: (bas + 1)...23)
                        Toggle("Akşam, kür yapılmadıysa bir davet", isOn: $aksam)
                        LabeledContent("Planlı", value: izin == .verildi ? "\(planli) bildirim · 3 gün" : "izin yok")
                        Button {
                            Dokunus.secim()
                            Task {
                                let tamam = await Bildirim.dene(depo)
                                izin = await Bildirim.izin()
                                denemeSonuc = tamam ? "5 saniye içinde gelecek. Kilit ekranında eylemleri dene." : "İzin yok; önce Ayarlar'dan aç."
                                tamam ? Dokunus.basari() : Dokunus.uyari()
                            }
                        } label: { Label("Deneme bildirimi gönder", systemImage: "paperplane") }
                        if let d = denemeSonuc { Text(d).font(.footnote).foregroundStyle(.secondary) }
                    }
                } header: { Text("Bildirimler") } footer: {
                    Text("Ekranda belirir, birikmez. Kilit ekranından: Hatırladım, Bilemedim (cevap ayrıca gelir), kendi cümlenle yaz, favori, tekrar havuzu, yer işareti, sesli yorum.")
                }
                .onChange(of: [bildirimSayi, bas, son]) { _, _ in bildirimKaydet() }
                .onChange(of: bildirimAcik) { _, _ in bildirimKaydet() }
                .onChange(of: aksam) { _, _ in bildirimKaydet() }
                .onChange(of: sesli) { _, _ in bildirimKaydet() }
                .task { await izinTazele() }

                Section {
                    LabeledContent("Vault", value: kasa.bagli ? kasa.klasorAdi : "bağlı değil")
                    if let s = depo.sonEsitleme { LabeledContent("Son eşitleme", value: Tarih.goreli(s)) }
                    #if os(iOS)
                    Button(kasa.bagli ? "Klasörü değiştir" : "Vault klasörünü seç") { klasorSec = true }
                    #endif
                    Button(depo.guncelleniyor ? "Güncelleniyor…" : "Akışı güncelle") { Task { await depo.guncelle() } }
                        .disabled(depo.guncelleniyor)
                    Button("Şimdi eşitle") { Task { await depo.esitleSimdi() } }.disabled(!kasa.bagli || depo.esitleniyor)
                    if let h = kasa.hata { Text(h).font(.footnote).foregroundStyle(Tema.uyari) }
                    if depo.bozukSatir > 0 {
                        Text("\(depo.bozukSatir) bozuk satır atlandı (yarım yazılmış olabilir); kalan her şey okundu.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Eşitleme") } footer: {
                    Text("iCloud Drive › Obsidian › Personel Data Management klasörünü seç. Her cihaz yalnız kendi günlüğüne yazar (ilerleme/\(Cihaz.ad).jsonl); çakışma olmaz. Vault bağlı olmasa da uygulama tam çalışır.")
                }

                Section {
                    TextField("Cihaz adı", text: $cihaz)
                        .onSubmit {
                            let a = Dil.dosyaAdi(cihaz)
                            UserDefaults.standard.set(a, forKey: Cihaz.anahtar); cihaz = a
                        }
                } header: { Text("Bu cihaz") } footer: {
                    Text("İş Mac'i ile ev Mac'i ayrı adla yazar (örn. mac-is, mac-ev). Adı değiştirmek eski kayıtları silmez.")
                }

                Section("Hakkında") {
                    LabeledContent("Kart paketi", value: depo.paket.surum)
                    LabeledContent("Akış", value: "\(depo.akis.isaretler.count) işaret · \(depo.akis.surum)")
                    LabeledContent("Olay", value: "\(depo.olaylar.count)")
                    LabeledContent("Kür", value: "\(depo.durum.kurlar.count)")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Ayarlar")
            .fileImporter(isPresented: $klasorSec, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r { kasa.klasorSecildi(u); Task { await depo.esitleSimdi() } }
            }
            .onChange(of: depo.zorlukHam) { _, _ in depo.yenidenHesapla(); depo.widgetYaz() }
            .onChange(of: depo.kurDakika) { _, _ in depo.widgetYaz() }
        }
    }

    private func bildirimKaydet() {
        Bildirim.acik = bildirimAcik; Bildirim.gunluk = bildirimSayi
        Bildirim.basSaat = bas; Bildirim.sonSaat = son; Bildirim.aksam = aksam; Bildirim.sesli = sesli
        Task {
            if bildirimAcik { _ = await Bildirim.izinIste() }
            await Bildirim.planla(depo)
            await izinTazele()
        }
    }

    private func izinTazele() async {
        izin = await Bildirim.izin()
        planli = UserDefaults.standard.integer(forKey: "teoria.bildirim.planli")
    }
}
