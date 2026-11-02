// Notes and the bicycle buttons: mark the sentence being read, record a voice note tied to it, write a note.
import Foundation
import AudioToolbox
import UIKit

struct NoteToast: Equatable {
    var id: String
    var seconds: Double?
    var text: String
}

extension AppModel {
    /// The place a note or a mark belongs to: the sentence being read (or where reading stopped).
    func sentenceNow() -> NSRange? {
        guard player.documentID != nil else { return nil }
        return player.spokenSentence ?? player.sentenceRange(around: player.cursor)
    }

    /// One press: the sentence being read turns yellow. A second press on the same sentence takes the mark away
    /// (a toggle; ⏭ on the headphones does the same).
    @discardableResult
    func markSpokenSentence() -> MarkResult? {
        guard var r = sentenceNow(), r.length > 0, let id = player.documentID else { return nil }
        // pressed in the first two seconds of a new sentence: the one that just ended was meant (the press comes late),
        // unless that one is already marked, then the press is for the sentence being read
        var back = false
        if player.isPlaying, Date.now.timeIntervalSince(player.sentenceSince) < 2,
           let p = player.previousSentence, p.location < r.location, !isMarked(p) {
            r = p; back = true
        }
        let marked = store.document(id)?.highlights.filter { NSIntersectionRange($0.range, r).length * 2 >= min($0.length, r.length) } ?? []
        if !marked.isEmpty {
            for h in marked { removeHighlight(h.id) }
            markChain = nil
            AudioServicesPlaySystemSound(1104)                 // a softer click than the mark's: heard as "taken away"
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return MarkResult(added: false, previous: back)
        }
        let text = player.excerptWord(r).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        addHighlight(r, color: .yellow, text: text)
        markChain = MarkChain(doc: id, range: r, count: 1, at: .now)
        AudioServicesPlaySystemSound(1057)                     // a short tick: heard without looking
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return MarkResult(added: true, previous: back)
    }

    /// The mark grows back by one sentence (held mark key, or ⏭ again): what was just heard is behind the voice, so
    /// the sentences before the marked one are taken in, one by one, up to `MarkChain.most`. One highlight covers them.
    /// Without a fresh chain it starts from the mark on the sentence being read. Nil: nothing more to take.
    @discardableResult
    func extendMarkBack() -> Int? {
        guard let id = player.documentID else { return nil }
        var c = markChain
        if c == nil || c?.doc != id, let r = sentenceNow(),
           let h = store.document(id)?.highlights.first(where: { NSIntersectionRange($0.range, r).length > 0 }) {
            c = MarkChain(doc: id, range: h.range, count: 1, at: .now)
        }
        guard var chain = c, chain.doc == id, chain.count < MarkChain.most else { return nil }
        guard let prev = player.sentence(before: chain.range.location) else { return nil }
        let r = NSRange(location: prev.location, length: NSMaxRange(chain.range) - prev.location)
        for h in store.document(id)?.highlights.filter({ NSIntersectionRange($0.range, r).length > 0 }) ?? [] { removeHighlight(h.id) }
        addHighlight(r, color: .yellow, text: player.excerptWord(r).trimmingCharacters(in: .whitespacesAndNewlines))
        chain.range = r; chain.count += 1; chain.at = .now
        markChain = chain
        AudioServicesPlaySystemSound(1057)
        UIImpactFeedbackGenerator(style: chain.count >= 3 ? .heavy : .medium).impactOccurred()
        return chain.count
    }

    struct MarkResult: Equatable { var added: Bool; var previous: Bool }

    struct MarkChain: Equatable {
        static let most = 6
        var doc: UUID
        var range: NSRange
        var count: Int                  // sentences in the mark
        var at: Date
    }

    func isMarked(_ r: NSRange) -> Bool {
        currentDocument?.highlights.contains { NSIntersectionRange($0.range, r).length * 2 >= min($0.length, r.length) } ?? false
    }

    /// The sentence being read is already marked (the bicycle button then offers to take the mark away).
    var spokenSentenceMarked: Bool {
        guard let r = sentenceNow(), r.length > 0, let d = currentDocument else { return false }
        return d.highlights.contains { NSIntersectionRange($0.range, r).length * 2 >= min($0.length, r.length) }
    }

    func toggleVoiceNote(anchor: NSRange? = nil) {
        if recorder.isRecording { finishVoiceNote() } else { startVoiceNote(anchor: anchor) }
    }

    /// Reading pauses, recording starts; the note belongs to `anchor` (a highlight) or the sentence being read.
    func startVoiceNote(anchor: NSRange? = nil) {
        guard !recorder.isRecording, let id = player.documentID, let doc = store.document(id),
              let r = anchor ?? sentenceNow() else { return }
        pendingNote = (id, doc.title, r, player.excerptWord(r).trimmingCharacters(in: .whitespacesAndNewlines),
                       player.chapterTitle(at: r.location))
        resumeAfterNote = player.isPlaying
        if player.isPlaying { player.pause() }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        AudioServicesPlaySystemSound(1113)
        Task {
            if await !recorder.start(withMusic: settings.musicMix != .off) {
                pendingNote = nil
                resumeReading()
            }
        }
    }

    /// Stops, saves, goes on reading from the start of the sentence, then writes the text on the phone.
    func finishVoiceNote() {
        let result = recorder.stop()
        defer { resumeReading() }
        guard let p = pendingNote else { return }
        pendingNote = nil
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        AudioServicesPlaySystemSound(1114)
        guard let result else { return }
        let n = notes.add(doc: p.doc, title: p.title, range: p.range, quote: p.quote, chapter: p.chapter, text: "",
                          transcript: nil, recording: result.url, seconds: result.seconds)
        noteToast = NoteToast(id: n.id, seconds: result.seconds, text: "")
        guard let url = notes.audioURL(n) else { return }
        Task {
            let text = await NoteRecorder.transcribe(url)
            guard !text.isEmpty, let cur = notes.note(n.id), cur.text.isEmpty else { return }
            notes.setText(n.id, text, transcript: "device")
            if noteToast?.id == n.id { noteToast?.text = text }
        }
    }

    func cancelVoiceNote() {
        recorder.cancel()
        pendingNote = nil
        resumeReading()
    }

    private func resumeReading() {
        guard resumeAfterNote else { return }
        resumeAfterNote = false
        player.play(from: player.sentenceStart(before: player.cursor + 1), snap: false)
    }

    /// A written note on a range (a highlight or a selection).
    func addTextNote(_ range: NSRange, quote: String, text: String) {
        guard let id = player.documentID, let doc = store.document(id),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notes.add(doc: id, title: doc.title, range: range, quote: quote, chapter: player.chapterTitle(at: range.location),
                  text: text, transcript: nil, recording: nil, seconds: nil)
    }

    var currentNotes: [ReaderNote] { player.documentID.map { notes.notes(of: $0) } ?? [] }
}

// MARK: - moving modes (Yolda)

extension AppModel {
    /// Bicycle or walking mode on: the big keys and the road screen, and the GPS record of the way starts.
    func startMove(_ kind: MoveKind) {
        settings.moveKind = kind
        if !settings.bikeLook.road { settings.bikeLook = .focus }     // the moving modes open on the road screen
        settings.bikeMode = true
        workout.start(kind)
    }

    /// The moving mode off: the record of the way is finished and kept.
    func endMove() {
        settings.bikeMode = false
        workout.finish()
    }
}
