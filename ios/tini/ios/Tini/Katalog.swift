import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Kitaplıktaki bir parça. Kimliği Belgeler klasörüne göre göreli yoludur (alt klasörler albüm olarak korunur).
struct Parca: Identifiable, Hashable, Codable {
    let yol: String
    var baslik: String
    var sanatci: String
    var album: String
    var albumSanatcisi: String
    var parcaNo: Int
    var diskNo: Int
    var yil: Int
    var sure: Double
    var bicim: String          // "FLAC 24/96", "MP3 320"
    var kayipsiz: Bool
    var yuksekCozunurluk: Bool
    var replayGain: Float?     // dB
    var kapak: String?         // önbellekteki dosya adı
    var boyut: Int
    var degisim: Double

    var id: String { yol }
    var url: URL { Depo.klasor.appendingPathComponent(yol) }
    var klasor: String { (yol as NSString).deletingLastPathComponent }
    var albumAnahtari: String { "\(albumSanatcisi.lowercased())|\(album.lowercased())" }

    static func == (a: Parca, b: Parca) -> Bool { a.yol == b.yol }
    func hash(into h: inout Hasher) { h.combine(yol) }

    var kapakURL: URL? { kapak.map { Katalog.kapakKlasoru.appendingPathComponent($0) } }
    var kapakResmi: UIImage? { kapakURL.flatMap { UIImage(contentsOfFile: $0.path) } }
}

struct Album: Identifiable, Hashable {
    let id: String
    let ad: String
    let sanatci: String
    let yil: Int
    let parcalar: [Parca]
    var kapak: Parca? { parcalar.first { $0.kapak != nil } }
    var bicim: String { parcalar.first?.bicim ?? "" }
    var sure: Double { parcalar.reduce(0) { $0 + $1.sure } }
}

enum Katalog {
    static var kapakKlasoru: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("kapak", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static var onbellekURL: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.appendingPathComponent("katalog.json")
    }

    static func onbellek() -> [Parca] {
        guard let v = try? Data(contentsOf: onbellekURL) else { return [] }
        return (try? JSONDecoder().decode([Parca].self, from: v)) ?? []
    }

    /// Belgeler klasörünü tarar; değişmemiş dosyaların künyesini önbellekten alır.
    static func tara() async -> [Parca] {
        let eski = Dictionary(onbellek().map { ($0.yol, $0) }, uniquingKeysWith: { a, _ in a })
        var sonuc: [Parca] = []
        for (yol, boyut, degisim) in Depo.dosyalar() {
            if let p = eski[yol], p.boyut == boyut, p.degisim == degisim { sonuc.append(p); continue }
            if let p = await oku(yol: yol, boyut: boyut, degisim: degisim) { sonuc.append(p) }
        }
        sonuc.sort(by: sirala)
        if let v = try? JSONEncoder().encode(sonuc) { try? v.write(to: onbellekURL, options: .atomic) }
        return sonuc
    }

    static func sirala(_ a: Parca, _ b: Parca) -> Bool {
        if a.albumSanatcisi != b.albumSanatcisi { return a.albumSanatcisi.localizedStandardCompare(b.albumSanatcisi) == .orderedAscending }
        if a.album != b.album { return a.album.localizedStandardCompare(b.album) == .orderedAscending }
        if a.diskNo != b.diskNo { return a.diskNo < b.diskNo }
        if a.parcaNo != b.parcaNo { return a.parcaNo < b.parcaNo }
        return a.yol.localizedStandardCompare(b.yol) == .orderedAscending
    }

    static func albumler(_ p: [Parca]) -> [Album] {
        Dictionary(grouping: p, by: \.albumAnahtari).map { k, v in
            Album(id: k, ad: v[0].album, sanatci: v[0].albumSanatcisi, yil: v.map(\.yil).max() ?? 0, parcalar: v.sorted(by: sirala))
        }.sorted { $0.sanatci == $1.sanatci ? $0.ad.localizedStandardCompare($1.ad) == .orderedAscending
            : $0.sanatci.localizedStandardCompare($1.sanatci) == .orderedAscending }
    }

    // MARK: Künye okuma

    private static func oku(yol: String, boyut: Int, degisim: Double) async -> Parca? {
        let url = Depo.klasor.appendingPathComponent(yol)
        let uzanti = url.pathExtension.lowercased()
        let dosyaAdi = url.deletingPathExtension().lastPathComponent
        let ust = url.deletingLastPathComponent().lastPathComponent
        var p = Parca(yol: yol, baslik: dosyaAdi, sanatci: "", album: "", albumSanatcisi: "", parcaNo: 0, diskNo: 1, yil: 0,
                      sure: 0, bicim: uzanti.uppercased(), kayipsiz: false, yuksekCozunurluk: false, replayGain: nil,
                      kapak: nil, boyut: boyut, degisim: degisim)
        var kapakVerisi: Data?

        if uzanti == "flac", let e = FlacEtiket.oku(url) {
            p.baslik = e.yorum["TITLE"] ?? p.baslik
            p.sanatci = e.yorum["ARTIST"] ?? ""
            p.album = e.yorum["ALBUM"] ?? ""
            p.albumSanatcisi = e.yorum["ALBUMARTIST"] ?? e.yorum["ALBUM ARTIST"] ?? ""
            p.parcaNo = sayi(e.yorum["TRACKNUMBER"])
            p.diskNo = max(1, sayi(e.yorum["DISCNUMBER"]))
            p.yil = sayi(e.yorum["DATE"] ?? e.yorum["YEAR"])
            p.replayGain = e.yorum["REPLAYGAIN_TRACK_GAIN"].flatMap(dB)
            if e.hz > 0 {
                p.sure = Double(e.toplamOrnek) / Double(e.hz)
                p.bicim = "FLAC \(e.bit)/\(khz(Double(e.hz)))"
                p.yuksekCozunurluk = e.bit > 16 || e.hz > 48000
            }
            p.kayipsiz = true
            kapakVerisi = e.kapak
        } else {
            let asset = AVURLAsset(url: url)
            if let ortak = try? await asset.load(.commonMetadata) {
                for m in ortak {
                    switch m.commonKey {
                    case .commonKeyTitle: if let s = try? await m.load(.stringValue), !s.isEmpty { p.baslik = s }
                    case .commonKeyArtist: p.sanatci = (try? await m.load(.stringValue)) ?? p.sanatci
                    case .commonKeyAlbumName: p.album = (try? await m.load(.stringValue)) ?? p.album
                    case .commonKeyArtwork: kapakVerisi = try? await m.load(.dataValue)
                    case .commonKeyCreationDate: p.yil = sayi(try? await m.load(.stringValue))
                    default: break
                    }
                }
            }
            if let hepsi = try? await asset.load(.metadata) {
                for m in hepsi {
                    let k = (m.identifier?.rawValue ?? "").lowercased()
                    if k.hasSuffix("trkn") || k.hasSuffix("trck") {
                        if let d = try? await m.load(.dataValue), d.count >= 4 { p.parcaNo = Int(d[3]) }
                        else if let s = try? await m.load(.stringValue) { p.parcaNo = sayi(s) }
                    } else if k.hasSuffix("aart") || k.hasSuffix("tpe2") {
                        p.albumSanatcisi = (try? await m.load(.stringValue)) ?? p.albumSanatcisi
                    } else if k.contains("replaygain_track_gain") {
                        p.replayGain = (try? await m.load(.stringValue)).flatMap(dB)
                    }
                }
            }
            if let f = try? AVAudioFile(forReading: url) {
                let hz = f.fileFormat.sampleRate
                p.sure = hz > 0 ? Double(f.length) / f.processingFormat.sampleRate : 0
                let asbd = f.fileFormat.streamDescription.pointee
                switch asbd.mFormatID {
                case kAudioFormatAppleLossless:
                    let bit = [1: 16, 2: 20, 3: 24, 4: 32][Int(asbd.mFormatFlags)] ?? 16
                    p.bicim = "ALAC \(bit)/\(khz(hz))"; p.kayipsiz = true; p.yuksekCozunurluk = bit > 16 || hz > 48000
                case kAudioFormatLinearPCM:
                    let bit = Int(asbd.mBitsPerChannel)
                    p.bicim = "\(uzanti == "wav" ? "WAV" : "PCM") \(bit)/\(khz(hz))"; p.kayipsiz = true
                    p.yuksekCozunurluk = bit > 16 || hz > 48000
                default:
                    let kbps = p.sure > 0 ? Int(Double(boyut) * 8 / p.sure / 1000) : 0
                    let ad = asbd.mFormatID == kAudioFormatMPEGLayer3 ? "MP3" : (asbd.mFormatID == kAudioFormatOpus ? "OPUS" : "AAC")
                    p.bicim = "\(ad) \(kbps)"
                }
            }
        }
        // Etiketsiz dosya: "Sanatçı - Başlık" adını böl.
        if p.sanatci.isEmpty, p.baslik == dosyaAdi, let r = dosyaAdi.range(of: " - ") {
            p.sanatci = String(dosyaAdi[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            p.baslik = String(dosyaAdi[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if p.album.isEmpty { p.album = ust.isEmpty || yol.contains("/") == false ? "Tekil parçalar" : ust }
        if p.sanatci.isEmpty { p.sanatci = "Bilinmeyen sanatçı" }
        if p.albumSanatcisi.isEmpty { p.albumSanatcisi = p.sanatci }
        if kapakVerisi == nil { kapakVerisi = klasorKapagi(url.deletingLastPathComponent()) }
        if let v = kapakVerisi, let ad = kapakKaydet(v, anahtar: p.albumAnahtari) { p.kapak = ad }
        return p
    }

    private static func klasorKapagi(_ klasor: URL) -> Data? {
        for ad in ["cover", "folder", "front", "Cover", "Folder", "Front", "album", "AlbumArt"] {
            for u in ["jpg", "jpeg", "png"] {
                let url = klasor.appendingPathComponent("\(ad).\(u)")
                if let v = try? Data(contentsOf: url) { return v }
            }
        }
        return nil
    }

    /// Kapağı 700 px'e küçültüp albüm başına bir kez kaydeder.
    private static func kapakKaydet(_ veri: Data, anahtar: String) -> String? {
        let ad = String(format: "%016llx.jpg", fnv(anahtar))
        let hedef = kapakKlasoru.appendingPathComponent(ad)
        if FileManager.default.fileExists(atPath: hedef.path) { return ad }
        guard let kaynak = CGImageSourceCreateWithData(veri as CFData, nil),
              let resim = CGImageSourceCreateThumbnailAtIndex(kaynak, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 700,
                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
              let jpg = UIImage(cgImage: resim).jpegData(compressionQuality: 0.85) else { return nil }
        try? jpg.write(to: hedef)
        return ad
    }

    private static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    private static func sayi(_ s: String?) -> Int {
        guard let s else { return 0 }
        return Int(s.prefix { $0.isNumber }) ?? 0
    }

    private static func dB(_ s: String) -> Float? {
        Float(s.replacingOccurrences(of: "dB", with: "").replacingOccurrences(of: " ", with: ""))
    }

    static func khz(_ hz: Double) -> String {
        let k = hz / 1000
        return k == k.rounded() ? String(Int(k)) : String(format: "%.1f", k)
    }
}

/// FLAC'ın kendi künye blokları (STREAMINFO, VORBIS_COMMENT, PICTURE). AVFoundation FLAC künyesini her
/// zaman okumadığı için elle okunur; dosyanın başındaki birkaç yüz KB'den fazlasına dokunulmaz.
struct FlacEtiket {
    var hz = 0, bit = 16, kanal = 2
    var toplamOrnek: Int64 = 0
    var yorum: [String: String] = [:]
    var kapak: Data?

    static func oku(_ url: URL) -> FlacEtiket? {
        guard let el = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? el.close() }
        func oku(_ n: Int) -> [UInt8]? {
            guard let v = try? el.read(upToCount: n), v.count == n else { return nil }
            return [UInt8](v)
        }
        guard var bas = oku(4) else { return nil }
        if bas[0] == 0x49, bas[1] == 0x44, bas[2] == 0x33 {   // önde ID3 varsa atla
            guard let r = oku(6) else { return nil }
            let boy = (Int(r[2]) << 21) | (Int(r[3]) << 14) | (Int(r[4]) << 7) | Int(r[5])
            try? el.seek(toOffset: UInt64(10 + boy))
            guard let b = oku(4) else { return nil }
            bas = b
        }
        guard bas == [0x66, 0x4C, 0x61, 0x43] else { return nil }   // "fLaC"
        var e = FlacEtiket()
        var son = false
        var tur3Bulundu = false
        while !son {
            guard let h = oku(4) else { break }
            son = h[0] & 0x80 != 0
            let tur = h[0] & 0x7F
            let boy = (Int(h[1]) << 16) | (Int(h[2]) << 8) | Int(h[3])
            switch tur {
            case 0:
                guard let b = oku(boy), b.count >= 18 else { return e }
                e.hz = (Int(b[10]) << 12) | (Int(b[11]) << 4) | (Int(b[12]) >> 4)
                e.kanal = Int((b[12] >> 1) & 7) + 1
                e.bit = Int(((b[12] & 1) << 4) | (b[13] >> 4)) + 1
                e.toplamOrnek = (Int64(b[13] & 0x0F) << 32) | (Int64(b[14]) << 24) | (Int64(b[15]) << 16) | (Int64(b[16]) << 8) | Int64(b[17])
            case 4:
                guard let b = oku(boy) else { return e }
                e.yorumlariAyristir(b)
            case 6 where !tur3Bulundu && boy < 12_000_000:
                guard let b = oku(boy) else { return e }
                if let (t, v) = resimAyristir(b) {
                    if t == 3 || e.kapak == nil { e.kapak = v }
                    if t == 3 { tur3Bulundu = true }
                }
            default:
                guard let k = try? el.offset() else { return e }
                try? el.seek(toOffset: k + UInt64(boy))
            }
        }
        return e
    }

    private mutating func yorumlariAyristir(_ b: [UInt8]) {
        var i = 0
        func u32() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return Int(b[i]) | (Int(b[i + 1]) << 8) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24)
        }
        guard let satici = u32() else { return }
        i += satici
        guard let adet = u32() else { return }
        for _ in 0..<adet {
            guard let n = u32(), i + n <= b.count else { return }
            let s = String(decoding: b[i..<(i + n)], as: UTF8.self)
            i += n
            if let esit = s.firstIndex(of: "=") {
                let k = s[..<esit].uppercased()
                if yorum[k] == nil { yorum[k] = String(s[s.index(after: esit)...]) }
            }
        }
    }

    private static func resimAyristir(_ b: [UInt8]) -> (Int, Data)? {
        var i = 0
        func u32() -> Int? {
            guard i + 4 <= b.count else { return nil }
            defer { i += 4 }
            return (Int(b[i]) << 24) | (Int(b[i + 1]) << 16) | (Int(b[i + 2]) << 8) | Int(b[i + 3])
        }
        guard let tur = u32(), let mime = u32() else { return nil }
        i += mime
        guard let acik = u32() else { return nil }
        i += acik + 16
        guard let n = u32(), i + n <= b.count else { return nil }
        return (tur, Data(b[i..<(i + n)]))
    }
}
