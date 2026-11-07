// Puts an app's items in the system search. Each app gives its whole list; only what changed since
// the last call is written, and what left the list is removed. A tap on a result gives the app the
// identifier back through `identifier(from:)`.
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

public enum PDMSpotlight {
    public struct Item: Sendable, Equatable {
        public var id: String
        public var title: String
        public var detail: String?
        public var keywords: [String]
        public var thumbnail: URL?

        public init(id: String, title: String, detail: String? = nil, keywords: [String] = [], thumbnail: URL? = nil) {
            self.id = id; self.title = title; self.detail = detail; self.keywords = keywords; self.thumbnail = thumbnail
        }

        var signature: String {
            let raw = [title, detail ?? "", keywords.joined(separator: ","), thumbnail?.path ?? ""].joined(separator: "\u{1F}")
            var h: UInt64 = 0xcbf29ce484222325
            for b in raw.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            return String(h, radix: 16)
        }
    }

    private static func ledger(_ scope: String) -> URL {
        URL.cachesDirectory.appending(path: "spotlight-\(scope).json")
    }

    /// Makes the index match `items`. `scope` separates lists in one app (`books`, `notes`). Call it off the main
    /// thread: thumbnails are read from disk. A failed write leaves the ledger as it was, so the next call tries again.
    public static func sync(_ items: [Item], scope: String) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let old = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: ledger(scope)))) ?? [:]
        var new: [String: String] = [:]
        for i in items { new[i.id] = i.signature }
        let changed = items.filter { old[$0.id] != new[$0.id] }
        let gone = old.keys.filter { new[$0] == nil }
        guard !changed.isEmpty || !gone.isEmpty else { return }

        let index = CSSearchableIndex.default()
        do {
            if !gone.isEmpty { try await index.deleteSearchableItems(withIdentifiers: gone) }
            var start = 0
            while start < changed.count {
                let part = changed[start..<min(start + 200, changed.count)]
                try await index.indexSearchableItems(part.map { i in
                    let a = CSSearchableItemAttributeSet(contentType: .text)
                    a.title = i.title
                    a.contentDescription = i.detail
                    a.keywords = i.keywords
                    if let t = i.thumbnail { a.thumbnailData = try? Data(contentsOf: t) }
                    return CSSearchableItem(uniqueIdentifier: i.id, domainIdentifier: scope, attributeSet: a)
                })
                start += part.count
            }
            try JSONEncoder().encode(new).write(to: ledger(scope), options: .atomic)
        } catch {
            return
        }
    }

    /// The identifier of the result the user tapped. Use with `.onContinueUserActivity(PDMSpotlight.activityType)`.
    public static let activityType = CSSearchableItemActionType
    public static func identifier(from activity: NSUserActivity) -> String? {
        activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    }
}
