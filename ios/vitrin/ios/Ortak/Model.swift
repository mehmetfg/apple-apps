// Vitrin'in iki tür verisi:
//  1) Öğrenme içeriği — Mac'teki veri/vitrin.py üretir (vitrin.json); uygulama ve widget yalnız okur.
//  2) Tasarımlar — duvar kâğıtları ve widget tasarımları; kullanıcı uygulamada kurar, App Group'ta durur.
import SwiftUI

// MARK: - Öğrenme içeriği (vitrin.json)

struct Kelime: Codable, Hashable {
    var w: String
    var ipa: String
    var tr: String
    var trTam: String
    var d: String
    var x: String
    var c: String
    var p: String
    var au: String
}

struct Alinti: Codable, Hashable {
    var metin: String
    var kaynak: String
    var tur: String
}

struct Kavram: Codable, Hashable {
    var terim: String
    var tanim: String
    var kaynak: String
}

struct OdakSatir: Codable, Hashable {
    var ad: String
    var kademe: String
    var bugun: String
}

struct BirYoneDilim: Codable, Hashable {
    var dilim: String?
    var dakika: Int?
    var baslik: String?
}

struct BirYone: Codable, Hashable {
    var gun: Int?
    var dilimler: [BirYoneDilim]
}

struct Odak: Codable, Hashable {
    var ana: String
    var destek: [String]
    var hedef: String
    var sonraki_olcum: String
    var gun_sayisi: Int?
    var satirlar: [OdakSatir]
    var biryone: BirYone?
}

struct VitrinVeri: Codable {
    var surum: Int
    var uretildi: String
    var bugun: String
    var kelimeler: [Kelime]
    var alintilar: [Alinti]
    var kavramlar: [Kavram]
    var odak: Odak

    static let bos = VitrinVeri(surum: 0, uretildi: "", bugun: "", kelimeler: [], alintilar: [], kavramlar: [],
                                odak: Odak(ana: "", destek: [], hedef: "", sonraki_olcum: "", gun_sayisi: nil, satirlar: [], biryone: nil))
}

// MARK: - Tasarım parçaları

enum ZeminTuru: String, Codable, CaseIterable, Identifiable {
    case duz, gradyan, mesh, desen, foto
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .duz: "Düz"
        case .gradyan: "Gradyan"
        case .mesh: "Mesh"
        case .desen: "Desen"
        case .foto: "Fotoğraf"
        }
    }
    var simge: String {
        switch self {
        case .duz: "square.fill"
        case .gradyan: "square.bottomhalf.filled"
        case .mesh: "circle.hexagongrid.fill"
        case .desen: "circle.grid.3x3.fill"
        case .foto: "photo"
        }
    }
}

enum DesenTuru: String, Codable, CaseIterable, Identifiable {
    case noktalar, cizgiler, izgara, dalga, topografya, yildizlar, bauhaus
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .noktalar: "Noktalar"
        case .cizgiler: "Çizgiler"
        case .izgara: "Izgara"
        case .dalga: "Dalga"
        case .topografya: "Topografya"
        case .yildizlar: "Yıldızlar"
        case .bauhaus: "Bauhaus"
        }
    }
}

struct Zemin: Codable, Hashable {
    var tur: ZeminTuru = .mesh
    var renkler: [String] = Palet.hepsi[0].renkler
    var aci: Double = 135
    var tohum: Int = 0
    var desen: DesenTuru = .noktalar
    var foto: String? = nil
    var bulanik: Double = 0      // 0…40
    var karartma: Double = 0     // -0.6 (aydınlat) … 0.7 (karart)
    var tane: Double = 0         // 0…1
    var vinyet: Double = 0       // 0…1

    func renk(_ i: Int) -> Color { Color(hex: renkler.isEmpty ? "#000000" : renkler[i % renkler.count]) }
}

enum IcerikTuru: String, Codable, CaseIterable, Identifiable {
    case yok, kelime, alinti, kavram, odak, metin, saat, tarih, geriSayim, ilerleme
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .yok: "Yalnız görsel"
        case .kelime: "Kelime"
        case .alinti: "Alıntı"
        case .kavram: "Kavram"
        case .odak: "Günün işi"
        case .metin: "Kendi metnin"
        case .saat: "Saat"
        case .tarih: "Takvim"
        case .geriSayim: "Geri sayım"
        case .ilerleme: "Ölçüme kalan"
        }
    }
    var simge: String {
        switch self {
        case .yok: "photo.artframe"
        case .kelime: "textformat.abc"
        case .alinti: "quote.opening"
        case .kavram: "lightbulb"
        case .odak: "scope"
        case .metin: "character.cursor.ibeam"
        case .saat: "clock"
        case .tarih: "calendar"
        case .geriSayim: "hourglass"
        case .ilerleme: "chart.bar.fill"
        }
    }
    static let duvarIcin: [IcerikTuru] = [.yok, .kelime, .alinti, .kavram, .odak, .metin]
    static let widgetIcin: [IcerikTuru] = [.kelime, .alinti, .kavram, .odak, .saat, .tarih, .geriSayim, .ilerleme, .metin, .yok]
    var donen: Bool { [.kelime, .alinti, .kavram].contains(self) }
}

enum YaziAilesi: String, Codable, CaseIterable, Identifiable {
    case sistem, serif, yuvarlak, mono, ince, siyah
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .sistem: "Sistem"
        case .serif: "Serif"
        case .yuvarlak: "Yuvarlak"
        case .mono: "Mono"
        case .ince: "İnce"
        case .siyah: "Kalın"
        }
    }
    func font(_ boy: CGFloat, ikincil: Bool = false) -> Font {
        switch self {
        case .sistem: .system(size: boy, weight: ikincil ? .regular : .semibold)
        case .serif: .system(size: boy, weight: ikincil ? .regular : .medium, design: .serif)
        case .yuvarlak: .system(size: boy, weight: ikincil ? .medium : .bold, design: .rounded)
        case .mono: .system(size: boy * 0.9, weight: ikincil ? .regular : .medium, design: .monospaced)
        case .ince: .system(size: boy, weight: ikincil ? .light : .ultraLight)
        case .siyah: .system(size: boy, weight: ikincil ? .semibold : .black).width(.condensed)
        }
    }
}

enum Hiza: String, Codable, CaseIterable, Identifiable {
    case bas, orta, son
    var id: String { rawValue }
    var yatay: HorizontalAlignment { self == .bas ? .leading : self == .orta ? .center : .trailing }
    var metin: TextAlignment { self == .bas ? .leading : self == .orta ? .center : .trailing }
    var cerceve: Alignment { self == .bas ? .leading : self == .orta ? .center : .trailing }
    var simge: String { self == .bas ? "text.alignleft" : self == .orta ? "text.aligncenter" : "text.alignright" }
}

struct YaziStili: Codable, Hashable {
    var aile: YaziAilesi = .serif
    var renk: String = "#F5EFE6"
    var vurgu: String = "#E9B872"
    var olcek: Double = 1
    var hiza: Hiza = .orta
    var golge: Bool = true
    var buyukHarf: Bool = false
}

enum KartStili: String, Codable, CaseIterable, Identifiable {
    case yok, cam, duz, cizgi
    var id: String { rawValue }
    var ad: String {
        switch self {
        case .yok: "Çıplak"
        case .cam: "Cam"
        case .duz: "Dolgu"
        case .cizgi: "Çerçeve"
        }
    }
}

enum Hedef: String, Codable, CaseIterable, Identifiable {
    case kilit, ana
    var id: String { rawValue }
    var ad: String { self == .kilit ? "Kilit ekranı" : "Ana ekran" }
}

// MARK: - Duvar kâğıdı tasarımı

struct Duvar: Codable, Identifiable, Hashable {
    var id = UUID()
    var ad: String
    var zemin = Zemin()
    var icerik: IcerikTuru = .kelime
    var metin: String = ""
    var yazi = YaziStili()
    var kart: KartStili = .cam
    var konum: Double = 0.64        // içeriğin dikey merkezi (0 üst … 1 alt)
    var hedef: Hedef = .kilit
    var derinlik: Bool = false      // fotoğrafta metni öznenin arkasına koy
    var guncellendi = Date()
}

// MARK: - Widget tasarımı

struct WidgetTasarim: Codable, Identifiable, Hashable {
    var id = UUID()
    var ad: String
    var zemin = Zemin()
    var icerik: IcerikTuru = .kelime
    var metin: String = ""
    var hedefAd: String = "Ölçüm günü"
    var hedefTarih: Date = Calendar.current.date(byAdding: .day, value: 20, to: .now) ?? .now
    var yazi = YaziStili()
    var ikincil: Bool = true        // anlam / kaynak satırı
    var dugmeler: Bool = true       // çevir · sonraki · dinle
    var gizliBasla: Bool = false    // kelimede anlam önce kapalı (önce hatırla)
    var dongu: Int = 60             // dakika; içerik bu aralıkla değişir
    var guncellendi = Date()
}

// MARK: - Kayıt

struct Tasarimlar: Codable {
    var duvarlar: [Duvar] = []
    var widgetlar: [WidgetTasarim] = []
    var gunlukListe: [UUID] = []     // Kestirmeler otomasyonu her gün sıradakini üretir
    var bilinen: [String] = []       // "biliyorum" denen kelimeler bir daha çıkmaz
}

// MARK: - Renk

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hex: String {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = { (x: CGFloat) in Int((max(0, min(1, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", k(r), k(g), k(b))
    }
}

enum RenkHesap {
    /// 0 (siyah) … 1 (beyaz) — göreli parlaklık
    static func parlaklik(_ hex: String) -> Double {
        let u = UIColor(Color(hex: hex))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    /// Yazının altındaki zeminin parlaklığı: desen/düz zeminde ve dolgu kartta ilk renk, mesh/gradyanda ilk üçün ortalaması
    static func zeminParlaklik(_ renkler: [String], tur: ZeminTuru, kart: KartStili = .yok) -> Double {
        guard !renkler.isEmpty else { return 0 }
        if tur == .desen || tur == .duz || kart == .duz { return parlaklik(renkler[0]) }
        return renkler.prefix(3).map(parlaklik).reduce(0, +) / Double(min(3, renkler.count))
    }

    /// Zemine göre okunur yazı rengi: koyu zeminde paletin en açığı, açık zeminde en koyusu
    static func yaziRengi(_ renkler: [String], tur: ZeminTuru = .mesh, kart: KartStili = .yok) -> String {
        guard !renkler.isEmpty else { return "#FFFFFF" }
        let sirali = renkler.sorted { parlaklik($0) < parlaklik($1) }
        if zeminParlaklik(renkler, tur: tur, kart: kart) < 0.5 { return parlaklik(sirali.last!) > 0.75 ? sirali.last! : "#F7F3EC" }
        return parlaklik(sirali.first!) < 0.25 ? sirali.first! : "#1C1B19"
    }

    /// Vurgu: yazı renginden farklı, zeminden en çok ayrışan (doygunluk da sayılır) palet rengi
    static func vurgu(_ renkler: [String], yazi: String, tur: ZeminTuru = .mesh, kart: KartStili = .yok) -> String {
        let z = zeminParlaklik(renkler, tur: tur, kart: kart)
        let adaylar = renkler.filter { $0.uppercased() != yazi.uppercased() }
        func puan(_ h: String) -> Double {
            let u = UIColor(Color(hex: h)); var hu: CGFloat = 0, sa: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            u.getHue(&hu, saturation: &sa, brightness: &br, alpha: &a)
            return abs(parlaklik(h) - z) + 0.35 * Double(sa)
        }
        guard let v = adaylar.max(by: { puan($0) < puan($1) }) else { return yazi }
        // Zeminle yetersiz ayrışıyorsa tonunu koruyup parlaklığını zeminin karşı ucuna çek
        if abs(parlaklik(v) - z) >= 0.35 { return v }
        let u = UIColor(Color(hex: v)); var hu: CGFloat = 0, sa: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        u.getHue(&hu, saturation: &sa, brightness: &br, alpha: &a)
        let yeni = z < 0.5 ? UIColor(hue: hu, saturation: min(sa, 0.55), brightness: 0.92, alpha: 1)
                           : UIColor(hue: hu, saturation: max(sa, 0.5), brightness: 0.42, alpha: 1)
        return Color(uiColor: yeni).hex
    }
}
