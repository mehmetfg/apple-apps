// Geçmiş: eski Arşiv + İstatistik tek görünümde. Solda günler, sağda seçilen gün; seçim yokken genel bakış
// (eğri, takvim, hata türleri, yapı skorları). Veri arşivden (sabah görevi) + henüz işlenmemiş yerel günlerden.
import SwiftUI
import Charts

struct GecmisGorunum: View {
    @EnvironmentObject var t: Tezgah
    @State private var secili: String?
    @State private var ara = ""

    var body: some View {
        let gunler = t.gecmis()
        HSplitView {
            VStack(spacing: 0) {
                TextField("ara: başlık, cümle, Türkçe…", text: $ara).textFieldStyle(.roundedBorder).padding(10)
                List(selection: $secili) {
                    Label("Genel bakış", systemImage: "chart.xyaxis.line").tag(String?.none)
                    ForEach(gunler.filter(eslesir)) { g in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Gün \(g.gun)").font(.caption.weight(.semibold)).foregroundStyle(Renk.vurgu)
                                Text(Gun.trKisa(g.tarih)).font(.caption).foregroundStyle(.secondary)
                                if g.yerel { Text("· yerel").font(.caption).foregroundStyle(.tertiary).help("sicile henüz işlenmedi") }
                            }
                            Text(g.baslik.isEmpty ? "—" : g.baslik).font(.body.weight(.medium)).lineLimit(1)
                            HStack(spacing: 10) {
                                olcu(g.tutma, "cümle"); olcu(g.paragrafYuzde, "paragraf"); olcu(g.recallYuzde, "test")
                            }
                        }
                        .padding(.vertical, 3)
                        .tag(Optional(g.id))
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 230, idealWidth: 270, maxWidth: 340)

            Group {
                if let s = secili, let g = gunler.first(where: { $0.id == s }) { GunDetay(g: g) }
                else { GenelBakis(gunler: gunler) }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func eslesir(_ g: ArsivGun) -> Bool {
        let q = ara.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        let m = ([g.baslik, g.tema] + g.cumleler.flatMap { [$0.en, $0.tr] } + g.sahne).joined(separator: " ").lowercased()
        return m.contains(q)
    }
    func olcu(_ v: Int?, _ a: String) -> some View {
        Text("\(v.map { "%\($0)" } ?? "—") \(a)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
    }
}

struct GenelBakis: View {
    var gunler: [ArsivGun]
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let sirali = gunler.reversed() as [ArsivGun]
        let sure = gunler.compactMap(\.sureDk)
        Sutun(genislik: 900) {
            Text("Genel bakış").font(.largeTitle.bold())
            HStack(spacing: 10) {
                Kutu(k: "çalışılan gün", v: "\(gunler.count)")
                Kutu(k: "günlük seri", v: "\(t.seri(gunler))")
                Kutu(k: "toplam süre", v: "\(sure.reduce(0, +)) dk")
                Kutu(k: "cümle turu ort.", v: ort(gunler.compactMap(\.tutma)))
                Kutu(k: "paragraf ort.", v: ort(gunler.compactMap(\.paragrafYuzde)))
                Kutu(k: "hatırlama ort.", v: ort(gunler.compactMap(\.recallYuzde)))
            }
            Kart {
                Baslik(metin: "Tutturma eğrisi", alt: "gün gün · %")
                Chart {
                    ForEach(sirali) { g in
                        if let v = g.tutma { LineMark(x: .value("Gün", g.gun), y: .value("%", v), series: .value("Seri", "cümle turu")).foregroundStyle(by: .value("Seri", "cümle turu"))
                            PointMark(x: .value("Gün", g.gun), y: .value("%", v)).foregroundStyle(by: .value("Seri", "cümle turu")) }
                        if let v = g.paragrafYuzde { LineMark(x: .value("Gün", g.gun), y: .value("%", v), series: .value("Seri", "paragraf")).foregroundStyle(by: .value("Seri", "paragraf")) }
                        if let v = g.recallYuzde { LineMark(x: .value("Gün", g.gun), y: .value("%", v), series: .value("Seri", "hatırlama")).foregroundStyle(by: .value("Seri", "hatırlama")) }
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 220)
                // İpucu payı: bakmadan yazılan cümleler (yalnız v6+ günler)
                let ipuclu = sirali.filter { $0.ipucu != nil }
                if !ipuclu.isEmpty {
                    Baslik(metin: "Tam cümleye bakılan", alt: "cümle sayısı · azalması üretimin arttığını gösterir").padding(.top, 8)
                    Chart(ipuclu) { g in
                        BarMark(x: .value("Gün", g.gun), y: .value("Bakılan", g.cumleler.filter { $0.baktim || $0.ipucu >= 3 }.count))
                            .foregroundStyle(Renk.kirmizi.opacity(0.7))
                    }
                    .frame(height: 110)
                }
            }
            IkiliSira {
                Kart {
                    Baslik(metin: "Hata türleri", alt: "bütün günler · toplam")
                    HtCubuk(ht: gunler.reduce(into: [String: Int]()) { a, g in for (k, v) in g.hataTurleri { a[k, default: 0] += v } })
                }
            } b: {
                Kart {
                    Baslik(metin: "Yapı skorları", alt: "%90 altı turuncu — döngünün tekrar yuvaları önce bunlara gider")
                    let ys = t.arsiv.kurmaYapilar.compactMap { k, v -> (String, Int)? in
                        let s = v.compactMap(\.skor); return s.isEmpty ? nil : (k, Int((Double(s.reduce(0, +)) / Double(s.count)).rounded()))
                    }.sorted { $0.1 < $1.1 }
                    ForEach(ys, id: \.0) { k, v in
                        HStack(spacing: 8) {
                            Text(Gramer.kisa(k)).font(.callout).frame(width: 170, alignment: .leading).lineLimit(1).help(k)
                            GeometryReader { g in Capsule().fill((v < 90 ? Renk.sari : Renk.vurgu).gradient).frame(width: g.size.width * CGFloat(v) / 100) }.frame(height: 8)
                            Text("%\(v)").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
            Kart {
                Baslik(metin: "Çalışma takvimi", alt: "son 12 hafta · koyuluk = dakika")
                Takvim(gunler: gunler)
            }
        }
    }
    func ort(_ a: [Int]) -> String { a.isEmpty ? "—" : "%\(Int((Double(a.reduce(0, +)) / Double(a.count)).rounded()))" }
}

struct Takvim: View {
    var gunler: [ArsivGun]
    var body: some View {
        let dk = gunler.reduce(into: [String: Int]()) { a, g in a[g.tarih, default: 0] += g.sureDk ?? 15 }
        let f = Gun.isoGun
        let cal = Calendar(identifier: .iso8601)
        let bugun = Date()
        let bas = cal.date(byAdding: .day, value: -(7 * 12 - 1), to: cal.dateInterval(of: .weekOfYear, for: bugun)!.start)!
        let gun = (0..<(7 * 13)).compactMap { cal.date(byAdding: .day, value: $0, to: bas) }.filter { $0 <= bugun }
        LazyHGrid(rows: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 7), spacing: 3) {
            ForEach(gun, id: \.self) { d in
                let v = dk[f.string(from: d)] ?? 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(v > 0 ? Renk.vurgu.opacity(min(1, 0.25 + Double(v) * 0.014)) : Color.secondary.opacity(0.1))
                    .frame(width: 14, height: 14)
                    .help(Gun.trKisa(f.string(from: d)) + (v > 0 ? " · \(v) dk" : " · çalışılmadı"))
            }
        }
        .frame(height: 7 * 17)
    }
}

struct GunDetay: View {
    var g: ArsivGun
    @EnvironmentObject var t: Tezgah
    @State private var sekme = "yazim"
    @State private var tr = false

    var body: some View {
        Sutun(genislik: 860) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GÜN \(g.gun) · \(Gun.trKisa(g.tarih).uppercased()) · \(g.mod.uppercased())" + (g.yerel ? " · SİCİLE HENÜZ İŞLENMEDİ" : ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(g.baslik.isEmpty ? "—" : g.baslik).font(.largeTitle.bold())
                    Text(g.tema).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Bu günü yeniden çalış") { t.yenidenCalis(g) }.buttonStyle(.borderedProminent)
            }
            HStack(spacing: 10) {
                Kutu(k: "cümle turu", v: g.tutma.map { "%\($0)" } ?? "—")
                Kutu(k: "paragraf", v: g.paragrafYuzde.map { "%\($0)" } ?? "—")
                Kutu(k: "hatırlama", v: g.recallYuzde.map { "%\($0)" } ?? "—")
                Kutu(k: "süre", v: g.sureDk.map { "\($0) dk" } ?? "—")
                if let ip = g.ipucu { Kutu(k: "ipuçlu cümle", v: "\(ip.filter { $0.key != "0" }.values.reduce(0, +))") }
                else { Kutu(k: "bakılan cümle", v: "\(g.cumleler.filter(\.baktim).count)") }
            }
            Akis {
                ForEach(g.sahne, id: \.self) { Cip(metin: $0, renk: Renk.vurgu) }
                ForEach(g.hatirlatma, id: \.self) { Cip(metin: $0, renk: .teal) }
            }
            Picker("", selection: $sekme) {
                Text("Metin").tag("metin"); Text("Yazdıkların").tag("yazim"); Text("Paragraf").tag("paragraf")
                Text("Test").tag("test"); Text("Hata ve kelime").tag("hata")
            }
            .pickerStyle(.segmented).labelsHidden()
            switch sekme {
            case "metin":
                HStack {
                    Toggle("Türkçeyi göster", isOn: $tr).toggleStyle(.checkbox)
                    Button { t.ses.zincir(g.cumleler.map(\.en)) } label: { Label("paragrafı dinle", systemImage: "play.fill") }
                }
                if !g.ozet.isEmpty { Kart { Baslik(metin: "Mesele ne?"); Text(g.ozet) } }
                ForEach(g.cumleler, id: \.no) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.en).font(.serif(18)).onTapGesture { t.ses.soyle(c.en) }
                        if tr { Text(c.tr).foregroundStyle(.secondary) }
                    }
                }
            case "yazim":
                ForEach(g.cumleler, id: \.no) { c in
                    Kart(dolgu: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(c.no)").font(.headline).foregroundStyle(.tertiary)
                            Text(c.tr).foregroundStyle(.secondary)
                            Spacer()
                            Button { t.ses.soyle(c.en) } label: { Image(systemName: "speaker.wave.2") }.buttonStyle(.borderless)
                        }
                        if c.yazim.isEmpty { Text("yazılmadı").foregroundStyle(.tertiary) } else { FarkGorunum(fark: Metin.fark(c.en, c.yazim), boyut: 16) }
                        HStack {
                            if let y = c.yuzde { Cip(metin: "%\(y)", renk: y >= 95 ? Renk.yesil : y >= 80 ? Renk.vurgu : Renk.kirmizi) }
                            if !c.konu.isEmpty { Cip(metin: c.konu) }
                            if c.baktim { Cip(metin: "bakıldı", renk: Renk.kirmizi) } else if c.ipucu > 0 { Cip(metin: "ipucu \(c.ipucu)", renk: Renk.sari) }
                        }
                        HtSatir(ht: c.ht)
                    }
                }
            case "paragraf":
                if let m = g.paragrafMetin, !m.isEmpty {
                    let f = Metin.fark(g.cumleler.map(\.en).joined(separator: " "), m)
                    Kart { HStack { Spacer(); SkorHalka(yuzde: f.yuzde) }; FarkGorunum(fark: f, boyut: 16) }
                } else { Text("paragraf turu yok").foregroundStyle(.secondary) }
            case "test":
                if g.sorular.isEmpty { Text("test yok").foregroundStyle(.secondary) }
                ForEach(Array(g.sorular.enumerated()), id: \.offset) { _, s in
                    let h = s.sonuc ?? "yok"
                    let p = s.bosluk.components(separatedBy: "____")
                    HStack(alignment: .firstTextBaseline) {
                        Text(h == "tam" ? "✓" : h == "kismi" ? "~" : "✗").foregroundStyle(h == "tam" ? Renk.yesil : h == "kismi" ? Renk.sari : Renk.kirmizi)
                        VStack(alignment: .leading) {
                            (Text(p.first ?? "") + Text(s.cevap).bold() + Text(p.dropFirst().joined(separator: "____"))).font(.serif(16))
                            Text(s.tip + (s.verilen.filter { !$0.isEmpty }.isEmpty ? "" : " · yazdığın: " + s.verilen.filter { !$0.isEmpty }.joined(separator: " → ")))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            default:
                HStack(alignment: .top, spacing: 14) {
                    Kart { Baslik(metin: "Hata türleri"); HtCubuk(ht: g.hataTurleri) }
                    Kart {
                        Baslik(metin: "Kelimeler", alt: "kırmızı kaçırılan · mavi yeni · yeşil tanıdık")
                        Akis {
                            ForEach(g.zor, id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.kirmizi) }
                            ForEach(g.yeni, id: \.self) { KelimeDugmesi(kelime: $0, renk: .blue) }
                            ForEach(g.tanidik, id: \.self) { KelimeDugmesi(kelime: $0, renk: Renk.yesil) }
                        }
                    }
                }
                if !g.kendi.isEmpty {
                    Kart {
                        Baslik(metin: "Kendi cümlelerin")
                        ForEach(Array(g.kendi.enumerated()), id: \.offset) { _, k in HStack { Text(k.metin).font(.serif(16)); Cip(metin: k.konu) } }
                    }
                }
            }
        }
        .id(g.id)
    }
}
