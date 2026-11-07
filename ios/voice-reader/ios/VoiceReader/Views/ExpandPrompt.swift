// Genişlet (2026-11-04): a prompt made from the book itself. A marked or selected passage (or all the marks of a book,
// or the chapter being read) becomes the topic; the app gathers its context (book, author, chapter, the paragraphs
// around it), the reader picks what the text is for and how long it is, copies the prompt, pastes it into any AI and
// brings the answer back. The answer goes into the book's own folder as "Genişletme · …", its author line naming the
// source book. A long text (≈ 30 minutes) can come in two answers: the first is kept, "devam" is copied, the second
// is joined to it. Same rules for the ear as İstem oluşturucu (PromptBuilder.swift).
import SwiftUI

/// What the prompt is made from.
enum ExpandSource: Identifiable, Hashable {
    case passage(doc: UUID, range: NSRange, text: String)   // one marked or selected passage
    case marks(doc: UUID)                                   // every mark of the book
    case chapter(doc: UUID, offset: Int)                    // the chapter at an offset

    var id: String {
        switch self {
        case .passage(let d, let r, _): "p-\(d)-\(r.location)-\(r.length)"
        case .marks(let d): "m-\(d)"
        case .chapter(let d, let o): "c-\(d)-\(o)"
        }
    }
    var documentID: UUID {
        switch self { case .passage(let d, _, _), .marks(let d), .chapter(let d, _): d }
    }
}

struct ExpandRequest: Equatable {
    enum Purpose: String, CaseIterable, Identifiable {
        case deepen, simplify, examples, counter, apply, history, compile, review
        var id: String { rawValue }
        var name: String {
            switch self {
            case .deepen: "Derinleştir"
            case .simplify: "Basitçe anlat"
            case .examples: "Örneklerle"
            case .counter: "Karşı görüş"
            case .apply: "Hayatıma uygula"
            case .history: "Tarihçe ve bağlam"
            case .compile: "Derleme"
            case .review: "Pekiştirme"
            }
        }
        var symbol: String {
            switch self {
            case .deepen: "arrow.down.to.line"
            case .simplify: "lightbulb"
            case .examples: "list.star"
            case .counter: "arrow.left.arrow.right"
            case .apply: "figure.walk"
            case .history: "clock.arrow.circlepath"
            case .compile: "square.stack.3d.up"
            case .review: "checkmark.bubble"
            }
        }
        var instruction: String {
            switch self {
            case .deepen: "Bu kısmı derinleştir: içindeki iddiayı ve kavramları tek tek aç, gerekçelerini göster, yazarın bunu neden söylediğini ve bu düşüncenin hangi soruya cevap olduğunu anlat. Konunun daha az bilinen, ince yanlarına in."
            case .simplify: "Bu kısmı hiç bilmeyen birine anlatır gibi açıkla: önce gündelik bir benzetmeyle sezgiyi kur, sonra kavramları adım adım tanıt, en sonda kısmın kendi diline dön ve onu yeniden oku."
            case .examples: "Bu kısmı somut örneklerle aç: farklı alanlardan (gündelik hayat, tarih, bilim, iş) en az beş örnek ver; her örnekte fikrin nasıl işlediğini göster, son örnekte fikrin sınırına dokun."
            case .counter: "Bu kısma yöneltilmiş en güçlü itirazları anlat: kim itiraz etti, hangi gerekçeyle; sonra yazarın ya da savunucularının cevabını ver ve tartışmanın bugün nerede durduğunu söyle. Taraf tutma, iki tarafın en iyi hâlini kur."
            case .apply: "Bu kısmı gündelik hayata, iş hayatına ve karar vermeye uygula: fikir bugün nerede işe yarar, hangi hatayı önler, nasıl bir alışkanlığa dönüşür. Sonda dinleyenin bu hafta deneyebileceği tek bir somut alıştırma öner."
            case .history: "Bu kısmın tarihçesini ve bağlamını anlat: fikir nereden geldi, kimlerden etkilendi, yazıldığı dönemde neye cevap veriyordu, sonra kimler onu sürdürdü ya da değiştirdi."
            case .compile: "Bu kitapta işaretlediğim kısımları bir araya getir: onları birbirine bağlayan ana düşünceyi bul, işaretleri bir anlatının içinde sırayla açıkla, aralarındaki boşlukları kitabın bütünüyle doldur. İşaretlerin neden önemli olduğu anlaşılsın."
            case .review: "Bu bölümü pekiştirmek için bir metin yaz: önce bölümün ana fikrini ve akışını kısaca toparla, sonra bölümden çıkan on soruyu birer birer sor; her sorudan sonra kısa bir sessizlik cümlesi koy (\"Cevabı düşün.\") ve ardından cevabı açıkla. Sonda bölümün en önemli üç fikrini yeniden söyle."
            }
        }
        static func choices(for s: ExpandSource) -> [Purpose] {
            switch s {
            case .passage: [.deepen, .simplify, .examples, .counter, .apply, .history]
            case .marks: [.compile, .deepen, .apply, .counter]
            case .chapter: [.review, .deepen, .simplify, .examples]
            }
        }
    }

    enum Length: Int, CaseIterable, Identifiable {
        case short = 2300, medium = 5000, long = 10000
        var id: Int { rawValue }
        /// Minutes at Voice Dream's 330 words a minute.
        var minutes: Int { Int((Double(rawValue) / 330).rounded()) }
        var name: String {
            switch self {
            case .short: "Kısa"
            case .medium: "Orta"
            case .long: "Uzun"
            }
        }
        var detail: String { "≈ \(minutes) dk · \(rawValue.formatted()) kelime" }
    }

    var purpose: Purpose = .deepen
    var length: Length = .medium
    var english = false
    var note = ""

    /// The context gathered from the book.
    struct Context: Equatable {
        var book = ""
        var author: String?
        var chapter: String?
        var focus = ""                          // the passage, the marks or the chapter
        var before = ""
        var after = ""
    }

    func prompt(_ c: Context, source: ExpandSource) -> String {
        let lang = english ? "İngilizce (English)" : "Türkçe"
        var p = "Sesli okuma (text-to-speech) için bir metin yaz. Metin bir okuma uygulamasında yüksek hızda dinlenecek; bu yüzden yalnız kulağa göre yazılmış düz metin (TXT) istiyorum.\n\n"
        p += "Kaynak kitap: \(c.book)"
        if let a = c.author, !a.isEmpty { p += " (\(a))" }
        if let ch = c.chapter, !ch.isEmpty { p += "\nBölüm: \(ch)" }
        switch source {
        case .passage:
            p += "\n\nKonu, kitapta işaretlediğim şu kısım:\n«\(c.focus)»"
            if !c.before.isEmpty { p += "\n\nKısmın hemen öncesi (bağlam için):\n\(c.before)" }
            if !c.after.isEmpty { p += "\n\nKısmın hemen sonrası (bağlam için):\n\(c.after)" }
        case .marks:
            p += "\n\nKitapta işaretlediğim kısımlar (sırayla):\n\(c.focus)"
        case .chapter:
            p += "\n\nBölümün metni:\n\(c.focus)"
        }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        p += "\n\nAmaç: \(purpose.instruction)"
        if !n.isEmpty { p += "\nAyrıca şunu istiyorum: \(n)" }
        p += "\n\nDil: \(lang). Uzunluk: yaklaşık \(length.rawValue.formatted()) kelime (dinlemesi ≈ \(length.minutes) dakika). Kısmı ya da kitabı özetleyip bırakma; onun üzerinden yeni bilgi, açıklama ve bağlam kat. Uzunluğu doldurmak için tekrar etme."
        if length == .long {
            p += "\nMetin uzun olduğu için iki cevapta yazabilirsin: ilk cevapta metnin yarısını yaz ve son satıra tek başına DEVAMI VAR yaz. Ben \"devam\" yazınca kaldığın yerden sürdür; başlığı ve girişi tekrarlama. Tek cevaba sığarsa tek cevapta yaz."
        }
        p += """


        Biçim kuralları (hepsine uy):
        1. Düz metin yaz. Yalnız başlık satırlarında işaret kullan: ilk satır "# " ile metnin adı, bölümler "## " ile (bunlar içindekiler olur). Kalın, italik, madde, numaralı liste, tablo, kod, alıntı bloğu ve yatay çizgi kullanma.
        2. Her paragraf tam cümlelerden oluşsun ve noktalama işaretiyle bitsin. Paragrafları tek boş satırla ayır; bir cümleyi satır sonuyla bölme.
        3. Birim ve simgeleri yazıyla ver: "yüzde 40", "metre", "dolar". Kısaltmaları ilk geçtiği yerde açık yaz.
        4. Bağlantı, dipnot, kaynak numarası, parantez içi atıf, emoji ve özel simge kullanma. Bir kaynağı anmak gerekiyorsa cümlenin içinde adıyla an.
        5. Cümleler çoğunlukla 10 ile 25 kelime arasında olsun.
        6. Giriş cümlesi ("Elbette", "İşte metniniz") ya da sonda açıklama ekleme; doğrudan başlıkla başla, metnin son cümlesiyle bitir.
        """
        return p
    }

    /// The context for a source, out of the book's text.
    static func context(_ source: ExpandSource, doc: DocumentRecord, content: DocumentContent?) -> Context {
        var c = Context(book: doc.title, author: doc.author)
        let text = (content?.text ?? "") as NSString
        let chapters = content?.chapters ?? []
        func chapter(at i: Int) -> Chapter? { chapters.last { $0.offset <= i } }
        func clip(_ r: NSRange) -> String {
            guard text.length > 0 else { return "" }
            let lo = max(0, min(text.length, r.location)), hi = max(lo, min(text.length, NSMaxRange(r)))
            return text.substring(with: NSRange(location: lo, length: hi - lo)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch source {
        case .passage(_, let r, let t):
            c.focus = t.trimmingCharacters(in: .whitespacesAndNewlines)
            let ch = chapter(at: r.location)
            c.chapter = ch?.title
            let start = max(ch?.offset ?? 0, r.location - 900)
            c.before = Self.wholeParagraphs(clip(NSRange(location: start, length: r.location - start)), fromEnd: true)
            c.after = Self.wholeParagraphs(clip(NSRange(location: NSMaxRange(r), length: 500)), fromEnd: false)
        case .marks:
            let marks = doc.highlights.sorted { $0.location < $1.location }.prefix(60)
            var lines: [String] = []
            var last: String?
            for h in marks {
                if let t = chapter(at: h.location)?.title, t != last { lines.append("\n[\(t)]"); last = t }
                var line = "— \(h.text.trimmingCharacters(in: .whitespacesAndNewlines))"
                if let n = h.note, !n.isEmpty { line += " (notum: \(n))" }
                lines.append(line)
            }
            c.focus = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .chapter(_, let o):
            let i = chapters.lastIndex { $0.offset <= o }
            let start = i.map { chapters[$0].offset } ?? 0
            let end = i.flatMap { $0 + 1 < chapters.count ? chapters[$0 + 1].offset : nil } ?? text.length
            c.chapter = i.map { chapters[$0].title }
            // a chapter of at most ~4.000 words, so the prompt fits any AI's box
            c.focus = clip(NSRange(location: start, length: min(end - start, 26_000)))
        }
        return c
    }

    /// Cuts a bit of text at a paragraph (or at least a sentence) so the context starts and ends cleanly.
    static func wholeParagraphs(_ s: String, fromEnd: Bool) -> String {
        guard !s.isEmpty else { return s }
        if fromEnd {
            if let r = s.range(of: "\n") { return String(s[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let r = s.range(of: ". ") { return String(s[r.upperBound...]) }
        } else {
            if let r = s.range(of: "\n", options: .backwards) { return String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
            if let r = s.range(of: ". ", options: .backwards) { return String(s[...r.lowerBound]) }
        }
        return s
    }
}

struct ExpandPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let source: ExpandSource
    @State private var req = ExpandRequest()
    @State private var context = ExpandRequest.Context()
    @State private var copied = false
    @State private var showPrompt = false
    // the first half of a long answer, kept while the second is fetched (the app may go to the background meanwhile)
    @AppStorage("expand.part1") private var part1 = ""
    @AppStorage("expand.part1.source") private var part1Source = ""

    private var doc: DocumentRecord? { model.store.document(source.documentID) }
    private var prompt: String { req.prompt(context, source: source) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(focusTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(context.focus.isEmpty ? "…" : context.focus)
                            .font(.system(.callout, design: .serif))
                            .lineLimit(6)
                        Text([context.book, context.chapter].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text(contextNote)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ExpandRequest.Purpose.choices(for: source)) { p in
                            let on = req.purpose == p
                            Button { req.purpose = p } label: {
                                Label(p.name, systemImage: p.symbol)
                                    .font(.subheadline.weight(on ? .semibold : .regular))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Ek isteğin (isteğe bağlı)", text: $req.note, axis: .vertical).lineLimit(1...4)
                } header: { Text("1 · Ne için") }

                Section {
                    Picker("Uzunluk", selection: $req.length) {
                        ForEach(ExpandRequest.Length.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(req.length.detail + (req.length == .long ? " · gerekirse iki cevapta gelir" : ""))
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("İngilizce yazılsın", isOn: $req.english)
                } header: { Text("2 · Uzunluk") }

                Section {
                    Button {
                        UIPasteboard.general.string = prompt
                        copied = true
                    } label: { Label(copied ? "Kopyalandı" : "İstemi kopyala", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .disabled(context.focus.isEmpty)
                    HStack {
                        Button("Claude'u aç") { if let u = URL(string: "https://claude.ai/new") { openURL(u) } }
                        Spacer()
                        Button("ChatGPT'yi aç") { if let u = URL(string: "https://chatgpt.com/") { openURL(u) } }
                    }
                    .buttonStyle(.borderless)
                    DisclosureGroup("İstemi gör", isExpanded: $showPrompt) {
                        Text(prompt).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } header: { Text("3 · Kopyala, yapay zekâya yapıştır") }

                Section {
                    if part1.isEmpty || part1Source != source.id {
                        Button { add() } label: { Label("Panodaki cevabı kitaplığa ekle", systemImage: "text.badge.plus") }
                        if req.length == .long {
                            Button { keepFirst() } label: { Label("Cevap yarım kaldı: 1. parçayı sakla", systemImage: "square.and.arrow.down") }
                        }
                    } else {
                        Label("1. parça saklandı · \(Self.words(part1).formatted()) kelime", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = "devam"
                        } label: { Label("\"devam\" yazısını kopyala", systemImage: "arrow.right.doc.on.clipboard") }
                        Button { add(joining: true) } label: { Label("2. parçayı ekle ve kitaplığa koy", systemImage: "text.badge.plus") }
                        Button(role: .destructive) { part1 = ""; part1Source = "" } label: { Label("Saklanan parçayı bırak", systemImage: "xmark") }
                    }
                } header: { Text("4 · Cevabı kopyala, buraya dön") } footer: {
                    Text("Metin \"\(doc?.folder ?? "Klasörsüz")\" içine \"Genişletme · …\" adıyla girer; yazar satırında kaynak kitap durur. Başlıklar içindekiler olur.")
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onChange(of: req) { copied = false }
            .task {
                req.purpose = ExpandRequest.Purpose.choices(for: source)[0]
                guard let d = doc else { return }
                let content = await model.store.content(for: d.id)
                context = ExpandRequest.context(source, doc: d, content: content)
            }
        }
    }

    private var navTitle: String {
        switch source {
        case .passage: "Bu kısmı genişlet"
        case .marks: "İşaretlerimden metin"
        case .chapter: "Bölümden metin"
        }
    }
    private var focusTitle: String {
        switch source {
        case .passage: "Seçili kısım"
        case .marks: "\(doc?.highlights.count ?? 0) işaret"
        case .chapter: "Bölüm"
        }
    }
    private var contextNote: String {
        switch source {
        case .passage: "İsteme kitabın adı, bölümü ve kısmın öncesindeki ve sonrasındaki paragraf da girer."
        case .marks: "İşaretler kitaptaki sırasıyla, bölüm başlıkları ve notlarınla isteme girer (en çok 60)."
        case .chapter: "Bölümün metni (en çok ≈ 4.000 kelime) isteme girer."
        }
    }

    private static func words(_ s: String) -> Int { s.split { $0 == " " || $0 == "\n" }.count }

    private func keepFirst() {
        guard let s = UIPasteboard.general.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.importMessage = "Panoda metin yok."; return
        }
        part1 = s
        part1Source = source.id
    }

    private func add(joining: Bool = false) {
        guard var s = UIPasteboard.general.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.importMessage = "Panoda metin yok."; return
        }
        if joining {
            // the second answer may repeat the title: drop a first "# " line
            var second = s
            if let first = second.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first, first.hasPrefix("# ") {
                second = String(second.dropFirst(first.count))
            }
            s = part1 + "\n\n" + second
        }
        guard let d = doc, model.importExpansion(s, from: d) else { return }
        if joining { part1 = ""; part1Source = "" }
        dismiss()
    }
}

extension AppModel {
    /// An AI's answer to a Genişlet prompt, into the source book's folder; true when it was added.
    @discardableResult
    func importExpansion(_ raw: String, from source: DocumentRecord) -> Bool {
        // the two-part marker never reaches the ear
        let text = raw.replacingOccurrences(of: #"(?m)^\s*\**DEVAMI VAR\**\s*$"#, with: "", options: .regularExpression)
        guard let imported = DocumentImporter.fromClipboard(text) else {
            importMessage = "Panodaki cevap okunamadı."
            return false
        }
        guard let rec = try? store.add(imported, original: nil) else { return false }
        let title = imported.title.hasPrefix("Genişletme") ? imported.title : "Genişletme · \(imported.title)"
        store.update(rec.id) {
            $0.title = title
            $0.author = source.title
            $0.folder = source.folder
        }
        sync.publish(rec.id)
        importMessage = "“\(title)” kitaplığa eklendi."
        return true
    }
}
