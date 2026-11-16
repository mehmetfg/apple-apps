// Akış › Gündem and X (2026-11-11): radar.py ranks tech news from open feeds and the X posts the Chrome extension saw
// on screen (people you follow first) into Feed/radar.json. Pins, mutes and hidden items are small files in the vault,
// so the other Mac shows the same page.
import SwiftUI
import AppKit

struct RadarStory: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var source: String
    var source_name: String
    var topic: String
    var title: String
    var url: String
    var summary: String?
    var image: String?
    var published: String?
    var score: Double?
    var x_shares: [String]?
    var x_followed_shares: [String]?
    var title_tr: String?
    var summary_tr: String?
    var shownTitle: String { (title_tr ?? "").isEmpty ? title : title_tr! }
    var shownSummary: String { let t = summary_tr ?? ""; return t.isEmpty ? (summary ?? "") : t }
    var link: URL? { URL(string: url) }
    var shares: [String] { x_shares ?? [] }
    var followedShares: [String] { x_followed_shares ?? [] }
    var publishedDate: Date? { published.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

struct RadarPost: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var status: String
    var url: String
    var author: String
    var handle: String
    var text: String
    var text_tr: String?
    var links: [String]?
    var image: String?
    var likes: Int?
    var reposts: Int?
    var replies: Int?
    var views: Int?
    var posted: String?
    var followed: Bool?
    var pinned: Bool?
    var liked: Bool?
    var topic: String
    var score: Double?
    var shownText: String { (text_tr ?? "").isEmpty ? text : text_tr! }
    var link: URL? { URL(string: url) }
    var postedDate: Date? { posted.flatMap { ISO8601DateFormatter().date(from: $0) } }
}

struct RadarAccount: Codable, Identifiable, Hashable, Sendable {
    var handle: String
    var name: String
    var posts: Int
    var followed: Bool
    var pinned: Bool
    var muted: Bool
    var id: String { handle }
}

struct RadarPage: Codable, Sendable {
    var updated: String?
    var fetched: String?
    var topics: [FeedTopic]
    var stories: [RadarStory]
    var posts: [RadarPost]
    var accounts: [RadarAccount]
    var x_last_seen: String?
    var x_followed_count: Int?
    var errors: [String]?
    static let empty = RadarPage(topics: [], stories: [], posts: [], accounts: [])
}

/// "12 sa önce", "3 gün önce": short, for the meta line.
func agoText(_ d: Date?) -> String {
    guard let d else { return "" }
    let m = Int(Date().timeIntervalSince(d) / 60)
    if m < 60 { return "\(max(1, m)) dk önce" }
    if m < 24 * 60 { return "\(m / 60) sa önce" }
    return "\(m / 1440) gün önce"
}

func compactNumber(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1f Mn", Double(n) / 1e6) : n >= 10_000 ? "\(n / 1000) B" : n >= 1000 ? String(format: "%.1f B", Double(n) / 1000) : "\(n)"
}

// MARK: Depo side

extension Depo {
    private var feedFolder: URL { kok.appendingPathComponent("Feed") }

    /// Pin or mute an account (Feed/x-accounts.json); shown at once, ranked again by the next pass.
    func radarAccount(_ handle: String, pin: Bool? = nil, mute: Bool? = nil) {
        let u = feedFolder.appendingPathComponent("x-accounts.json")
        var d = (try? JSONSerialization.jsonObject(with: Data(contentsOf: u))) as? [String: Any] ?? [:]
        var pinned = Set((d["pinned"] as? [String]) ?? []), muted = Set((d["muted"] as? [String]) ?? [])
        let h = handle.lowercased()
        if let pin { if pin { pinned.insert(h); muted.remove(h) } else { pinned.remove(h) } }
        if let mute { if mute { muted.insert(h); pinned.remove(h) } else { muted.remove(h) } }
        d["pinned"] = pinned.sorted(); d["muted"] = muted.sorted()
        d["note"] = "Kıvılcım › Akış › X: pinned accounts come first, muted ones never show"
        if let v = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) { try? v.write(to: u, options: .atomic) }
        radarLocal { p in
            for i in p.accounts.indices where p.accounts[i].handle == h {
                p.accounts[i].pinned = pinned.contains(h); p.accounts[i].muted = muted.contains(h)
            }
            for i in p.posts.indices where p.posts[i].handle == h { p.posts[i].pinned = pinned.contains(h) }
            if mute == true { p.posts.removeAll { $0.handle == h } }
        }
        isle(hizli: true)
    }

    /// "Geç" on a story or post: Feed/radar-hidden.json (kept short), gone from the page on every device.
    func radarHide(_ id: String) {
        let u = feedFolder.appendingPathComponent("radar-hidden.json")
        var d = (try? JSONSerialization.jsonObject(with: Data(contentsOf: u))) as? [String: Any] ?? [:]
        var ids = (d["ids"] as? [String]) ?? []
        if !ids.contains(id) { ids.append(id) }
        d["ids"] = Array(ids.suffix(400))
        if let v = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted]) { try? v.write(to: u, options: .atomic) }
        radarLocal { p in p.stories.removeAll { $0.id == id }; p.posts.removeAll { $0.id == id } }
    }

    /// Opens x.com in Chrome (where the extension lives) with the one-minute reading pass asked for.
    func radarScanX() {
        guard let url = URL(string: "https://x.com/home#kivilcim-scan") else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: Views

struct RadarStoryCard: View {
    @EnvironmentObject var depo: Depo
    let s: RadarStory
    let topicName: String
    var selected = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(s.source_name).font(.callout.weight(.semibold)).foregroundStyle(Ink.ember)
                    Text(topicName).font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Ink.surface2)).foregroundStyle(Ink.secondary)
                    Text(agoText(s.publishedDate)).font(.caption).foregroundStyle(Ink.faint)
                }
                Text(s.shownTitle).font(Ink.serif(.title3, .semibold)).fixedSize(horizontal: false, vertical: true)
                if s.title_tr != nil { Text(s.title).font(.caption).foregroundStyle(Ink.faint).lineLimit(1) }
                if !s.shownSummary.isEmpty, s.shownSummary != s.shownTitle {
                    Text(s.shownSummary).font(.callout).foregroundStyle(Ink.secondary).lineLimit(2)
                }
                if !s.shares.isEmpty {
                    Label(sharesText, systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: "#1D9BF0"))
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button { s.link.map { _ = NSWorkspace.shared.open($0) } } label: { Image(systemName: "arrow.up.right.square") }
                    .help("Aç")
                Button { depo.radarHide(s.id) } label: { Image(systemName: "eye.slash") }.help("Geç: bir daha gösterme")
            }
            .buttonStyle(.borderless).font(.title3)
        }
        .padding(14)
        .background(selected ? Ink.ember.opacity(0.08) : Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Ink.ember : Ink.line, lineWidth: selected ? 1.5 : 1) }
        .contentShape(Rectangle())
    }

    private var sharesText: String {
        let f = s.followedShares
        let who = (f.isEmpty ? s.shares : f).prefix(3).map { "@" + $0 }.joined(separator: ", ")
        return f.isEmpty ? "X'te paylaşıldı: \(who)" : "Takip ettiklerin paylaştı: \(who)" + (s.shares.count > 3 ? " +\(s.shares.count - 3)" : "")
    }
}

struct RadarPostCard: View {
    @EnvironmentObject var depo: Depo
    let p: RadarPost
    let topicName: String
    var selected = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if p.pinned == true { Image(systemName: "pin.fill").foregroundStyle(Ink.gold) }
                Text(p.author).font(.callout.weight(.bold))
                Text("@\(p.handle)").font(.callout).foregroundStyle(Ink.secondary)
                if p.followed == true { Text("takip").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: "#1D9BF0").opacity(0.15))).foregroundStyle(Color(hex: "#1D9BF0")) }
                if p.liked == true { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
                Text(agoText(p.postedDate)).font(.caption).foregroundStyle(Ink.faint)
                Spacer()
                Text(topicName).font(.caption).foregroundStyle(Ink.secondary)
            }
            Text(p.shownText).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true).lineLimit(7)
            if p.text_tr != nil { Text(p.text).font(.caption).foregroundStyle(Ink.faint).lineLimit(2) }
            if let l = p.links, !l.isEmpty {
                Text(l.joined(separator: " · ")).font(.caption).foregroundStyle(Ink.ember).lineLimit(1)
            }
            HStack(spacing: 14) {
                metric("bubble.left", p.replies); metric("arrow.2.squarepath", p.reposts)
                metric("heart", p.likes); metric("chart.bar", p.views)
                Spacer()
                Button { p.link.map { _ = NSWorkspace.shared.open($0) } } label: { Label("X'te aç", systemImage: "arrow.up.right") }
                Menu {
                    Button(p.pinned == true ? "Sabitlemeyi kaldır" : "@\(p.handle) hep önde olsun") { depo.radarAccount(p.handle, pin: !(p.pinned == true)) }
                    Button("@\(p.handle) bir daha görünmesin") { depo.radarAccount(p.handle, mute: true) }
                    Divider()
                    Button("Bu postu geç") { depo.radarHide(p.id) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .font(.callout).buttonStyle(.borderless)
        }
        .padding(14)
        .background(selected ? Ink.ember.opacity(0.08) : Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Ink.ember : Ink.line, lineWidth: selected ? 1.5 : 1) }
        .contentShape(Rectangle())
    }

    private func metric(_ symbol: String, _ n: Int?) -> some View {
        HStack(spacing: 3) { Image(systemName: symbol); Text(compactNumber(n ?? 0)).monospacedDigit() }
            .font(.caption).foregroundStyle(Ink.secondary)
    }
}

/// Who the X list is made of: pinned first, then the followed ones; pin or mute from here.
struct RadarAccounts: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("X hesapları").font(Ink.serif(.title2, .bold))
                Spacer()
                Button("Tamam") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text("Sabitlenen hesabın her postu öne çıkar; susturulan hiç görünmez. Takip bilgisi X'teki “Takip edilenler” sekmesinden öğrenilir. Ayarlar vault'ta durur: öteki Mac'te de geçerli.")
                .font(.callout).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
            List(depo.radar.accounts) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.body.weight(.medium))
                        Text("@\(a.handle) · \(a.posts) post" + (a.followed ? " · takip" : "")).font(.caption).foregroundStyle(Ink.secondary)
                    }
                    Spacer()
                    Toggle("Sabitle", isOn: Binding(get: { a.pinned }, set: { depo.radarAccount(a.handle, pin: $0) }))
                    Toggle("Sustur", isOn: Binding(get: { a.muted }, set: { depo.radarAccount(a.handle, mute: $0) }))
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 340)
        }
        .padding(20)
        .frame(width: 560)
    }
}

struct RadarStoryDetail: View {
    @EnvironmentObject var depo: Depo
    let s: RadarStory
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(s.source_name) · \(agoText(s.publishedDate))").font(.callout).foregroundStyle(Ink.secondary)
            if let i = s.image, !i.isEmpty {
                FeedPicture(item: FeedItem(id: s.id, source: s.source, community: s.source_name, topic: s.topic, title: s.title,
                                           url: s.url, status: "open", image: i), height: 230)
            }
            Text(s.shownTitle).font(Ink.serif(.title, .bold)).textSelection(.enabled)
            if s.title_tr != nil { Text(s.title).font(.callout).foregroundStyle(Ink.secondary).textSelection(.enabled) }
            if !s.shownSummary.isEmpty { Text(s.shownSummary).font(Ink.serif(.body)).textSelection(.enabled) }
            if !s.shares.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("X'te paylaşanlar").font(.headline)
                    Text(s.shares.map { "@" + $0 + (s.followedShares.contains($0) ? " (takip)" : "") }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(Ink.secondary)
                }
            }
            HStack(spacing: 10) {
                Button("Bağlantıyı aç") { s.link.map { _ = NSWorkspace.shared.open($0) } }.buttonStyle(.borderedProminent)
                Button("Geç") { depo.radarHide(s.id) }
            }
        }
    }
}

struct RadarPostDetail: View {
    @EnvironmentObject var depo: Depo
    let p: RadarPost
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(p.author).font(.title3.weight(.bold))
                Text("@\(p.handle)").foregroundStyle(Ink.secondary)
                if p.followed == true { Text("· takip ediyorsun").foregroundStyle(Ink.secondary) }
            }
            if let i = p.image, !i.isEmpty {
                FeedPicture(item: FeedItem(id: p.id, source: "x", community: "X", topic: p.topic, title: "", url: p.url, status: "open", image: i), height: 260)
            }
            Text(p.shownText).font(Ink.serif(.title3)).textSelection(.enabled)
            if p.text_tr != nil {
                DisclosureGroup("Özgün metin") { Text(p.text).font(.callout).foregroundStyle(Ink.secondary).textSelection(.enabled).padding(.top, 4) }
            }
            Text("\(compactNumber(p.likes ?? 0)) beğeni · \(compactNumber(p.reposts ?? 0)) paylaşım · \(compactNumber(p.replies ?? 0)) yanıt · \(compactNumber(p.views ?? 0)) görüntülenme")
                .font(.callout).foregroundStyle(Ink.secondary)
            ForEach(p.links ?? [], id: \.self) { l in
                Button(l) { URL(string: l.hasPrefix("http") ? l : "https://" + l).map { _ = NSWorkspace.shared.open($0) } }.buttonStyle(.link)
            }
            HStack(spacing: 10) {
                Button("X'te aç") { p.link.map { _ = NSWorkspace.shared.open($0) } }.buttonStyle(.borderedProminent)
                Button(p.pinned == true ? "Sabitlemeyi kaldır" : "Hesabı sabitle") { depo.radarAccount(p.handle, pin: !(p.pinned == true)) }
                Button("Geç") { depo.radarHide(p.id) }
            }
        }
    }
}
