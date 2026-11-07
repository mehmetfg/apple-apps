// Metin: günün metni tek parça, Türkçesiyle birlikte. Üstte İngilizce · Türkçe · Yan yana seçimi; metin seçilip kopyalanır.
// Altta "Sesli oku ve kaydet": okurken İngilizce kalır, kayıt bitince tanınmayan kelimeler sarı.
// Kayıtlar iPhone ve Mac'te aynı klasöre gider (paket/gun-NNN/kayit/); Mac'te ertesi sabah Whisper'la çözümlenir.
// Kayıtlarım (iki cihazın kayıtları + widget'ta kurulan cümleler) sağ üstteki düğmeden ayrı sayfada.
import SwiftUI

enum MetinGorunumu: String, CaseIterable, Identifiable {
    case ingilizce = "İngilizce", turkce = "Türkçe", yanyana = "Yan yana"
    var id: String { rawValue }
}

struct KayitEkrani: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oynatici: Oynatici
    @StateObject private var k = Kaydedici()
    @AppStorage("metin.gorunum") private var gorunum: MetinGorunumu = .ingilizce
    @State private var kopyalanan: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = depo.guncel {
                        if k.hal == .bitti, let s = k.sonuc { sonucKarti(s) }
                        baslik(p)
                        kagit(p)
                    } else {
                        BosDurum(simge: "doc.text", baslik: "Okunacak metin yok", metin: "Paket telefona inince bütün metin burada durur.")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 30)
            }
            .background(Tema.arka)
            .safeAreaInset(edge: .bottom) {
                if let p = depo.guncel {
                    kayitDugmesi(p)
                        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
                        .background(.bar)
                }
            }
            .navigationTitle("Metin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let p = depo.guncel { kopyaMenusu(p) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        KayitlarimEkrani()
                    } label: {
                        Label("Kayıtlarım", systemImage: "waveform")
                    }
                }
            }
        }
    }

    // MARK: Başlık ve görünüm seçimi

    private func baslik(_ p: Paket) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GÜN \(p.gun)").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            Text(p.ad).font(.system(.title2, design: .serif).weight(.semibold))
            Picker("Görünüm", selection: $gorunum) {
                ForEach(MetinGorunumu.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(k.hal == .kayit)
        }
    }

    private func kopyaMenusu(_ p: Paket) -> some View {
        Menu {
            Button { kopyala(ingilizce(p), "en") } label: { Label("İngilizce metni kopyala", systemImage: "doc.on.doc") }
            Button { kopyala(turkce(p), "tr") } label: { Label("Türkçesini kopyala", systemImage: "character.bubble") }
            Button { kopyala(ikisi(p), "iki") } label: { Label("İkisini birlikte kopyala", systemImage: "text.badge.plus") }
        } label: {
            Image(systemName: kopyalanan == nil ? "doc.on.doc" : "checkmark")
        }
        .accessibilityLabel("Metni kopyala")
    }

    private func ingilizce(_ p: Paket) -> String { p.cumleler.compactMap(\.en).joined(separator: " ") }
    private func turkce(_ p: Paket) -> String { p.cumleler.compactMap(\.tr).joined(separator: " ") }
    private func ikisi(_ p: Paket) -> String {
        p.cumleler.map { [$0.en, $0.tr].compactMap { $0 }.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private func kopyala(_ metin: String, _ kimlik: String) {
        guard PasteboardCopy.write(metin, note: "Metin panoda") else { return }
        kopyalanan = kimlik
        Task {
            try? await Task.sleep(for: .seconds(2))
            if kopyalanan == kimlik { kopyalanan = nil }
        }
    }

    // MARK: Okuma kâğıdı

    private func kagit(_ p: Paket) -> some View {
        let bitti = k.hal == .bitti && k.sonuc?.tanima != nil
        // Kayıt sırasında İngilizce okunur; seçim ne olursa olsun
        let g = k.hal == .kayit ? MetinGorunumu.ingilizce : gorunum
        // Her cümlenin ilk kelimesinin metin içindeki sırası (tanıma karşılaştırmasıyla aynı ayıklama)
        var baslar: [Int] = []
        var n = 0
        for c in p.cumleler { baslar.append(n); n += Metin.kelimeler(c.en ?? "").count }
        return VStack(alignment: .leading, spacing: 12) {
            if k.hal == .kayit {
                Label(Tarih.sure(k.sure), systemImage: "record.circle").font(.subheadline.monospacedDigit()).foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            switch g {
            case .ingilizce:
                // Tek parça: bütün cümleler bir paragrafta akar
                Text(p.cumleler.enumerated().reduce(into: AttributedString()) { a, e in
                    if !a.characters.isEmpty { a += AttributedString(" ") }
                    a += boyali(e.element.en ?? "", bas: baslar[e.offset], bitti: bitti)
                })
                .font(Tema.ingilizce(.title3)).lineSpacing(6)
            case .turkce:
                Text(turkce(p)).font(.title3).lineSpacing(6)
            case .yanyana:
                ForEach(Array(p.cumleler.enumerated()), id: \.element.id) { j, c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(boyali(c.en ?? "", bas: baslar[j], bitti: bitti)).font(Tema.ingilizce(.body)).lineSpacing(3)
                        if let tr = c.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                    }
                    if j < p.cumleler.count - 1 { Divider() }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kart(18)
    }

    /// Tanınan kelime yeşil, tanınmayan sarı — tanıma sonucunun kelime sırasına göre (eslesen).
    private func boyali(_ en: String, bas: Int, bitti: Bool) -> AttributedString {
        var a = AttributedString(en)
        guard bitti else { return a }
        var arama = a.startIndex
        var i = bas
        for parca in en.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let w = String(parca)
            let say = Metin.kelimeler(w).count
            guard say > 0, let r = a[arama...].range(of: w) else { continue }
            if k.eslesen.contains(i) { a[r].foregroundColor = Tema.yesil }
            else { a[r].backgroundColor = Tema.sari.opacity(0.32) }
            arama = r.upperBound
            i += say
        }
        return a
    }

    // MARK: Kayıt düğmesi

    @ViewBuilder
    private func kayitDugmesi(_ p: Paket) -> some View {
        VStack(spacing: 14) {
            switch k.hal {
            case .kayit:
                Dalga(seviyeler: k.seviyeler, renk: .red)
                HStack(spacing: 14) {
                    Button(role: .destructive) { k.vazgec() } label: { Label("Vazgeç", systemImage: "xmark") }
                        .buttonStyle(.bordered)
                    Button {
                        Task {
                            let metin = p.cumleler.compactMap(\.en).joined(separator: " ")
                            if let kb = await k.bitir(metin: metin, gun: p.gun) { depo.kayitEklendi(kb, paket: p) }
                        }
                    } label: { Label("Bitir", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.borderedProminent).tint(.red)
                }
            case .cozuluyor:
                ProgressView("Cihazda yazıya çevriliyor…").padding()
            case .bitti:
                Button { k.sifirla() } label: { Label("Bir daha oku", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity).padding(.vertical, 4) }
                    .buttonStyle(.bordered)
            case .izinYok:
                Text("Mikrofon izni yok. Ayarlar › Memories › Mikrofon'dan açabilirsin. Bu adım isteğe bağlı; geçebilirsin.")
                    .font(.callout).foregroundStyle(.secondary)
            case .hata(let m):
                Text(m).font(.callout).foregroundStyle(.secondary)
                Button("Tekrar dene") { k.sifirla() }
            case .bos:
                Button {
                    oynatici.duraklat()
                    Task { await k.baslat(gun: p.gun, klasor: depo.kayitKlasoru) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill").font(.title2)
                        Text("Sesli oku ve kaydet").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background { Capsule().fill(Color.red.gradient) }
                }
                .buttonStyle(.plain)
                .dokun(depo, k.hal)
                Text("Kayıt Mac'e de gider; ertesi sabah okunuşun metinle karşılaştırılır.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sonucKarti(_ s: KayitBilgisi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let t = s.tanima {
                    Text("%\(Int(t * 100))").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(Tema.yesil)
                    Text("tanındı").foregroundStyle(.secondary)
                } else {
                    Text("Kaydedildi").font(.headline)
                }
                Spacer()
                Text(Tarih.sure(s.sure ?? 0)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Button { k.cal(depo.kayitURL(s), kimlik: s.ad) } label: {
                    Image(systemName: k.calan == s.ad ? "stop.circle.fill" : "play.circle.fill").font(.title)
                }.accessibilityLabel(k.calan == s.ad ? "Durdur" : "Dinle")
            }
            if let t = s.takilan, !t.isEmpty {
                Text("Kontrol et (sarı):").font(.caption).foregroundStyle(.secondary)
                FlowCipler(kelimeler: t)
            } else if s.tanima != nil {
                Label("Bütün kelimeler tanındı.", systemImage: "checkmark.seal").foregroundStyle(Tema.yesil)
            }
            if s.tanima == nil {
                Text("Cihaz içi tanıma bu telefonda yok ya da izin verilmedi; kayıt yine saklandı, Mac'te çözümlenecek.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Sarı hata değildir — aksan payı var. Mac'te Whisper ikinci kez bakar.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .kart()
    }
}

// MARK: - Kayıtlarım (ayrı sayfa)

struct KayitlarimEkrani: View {
    @EnvironmentObject var depo: Depo
    @StateObject private var k = Kaydedici()
    @State private var silinecek: KayitBilgisi?
    @State private var rebuilds: [RebuildRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                kayitlarim
                if !rebuilds.isEmpty { rebuildList }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(Tema.arka)
        .navigationTitle("Kayıtlarım")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { rebuilds = RebuildRecord.all() }
        .onDisappear { k.durdur() }
        .confirmationDialog("Bu kayıt silinsin mi?", isPresented: Binding(get: { silinecek != nil }, set: { if !$0 { silinecek = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let s = silinecek { depo.kayitSil(s) }; silinecek = nil }
        } message: { Text("Telefondan ve vault'tan silinir. Geri alınamaz.") }
    }

    private var kayitlarim: some View {
        let gunler = Dictionary(grouping: depo.kayitlar, by: \.gun).sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Sesli okumalar").font(.title3.weight(.semibold)).padding(.top, 8)
            if gunler.isEmpty {
                Text("Henüz kayıt yok.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(gunler, id: \.key) { gun, liste in
                VStack(alignment: .leading, spacing: 0) {
                    Text("Gün \(gun)" + (depo.paketler.first { $0.gun == gun }.map { " · \($0.ad)" } ?? ""))
                        .font(.subheadline.weight(.semibold)).padding(.bottom, 6)
                    ForEach(liste.sorted { $0.zaman > $1.zaman }) { s in
                        kayitSatiri(s)
                        if s.id != liste.last?.id { Divider() }
                    }
                }
                .kart(14)
            }
        }
    }

    private func kayitSatiri(_ s: KayitBilgisi) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.cihaz == "iphone" ? "iphone" : "laptopcomputer").foregroundStyle(Tema.vurgu).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.zaman.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.callout)
                HStack(spacing: 6) {
                    if let su = s.sure { Text(Tarih.sure(su)) }
                    if let t = s.tanima { Text("· %\(Int(t * 100)) tanındı") }
                    Image(systemName: s.vaultta ? "checkmark.icloud" : "icloud.and.arrow.up").foregroundStyle(s.vaultta ? Tema.yesil : .secondary)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    if s.yerelde || FileManager.default.fileExists(atPath: depo.kayitURL(s).path) {
                        k.cal(depo.kayitURL(s), kimlik: s.ad)
                    } else if let u = await depo.kayitIndir(s) {
                        k.cal(u, kimlik: s.ad)
                    }
                }
            } label: {
                Image(systemName: k.calan == s.ad ? "stop.circle.fill" : (s.yerelde ? "play.circle" : "icloud.and.arrow.down"))
                    .font(.title2)
            }
            .buttonStyle(.plain).foregroundStyle(Tema.vurgu)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(role: .destructive) { silinecek = s } label: { Label("Sil", systemImage: "trash") }
        }
    }
}

// MARK: Sentences built from the widget

extension KayitlarimEkrani {
    /// "Cümle cümle" widget's 🎙 recordings: the target sentence, what was heard, the score; tap to listen.
    var rebuildList: some View {
        let days = Dictionary(grouping: rebuilds, by: \.day).sorted { $0.key > $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Kurduğun cümleler").font(.title3.weight(.semibold)).padding(.top, 8)
            Text("Widget'ta ya da Oku'da 🎙 Kur ile. Mac'e de gider (kurma/); istediğinde Claude değerlendirir.").font(.caption).foregroundStyle(.secondary)
            ForEach(days, id: \.key) { day, list in
                VStack(alignment: .leading, spacing: 0) {
                    Text("Gün \(day)").font(.subheadline.weight(.semibold)).padding(.bottom, 6)
                    ForEach(list.sorted { $0.recordedAt > $1.recordedAt }, id: \.file) { r in
                        rebuildRow(r)
                        if r.file != list.last?.file { Divider() }
                    }
                }
                .kart(14)
            }
        }
    }

    private func rebuildRow(_ r: RebuildRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(r.target).font(Tema.ingilizce(.callout))
                if let h = r.heard { Text("Duyulan: \(h)").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    if let x = r.ratio { Text("%\(Int((x * 100).rounded()))").foregroundStyle(x >= 0.85 ? Tema.yesil : Tema.kehribarYazi) }
                    Text("· \(Fade.label(r.rung))")
                    if let m = r.missed, !m.isEmpty { Text("· " + m.joined(separator: ", ")) }
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { k.cal(RebuildState.folder.appendingPathComponent(r.file), kimlik: r.file) } label: {
                Image(systemName: k.calan == r.file ? "stop.circle.fill" : "play.circle").font(.title2)
            }
            .buttonStyle(.plain).foregroundStyle(Tema.vurgu)
            .accessibilityLabel(k.calan == r.file ? "Durdur" : "Dinle")
        }
        .padding(.vertical, 8)
    }
}

extension RebuildRecord {
    /// Every recording still on the phone (App Group kurma/), newest day first.
    static func all() -> [RebuildRecord] {
        let dir = RebuildState.folder
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .compactMap { try? d.decode(RebuildRecord.self, from: Data(contentsOf: dir.appendingPathComponent($0))) }
    }
}

/// Kelime çipleri, satıra sığmayan alta geçer.
struct FlowCipler: View {
    var kelimeler: [String]
    var body: some View {
        AkisDuzeni(aralik: 6) {
            ForEach(kelimeler, id: \.self) { w in
                Text(w).font(Tema.ingilizce(.callout))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background { RoundedRectangle(cornerRadius: 6).fill(Tema.sari.opacity(0.26)) }
            }
        }
    }
}

struct AkisDuzeni: Layout {
    var aralik: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > w, x > 0 { x = 0; y += satir + aralik; satir = 0 }
            x += b.width + aralik; satir = max(satir, b.height)
        }
        return CGSize(width: w, height: y + satir)
    }
    func placeSubviews(in r: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = r.minX, y = r.minY, satir: CGFloat = 0
        for s in subviews {
            let b = s.sizeThatFits(.unspecified)
            if x + b.width > r.maxX, x > r.minX { x = r.minX; y += satir + aralik; satir = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += b.width + aralik; satir = max(satir, b.height)
        }
    }
}
