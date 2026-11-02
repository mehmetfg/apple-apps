// Kelimeler (araç çubuğu, ⇧⌘L): bugünün ve bir önceki günün kelimeleri — Türkçesi, okunuşu, İngilizce tanımı,
// metindeki cümlesi, Oxford sesi. Yeni kelimeler önce, sonra yankı (tekrar) ve tanıdık.
import SwiftUI

struct WordsSheet: View {
    @EnvironmentObject var t: Tezgah
    @Environment(\.dismiss) var close
    @State private var which = 0          // 0 today · 1 previous day
    @State private var showTurkish = true

    /// A day's word lists, from the open day / day files, else the archive.
    struct DayWords { var no: Int; var title: String; var sentences: [String]; var groups: [(String, Color, [String])] }

    func words(_ no: Int) -> DayWords? {
        if let g = (t.o?.gun.no == no ? t.o?.gun : nil) ?? t.tumGunler.first(where: { $0.no == no }) {
            return DayWords(no: no, title: g.ad, sentences: g.cumleler.map(\.en),
                            groups: [("Yeni", .blue, g.yeni ?? []), ("Yankı · tekrar", Renk.sari, g.yanki ?? []), ("Tanıdık", Renk.yesil, g.tanidik ?? [])])
        }
        if let a = t.arsiv.gunler.first(where: { $0.gun == no }) ?? t.gecmis().first(where: { $0.gun == no }) {
            return DayWords(no: no, title: a.baslik, sentences: a.cumleler.map(\.en),
                            groups: [("Yeni", .blue, a.yeni), ("Yankı · tekrar", Renk.sari, a.yanki), ("Tanıdık", Renk.yesil, a.tanidik)])
        }
        return nil
    }

    var todayNo: Int { t.o?.gun.no ?? t.gunMasa?.no ?? 0 }

    var body: some View {
        let today = words(todayNo), prev = words(todayNo - 1)
        let d = which == 0 ? today : prev
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("", selection: $which) {
                    Text("Bugün · Gün \(todayNo)").tag(0)
                    Text("Önceki · Gün \(todayNo - 1)").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320)
                Toggle("Türkçesi", isOn: $showTurkish).toggleStyle(.switch).controlSize(.small)
                    .help("Kapatınca önce kendin hatırla; karta gelince görünür")
                Spacer()
                Button("Kapat") { close() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let d {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GÜN \(d.no)").font(.caption.weight(.semibold)).foregroundStyle(Renk.vurgu).tracking(0.6)
                            Text(d.title.isEmpty ? "—" : d.title).font(.system(size: 26, weight: .bold))
                        }
                        let any = d.groups.contains { !$0.2.isEmpty }
                        if !any {
                            Text("Bu gün kurma kipinde: yeni kelime yok, yalnız yapı çalışıldı.").foregroundStyle(.secondary)
                        }
                        ForEach(d.groups.filter { !$0.2.isEmpty }, id: \.0) { name, color, list in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Circle().fill(color).frame(width: 8, height: 8)
                                    Text(name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
                                    Text("\(list.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                                    ForEach(list, id: \.self) { w in
                                        WordTile(word: w, color: color, sentence: sentence(for: w, in: d.sentences), showTurkish: showTurkish)
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gün \(which == 0 ? todayNo : todayNo - 1) bulunamadı").font(.title2.bold())
                            Text("Bu günün dosyası ne masada ne pakette ne de arşivde var.").foregroundStyle(.secondary)
                        }
                    }
                    if !t.sozlukHazir { ProgressView("Sözlük yükleniyor…").controlSize(.small) }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 900, height: 680)
        .background(Renk.zemin)
    }

    /// The text's sentence that holds the word (or one of its forms).
    func sentence(for w: String, in list: [String]) -> String? {
        let key = w.lowercased(), forms = Set([key] + Metin.govdeler(key))
        return list.first { s in
            Metin.kelimeler(s).contains { k in let l = k.lowercased(); return forms.contains(l) || Metin.govdeler(l).contains(key) }
        }
    }
}

struct WordTile: View {
    var word: String
    var color: Color
    var sentence: String?
    var showTurkish: Bool
    @EnvironmentObject var t: Tezgah
    @State private var hover = false

    var body: some View {
        let s = t.sozluk.bul(word)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(word).font(.serif(22, .semibold))
                if let p = s?.phon, !p.isEmpty { Text(p).font(.callout).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                if let c = s?.cefr, !c.isEmpty { Cip(metin: c, renk: color) }
                Button { t.ses.kelime(word, sozluk: t.sozluk) } label: { Image(systemName: "speaker.wave.2.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("Dinle").help("Oxford telaffuzu")
            }
            HStack(spacing: 6) {
                Text(showTurkish || hover ? (s?.tr.isEmpty == false ? s!.tr : "—") : "• • •")
                    .font(.title3.weight(.medium)).foregroundStyle(showTurkish || hover ? color : .secondary)
                if let p = s?.pos, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.tertiary) }
            }
            if let d = s?.def, !d.isEmpty { Text(d).font(.callout).foregroundStyle(.primary.opacity(0.85)).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            if let c = sentence {
                Text(Highlight.word(c, word, color)).font(.serif(14)).foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.5)).frame(width: 2) }
                    .fixedSize(horizontal: false, vertical: true)
            } else if let e = s?.ex.first {
                Text(e).font(.serif(14)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Renk.kart) }
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(hover ? color.opacity(0.5) : Renk.cizgi) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// AttributedString helpers for marking a word / a regex inside a sentence.
enum Highlight {
    static func word(_ s: String, _ w: String, _ color: Color, size: CGFloat = 14) -> AttributedString {
        let forms = [w] + Metin.govdeler(w.lowercased())
        let pattern = "\\b(" + forms.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")\\w*"
        return regex(s, pattern, color, size: size)
    }
    static func regex(_ s: String, _ pattern: String, _ color: Color, size: CGFloat = 14) -> AttributedString {
        var a = AttributedString(s)
        guard !pattern.isEmpty, let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return a }
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard m.range.length > 0, let r = Range(m.range, in: s),
                  let lo = AttributedString.Index(r.lowerBound, within: a), let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
            a[lo..<hi].foregroundColor = color
            a[lo..<hi].backgroundColor = color.opacity(0.14)
            a[lo..<hi].font = .serif(size, .semibold)
        }
        return a
    }
}
