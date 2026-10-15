// Navigation state shared by the iPhone tab bar and the Mac sidebar.
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today, timeline, library, apps, search
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Bugün"
        case .timeline: return "Akış"
        case .library: return "Kitaplık"
        case .apps: return "Uygulamalar"
        case .search: return "Ara"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.horizon.fill"
        case .timeline: return "calendar.day.timeline.left"
        case .library: return "square.stack.3d.up.fill"
        case .apps: return "app.badge.fill"
        case .search: return "magnifyingglass"
        }
    }
}

@MainActor
final class Router: ObservableObject {
    @Published var section: AppSection = .today
    @Published var stacks: [AppSection: NavigationPath] = [:]
    @Published var composeKind: NoteKind?
    @Published var showVoice = false
    @Published var showSettings = false

    func path(_ s: AppSection) -> Binding<NavigationPath> {
        Binding(get: { self.stacks[s] ?? NavigationPath() }, set: { self.stacks[s] = $0 })
    }

    func open(_ path: String) {
        var p = stacks[section] ?? NavigationPath()
        p.append(NoteRoute(path: path))
        stacks[section] = p
    }
}

/// Every pushed screen is declared once here so all sections share it.
struct Destinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: NoteRoute.self) { NoteScreen(path: $0.path) }
            .navigationDestination(for: FolderRoute.self) { FolderScreen(path: $0.path) }
            .navigationDestination(for: AppRoute.self) { AppDetailScreen(appId: $0.id) }
            .navigationDestination(for: DayRoute.self) { DayScreen(day: $0.day) }
    }
}

/// Handles taps on `atrium-note:` links anywhere inside a section.
struct NoteLinkHandler: ViewModifier {
    @EnvironmentObject var store: VaultStore
    @EnvironmentObject var router: Router
    var source: String?

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "atrium-note" else { return .systemAction }
            let raw = url.absoluteString.dropFirst("atrium-note:".count)
            let target = String(raw).removingPercentEncoding ?? String(raw)
            if let path = store.resolve(link: target, from: source) {
                router.open(path)
            } else {
                store.message = "“\(target)” vault'ta yok."
            }
            return .handled
        })
    }
}

extension View {
    func atriumDestinations() -> some View { modifier(Destinations()) }
    func noteLinks(source: String? = nil) -> some View { modifier(NoteLinkHandler(source: source)) }
}
