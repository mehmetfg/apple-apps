// Konular: 60 konunun tamamı tek yerde. Süzgeç (bölge · yasa · faz · aşinalık · arama) + dört görünüm
// (Liste · Kartlar · Bölgeler · Matris). Satıra dokun → konu kartı. Basılı tut → Bugüne al.
// Harita'nın (gece gökyüzü) yerine geldi: bakınca hangi konuların olduğu, girince ayrıntısı görünsün diye.
import SwiftUI

enum KonuGorunum: String, CaseIterable, Identifiable {
    case liste, kartlar, bolgeler, matris
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .liste: "Liste"
        case .kartlar: "Kartlar"
        case .bolgeler: "Bölgeler"
        case .matris: "Matris"
        }
    }
    var sembol: String {
        switch self {
        case .liste: "list.bullet"
        case .kartlar: "square.grid.2x2"
        case .bolgeler: "rectangle.grid.1x2"
        case .matris: "tablecells"
        }
    }
}

enum KonuSira: String, CaseIterable, Identifiable {
    case yol, bolge, alfabe
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .yol: "Önerilen sıra"
        case .bolge: "Bölgeye göre"
        case .alfabe: "A → Z"
        }
    }
}

struct KonularEkrani: View {
    @Environment(Depo.self) private var depo
    let ac: (Acilan) -> Void

    @AppStorage("konular-gorunum") private var gorunum: KonuGorunum = .liste
    @AppStorage("konular-sira") private var sira: KonuSira = .yol
    @State private var arama = ""
    @State private var bolge: String?
    @State private var yasa: String?
    @State private var faz: Int?
    @State private var asinalik: Int?    // 0 dokunmadım · 1 gördüm · 2+ çalıştım

    private var suzgecVar: Bool { bolge != nil || yasa != nil || faz != nil || asinalik != nil }

    private var sonuc: [Konu] {
        let sozcuk = arama.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr_TR"))
        var l = depo.veri.konular.filter { k in
            if let bolge, k.bolge != bolge { return false }
            if let yasa, !k.yasalar.contains(where: { $0.id == yasa }) { return false }
            if let faz, k.faz != faz { return false }
            if let asinalik {
                let kd = depo.kademe(k.id)
                if asinalik == 2 ? kd < 2 : kd != asinalik { return false }
            }
            if !sozcuk.isEmpty {
                let metin = [k.tr, k.ad, k.ne, k.formul].joined(separator: " ").lowercased(with: Locale(identifier: "tr_TR"))
                if !metin.contains(sozcuk) { return false }
            }
            return true
        }
        switch sira {
        case .yol:
            let sirasi = Dictionary(uniqueKeysWithValues: depo.veri.yol.enumerated().map { ($1, $0) })
            l.sort { (sirasi[$0.id] ?? 999) < (sirasi[$1.id] ?? 999) }
        case .bolge:
            let bs = Dictionary(uniqueKeysWithValues: depo.veri.bolgeler.enumerated().map { ($1.id, $0) })
            l.sort { (bs[$0.bolge] ?? 0, $0.faz) < (bs[$1.bolge] ?? 0, $1.faz) }
        case .alfabe:
            l.sort { $0.tr.compare($1.tr, locale: Locale(identifier: "tr_TR")) == .orderedAscending }
        }
        return l
    }

    var body: some View {
        NavigationStack {
            let l = sonuc
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                    suzgecler
                    Text(l.count == depo.veri.konular.count ? "\(l.count) konu" : "\(depo.veri.konular.count) konudan \(l.count) tanesi")
                        .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal)
                    if l.isEmpty {
                        ContentUnavailableView("Konu yok", systemImage: "line.3.horizontal.decrease",
                                               description: Text("Süzgeci gevşet ya da aramayı değiştir."))
                            .padding(.top, 40)
                    } else {
                        switch gorunum {
                        case .liste: liste(l)
                        case .kartlar: kartlar(l)
                        case .bolgeler: bolgeler(l)
                        case .matris: matris(l)
                        }
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Lekeler(renkler: [Tema.renk("yesil"), Tema.renk("mor")]))
            .navigationTitle("Konular")
            .searchable(text: $arama, prompt: "Konu, kalıp ya da kelime ara")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Görünüm", selection: $gorunum) {
                            ForEach(KonuGorunum.allCases) { Label($0.ad, systemImage: $0.sembol).tag($0) }
                        }
                        Picker("Sıra", selection: $sira) {
                            ForEach(KonuSira.allCases) { Text($0.ad).tag($0) }
                        }
                    } label: {
                        Image(systemName: gorunum.sembol)
                    }
                    .accessibilityLabel("Görünüm ve sıra")
                }
            }
        }
    }

    // MARK: Süzgeç çubuğu

    private var suzgecler: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Görünüm", selection: $gorunum.animation(.snappy)) {
                ForEach(KonuGorunum.allCases) { Text($0.ad).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if suzgecVar {
                        Button {
                            withAnimation(.snappy) { bolge = nil; yasa = nil; faz = nil; asinalik = nil }
                        } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold))
                                .frame(width: 32, height: 32).background(Circle().fill(Tema.yuzey))
                                .overlay(Circle().stroke(Tema.cizgi))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Süzgeçleri temizle")
                    }
                    Menu {
                        Button("Tüm bölgeler") { bolge = nil }
                        ForEach(depo.veri.bolgeler) { b in
                            Button { bolge = b.id } label: { Text("\(b.ad) · \(depo.konular(bolge: b.id).count)") }
                        }
                    } label: {
                        SuzgecCipi(baslik: bolge.flatMap { depo.bolge($0)?.ad } ?? "Bölge", secili: bolge != nil,
                                   renk: bolge.flatMap { depo.bolge($0) }.map { Tema.renk($0.renk) })
                    }
                    Menu {
                        Button("Tüm yasalar") { yasa = nil }
                        ForEach(depo.veri.yasalar) { y in
                            Button { yasa = y.id } label: { Text("\(y.ad) · \(y.konular.count)") }
                        }
                    } label: {
                        SuzgecCipi(baslik: yasa.flatMap { depo.yasa($0)?.ad } ?? "Yasa", secili: yasa != nil,
                                   renk: yasa.flatMap { depo.yasa($0) }.map { Tema.renk($0.renk) })
                    }
                    Menu {
                        Button("Bütün fazlar") { faz = nil }
                        ForEach(Array(Set(depo.veri.konular.map(\.faz))).sorted(), id: \.self) { f in
                            Button("Faz \(f)") { faz = f }
                        }
                    } label: {
                        SuzgecCipi(baslik: faz.map { "Faz \($0)" } ?? "Faz", secili: faz != nil)
                    }
                    Menu {
                        Button("Hepsi") { asinalik = nil }
                        Button("Dokunmadıklarım") { asinalik = 0 }
                        Button("Yalnız gördüklerim") { asinalik = 1 }
                        Button("Çalıştıklarım") { asinalik = 2 }
                    } label: {
                        SuzgecCipi(baslik: ["Dokunmadım", "Gördüm", "Çalıştım"][safe: asinalik ?? -1] ?? "Aşinalık", secili: asinalik != nil)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Görünümler

    private func liste(_ l: [Konu]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(l.enumerated()), id: \.element.id) { i, k in
                KonuSatiri(konu: k, ozetli: true) { ac(.konu(k.id)) }
                if i < l.count - 1 { Divider().padding(.leading, 30) }
            }
        }
        .kart(4, yaricap: 22)
        .padding(.horizontal)
    }

    private func kartlar(_ l: [Konu]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(l) { k in
                Button { ac(.konu(k.id)) } label: { KonuKutusu(konu: k) }
                    .buttonStyle(BasinStil())
                    .contextMenu { bugunMenusu(k) }
            }
        }
        .padding(.horizontal)
    }

    private func bolgeler(_ l: [Konu]) -> some View {
        ForEach(depo.veri.bolgeler) { b in
            let ic = l.filter { $0.bolge == b.id }
            if !ic.isEmpty {
                let r = Tema.renk(b.renk)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(r).frame(width: 10, height: 10)
                        Text(b.ad).font(Tema.baslik(.title3))
                        Text("\(ic.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(b.ozet).font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(ic.enumerated()), id: \.element.id) { i, k in
                            KonuSatiri(konu: k, ozetli: false) { ac(.konu(k.id)) }
                            if i < ic.count - 1 { Divider().padding(.leading, 30) }
                        }
                    }
                    .kart(4, yaricap: 20)
                }
                .padding(.horizontal)
                .padding(.top, 6)
            }
        }
    }

    /// Konu × yasa ızgarası: hangi konu hangi yasayla dönüyor, tek bakışta. Sütun başına dokun → o yasayla süz.
    private func matris(_ l: [Konu]) -> some View {
        let ys = depo.veri.yasalar
        let hucre: CGFloat = 24
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Yasalar →").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(ys) { y in
                    Button { withAnimation(.snappy) { yasa = yasa == y.id ? nil : y.id } } label: {
                        Cizim(ad: y.id, renk: Tema.renk(y.renk), boy: hucre - 2, zemin: yasa == y.id)
                            .opacity(yasa == nil || yasa == y.id ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                    .frame(width: hucre)
                    .accessibilityLabel(y.ad)
                }
            }
            .padding(.vertical, 8)
            Divider()
            ForEach(l) { k in
                Button { ac(.konu(k.id)) } label: {
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Capsule().fill(depo.renk(k)).frame(width: 3, height: 14)
                            Text(k.tr).font(.caption).lineLimit(1).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(ys) { y in
                            let var_ = k.yasalar.contains { $0.id == y.id }
                            Circle()
                                .fill(var_ ? Tema.renk(y.renk) : Color.primary.opacity(0.06))
                                .frame(width: var_ ? 11 : 5, height: var_ ? 11 : 5)
                                .frame(width: hucre, height: 28)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { bugunMenusu(k) }
            }
        }
        .kart(12, yaricap: 20)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func bugunMenusu(_ k: Konu) -> some View {
        Button { ac(.konu(k.id)) } label: { Label("Aç", systemImage: "arrow.up.right") }
        if k.id != depo.durum.gununKonusu {
            Button { Dokunus.basari(); depo.bugunuDegistir(k.id) } label: { Label("Bugüne al", systemImage: "sun.horizon") }
        }
    }
}

// MARK: - Parçalar

struct SuzgecCipi: View {
    let baslik: String
    let secili: Bool
    var renk: Color? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let renk, secili { Circle().fill(renk).frame(width: 7, height: 7) }
            Text(baslik).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).opacity(0.6)
        }
        .font(.subheadline.weight(secili ? .semibold : .regular))
        .foregroundStyle(secili ? Color.primary : .secondary)
        .padding(.horizontal, 13).frame(height: 32)
        .background(Capsule().fill(secili ? (renk ?? Tema.vurgu).opacity(0.14) : Tema.yuzey))
        .overlay(Capsule().stroke(secili ? (renk ?? Tema.vurgu).opacity(0.35) : Tema.cizgi))
    }
}

/// Liste satırı: bölge çizgisi · Türkçe ad · İngilizce ad · (özet) · aşinalık
struct KonuSatiri: View {
    @Environment(Depo.self) private var depo
    let konu: Konu
    var ozetli = true
    let ac: () -> Void

    var body: some View {
        let r = depo.renk(konu)
        Button(action: ac) {
            HStack(alignment: .center, spacing: 12) {
                Capsule().fill(r).frame(width: 4, height: ozetli ? 44 : 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(konu.tr).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        if konu.id == depo.durum.gununKonusu {
                            Text("bugün").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(r.opacity(0.16))).foregroundStyle(r)
                        }
                    }
                    Text(konu.ad).font(Tema.ingilizce(.subheadline).italic()).foregroundStyle(.secondary).lineLimit(1)
                    if ozetli {
                        Text(konu.ne).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading).padding(.top, 2)
                    }
                }
                Spacer(minLength: 4)
                KademeHalkasi(kademe: depo.kademe(konu.id), renk: r, boy: 20)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if konu.id != depo.durum.gununKonusu {
                Button { Dokunus.basari(); depo.bugunuDegistir(konu.id) } label: { Label("Bugüne al", systemImage: "sun.horizon") }
            }
        }
    }
}

/// Kart görünümü kutusu: bölge · ad · kısa kalıp · bağlı yasaların çizimleri
struct KonuKutusu: View {
    @Environment(Depo.self) private var depo
    let konu: Konu
    var body: some View {
        let r = depo.renk(konu)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(depo.bolge(konu.bolge)?.ad ?? "").font(.caption2.weight(.bold)).foregroundStyle(r).lineLimit(1)
                Spacer(minLength: 0)
                KademeHalkasi(kademe: depo.kademe(konu.id), renk: r, boy: 16)
            }
            Text(konu.tr).font(.headline).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
            Text(konu.ad).font(Tema.ingilizce(.caption).italic()).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 2)
            Text(konu.kalip.bloklar.first?.kaliplar.first.map { $0.parcalar.map(\.m).joined(separator: " + ") }
                 ?? konu.kalip.bloklar.first?.liste.prefix(3).joined(separator: " · ") ?? "")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                ForEach(konu.yasalar, id: \.id) { ky in
                    if let y = depo.yasa(ky.id) { Cizim(ad: y.id, renk: Tema.renk(y.renk), boy: 22) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Tema.yuzey)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tema.cizgi))
        )
    }
}
