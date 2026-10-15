// Kenar işleri + Ayarlar (kapı, kulaklık sınaması, aksan, akşam hatırlatması, vault).
import FamilyControls
import SwiftUI

struct KenarIsleriEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota

    var body: some View {
        NavigationStack {
            List {
                if merkez.kenarIsleri.isEmpty {
                    ContentUnavailableView("Kenar'dan iş yok", systemImage: "text.book.closed",
                                           description: Text("Kenar'da bir bölümü \"bitti\" diye işaretleyince buraya düşer: Türkçe paragrafını İngilizce anlatırsın, düzeltilen İngilizce Kenar'a geri gider."))
                }
                ForEach(merkez.kenarIsleri) { x in
                    let kayit = merkez.d.kayitlar.last { $0.kenarIs == x.id }
                    Section {
                        Text(x.iddia).font(.system(size: 15, design: .serif).italic()).foregroundStyle(.secondary)
                        Text(x.paragraf).font(.system(size: 15, design: .serif)).lineLimit(6)
                        if let d = kayit?.duzeltme {
                            Label("İngilizcesi Kenar'a gitti", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.footnote)
                            Text(d).font(.callout)
                        } else if kayit != nil {
                            Label("Anlattın · Mac düzeltecek", systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { rota.kayit = KayitIstegi(tur: .metin, istem: "§\(x.bolumNo) \(x.baslik)", aciklama: x.paragraf, kenarIs: x.id) } label: {
                            Label(kayit == nil ? "İngilizce anlat" : "Yeniden anlat", systemImage: "mic.fill")
                        }
                    } header: { Text("\(x.metin) · §\(x.bolumNo) \(x.baslik)") }
                }
            }
            .navigationTitle("Kenar")
        }
    }
}

struct AyarlarEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @StateObject private var y = Yuruyus.shared
    @State private var kapiAcik = Kapi.acik
    @State private var secim = Kapi.secim
    @State private var secici = false
    @State private var izin = AuthorizationCenter.shared.authorizationStatus
    @State private var izinHatasi: String?
    @State private var tavan = Kapi.tavan
    @AppStorage("aksan") private var aksan = "en-GB"
    @AppStorage("aksamAcik") private var aksamAcik = true
    @AppStorage("aksamSaat") private var aksamSaat = 21
    @State private var klasor = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if izin != .approved {
                        Button("Ekran Süresi iznini ver") {
                            Task {
                                do { try await AuthorizationCenter.shared.requestAuthorization(for: .individual); izinHatasi = nil }
                                catch { izinHatasi = error.localizedDescription }
                                izin = AuthorizationCenter.shared.authorizationStatus
                            }
                        }
                        if let h = izinHatasi { Text(h).font(.caption).foregroundStyle(.red) }
                    } else {
                        Toggle("Kapı açık", isOn: $kapiAcik)
                            .onChange(of: kapiAcik) { _, v in Kapi.acik = v; Kapi.kur(); Kapi.gunlukIzlemeyiKur() }
                        Button { secici = true } label: {
                            LabeledContent("Uygulamalar", value: "\(secim.applicationTokens.count) uygulama · \(secim.categoryTokens.count) kategori")
                        }
                        Stepper("Günde en çok \(tavan) kapı", value: $tavan, in: 1...6).onChange(of: tavan) { _, v in Kapi.tavan = v; Kapi.kur() }
                        LabeledContent("Bugün", value: "\(Kapi.bugun)/\(Kapi.tavan)")
                    }
                } header: { Text("Ekran Süresi kapısı") } footer: {
                    Text("Seçtiğin uygulamayı açınca önce \"tek cümle, İngilizce\" kalkanı çıkar. Söyle ya da geç — ikisinde de 15 dk serbest. Günlük tavandan sonra gün bitene kadar kapalı. Kapatmak tek dokunuş.")
                }
                .familyActivityPicker(isPresented: $secici, selection: $secim)
                .onChange(of: secim) { _, v in Kapi.secim = v; Kapi.kur() }

                Section {
                    Button(y.calisiyor ? "Dinliyor…" : "Sınamayı başlat") { y.dinlemeyiAc() }
                    LabeledContent("Son gelen tuş", value: y.sonKomut)
                } header: { Text("Kulaklık sınaması (FiiO BTR15)") } footer: {
                    Text("Başlat, sonra BTR15'te tuşlara bas: hangisi \"Oynat/Duraklat\" (doğru), hangisi \"İleri\" (yanlış), hangisi \"Geri\" (tekrar) gönderiyor burada görünür. Ses tuşları komut göndermez.")
                }

                Section("Ses") {
                    Picker("Aksan", selection: $aksan) { Text("İngiliz").tag("en-GB"); Text("Amerikan").tag("en-US") }
                    Button("Dene") { Task { await Konusmaci.shared.soyle("Today I went to the office early and had a meeting with my boss.") } }
                }
                Section("Akşam hatırlatması") {
                    Toggle("Her akşam bir anı sor", isOn: $aksamAcik)
                    Stepper("Saat \(aksamSaat):00", value: $aksamSaat, in: 17...23)
                }
                .onChange(of: aksamAcik) { _, v in Merkez.aksamBildirimi(aksamSaat, 0, acik: v) }
                .onChange(of: aksamSaat) { _, v in Merkez.aksamBildirimi(v, 0, acik: aksamAcik) }

                Section {
                    LabeledContent("Vault", value: merkez.bagli ? "bağlı" : "seçilmedi")
                    if let z = merkez.sonEsitleme { LabeledContent("Son eşitleme", value: z.formatted(date: .omitted, time: .shortened)) }
                    if let h = merkez.hata { Text(h).font(.caption).foregroundStyle(.red) }
                    Button("Vault klasörünü seç") { klasor = true }
                    Button("Şimdi eşitle") { Task { await merkez.esitle() } }
                } header: { Text("Vault") } footer: {
                    Text("Kayıtlar \(Merkez.proje)/telefon/'a gider. Mac: ~/.local/share/yanki/.venv/bin/python \"\(Merkez.proje)/veri/ayna.py\" isle")
                }
            }
            .navigationTitle("Ayarlar")
            .fileImporter(isPresented: $klasor, allowedContentTypes: [.folder]) { if case .success(let u) = $0 { merkez.klasorSecildi(u) } }
            .onAppear { Merkez.aksamBildirimi(aksamSaat, 0, acik: aksamAcik) }
        }
    }
}
