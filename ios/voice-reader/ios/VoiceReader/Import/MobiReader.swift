// Kindle books without DRM: MOBI, AZW, AZW3 (KF8) and PRC. A Palm database whose first record holds the PalmDOC and
// MOBI headers (and EXTH: author, title); the text records are PalmDOC-compressed HTML. Huffman-compressed (HUFF/CDIC)
// and encrypted books are refused with a message, not read wrongly.
import Foundation

enum MobiReader {
    enum Failure: Error { case notMobi, drm, huffman }

    struct Book { let html: String; let title: String?; let author: String? }

    static func read(_ d: Data) throws -> Book {
        let b = [UInt8](d)
        guard b.count > 78 else { throw Failure.notMobi }
        let count = Int(u16(b, 76))
        var offsets: [Int] = []
        for k in 0..<count where 78 + k * 8 + 4 <= b.count { offsets.append(Int(u32(b, 78 + k * 8))) }
        guard offsets.count >= 2 else { throw Failure.notMobi }
        func record(_ k: Int) -> ArraySlice<UInt8> {
            let a = offsets[k], z = k + 1 < offsets.count ? offsets[k + 1] : b.count
            return a < z && z <= b.count ? b[a..<z] : []
        }
        let r0 = Array(record(0))
        guard r0.count >= 16 else { throw Failure.notMobi }
        let compression = u16(r0, 0)
        let textRecords = Int(u16(r0, 8))
        if u16(r0, 12) != 0 { throw Failure.drm }
        if compression == 17480 { throw Failure.huffman }

        var encoding: String.Encoding = .windowsCP1252
        var extraFlags: UInt16 = 0
        var title: String?, author: String?
        if r0.count >= 24, String(bytes: r0[16..<20], encoding: .ascii) == "MOBI" {
            let headerLength = Int(u32(r0, 20))
            if u32(r0, 28) == 65001 { encoding = .utf8 }
            if headerLength >= 0xE4, r0.count >= 16 + 0xF4 { extraFlags = u16(r0, 16 + 0xE2) }
            let nameAt = Int(u32(r0, 84)), nameLength = Int(u32(r0, 88))
            if nameAt + nameLength <= r0.count, nameLength > 0 { title = String(bytes: r0[nameAt..<(nameAt + nameLength)], encoding: encoding) }
            // EXTH: 100 author, 503 updated title
            if u32(r0, 128) & 0x40 != 0 {
                var p = 16 + headerLength
                if p + 12 <= r0.count, String(bytes: r0[p..<(p + 4)], encoding: .ascii) == "EXTH" {
                    let n = Int(u32(r0, p + 8))
                    p += 12
                    for _ in 0..<n {
                        guard p + 8 <= r0.count else { break }
                        let type = u32(r0, p), len = Int(u32(r0, p + 4))
                        guard len >= 8, p + len <= r0.count else { break }
                        let value = String(bytes: r0[(p + 8)..<(p + len)], encoding: encoding)
                        if type == 100, author == nil { author = value }
                        if type == 503 { title = value }
                        p += len
                    }
                }
            }
        }

        var text: [UInt8] = []
        for k in 1...max(1, min(textRecords, offsets.count - 1)) {
            var r = Array(record(k))
            r.removeLast(min(r.count, trailing(r, flags: extraFlags)))
            text += compression == 2 ? palmDOC(r) : r
        }
        let html = String(bytes: text, encoding: encoding) ?? String(decoding: text, as: UTF8.self)
        return Book(html: html, title: title?.trimmingCharacters(in: .whitespaces), author: author?.trimmingCharacters(in: .whitespaces))
    }

    /// Bytes at the end of a text record that are not text (indexing data), as calibre measures them.
    private static func trailing(_ r: [UInt8], flags: UInt16) -> Int {
        var num = 0
        var f = flags >> 1
        while f != 0 {
            if f & 1 != 0 {
                var size = r.count - num, bit = 0, value = 0
                while size > 0 {
                    let v = Int(r[size - 1])
                    value |= (v & 0x7F) << bit
                    bit += 7; size -= 1
                    if v & 0x80 != 0 || bit >= 28 { break }
                }
                num += value
            }
            f >>= 1
        }
        if flags & 1 != 0, r.count - num - 1 >= 0 { num += Int(r[r.count - num - 1] & 0x3) + 1 }
        return num
    }

    /// PalmDOC LZ77.
    private static func palmDOC(_ d: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(d.count * 2)
        var i = 0
        while i < d.count {
            let c = d[i]; i += 1
            switch c {
            case 0x01...0x08:
                let n = Int(c)
                out += d[i..<min(d.count, i + n)]; i += n
            case 0x00, 0x09...0x7F:
                out.append(c)
            case 0xC0...0xFF:
                out.append(0x20); out.append(c ^ 0x80)
            default:
                guard i < d.count else { break }
                let v = (Int(c) << 8 | Int(d[i])) & 0x3FFF; i += 1
                let dist = v >> 3, n = (v & 7) + 3
                guard dist > 0, dist <= out.count else { continue }
                for _ in 0..<n { out.append(out[out.count - dist]) }
            }
        }
        return out
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { i + 1 < b.count ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : 0 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        i + 3 < b.count ? UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]) : 0
    }
}
