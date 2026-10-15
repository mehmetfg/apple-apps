// Ayarlar: günlük tempo, bildirimler, ses, widget kipi, vault bağlantısı.
import SwiftUI
import UserNotifications

struct AyarlarEkrani: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var kasa: Kasa
    @Environment(\.dismiss) private var kapat
    @AppStorage("gorunum") private var gorunum = 0
    @State private var ayar = Ayarlar()
    @State private var izin: UNAuthorizationStatus = .notDetermined
    @State private var klasorSec = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $ayar.yeniSayisi, in: 3...25) {
                        satir("Günde yeni kelime", "\(ayar.yeniSayisi)")
                    }
                    Stepper(value: $ayar.pvSayisi, in: 0...10) {
                        satir("Günde yeni deyimsel fiil", ayar.pvSayisi == 0 ? "kapalı" : "\(ayar.pvSayisi)")
                    }
                    Stepper(value: $ayar.tekrarTavani, in: 20...150, step: 10) {
                        satir("Günlük tekrar tavanı", "\(ayar.tekrarTavani)")
                    }
                } header: { Text("Tempo") } footer: {
                    Text("10 yeni kelime ≈ günde 5-8 dakika. Tavanı aşan tekrar ertesi güne kayar; birikmiş borç diye bir şey yok.")
                }

                Section {
                    if izin == .denied {
                        Label("Bildirim izni kapalı — Ayarlar › Aşina'dan aç.", systemImage: "bell.slash")
                            .foregroundStyle(R.yanlis)
                    } else if izin != .authorized && izin != .provisional {
                        Button { Task { _ = await Bildirim.izinIste(); await izinOku(); depo.planla() } } label: {
                            Label("Bildirimlere izin ver", systemImage: "bell.badge")
                        }
                    }
                    Stepper(value: $ayar.bildirimSayisi, in: 0...12) {
                        satir("Günde kelime bildirimi", ayar.bildirimSayisi == 0 ? "kapalı" : "\(ayar.bildirimSayisi)")
                    }
                    if ayar.bildirimSayisi > 0 {
                        Stepper(value: $ayar.bildirimBas, in: 6...(ayar.bildirimSon - 1)) {
                            satir("İlk", "\(ayar.bildirimBas):00")
                        }
                        Stepper(value: $ayar.bildirimSon, in: (ayar.bildirimBas + 1)...23) {
                            satir("Son", "\(ayar.bildirimSon):00")
                        }
                    }
                    Toggle("Akşam hatırlatması", isOn: $ayar.hatirlatma)
                    if ayar.hatirlatma {
                        Stepper(value: $ayar.hatirlatmaSaati, in: 12...23) {
                            satir("Saat", "\(ayar.hatirlatmaSaati):00")
                        }
                    }
                } header: { Text("Gün boyu") } footer: {
                    Text("Kelime bildirimleri sessiz gelir, yalnız ekranda belirir. Uzun bas: \"Biliyordum\" ya da \"Oturumda sor\". Hatırlatma, o günün destesi bittiyse gelmez.")
                }

                Section {
                    Toggle("Önce hatırla", isOn: $ayar.onceHatirla)
                } header: { Text("Widget") } footer: {
                    Text("Açıkken widget anlamı gizler; önce kendin hatırlarsın, sonra göz düğmesiyle açarsın. Ana ekrana eklemek için: boş yere basılı tut › + › Aşina. Kilit ekranına: kilit ekranına basılı tut › Özelleştir.")
                }

                Section("Ses") {
                    Toggle("Oxford kaydı (çevrimiçi)", isOn: $ayar.oxfordSesi)
                    Toggle("Kelimeyi kendiliğinden seslendir", isOn: $ayar.otomatikSes)
                }

                Section {
                    Picker("Görünüm", selection: $gorunum) {
                        Text("Otomatik").tag(0)
                        Text("Açık").tag(1)
                        Text("Koyu").tag(2)
                    }
                }

                Section {
                    if kasa.bagli {
                        LabeledContent("Klasör", value: kasa.klasorAdi)
                        if let s = kasa.sonEslesme {
                            LabeledContent("Son eşitleme", value: s.formatted(.relative(presentation: .named)))
                        }
                        Button { Task { await depo.eslestir() } } label: {
                            Label("Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button("Bağlantıyı kaldır", role: .destructive) { kasa.unut() }
                    } else {
                        Button { klasorSec = true } label: {
                            Label("Vault klasörünü seç", systemImage: "folder.badge.plus")
                        }
                    }
                    if let h = kasa.hata { Text(h).font(.footnote).foregroundStyle(R.yanlis) }
                    LabeledContent("Kelime verisi", value: depo.paketSurum)
                } header: { Text("Vault") } footer: {
                    Text("iCloud Drive › Obsidian › Personel Data Management'ı seç. Uygulama oradan güncel kelime deposunu okur, ilerlemeni `_projects/asina/telefon/ilerleme.json`'a yazar. Bildiğin kelimeler Örgü ve Cümle Tezgâhı'nın havuzundan da düşer.")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { kapat() }.fontWeight(.semibold)
                }
            }
            .fileImporter(isPresented: $klasorSec, allowedContentTypes: [.folder]) { s in
                if case .success(let u) = s {
                    kasa.klasorSecildi(u)
                    Task { await depo.eslestir() }
                }
            }
        }
        .onAppear { ayar = depo.ayar }
        .onChange(of: ayar) { _, y in depo.ayar = y }
        .task { await izinOku() }
    }

    private func izinOku() async {
        izin = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func satir(_ ad: String, _ deger: String) -> some View {
        HStack {
            Text(ad)
            Spacer()
            Text(deger).foregroundStyle(R.ikincil).monospacedDigit()
        }
    }
}
