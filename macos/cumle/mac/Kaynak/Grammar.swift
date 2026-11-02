// Gramer sayfası (⌥G): solda bugünün konuları (metnin yapıları + döngü), sağda konu kartı.
// Kart: ne zaman · renkli kalıp şeridi · yanlış ✗ / doğru ✓ · örnekler (karttan + bugünün metninden, yapı işaretli)
// · alıştırma: 3 soru (boşluk · seç · kur), cevaptan sonra tek satır açıklama. Kayıt tutulmaz, puan yok.
import SwiftUI

struct GrammarSheet: View {
    @EnvironmentObject var t: Tezgah
    @Environment(\.dismiss) var close
    @State private var selected: String?      // topic name; nil = cycle calendar

    var body: some View {
        let today = t.todayTopics
        let opened = (t.gramerSayfa ?? []).filter { !today.text.contains($0) && !today.cycle.contains($0) }
        HStack(spacing: 0) {
            // left rail
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        rail("Bugünün metni", "text.quote", today.text)
                        rail("Döngüden bugün", "arrow.triangle.2.circlepath", today.cycle)
                        if !opened.isEmpty { rail("Açılan", "bookmark", opened) }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TÜM KONULAR").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).tracking(0.6)
                            railButton(nil, title: "Döngü takvimi · 41 konu", icon: "calendar")
                        }
                    }
                    .padding(14)
                }
                Spacer(minLength: 0)
                Divider()
                Button("Kapat") { close() }.keyboardShortcut(.cancelAction).padding(12)
            }
            .frame(width: 250)
            .background(Renk.kenar)
            Divider()
            ScrollView {
                Group {
                    if let s = selected { TopicCard(name: s).id(s) }
                    else { DonguGorunum(ac: { selected = $0 }) }
                }
                .padding(.horizontal, 34).padding(.vertical, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Renk.zemin)
        }
        .frame(width: 1060, height: 760)
        .onAppear {
            let l = t.gramerSayfa ?? []
            selected = t.gramerI < 0 ? nil : (l[safe: t.gramerI] ?? today.text.first ?? today.cycle.first)
        }
    }

    func rail(_ title: String, _ icon: String, _ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: icon).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            if list.isEmpty { Text("—").font(.callout).foregroundStyle(.tertiary) }
            ForEach(list, id: \.self) { railButton($0, title: Gramer.kisa($0), icon: nil) }
        }
    }

    func railButton(_ name: String?, title: String, icon: String?) -> some View {
        let on = selected == name
        let g = name.flatMap { t.gramerMap[$0] }
        return Button { withAnimation(.easeOut(duration: 0.15)) { selected = name } } label: {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).frame(width: 16) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(on ? .semibold : .regular)).lineLimit(1)
                    if let g { Text(g.tr).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if g?.yildiz == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Renk.sari) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 8).fill(on ? Renk.vurgu.opacity(0.16) : .clear) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Topic card

struct TopicCard: View {
    var name: String
    @EnvironmentObject var t: Tezgah

    var body: some View {
        if let g = t.gramerMap[name] {
            VStack(alignment: .leading, spacing: 26) {
                header(g)
                section("Ne zaman kullanılır", "lightbulb") { Text(g.ne).font(.title3).fixedSize(horizontal: false, vertical: true) }
                section("Kalıp", "square.stack.3d.up") { PatternStrip(formula: g.formul) }
                section("Yanlış · doğru", "checkmark.arrow.trianglehead.counterclockwise") { TrapCompare(text: g.tuzak) }
                section("Örnekler", "text.bubble") { examples(g) }
                section("Alıştırma · 3 soru", "pencil.and.list.clipboard") {
                    PracticeSet(questions: questions(g)).id(g.ad)
                }
            }
        } else {
            Text("Bu konunun kartı yok.").foregroundStyle(.secondary)
        }
    }

    func header(_ g: GramerKart) -> some View {
        let isText = t.todayTopics.text.contains(g.ad)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Cip(metin: "Faz \(g.faz)", renk: Renk.vurgu)
                if isText { Cip(metin: "bugünün metninde", renk: Renk.yesil, simge: "text.quote") }
                if g.yildiz { Cip(metin: "kalıcı boşluk", renk: Renk.sari, simge: "star.fill") }
                if let sk = score(g.ad) { Cip(metin: "yapı skoru %\(sk)", renk: sk < 90 ? Renk.sari : Renk.yesil) }
            }
            Text(Gramer.kisa(g.ad)).font(.system(size: 32, weight: .bold))
            Text(g.tr).font(.title2).foregroundStyle(.secondary)
            if Gramer.kisa(g.ad) != g.ad { Text(g.ad).font(.callout).foregroundStyle(.tertiary) }
        }
    }

    func score(_ ad: String) -> Int? {
        let s = (t.arsiv.kurmaYapilar[ad] ?? []).compactMap(\.skor)
        return s.isEmpty ? nil : Int((Double(s.reduce(0, +)) / Double(s.count)).rounded())
    }

    @ViewBuilder func examples(_ g: GramerKart) -> some View {
        let day = t.o?.gun ?? t.gunMasa
        let fromText = (day?.cumleler ?? []).filter { $0.konu == g.ad }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(g.ornek.enumerated()), id: \.offset) { _, o in
                exampleRow(en: o.first ?? "", tr: o.count > 1 ? o.last : nil, desen: g.desen, tag: nil)
            }
            if !fromText.isEmpty {
                Text("BUGÜNÜN METNİNDEN · Gün \(day?.no ?? 0)").font(.caption2.weight(.semibold)).foregroundStyle(Renk.yesil).tracking(0.6).padding(.top, 6)
                ForEach(fromText, id: \.self) { c in exampleRow(en: c.en, tr: c.tr, desen: g.desen, tag: "metin") }
            }
        }
    }

    func exampleRow(en: String, tr: String?, desen: String, tag: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { t.ses.soyle(en) } label: { Image(systemName: "speaker.wave.2.fill").frame(width: 26, height: 26) }
                .buttonStyle(.borderless).accessibilityLabel("Dinle")
            VStack(alignment: .leading, spacing: 3) {
                Text(Highlight.regex(en, desen, Renk.vurgu, size: 18)).font(.serif(18)).fixedSize(horizontal: false, vertical: true)
                if let tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tag == nil ? Renk.kart : Renk.yesil.opacity(0.07)) }
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Renk.cizgi) }
    }

    /// Practice set; the card's own mini question is the fallback.
    func questions(_ g: GramerKart) -> [PracticeQuestion] {
        if let q = t.practice[g.ad], !q.isEmpty { return q }
        guard !g.yoklaS.isEmpty else { return [] }
        let ans = g.yoklaC.components(separatedBy: " · ").joined(separator: " ")
        return [PracticeQuestion(kind: .gap, prompt: g.yoklaS, answers: [ans], options: [], correct: 0, parts: [], tr: "", why: g.ne)]
    }

    func section<I: View>(_ title: String, _ icon: String, @ViewBuilder _ i: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title.uppercased(), systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            i()
        }
    }
}

/// "a/an + tekil (yeni) · the + bilinen" → one row per alternative, colored token per slot.
struct PatternStrip: View {
    var formula: String
    var body: some View {
        let rows = formula.components(separatedBy: " · ").flatMap { $0.components(separatedBy: " ↔ ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let tokens = row.components(separatedBy: " + ").map { $0.trimmingCharacters(in: .whitespaces) }
                Akis(aralik: 6) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { i, tok in
                        if i > 0 { Text("+").font(.callout.weight(.semibold)).foregroundStyle(.tertiary) }
                        token(tok, Renk.tokens[i % Renk.tokens.count])
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Renk.kart) }
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Renk.cizgi) }
            }
        }
    }
    func token(_ s: String, _ c: Color) -> some View {
        // "(yeni)" style notes become a small caption under the token
        let parts = s.split(separator: "(", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let main = parts.first ?? s, note = parts.count > 1 ? String(parts[1].dropLast(parts[1].hasSuffix(")") ? 1 : 0)) : nil
        return VStack(alignment: .leading, spacing: 1) {
            Text(main).font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(c)
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(c.opacity(0.13)) }
    }
}

/// "note: ✗ wrong → ✓ right (why)" → two side-by-side cards; anything else stays as a note.
struct TrapCompare: View {
    var text: String
    var body: some View {
        if let p = parse() {
            VStack(alignment: .leading, spacing: 8) {
                if let pre = p.pre, !pre.isEmpty { Text(pre).font(.callout).foregroundStyle(.secondary) }
                IkiliSira {
                    box("✗", p.wrong, Renk.kirmizi)
                } b: {
                    box("✓", p.right, Renk.yesil)
                }
                if let n = p.note { Label(n, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            }
        } else {
            Label(text, systemImage: "exclamationmark.triangle").font(.title3)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background { RoundedRectangle(cornerRadius: 10).fill(Renk.sari.opacity(0.1)) }
        }
    }
    func box(_ mark: String, _ s: String, _ c: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(mark).font(.title2.weight(.bold)).foregroundStyle(c)
            Text(s).font(.serif(17)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.opacity(0.1)) }
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c.opacity(0.3)) }
    }
    func parse() -> (pre: String?, wrong: String, right: String, note: String?)? {
        guard let x = text.range(of: "✗"), let arrow = text.range(of: "→", range: x.upperBound..<text.endIndex),
              let check = text.range(of: "✓", range: arrow.upperBound..<text.endIndex) else { return nil }
        let pre = String(text[..<x.lowerBound]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let wrong = String(text[x.upperBound..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
        var right = String(text[check.upperBound...]).trimmingCharacters(in: .whitespaces), note: String?
        if right.hasSuffix(")"), let open = right.range(of: " (", options: .backwards) {
            note = String(right[open.upperBound..<right.index(before: right.endIndex)])
            right = String(right[..<open.lowerBound])
        }
        return (pre.isEmpty ? nil : pre, wrong, right, note)
    }
}

// MARK: - Practice: 3 questions

struct PracticeSet: View {
    var questions: [PracticeQuestion]
    @State private var results: [Int: Bool] = [:]
    @State private var round = 0      // bump to reset all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if questions.isEmpty { Text("Bu konuya alıştırma yazılmadı.").foregroundStyle(.secondary) }
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                QuestionCard(n: i + 1, q: q) { ok in results[i] = ok }
            }
            if !questions.isEmpty && results.count == questions.count {
                let n = results.values.filter { $0 }.count
                HStack(spacing: 12) {
                    Image(systemName: n == questions.count ? "checkmark.seal.fill" : "arrow.clockwise.circle")
                        .font(.title2).foregroundStyle(n == questions.count ? Renk.yesil : Renk.sari)
                    Text(n == questions.count ? "\(n)/\(questions.count) — yapı oturdu." : "\(n)/\(questions.count) — açıklamalara bak, sonra yeniden dene.")
                        .font(.headline)
                    Spacer()
                    Button("Baştan") { results = [:]; round += 1 }
                }
                .padding(12)
                .background { RoundedRectangle(cornerRadius: 10).fill((n == questions.count ? Renk.yesil : Renk.sari).opacity(0.1)) }
            }
        }
        .id(round)
    }
}

struct QuestionCard: View {
    var n: Int
    var q: PracticeQuestion
    var done: (Bool) -> Void
    @EnvironmentObject var t: Tezgah
    @State private var text = ""
    @State private var picked: Int?
    @State private var pool: [Int] = []       // indices into q.parts, still unplaced
    @State private var line: [Int] = []
    @State private var result: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("\(n)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background { Circle().fill(badge) }
                Text(kindLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.5)
                Spacer()
            }
            switch q.kind {
            case .gap: gap
            case .choose: choose
            case .build: build
            }
            if let r = result {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: r ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r ? Renk.yesil : Renk.kirmizi)
                    VStack(alignment: .leading, spacing: 3) {
                        if !r { Text("Doğrusu: " + rightAnswer).font(.serif(16, .semibold)) }
                        Text(q.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button { t.ses.soyle(fullSentence) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless).accessibilityLabel("Doğru cümleyi dinle")
                }
                .padding(10)
                .background { RoundedRectangle(cornerRadius: 8).fill((r ? Renk.yesil : Renk.kirmizi).opacity(0.08)) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Renk.kart) }
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(result.map { ($0 ? Renk.yesil : Renk.kirmizi).opacity(0.45) } ?? Renk.cizgi) }
        .animation(.easeOut(duration: 0.18), value: result)
        .onAppear { if pool.isEmpty && line.isEmpty { pool = shuffled() } }
    }

    var badge: Color { result.map { $0 ? Renk.yesil : Renk.kirmizi } ?? Renk.vurgu }
    var kindLabel: String { switch q.kind { case .gap: "BOŞLUK DOLDUR"; case .choose: "DOĞRUSUNU SEÇ"; case .build: "CÜMLEYİ KUR" } }
    var rightAnswer: String {
        switch q.kind {
        case .gap: q.answers.first ?? ""
        case .choose: q.options[safe: q.correct] ?? ""
        case .build: q.parts.joined(separator: " ")
        }
    }
    var fullSentence: String {
        switch q.kind {
        case .gap:
            let base = q.prompt.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
            let blanks = base.components(separatedBy: "___").count - 1
            let a = q.answers.first ?? ""
            let words = a.split(separator: " ").map(String.init)
            var s = base, k = 0
            while let r = s.range(of: "___") { s.replaceSubrange(r, with: blanks > 1 ? (words[safe: k] ?? "") : a); k += 1 }
            return s
        case .choose: return q.options[safe: q.correct] ?? ""
        case .build: return q.parts.joined(separator: " ")
        }
    }

    // gap
    var gap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(q.prompt.replacingOccurrences(of: "___", with: "＿＿＿")).font(.serif(19)).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("cevabın", text: $text).textFieldStyle(.roundedBorder).font(.system(size: 15)).frame(maxWidth: 280)
                    .disabled(result != nil).onSubmit(checkGap)
                Button("Kontrol") { checkGap() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || result != nil)
            }
        }
    }
    func checkGap() {
        guard result == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        finish(q.answers.map(Practice.normal).contains(Practice.normal(text)))
    }

    // choose
    var choose: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(q.prompt).font(.callout).foregroundStyle(.secondary)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                let state: Color? = result == nil ? nil : i == q.correct ? Renk.yesil : i == picked ? Renk.kirmizi : nil
                Button { guard result == nil else { return }; picked = i; finish(i == q.correct) } label: {
                    HStack(spacing: 10) {
                        Text(["A", "B", "C", "D"][safe: i] ?? "").font(.callout.weight(.bold)).foregroundStyle(state ?? .secondary).frame(width: 18)
                        Text(o).font(.serif(17)).frame(maxWidth: .infinity, alignment: .leading)
                        if let state { Image(systemName: state == Renk.yesil ? "checkmark" : "xmark").foregroundStyle(state) }
                    }
                    .padding(10)
                    .background { RoundedRectangle(cornerRadius: 8).fill((state ?? Color.secondary).opacity(state == nil ? 0.07 : 0.13)) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // build
    var build: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !q.tr.isEmpty { Text("“\(q.tr)”").font(.callout).foregroundStyle(.secondary) }
            Akis(aralik: 6) {
                ForEach(line, id: \.self) { i in chip(q.parts[i], on: true) { guard result == nil else { return }; line.removeAll { $0 == i }; pool.append(i) } }
                if line.isEmpty { Text("kelimelere sırayla tıkla").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 6) }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.secondary.opacity(0.4)) }
            Akis(aralik: 6) {
                ForEach(pool, id: \.self) { i in chip(q.parts[i], on: false) { guard result == nil else { return }; pool.removeAll { $0 == i }; line.append(i) } }
            }
            HStack {
                Button("Kontrol") { finish(line.map { q.parts[$0] } == q.parts) }.disabled(!pool.isEmpty || result != nil)
                Button("Sıfırla") { line = []; pool = shuffled() }.buttonStyle(.borderless).disabled(result != nil)
            }
        }
    }
    func chip(_ s: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(s).font(.serif(16)).padding(.horizontal, 10).padding(.vertical, 5)
                .background { RoundedRectangle(cornerRadius: 7).fill(on ? Renk.vurgu.opacity(0.18) : Renk.kart2) }
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Renk.cizgi) }
        }
        .buttonStyle(.plain)
    }
    func shuffled() -> [Int] {
        var r = Array(q.parts.indices)
        guard r.count > 1 else { return r }
        repeat { r.shuffle() } while r == Array(q.parts.indices)
        return r
    }

    func finish(_ ok: Bool) {
        result = ok
        done(ok)
    }
}
