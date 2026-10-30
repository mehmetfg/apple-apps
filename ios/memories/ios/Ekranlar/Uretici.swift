// Telefonda paket üretimi (2026-10-30, kullanıcı kararı): müfredatı Mac seçer (gun.py brief --json),
// metni iPhone yazar. Qwen3.5-2B (MLX, 4-bit) yalnız İngilizce yazar — cümle cümle, uzunluğu ve yapıyı kod tutar;
// Türkçe Apple Translation'dan (UretEkrani), ses AVSpeechSynthesizer'dan. Çıktı Mac'in paket.json biçimi:
// Dinle · Oku · widget değişmeden çalışır. Model uygulamaya gömülmez: App Group › Model klasöründen yüklenir.
@preconcurrency import AVFoundation
import Foundation
import MLXLLM
import MLXLMCommon
import Tokenizers

@MainActor
final class Uretici: ObservableObject {
    static let shared = Uretici()

    enum Asama: Equatable {
        case bos, hazirlik, model, ingilizce(Int, Int), ceviri, ses, bitti(Int), hata(String)
    }

    struct Taslak: Identifiable, Hashable {
        var i: Int
        var en: String
        var tr: String?
        var konu: String?
        var sorun: [String] = []
        var deneme = 1
        var id: Int { i }
    }

    @Published private(set) var asama: Asama = .bos
    @Published private(set) var tokSn: Double = 0
    @Published private(set) var cumleler: [Taslak] = []
    @Published private(set) var gunluk: [String] = []
    @Published private(set) var brief: Brief?
    @Published private(set) var denetim: Denetci.Sonuc?
    @Published private(set) var iceAktariliyor = false
    @Published var bilgi: String?

    private var konteyner: ModelContainer?
    private var denetci: Denetci?
    private var fikir = "", baslik = "", ozetEn = "", temaEn = ""
    private var ozetTr: String?, temaTr: String?

    // MARK: Model

    nonisolated static let modelAdi = "Qwen3.5-2B-text-4bit"
    /// App Group › qwen/: telefonun iCloud'u vault'u eşitlemiyor (2026-10-13'ten beri), bu yüzden model ve brief
    /// Mac'ten kabloyla gelir — oncalisma/telefona_gonder.py (devicectl, appGroupDataContainer).
    nonisolated static var qwenKlasoru: URL { Paylasim.kapsayici.appendingPathComponent("qwen", isDirectory: true) }
    nonisolated static var modelKlasoru: URL { qwenKlasoru.appendingPathComponent("model", isDirectory: true) }
    /// brief/gun-NNN.json + brief/bilinen.json
    nonisolated static var briefKlasoru: URL { qwenKlasoru.appendingPathComponent("brief", isDirectory: true) }
    var modelVar: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: Uretici.modelKlasoru.appendingPathComponent("config.json").path)
            && fm.fileExists(atPath: Uretici.modelKlasoru.appendingPathComponent("model.safetensors").path)
    }
    var modelBoyutu: String {
        let u = Uretici.modelKlasoru.appendingPathComponent("model.safetensors")
        let n = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    /// Ayarlar › "Modeli içe aktar": Dosyalar'dan seçilen klasörü App Group'a kopyalar (~1 GB).
    func iceAktar(_ kaynak: URL) async {
        iceAktariliyor = true
        defer { iceAktariliyor = false }
        let hedef = Uretici.modelKlasoru
        let sonuc: String? = await Task.detached {
            let e = kaynak.startAccessingSecurityScopedResource()
            defer { if e { kaynak.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            guard fm.fileExists(atPath: kaynak.appendingPathComponent("config.json").path) else {
                return "Seçilen klasörde config.json yok — \(Uretici.modelAdi) klasörünün kendisini seç."
            }
            do {
                try? fm.removeItem(at: hedef)
                try fm.createDirectory(at: hedef, withIntermediateDirectories: true)
                for ad in try fm.contentsOfDirectory(atPath: kaynak.path) where !ad.hasPrefix(".") && !ad.hasSuffix(".md") {
                    let k = kaynak.appendingPathComponent(ad)
                    _ = Kasa.indir(k, bekle: 120)
                    try fm.copyItem(at: k, to: hedef.appendingPathComponent(ad))
                }
                return nil
            } catch { return error.localizedDescription }
        }.value
        konteyner = nil
        bilgi = sonuc ?? "Model içe aktarıldı (\(modelBoyutu))."
    }

    func modeliSil() {
        try? FileManager.default.removeItem(at: Uretici.modelKlasoru)
        konteyner = nil
        objectWillChange.send()
    }

    private func modelYukle() async throws -> ModelContainer {
        if let k = konteyner { return k }
        asama = .model
        let k = try await LLMModelFactory.shared.loadContainer(from: Uretici.modelKlasoru, using: TokenizerYukleyici())
        konteyner = k
        return k
    }

    // MARK: Brief

    /// Üretilecek gün: App Group › qwen/brief'teki en ileri brief (telefona_gonder.py atar). Orada yoksa vault denenir
    /// (iCloud düzelirse kendiliğinden çalışır) ve bulunan kopya qwen/brief'e yazılır.
    func briefBul(_ depo: Depo) async -> (Brief, Bilinen)? {
        if let x = yerelBrief() { return x }
        guard depo.kasa.bagli else { return nil }
        let vaulttan: (Int, Data, Data)? = await depo.kasa.ile { kok -> (Int, Data, Data)? in
            let pk = kok.appendingPathComponent("paket", isDirectory: true)
            let fm = FileManager.default
            let gunler = ((try? fm.contentsOfDirectory(atPath: pk.path)) ?? []).filter { $0.hasPrefix("gun-") }
                .compactMap { Int($0.dropFirst(4)) }.sorted(by: >)
            for g in gunler {
                let b = pk.appendingPathComponent(Paket.klasor(g)).appendingPathComponent("brief.json")
                guard fm.fileExists(atPath: b.path) || fm.fileExists(atPath: b.deletingLastPathComponent().appendingPathComponent(".brief.json.icloud").path) else { continue }
                let bj = pk.appendingPathComponent("bilinen.json")
                guard Kasa.indir(b, bekle: 10), Kasa.indir(bj, bekle: 20),
                      let bv = Kasa.koordineliOku(b), let jv = Kasa.koordineliOku(bj) else { return nil }
                return (g, bv, jv)
            }
            return nil
        } ?? nil
        guard let (g, bv, jv) = vaulttan else { return nil }
        let k = Uretici.briefKlasoru
        try? FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
        try? bv.write(to: k.appendingPathComponent("\(Paket.klasor(g)).json"), options: .atomic)
        try? jv.write(to: k.appendingPathComponent("bilinen.json"), options: .atomic)
        return yerelBrief()
    }

    /// qwen/brief/gun-NNN.json — en büyük gün; bilinen.json yanında.
    private func yerelBrief() -> (Brief, Bilinen)? {
        let k = Uretici.briefKlasoru
        guard let jv = try? Data(contentsOf: k.appendingPathComponent("bilinen.json")),
              let j = try? JSONDecoder().decode(Bilinen.self, from: jv) else { return nil }
        let adlar = ((try? FileManager.default.contentsOfDirectory(atPath: k.path)) ?? [])
            .filter { $0.hasPrefix("gun-") && $0.hasSuffix(".json") }
            .sorted { (Int($0.dropFirst(4).dropLast(5)) ?? 0) > (Int($1.dropFirst(4).dropLast(5)) ?? 0) }
        for ad in adlar {
            if let v = try? Data(contentsOf: k.appendingPathComponent(ad)), let b = try? JSONDecoder().decode(Brief.self, from: v) {
                return (b, j)
            }
        }
        return nil
    }

    // MARK: ① İngilizce

    private func yaz(_ s: String) { gunluk.append(s) }

    /// Cümle planı: her cümleye hedef kelimeler ve bir yapı. Uzunluk ve kapsam koddan gelir, modelden değil.
    private func planla(_ b: Brief) -> [Denetci.Plan] {
        let n = min(max(14, b.sinirlar.cumle[0]), b.sinirlar.cumle[1])
        // derle_kurma kelimeyi KELIME_RE ile sayar: tireli/çok kelimeli madde ("so-called") hiç tutmaz.
        // Brief'in kuralıyla sahneye sığmayan yedekten değiştirilir.
        var yeni = b.yeni.map(\.w)
        var yedek = (b.yedek ?? []).map(\.w).filter { !$0.contains("-") && !$0.contains(" ") }
        for (i, w) in yeni.enumerated() where w.contains("-") || w.contains(" ") {
            if !yedek.isEmpty { let y = yedek.removeFirst(); yaz("· \(w) → \(y) (tireli kelime derle'de sayılmaz)"); yeni[i] = y }
        }
        etkinYeni = yeni
        let yuva = yeni + b.yanki.map(\.w) + b.tanidik.map(\.w) + yeni
        var plan = (0..<n).map { _ in Denetci.Plan(kelimeler: [], yapi: nil, konu: nil) }
        for (k, w) in yuva.enumerated() {
            var i = k % n
            while plan[i].kelimeler.contains(w) || plan[i].kelimeler.count >= 3 { i = (i + 1) % n }
            plan[i].kelimeler.append(w)
        }
        let yapilar = b.sahne_konulari.flatMap { k in Yapi.cikar(k).map { (k, $0) } }
        if !yapilar.isEmpty {
            for i in 1..<(n - 1) {
                let (konu, y) = yapilar[(i - 1) % yapilar.count]
                plan[i].yapi = y; plan[i].konu = konu
            }
        }
        return plan
    }
    private var etkinYeni: [String] = []

    private static let sistem = """
        You write short, easy English (CEFR B1) for a Turkish learner. Everyday life, one clear story, \
        simple and common words, short natural sentences. Never write Turkish. Never explain.
        """

    /// Bir istem → tek satır yanıt.
    private func sor(_ k: ModelContainer, _ istem: String, sicaklik: Float = 0.7, enCok: Int = 60) async throws -> String {
        let girdi = UserInput(chat: [.system(Uretici.sistem), .user(istem)], additionalContext: ["enable_thinking": false])
        let hazir = try await k.prepare(input: girdi)
        let p = GenerateParameters(maxTokens: enCok, temperature: sicaklik, topP: 0.8, repetitionPenalty: 1.1, repetitionContextSize: 64)
        var metin = ""
        for await g in try await k.generate(input: hazir, parameters: p) {
            if let c = g.chunk { metin += c }
            if let i = g.info { tokSn = i.tokensPerSecond }
        }
        return metin.replacingOccurrences(of: "<think>", with: "").replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Yanıttan tek cümle: numara, tırnak, ikinci satır atılır; birden çok cümle varsa hedefleri en çok taşıyan.
    private func cumleAyikla(_ yanit: String, _ plan: Denetci.Plan) -> String {
        var s = yanit.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        s = s.replacingOccurrences(of: #"^(\d+[.)]\s*|[-*•]\s*|Sentence \d+:\s*)"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' "))
        let parcalar = Denetci.eslesmeler(#"[^.!?]+[.!?]+"#, s).map { $0.trimmingCharacters(in: .whitespaces) }
        if parcalar.count > 1 {
            s = parcalar.max { a, b in
                plan.kelimeler.filter { Denetci.gecis(a, $0) > 0 }.count < plan.kelimeler.filter { Denetci.gecis(b, $0) > 0 }.count
            } ?? s
        }
        if let son = s.last, !".!?".contains(son) { s += "." }
        return s
    }

    private func cumleIstemi(_ i: Int, _ n: Int, _ plan: Denetci.Plan, onceki: [String], uzunluk: ClosedRange<Int>, sorun: [String]) -> String {
        var s = "Story idea: \(fikir)\n"
        s += onceki.isEmpty ? "This is the first sentence of the story.\n" : "Story so far:\n" + onceki.joined(separator: " ") + "\n"
        s += "\nWrite sentence \(i + 1) of \(n)." + (i == n - 1 ? " It ends the story." : " Continue the story naturally.") + "\nRules:\n"
        s += "- One sentence, \(uzunluk.lowerBound)-\(uzunluk.upperBound) words, simple English.\n"
        if !plan.kelimeler.isEmpty { s += "- It MUST contain these words: " + plan.kelimeler.joined(separator: ", ") + ".\n" }
        if let y = plan.yapi { s += "- It MUST use \(y.kalip).\n" }
        if !sorun.isEmpty { s += "- Your last try was wrong: " + sorun.joined(separator: "; ") + ". Fix it.\n" }
        s += "Answer with the sentence only."
        return s
    }

    /// Bir cümleyi üretir ve denetler; tutmazsa en çok 3 kez yeniden (sıcaklık biraz artarak). En az sorunlu kalır.
    private func cumleUret(_ k: ModelContainer, _ d: Denetci, _ i: Int, _ n: Int, _ plan: Denetci.Plan,
                           onceki: [String], uzunluk: ClosedRange<Int>) async throws -> Taslak {
        var enIyi: Taslak?
        var sorun: [String] = []
        for deneme in 1...4 {
            try Task.checkCancellation()
            let yanit = try await sor(k, cumleIstemi(i, n, plan, onceki: onceki, uzunluk: uzunluk, sorun: sorun),
                                      sicaklik: 0.7 + Float(deneme - 1) * 0.1)
            let c = cumleAyikla(yanit, plan)
            sorun = d.cumleSorunlari(c, plan)
            let wc = Denetci.kelimeler(c).count
            if !uzunluk.contains(wc) && sorun.isEmpty && (wc < uzunluk.lowerBound - 2 || wc > uzunluk.upperBound + 3) {
                sorun.append("\(wc) kelime")
            }
            let t = Taslak(i: i, en: c, konu: plan.konu, sorun: sorun, deneme: deneme)
            if enIyi == nil || sorun.count < enIyi!.sorun.count { enIyi = t }
            if sorun.isEmpty { break }
        }
        return enIyi!
    }

    func ingilizceUret(_ depo: Depo) async {
        asama = .hazirlik
        gunluk = []; cumleler = []; denetim = nil; ozetTr = nil; temaTr = nil
        guard modelVar else { asama = .hata("Model yok — Ayarlar › Model › İçe aktar."); return }
        guard let (b, j) = await briefBul(depo) else {
            asama = .hata("Brief yok. Mac'te: gun.py brief --kurma --ileri --json, sonra oncalisma/telefona_gonder.py"); return
        }
        brief = b
        let d = Denetci(brief: b, bilinen: j)
        denetci = d
        yaz("Gün \(b.gun) · " + b.sahne_konulari.joined(separator: " + "))
        do {
            let k = try await modelYukle()
            let plan = planla(b)
            let n = plan.count
            asama = .ingilizce(0, n)
            fikir = cumleAyikla(try await sor(k, """
                Plan a short everyday story: one place, two or three people, a small problem and how it is solved. \
                It should be able to use these words naturally: \(plan.flatMap(\.kelimeler).uniqued().joined(separator: ", ")). \
                Answer in ONE sentence of at most 30 words.
                """, enCok: 70), Denetci.Plan(kelimeler: [], yapi: nil, konu: nil))
            yaz("Fikir: \(fikir)")
            // Hedef bütçe: 140-170 kelime → cümle başına ~11
            let ort = (b.sinirlar.kelime[0] + b.sinirlar.kelime[1]) / 2 / n
            let uz = max(6, ort - 2)...(ort + 3)
            for i in 0..<n {
                asama = .ingilizce(i, n)
                let t = try await cumleUret(k, d, i, n, plan[i], onceki: cumleler.map(\.en), uzunluk: uz)
                cumleler.append(t)
                yaz("\(i + 1). \(t.en)" + (t.sorun.isEmpty ? "" : "  ⚠ " + t.sorun.joined(separator: "; ")) + (t.deneme > 1 ? "  (\(t.deneme). deneme)" : ""))
            }
            // Bütçe dışına taştıysa en kısa / en uzun cümleler yeniden yazılır
            for _ in 0..<n {
                let wc = cumleler.map { Denetci.kelimeler($0.en).count }.reduce(0, +)
                let kisa = wc < b.sinirlar.kelime[0], uzun = wc > b.sinirlar.kelime[1]
                guard kisa || uzun else { break }
                let sira = cumleler.indices.sorted { Denetci.kelimeler(cumleler[$0].en).count < Denetci.kelimeler(cumleler[$1].en).count }
                guard let i = kisa ? sira.first : sira.last else { break }
                let aralik = kisa ? (ort + 2)...(ort + 6) : max(6, ort - 5)...max(8, ort - 2)
                let t = try await cumleUret(k, d, i, n, plan[i], onceki: Array(cumleler.prefix(i).map(\.en)), uzunluk: aralik)
                if t.sorun.count <= cumleler[i].sorun.count { cumleler[i] = t; yaz("↻ \(i + 1). \(t.en)") } else { break }
            }
            let hikaye = cumleler.map(\.en).joined(separator: " ")
            baslik = (try await sor(k, "Give a 2-4 word English title for this story. Answer with the title only.\n\n\(hikaye)", enCok: 16))
                .split(separator: "\n").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”*# .")) } ?? "Day \(b.gun)"
            ozetEn = try await sor(k, "Summarize this story in two or three short sentences: who, where, what is the problem, how is it solved.\n\n\(hikaye)", enCok: 110)
            temaEn = try await sor(k, "What is the theme of this story? Answer in 4-8 words.\n\n\(hikaye)", enCok: 24)
            denetim = d.denetle(cumleler.map { ($0.en, "-", $0.konu) }, ozet: String(repeating: "x", count: 80))
            yaz("Başlık: \(baslik) · \(denetim?.kelime ?? 0) kelime · K3 %\(Int((denetim?.k3 ?? 0) * 100))")
            asama = .ceviri
        } catch is CancellationError {
            asama = .hata("Durduruldu.")
        } catch {
            asama = .hata(error.localizedDescription)
        }
    }

    // MARK: ② Türkçe (UretEkrani'nin translationTask'ı çağırır)

    /// Çeviri için gidecek metinler: cümleler + özet + tema. clientIdentifier = sıra.
    var ceviriMetinleri: [String] { cumleler.map(\.en) + [ozetEn, temaEn] }

    func ceviriGeldi(_ tr: [String?]) {
        for i in cumleler.indices where i < tr.count { cumleler[i].tr = tr[i] }
        ozetTr = tr.count > cumleler.count ? tr[cumleler.count] : nil
        temaTr = tr.count > cumleler.count + 1 ? tr[cumleler.count + 1] : nil
        if let d = denetci {
            denetim = d.denetle(cumleler.map { ($0.en, $0.tr, $0.konu) }, ozet: ozetTr)
        }
    }

    func ceviriHatasi(_ e: Error) { asama = .hata("Çeviri: \(e.localizedDescription)") }

    // MARK: ③ Anlatım + ses + paket

    func paketle(_ depo: Depo) async {
        guard let b = brief else { return }
        asama = .ses
        do {
            let anl = anlatim(b)
            let k = Paylasim.kapsayici.appendingPathComponent("paket/\(Paket.klasor(b.gun))", isDirectory: true)
            try FileManager.default.createDirectory(at: k, withIntermediateDirectories: true)
            let ses = try await SesYazici().yaz(anl.satirlar, hedef: k.appendingPathComponent("ses.m4a"))
            let metin = cumleler.map { Cumle(i: $0.i, en: $0.en, tr: $0.tr, konu: $0.konu) }
            let k3 = denetci?.k3(anl.satirlar.compactMap(\.t).joined(separator: " ")).oran ?? 0
            if k3 < b.sinirlar.tanidik_oran {     // oncalisma olc ile aynı ölçü: anlatımın tamamı
                denetim?.uyari.append(String(format: "anlatım tanıdık %%%.1f — K3 altında", k3 * 100))
            }
            let tf = DateFormatter(); tf.locale = Locale(identifier: "en_US_POSIX"); tf.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            let sozluk = (b.yeni.filter { etkinYeni.contains($0.w) } + (b.yedek ?? []).filter { etkinYeni.contains($0.w) } + b.tanidik + b.yanki)
            let p = Paket(gun: b.gun, baslik: baslik, surum: "telefon-qwen", uretildi: tf.string(from: Date()), sure_sn: ses.sure,
                          kelime: Denetci.kelimeler(anl.satirlar.compactMap(\.t).joined(separator: " ")).count, tanidik: (k3 * 1000).rounded() / 1000,
                          ses: "ses.m4a", bolumler: ses.bolumler, satirlar: ses.satirlar, metin: metin,
                          ozet: ozetTr ?? ozetEn, tema: temaTr ?? temaEn, sahne_konulari: b.sahne_konulari, sozluk: sozluk)
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try e.encode(p).write(to: k.appendingPathComponent("paket.json"), options: .atomic)
            // Tezgâh'ın taslak biçimi (gun.py derle --kurma --ileri girdisi) + anlatım: Mac görsün diye
            let gun = GunTaslagi(gun: b.gun, faz: b.faz ?? 2, baslik: baslik, tema: temaTr ?? temaEn, ozet: ozetTr ?? ozetEn,
                                 sahne_konulari: b.sahne_konulari,
                                 cumleler: cumleler.map { .init(en: $0.en, tr: $0.tr ?? "", konu: $0.konu) },
                                 yeni: etkinYeni, yanki: b.yanki.map(\.w), tanidik: b.tanidik.map(\.w),
                                 uretim: .init(model: Uretici.modelAdi, uyari: denetim?.uyari ?? []))
            let gv = try e.encode(gun), av = try e.encode(anl)
            try gv.write(to: k.appendingPathComponent("gun.json"), options: .atomic)
            try av.write(to: k.appendingPathComponent("anlatim.json"), options: .atomic)
            let pv = try e.encode(p)
            // Vault: Mac'in dosyalarına dokunmadan paket/gun-NNN/telefon/ altına
            let g = b.gun
            let gitti = await depo.kasa.ile { kok -> Bool in
                let t = kok.appendingPathComponent("paket/\(Paket.klasor(g))/telefon", isDirectory: true)
                try Kasa.koordineliYaz(gv, t.appendingPathComponent("gun.json"))
                try Kasa.koordineliYaz(av, t.appendingPathComponent("anlatim.json"))
                try Kasa.koordineliYaz(pv, t.appendingPathComponent("paket.json"))
                return true
            } ?? false
            yaz(gitti ? "Vault: paket/\(Paket.klasor(g))/telefon/ yazıldı." : "Vault'a yazılamadı — paket yalnız telefonda.")
            depo.yerelYenile()
            depo.gunSec(b.gun)
            asama = .bitti(b.gun)
        } catch {
            asama = .hata("Paket: \(error.localizedDescription)")
        }
    }

    /// build_day.py'nin şablonu — LLM yok. Açıklama: fikir + özet + yapı örnekleri hikâyeden; kelimeler: Oxford tanımı.
    private func anlatim(_ b: Brief) -> Anlatim {
        let birler = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split(separator: " ").map(String.init)
        let onlar = [2: "twenty", 3: "thirty", 4: "forty", 5: "fifty", 6: "sixty", 7: "seventy", 8: "eighty", 9: "ninety"]
        func yazi(_ n: Int) -> String { n < 20 ? birler[n] : (onlar[n / 10] ?? "\(n)") + (n % 10 == 0 ? "" : " " + birler[n % 10]) }
        var L: [Anlatim.Satir] = [.init(bolum: "aciklama")]
        L += [.init(s: "MAYA", t: "Hi, and welcome. This is your preparation for day \(yazi(b.gun)). Tomorrow you will write a short story in English. Today you will hear it first."),
              .init(s: "MAYA", t: "First we will talk about the story. Then you will hear the text. At the end, we will look at the words and the grammar.")]
        L += [.init(s: "SAM", t: "What is the story about?"), .init(s: "MAYA", t: ozetEn.isEmpty ? fikir : ozetEn)]
        L += [.init(s: "SAM", t: "And the grammar?")]
        var ornekler: [String] = []
        for k in b.sahne_konulari {
            for y in Yapi.cikar(k) {
                if let c = cumleler.first(where: { Denetci.yapiVar($0.en, y) && !ornekler.contains($0.en) }) {
                    ornekler.append(c.en)
                    L.append(.init(s: "MAYA", t: "\(y.ad). For example: \(c.en)"))
                }
            }
        }
        L += [.init(s: "MAYA", t: "Ready? Here is the text.")]
        L += [.init(s: "MAYA", t: "Listen to the story two times if you can. The first time, follow the events. The second time, listen to the grammar and the small words.")]
        L += [.init(bolum: "metin"), .init(s: "SAM", t: baslik + ".")]
        L += cumleler.map { .init(s: "SAM", t: $0.en, cumle: $0.i) }
        let yeni = (b.yeni + (b.yedek ?? [])).filter { etkinYeni.contains($0.w) }
        L += [.init(bolum: "kelimeler"), .init(s: "MAYA", t: "Now the new words. There are \(yazi(yeni.count)).")]
        for w in yeni {
            var t = "\(w.w.capitalized)."
            if let tn = w.tanim, !tn.isEmpty { t += " \(w.w.capitalized) means: \(tn)." }
            if let c = cumleler.first(where: { Denetci.gecis($0.en, w.w) > 0 }) { t += " In the story: \(c.en)" }
            L.append(.init(s: "MAYA", t: t))
        }
        let eski = b.yanki + b.tanidik
        if !eski.isEmpty {
            L.append(.init(s: "SAM", t: "And the old words?"))
            L.append(.init(s: "MAYA", t: "Some come back today. " + eski.map { w in
                "\(w.w.capitalized)" + ((w.tanim ?? "").isEmpty ? "." : ": \(w.tanim!).")
            }.joined(separator: " ")))
        }
        L += [.init(s: "SAM", t: "Any advice for tomorrow?"), .init(s: "MAYA", t: "Yes. Write the story from memory, sentence by sentence. If you forget a word, try another way to say it. That is also good practice."), .init(s: "SAM", t: "What if the sentences are too fast?"), .init(s: "MAYA", t: "Then stop and go back to one sentence. You can listen to it again and again. Take your time.")]
        L += [.init(s: "MAYA", t: "Here is how to use this lesson. Listen to it three times. Listen once in the morning, once in the evening, and once before you write. The first time, think about the story. The second time, listen to the small words, like a, the, in and on. The third time, say the sentences after me in a low voice. Do not be afraid of mistakes. Everybody makes mistakes when they learn.")]
        L += [.init(s: "MAYA", t: "That's all for today. Listen once more if you like, and read the text on your screen. Tomorrow, you will write it yourself. See you then.")]
        return Anlatim(gun: b.gun, baslik: baslik, kaynak: "Cümle Tezgâhı Gün \(b.gun) · kurma · telefon (Qwen)",
                       sesler: SesYazici.sesAdlari, hiz: SesYazici.hiz, satirlar: L)
    }
}

// MARK: - Dosya biçimleri

/// anlatim.json (Yankı satır biçimi)
struct Anlatim: Codable {
    struct Satir: Codable {
        var bolum: String?
        var s: String?
        var t: String?
        var cumle: Int?
        init(bolum: String) { self.bolum = bolum }
        init(s: String, t: String, cumle: Int? = nil) { self.s = s; self.t = t; self.cumle = cumle }
    }
    var gun: Int
    var baslik: String
    var kaynak: String
    var sesler: [String: String]
    var hiz: Double
    var satirlar: [Satir]
}

/// gun.json — Tezgâh taslağı (gun.py derle girdisi) + üretim notu.
struct GunTaslagi: Codable {
    struct C: Codable { var en: String; var tr: String; var konu: String? }
    struct Uretim: Codable { var model: String; var uyari: [String] }
    var gun: Int
    var mod = "kurma"
    var faz: Int
    var baslik: String
    var tema: String
    var ozet: String
    var sahne_konulari: [String]
    var cumleler: [C]
    var yeni: [String]
    var yanki: [String]
    var tanidik: [String]
    var uretim: Uretim
}

// MARK: - Tokenizer (swift-transformers → MLXLMCommon)

struct TokenizerYukleyici: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        Kopru(try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }

    struct Kopru: MLXLMCommon.Tokenizer {
        let ust: any Tokenizers.Tokenizer
        init(_ u: any Tokenizers.Tokenizer) { ust = u }
        func encode(text: String, addSpecialTokens: Bool) -> [Int] { ust.encode(text: text, addSpecialTokens: addSpecialTokens) }
        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { ust.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens) }
        func convertTokenToId(_ token: String) -> Int? { ust.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { ust.convertIdToToken(id) }
        var bosToken: String? { ust.bosToken }
        var eosToken: String? { ust.eosToken }
        var unknownToken: String? { ust.unknownToken }
        func applyChatTemplate(messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
                               additionalContext: [String: any Sendable]?) throws -> [Int] {
            do { return try ust.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext) }
            catch Tokenizers.TokenizerError.missingChatTemplate { throw MLXLMCommon.TokenizerError.missingChatTemplate }
        }
    }
}

// MARK: - Ses (AVSpeechSynthesizer → ses.m4a + satır zamanları)

@MainActor
final class SesYazici {
    static let hiz = 0.9
    static let oran: Double = 22_050
    // oncalisma.py ile aynı nefesler
    static let araSatir = 0.35, araBolum = 1.0, araCumle = 0.8

    private let sentez = AVSpeechSynthesizer()
    private let bicim = AVAudioFormat(standardFormatWithSampleRate: SesYazici.oran, channels: 1)!

    static var sesAdlari: [String: String] { ["MAYA": sesSec(.female).identifier, "SAM": sesSec(.male).identifier] }

    /// En iyi kaliteli en-US ses (gelişmiş/premium indirildiyse o).
    static func sesSec(_ cins: AVSpeechSynthesisVoiceGender) -> AVSpeechSynthesisVoice {
        let hepsi = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        let aday = hepsi.filter { $0.gender == cins }.sorted { $0.quality.rawValue > $1.quality.rawValue }
        return aday.first ?? hepsi.first ?? AVSpeechSynthesisVoice(language: "en-US")!
    }

    struct Sonuc { var sure: Double; var bolumler: [Bolum]; var satirlar: [Satir] }

    func yaz(_ satirlar: [Anlatim.Satir], hedef: URL) async throws -> Sonuc {
        try? FileManager.default.removeItem(at: hedef)
        let ayar: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: SesYazici.oran,
                                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
        let dosya = try AVAudioFile(forWriting: hedef, settings: ayar, commonFormat: .pcmFormatFloat32, interleaved: false)
        let sesler = ["MAYA": SesYazici.sesSec(.female), "SAM": SesYazici.sesSec(.male)]
        var n: AVAudioFramePosition = 0
        var bolumler: [Bolum] = [], cikti: [Satir] = []
        var bolum: String?, onceki: String?
        func sn(_ f: AVAudioFramePosition) -> Double { (Double(f) / SesYazici.oran * 100).rounded() / 100 }
        func ekle(_ b: AVAudioPCMBuffer) throws { try dosya.write(from: b); n += AVAudioFramePosition(b.frameLength) }

        for x in satirlar {
            if let ad = x.bolum {
                if n > 0 { try ekle(sus(SesYazici.araBolum)); try ekle(zil()); try ekle(sus(SesYazici.araBolum)) }
                if !bolumler.isEmpty { bolumler[bolumler.count - 1].bitis = sn(n) }
                bolumler.append(Bolum(ad: ad, baslangic: sn(n), bitis: sn(n)))
                bolum = ad; onceki = nil
                continue
            }
            guard let t = x.t, let s = x.s else { continue }
            if onceki != nil { try ekle(sus(bolum == "metin" ? SesYazici.araCumle : SesYazici.araSatir)) }
            let bas = n
            let u = AVSpeechUtterance(string: t)
            u.voice = sesler[s]
            u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(SesYazici.hiz)
            for b in await parcalar(u) { try ekle(b) }
            cikti.append(Satir(bolum: bolum, s: s, t: t, baslangic: sn(bas), bitis: sn(n), cumle: x.cumle))
            onceki = s
        }
        if !bolumler.isEmpty { bolumler[bolumler.count - 1].bitis = sn(n) }
        return Sonuc(sure: (Double(n) / SesYazici.oran * 10).rounded() / 10, bolumler: bolumler, satirlar: cikti)
    }

    /// Bir söyleyişin sesi, ortak biçime (22 050 Hz, tek kanal, Float32) çevrilmiş.
    private func parcalar(_ u: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        let hedef = bicim
        return await withCheckedContinuation { (dev: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
            var liste: [AVAudioPCMBuffer] = []
            var bitti = false
            sentez.write(u) { tampon in
                guard !bitti else { return }
                guard let p = tampon as? AVAudioPCMBuffer, p.frameLength > 0 else {
                    bitti = true; dev.resume(returning: liste); return
                }
                if let c = SesYazici.cevir(p, hedef) { liste.append(c) }
            }
        }
    }

    nonisolated private static func cevir(_ p: AVAudioPCMBuffer, _ hedef: AVAudioFormat) -> AVAudioPCMBuffer? {
        if p.format == hedef { return p }
        guard let c = AVAudioConverter(from: p.format, to: hedef) else { return nil }
        let kap = AVAudioFrameCount(Double(p.frameLength) * hedef.sampleRate / p.format.sampleRate) + 1024
        guard let o = AVAudioPCMBuffer(pcmFormat: hedef, frameCapacity: kap) else { return nil }
        var verildi = false
        var hata: NSError?
        c.convert(to: o, error: &hata) { _, durum in
            if verildi { durum.pointee = .endOfStream; return nil }
            verildi = true; durum.pointee = .haveData; return p
        }
        return hata == nil ? o : nil
    }

    private func sus(_ saniye: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(saniye * SesYazici.oran)
        let b = AVAudioPCMBuffer(pcmFormat: bicim, frameCapacity: n)!
        b.frameLength = n
        return b    // sıfırlarla dolu
    }

    /// yanki.zil: iki notalı yumuşak geçiş sesi.
    private func zil(sure: Double = 0.5) -> AVAudioPCMBuffer {
        let yarim = Int(sure / 2 * SesYazici.oran)
        let b = AVAudioPCMBuffer(pcmFormat: bicim, frameCapacity: AVAudioFrameCount(yarim * 2))!
        b.frameLength = AVAudioFrameCount(yarim * 2)
        let v = b.floatChannelData![0]
        for (k, hz) in [660.0, 880.0].enumerated() {
            for i in 0..<yarim {
                let t = Double(i) / SesYazici.oran
                v[k * yarim + i] = Float(sin(2 * .pi * hz * t) * exp(-t * 9) * 0.18)
            }
        }
        return b
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var g = Set<Element>(); return filter { g.insert($0).inserted } }
}
