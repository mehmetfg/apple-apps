// Reads entries out of a ZIP file (EPUB and DOCX are ZIP files). Stored and deflated entries; no ZIP64, no encryption.
// Apple's COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is exactly what ZIP stores.
import Foundation
import Compression

struct ZipArchive {
    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error { case notZip, unsupported, corrupt }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        try readDirectory()
    }

    var paths: [String] { Array(entries.keys) }

    private func u16(_ at: Int) -> UInt16 {
        guard at + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt16.self)) }
    }
    private func u32(_ at: Int) -> UInt32 {
        guard at + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }
    }

    private mutating func readDirectory() throws {
        // the end-of-central-directory record is in the last 64 KiB + 22 bytes
        let n = data.count
        guard n >= 22 else { throw ZipError.notZip }
        var eocd = -1
        var i = n - 22
        let floor = max(0, n - 65_557)
        while i >= floor {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= n, u32(p) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = u16(p + 10)
            let csize = Int(u32(p + 20))
            let size = Int(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let local = Int(u32(p + 42))
            guard p + 46 + nameLen <= n else { throw ZipError.corrupt }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(path: name, method: method, compressedSize: csize, size: size, localHeaderOffset: local)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    /// The entry's bytes, or nil if it is missing or cannot be read. Lookup ignores case as a fallback
    /// (some EPUBs reference "Text/ch1.xhtml" while the archive holds "text/ch1.xhtml").
    func data(for path: String) -> Data? {
        let entry = entries[path] ?? entries.first { $0.key.caseInsensitiveCompare(path) == .orderedSame }?.value
        guard let e = entry else { return nil }
        let h = e.localHeaderOffset
        guard u32(h) == 0x0403_4B50 else { return nil }
        let start = h + 30 + Int(u16(h + 26)) + Int(u16(h + 28))
        guard start + e.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return inflate(raw, size: e.size)
        default: return nil
        }
    }

    private func inflate(_ raw: Data, size: Int) -> Data? {
        if size == 0 { return Data() }
        guard !raw.isEmpty else { return nil }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            raw.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.count = written
        return out
    }
}
