// A document voiced on the Mac by Voice Reader Studio (studio/studio.py: VoxCPM2, a large local model, far more
// natural than anything that runs live on a phone). The pack sits next to the document's text:
//
//   docs/<id>/studio/book.json     segments: where each is in the text, its audio file, its pause, its word starts
//   docs/<id>/studio/audio/NNNN.m4a
//
// With the "Anlatıcı" voice the player plays these files instead of synthesising; speed is applied here with the
// same WSOLA as the other voices, so the pitch stays. A place the pack does not cover is read live by Ema.
import Foundation
import AVFoundation

struct StudioPack: Sendable {
    struct Segment: Decodable, Sendable {
        let location: Int                   // UTF-16 offset in the document text
        let length: Int
        let file: String
        let pause: Double                   // seconds of silence after it (at 1×)
        let duration: Double?
        let words: [[Int]]?                 // [start ms, location, length]
        var end: Int { location + length }
    }
    private struct Book: Decodable {
        let id: UUID?
        let title: String
        let author: String?
        let voice: String?
        let complete: Bool?
        let content: DocumentContent
        let segments: [Segment]
    }

    let folder: URL
    let segments: [Segment]                 // sorted by location
    let complete: Bool

    /// The pack of an imported document, if it has one.
    static func load(_ folder: URL) -> StudioPack? {
        guard let data = try? Data(contentsOf: folder.appending(path: "book.json")),
              let book = try? JSONDecoder().decode(Book.self, from: data) else { return nil }
        return StudioPack(folder: folder, segments: book.segments.sorted { $0.location < $1.location },
                          complete: book.complete ?? false)
    }

    /// Reads a pack folder (as dropped from the Mac) into what the library needs to add it as a document.
    static func readDocument(_ folder: URL) throws -> (id: UUID?, title: String, author: String?, content: DocumentContent) {
        let data = try Data(contentsOf: folder.appending(path: "book.json"))
        let book = try JSONDecoder().decode(Book.self, from: data)
        return (book.id, book.title, book.author, book.content)
    }

    /// The segment that holds `pos`, or the next one when `pos` falls between two (a line break).
    func index(at pos: Int) -> Int? {
        var lo = 0, hi = segments.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if segments[mid].end <= pos { lo = mid + 1 } else { hi = mid }
        }
        return lo < segments.count ? lo : nil
    }

    /// The segment's audio from `start` (a document offset inside it) at `speed`: 48 kHz samples and word starts,
    /// with word ranges relative to `start`. Nil when the file is missing or unreadable.
    func render(_ i: Int, from start: Int, speed: Double, boost: Double = 0) -> RenderedSpeech? {
        let seg = segments[i]
        guard var samples = Self.decode(folder.appending(path: "audio").appending(path: seg.file)), !samples.isEmpty else { return nil }
        var words: [(sample: Int, range: NSRange)] = (seg.words ?? []).compactMap { w in
            guard w.count == 3 else { return nil }
            return (Int(Double(w[0]) * 48), NSRange(location: w[1], length: w[2]))
        }
        // started mid-segment (a tap on a word): cut the audio at that word
        if start > seg.location, let first = words.first(where: { $0.range.location >= start }) {
            let cut = max(0, min(samples.count, first.sample - 480))        // 10 ms before the word
            samples.removeFirst(cut)
            words = words.filter { $0.range.location >= start }.map { ($0.sample - cut, $0.range) }
        }
        words = words.map { ($0.sample, NSRange(location: $0.range.location - start, length: $0.range.length)) }
        samples = ToneEQ.apply(samples, .flat)
        let tempo = max(1, speed)
        if tempo > 1.01, samples.count > 4096 {
            let before = samples.count
            samples = TimeStretch.compress(samples, tempo: tempo)
            let k = Double(samples.count) / Double(before)
            words = words.map { (Int(Double($0.sample) * k), $0.range) }
        }
        samples = Level.apply(samples, boost: boost)
        return RenderedSpeech(samples: samples, words: words)
    }

    /// An AAC (or any AVAudioFile) as 48 kHz mono floats.
    static func decode(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else { return nil }
        let src = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else { return nil }
        do { try file.read(into: inBuf) } catch { return nil }
        if src.sampleRate == 48_000, src.channelCount == 1, src.commonFormat == .pcmFormatFloat32 {
            return Array(UnsafeBufferPointer(start: inBuf.floatChannelData![0], count: Int(inBuf.frameLength)))
        }
        guard let conv = AVAudioConverter(from: src, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target,
                                         frameCapacity: AVAudioFrameCount(Double(frames) * 48_000 / src.sampleRate) + 1024) else { return nil }
        var given = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .endOfStream; return nil }
            given = true; status.pointee = .haveData; return inBuf
        }
        guard err == nil else { return nil }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }
}
