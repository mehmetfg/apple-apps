// İstem oluşturucu: write the topic, the details and the length; copy the prompt; paste it into any AI (Claude,
// ChatGPT, Gemini…); copy its answer back; one tap adds it to the library. The prompt asks for text made for the ear:
// Markdown headings only (they become the table of contents), plain prose, numbers and abbreviations written out, no
// tables, lists, links or footnotes, so the answer reads cleanly in Wise Path at listening speed.
import SwiftUI

struct PromptRequest: Equatable {
    enum Length: Int, CaseIterable, Identifiable {
        case short = 1500, medium = 4000, long = 7000
        var id: Int { rawValue }
        var name: String {
            switch self {
            case .short: "Kısa · ~1.500 kelime"
            case .medium: "Orta · ~4.000 kelime"
            case .long: "Uzun · ~7.000 kelime"
            }
        }
        /// Minutes at Voice Dream's 330 words a minute.
        var minutes: Int { Int((Double(rawValue) / 330).rounded()) }
    }
    enum Form: String, CaseIterable, Identifiable {
        case lesson = "Ders", narrative = "Anlatı", summary = "Kitap özeti", dialogue = "Söyleşi"
        var id: String { rawValue }
        var instruction: String {
            switch self {
            case .lesson: "Bir ders gibi kur: önce konunun neden önemli olduğunu söyleyen bir giriş, sonra temelden ileriye giden bölümler, her bölümde somut bir örnek, sonda kısa bir toparlama."
            case .narrative: "Bir deneme ya da anlatı gibi yaz: bir sahne ya da soruyla aç, düşünceyi akış içinde geliştir, bölümleri birbirine bağla."
            case .summary: "Bir kitabın ya da eserin derinlikli özeti olarak yaz: ana tez, bölüm bölüm iddialar ve gerekçeleri, eserin etkisi ve ona yöneltilen en güçlü itiraz."
            case .dialogue: "İki kişinin söyleşisi olarak yaz; konuşanı her paragrafın başında adıyla ve iki noktayla belirt (örnek: Ayşe: …). Konuşma çizgisi, tırnak ya da sahne notu kullanma."
            }
        }
    }

    var topic = ""
    var details = ""
    var length: Length = .medium
    var form: Form = .lesson
    var english = false

    var prompt: String {
        let lang = english ? "İngilizce (English)" : "Türkçe"
        var p = """
        Sesli okuma (text-to-speech) için bir metin yaz. Metin bir okuma uygulamasında yüksek hızda dinlenecek; bu yüzden yalnız kulağa göre yazılmış düz metin istiyorum.

        Konu: \(topic.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { p += "\nAyrıntılar ve teknik istekler: \(d)" }
        p += """


        Biçim: \(form.instruction)
        Dil: \(lang). Uzunluk: yaklaşık \(length.rawValue.formatted()) kelime (dinlemesi ≈ \(length.minutes) dakika). Uzunluğu doldurmak için tekrar etme; konu daha kısa sürede bitiyorsa kısa bırak.

        Biçim kuralları (hepsine uy):
        1. Yalnız Markdown başlık kullan: ilk satır "# " ile metnin adı, bölümler "## " ile. Başka hiçbir Markdown işareti (kalın, italik, madde, numaralı liste, tablo, kod, alıntı bloğu, yatay çizgi) kullanma.
        2. Her paragraf tam cümlelerden oluşsun ve noktalama işaretiyle bitsin. Paragrafları tek boş satırla ayır; bir cümleyi satır sonuyla bölme.
        3. Sayıları ve yılları okunduğu gibi yazmak zorunda değilsin, ama birim ve simgeleri yazıyla ver: "yüzde 40", "metre", "dolar" (%, m, $ değil). Kısaltmaları ilk geçtiği yerde açık yaz.
        4. Bağlantı, dipnot, kaynak numarası, parantez içi atıf, emoji ve özel simge (→, •, ✓, *) kullanma. Bir kaynağı anmak gerekiyorsa cümlenin içinde adıyla an.
        5. Cümleler çoğunlukla 10 ile 25 kelime arasında olsun; çok uzun iç içe yan cümlelerden kaçın.
        6. Giriş cümlesi ("Elbette", "İşte metniniz" gibi) ya da sonda açıklama ekleme; doğrudan başlıkla başla, metnin son cümlesiyle bitir.
        """
        return p
    }
}

struct PromptBuilderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var req = PromptRequest()
    @State private var copied = false
    @State private var showPrompt = false

    private var ready: Bool { !req.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Konu (örn. Leibniz'in monadları)", text: $req.topic, axis: .vertical)
                    TextField("Teknik ayrıntılar, kapsam, seviye (isteğe bağlı)", text: $req.details, axis: .vertical)
                        .lineLimit(2...6)
                } header: { Text("1 · Konuyu yaz") }

                Section {
                    Picker("Biçim", selection: $req.form) { ForEach(PromptRequest.Form.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Uzunluk", selection: $req.length) { ForEach(PromptRequest.Length.allCases) { Text($0.name).tag($0) } }
                    Toggle("İngilizce yazılsın", isOn: $req.english)
                } header: { Text("Miktar ve biçim") }

                Section {
                    Button {
                        UIPasteboard.general.string = req.prompt
                        copied = true
                    } label: { Label(copied ? "Kopyalandı" : "İstemi kopyala", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .disabled(!ready)
                    HStack {
                        Button("Claude'u aç") { if let u = URL(string: "https://claude.ai/new") { openURL(u) } }
                        Spacer()
                        Button("ChatGPT'yi aç") { if let u = URL(string: "https://chatgpt.com/") { openURL(u) } }
                    }
                    .buttonStyle(.borderless)
                    DisclosureGroup("İstemi gör", isExpanded: $showPrompt) {
                        Text(req.prompt).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                } header: { Text("2 · Kopyala, yapay zekâya yapıştır") } footer: {
                    Text("İstem herhangi bir yapay zekâda çalışır. Uygulamasını ya da sitesini aç, istemi yapıştır, gönder.")
                }

                Section {
                    Button {
                        model.importClipboard()
                        dismiss()
                    } label: { Label("Panodaki cevabı kitaplığa ekle", systemImage: "text.badge.plus") }
                } header: { Text("3 · Cevabı kopyala, buraya dön") } footer: {
                    Text("Cevabın tamamını kopyala (çoğu uygulamada cevabın altındaki kopyala simgesi). Başlıklar içindekiler olur, metin dinlemeye hazır temizlenir. Cevabı .md dosyası olarak paylaşırsan \"Birlikte aç › Wise Path\" de aynı işi yapar.")
                }
            }
            .navigationTitle("İstem oluşturucu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .onChange(of: req) { copied = false }
        }
    }
}
