import SwiftUI

// İngilizce metindeki sözlük terimleri dokunulabilir olur: noktalı alt çizgi, dokununca terim kartı.
// Bütün derslerin terimleri kullanılır; önceki derste öğrenilen kelime sonraki derste yine yakalanır.

private let ekler: Set<String> = ["", "s", "es", "d", "ed", "ing", "ped", "ping", "ped", "ted", "ting", "er", "ers"]

func bagliMetin(_ metin: String, terimler: [Terim], renk: Color = Tema.vurgu) -> AttributedString {
    var a = (try? AttributedString(markdown: metin,
                                   options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(metin)
    let duz = String(a.characters)
    var dolu: [Range<String.Index>] = []
    for t in terimler.sorted(by: { $0.terim.count > $1.terim.count }) {
        var bak = duz.startIndex..<duz.endIndex
        while let r = duz.range(of: t.terim, options: [.caseInsensitive], range: bak) {
            bak = r.upperBound..<duz.endIndex
            if r.lowerBound != duz.startIndex, duz[duz.index(before: r.lowerBound)].isLetter { continue }
            var son = r.upperBound
            while son < duz.endIndex, duz[son].isLetter { son = duz.index(after: son) }
            guard ekler.contains(String(duz[r.upperBound..<son]).lowercased()) else { continue }
            let tam = r.lowerBound..<son
            if dolu.contains(where: { $0.overlaps(tam) }) { continue }
            dolu.append(tam)
            var bilesen = URLComponents()
            bilesen.scheme = "terim"; bilesen.host = "t"
            bilesen.queryItems = [URLQueryItem(name: "id", value: t.id)]
            let bas = a.characters.index(a.startIndex, offsetBy: duz.distance(from: duz.startIndex, to: tam.lowerBound))
            let bit = a.characters.index(bas, offsetBy: duz.distance(from: tam.lowerBound, to: tam.upperBound))
            a[bas..<bit].link = bilesen.url
            a[bas..<bit].underlineStyle = Text.LineStyle(pattern: .dot, color: renk)
        }
    }
    return a
}

struct BagliText: View {
    let metin: String
    var font: Font = .system(.body)
    var body: some View {
        Text(bagliMetin(metin, terimler: Kutuphane.shared.terimler))
            .font(font)
            .foregroundStyle(Tema.murekkep)
            .tint(Tema.murekkep)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Terim kartı

struct TerimSecimi: ViewModifier {
    @State private var secili: Terim?
    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "terim",
                      let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                      let t = Kutuphane.shared.terimler.first(where: { $0.id == id }) else { return .systemAction }
                Dokunma.hafif()
                secili = t
                return .handled
            })
            .sheet(item: $secili) { t in
                TerimKarti(terim: t)
                    .presentationDetents([.height(380), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Tema.zemin)
            }
    }
}

extension View {
    func terimSecimi() -> some View { modifier(TerimSecimi()) }
}

struct TerimKarti: View {
    let terim: Terim
    @Environment(Ilerleme.self) private var ilerleme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(terim.terim).font(Tema.baslik(.largeTitle)).foregroundStyle(Tema.murekkep)
                    Text(terim.ipa).font(.system(.callout, design: .serif)).foregroundStyle(Tema.soluk)
                }
                Spacer()
                SesDugmeleri(metin: terim.terim)
            }
            Text(terim.tr).font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(Tema.vurgu)
            VStack(alignment: .leading, spacing: 10) {
                satir("PATTERN", terim.kalip)
                satir("EXAMPLE", terim.ornek)
            }
            Spacer(minLength: 0)
            HStack {
                if let d = Kutuphane.shared.terimDersi[terim.id], let ders = Kutuphane.shared.dersler[d] {
                    Text("From: \(ders.baslik)").font(.caption).foregroundStyle(Tema.soluk)
                }
                Spacer()
                Button {
                    Dokunma.hafif()
                    ilerleme.bilinenDegistir(terim)
                } label: {
                    Label(ilerleme.biliyor(terim) ? "I know this" : "Mark as known",
                          systemImage: ilerleme.biliyor(terim) ? "checkmark.seal.fill" : "seal")
                }
                .buttonStyle(IkinciDugme())
            }
        }
        .padding(22)
        .padding(.top, 8)
    }

    private func satir(_ baslik: String, _ metin: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(baslik).font(.system(.caption2, design: .rounded, weight: .heavy)).foregroundStyle(Tema.soluk)
                .frame(width: 64, alignment: .leading).padding(.top, 3)
            Text(metin).font(.body).foregroundStyle(Tema.murekkep).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { Ses.shared.soyle(metin) } label: {
                Image(systemName: "speaker.wave.2").font(.footnote).foregroundStyle(Tema.soluk)
            }.buttonStyle(.plain)
        }
    }
}

struct SesDugmeleri: View {
    let metin: String
    var body: some View {
        HStack(spacing: 8) {
            Button { Ses.shared.soyle(metin) } label: {
                Image(systemName: "speaker.wave.2.fill").frame(width: 38, height: 38)
                    .background(Tema.kart2, in: Circle())
            }
            Button { Ses.shared.soyle(metin, yavas: true) } label: {
                Image(systemName: "tortoise.fill").frame(width: 38, height: 38)
                    .background(Tema.kart2, in: Circle())
            }
        }
        .font(.callout)
        .foregroundStyle(Tema.murekkep)
        .buttonStyle(.plain)
    }
}
