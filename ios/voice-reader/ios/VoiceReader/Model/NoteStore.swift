// Notes: written or spoken thoughts tied to a place in a document (a sentence, a highlight). One append-only log
// (a changed or deleted note is a new line; the newest line of an id wins) and one .m4a per voice note.
//
//   Application Support/VoiceReader/notes/<device>.jsonl   the log
//   Application Support/VoiceReader/notes/audio/<id>.m4a   the recordings
//
// Both are copied into the vault (VaultMirror: durum/Notes, durum/NoteAudio). On the Mac, Teoria's library step turns
// them into Teoria notes (Notlarım), Whisper writes a cleaner transcript, as Kıvılcım does.
import Foundation
import AVFoundation
import Observation

struct ReaderNote: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var doc: UUID
    var bookTitle: String
    var text: String
    var transcript: String?                     // where `text` came from: "device" (iOS speech recognition), nil = typed
    var audio: String?                          // file name in notes/audio
    var seconds: Double?
    var location: Int                           // the sentence or highlight it belongs to (UTF-16)
    var length: Int
    var quote: String
    var chapterTitle: String?
    var date: Date
    var edited: Date?
    var deleted: Bool?

    var range: NSRange { NSRange(location: location, length: length) }
    var stamp: Date { edited ?? date }
    var hasVoice: Bool { audio != nil }
}

@MainActor
@Observable
final class NoteStore {
    private(set) var notes: [ReaderNote] = []          // live notes, newest first
    @ObservationIgnored private let dir: URL
    @ObservationIgnored let audioDir: URL
    @ObservationIgnored private let device: String

    init(device: String) {
        self.device = device
        dir = URL.applicationSupportDirectory.appending(path: "VoiceReader/notes", directoryHint: .isDirectory)
        audioDir = dir.appending(path: "audio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        // the log is read off the main thread (it only grows); a note written before it is in stays as written
        let log = log
        Task.detached(priority: .userInitiated) { [weak self] in
            let stored = Self.read(log)
            await self?.adopt(stored)
        }
    }

    private var log: URL { dir.appending(path: "\(device).jsonl") }

    func notes(of doc: UUID) -> [ReaderNote] { notes.filter { $0.doc == doc }.sorted { $0.location < $1.location } }
    func note(_ id: String) -> ReaderNote? { notes.first { $0.id == id } }
    func audioURL(_ n: ReaderNote) -> URL? { n.audio.map { audioDir.appending(path: $0) } }

    /// The live notes of a log, newest first (the newest line of an id wins; a deleted one is left out).
    nonisolated private static func read(_ log: URL) -> [ReaderNote] {
        guard let t = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        var latest: [String: ReaderNote] = [:]
        for l in t.split(separator: "\n") {
            guard let n = try? dec.decode(ReaderNote.self, from: Data(l.utf8)) else { continue }
            if let old = latest[n.id], old.stamp > n.stamp { continue }
            latest[n.id] = n
        }
        return latest.values.filter { $0.deleted != true }.sorted { $0.stamp > $1.stamp }
    }

    private func adopt(_ stored: [ReaderNote]) {
        let mine = Set(notes.map(\.id))
        notes = (notes + stored.filter { !mine.contains($0.id) }).sorted { $0.stamp > $1.stamp }
    }

    private func write(_ n: ReaderNote) {
        guard var line = try? JSONEncoder().encode(n) else { return }
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(line); try? h.close() }
        else { try? line.write(to: log, options: .atomic) }
        if let i = notes.firstIndex(where: { $0.id == n.id }) { notes.remove(at: i) }
        if n.deleted != true { notes.insert(n, at: 0) }
        mirror()
    }

    /// The whole log and any recording not there yet go to the vault copy (also catches up notes made before the
    /// vault folder was chosen).
    func mirror() {
        let log = log, audio = audioDir, device = device
        Task.detached { await VaultMirror.shared.mirrorNotes(log: log, audioDir: audio, device: device) }
    }

    /// A new note. `recording` is the recorder's file; it moves into the notes' audio folder.
    @discardableResult
    func add(doc: UUID, title: String, range: NSRange, quote: String, chapter: String?, text: String,
             transcript: String?, recording: URL?, seconds: Double?) -> ReaderNote {
        let id = "vr-" + UUID().uuidString.prefix(12).lowercased()
        var audio: String?
        if let recording {
            let name = "\(id).m4a"
            let dst = audioDir.appending(path: name)
            try? FileManager.default.removeItem(at: dst)
            if (try? FileManager.default.moveItem(at: recording, to: dst)) != nil { audio = name }
        }
        let n = ReaderNote(id: id, doc: doc, bookTitle: title, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                           transcript: transcript, audio: audio, seconds: seconds, location: range.location,
                           length: range.length, quote: quote, chapterTitle: chapter, date: .now)
        write(n)
        return n
    }

    func setText(_ id: String, _ text: String, transcript: String?) {
        guard var n = note(id) else { return }
        n.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        n.transcript = transcript
        n.edited = .now
        write(n)
    }

    func delete(_ id: String) {
        guard var n = note(id) else { return }
        n.deleted = true
        n.edited = .now
        write(n)
    }
}
