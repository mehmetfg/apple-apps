// Kılavuz — Orkestra'nın mantığı açık: durumlar, hamle kuralları, göstergeler, görselleştirme sözlüğü, ayarlar.
import SwiftUI

struct KilavuzEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @State private var secici = false
    @State private var izin = false

    var body: some View {
        NavigationStack {
            List {
                Section("Bağlantı") {
                    LabeledContent("Vault", value: merkez.bagli ? merkez.klasorAdi : "seçilmedi")
                    if let d = merkez.durum, let u = d.veri.uretimZamani {
                        LabeledContent("Mac verisi", value: "\(d.veri.makine) · \(Tarih.gorece(u, d.simdi))")
                    }
                    if let s = merkez.sonOkuma { LabeledContent("Son okuma", value: Tarih.gorece(s)) }
                    Button("Vault klasörünü seç", systemImage: "folder") { secici = true }
                    Button("Şimdi tazele", systemImage: "arrow.clockwise") { Task { await merkez.tazele() } }
                    if let h = merkez.hata { Text(h).font(.footnote).foregroundStyle(.red) }
                    if let u = merkez.veri?.uyarilar, !u.isEmpty {
                        ForEach(u, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
                    }
                }
                Section {
                    LabeledContent("Bildirim izni", value: izin ? "açık" : "kapalı")
                    if !izin { Button("İzin ver") { Task { izin = await Bildirimci.izinIste() } } }
                    Button("Deneme bildirimi", systemImage: "bell.badge") { Task { await Bildirimci.deneme() } }
                } header: { Text("Bildirimler · her olayda") } footer: {
                    Text("Olay: bir sürecin gecikti/aksıyor/tıkalı'ya düşmesi ya da toparlanması, sabah görevinin tıkanması, vadeye 7/3/1/0 gün kalması, Mac verisinin 36 saatten eski olması. Aynı olay bir kez gelir. Zamana bağlı olaylar önceden kurulur; 22:30–07:30 arası doğanlar sabaha kayar. Sabah 07:30'da bugünün sırası, 21:00'de ana odak sessizse kapanış. Bildirimdeki \"Yarına bırak\" o süreci 24 saat susturur.")
                }
                Section("Durumlar") {
                    ForEach(Durum.allCases, id: \.self) { d in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Tema.durumSimge(d)).foregroundStyle(Tema.durum(d)).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.ad).font(.system(size: 15, weight: .semibold))
                                Text(d.aciklama).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    kural("1", "Tıkalı boru önce gelir", "Sabah görevi çıktı vermediyse onun beslediği süreçte çalışmak boşa gider. Her zaman ilk sırada.")
                    kural("2", "Ana odak önce", "Yön Belgesi'nin ana odağındaki aksayan süreç +300, bugün dokunulmamış ana odak +150.")
                    kural("3", "Birikme varsa üretme, tüket", "Bekleyen metin eşiği geçtiyse hamle \"önce tüket\" olur. Bu vault'ta sistemler bilgi eksikliğinden değil birikmeden öldü.")
                    kural("4", "Aksama × Yön ağırlığı", "Sessizlik/ritim oranı (en çok 6) × 10 × ağırlık. Ağırlık Yön Belgesi'nden: ana 3 · destek 2 · hat 1,5 · bakım 1. Vade 7 gün içindeyse +60, 3 gün içindeyse +120.")
                                        kural("5", "En çok üç hamle", "Üçü bitmeden dördüncü görünmez. Tek odak ilkesi.")
                } header: { Text("Bugünün sırası nasıl kurulur") }
                Section("Göstergeler") {
                    terim("Nabız", "Aktif süreçlerin ağırlıklı sağlığı (0–100). Akıyor 1 · gecikti 0,6 · başlamadı 0,3 · aksıyor 0,2 · tıkalı 0,1.")
                    terim("Ritim", "Bir sürecin en uzun doğal aralığı. Günlük, Teoria, Cümle: her gün. Hatlar: 2 gün. Mülakat: 3 gün. Üretim: 7 gün.")
                    terim("Sessizlik", "Son izden bugüne gün. İz = süreçlerin kendi bıraktığı kayıt; elle giriş yok.")
                    terim("Birikme", "Üretilmiş ama tüketilmemiş (dinlenmemiş metin, açılmamış paket). Kırmızı çizgi eşik.")
                    terim("Boru hattı", "Sabah görevleri: İdrak 06:20 · Mühendis 06:50 · Teoria 07:00 · Yazma Halkası 07:10. Çıktı dosyasının tarihi beklenen günü yansıtmıyorsa tıkalı.")
                    terim("Seri ve borç yok", "Kaçırılan gün hiçbir yerde birikmez. Orkestra yalnız bugünü ve sıradakini söyler.")
                }
                Section("Görselleştirme sözlüğü") {
                    ornek("Halka", "Tek bitiş noktası olan müfredat (Cümle'nin 41 gramer konusu, Mülakat'ın 15 alıştırması).") {
                        Halka(oran: 0.34, renk: Tema.alan("ingilizce"), kalinlik: 5).frame(width: 34, height: 34)
                    }
                    ornek("Merdiven", "Basamaklı ilerleme: Teoria'nın 3 hattı × 6 kademe, Mühendis'in 12 alanı.") {
                        Merdiven(basamaklar: [Basamak(ad: "Hatırla", a: 3, b: 6), Basamak(ad: "Kur", a: 1, b: 6)],
                                 renk: Tema.alan("felsefe")).frame(width: 170)
                    }
                    ornek("Depo", "Üretim ile tüketim farkı. Seviye kırmızı çizgiyi geçerse hat tıkalı.") {
                        DepoGorseli(ilerleme: nil, birikme: Birikme(bekleyen: 4, esik: 3, birim: "", not: ""),
                                    renk: Tema.alan("yazilim")).frame(width: 22, height: 40)
                    }
                    ornek("Kitaplık", "Aynı anda süren metinler; sırt boyu dinlenen yüzde.") {
                        Kitaplik(kitaplar: [Basamak(ad: "a", a: 75, b: 100), Basamak(ad: "b", a: 40, b: 100), Basamak(ad: "c", a: 90, b: 100)],
                                 renk: Tema.alan("felsefe")).frame(height: 40)
                    }
                    ornek("İz", "Yalnız ritmin önemli olduğu süreçler: her kare bir gün.") {
                        IzTakvimi(iz: [1, 0, 2, 1, 1, 0, 3, 2, 1, 0, 1, 2, 2, 1], renk: Tema.alan("vault"), hucre: 7)
                    }
                }
                Section {
                    Text("Orkestra salt okur. Hiçbir sürece yazmaz, puan ya da seri tutmaz. Veriyi Mac'teki toplayıcı (_araçlar/orkestra/veri/orkestra.py) her pano koşusunda tazeler; telefon Teoria ve Memories izlerini doğrudan da okur. Aşina, GramerApp ve Engineering ilerlemelerini yalnız telefonda tuttuğu için şimdilik \"görünmüyor\".")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Nereden okur") }
            }
            .scrollContentBackground(.hidden)
            .background(Tema.zemin)
            .navigationTitle("Kılavuz")
            .task { izin = await Bildirimci.izinVar() }
            .fileImporter(isPresented: $secici, allowedContentTypes: [.folder]) { sonuc in
                if case .success(let u) = sonuc { merkez.klasorSecildi(u) }
            }
        }
    }

    func kural(_ n: String, _ b: String, _ a: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.yuvarlak(12, .bold)).foregroundStyle(.white).frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(b).font(.system(size: 14, weight: .semibold))
                Text(a).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    func terim(_ b: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(b).font(.system(size: 14, weight: .semibold))
            Text(a).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    func ornek<G: View>(_ b: String, _ a: String, @ViewBuilder _ g: () -> G) -> some View {
        HStack(spacing: 12) {
            g().frame(minWidth: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(b).font(.system(size: 14, weight: .semibold))
                Text(a).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
