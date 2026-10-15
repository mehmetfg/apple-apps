// Konu kartı: beş sayfalık deste. Fikir → Formül → Örnek → Tuzak → Bağlar.
// Son sayfa konuyu aynı yasayı kullanan başka konulara bağlar; oradan dokunarak konudan konuya geçilir.
import SwiftUI

struct KonuKarti: View {
    @Environment(Depo.self) private var depo
    @Environment(\.dismiss) private var kapat
    @State var konuId: String
    @State private var sayfa = 0
    @State private var duzeltildi = false
    @State private var quiz: [QuizOgesi]?
    @State private var motor = false
    @State private var acikYasalar: Set<String> = []

    private let sayfaAdlari = ["Fikir", "Kalıp", "Örnek", "Tuzak", "Bağlar"]

    var body: some View {
        if let k = depo.konu(konuId) {
            let renk = depo.renk(k)
            VStack(spacing: 0) {
                ust(k, renk)
                TabView(selection: $sayfa) {
                    fikir(k, renk).tag(0)
                    formul(k, renk).tag(1)
                    ornekler(k, renk).tag(2)
                    tuzak(k, renk).tag(3)
                    baglar(k, renk).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                alt(k, renk)
            }
            .background(Lekeler(renkler: [renk, Tema.vurgu]))
            .onChange(of: sayfa) { _, s in
                Dokunus.secim()
                if s >= 2 {
                    depo.gordu(k.id)
                    if k.id == depo.durum.gununKonusu { depo.bitti("kart") }
                }
            }
            .fullScreenCover(item: Binding(get: { quiz.map { QuizSarmal(ogeler: $0) } }, set: { quiz = $0?.ogeler })) { q in
                QuizEkrani(ogeler: q.ogeler, gunluk: false)
            }
            .fullScreenCover(isPresented: $motor) { MotorOyunu() }
        }
    }

    // MARK: Üst · alt

    private func ust(_ k: Konu, _ renk: Color) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { kapat() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain).accessibilityLabel("Kapat")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(renk).frame(width: 7, height: 7)
                    Text(depo.bolge(k.bolge)?.ad ?? "")
                }
                .font(.caption.weight(.bold)).foregroundStyle(renk)
                Spacer()
                KademeHalkasi(kademe: depo.kademe(k.id), renk: renk, boy: 30)
            }
            HStack(spacing: 6) {
                ForEach(0..<5) { i in
                    Button { withAnimation { sayfa = i } } label: {
                        VStack(spacing: 4) {
                            Capsule().fill(i <= sayfa ? renk : renk.opacity(0.18)).frame(height: 4)
                            Text(sayfaAdlari[i]).font(.caption2.weight(i == sayfa ? .bold : .regular))
                                .foregroundStyle(i == sayfa ? renk : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private func alt(_ k: Konu, _ renk: Color) -> some View {
        HStack(spacing: 12) {
            if sayfa > 0 {
                Button { withAnimation { sayfa -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 52, height: 52)
                        .background(Circle().fill(Tema.yuzey))
                }
                .buttonStyle(.plain)
            }
            Button {
                if sayfa < 4 { withAnimation { sayfa += 1 } }
                else { Dokunus.orta(); quiz = depo.sorular(k, adet: 4) }
            } label: {
                Text(sayfa < 4 ? "Devam" : "Bu konudan 4 soru")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(renk))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: Sayfalar

    private func sayfaKabi<V: View>(@ViewBuilder _ ic: () -> V) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) { ic() }.padding(.horizontal).padding(.vertical, 12) }
            .scrollIndicators(.hidden)
    }

    private func fikir(_ k: Konu, _ renk: Color) -> some View {
        sayfaKabi {
            HStack(spacing: 8) {
                Text("Faz \(k.faz)").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(renk.opacity(0.15))).foregroundStyle(renk)
                if k.yildiz {
                    Label("kalıcı boşluk", systemImage: "star.fill").font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Tema.renk("kehribar").opacity(0.15))).foregroundStyle(Tema.renk("kehribar"))
                }
            }
            Text(k.tr).font(.system(size: 38, weight: .heavy, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            Text(k.ad).font(Tema.ingilizce(.title3).italic()).foregroundStyle(.secondary)
            Text(k.ne).font(.title3).fixedSize(horizontal: false, vertical: true).kart(18)
            VStack(alignment: .leading, spacing: 10) {
                Label("Akılda kalsın", systemImage: "lightbulb.max.fill").font(.subheadline.weight(.bold)).foregroundStyle(renk)
                Text(k.imge).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(renk.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(renk.opacity(0.3), lineWidth: 1))
        }
    }

    private func formul(_ k: Konu, _ renk: Color) -> some View {
        sayfaKabi {
            Text("Kalıp").font(Tema.baslik(.title2))
            Text("Yukarıdan aşağı oku: her satır cümlenin bir parçası, yanında ne iş gördüğü.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(k.kalip.bloklar.enumerated()), id: \.offset) { i, blok in
                if k.kalip.karsi && i == 1 {
                    HStack(spacing: 10) {
                        Rectangle().fill(Tema.cizgi).frame(height: 1)
                        Text("karşısında").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Rectangle().fill(Tema.cizgi).frame(height: 1)
                    }
                    .padding(.vertical, 2)
                }
                KalipBlokGorunum(blok: blok)
            }
            if k.yasalar.contains(where: { $0.id == "talep" || $0.id == "ayna" }) {
                Button { motor = true } label: {
                    HStack(spacing: 10) {
                        Cizim(ad: "talep", renk: Tema.zaman, boy: 30, zemin: false)
                        Text("Motor'da kendin çalıştır").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.zaman.opacity(0.13)))
                    .foregroundStyle(Tema.zaman)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ornekler(_ k: Konu, _ renk: Color) -> some View {
        sayfaKabi {
            Text("Kulağında kalsın").font(Tema.baslik(.title2))
            Text("Dokun, dinle. Sonra kapat ve kendin söyle.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array(k.ornek.enumerated()), id: \.offset) { _, o in
                SesliCumle(en: o.first ?? "", tr: o.count > 1 ? o[1] : nil, renk: renk).kart(18)
            }
        }
    }

    private func tuzak(_ k: Konu, _ renk: Color) -> some View {
        let t = k.tuzakAyrik
        return sayfaKabi {
            Text("Türk konuşurun tuzağı").font(Tema.baslik(.title2))
            if t.y.isEmpty {
                Text(k.tuzak).font(.title3).kart(18)
            } else {
                if !t.on.isEmpty { Text(t.on).font(.subheadline).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.yanlis).font(.title2)
                        Text(t.y).font(Tema.ingilizce(.title3)).strikethrough(duzeltildi, color: Tema.yanlis)
                            .foregroundStyle(duzeltildi ? .secondary : .primary)
                    }
                    if duzeltildi {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tema.dogru).font(.title2)
                            Text(t.d).font(Tema.ingilizce(.title3, .semibold))
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        if !t.not.isEmpty {
                            Text(t.not).font(.callout).foregroundStyle(.secondary).transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kart(20)
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { duzeltildi.toggle() }
                    if duzeltildi { Dokunus.basari(); Ses.konus(t.d) }
                } label: {
                    Label(duzeltildi ? "Yanlışa geri dön" : "Önce kendin düzelt, sonra dokun", systemImage: duzeltildi ? "arrow.uturn.backward" : "wand.and.stars")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(renk.opacity(0.14)))
                        .foregroundStyle(renk)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func baglar(_ k: Konu, _ renk: Color) -> some View {
        sayfaKabi {
            Text("Hangi yasayla dönüyor?").font(Tema.baslik(.title2))
            Text("Bu konu ayrı bir kural değil. Aşağıdaki yasa başka konularda da aynı hareketi yapar; birini anlayınca öteki kolaylaşır.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(k.yasalar, id: \.id) { ky in
                if let y = depo.yasa(ky.id) {
                    BagKarti(konu: k, yasa: y, not: ky.not, acik: acikYasalar.contains(y.id),
                             tumu: { withAnimation(.snappy) { _ = acikYasalar.insert(y.id) } },
                             git: { d in
                                 Dokunus.hafif()
                                 withAnimation(.snappy) { konuId = d; sayfa = 0; duzeltildi = false; acikYasalar = [] }
                             })
                }
            }
        }
    }
}

/// Bir yasanın bu konudaki hâli: ① tek cümle ② bu konu ↔ komşu konu, aynı hareket işaretli ③ en yakın komşular
struct BagKarti: View {
    @Environment(Depo.self) private var depo
    let konu: Konu
    let yasa: Yasa
    let not: String
    let acik: Bool
    let tumu: () -> Void
    let git: (String) -> Void

    var body: some View {
        let yr = Tema.renk(yasa.renk)
        let komsular = depo.komsular(konu, yasa: yasa)
        let kendi = yasa.ornekler.first { $0.konu == konu.id }
        let karsi = yasa.ornekler.first { $0.konu != konu.id }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Cizim(ad: yasa.id, renk: yr, boy: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(yasa.ad).font(.headline)
                    Text(yasa.ozet).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            // ① bu konuda ne yapıyor
            Text(not).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)

            // ② aynı hareket, iki konuda
            VStack(spacing: 8) {
                OrnekKutusu(baslik: "Bu konuda", en: kendi?.en ?? konu.ornek.first?.first ?? "",
                            hareket: kendi?.tr ?? "", renk: yr)
                if let karsi, let kk = depo.konu(karsi.konu) {
                    Image(systemName: "equal").font(.caption.weight(.bold)).foregroundStyle(yr.opacity(0.7))
                        .accessibilityLabel("aynı hareket")
                    Button { git(kk.id) } label: {
                        OrnekKutusu(baslik: kk.tr, en: karsi.en, hareket: karsi.tr, renk: yr, gidilir: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            // ③ en yakın komşular
            if !komsular.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aynı yasayla dönen konular").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    ForEach(acik ? komsular : Array(komsular.prefix(4))) { d in
                        Button { git(d.id) } label: {
                            HStack(spacing: 10) {
                                Capsule().fill(depo.renk(d)).frame(width: 3, height: 18)
                                Text(d.tr).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(depo.bolge(d.bolge)?.ad ?? "").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !acik && komsular.count > 4 {
                        Button(action: tumu) {
                            Text("Tümü (\(komsular.count))").font(.subheadline.weight(.semibold)).foregroundStyle(yr)
                                .padding(.top, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .kart(18)
    }
}

/// Örnek cümle; hareket metnindeki ("am → was") kelimeler cümlede vurgulanır.
struct OrnekKutusu: View {
    let baslik: String
    let en: String
    let hareket: String
    let renk: Color
    var gidilir = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(baslik).font(.caption.weight(.bold)).foregroundStyle(renk)
                Spacer()
                if gidilir { Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(renk.opacity(0.7)) }
            }
            Text(Self.vurgula(en, hareket, renk)).font(Tema.ingilizce(.body)).fixedSize(horizontal: false, vertical: true)
            if !hareket.isEmpty {
                Text(hareket).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(renk.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { Ses.konus(en) }
    }

    static func vurgula(_ en: String, _ hareket: String, _ r: Color) -> AttributedString {
        let ayir = CharacterSet.letters.inverted.subtracting(CharacterSet(charactersIn: "'’"))
        var isaret = Set(hareket.components(separatedBy: ayir).map { $0.lowercased() }.filter { $0.count > 1 })
        let kelimeler = en.components(separatedBy: ayir).filter { !$0.isEmpty }
        if !kelimeler.contains(where: { isaret.contains($0.lowercased()) }) {
            // hareket Türkçe anlatıldıysa: have/has/had + V3 öbeğini vurgula (geriye bakış)
            for (i, w) in kelimeler.enumerated() where ["have", "has", "had", "'ve"].contains(w.lowercased()) {
                isaret.insert(w.lowercased())
                if i + 1 < kelimeler.count { isaret.insert(kelimeler[i + 1].lowercased()) }
            }
        }
        var sonuc = AttributedString()
        var kelime = ""
        func bitir() {
            guard !kelime.isEmpty else { return }
            var a = AttributedString(kelime)
            if isaret.contains(kelime.lowercased()) { a.foregroundColor = r; a.font = Tema.ingilizce(.body, .bold) }
            sonuc += a; kelime = ""
        }
        for ch in en {
            if ch.isLetter || ch == "'" || ch == "’" { kelime.append(ch) } else { bitir(); sonuc += AttributedString(String(ch)) }
        }
        bitir()
        return sonuc
    }
}

/// Kalıp bloğu: kalıplar alt alta, her kalıpta yuvalar alt alta.
struct KalipBlokGorunum: View {
    let blok: KalipBlok
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blok.kaliplar.enumerated()), id: \.offset) { _, k in
                KalipSatirGorunum(satir: k)
            }
            if !blok.liste.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(blok.liste, id: \.self) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Tema.vurgu.opacity(0.5)).frame(width: 5, height: 5)
                            Text(l).font(Tema.ingilizce(.body, .medium)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !blok.not.isEmpty {
                        Text(blok.not).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.yanlis).padding(.top, 4)
                    }
                }
                .kart(16, yaricap: 18)
            }
        }
    }
}

struct KalipSatirGorunum: View {
    let satir: KalipSatir
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !satir.etiket.isEmpty {
                Text(satir.etiket).font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            if satir.parcalar.count == 1, let p = satir.parcalar.first, p.t == "ornek" {
                Text(p.m).font(Tema.ingilizce(.title3, .medium)).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(satir.parcalar.enumerated()), id: \.offset) { i, p in
                    if p.t == "ayrac" {
                        HStack(spacing: 8) {
                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 18, height: 1)
                            Text("virgül · \(p.a)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        if i > 0 && satir.parcalar[i - 1].t != "ayrac" {
                            Text("+").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                .frame(width: 18).padding(.vertical, 1)
                        }
                        YuvaSatiri(parca: p)
                    }
                }
            }
            if !satir.isaret.isEmpty {
                Akis(aralik: 6, satirAraligi: 6, ortala: false) {
                    ForEach(satir.isaret, id: \.self) { w in
                        Text(w).font(.caption.weight(.medium)).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().stroke(Tema.cizgi.opacity(3), lineWidth: 1))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            }
        }
        .kart(16, yaricap: 18)
    }
}

/// Tek yuva: renkli kutu + yanında ne iş gördüğü
struct YuvaSatiri: View {
    let parca: KalipParca
    var body: some View {
        let r = Tema.yuva(parca.t)
        HStack(alignment: .center, spacing: 12) {
            Text(parca.m)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(parca.t == "diger" ? Color.primary : r)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(r.opacity(parca.t == "diger" ? 0.08 : 0.14)))
                .fixedSize(horizontal: false, vertical: true)
            if !parca.a.isEmpty {
                Text(parca.a).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// fullScreenCover(item:) için kimlikli sarmal
struct QuizSarmal: Identifiable {
    let ogeler: [QuizOgesi]
    var id: UUID { ogeler.first?.id ?? UUID() }
}
