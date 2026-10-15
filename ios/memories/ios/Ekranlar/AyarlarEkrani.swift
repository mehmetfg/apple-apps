// Ayarlar: vault klasörü · bildirimler (hepsi burada — kullanıcı kararı) · oynatma · hakkında.
import SwiftUI
import UniformTypeIdentifiers

struct AyarlarEkrani: View {
    @EnvironmentObject var depo: Depo
    @State private var klasorSec = false
    @State private var izin: Bildirim.Izin = .sorulmadi
    @State private var paketAcik = Bildirim.paketAcik
    @State private var paketZaman = Calendar.current.date(bySettingHour: Bildirim.paketSaat, minute: Bildirim.paketDakika, second: 0, of: Date()) ?? Date()
    @State private var aksamAcik = Bildirim.aksamAcik
    @State private var aksamSaat = Bildirim.aksamSaat
    @State private var cozumAcik = Bildirim.cozumAcik
    @State private var sesli = Bildirim.sesli

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label(depo.kasa.bagli ? depo.kasa.klasorAdi : "Bağlı değil", systemImage: depo.kasa.bagli ? "folder.fill" : "folder.badge.questionmark")
                        Spacer()
                        Button(depo.kasa.bagli ? "Değiştir" : "Seç") { klasorSec = true }
                    }
                    Button {
                        Task { await depo.esitleSimdi() }
                    } label: {
                        HStack {
                            Label("Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if depo.esitleniyor { ProgressView() }
                            else if let s = depo.sonEsitleme { Text(Tarih.gorece(s)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(!depo.kasa.bagli)
                    if let h = depo.kasa.hata { Text(h).font(.caption).foregroundStyle(.red) }
                } header: { Text("Vault") } footer: {
                    Text("iCloud Drive › Obsidian › Personel Data Management klasörünü seç. Paketler 01 - English Learning/oncalisma/paket'ten iner; kayıtların ve olayların oraya gider. Bağlı olmasa da indirilen paketler çevrimdışı çalışır.")
                }

                Section {
                    if izin == .reddedildi {
                        Button("Bildirim izni kapalı — Ayarlar'ı aç") {
                            if let u = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(u) }
                        }
                    }
                    Toggle(isOn: $paketAcik) {
                        VStack(alignment: .leading) {
                            Text("Paket hazır")
                            Text("Her paket için en fazla bir kez; dinlemeye başladıysan gelmez.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if paketAcik {
                        DatePicker("Saat", selection: $paketZaman, displayedComponents: .hourAndMinute)
                    }
                    Toggle(isOn: $aksamAcik) {
                        VStack(alignment: .leading) {
                            Text("Akşam hatırlatması")
                            Text("O gün paket hiç açılmadıysa, yalnız o gün.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if aksamAcik {
                        Picker("Saat", selection: $aksamSaat) {
                            ForEach(17..<23) { Text(String(format: "%02d:00", $0)).tag($0) }
                        }
                    }
                    Toggle(isOn: $cozumAcik) {
                        VStack(alignment: .leading) {
                            Text("Çözüm geldi")
                            Text("Mac'te yazdığın günün çözümü telefona inince.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Sesli", isOn: $sesli)
                    Button("Deneme bildirimi gönder") { Task { if await Bildirim.izinIste() { await Bildirim.dene() }; izin = await Bildirim.izin() } }
                } header: { Text("Bildirimler") } footer: {
                    Text("Seri, kaçırılan gün sayacı ve tekrarlanan hatırlatma yok.")
                }

                Section("Oynatma") {
                    Picker("Varsayılan hız", selection: $depo.hiz) {
                        ForEach([0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { h in
                            Text(String(format: "%.1f×", h).replacingOccurrences(of: ".", with: ",")).tag(h)
                        }
                    }
                    Toggle("Dokunsal geri bildirim", isOn: $depo.haptik)
                }

                Section("Akış") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("① Çalış — telefonda: dinle, ekrandan oku, kendi sesinle oku", systemImage: "iphone")
                        Label("② Yaz — Mac'te Cümle Tezgâhı (sıra aynı)", systemImage: "laptopcomputer")
                        Label("③ Çözümle — ertesi sabah, yazım + okuma", systemImage: "sparkles")
                    }
                    .font(.callout)
                    Text("Paket bir gün önce sabah hazır olur. Çantada en fazla bir paket bekler; birikme yok.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ayarlar")
            .fileImporter(isPresented: $klasorSec, allowedContentTypes: [.folder]) { r in
                if case .success(let u) = r {
                    depo.kasa.klasorSecildi(u)
                    Task { await depo.esitleSimdi() }
                }
            }
            .task { izin = await Bildirim.izin() }
            .onChange(of: paketAcik) { _, v in Bildirim.paketAcik = v; yenidenPlanla() }
            .onChange(of: paketZaman) { _, v in
                let c = Calendar.current.dateComponents([.hour, .minute], from: v)
                Bildirim.paketSaat = c.hour ?? 8; Bildirim.paketDakika = c.minute ?? 30; yenidenPlanla()
            }
            .onChange(of: aksamAcik) { _, v in Bildirim.aksamAcik = v; yenidenPlanla() }
            .onChange(of: aksamSaat) { _, v in Bildirim.aksamSaat = v; yenidenPlanla() }
            .onChange(of: cozumAcik) { _, v in Bildirim.cozumAcik = v }
            .onChange(of: sesli) { _, v in Bildirim.sesli = v; yenidenPlanla() }
        }
    }

    private func yenidenPlanla() {
        Task { await Bildirim.planla(depo); izin = await Bildirim.izin() }
    }
}
