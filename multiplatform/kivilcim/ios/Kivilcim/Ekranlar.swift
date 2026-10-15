// Kaydet · Arşiv · Detay · Ayarlar
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: Çalma

@MainActor
final class TelefonOynatici: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TelefonOynatici()
    @Published private(set) var calan: String?
    @Published private(set) var caliyor = false
    @Published private(set) var konum: Double = 0
    @Published private(set) var uzunluk: Double = 0
    @Published private(set) var yukleniyor: String?
    @Published var hiz: Float = 1 { didSet { calici?.rate = hiz } }
    private var calici: AVAudioPlayer?
    private var zamanlayici: Timer?

    func degistir(_ o: Oge) async {
        if calan == o.id, let c = calici {
            if c.isPlaying { c.pause() } else { c.play() }
            caliyor = c.isPlaying; return
        }
        yukleniyor = o.id
        let u = await TelefonDeposu.shared.sesURL(o)
        yukleniyor = nil
        guard let u, let c = try? AVAudioPlayer(contentsOf: u) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        calici?.stop()
        c.delegate = self; c.enableRate = true; c.rate = hiz
        c.play()
        calici = c; calan = o.id; uzunluk = c.duration; konum = 0; caliyor = true
        zamanlayici?.invalidate()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in TelefonOynatici.shared.konum = TelefonOynatici.shared.calici?.currentTime ?? 0 }
        }
    }

    func atla(_ t: Double) { calici?.currentTime = max(0, min(uzunluk, t)); konum = calici?.currentTime ?? 0 }
    func ileri(_ d: Double) { atla(konum + d) }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let o = TelefonOynatici.shared
            o.caliyor = false; o.calan = nil; o.zamanlayici?.invalidate()
        }
    }
}

// MARK: Kaydet

struct KayitEkrani: View {
    @EnvironmentObject var merkez: KayitMerkezi
    @EnvironmentObject var depo: TelefonDeposu
    @EnvironmentObject var kasa: Kasa
    @Binding var sekme: Int
    @State private var basma: Date?
    @State private var basildigindaKayittaydi = false
    @State private var secili: Oge?
    @State private var nabiz = false

    var bugun: [Oge] { depo.ogeler.filter { Calendar.current.isDateInToday($0.zaman) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                ust
                Spacer(minLength: 12)
                dugme
                Text(merkez.kayitta ? "Dokun: bitir" : "Dokun: başlat · basılı tut: bas-konuş")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 14)
                if merkez.kayitta {
                    Button("Vazgeç", role: .destructive) { Task { await merkez.vazgec() } }
                        .font(.footnote.weight(.medium)).padding(.top, 6)
                }
                Spacer(minLength: 16)
                sonKayit
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
            .background(arkaPlan.ignoresSafeArea())
            .navigationTitle("Kıvılcım")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if depo.esitleniyor { ProgressView() }
                    else if !kasa.bagli { Image(systemName: "icloud.slash").foregroundStyle(.orange) }
                    else if depo.gonderilmemis > 0 { Label("\(depo.gonderilmemis)", systemImage: "arrow.up.circle").foregroundStyle(.orange) }
                }
            }
            .sheet(item: $secili) { o in NavigationStack { DetayEkrani(id: o.id) } }
        }
    }

    private var arkaPlan: some View {
        LinearGradient(colors: [Color.kivilcim.opacity(merkez.kayitta ? 0.22 : 0.08), Color(.systemBackground)],
                       startPoint: .top, endPoint: .center)
            .animation(.easeInOut(duration: 0.4), value: merkez.kayitta)
    }

    @ViewBuilder private var ust: some View {
        if merkez.kayitta {
            VStack(spacing: 14) {
                Text(Zaman.sure(merkez.sure))
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                DuzeyCubuklari(seviyeler: merkez.seviyeler, adet: 34).frame(height: 54).padding(.horizontal, 30)
                Text("\(merkez.kaliteSecimi.ad) · ≈\(merkez.kaliteSecimi.kbDk) KB/dk").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 8) {
                Text("Aklına geleni söyle").font(.title2.weight(.semibold))
                Text(bugun.isEmpty ? "Bugün henüz fikir yok" : "Bugün \(bugun.count) fikir · \(Int(bugun.reduce(0) { $0 + $1.sure } / 60)) dk")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let h = merkez.hata { Text(h).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal) }
                if !kasa.bagli {
                    Button { sekme = 2 } label: { Label("Vault klasörünü bağla", systemImage: "folder.badge.plus") }
                        .buttonStyle(.bordered).tint(.orange).padding(.top, 6)
                }
            }
        }
    }

    private var dugme: some View {
        ZStack {
            Circle().fill(Color.kivilcim.opacity(0.12)).frame(width: 232, height: 232)
                .scaleEffect(merkez.kayitta ? (nabiz ? 1.08 : 0.96) : 1)
                .animation(merkez.kayitta ? .easeInOut(duration: 0.9).repeatForever() : .default, value: nabiz)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FF8A4C"), .kivilcimKoyu], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 168, height: 168)
                .shadow(color: .kivilcim.opacity(0.45), radius: merkez.kayitta ? 28 : 16, y: 8)
            Image(systemName: merkez.kayitta ? "stop.fill" : "mic.fill")
                .font(.system(size: 58, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard basma == nil else { return }
                basma = Date(); basildigindaKayittaydi = merkez.kayitta
                if !merkez.kayitta { Task { await merkez.baslat() } }
            }
            .onEnded { _ in
                let tutuldu = Date().timeIntervalSince(basma ?? Date()) >= 0.6
                basma = nil
                if basildigindaKayittaydi || (tutuldu && merkez.kayitta) { Task { await merkez.bitir() } }
            })
        .onChange(of: merkez.kayitta) { _, k in nabiz = k }
        .accessibilityLabel(merkez.kayitta ? "Kaydı bitir" : "Kaydı başlat")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var sonKayit: some View {
        let son = Array(depo.ogeler.prefix(3))
        if !son.isEmpty && !merkez.kayitta {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Son fikirler").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Tümü") { sekme = 1 }.font(.subheadline)
                }
                ForEach(son) { o in
                    Button { secili = o } label: { OgeKarti(o: o) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct OgeKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    var sorgu = ""
    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: al.simge).font(.system(size: 15, weight: .semibold)).foregroundStyle(al.color)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(al.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if o.yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(o.baslik).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                }
                if !sorgu.isEmpty || !o.ozet.isEmpty {
                    Text(sorgu.isEmpty ? o.ozet : Arama.parca(o, sorgu)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(depo.siniflar.amac(o.amac).ad)
                    Text("·"); Text(Zaman.goreli(o.zaman)); Text("·"); Text(o.sureMetni)
                    if o.durum == "yerel" { Image(systemName: "iphone").foregroundStyle(.orange) }
                    else if !o.islendi { Image(systemName: "hourglass").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: Arşiv

struct ArsivEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @State private var sorgu = ""
    @State private var alan: String?
    @State private var amac: String?
    @State private var yildizli = false

    var liste: [Oge] {
        depo.ogeler.filter { o in
            (alan == nil || o.alan == alan) && (amac == nil || o.amac == amac) && (!yildizli || o.yildiz)
                && Arama.eslesir(o, sorgu, depo.siniflar)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { suzgecler.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                ForEach(liste.gunlere(), id: \.0) { gun, ogeler in
                    Section(gun) {
                        ForEach(ogeler) { o in
                            NavigationLink(value: o.id) { ArsivSatiri(o: o, sorgu: sorgu) }
                                .swipeActions(edge: .leading) {
                                    Button { depo.duzelt(o, "yildiz", !o.yildiz) } label: { Label("Yıldız", systemImage: o.yildiz ? "star.slash" : "star") }.tint(.yellow)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { depo.duzelt(o, "sil", true) } label: { Label("Çöpe", systemImage: "trash") }
                                }
                                .contextMenu { SinifMenusu(o: o) }
                        }
                    }
                }
            }
            .overlay {
                if liste.isEmpty {
                    ContentUnavailableView(sorgu.isEmpty ? "Fikir yok" : "“\(sorgu)” bulunamadı",
                                           systemImage: sorgu.isEmpty ? "waveform" : "magnifyingglass",
                                           description: Text(sorgu.isEmpty ? "Kaydet sekmesinden ya da kilit ekranından ilk fikrini söyle." : "Başlıkta, dökümde ve etiketlerde arandı."))
                }
            }
            .navigationTitle("Arşiv")
            .navigationDestination(for: String.self) { DetayEkrani(id: $0) }
            .searchable(text: $sorgu, placement: .navigationBarDrawer(displayMode: .always), prompt: "Başlık, döküm, etiket")
            .refreshable { await depo.gonder() }
        }
    }

    private var suzgecler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Cip(ad: "Yıldızlı", simge: "star.fill", renk: .yellow, secili: yildizli) { yildizli.toggle() }
                ForEach(depo.siniflar.alanlar) { a in
                    let n = depo.ogeler.filter { $0.alan == a.id }.count
                    if n > 0 { Cip(ad: "\(a.ad) \(n)", simge: a.simge, renk: a.color, secili: alan == a.id) { alan = alan == a.id ? nil : a.id } }
                }
                Divider().frame(height: 22)
                ForEach(depo.siniflar.amaclar) { a in
                    if depo.ogeler.contains(where: { $0.amac == a.id }) {
                        Cip(ad: a.ad, simge: a.simge, renk: .secondary, secili: amac == a.id) { amac = amac == a.id ? nil : a.id }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

struct Cip: View {
    let ad: String; let simge: String; let renk: Color; let secili: Bool; let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Label(ad, systemImage: simge).font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(secili ? .white : renk)
                .background(Capsule().fill(secili ? AnyShapeStyle(renk) : AnyShapeStyle(renk.opacity(0.12))))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: secili)
    }
}

struct ArsivSatiri: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    let sorgu: String
    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(al.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if o.yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(o.baslik).font(.body.weight(.semibold)).lineLimit(2)
                }
                let alt = sorgu.isEmpty ? (o.ozet.isEmpty ? o.metin : o.ozet) : Arama.parca(o, sorgu)
                if !alt.isEmpty { Text(alt).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                HStack(spacing: 6) {
                    Label(al.ad, systemImage: al.simge).foregroundStyle(al.color).lineLimit(1)
                    Image(systemName: depo.siniflar.amac(o.amac).simge)
                    Spacer()
                    if o.durum == "yerel" { Image(systemName: "icloud.and.arrow.up").foregroundStyle(.orange) }
                    else if !o.islendi { Image(systemName: "hourglass").foregroundStyle(.orange) }
                    Text("\(Zaman.saat(o.zaman)) · \(o.sureMetni)").monospacedDigit()
                    Image(systemName: o.cihaz == "mac" ? "laptopcomputer" : "iphone")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SinifMenusu: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    var body: some View {
        Menu("Alan") { ForEach(depo.siniflar.alanlar) { a in Button { depo.duzelt(o, "alan", a.id) } label: { Label(a.ad, systemImage: a.simge) } } }
        Menu("Amaç") { ForEach(depo.siniflar.amaclar) { a in Button { depo.duzelt(o, "amac", a.id) } label: { Label(a.ad, systemImage: a.simge) } } }
        Button { depo.duzelt(o, "yildiz", !o.yildiz) } label: { Label(o.yildiz ? "Yıldızı kaldır" : "Yıldızla", systemImage: "star") }
        Button { UIPasteboard.general.string = "\(o.baslik)\n\n\(o.metin)" } label: { Label("Dökümü kopyala", systemImage: "doc.on.doc") }
    }
}

// MARK: Detay

struct DetayEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @EnvironmentObject var oy: TelefonOynatici
    @Environment(\.dismiss) private var kapat
    let id: String
    @State private var baslik = ""
    @State private var silSor = false
    @FocusState private var odak: Bool

    var body: some View {
        if let o = depo.oge(id) {
            let al = depo.siniflar.alan(o.alan)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: o.cihaz == "mac" ? "laptopcomputer" : "iphone")
                            Text("\(Zaman.gunBasligi(o.zaman)) · \(Zaman.saat(o.zaman)) · \(o.sureMetni)")
                            if o.boyut > 0 { Text("· \(o.boyut / 1024) KB") }
                        }.font(.caption).foregroundStyle(.secondary)
                        TextField("Başlık", text: $baslik, axis: .vertical)
                            .font(.title2.weight(.bold)).focused($odak)
                            .submitLabel(.done)
                            .onChange(of: odak) { _, o2 in if !o2 { kaydet(o) } }
                        HStack(spacing: 8) {
                            Menu { ForEach(depo.siniflar.alanlar) { a in Button { depo.duzelt(o, "alan", a.id) } label: { Label(a.ad, systemImage: a.simge) } } }
                                label: { Label(al.ad, systemImage: al.simge).font(.subheadline.weight(.medium)) }
                                .buttonStyle(.bordered).tint(al.color)
                            Menu { ForEach(depo.siniflar.amaclar) { a in Button { depo.duzelt(o, "amac", a.id) } label: { Label("\(a.ad) — \(a.aciklama)", systemImage: a.simge) } } }
                                label: { let a = depo.siniflar.amac(o.amac); Label(a.ad, systemImage: a.simge).font(.subheadline.weight(.medium)) }
                                .buttonStyle(.bordered).tint(.secondary)
                            Spacer()
                            Button { depo.duzelt(o, "yildiz", !o.yildiz) } label: {
                                Image(systemName: o.yildiz ? "star.fill" : "star").foregroundStyle(o.yildiz ? .yellow : .secondary)
                            }.buttonStyle(.bordered).sensoryFeedback(.impact, trigger: o.yildiz)
                        }
                        if !o.etiketler.isEmpty {
                            Text(o.etiketler.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    calar(o, al.color)
                    if !o.ozet.isEmpty {
                        Text(o.ozet).font(.body).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(al.color.opacity(0.1)))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Döküm").font(.headline)
                            Text(o.metin_kaynak == "whisper" ? "Whisper · Mac" : o.metin_kaynak == "cihaz" ? "telefonun ön dökümü" : "").font(.caption).foregroundStyle(.secondary)
                        }
                        if o.metin.isEmpty {
                            Text(o.durum == "yerel" ? "Vault'a gönderilmeyi bekliyor; Mac açıkken Whisper yazıya döker."
                                 : o.islendi ? "Konuşma duyulmadı." : "Mac'te Whisper sırasında.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(o.metin).font(.body).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                    Text("Başlık: \(o.baslik_kaynak == "claude" ? "Claude" : o.baslik_kaynak == "elle" ? "sen" : "kural") · \(o.kalite.isEmpty ? "" : (Kalite(rawValue: o.kalite)?.ad ?? ""))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: "\(o.baslik)\n\n\(o.metin)") { Label("Metni paylaş", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = o.metin } label: { Label("Dökümü kopyala", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { silSor = true } label: { Label("Çöpe taşı", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear { baslik = o.baslik }
            .onChange(of: o.baslik) { _, y in baslik = y }
            .confirmationDialog("Bu fikir çöpe taşınsın mı?", isPresented: $silSor, titleVisibility: .visible) {
                Button("Çöpe taşı", role: .destructive) { depo.duzelt(o, "sil", true); kapat() }
            } message: { Text("Mac'te Kıvılcım/_silinen klasörüne gider, oradan geri alınabilir.") }
        } else {
            ContentUnavailableView("Fikir bulunamadı", systemImage: "questionmark")
        }
    }

    private func kaydet(_ o: Oge) {
        let b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty, b != o.baslik { depo.duzelt(o, "baslik", b) }
    }

    private func calar(_ o: Oge, _ renk: Color) -> some View {
        let bu = oy.calan == o.id
        return VStack(spacing: 10) {
            HStack(spacing: 16) {
                Button { Task { await oy.degistir(o) } } label: {
                    ZStack {
                        Circle().fill(renk).frame(width: 52, height: 52)
                        if oy.yukleniyor == o.id { ProgressView().tint(.white) }
                        else { Image(systemName: bu && oy.caliyor ? "pause.fill" : "play.fill").font(.title3.weight(.bold)).foregroundStyle(.white) }
                    }
                }.buttonStyle(.plain).sensoryFeedback(.impact(weight: .light), trigger: oy.caliyor)
                if bu {
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { oy.konum }, set: { oy.atla($0) }), in: 0...max(0.1, oy.uzunluk)).tint(renk)
                        HStack {
                            Text(Zaman.sure(oy.konum)); Spacer()
                            Button { oy.ileri(-10) } label: { Image(systemName: "gobackward.10") }
                            Button { oy.hiz = oy.hiz == 1 ? 1.5 : oy.hiz == 1.5 ? 2 : 1 } label: { Text(oy.hiz == 1 ? "1×" : oy.hiz == 1.5 ? "1,5×" : "2×").monospacedDigit() }
                            Button { oy.ileri(10) } label: { Image(systemName: "goforward.10") }
                            Spacer(); Text(Zaman.sure(oy.uzunluk))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Dinle · \(o.sureMetni)").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: Ayarlar

struct AyarlarEkrani: View {
    @EnvironmentObject var depo: TelefonDeposu
    @EnvironmentObject var kasa: Kasa
    @AppStorage("kalite") private var kalite = "dengeli"
    @AppStorage("dil") private var dil = "tr"
    @AppStorage("onDokum") private var onDokum = true
    @AppStorage("sunucuDokum") private var sunucuDokum = false
    @AppStorage("dokunsal") private var dokunsal = true
    @State private var secici = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Kalite.allCases) { q in
                        Button { kalite = q.rawValue } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.ad).foregroundStyle(.primary)
                                    Text("\(q.ozet)").font(.caption).foregroundStyle(.secondary)
                                    Text(q.aciklama).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if kalite == q.rawValue { Image(systemName: "checkmark").foregroundStyle(Color.kivilcim).fontWeight(.semibold) }
                            }
                        }
                    }
                } header: { Text("Kayıt kalitesi") } footer: {
                    Text("Whisper sesi zaten 16 kHz'e indirir; konuşma için Dengeli yeter. 10 dakikalık fikir Dengeli'de ≈2,4 MB.")
                }
                Section("Konuşma dili") {
                    Picker("Dil", selection: $dil) { Text("Türkçe").tag("tr"); Text("İngilizce").tag("en"); Text("Kendisi anlasın").tag("oto") }
                        .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Telefonda ön döküm", isOn: $onDokum)
                    if onDokum { Toggle("Cihaz içi değilse Apple sunucusunu kullan", isOn: $sunucuDokum) }
                } header: { Text("Döküm") } footer: {
                    Text("Asıl döküm Mac'te yerel Whisper ile yapılır. Ön döküm, Mac kapalıyken de fikri telefonda aranabilir kılar; varsayılan olarak ses telefondan çıkmaz.")
                }
                Section {
                    LabeledContent("Klasör", value: kasa.bagli ? kasa.klasorAdi : "bağlı değil")
                    Button(kasa.bagli ? "Klasörü değiştir" : "Vault klasörünü seç") { secici = true }
                    if kasa.bagli {
                        Button { Task { await depo.gonder() } } label: {
                            HStack { Text("Şimdi eşitle"); Spacer(); if depo.esitleniyor { ProgressView() } }
                        }
                    }
                    if let h = kasa.hata { Text(h).font(.caption).foregroundStyle(.red) }
                } header: { Text("Vault") } footer: {
                    Text("iCloud Drive › Obsidian › Personel Data Management'ı seç. Kayıtlar 05 - Notlar/Fikirler/Kıvılcım altına gider."
                         + (depo.sonEsitleme.map { " Son eşitleme: \(Zaman.goreli($0))." } ?? ""))
                }
                Section {
                    Adim(n: 1, metin: "Kilit ekranına uzun bas › Özelleştir › Kilit Ekranı")
                    Adim(n: 2, metin: "Alttaki el feneri ya da kamera düğmesine dokun › − ile kaldır › + › Kıvılcım › Fikir kaydet")
                    Adim(n: 3, metin: "Düğmeye basılı tut: kilit açılmadan kayıt başlar; kilit ekranında ve Dynamic Island'da süre görünür, ■ ile biter")
                    Adim(n: 4, metin: "Olmazsa ikinci denetimi dene: Kıvılcım › Aç ve kaydet (Face ID ile açar, kaydı hemen başlatır)")
                } header: { Text("Kilit ekranından kayıt") } footer: {
                    Text("Önceden: Ayarlar › Kıvılcım › Mikrofon ve Canlı Etkinlikler açık olmalı. Denetimi yeni kurduysan telefonu bir kez yeniden başlatmak gerekebilir.")
                }
                Section {
                    NavigationLink("Tanı kaydı") { TaniEkrani() }
                } footer: { Text("Kilit ekranı düğmesi çalışmazsa buradaki son satırlar nedenini söyler.") }
                Section {
                    Toggle("Dokunsal geri bildirim", isOn: $dokunsal)
                    LabeledContent("Toplam", value: "\(depo.ogeler.count) fikir · \(depo.toplamDakika) dk · \(String(format: "%.1f", depo.toplamMB)) MB")
                } footer: { Text("Siri: \"Kıvılcım ile fikir kaydet\". Kestirmeler'de Arkaya Dokunma'ya da bağlanabilir (Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokunma).") }
            }
            .navigationTitle("Ayarlar")
            .fileImporter(isPresented: $secici, allowedContentTypes: [.folder]) { s in
                if case .success(let u) = s { kasa.klasorSecildi(u); Task { await depo.gonder() } }
            }
        }
    }
}

struct Adim: View {
    let n: Int; let metin: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Circle().fill(Color.kivilcim))
            Text(metin).font(.subheadline)
        }
    }
}

struct TaniEkrani: View {
    @State private var metin = Tani.oku()
    var body: some View {
        ScrollView {
            Text(metin.isEmpty ? "Henüz kayıt yok. Kilit ekranındaki düğmeye bas, sonra buraya dön." : metin)
                .font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Tanı")
        .toolbar { Button("Yenile") { metin = Tani.oku() } }
        .refreshable { metin = Tani.oku() }
    }
}
