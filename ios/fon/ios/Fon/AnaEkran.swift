import SwiftUI
import UniformTypeIdentifiers

struct AnaEkran: View {
    @EnvironmentObject private var calar: Calar
    @Environment(\.scenePhase) private var evre
    @AppStorage(Depo.klasorAdiAnahtari) private var klasorAdi = ""

    private enum Secici { case dosya, klasor }
    @State private var secici: Secici = .dosya
    @State private var seciciAcik = false
    @State private var esitleniyor = false
    @State private var bilgi: String?
    @State private var yardimAcik = false

    var body: some View {
        NavigationStack {
            // Çalar kartı listenin dışında durur: liste satırındaki birden çok düğme dokunuşları karıştırıyordu.
            VStack(spacing: 0) {
            CalarKarti()
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            List {
                Section {
                    eslikSatiri
                    uykuSatiri
                    klasorSatiri
                }

                Section {
                    if calar.parcalar.isEmpty {
                        bosDurum
                    } else {
                        ForEach(calar.parcalar) { parca in
                            ParcaSatiri(parca: parca)
                                .contentShape(Rectangle())
                                .onTapGesture { calar.cal(parca) }
                        }
                        .onDelete { sira in sira.map { calar.parcalar[$0] }.forEach(calar.sil) }
                    }
                } header: {
                    Text(calar.parcalar.isEmpty ? "Parçalar" : "Parçalar · \(calar.parcalar.count)")
                } footer: {
                    if !calar.parcalar.isEmpty {
                        Text("Dosyalar › iPhone'umda › Fon klasörüne attığın müzik de burada görünür.")
                    }
                }
            }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { yardimAcik = true } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { ac(.dosya) } label: { Label("Dosya ekle", systemImage: "doc.badge.plus") }
                        Button { ac(.klasor) } label: { Label("Klasör bağla", systemImage: "folder.badge.plus") }
                        if !klasorAdi.isEmpty {
                            Button { Task { await esitle() } } label: { Label("Şimdi eşitle", systemImage: "arrow.triangle.2.circlepath") }
                        }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .refreshable { await esitle() }
            .fileImporter(isPresented: $seciciAcik,
                          allowedContentTypes: secici == .klasor ? [.folder] : [.audio],
                          allowsMultipleSelection: secici == .dosya) { sonuc in
                secildi(sonuc)
            }
            .alert("Fon", isPresented: Binding(get: { bilgi != nil }, set: { if !$0 { bilgi = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(bilgi ?? "") }
            .sheet(isPresented: $yardimAcik) { YardimEkrani() }
            .task { if !klasorAdi.isEmpty { await esitle(sessiz: true) } }
            .onChange(of: evre) { _, yeni in
                if yeni == .active, !klasorAdi.isEmpty { Task { await esitle(sessiz: true) } }
            }
        }
        .tint(Color("AccentColor"))
    }

    // MARK: Satırlar

    private var eslikSatiri: some View {
        Menu {
            Picker("Diğer ses çalınca", selection: $calar.eslik) {
                ForEach(Calar.Eslik.allCases) { Text($0.ad).tag($0) }
            }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Konuşmaya eşlik").foregroundStyle(.primary)
                        Text(calar.eslik == .kapali ? "Müzik hep aynı seste çalar."
                             : calar.eslik == .onePlanaCik ? "Voice Dream konuşurken kısılır, susunca öne çıkar."
                             : "Voice Dream susunca müzik de sessize iner.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                } icon: { Image(systemName: "waveform.badge.mic").foregroundStyle(Color("AccentColor")) }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(calar.eslik == .kapali ? "Kapalı" : calar.eslik == .onePlanaCik ? "Öne çık" : "Sessize in")
                        .foregroundStyle(.secondary)
                    if let var_ = calar.konusmaAlgilandi {
                        // Algılamanın çalışıp çalışmadığı buradan görülür.
                        Label(var_ ? "konuşma var" : "konuşma yok", systemImage: var_ ? "waveform" : "pause")
                            .font(.caption2).foregroundStyle(var_ ? Color("AccentColor") : .secondary)
                    }
                }
            }
        }
        .tint(.primary)
    }

    private var uykuSatiri: some View {
        Menu {
            ForEach([15, 30, 45, 60, 90], id: \.self) { dk in
                Button("\(dk) dakika") { calar.uyku(dakika: dk) }
            }
            if calar.uykuBitis != nil {
                Button("Zamanlayıcıyı kapat", role: .destructive) { calar.uykuyuIptal() }
            }
        } label: {
            HStack {
                Label { Text("Uyku zamanlayıcısı") } icon: { Image(systemName: "moon.zzz").foregroundStyle(Color("AccentColor")) }
                    .foregroundStyle(.primary)
                Spacer()
                if let bitis = calar.uykuBitis {
                    Text(timerInterval: Date()...bitis, countsDown: true)
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("Kapalı").foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
    }

    private var klasorSatiri: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(klasorAdi.isEmpty ? "Klasör bağlı değil" : "Kaynak: \(klasorAdi)")
                    Text(klasorAdi.isEmpty ? "iCloud Drive › Fon klasörünü bağla; Mac'ten attığın müzik gelsin."
                                           : "Açılışta ve aşağı çekince yeni dosyalar alınır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "icloud") }
            Spacer()
            if esitleniyor {
                ProgressView()
            } else if klasorAdi.isEmpty {
                Button("Bağla") { ac(.klasor) }.buttonStyle(.bordered)
            }
        }
        .swipeActions {
            if !klasorAdi.isEmpty {
                Button("Bağı kaldır", role: .destructive) { Depo.klasorBaginiKaldir(); klasorAdi = "" }
            }
        }
    }

    private var bosDurum: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary)
            Text("Henüz müzik yok").font(.headline)
            Text("Sağ üstteki + ile dosya ekle ya da iCloud Drive'daki Fon klasörünü bağla.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: İşler

    private func ac(_ tur: Secici) {
        secici = tur
        seciciAcik = true
    }

    private func secildi(_ sonuc: Result<[URL], Error>) {
        guard case .success(let urller) = sonuc else { return }
        if secici == .klasor, let klasor = urller.first {
            do {
                try Depo.klasorBagla(klasor)
                klasorAdi = klasor.lastPathComponent
                Task { await esitle() }
            } catch {
                bilgi = "Klasör bağlanamadı: \(error.localizedDescription)"
            }
            return
        }
        Task {
            esitleniyor = true
            let sayi = await Task.detached { () -> Int in
                var n = 0
                for url in urller {
                    let erisim = url.startAccessingSecurityScopedResource()
                    if (try? Depo.iceriAl(url)) == true { n += 1 }
                    if erisim { url.stopAccessingSecurityScopedResource() }
                }
                return n
            }.value
            esitleniyor = false
            calar.yenile()
            if sayi == 0 { bilgi = "Seçilen dosyalar zaten kitaplıkta." }
        }
    }

    private func esitle(sessiz: Bool = false) async {
        guard Depo.bagliKlasorVar, !esitleniyor else { return }
        esitleniyor = true
        let sonuc = await Task.detached { Depo.esitle() }.value
        esitleniyor = false
        calar.yenile()
        if !sonuc.hatalar.isEmpty {
            bilgi = "Alınamayanlar: " + sonuc.hatalar.prefix(5).joined(separator: ", ")
        } else if !sessiz {
            bilgi = sonuc.yeni == 0 ? "Yeni dosya yok." : "\(sonuc.yeni) yeni parça alındı."
        }
    }
}

// MARK: - Çalar kartı

private struct CalarKarti: View {
    @EnvironmentObject private var calar: Calar

    private var durumYazisi: String {
        switch calar.durum {
        case .durdu: return calar.parcalar.isEmpty ? "Müzik ekleyince başlar" : "Duruyor"
        case .caliyor: return calar.eslik == .kapali ? "Çalıyor · diğer sesin altında" : "Konuşmanın altında · kısık"
        case .konusmaYok: return calar.eslik == .onePlanaCik ? "Ön planda · konuşma durdu" : "Sessizde · konuşma bekleniyor"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Dalga(aktif: calar.caliyorMu && !(calar.durum == .konusmaYok && calar.eslik == .sessizeIn))
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(calar.simdiki?.ad ?? "Fon")
                        .font(.headline).lineLimit(2)
                    Text(durumYazisi)
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }

            HStack {
                Dugme(simge: "shuffle", secili: calar.karisik) { calar.karisik.toggle() }
                Spacer()
                Button { calar.acKapa() } label: {
                    Image(systemName: calar.caliyorMu ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 72, height: 72)
                        .background(Circle().fill(.white))
                        .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.20))
                }
                .buttonStyle(.plain)
                .disabled(calar.parcalar.isEmpty)
                .sensoryFeedback(.impact, trigger: calar.caliyorMu)
                Spacer()
                Dugme(simge: "forward.fill", secili: false) { calar.sonraki() }
                    .disabled(calar.parcalar.isEmpty)
                Spacer()
                Dugme(simge: "repeat.1", secili: calar.tekParcaTekrar) { calar.tekParcaTekrar.toggle() }
            }

            VStack(spacing: 6) {
                if calar.eslik == .onePlanaCik {
                    SesSurgusu(baslik: "Konuşurken", deger: $calar.ses, etkin: calar.durum != .konusmaYok)
                    SesSurgusu(baslik: "Durunca", deger: $calar.onPlanSes, etkin: calar.durum == .konusmaYok)
                } else {
                    SesSurgusu(baslik: nil, deger: $calar.ses, etkin: true)
                }
                Text("Telefonun ses tuşları ikisini birlikte, sürgüler yalnız müziği ayarlar.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.30), Color(red: 0.38, green: 0.20, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }
}

private struct SesSurgusu: View {
    let baslik: String?
    @Binding var deger: Float
    /// Şu an geçerli olan sürgü parlak, öteki soluk görünür.
    let etkin: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let baslik {
                Text(baslik).font(.caption).frame(width: 74, alignment: .leading)
            } else {
                Image(systemName: "speaker.fill").font(.caption)
            }
            Slider(value: $deger, in: 0...1).tint(.white)
            if baslik == nil { Image(systemName: "speaker.wave.3.fill").font(.caption) }
            Text("\(Int((deger * 100).rounded()))")
                .font(.caption.monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .opacity(etkin ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.3), value: etkin)
    }
}

private struct Dugme: View {
    let simge: String
    let secili: Bool
    let eylem: () -> Void

    var body: some View {
        Button(action: eylem) {
            Image(systemName: simge)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(secili ? 0.28 : 0.08)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Çalarken kıpırdayan üç çizgi; iki katman — konuşma ve altındaki müzik.
private struct Dalga: View {
    let aktif: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !aktif)) { zaman in
            let t = zaman.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<4) { i in
                    let h = aktif ? 0.35 + 0.65 * abs(sin(t * (1.6 + Double(i) * 0.7) + Double(i))) : 0.3
                    Capsule().fill(.white.opacity(i % 2 == 0 ? 0.95 : 0.55))
                        .frame(width: 6, height: 40 * h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.12)))
        }
    }
}

private struct ParcaSatiri: View {
    @EnvironmentObject private var calar: Calar
    let parca: Parca

    var body: some View {
        HStack(spacing: 12) {
            let simdiki = calar.simdiki == parca
            Image(systemName: simdiki && calar.caliyorMu ? "speaker.wave.2.fill" : "music.note")
                .foregroundStyle(simdiki ? Color("AccentColor") : .secondary)
                .frame(width: 22)
            Text(parca.ad)
                .lineLimit(1)
                .fontWeight(simdiki ? .semibold : .regular)
            Spacer()
        }
    }
}

// MARK: - Yardım

private struct YardimEkrani: View {
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            List {
                Section("Nasıl çalışır") {
                    Text("Voice Dream'de (ya da başka bir okuma uygulamasında) dinlemeye başla, sonra Fon'da ▶︎'ye bas. Fon diğer sesi kesmez, altında çalar.")
                    Text("Kilit ekranındaki düğmeler Voice Dream'e aittir. Fon'u uygulamadan, Siri'den ya da Kestirmeler'den yönet.")
                    Text("Sürgü müziğin sesini ayarlar; telefonun ses tuşları ikisini birlikte ayarlar. Başlangıç için 25-35 iyi bir aralıktır.")
                }
                Section("Müziği koymanın üç yolu") {
                    Text("Mac'te iCloud Drive › Fon klasörüne at; Fon'da klasörü bir kez bağla. Sonrası kendiliğinden gelir.")
                    Text("Telefonda Dosyalar › iPhone'umda › Fon klasörüne taşı.")
                    Text("Herhangi bir uygulamada ses dosyasını Paylaş › Fon ile aç.")
                }
                Section("Otomatik başlatma") {
                    Text("Kestirmeler › Otomasyon › + › Uygulama › Voice Dream › Açıldığında › Fon'u çal. \"Hemen Çalıştır\"ı seç.")
                    Text("\"Kapandığında\" tetiği kullanma: Voice Dream'den başka uygulamaya geçmek de onu \"kapatır\", müzik boşuna durur. Durdurmayı \"Konuşmaya eşlik\" ya da uyku zamanlayıcısı üstlenir.")
                    Text("Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokunma › İki kez dokun › Fon'u aç/kapat.")
                    Text("Siri: \"Fon çal\", \"Fon durdur\".")
                }
            }
            .navigationTitle("Yardım")
            .toolbar { Button("Kapat") { kapat() } }
        }
    }
}
