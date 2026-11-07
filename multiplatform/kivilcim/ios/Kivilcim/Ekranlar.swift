// Kaydet · Arşiv · Detay · Ayarlar
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import PDMBus

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

    func degistir(_ o: Oge, baslangic: Double = 0) async {
        let anahtar = o.parent.isEmpty ? o.id : o.parent
        if calan == anahtar, let c = calici, baslangic == 0 {
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
        if baslangic > 0 { c.currentTime = max(0, baslangic - 2) }
        calici = c; calan = anahtar; uzunluk = c.duration; konum = c.currentTime; caliyor = true
        zamanlayici?.invalidate()
        zamanlayici = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in TelefonOynatici.shared.konum = TelefonOynatici.shared.calici?.currentTime ?? 0 }
        }
    }

    /// A sound that is not a Kıvılcım record (a Teoria or Wise Path note under Merkez › Konular).
    func calURL(_ anahtar: String, _ u: URL, baslangic: Double = 0) {
        if calan == anahtar, let c = calici, baslangic == 0 {
            if c.isPlaying { c.pause() } else { c.play() }
            caliyor = c.isPlaying; return
        }
        guard let c = try? AVAudioPlayer(contentsOf: u) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        calici?.stop()
        c.delegate = self; c.enableRate = true; c.rate = hiz
        c.play()
        if baslangic > 0 { c.currentTime = max(0, baslangic - 2) }
        calici = c; calan = anahtar; uzunluk = c.duration; konum = c.currentTime; caliyor = true
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
    @State private var ayarlar = false

    var bugun: [Oge] { depo.ogeler.filter { Calendar.current.isDateInToday($0.zaman) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !merkez.kayitta {
                    Picker("Kayıt türü", selection: $merkez.kind) {
                        Label("Kıvılcım", systemImage: "sparkles").tag("spark")
                        Label("Günlük", systemImage: "book.pages").tag("journal")
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 40).padding(.top, 8)
                }
                Spacer(minLength: 12)
                ust
                Spacer(minLength: 12)
                dugme
                Text(merkez.kayitta ? "Dokun: bitir" : merkez.kind == "journal" ? "Dokun: günlüğe başla · fikirde “kıvılcım” de" : "Dokun: başlat · basılı tut: bas-konuş")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 14)
                if merkez.kayitta {
                    HStack(spacing: 22) {
                        Button("Vazgeç", role: .destructive) { Task { await merkez.vazgec() } }
                        Button(merkez.duraklatildi ? "Devam" : "Duraklat") { Task { await merkez.duraklatDegistir() } }
                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    Button { ayarlar = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ayarlar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if depo.esitleniyor { ProgressView() }
                    else if !kasa.bagli { Image(systemName: "icloud.slash").foregroundStyle(.orange) }
                    else if depo.gonderilmemis > 0 { Label("\(depo.gonderilmemis)", systemImage: "arrow.up.circle").foregroundStyle(.orange) }
                    else if depo.bulutBekleyen > 0 { Label("\(depo.bulutBekleyen)", systemImage: "icloud.and.arrow.up").foregroundStyle(.orange) }
                }
            }
            .sheet(item: $secili) { o in NavigationStack { DetayEkrani(id: o.id) } }
            .sheet(isPresented: $ayarlar) { AyarlarEkrani() }
            .sheet(item: Binding(get: { merkez.hizliDuzen.map(KimlikSarici.init) }, set: { merkez.hizliDuzen = $0?.id })) { k in
                HizliDuzenSayfasi(id: k.id).presentationDetents([.medium, .large])
            }
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
                RecordingClock(meter: merkez.meter)
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                MeterBars(meter: merkez.meter, adet: 34).frame(height: 54).padding(.horizontal, 30)
                Text("\(merkez.aktifTur == "journal" ? "Sesli günlük · en çok 60 dk" : "Kıvılcım") · \(merkez.kaliteSecimi.ad)").font(.caption).foregroundStyle(.secondary)
                if let t = merkez.activeTopic {
                    // the name comes from a record already linked to the same topic; otherwise the id itself
                    let ad = t.hasPrefix("k:") ? String(t.dropFirst(2)) : (depo.ogeler.first { $0.topic == t && !$0.topic_name.isEmpty }?.topic_name ?? t)
                    Label("Konu: \(ad)", systemImage: "book.closed").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else {
            VStack(spacing: 8) {
                Text(merkez.kind == "journal" ? "Gününü anlat" : "Aklına geleni söyle").font(.title2.weight(.semibold))
                Text(bugun.isEmpty ? "Bugün henüz fikir yok" : "Bugün \(bugun.count) fikir · \(Int(bugun.reduce(0) { $0 + $1.sure } / 60)) dk")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let h = merkez.hata { Text(h).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal) }
                if !kasa.bagli {
                    Button { ayarlar = true } label: { Label("Vault klasörünü bağla", systemImage: "folder.badge.plus") }
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
                if basildigindaKayittaydi || (tutuldu && merkez.kayitta) { Tani.yaz("uygulama düğmesi: bitir"); Task { await merkez.bitir() } }
            })
        .onChange(of: merkez.kayitta) { _, k in nabiz = k }
        .accessibilityLabel(merkez.kayitta ? "Kaydı bitir" : "Kaydı başlat")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var sonKayit: some View {
        // newest recordings first (incl. a journal), so what was just said is always in sight
        let sira = Array(depo.ogeler.filter { $0.kind != "extract" || Calendar.current.isDateInToday($0.zaman) }.prefix(3))
        if !sira.isEmpty && !merkez.kayitta {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Son kayıtlar · \(depo.acik.count) açık").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Tümü") { sekme = 1 }.font(.subheadline)
                }
                ForEach(sira) { o in
                    KaydirmaliKart(yildizli: o.yildiz, sil: { depo.duzelt(o, "status", "done") },
                                   yildiz: { depo.duzelt(o, "priority", o.priority == 3 ? 1 : o.priority + 1) }) {
                        OgeKarti(o: o).contentShape(Rectangle()).onTapGesture { secili = o }
                            .accessibilityAddTraits(.isButton)
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(.snappy, value: sira.map(\.id))
        }
    }
}

struct KimlikSarici: Identifiable { let id: String }

/// Liste dışındaki kart için kaydırma (Kaydet ekranı): sağa çek → yapıldı, sola çek → öncelik bir basamak yukarı.
/// Eşiği geçince dokunsal tık; bırakınca uygulanır, geçmezse yerine yaylanır.
struct KaydirmaliKart<Icerik: View>: View {
    let yildizli: Bool
    let sil: () -> Void
    let yildiz: () -> Void
    @ViewBuilder let icerik: Icerik
    @State private var x: CGFloat = 0
    @State private var yatay: Bool?
    private let esik: CGFloat = 96

    var body: some View {
        icerik.offset(x: x).background {
            HStack {
                Label("Yapıldı", systemImage: "checkmark").opacity(x > 8 ? 1 : 0).scaleEffect(x > esik ? 1.15 : 1)
                Spacer()
                Label("Öncelik", systemImage: "flag.fill")
                    .opacity(x < -8 ? 1 : 0).scaleEffect(x < -esik ? 1.15 : 1)
            }
            .labelStyle(.iconOnly).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(x >= 0 ? Color.green : Color.orange) }
            .opacity(x == 0 ? 0 : 1)
            .animation(.snappy(duration: 0.18), value: x > esik || x < -esik)
        }
        .gesture(DragGesture(minimumDistance: 14)
            .onChanged { g in
                if yatay == nil { yatay = abs(g.translation.width) > abs(g.translation.height) }
                guard yatay == true else { return }
                let w = g.translation.width
                x = abs(w) > esik * 1.6 ? w.sign == .minus ? -esik * 1.6 - (abs(w) - esik * 1.6) * 0.3 : esik * 1.6 + (w - esik * 1.6) * 0.3 : w
            }
            .onEnded { _ in
                defer { yatay = nil }
                if x > esik {
                    withAnimation(.easeIn(duration: 0.2)) { x = 600 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(.snappy) { sil() } }
                } else {
                    if x < -esik { yildiz() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { x = 0 }
                }
            })
        .sensoryFeedback(.impact(weight: .medium), trigger: x > esik)
        .sensoryFeedback(.impact(weight: .light), trigger: x < -esik)
    }
}

struct OgeKarti: View {
    @EnvironmentObject var depo: TelefonDeposu
    let o: Oge
    var sorgu = ""
    var body: some View {
        let al = depo.siniflar.alan(o.alan)
        HStack(alignment: .top, spacing: 12) {
            DoneCheck(o: o, size: 26).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if o.yildiz { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(o.baslik).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                }
                if !sorgu.isEmpty || !o.ozet.isEmpty {
                    Text(sorgu.isEmpty ? o.ozet : Arama.parca(o, sorgu)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(o.prio.name).foregroundStyle(o.prio.color)
                    Text("·"); Text(al.ad); Text("·"); Text(Zaman.goreli(o.zaman))
                    if o.durum == "yerel" { Image(systemName: "iphone").foregroundStyle(.orange) }
                    else if !o.islendi { Image(systemName: "hourglass").foregroundStyle(.orange) }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)) }
        .overlay(alignment: .leading) {
            if o.priority >= Priority.high.rawValue { UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(o.prio.color).frame(width: 5) }
        }
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
                                    Button { depo.duzelt(o, "status", o.isDone ? "open" : "done") } label: { Label(o.isDone ? "Aç" : "Yapıldı", systemImage: "checkmark") }.tint(.green)
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
            .navigationTitle("Tümü")
            .navigationDestination(for: String.self) { DetayEkrani(id: $0) }
            .searchable(text: $sorgu, prompt: "Başlık, döküm, not, etiket")
            .refreshable { await depo.gonder() }
        }
    }

    private var suzgecler: some View {
        ScrollView(.horizontal) {
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
        .scrollIndicators(.hidden)
    }
}

struct Cip: View {
    let ad: String; let simge: String; let renk: Color; let secili: Bool; let eylem: () -> Void
    var body: some View {
        Button(action: eylem) {
            Label(ad, systemImage: simge).font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(secili ? .white : renk)
                .background { Capsule().fill(secili ? AnyShapeStyle(renk) : AnyShapeStyle(renk.opacity(0.12))) }
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
                            }.accessibilityLabel(o.yildiz ? "Yıldızı kaldır" : "Yıldızla").buttonStyle(.bordered).sensoryFeedback(.impact, trigger: o.yildiz)
                        }
                        if !o.etiketler.isEmpty {
                            Text(o.etiketler.map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(.secondary)
                        }
                        if !o.isJournal {
                            PrioritySelector(selected: o.priority) { depo.duzelt(o, "priority", $0.rawValue) }
                            Button { withAnimation(.snappy) { depo.duzelt(o, "status", o.isDone ? "open" : "done") } } label: {
                                Label(o.isDone ? "Yapıldı · yeniden aç" : "Yapıldı işaretle",
                                      systemImage: o.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                            }
                            .buttonStyle(.glassProminent).tint(o.isDone ? .gray : .green)
                            .sensoryFeedback(.success, trigger: o.isDone)
                            if let g = o.daysToArchive {
                                Text("\(g) gün sonra vault'taki Kıvılcım/Arşiv klasörüne taşınır.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if o.kind == "extract", let j = depo.oge(o.parent) {
                            Button { Task { await oy.degistir(o, baslangic: o.offset) } } label: {
                                Label("Sesli günlükten · \(Zaman.gunBasligi(j.zaman)) \(Zaman.sure(o.offset))'tan dinle", systemImage: "book.pages")
                                    .font(.subheadline)
                            }.buttonStyle(.bordered).tint(.indigo)
                        }
                    }
                    if o.kind == "isaret" {
                        if !o.simdi.isEmpty {
                            Label(o.simdi, systemImage: "sparkles").font(.subheadline).foregroundStyle(.orange)
                        }
                        if let u = URL(string: o.url), !o.url.isEmpty {
                            Link(destination: u) {
                                Label(u.host ?? o.url, systemImage: "link").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                            }.buttonStyle(.bordered).tint(.orange)
                        }
                    }
                    if !(o.kind == "isaret" && o.ses.isEmpty) { calar(o, al.color) }
                    if !o.ozet.isEmpty {
                        Text(o.ozet).font(.body).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background { RoundedRectangle(cornerRadius: 12).fill(al.color.opacity(0.1)) }
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
                    if o.isJournal { cocukBolumu(o) }
                    notBolumu(o)
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
                        if !o.journal_note.isEmpty, let u = obsidianURL(o.journal_note) { Link(destination: u) { Label("Günlüğü Obsidian'da aç", systemImage: "book") } }
                        if !o.not.isEmpty, let u = obsidianURL(veriKlasoruYolu + "/" + o.not) { Link(destination: u) { Label("Obsidian'da aç", systemImage: "arrow.up.forward.app") } }
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

    @State private var yeniNot = ""
    @FocusState private var notOdak: Bool

    @ViewBuilder private func notBolumu(_ o: Oge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notlarım").font(.headline)
            ForEach(o.notes, id: \.self) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.text).font(.body)
                    Text(Zaman.coz(n.t).map(Zaman.goreli) ?? "").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            }
            HStack(alignment: .bottom) {
                TextField("Not ekle…", text: $yeniNot, axis: .vertical).lineLimit(1...6).focused($notOdak)
                Button {
                    depo.duzelt(o, "note", yeniNot.trimmingCharacters(in: .whitespacesAndNewlines)); yeniNot = ""; notOdak = false
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(yeniNot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Notu ekle")
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            Text("Not, Obsidian'daki notun Notlarım bölümüne eklenir.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func cocukBolumu(_ j: Oge) -> some View {
        let c = depo.cocuklar(j)
        VStack(alignment: .leading, spacing: 8) {
            Text("Ayıklanan kıvılcımlar").font(.headline)
            if c.isEmpty {
                Text("Konuşmada “kıvılcım” dediğin yerler ve Claude'un önerdikleri Mac işleyince burada görünür.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(c) { k in
                HStack(spacing: 10) {
                    DoneCheck(o: k)
                    VStack(alignment: .leading) {
                        Text(k.baslik).font(.subheadline.weight(.semibold))
                        Text(Zaman.sure(k.offset)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await oy.degistir(k, baslangic: k.offset) } } label: { Image(systemName: "play.circle") }
                        .accessibilityLabel("Bu yerden dinle")
                }
            }
            if !j.journal_note.isEmpty {
                Text("Tam metin: \(j.journal_note.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: ".md", with: "") ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func obsidianURL(_ yol: String) -> URL? {
        var c = URLComponents(string: "obsidian://open")
        c?.queryItems = [URLQueryItem(name: "vault", value: "Personel Data Management"), URLQueryItem(name: "file", value: yol)]
        return c?.url
    }

    private func kaydet(_ o: Oge) {
        let b = baslik.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty, b != o.baslik { depo.duzelt(o, "baslik", b) }
    }

    private func calar(_ o: Oge, _ renk: Color) -> some View {
        let bu = oy.calan == (o.parent.isEmpty ? o.id : o.parent)
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
                            Button { oy.ileri(-10) } label: { Image(systemName: "gobackward.10") }.accessibilityLabel("10 saniye geri")
                            Button { oy.hiz = oy.hiz == 1 ? 1.5 : oy.hiz == 1.5 ? 2 : 1 } label: { Text(oy.hiz == 1 ? "1×" : oy.hiz == 1.5 ? "1,5×" : "2×").monospacedDigit() }
                            Button { oy.ileri(10) } label: { Image(systemName: "goforward.10") }.accessibilityLabel("10 saniye ileri")
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
        .background { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)) }
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
                    if depo.bulutBekleyen > 0 {
                        Label("\(depo.bulutBekleyen) kayıt iCloud'da yüklenmeyi bekliyor; Mac'e henüz gitmedi", systemImage: "icloud.and.arrow.up")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let h = depo.bulutHata { Text("iCloud: \(h)").font(.caption).foregroundStyle(.red) }
                } header: { Text("Vault") } footer: {
                    Text("iCloud Drive › Obsidian › Personel Data Management'ı seç. Kayıtlar 05 - Notlar/Fikirler/Kıvılcım altına gider. iCloud takılırsa telefon Mac'e bağlıyken Mac'teki Kıvılcım onları doğrudan alır."
                         + (depo.sonEsitleme.map { " Son eşitleme: \(Zaman.goreli($0))." } ?? ""))
                }
                // the bus needs the vault root; with a subfolder connected above it gets its own folder row here
                PDMSettingsSection(bus: KivilcimBus.shared, selectsVault: kasa.bagli && !Kasa.isVaultRoot(kasa.klasorAdi))
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
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(.white).frame(width: 20, height: 20).background { Circle().fill(Color.kivilcim) }
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
