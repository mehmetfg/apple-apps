// Ayarlar: metnin başlığı ve sorusu · bildirim saatleri · vault · telefonun kapıları (NFC, Odak, Siri) · Mac komutları.
import SwiftUI

struct AyarlarEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    @State private var baslik = ""
    @State private var soru = ""
    @State private var bildirim = Bildirimci.acik
    @State private var saat1 = Date()
    @State private var saat2 = Date()
    @State private var klasor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Metin") {
                    TextField("Başlık", text: $baslik).font(.serif(17))
                    TextField("Soru", text: $soru, axis: .vertical).font(.serif(16).italic())
                }
                Section {
                    Toggle("Kutu'dan işaret sor", isOn: $bildirim)
                    if bildirim {
                        DatePicker("Öğle", selection: $saat1, displayedComponents: .hourAndMinute)
                        DatePicker("Akşam", selection: $saat2, displayedComponents: .hourAndMinute)
                        Button("Deneme bildirimi (5 sn)") { Bildirimci.deneme() }
                    }
                } header: { Text("Bildirim") } footer: {
                    Text("Günde en çok iki kez, Kutu'nun en ilgili işareti gelir. Bildirime basılı tut: bölüm düğmeleri çıkar, uygulama açılmaz. Sessiz gelir; sayaç ya da seri yok.")
                }
                Section {
                    LabeledContent("Durum", value: merkez.bagli ? "bağlı" : "seçilmedi")
                    if let z = merkez.sonEsitleme { LabeledContent("Son eşitleme", value: z.formatted(date: .omitted, time: .shortened)) }
                    Button("Vault klasörünü yeniden seç") { klasor = true }
                    Button("Şimdi eşitle") { Task { await merkez.esitle() } }
                } header: { Text("Vault") } footer: {
                    Text("Okunan: Teoria'nın akis.json'u (Voice Dream işaretleri), Mac'in anlatım dökümleri. Yazılan: \(Merkez.proje)/telefon/ ve metin/ — Obsidian'da taslak olarak görünür.")
                }
                Section("Telefonun kapıları") {
                    Label("Simgeye basılı tut: Oku · Kamera · Anlat · Kutu", systemImage: "hand.tap")
                    Label("Denetim Merkezi / kilit ekranı: + › Kenar › Okumaya başla · Kamerayla işaretle", systemImage: "switch.2")
                    Label("Siri: “Kenar ile okumaya başla”, “Kenar Feynman dakikası”", systemImage: "mic")
                    Label("NFC ayraç: Kestirmeler › Otomasyon › + › NFC › etiketi okut › eylem: Okumaya başla (Kenar)", systemImage: "wave.3.right")
                    Label("Okuma Odağı: Ayarlar › Odak › odak seç › Odak Süzgeçleri › + › Kenar", systemImage: "moon")
                    Label("Paylaş › Kenar: Kitaplar, Kindle, Safari'den seçilen cümle Kutu'ya düşer", systemImage: "square.and.arrow.up")
                    Label("Spotlight: işaret ve bölümler aramada çıkar", systemImage: "magnifyingglass")
                }
                .font(.footnote)
                Section("Mac") {
                    Text("Anlatımları Whisper ile dök:\n~/.local/share/yanki/.venv/bin/python \"\(Merkez.proje)/veri/kenar.py\" isle\nTeoria'nın sabah akışı bunu arka planda zaten çağırır. Claude notu için Claude Code'da: \"Kenar değerlendir\".")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
                Section("Ayna") {
                    Text("Bitti dediğin bölümler Ayna'nın kuyruğuna gider (ortak dolap: group.com.fatihgocgun.atolye). Ayna İngilizcesini anlattırıp düzeltilmiş paragrafı geri yazar; burada bölümün altında görünür.")
                        .font(.footnote).foregroundStyle(Color.soluk)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kaydet(); kapat() } } }
            .fileImporter(isPresented: $klasor, allowedContentTypes: [.folder]) { if case .success(let u) = $0 { merkez.klasorSecildi(u) } }
            .onAppear {
                baslik = merkez.d.metin?.baslik ?? ""; soru = merkez.d.metin?.soru ?? ""
                let s = Bildirimci.saatler.sorted()
                saat1 = tarih(s.first ?? 750); saat2 = tarih(s.last ?? 1230)
            }
        }
    }

    private func tarih(_ dk: Int) -> Date { Calendar.current.date(bySettingHour: dk / 60, minute: dk % 60, second: 0, of: .now) ?? .now }
    private func dakika(_ d: Date) -> Int { let c = Calendar.current.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }

    private func kaydet() {
        merkez.metinGuncelle(baslik: baslik.isEmpty ? nil : baslik, soru: soru.isEmpty ? nil : soru)
        Bildirimci.acik = bildirim
        Bildirimci.saatler = [dakika(saat1), dakika(saat2)]
        Bildirimci.planla(merkez.d)
    }
}
