import SwiftUI

struct AyarlarEkrani: View {
    @EnvironmentObject var m: Merkez
    @Environment(\.dismiss) var kapat
    @State private var secici = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if m.bagli {
                        LabeledContent("Klasör", value: m.klasorAdi)
                        Button { Task { await m.tazele() } } label: {
                            HStack { Label("Şimdi tazele", systemImage: "arrow.clockwise"); if m.yukleniyor { Spacer(); ProgressView() } }
                        }
                        Button("Bağlantıyı kaldır", role: .destructive) { m.unut() }
                    } else {
                        Button { secici = true } label: { Label("Vault klasörünü seç", systemImage: "folder.badge.plus") }
                    }
                } header: { Text("Öğrenme içeriği") } footer: {
                    Text("iCloud Drive › Obsidian › **Personel Data Management**'ı seç. Mac'te `veri/vitrin.py` her pano koşusunda içeriği tazeler; uygulama her açılışta okur. Bağlı değilken kurulumla gelen kopya kullanılır.")
                }
                Section("Durum") {
                    LabeledContent("Üretildi", value: m.veri.uretildi.replacingOccurrences(of: "T", with: " "))
                    LabeledContent("Kelime (Oxford 3000, bilmediklerin)", value: "\(m.veri.kelimeler.count)")
                    LabeledContent("Seviye", value: seviyeOzeti)
                    LabeledContent("Alıntı", value: "\(m.veri.alintilar.count)")
                    LabeledContent("Kavram", value: "\(m.veri.kavramlar.count)")
                    LabeledContent("Ana odak", value: m.veri.odak.ana)
                }
                Section {
                    if m.kayit.bilinen.isEmpty {
                        Text("Henüz yok — bugün kartında ✓ ya da düzenleyicide \"biliyorum\"").foregroundStyle(Renkler.ikincil)
                    }
                    ForEach(m.kayit.bilinen, id: \.self) { w in Text(w) }
                        .onDelete { i in i.map { m.kayit.bilinen[$0] }.forEach(m.bilinenSil) }
                } header: { Text("Bilinen kelimeler (\(m.kayit.bilinen.count))") } footer: {
                    Text("Bunlar duvara ve widget'a bir daha gelmez. Kaydırıp silersen geri döner.")
                }
                Section("Sayılar") {
                    LabeledContent("Duvar tasarımı", value: "\(m.kayit.duvarlar.count)")
                    LabeledContent("Widget tasarımı", value: "\(m.kayit.widgetlar.count)")
                    LabeledContent("Günlük listede", value: "\(m.kayit.gunlukListe.count)")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { kapat() } } }
            .fileImporter(isPresented: $secici, allowedContentTypes: [.folder]) { sonuc in
                if case .success(let u) = sonuc { m.klasorSecildi(u) }
            }
        }
    }

    private var seviyeOzeti: String {
        let s = Dictionary(grouping: m.veri.kelimeler, by: \.c).mapValues(\.count)
        return ["B2", "B1", "A2", "A1"].compactMap { k in s[k].map { "\(k) \($0)" } }.joined(separator: " · ")
    }
}
