// What the library knows about a document. The text itself lives in its own file (DocumentContent) and is loaded
// only when the document is opened, so the library stays small however many books it holds.
import Foundation

enum DocumentFormat: String, Codable, CaseIterable, Sendable {
    case pdf, epub, docx, html, rtf, txt, markdown, clipboard, mobi, odt, fb2, doc

    var badge: String {
        switch self {
        case .pdf: "PDF"
        case .epub: "EPUB"
        case .docx: "DOCX"
        case .html: "HTML"
        case .rtf: "RTF"
        case .txt: "TXT"
        case .markdown: "MD"
        case .clipboard: "METİN"
        case .mobi: "MOBI"
        case .odt: "ODT"
        case .fb2: "FB2"
        case .doc: "DOC"
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow, blue, red, green

    var name: String {
        switch self {
        case .yellow: "Sarı"
        case .blue: "Mavi"
        case .red: "Kırmızı"
        case .green: "Yeşil"
        }
    }
}

struct Bookmark: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var offset: Int
    var excerpt: String
    var createdAt = Date()
}

struct Highlight: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var location: Int
    var length: Int
    var color: HighlightColor
    var text: String
    var note: String?
    var createdAt = Date()

    var range: NSRange { NSRange(location: location, length: length) }
}

/// A heading in the document, at its UTF-16 offset in the plain text.
struct Chapter: Codable, Hashable, Sendable {
    var title: String
    var offset: Int
    var level: Int = 1
}

/// The readable form of a document: plain text with one paragraph per line, its headings and (for PDF) page starts.
struct DocumentContent: Codable, Sendable {
    var text: String
    var chapters: [Chapter]
    var pages: [Int]                                    // UTF-16 offset where each page starts; empty if not paged
}

struct DocumentRecord: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var author: String?
    var format: DocumentFormat
    var sourceName: String
    var folder: String?
    var flag: HighlightColor?
    var addedAt = Date()
    var lastOpenedAt: Date?
    var position = 0                                    // UTF-16 offset of the speech cursor
    var length: Int
    var wordCount: Int
    var language: String?                               // BCP 47 code detected at import ("tr", "en"…)
    var voiceID: String?                                // document-specific voice, else the language default
    var speed: Double?                                  // document-specific speed, else the global speed
    var bookmarks: [Bookmark] = []
    var highlights: [Highlight] = []
    var positionAt: Date?                               // when the position last changed (sync: newest wins)
    var partsApplied: Int?                              // pages appended from Library/<id>/parts (sync)
    var finishedAt: Date?                               // the reading heard to the end; nil while a reading goes on
    var finishes: [Date] = []                           // every reading heard to its end, oldest first

    var progress: Double { isFinished ? 1 : length > 0 ? min(1, Double(position) / Double(length)) : 0 }
    /// Finished is a fact written when the reading reached the end, never guessed from the place.
    var isFinished: Bool { finishedAt != nil }
    var isUnread: Bool { position == 0 && lastOpenedAt == nil && finishes.isEmpty }
    /// 1 for the first reading, 2 once the book was started again after it was finished…
    var readingNumber: Int { isFinished ? max(1, finishes.count) : finishes.count + 1 }
}

// MARK: - reading old and newer library files
//
// The library file must survive every update: a field added later is missing in the old file, a field this version
// does not know is ignored, and an unknown colour or format falls back instead of failing. One bad record never takes
// the others (and the reading positions and marks in them) with it.

extension DocumentRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil ?? "Adsız"
        author = try? c.decodeIfPresent(String.self, forKey: .author)
        format = (try? c.decodeIfPresent(DocumentFormat.self, forKey: .format)) ?? nil ?? .txt
        sourceName = (try? c.decodeIfPresent(String.self, forKey: .sourceName)) ?? nil ?? ""
        folder = try? c.decodeIfPresent(String.self, forKey: .folder)
        flag = try? c.decodeIfPresent(HighlightColor.self, forKey: .flag)
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? nil ?? Date()
        lastOpenedAt = try? c.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
        position = (try? c.decodeIfPresent(Int.self, forKey: .position)) ?? nil ?? 0
        length = (try? c.decodeIfPresent(Int.self, forKey: .length)) ?? nil ?? 0
        wordCount = (try? c.decodeIfPresent(Int.self, forKey: .wordCount)) ?? nil ?? 0
        language = try? c.decodeIfPresent(String.self, forKey: .language)
        voiceID = try? c.decodeIfPresent(String.self, forKey: .voiceID)
        speed = try? c.decodeIfPresent(Double.self, forKey: .speed)
        bookmarks = ((try? c.decodeIfPresent([Lossy<Bookmark>].self, forKey: .bookmarks)) ?? nil)?.compactMap(\.value) ?? []
        highlights = ((try? c.decodeIfPresent([Lossy<Highlight>].self, forKey: .highlights)) ?? nil)?.compactMap(\.value) ?? []
        positionAt = try? c.decodeIfPresent(Date.self, forKey: .positionAt)
        partsApplied = try? c.decodeIfPresent(Int.self, forKey: .partsApplied)
        finishedAt = try? c.decodeIfPresent(Date.self, forKey: .finishedAt)
        finishes = (try? c.decodeIfPresent([Date].self, forKey: .finishes)) ?? nil ?? []
        // a library written before finishing was recorded: a book at its end (the old 99 % rule) was finished then
        if !c.contains(.finishedAt), !c.contains(.finishes), length > 0, Double(position) >= Double(length) * 0.99 {
            let at = positionAt ?? lastOpenedAt ?? addedAt
            finishedAt = at
            finishes = [at]
        }
    }
}

extension Highlight {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil ?? UUID()
        location = try c.decode(Int.self, forKey: .location)
        length = try c.decode(Int.self, forKey: .length)
        color = (try? c.decodeIfPresent(HighlightColor.self, forKey: .color)) ?? nil ?? .yellow
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil ?? ""
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil ?? Date()
    }
}

extension Bookmark {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil ?? UUID()
        offset = try c.decode(Int.self, forKey: .offset)
        excerpt = (try? c.decodeIfPresent(String.self, forKey: .excerpt)) ?? nil ?? ""
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil ?? Date()
    }
}

/// One element of an array that may fail alone.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
