// The app's side of the widgets and the icon's quick actions (2026-10-28). `publish` writes the snapshot and the
// small covers to the App Group folder (a second after the last call, so a burst of changes writes once) and asks
// WidgetKit to redraw; it also sets the quick actions under the app icon (the book to go on with, the moving modes,
// music). `QuickActions` carries a quick action or a wisepath:// link to the library, which performs it.
import SwiftUI
import UIKit
import WidgetKit

@MainActor
enum WidgetFeed {
    private static var pending: Task<Void, Never>?

    static func publish(_ model: AppModel, now: Bool = false) {
        pending?.cancel()
        if now { write(model); return }
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            write(model)
        }
    }

    nonisolated private static func book(_ d: DocumentRecord, status: String) -> WidgetSnapshot.Book {
        let quotes = d.highlights.sorted { $0.createdAt > $1.createdAt }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 12 }
            .map { $0.count > 280 ? String($0.prefix(277)) + "…" : $0 }
        return .init(id: d.id, title: d.title, author: d.author, progress: d.progress, status: status,
                     finished: d.isFinished, quotes: Array(quotes.prefix(30)))
    }

    /// The main thread only hands over what the snapshot is made from (the document list is a copy-on-write value);
    /// sorting the library, gathering the quotes, encoding and writing happen off it. A background task keeps the
    /// app awake until the file is there, since this is also called as the app leaves the screen.
    private static func write(_ model: AppModel) {
        guard let url = WidgetShared.snapshotURL else { return }
        let docs = model.store.documents
        let playing = model.player.documentID.flatMap { model.store.document($0) }
        let pace = model.player.charsPerSecond, speed = model.settings.speed
        let today = model.listening.day(.now)
        let week = StatsModel(model: model).buckets(.day).suffix(7).map { WidgetSnapshot.Day(label: String($0.label.prefix(2)), minutes: $0.minutes, today: $0.current) }
        let hold = BackgroundHold("widget-snapshot")
        Task.detached(priority: .utility) {
            let byOpened = docs.filter { $0.lastOpenedAt != nil }.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            let current = playing ?? byOpened.first { !$0.isFinished }
            let reading = byOpened.filter { !$0.isFinished && !$0.isUnread }.prefix(12)
            let withMarks = byOpened.filter { !$0.highlights.isEmpty }.prefix(40)
            func made(_ d: DocumentRecord) -> WidgetSnapshot.Book {
                book(d, status: AppModel.statusText(d, charsPerSecond: pace, speed: speed))
            }
            let snap = WidgetSnapshot(current: current.map(made),
                                      reading: reading.map(made),
                                      books: withMarks.map(made),
                                      todayMinutes: today.seconds / 60,
                                      todayPages: Double(today.words) / 225,
                                      week: Array(week),
                                      updated: .now)
            if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
            // covers are written once per book: only a book without one goes back to the main thread to be drawn
            var seen = Set<UUID>()
            let coverless = ([current].compactMap { $0 } + reading + withMarks).filter { d in
                seen.insert(d.id).inserted && WidgetShared.coverURL(d.id).map { !FileManager.default.fileExists(atPath: $0.path) } == true
            }
            await MainActor.run {
                for d in coverless { cover(d, model) }
                WidgetCenter.shared.reloadAllTimelines()
                QuickActions.install(current: current)
                hold.end()
            }
        }
    }

    /// A 240-pixel cover for the widgets: the book's own picture, else the cover the app draws. Written once.
    private static func cover(_ d: DocumentRecord, _ model: AppModel) {
        guard let out = WidgetShared.coverURL(d.id), !FileManager.default.fileExists(atPath: out.path) else { return }
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        var image: UIImage?
        if SeriesBook(title: d.title) == nil, let img = UIImage(contentsOfFile: model.store.coverURL(d.id).path) {
            let size = CGSize(width: 240, height: 360)
            image = UIGraphicsImageRenderer(size: size).image { _ in
                let scale = max(size.width / img.size.width, size.height / img.size.height)
                let w = img.size.width * scale, h = img.size.height * scale
                img.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
        } else {
            let view = Group {
                if let s = SeriesBook(title: d.title) { SeriesCover(book: s, width: 120) } else { GeneratedCover(doc: d, width: 120) }
            }
            .frame(width: 120, height: 180)
            let r = ImageRenderer(content: view)
            r.scale = 2
            image = r.uiImage
        }
        if let data = image?.jpegData(compressionQuality: 0.85) { try? data.write(to: out, options: .atomic) }
    }
}

/// Keeps the app running in the background until `end()` (or until iOS says the time is up).
@MainActor
private final class BackgroundHold {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// A quick action from the app icon or a wisepath:// link, waiting for the library to perform it.
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()
    var pending: String?

    static func install(current: DocumentRecord?) {
        var items: [UIApplicationShortcutItem] = []
        if let c = current {
            items.append(UIApplicationShortcutItem(type: "resume", localizedTitle: "Kaldığın yerden dinle", localizedSubtitle: c.title,
                                                   icon: UIApplicationShortcutIcon(systemImageName: "play.fill")))
        }
        items.append(UIApplicationShortcutItem(type: "bike", localizedTitle: "Bisiklet modu", localizedSubtitle: "Yolda · GPS",
                                               icon: UIApplicationShortcutIcon(systemImageName: "bicycle")))
        items.append(UIApplicationShortcutItem(type: "walk", localizedTitle: "Yürüyüş modu", localizedSubtitle: "Yolda · GPS",
                                               icon: UIApplicationShortcutIcon(systemImageName: "figure.walk")))
        items.append(UIApplicationShortcutItem(type: "music", localizedTitle: "Müzik modu", localizedSubtitle: nil,
                                               icon: UIApplicationShortcutIcon(systemImageName: "music.note")))
        UIApplication.shared.shortcutItems = items
    }
}

/// Hands a quick action chosen on the app icon to `QuickActions`, at a cold start and while running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { Task { @MainActor in QuickActions.shared.pending = item.type } }
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in QuickActions.shared.pending = shortcutItem.type }
        completionHandler(true)
    }
}
