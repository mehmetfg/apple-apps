// Atölye — Mac'te düşünmeyi tatbik etme yeri. Tek amaç: soyut, yüksek ve etkili düşünmeyi basamak basamak çalışmak.
// Düzen: solda dokuz basamaklı YOL (basitten zora, her biri düz Türkçeyle), ortada tek sütun:
//   ① kılavuz kartı (ne · neden · nasıl · örnek) → ② üç aşama çubuğu (Oku · Yaz · Karşılaştır) → ③ iş → ④ sonuç, hepsi aynı sayfada.
// Sağda sonradan açılan sütun yok: neyin olup bittiği aynı sayfada, aşağıya doğru akar.
// Her cevap aynı olay günlüğüne yazılır (iPhone'la eşit); oturum kapanınca bir kür sayılır.
// Kısayollar: 1-4 şık seç (kavramı işlet) · ⌘⏎ gönder · ⌘I ipucu · 1-4 kendini değerlendir · ⌘→ sonraki.
import SwiftUI

/// Dokuz basamak, basitten zora. Sıra = tırmanış sırası; her basamak bir öncekinin üstüne kurulur.
enum AtolyeKipi: String, CaseIterable, Identifiable {
    case concept, anahtar, gundelik, ayirt, fikir, taklit, arguman, paragraf, aforizma
    var id: String { rawValue }
    var no: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var ad: String {
        switch self {
        case .concept: "Kavramı işlet"
        case .anahtar: "Cümleyi yeniden kur"
        case .gundelik: "Günlük dilden kavrama"
        case .ayirt: "İki kavramın farkı"
        case .fikir: "Fikri cümleye dök"
        case .taklit: "Yapıyı taklit et"
        case .arguman: "Kısa argüman"
        case .paragraf: "Bir paragraf kur"
        case .aforizma: "Kendi aforizman"
        }
    }

    var sembol: String {
        switch self {
        case .concept: "checklist"
        case .anahtar: "key"
        case .gundelik: "arrow.up.forward.circle"
        case .ayirt: "arrow.left.arrow.right"
        case .fikir: "lightbulb"
        case .taklit: "square.on.square"
        case .arguman: "point.3.connected.trianglepath.dotted"
        case .paragraf: "text.alignleft"
        case .aforizma: "quote.opening"
        }
    }

    /// Soldaki listede adın altında tek satır.
    var kisa: String {
        switch self {
        case .concept: "örnekte tanı, ayır, uygula"
        case .anahtar: "verilen kelimelerle"
        case .gundelik: "sıradan cümle → kavram"
        case .ayirt: "yakın iki kavramı ayır"
        case .fikir: "bulanık fikir → net cümle"
        case .taklit: "iskeleti al, konuyu değiştir"
        case .arguman: "iddia + gerekçe"
        case .paragraf: "iddia, gerekçe, örnek"
        case .aforizma: "tek cümle, karşıtlıkla"
        }
    }

    var ne: String {
        switch self {
        case .concept: "Bir kavram hakkında çok seçmeli bir soru gelir: onu bir örnekte tanırsın, yakın komşusundan ayırırsın ya da bir duruma uygularsın."
        case .anahtar: "Önemli bir cümlenin anahtar kelimeleri verilir. Cümleyi kendi sözünle yeniden kurarsın."
        case .gundelik: "Gündelik bir cümle verilir. Aynı şeyi kavramlarla söylersin."
        case .ayirt: "Birbirine yakın iki kavram verilir. Aradaki farkı kendi cümlenle söylersin."
        case .fikir: "Cümle yok, yalnız bir fikir var. Cümleyi sen kurarsın."
        case .taklit: "İyi kurulmuş bir cümlenin iskeletini alır, başka bir konuya uygularsın."
        case .arguman: "Bir iddia yazar, hemen ardından gerekçesini söylersin. İki üç cümle."
        case .paragraf: "Üç cümlelik küçük bir bütün: iddia, gerekçe, örnek."
        case .aforizma: "Bir fikri tek cümleye sıkıştırırsın, tercihen bir karşıtlıkla."
        }
    }

    var neden: String {
        switch self {
        case .concept: "Bir kavramın tanımını bilmek yetmez; onu iş başında görebilmek gerekir. Örnekte tanıyabildiğin kavram, üzerine düşünebileceğin kavramdır."
        case .anahtar: "Bir fikri başkasının kelimeleriyle yeniden kurabiliyorsan anlamışsındır. Yalnızca tanıyorsan henüz anlamış sayılmazsın."
        case .gundelik: "Yüksek düşünme, sıradan bir olayı ortak bir kavrama bağlayabilmektir. Bu, olaylardan kalıp çıkarma alışkanlığıdır."
        case .ayirt: "Ayırt edemediğin iki kavram, aklında tek bulanık fikir olarak durur. Net düşünme farkı görmekle başlar."
        case .fikir: "Bulanık bir fikri net bir cümleye çevirmek, yazarak düşünmenin ilk adımıdır. Cümle kuramıyorsan fikir henüz fikir değildir."
        case .taklit: "Usta yazarlar da önce taklit eder. Yapı zihne yerleşince kendi cümlen kendiliğinden akmaya başlar."
        case .arguman: "Etkili düşünme, bir iddiayı gerekçeyle taşıyabilmektir. Gerekçesiz iddia yalnızca fikir beyanıdır."
        case .paragraf: "Fikri küçük bir bütün olarak kurabilmek, yazıya ve konuşmaya geçişin eşiğidir."
        case .aforizma: "Bir fikri en yoğun hâline sıkıştırabilmek, onu gerçekten anladığının sınavıdır."
        }
    }

    var nasil: String {
        switch self {
        case .concept: "Soruyu ve varsa durumu oku → şıklardan birini seç (1–4) → açıklamayı oku → sonraki soru."
        case .anahtar: "Kelimelere bak → cümleyi yaz → Gönder → kaynak cümleyle karşılaştır."
        case .gundelik: "Cümleyi oku → kavramlarla yeniden yaz → Gönder → örnekle karşılaştır."
        case .ayirt: "İki kavrama bak → farkı bir iki cümleyle yaz → Gönder → örnekle karşılaştır."
        case .fikir: "Fikri oku → cümleni kur → Gönder → kaynak cümleyle karşılaştır. Takılırsan ⌘I ile ipucu al."
        case .taklit: "Örnek yapıyı oku → aynı iskelette başka bir konu yaz → Gönder → örnekle karşılaştır."
        case .arguman: "İddiayı yaz, “çünkü” ile gerekçeni ekle → Gönder → örnek argümanla karşılaştır."
        case .paragraf: "Üç cümle yaz: önce iddia, sonra gerekçe, sonra örnek → Gönder → karşılaştır."
        case .aforizma: "Fikri seç → tek cümleye sıkıştır → Gönder → örnekle karşılaştır."
        }
    }

    var ornek: String {
        switch self {
        case .concept: "“Hangisi kategorik buyruktur?”  →  “Yalan söyleme.” Öteki şıklar (“Sevilmek istiyorsan yalan söyleme.”) koşula bağlıdır."
        case .anahtar: "Kelimeler: bilgi · deneyim · sınır.  →  “Bilginin sınırı, deneyimin bittiği yerde başlar.”"
        case .gundelik: "“Onu tanıyınca fikrim değişti.”  →  “Deneyim, önyargıyı çürüttü.”"
        case .ayirt: "Bilgi ile bilinç: bilgi bir şeyi bilmektir, bilinç ise bildiğini bilmektir."
        case .fikir: "Fikir: bilmek, sınırı fark etmeyi gerektirir.  →  “Bir şeyi bildiğini ancak sınırını gördüğünde söyleyebilirsin.”"
        case .taklit: "İskelet: “X, Y'nin yokluğunda değil, Z'nin varlığında doğar.”  →  “Cesaret, korkunun yokluğunda değil, ona rağmen doğar.”"
        case .arguman: "“Özgürlük sorumluluk ister, çünkü seçimin sonucunu senin yerine kimse taşıyamaz.”"
        case .paragraf: "“Okumak yetmez, yazmak gerekir. Çünkü yazarken bulanık düşünce kendini ele verir. Örneğin cümle kuramadığın fikri aslında anlamamışsındır.”"
        case .aforizma: "“Bilmek, bilmediğini bilmekle başlar.”"
        }
    }

    /// Sol yolda gruplama.
    var evre: String { no <= 3 ? "Temel" : (no <= 6 ? "Orta" : "İleri") }

    var hat: Hat {
        switch self {
        case .concept, .gundelik, .ayirt, .arguman, .aforizma: .donustur
        case .anahtar, .fikir, .taklit, .paragraf: .kur
        }
    }

    /// Kipin merdivendeki kademesi (kavramı işlet = Dönüştür K1, kürdeki kavram soruları).
    var kademe: Int {
        switch self {
        case .concept: 1
        case .gundelik, .anahtar: 3
        case .ayirt, .fikir: 4
        case .arguman, .taklit: 5
        case .aforizma, .paragraf: 6
        }
    }
}

struct AtolyeEkrani: View {
    @EnvironmentObject var depo: Depo

    @State private var kip: AtolyeKipi = .concept
    @State private var kipSecildi = false
    @State private var isler: [Alistirma] = []
    @State private var seciliIs: String?
    @State private var sayim: [AtolyeKipi: (biten: Int, toplam: Int)] = [:]
    @State private var rehberAcik = true

    // Oturum
    @State private var kurId = UUID().uuidString
    @State private var baslangic = Date()
    @State private var yapilan: [Olay] = []

    // Yazma işi durumu
    @State private var yazi = ""
    @State private var ipucu = 0
    @State private var gonderildi = false
    @State private var oneri: Double = 0
    @State private var kartBasi = Date()
    @FocusState private var odak: Bool

    // Kavramı işlet durumu: seçilen şık
    @State private var chosen: String?

    /// `ilk` verilirse o basamak doğrudan açılır (önizleme ve sınama).
    init(ilk: AtolyeKipi? = nil) {
        _kip = State(initialValue: ilk ?? .concept)
        _kipSecildi = State(initialValue: ilk != nil)
    }

    var aktifIs: Alistirma? { isler.first { $0.id == seciliIs } ?? isler.first }

    /// Önerilen basamak: üç işi bitmemiş ilk basamak; hepsi üçü geçtiyse en çok bekleyen.
    var onerilen: AtolyeKipi {
        AtolyeKipi.allCases.first { k in
            let s = sayim[k] ?? (0, 0)
            return s.toplam > 0 && s.biten < min(3, s.toplam)
        } ?? AtolyeKipi.allCases.max { (sayim[$0]?.toplam ?? 0) - (sayim[$0]?.biten ?? 0) < (sayim[$1]?.toplam ?? 0) - (sayim[$1]?.biten ?? 0) } ?? .concept
    }

    var body: some View {
        HStack(spacing: 0) {
            yol
                .frame(width: 300)
                .background(Tema.yuzey.opacity(0.5))
            Rectangle().fill(Tema.cizgi).frame(width: 0.5)
            VStack(spacing: 0) {
                if kipSecildi {
                    ustBilgi
                    Rectangle().fill(Tema.cizgi).frame(height: 0.5)
                }
                ScrollView {
                    Group {
                        if !kipSecildi { karsilama } else { calisma }
                    }
                    .padding(.horizontal, 44).padding(.vertical, 30)
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Tema.arka)
        .onAppear { sayimlariYenile(); if kipSecildi { isleriKur() } }
        .onChange(of: kip) { _, _ in
            isleriKur()
            rehberAcik = (sayim[kip]?.biten ?? 0) < 2
        }
        .onDisappear { oturumuKapat() }
    }

    // MARK: Sol: yol

    private var yol: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Atölye").font(Tema.serif(.title, .bold)).foregroundStyle(Tema.metin)
                    Text("Düşünmeyi tatbik edersin: dokuz basamak, basitten zora. Hepsi açık; önerilen sıra işaretli.")
                        .font(.system(size: 13)).foregroundStyle(Tema.ikincil)
                }
                .padding(.bottom, 4)
                ForEach(["Temel", "Orta", "İleri"], id: \.self) { evre in
                    Text(evre.uppercased(with: Dil.tr)).font(.system(size: 11, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Tema.soluk).padding(.top, 6)
                    ForEach(AtolyeKipi.allCases.filter { $0.evre == evre }) { k in basamak(k) }
                }
            }
            .padding(18)
        }
    }

    private func basamak(_ k: AtolyeKipi) -> some View {
        let s = sayim[k] ?? (0, 0)
        let secili = kipSecildi && kip == k
        let oner = k == onerilen
        let renk = Tema.hat(k.hat)
        return Button {
            withAnimation(.snappy) { kip = k; kipSecildi = true }
            isleriKur()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(s.toplam > 0 && s.biten >= s.toplam ? renk : (secili ? renk.opacity(0.16) : Tema.yuzey2))
                    if s.toplam > 0 && s.biten >= s.toplam {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Text("\(k.no)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(secili ? renk : Tema.ikincil)
                    }
                    if oner && !secili { Circle().strokeBorder(Tema.vurgu, lineWidth: 2).padding(-3) }
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(k.ad).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Tema.metin).lineLimit(1)
                        if oner { Hap(metin: "önerilen", renk: Tema.vurgu).scaleEffect(0.8, anchor: .leading) }
                    }
                    Text(k.kisa).font(.system(size: 12)).foregroundStyle(Tema.ikincil).lineLimit(1)
                    if s.toplam > 0 {
                        HStack(spacing: 6) {
                            ProgressView(value: Double(min(s.biten, s.toplam)), total: Double(max(s.toplam, 1)))
                                .progressViewStyle(.linear).tint(renk).frame(width: 90)
                            Text("\(s.biten)/\(s.toplam)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Tema.soluk)
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(secili ? Tema.yuzey : .clear))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(secili ? renk.opacity(0.5) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Karşılama

    private var karsilama: some View {
        let o = onerilen
        return VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BUGÜN").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Tema.soluk)
                Text("Düşünmeyi çalış").font(Tema.serif(.largeTitle, .bold)).foregroundStyle(Tema.metin)
                Text("Burada bir şey ezberlemezsin. Soyut düşünmeyi, kavramlarla konuşmayı ve fikri net bir cümleye dökmeyi kısa işlerle tatbik edersin. Her iş birkaç dakikadır.")
                    .font(Tema.serif(.title3)).foregroundStyle(Tema.ikincil).lineSpacing(3)
            }
            Yuzey(dolgu: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Bolumbasi(metin: "Önerilen başlangıç", sembol: "arrow.turn.down.right", renk: Tema.vurgu)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(o.no)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Tema.hat(o.hat))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(o.ad).font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                            Text(o.ne).font(.callout).foregroundStyle(Tema.ikincil)
                        }
                    }
                    Button { withAnimation(.snappy) { kip = o; kipSecildi = true }; isleriKur() } label: { Text("Başla") }
                        .buttonStyle(AnaDugme()).frame(width: 160)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Bolumbasi(metin: "Nasıl işler", sembol: "questionmark.circle")
                nasilSatiri("1", "Oku", "İşin ne istediğini ve örneğini görürsün. Kılavuz kartı her basamakta ne yaptığını tek tek anlatır.")
                nasilSatiri("2", "Yaz", "Cevabı kendi cümlenle yazarsın. Takılırsan ⌘I ile ipucu alırsın; ipucu puanı biraz düşürür, ceza değildir.")
                nasilSatiri("3", "Karşılaştır", "Gönderince kaynak ya da örnek cümle açılır. Kendini dürüstçe değerlendirirsin; bu işin ne zaman geri döneceğini belirler.")
                nasilSatiri("↑", "Yüksel", "Bir basamakta rahatlayınca bir sonrakine geçersin. Sıra basitten zora: kavramı işletmek en başta, aforizma en sonda.")
            }
            Text("Kısayollar: 1–4 şık seç · ⌘⏎ gönder · ⌘I ipucu · 1–4 değerlendir · ⌘→ sonraki")
                .font(.caption).foregroundStyle(Tema.soluk)
        }
    }

    private func nasilSatiri(_ n: String, _ b: String, _ a: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(n).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Tema.vurgu)
                .frame(width: 26, height: 26).background(Circle().fill(Tema.vurgu.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(b).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.metin)
                Text(a).font(.callout).foregroundStyle(Tema.ikincil).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Üst bilgi

    private var ustBilgi: some View {
        HStack(spacing: 14) {
            Text("Basamak \(kip.no)/9").font(.system(size: 12, weight: .bold)).tracking(0.4)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Tema.hat(kip.hat).opacity(0.14))).foregroundStyle(Tema.hat(kip.hat))
            Text(kip.ad).font(.headline)
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("\(Int(Date().timeIntervalSince(baslangic) / 60)) dk · \(yapilan.count) iş")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button("Oturumu kapat") { oturumuKapat(); depo.bildirim = "Atölye oturumu kür olarak kaydedildi." }
                .disabled(yapilan.isEmpty)
            Button { sonraki() } label: { Label("Sonraki", systemImage: "arrow.right") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    // MARK: Çalışma (kılavuz → aşamalar → iş → sonuç)

    private var calisma: some View {
        VStack(alignment: .leading, spacing: 22) {
            rehber
            asamaCubugu
            if let a = aktifIs { if kip == .concept { choiceTask(a) } else { yazmaIsi(a) } } else { bos }
            if kip != .concept, let a = aktifIs, gonderildi { sonuc(a) }
        }
    }

    private var rehber: some View {
        let r = Tema.hat(kip.hat)
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.snappy) { rehberAcik.toggle() } } label: {
                HStack {
                    Label("Bu basamakta ne yapıyorsun?", systemImage: "map").font(.system(size: 14, weight: .semibold)).foregroundStyle(r)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.soluk)
                        .rotationEffect(.degrees(rehberAcik ? 0 : -90))
                }
                .padding(16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if rehberAcik {
                VStack(alignment: .leading, spacing: 14) {
                    rehberSatiri("Ne", kip.ne)
                    rehberSatiri("Neden", kip.neden)
                    rehberSatiri("Nasıl", kip.nasil)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ÖRNEK").font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Tema.soluk)
                        Text(kip.ornek).font(Tema.serif(.callout)).foregroundStyle(Tema.metin).lineSpacing(3)
                            .padding(12).tamGenislik()
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Tema.yuzey2.opacity(0.7)))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(r.opacity(0.25)))
    }

    private func rehberSatiri(_ e: String, _ d: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(e.uppercased(with: Dil.tr)).font(.system(size: 11, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Tema.soluk).frame(width: 54, alignment: .leading)
            Text(d).font(.callout).foregroundStyle(Tema.metin).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Hangi aşamadasın: 1 Oku → 2 Yaz → 3 Karşılaştır.
    private var asamaCubugu: some View {
        let ad = kip == .concept ? ["Oku", "Seç", "Açıklama"] : ["Oku", "Yaz", "Karşılaştır"]
        let simdi: Int = {
            if kip == .concept { return chosen == nil ? 0 : 2 }
            return gonderildi ? 2 : (yazi.isEmpty ? 0 : 1)
        }()
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(i < simdi ? Tema.basari : (i == simdi ? Tema.vurgu : Tema.yuzey2))
                        if i < simdi { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
                        else { Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(i == simdi ? .white : Tema.ikincil) }
                    }
                    .frame(width: 20, height: 20)
                    Text(ad[i]).font(.system(size: 13.5, weight: i == simdi ? .semibold : .medium))
                        .foregroundStyle(i == simdi ? Tema.metin : Tema.ikincil)
                }
                if i < 2 { Rectangle().fill(Tema.cizgi).frame(height: 1).frame(maxWidth: 40) }
            }
            Spacer()
        }
        .animation(.snappy, value: simdi)
    }

    private var bos: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Tema.soluk)
            Text("Bu basamakta malzeme yok. Kart paketine cümle eklenince burada açılır.").foregroundStyle(Tema.ikincil)
        }
        .frame(maxWidth: .infinity).padding(60)
    }

    // MARK: Kavramı işlet (çok seçmeli)

    private func choiceTask(_ a: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                let i = (isler.firstIndex { $0.id == a.id } ?? 0) + 1
                Text("SORU \(i)/\(isler.count)").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Tema.soluk)
                if !a.kaynak.isEmpty { Text(a.kaynak).font(.caption).foregroundStyle(.secondary) }
            }
            if let b = a.baglam {
                Text(b).font(Tema.serif(.title2)).foregroundStyle(Tema.metin).lineSpacing(4)
                    .padding(20).tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
            }
            Text(a.soru).font(Tema.serif(.title2, .semibold)).foregroundStyle(Tema.metin)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(Array(a.secenekler.enumerated()), id: \.element) { i, o in choiceRow(a, o, i) }
            }
            if let c = chosen {
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle().fill(Tema.cizgi).frame(height: 0.5)
                    Label(c == a.dogru ? "Doğru" : "Doğrusu: \(a.dogru)",
                          systemImage: c == a.dogru ? "checkmark.circle.fill" : "arrow.uturn.left.circle")
                        .font(.headline).foregroundStyle(c == a.dogru ? Tema.basari : Tema.uyari)
                    if let x = a.aciklama {
                        Text(x).font(Tema.serif(.body)).foregroundStyle(Tema.metin).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { sonraki() } label: { Label("Sonraki soru", systemImage: "arrow.right") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .padding(.top, 4)
                }
                .transition(.opacity)
            }
        }
    }

    private func choiceRow(_ a: Alistirma, _ o: String, _ i: Int) -> some View {
        let picked = chosen == o
        let isRight = o == a.dogru
        let border: Color = chosen == nil ? Tema.cizgi
            : (isRight ? Tema.basari.opacity(0.7) : (picked ? Tema.uyari.opacity(0.7) : Tema.cizgi))
        return Button { choose(a, o) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(i + 1)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Tema.ikincil)
                    .frame(width: 24, height: 24).background(Circle().fill(Tema.yuzey2))
                Text(o).font(Tema.serif(.title3)).foregroundStyle(Tema.metin)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if chosen != nil && (isRight || picked) {
                    Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isRight ? Tema.basari : Tema.uyari)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: chosen == nil ? 0.7 : 1.4))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(chosen != nil)
        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
    }

    // MARK: Yazma işi

    private func yazmaIsi(_ a: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(a.baslik.uppercased(with: Dil.tr)).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Tema.hat(a.hat))
                if !a.kaynak.isEmpty { Text(a.kaynak).font(.caption).foregroundStyle(.secondary) }
            }
            if let b = a.baglam {
                Text(b).font(Tema.serif(.title2)).foregroundStyle(Tema.metin).lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(20).tamGenislik()
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
            }
            Text(a.soru).font(.title3.weight(.semibold)).foregroundStyle(Tema.metin)
            if ipucu > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(a.ipuclari.prefix(ipucu).enumerated()), id: \.offset) { _, i in
                        Label(i, systemImage: "lightbulb").font(.callout).foregroundStyle(Tema.altin)
                    }
                }
            }
            yazmaAlani($yazi, yer: a.kademe >= 5 ? "Kendi cümlen…" : "Yaz…", yukseklik: a.kademe >= 6 ? 240 : 170, kapali: gonderildi)
            HStack(spacing: 12) {
                Text("\(Dil.kelimeler(yazi).count) kelime").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if ipucu < a.ipuclari.count && !gonderildi {
                    Button { withAnimation(.snappy) { ipucu += 1 } } label: { Label("İpucu \(ipucu + 1)/\(a.ipuclari.count)", systemImage: "lightbulb") }
                        .keyboardShortcut("i", modifiers: .command)
                }
                Button("Gönder") { gonder(a) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(gonderildi || Dil.kelimeler(yazi).count < 3)
            }
        }
    }

    private func yazmaAlani(_ metin: Binding<String>, yer: String, yukseklik: CGFloat, kapali: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if metin.wrappedValue.isEmpty {
                Text(yer).font(Tema.serif(.title3)).foregroundStyle(Tema.soluk).padding(.horizontal, 6).padding(.vertical, 2)
            }
            TextEditor(text: metin)
                .font(Tema.serif(.title3))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($odak)
                .disabled(kapali)
        }
        .frame(minHeight: yukseklik)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(odak ? Tema.vurgu.opacity(0.4) : Tema.cizgi))
    }

    // MARK: Sonuç (aynı sayfada, gönderince altta açılır)

    private func sonuc(_ a: Alistirma) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(Tema.cizgi).frame(height: 0.5)
            Bolumbasi(metin: a.kademe >= 5 ? "Karşılaştır · bir örnek ses" : "Karşılaştır · kaynak", sembol: "text.quote", renk: Tema.basari)
            Text(a.model).font(Tema.serif(.title3)).foregroundStyle(Tema.metin).lineSpacing(3).textSelection(.enabled)
                .padding(18).tamGenislik()
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
            if !a.anahtar.isEmpty {
                let b = Dil.kapsam(yazi, a.anahtar).bulunan
                AkanYerlesim(aralik: 6) {
                    ForEach(a.anahtar, id: \.self) { w in Hap(metin: (b.contains(w) ? "✓ " : "") + w, renk: b.contains(w) ? Tema.basari : Tema.soluk) }
                }
            }
            if let x = a.aciklama { Text(x).font(.callout).foregroundStyle(Tema.ikincil) }
            VStack(alignment: .leading, spacing: 4) {
                Text("Kendini nasıl buldun?").font(.headline).foregroundStyle(Tema.metin)
                Text("Dürüst işaretle: bu cevap, işin ne zaman geri döneceğini belirler. Düşük işaret ceza değil, tekrar demektir.")
                    .font(.footnote).foregroundStyle(Tema.ikincil)
            }
            .padding(.top, 4)
            HStack(spacing: 10) {
                ForEach(Array([(0.0, "Kaçırdım"), (0.5, "Kısmen"), (0.85, "Yakaladım"), (1.0, "Tam")].enumerated()), id: \.offset) { i, s in
                    Button { degerlendir(a, s.0) } label: {
                        VStack(spacing: 3) {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(s.1).font(.system(size: 14, weight: .semibold))
                            if oneri == s.0 { Text("öneri").font(.caption2).foregroundStyle(Tema.vurgu) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .tint(oneri == s.0 ? Tema.vurgu : nil)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
        }
    }

    // MARK: Eylemler

    private func adaylar(_ k: AtolyeKipi) -> [Aday] {
        k.hat == .donustur ? Uretec.donustur(depo.paket, k.kademe) : Uretec.kur(depo.paket, k.kademe)
    }

    private func sayimlariYenile() {
        var s: [AtolyeKipi: (biten: Int, toplam: Int)] = [:]
        for k in AtolyeKipi.allCases {
            let a = adaylar(k)
            s[k] = (a.filter { depo.durum.kartlar[$0.anahtar] != nil }.count, a.count)
        }
        sayim = s
    }

    private func isleriKur() {
        isSifirla()
        isler = Kurgu.sirala(adaylar(kip), depo.durum, Date()).map { $0.yap() }
        seciliIs = isler.first?.id
    }

    private func isSifirla() { yazi = ""; ipucu = 0; gonderildi = false; oneri = 0; chosen = nil; kartBasi = Date(); odak = kip != .concept }

    private func kaydet(_ hedef: String, _ hat: Hat, _ kademe: Int, _ puan: Double, metin: String?) {
        let o = Olay(tur: .cevap, hedef: hedef, hat: hat, kademe: kademe, puan: puan, guven: nil,
                     not: Olcum.not(puan, guven: nil).rawValue, metin: metin,
                     sure: Date().timeIntervalSince(kartBasi), kurId: kurId)
        if yapilan.isEmpty { baslangic = Date().addingTimeInterval(-o.sure!) }
        yapilan.append(o)
        depo.ekle(o)
        kartBasi = Date()
        sayimlariYenile()
    }

    private func choose(_ a: Alistirma, _ o: String) {
        guard chosen == nil else { return }
        withAnimation(.snappy) { chosen = o }
        kaydet(a.kartAnahtari, a.hat, a.kademe, o == a.dogru ? 1 : 0, metin: o)
    }

    private func gonder(_ a: Alistirma) {
        odak = false
        oneri = Olcum.oneri(yazi, a)
        withAnimation(.spring(response: 0.4)) { gonderildi = true }
    }

    private func degerlendir(_ a: Alistirma, _ p: Double) {
        guard gonderildi else { return }
        kaydet(a.kartAnahtari, a.hat, a.kademe, p, metin: yazi)
        sonraki()
    }

    private func sonraki() {
        withAnimation(.snappy) {
            if let i = isler.firstIndex(where: { $0.id == aktifIs?.id }), !isler.isEmpty { seciliIs = isler[(i + 1) % isler.count].id }
            isSifirla()
        }
    }

    /// En az bir iş yapıldıysa oturum bir kür olarak kapanır; yeni oturum açılır.
    private func oturumuKapat() {
        guard !yapilan.isEmpty else { return }
        depo.ekle(Olay(tur: .kur, sure: min(Date().timeIntervalSince(baslangic), 60 * 60), kurId: kurId, rol: "atolye"))
        yapilan = []
        kurId = UUID().uuidString
        baslangic = Date()
    }
}

// MARK: - Mac akışı

/// Mac akışı: solda akış (dar, kompakt), sağda seçili gönderi — yeniden üretim masası.
/// Tıklayınca metin açık gelir, kendiliğinden buzlanmaz. Önce hatırlayıp yazmak istersen "Buzlandır"a basarsın;
/// buzluyken İpucu (ilk kelimeler) ve Göster vardır. Soldaki aynı gönderi de ona uyar. Paylaşım yok.
struct MacAkis: View {
    @EnvironmentObject var depo: Depo
    @Binding var secili: Isaret?
    var sesAc: (String?) -> Void
    @State private var rol = "fikir"
    @State private var goster = true            // varsayılan açık: buzlandırmak kullanıcının tercihi
    @State private var bakti = false            // buzlandırdıktan sonra Göster'e bastı mı
    @State private var yazi = ""
    @FocusState private var odak: Bool

    var body: some View {
        HStack(spacing: 0) {
            AkisListesi(sesAc: sesAc, secili: secili?.id, sec: { x in withAnimation(.snappy) { secili = x } },
                        perdeli: goster ? nil : secili?.id)
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 500)
            Rectangle().fill(Tema.cizgi).frame(width: 0.5)
            Group {
                if let i = secili { detay(i).id(i.id).transition(.opacity) } else { sahne.transition(.opacity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: secili?.id) { _, _ in goster = true; bakti = false; yazi = "" }
    }

    /// Seçili değilken sahne: günün cümlesi büyük, kitabın renginde.
    private var sahne: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 40)
                if let x = depo.gununCumlesi() {
                    SeckiKarti(isaret: x, boy: .sahne, ac: { withAnimation(.snappy) { secili = x } },
                               yaz: { withAnimation(.snappy) { secili = x }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { odak = true } })
                        .frame(maxWidth: 760)
                    Text("Soldan bir işaret seç ya da bu cümlenin üzerine yaz. Bir işaretten buraya dönmek için esc.")
                        .font(.system(size: 13)).foregroundStyle(Tema.soluk).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "text.quote").font(.system(size: 40)).foregroundStyle(Tema.soluk)
                    Text("Voice Dream'de işaretlediklerin burada belirir.").foregroundStyle(Tema.ikincil)
                }
                Spacer(minLength: 40)
            }
            .padding(48)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { if let x = depo.gununCumlesi() { KitapTulu(kitap: x.kitap, yukseklik: 700) } }
    }

    /// Okuma odası: kitabın renginde tül, okunur ölçüde (≈ 65 karakter) büyük serif, asılı tırnak,
    /// bağlam ayrı bir ses gibi altında; sonra yazma masası, senin yazdıkların ve aynı kitaptan komşu işaretler.
    private func detay(_ i: Isaret) -> some View {
        let d = depo.durum
        let yazdiklarin = d.kendiCumleler.filter { $0.hedef == i.id }
        let kr = Tema.kitap(i.kitap)
        let kisa = i.metin.count <= 180
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 18) {
                    KitapKapagi(id: i.kitap, baslik: i.baslik, genislik: 52)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(i.kisaBaslik).font(.system(size: 21, weight: .semibold, design: .serif)).foregroundStyle(Tema.metin)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            TurRozeti(renk: i.renk)
                            Text(i.zaman.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Dil.tr)))
                                .font(.system(size: 12.5)).foregroundStyle(Tema.soluk)
                        }
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        let fav = d.favoriler.contains(i.id), hat = d.hatirlatmalar.contains(i.id), yer = d.yerIsaretleri.contains(i.id)
                        odaDugmesi(fav ? "heart.fill" : "heart", fav ? Color.pink : Tema.ikincil, "Favori") { depo.favori(i.id) }
                        odaDugmesi(hat ? "bell.fill" : "bell", hat ? Tema.vurgu : Tema.ikincil, "Tekrar havuzuna al") { depo.hatirlat(i.id) }
                        odaDugmesi(yer ? "bookmark.fill" : "bookmark", yer ? Tema.vurgu : Tema.ikincil, "Yer işareti") { depo.yerIsareti(i.id) }
                        odaDugmesi("mic", Tema.uyari, "Sesli not — kayıt sürerken metin kapalı kalır") { sesAc(i.id) }
                    }
                }
                .padding(.bottom, 44)

                if depo.gununCumlesi()?.id == i.id {
                    Label("GÜNÜN CÜMLESİ", systemImage: "sparkle")
                        .font(.system(size: 11, weight: .bold)).tracking(1.4).foregroundStyle(kr)
                        .padding(.bottom, 14)
                }

                HatirlamaPerdesi(acik: $goster, bakti: $bakti, ipucu: HatirlamaPerdesi<EmptyView>.ilkKelimeler(i.metin)) {
                    VStack(alignment: .leading, spacing: 34) {
                        Text(i.metin)
                            .font(.system(size: kisa ? 31 : 21, design: .serif)).lineSpacing(kisa ? 10 : 8)
                            .foregroundStyle(Tema.metin)
                            .textSelection(.enabled).tamGenislik()
                            .overlay(alignment: .topLeading) {
                                Text("“").font(.system(size: kisa ? 120 : 96, weight: .bold, design: .serif)).foregroundStyle(kr.opacity(0.28))
                                    .offset(x: kisa ? -58 : -48, y: kisa ? -34 : -28).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        if let b = i.baglam, !b.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BAĞLAM").font(.system(size: 10.5, weight: .bold)).tracking(1.4).foregroundStyle(Tema.soluk)
                                Text(b).font(.system(size: 16, design: .serif)).foregroundStyle(Tema.ikincil).lineSpacing(6)
                                    .textSelection(.enabled)
                            }
                            .padding(.leading, 20).tamGenislik()
                            .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.35)).frame(width: 2) }
                        }
                    }
                }
                .padding(.bottom, 40)

                Rectangle().fill(Tema.cizgi).frame(height: 0.5).padding(.bottom, 28)
                SimgeSecici(secenekler: [.init(deger: "fikir", ad: "Fikrim", sembol: "lightbulb"),
                                         .init(deger: "yorum", ad: "Yorum", sembol: "text.bubble"),
                                         .init(deger: "alinti", ad: "Alıntı", sembol: "arrow.2.squarepath")],
                            secili: $rol).frame(width: 330)
                    .padding(.bottom, 14)
                yazmaKutusu(i)

                if !yazdiklarin.isEmpty {
                    Bolumbasi(metin: "Senin yazdıkların · \(yazdiklarin.count)", sembol: "person").padding(.top, 34).padding(.bottom, 10)
                    VStack(spacing: 10) {
                        ForEach(yazdiklarin) { o in SenGonderisi(olay: o, alintiGoster: false) }
                    }
                }
                komsular(i, kr)
            }
            .padding(.horizontal, 64).padding(.top, 40).padding(.bottom, 56)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) { KitapTulu(kitap: i.kitap, yukseklik: 560) }
        .onExitCommand { withAnimation(.snappy) { secili = nil } }
    }

    private func odaDugmesi(_ s: String, _ r: Color, _ ad: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: s).font(.system(size: 14, weight: .medium)).foregroundStyle(r)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Tema.yuzey.opacity(0.85)))
                .overlay(Circle().strokeBorder(Tema.cizgi, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .help(ad)
    }

    /// Aynı kitaptan, zamanca en yakın sekiz işaret: dokun = o işarete geç.
    @ViewBuilder
    private func komsular(_ i: Isaret, _ kr: Color) -> some View {
        let l = depo.akis.isaretler.filter { $0.kitap == i.kitap && $0.id != i.id }
            .sorted { abs($0.zaman.timeIntervalSince(i.zaman)) < abs($1.zaman.timeIntervalSince(i.zaman)) }
            .prefix(8)
        if !l.isEmpty {
            Bolumbasi(metin: "Aynı kitaptan", sembol: "books.vertical").padding(.top, 38).padding(.bottom, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(l)) { k in
                        Button { withAnimation(.snappy) { secili = k } } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(k.metin).font(.system(size: 13.5, design: .serif)).foregroundStyle(Tema.metin)
                                    .lineSpacing(3).lineLimit(5).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Text(Tarih.kisa(k.zaman)).font(.system(size: 11)).foregroundStyle(Tema.soluk)
                            }
                            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
                            .frame(width: 232, height: 150, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.yuzey))
                            .overlay(alignment: .leading) { Capsule().fill(kr.opacity(0.7)).frame(width: 2.5).padding(.vertical, 14).padding(.leading, 7) }
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.6))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var yerTutucu: String {
        switch rol {
        case "yorum": "Bu işarete yorumun: katılıyor musun, neden?"
        case "alinti": "Alıntılarken ne eklersin?"
        default: "Bu işaret ne diyor, sen ne düşünüyorsun? Kendi cümlelerinle yaz."
        }
    }

    private func yazmaKutusu(_ i: Isaret) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if yazi.isEmpty {
                    Text(yerTutucu).font(.system(size: 17, design: .serif)).foregroundStyle(Tema.soluk)
                        .padding(.top, 14).padding(.leading, 17).allowsHitTesting(false)
                }
                TextEditor(text: $yazi)
                    .font(.system(size: 17, design: .serif)).lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .focused($odak)
                    .padding(10)
                    .frame(minHeight: 200)
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.yuzey))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(odak ? Tema.vurgu.opacity(0.5) : Tema.cizgi, lineWidth: odak ? 1.2 : 0.7))
            HStack(spacing: 12) {
                Text(goster ? (bakti ? "Buzlandırıp sonra baktın." : "Metin açık. İstersen Buzlandır'la önce hatırlayarak yaz.") : "Metin buzlu — hatırlayarak yazıyorsun.")
                    .font(.system(size: 12.5)).foregroundStyle(goster ? Tema.soluk : Tema.basari)
                Spacer()
                Text("\(yazi.split(whereSeparator: \.isWhitespace).count) kelime").font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Tema.soluk)
                Button {
                    let m = yazi.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !m.isEmpty else { return }
                    depo.ekle(Olay(tur: .kendiCumle, hedef: i.id, deger: goster || bakti, metin: m, rol: rol))   // deger: metne bakıldı mı
                    Dokunus.basari()
                    yazi = ""; bakti = false
                    depo.bildirim = "Kaydedildi — Benim sekmesinde ve değerlendirmede"
                } label: { Text("Kaydet") }
                .buttonStyle(AnaDugme())
                .frame(width: 140)
                .disabled(yazi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Kaydet (⌘↩)")
            }
        }
    }
}
