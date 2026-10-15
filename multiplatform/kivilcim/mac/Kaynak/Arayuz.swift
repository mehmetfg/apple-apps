// Menü paneli · Arşiv penceresi · Ayarlar.
import SwiftUI
import AppKit
import ServiceManagement

// MARK: Menü paneli (menü çubuğu simgesine tıklayınca)

struct MenuPaneli: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var k: Kaydedici
    @EnvironmentObject var oy: Oynatici
    @Environment(\.openWindow) private var pencereAc
    @State private var sorgu = ""

    var sonlar: [Oge] {
        let l = depo.ogeler.filter { Arama.eslesir($0, sorgu, depo.siniflar) }
        return Array(l.prefix(sorgu.isEmpty ? 6 : 12))
    }

    var body: some View {
        VStack(spacing: 0) {
            kayitAlani.padding(16)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Fikirlerde ara…", text: $sorgu).textFieldStyle(.plain)
                if !sorgu.isEmpty { Button { sorgu = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider()
            if sonlar.isEmpty {
                Text(sorgu.isEmpty ? "İlk fikrini kaydet: düğmeye bas ya da \(KisayolSecenegi.secili.ad)." : "Bulunamadı.")
                    .font(.callout).foregroundStyle(.secondary).padding(22).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(sonlar) { o in
                            KucukSatir(o: o, sorgu: sorgu) { depo.secili = o.id; ac() }
                        }
                    }.padding(6)
                }.frame(maxHeight: 330)
            }
            Divider()
            altSerit.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 370)
    }

    private var kayitAlani: some View {
        HStack(spacing: 14) {
            Button { k.degistir() } label: {
                ZStack {
                    Circle().fill(k.kayitta ? Color.kivilcim : Color.kivilcim.opacity(0.14)).frame(width: 58, height: 58)
                    Image(systemName: k.kayitta ? "stop.fill" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(k.kayitta ? .white : Color.kivilcim)
                }
            }
            .buttonStyle(.plain)
            .help(k.kayitta ? "Kaydı bitir" : "Kaydı başlat")
            VStack(alignment: .leading, spacing: 5) {
                if k.kayitta {
                    HStack {
                        Text(Zaman.sure(k.sure)).font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                        Spacer()
                        Button("Vazgeç") { k.vazgec() }.controlSize(.small)
                    }
                    DuzeyCubuklari(seviyeler: k.seviyeler).frame(height: 22)
                } else {
                    Text("Aklına geleni söyle").font(.headline)
                    Text("\(KisayolSecenegi.secili.ad) · bas-konuş için basılı tut").font(.caption).foregroundStyle(.secondary)
                    Text("\(k.kaliteSecimi.ad) · ≈\(k.kaliteSecimi.kbDk) KB/dk").font(.caption2).foregroundStyle(.tertiary)
                }
                if let h = k.hata ?? depo.hata { Text(h).font(.caption2).foregroundStyle(.red).lineLimit(3) }
            }
            Spacer(minLength: 0)
        }
    }

    private var altSerit: some View {
        HStack(spacing: 10) {
            if depo.isleniyor {
                ProgressView().controlSize(.small)
                Text(depo.durumMetni).font(.caption).foregroundStyle(.secondary)
            } else if depo.bekleyenSayisi > 0 {
                Image(systemName: "clock").foregroundStyle(.orange)
                Text("\(depo.bekleyenSayisi) kayıt sırada").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(depo.ogeler.count) fikir · \(depo.toplamDakika) dk · \(String(format: "%.1f", depo.toplamMB)) MB")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { ac() } label: { Label("Arşiv", systemImage: "square.grid.2x2") }.controlSize(.small)
            SettingsLink { Image(systemName: "gearshape") }.controlSize(.small).help("Ayarlar")
            Menu {
                Button("Şimdi işle") { depo.isle() }
                Button("Veri klasörünü göster") { NSWorkspace.shared.activateFileViewerSelecting([depo.kok]) }
                Button("Fikir Defteri'ni Obsidian'da aç") { obsidianAc(depo.kok.appendingPathComponent("Fikir Defteri.md"), depo.vault) }
                Divider()
                Button("Kıvılcım'dan çık") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func ac() {
        pencereAc(id: "arsiv")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct KucukSatir: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oy: Oynatici
    let o: Oge
    var sorgu = ""
    let ac: () -> Void
    @State private var uzerinde = false

    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 10) {
            Button { oy.degistir(o) } label: {
                Image(systemName: oy.calan == o.id && oy.caliyor ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(al.color)
                    .frame(width: 26, height: 26).background(Circle().fill(al.color.opacity(0.15)))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if o.yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(o.baslik).font(.callout.weight(.medium)).lineLimit(1)
                }
                if !sorgu.isEmpty {
                    Text(Arama.parca(o, sorgu)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    SinifRozeti(alan: al, amac: depo.siniflar.amac(o.amac), kucuk: true)
                    Spacer(minLength: 4)
                    if !o.islendi { Image(systemName: "hourglass").font(.caption2).foregroundStyle(.orange) }
                    Text("\(Zaman.goreli(o.zaman)) · \(o.sureMetni)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(uzerinde ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { uzerinde = $0 }
        .onTapGesture(perform: ac)
    }
}

func obsidianAc(_ dosya: URL, _ vault: URL) {
    let yol = String(dosya.path.dropFirst(vault.path.count + 1))
    var c = URLComponents(string: "obsidian://open")!
    c.queryItems = [URLQueryItem(name: "vault", value: vault.lastPathComponent), URLQueryItem(name: "file", value: yol)]
    if let u = c.url { NSWorkspace.shared.open(u) }
}

// MARK: Arşiv penceresi

enum Suzgec: Hashable {
    case tumu, bugun, hafta, yildizli, bekleyen, alan(String), amac(String)
}

struct ArsivPenceresi: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var k: Kaydedici
    @State private var suzgec: Suzgec? = .tumu
    @State private var sorgu = ""

    var liste: [Oge] {
        let tk = Calendar.current
        return depo.ogeler.filter { o in
            switch suzgec ?? .tumu {
            case .tumu: true
            case .bugun: tk.isDateInToday(o.zaman)
            case .hafta: Date().timeIntervalSince(o.zaman) < 7 * 86400
            case .yildizli: o.yildiz
            case .bekleyen: !o.islendi
            case .alan(let a): o.alan == a
            case .amac(let a): o.amac == a
            }
        }.filter { Arama.eslesir($0, sorgu, depo.siniflar) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $suzgec) {
                Section {
                    satir(.tumu, "Tümü", "tray.full", depo.ogeler.count)
                    satir(.bugun, "Bugün", "sun.max", depo.ogeler.filter { Calendar.current.isDateInToday($0.zaman) }.count)
                    satir(.hafta, "Bu hafta", "calendar", depo.ogeler.filter { Date().timeIntervalSince($0.zaman) < 7 * 86400 }.count)
                    satir(.yildizli, "Yıldızlı", "star", depo.ogeler.filter(\.yildiz).count)
                    if depo.bekleyenSayisi > 0 { satir(.bekleyen, "İşlenmeyi bekleyen", "hourglass", depo.bekleyenSayisi) }
                }
                Section("Alanlar") {
                    ForEach(depo.siniflar.alanlar) { a in
                        let n = depo.ogeler.filter { $0.alan == a.id }.count
                        if n > 0 {
                            Label { HStack { Text(a.ad); Spacer(); Text("\(n)").foregroundStyle(.secondary).monospacedDigit() } }
                                icon: { Image(systemName: a.simge).foregroundStyle(a.color) }
                                .tag(Suzgec.alan(a.id))
                        }
                    }
                }
                Section("Amaç") {
                    ForEach(depo.siniflar.amaclar) { a in
                        let n = depo.ogeler.filter { $0.amac == a.id }.count
                        if n > 0 { satir(.amac(a.id), a.ad, a.simge, n) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Button { k.degistir() } label: {
                    Label(k.kayitta ? "Bitir · \(Zaman.sure(k.sure))" : "Yeni sesli fikir", systemImage: k.kayitta ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(.kivilcim)
                .padding(10)
            }
        } content: {
            OgeListesi(liste: liste, sorgu: sorgu)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            if let id = depo.secili, let o = depo.ogeler.first(where: { $0.id == id }) {
                Detay(o: o, sorgu: sorgu).id(o.id)
            } else {
                ContentUnavailableView("Bir fikir seç", systemImage: "waveform", description: Text("Ya da \(KisayolSecenegi.secili.ad) ile yenisini söyle."))
            }
        }
        .searchable(text: $sorgu, placement: .toolbar, prompt: "Başlık, döküm, etiket…")
        .toolbar {
            ToolbarItem {
                if depo.isleniyor { ProgressView().controlSize(.small).help(depo.durumMetni) }
                else { Button { depo.isle() } label: { Image(systemName: "arrow.clockwise") }.help("Şimdi işle (⌘R)") }
            }
        }
        .navigationTitle("Kıvılcım")
        .navigationSubtitle("\(depo.ogeler.count) fikir · \(depo.toplamDakika) dk · \(String(format: "%.1f", depo.toplamMB)) MB")
    }

    private func satir(_ s: Suzgec, _ ad: String, _ simge: String, _ n: Int) -> some View {
        Label { HStack { Text(ad); Spacer(); Text("\(n)").foregroundStyle(.secondary).monospacedDigit() } } icon: { Image(systemName: simge) }
            .tag(s)
    }
}

struct OgeListesi: View {
    @EnvironmentObject var depo: Depo
    let liste: [Oge]
    let sorgu: String

    var body: some View {
        List(selection: $depo.secili) {
            ForEach(liste.gunlere(), id: \.0) { gun, ogeler in
                Section(gun) {
                    ForEach(ogeler) { o in
                        ListeSatiri(o: o, sorgu: sorgu).tag(o.id)
                            .contextMenu { BaglamMenusu(o: o) }
                    }
                }
            }
        }
        .overlay {
            if liste.isEmpty {
                ContentUnavailableView(sorgu.isEmpty ? "Burada fikir yok" : "“\(sorgu)” bulunamadı", systemImage: sorgu.isEmpty ? "tray" : "magnifyingglass")
            }
        }
    }
}

struct ListeSatiri: View {
    @EnvironmentObject var depo: Depo
    let o: Oge
    let sorgu: String
    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(al.color).frame(width: 4).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if o.yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(o.baslik).font(.body.weight(.semibold)).lineLimit(2)
                }
                Text(sorgu.isEmpty ? (o.ozet.isEmpty ? o.metin : o.ozet) : Arama.parca(o, sorgu))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    SinifRozeti(alan: al, amac: depo.siniflar.amac(o.amac), kucuk: true)
                    Spacer()
                    if !o.islendi { Label(o.durum == "hata" ? "hata" : "sırada", systemImage: "hourglass").font(.caption2).foregroundStyle(.orange) }
                    Text("\(Zaman.saat(o.zaman)) · \(o.sureMetni)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Image(systemName: o.cihaz == "mac" ? "laptopcomputer" : "iphone").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct BaglamMenusu: View {
    @EnvironmentObject var depo: Depo
    let o: Oge
    var body: some View {
        Button(o.yildiz ? "Yıldızı kaldır" : "Yıldızla") { depo.duzelt(o, "yildiz", !o.yildiz) }
        Menu("Alan") {
            ForEach(depo.siniflar.alanlar) { a in Button(a.ad) { depo.duzelt(o, "alan", a.id) } }
        }
        Menu("Amaç") {
            ForEach(depo.siniflar.amaclar) { a in Button(a.ad) { depo.duzelt(o, "amac", a.id) } }
        }
        Divider()
        if let n = depo.notURL(o) { Button("Obsidian'da aç") { obsidianAc(n, depo.vault) } }
        if let s = depo.sesURL(o) { Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([s]) } }
        Button("Dökümü kopyala") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(o.baslik)\n\n\(o.metin)", forType: .string)
        }
        Divider()
        Button("Çöpe taşı", role: .destructive) { depo.duzelt(o, "sil", true); if depo.secili == o.id { depo.secili = nil } }
    }
}

struct Detay: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oy: Oynatici
    let o: Oge
    let sorgu: String
    @State private var baslik = ""
    @State private var silSor = false

    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: o.cihaz == "mac" ? "laptopcomputer" : "iphone")
                        Text(Zaman.gunBasligi(o.zaman) + " · " + Zaman.saat(o.zaman))
                        Text("·"); Text(o.sureMetni)
                        if o.boyut > 0 { Text("·"); Text("\(o.boyut / 1024) KB") }
                        if !o.kalite.isEmpty, let q = Kalite(rawValue: o.kalite) { Text("·"); Text(q.ad) }
                    }.font(.caption).foregroundStyle(.secondary)
                    TextField("Başlık", text: $baslik, axis: .vertical)
                        .font(.system(size: 24, weight: .bold)).textFieldStyle(.plain)
                        .onSubmit(kaydetBaslik)
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(depo.siniflar.alanlar) { a in
                                Button { depo.duzelt(o, "alan", a.id) } label: { Label(a.ad, systemImage: a.simge) }
                            }
                        } label: { Label(al.ad, systemImage: al.simge) }
                            .menuStyle(.button).buttonStyle(.bordered).tint(al.color).fixedSize()
                        Menu {
                            ForEach(depo.siniflar.amaclar) { a in
                                Button { depo.duzelt(o, "amac", a.id) } label: { Label("\(a.ad) — \(a.aciklama)", systemImage: a.simge) }
                            }
                        } label: { let a = depo.siniflar.amac(o.amac); Label(a.ad, systemImage: a.simge) }
                            .menuStyle(.button).buttonStyle(.bordered).fixedSize()
                        Button { depo.duzelt(o, "yildiz", !o.yildiz) } label: {
                            Image(systemName: o.yildiz ? "star.fill" : "star").foregroundStyle(o.yildiz ? .yellow : .secondary)
                        }.buttonStyle(.bordered).help("Yıldızla")
                        Spacer()
                        kaynakRozeti
                    }
                    if !o.etiketler.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(o.etiketler, id: \.self) { e in
                                Text("#" + e).font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                }
                CalarSerit(o: o, renk: al.color)
                if !o.ozet.isEmpty {
                    Text(o.ozet).font(.title3).foregroundStyle(.primary.opacity(0.85))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(al.color.opacity(0.08)))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Döküm").font(.headline)
                        Text(o.metin_kaynak == "whisper" ? "Whisper" : o.metin_kaynak == "cihaz" ? "cihaz içi ön döküm" : "")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(o.metin, forType: .string) } label: {
                            Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Kopyala")
                    }
                    if o.metin.isEmpty {
                        Text(o.islendi ? "Konuşma duyulmadı." : "Sırada — Mac Whisper ile birazdan yazıya döker.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(vurgula(o.metin, sorgu)).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    }
                }
                HStack {
                    if let n = depo.notURL(o) { Button { obsidianAc(n, depo.vault) } label: { Label("Obsidian'da aç", systemImage: "arrow.up.forward.app") } }
                    if let s = depo.sesURL(o) { Button { NSWorkspace.shared.activateFileViewerSelecting([s]) } label: { Label("Finder", systemImage: "folder") } }
                    Spacer()
                    Button(role: .destructive) { silSor = true } label: { Label("Çöpe taşı", systemImage: "trash") }
                }
                .controlSize(.small)
            }
            .padding(24).frame(maxWidth: 760, alignment: .leading)
        }
        .onAppear { baslik = o.baslik }
        .onChange(of: o.baslik) { _, y in baslik = y }
        .onDisappear(perform: kaydetBaslik)
        .confirmationDialog("Bu fikir çöpe taşınsın mı?", isPresented: $silSor) {
            Button("Çöpe taşı", role: .destructive) { depo.duzelt(o, "sil", true); depo.secili = nil }
        } message: { Text("Ses ve not Kıvılcım/_silinen klasörüne gider; oradan geri alınabilir.") }
    }

    private var kaynakRozeti: some View {
        let (ad, simge): (String, String) = switch o.baslik_kaynak {
        case "claude": ("Claude", "sparkles")
        case "elle": ("sen", "pencil")
        default: ("kural", "textformat")
        }
        return Label("başlık: \(ad)", systemImage: simge).font(.caption2).foregroundStyle(.tertiary)
    }

    private func kaydetBaslik() {
        let b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty, b != o.baslik { depo.duzelt(o, "baslik", b) }
    }

    private func vurgula(_ m: String, _ s: String) -> AttributedString {
        var a = AttributedString(m)
        for p in s.split(separator: " ") where p.count >= 2 {
            var aralik = a.startIndex..<a.endIndex
            while let r = a[aralik].range(of: String(p), options: [.caseInsensitive, .diacriticInsensitive]) {
                a[r].backgroundColor = .yellow.opacity(0.35)
                aralik = r.upperBound..<a.endIndex
            }
        }
        return a
    }
}

struct CalarSerit: View {
    @EnvironmentObject var oy: Oynatici
    let o: Oge
    let renk: Color
    var body: some View {
        let bu = oy.calan == o.id
        HStack(spacing: 12) {
            Button { oy.degistir(o) } label: {
                Image(systemName: bu && oy.caliyor ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white).frame(width: 38, height: 38).background(Circle().fill(renk))
            }.buttonStyle(.plain).keyboardShortcut(.space, modifiers: [])
            if bu {
                Slider(value: Binding(get: { oy.konum }, set: { oy.atla($0) }), in: 0...max(0.1, oy.uzunluk))
                Text("\(Zaman.sure(oy.konum)) / \(Zaman.sure(oy.uzunluk))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Picker("", selection: $oy.hiz) {
                    Text("1×").tag(Float(1)); Text("1,5×").tag(Float(1.5)); Text("2×").tag(Float(2))
                }.pickerStyle(.segmented).frame(width: 120)
            } else {
                Text("Dinle · \(o.sureMetni)").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

// MARK: Ayarlar

struct AyarlarGorunumu: View {
    @EnvironmentObject var depo: Depo
    @AppStorage("kalite") private var kalite = "dengeli"
    @AppStorage("dil") private var dil = "tr"
    @AppStorage("kisayol") private var kisayol = "ctrlOptK"
    @AppStorage("claudeBaslik") private var claudeBaslik = true
    @AppStorage("hud") private var hud = true
    @State private var giris = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Kayıt kalitesi") {
                Picker("Kalite", selection: $kalite) {
                    ForEach(Kalite.allCases) { q in
                        VStack(alignment: .leading) { Text(q.ad); Text("\(q.ozet) — \(q.aciklama)").font(.caption).foregroundStyle(.secondary) }.tag(q.rawValue)
                    }
                }.pickerStyle(.radioGroup)
                Text("Whisper sesi zaten 16 kHz'e indirir; konuşma için Dengeli yeter. 10 dakikalık bir fikir Dengeli'de ≈\(Kalite.dengeli.kbDk * 10 / 1000) MB.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Konuşma dili") {
                Picker("Dil", selection: $dil) {
                    Text("Türkçe").tag("tr"); Text("İngilizce").tag("en"); Text("Kendisi anlasın").tag("oto")
                }.pickerStyle(.segmented)
            }
            Section("Kısayol") {
                Picker("Genel kısayol", selection: $kisayol) {
                    ForEach(KisayolSecenegi.hepsi) { s in Text(s.ad).tag(s.id) }
                }
                .onChange(of: kisayol) { _, _ in Kisayol.shared.kur() }
                Text("Kısa bas: başlat / bitir. Basılı tut: konuş, bırakınca biter. Kayıtta Esc: vazgeç.").font(.caption).foregroundStyle(.secondary)
                Toggle("Kayıtta ekranın üstünde küçük pano göster", isOn: $hud)
            }
            Section("Başlık ve sınıf") {
                Toggle("Claude'dan başlık ve özet iste (terminaldeki claude oturumu açıksa)", isOn: $claudeBaslik)
                Text("Kapalıysa ya da oturum yoksa başlığı yerel kural koyar. Bir Claude Code oturumunda \"Kıvılcım'ı düzenle\" demek de aynı işi yapar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Genel") {
                Toggle("Mac açılınca başlat", isOn: $giris).onChange(of: giris) { _, a in
                    if a { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
                LabeledContent("Menü çubuğu simgesi") {
                    Button("Saatin yanına al") { MenuKonumu.sifirlaVeYenidenAc() }
                }
                Text("Çentikli ekranda menü çubuğu dolarsa macOS taşan simgeleri gizler. Simgeyi ⌘ basılı tutup sürükleyerek de taşıyabilirsin.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Veri") {
                    Button("Klasörü göster") { NSWorkspace.shared.activateFileViewerSelecting([depo.kok]) }
                }
                LabeledContent("Günlük") {
                    Button("Aç") { NSWorkspace.shared.open(depo.kayitDosyasi) }
                }
                LabeledContent("Toplam", value: "\(depo.ogeler.count) fikir · \(depo.toplamDakika) dk · \(String(format: "%.1f", depo.toplamMB)) MB")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }
}
