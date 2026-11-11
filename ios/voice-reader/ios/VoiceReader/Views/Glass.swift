// Liquid Glass, in one place (2026-11-10: "sistemi elden geçir, liquid glass'ın tüm imkânlarını kullandır").
//
// The rule the system itself follows: glass is the layer of controls that floats over the content; the content (the
// page, the covers, the charts) is not glass. So the reader's two bars float over the text, which runs under them;
// chips, pills and keys are glass that answers the finger; neighbouring pieces share one container so they blend
// and are drawn in one pass. Before iOS 26 each piece falls back to what it was (a flat bar, a material capsule).
//
//   ReaderBarGlass     the reader's top and bottom bars: a floating glass slab tinted with the page's chrome colour
//   GlassCapsule       chips, pills, small keys (optionally tinted, optionally answering the touch)
//   GlassGroup         GlassEffectContainer where it exists
//   GlassPanel         cards and the mini player (MiniPlayer.swift)
//   glassAction()      the main button of a page: the system's prominent glass button
import SwiftUI

struct ReaderBarGlass: ViewModifier {
    let theme: ReaderTheme
    let edge: VerticalEdge

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color(uiColor: theme.chrome).opacity(0.5)), in: .rect(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, 8)
                .padding(edge == .top ? .top : .bottom, 2)
        } else {
            content
                .background(Color(uiColor: theme.chrome).ignoresSafeArea(edges: edge == .top ? .top : .bottom))
                .overlay(alignment: edge == .top ? .bottom : .top) { Rectangle().fill(Color(uiColor: theme.hairline)).frame(height: 0.5) }
        }
    }
}

struct GlassCapsule: ViewModifier {
    var tint: Color? = nil
    var interactive = true
    /// What the piece was before glass (also what it is before iOS 26).
    var fallback: Color = Color.primary.opacity(0.07)

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
            content.glassEffect(interactive ? glass.interactive() : glass, in: .capsule)
        } else {
            content.background(tint ?? fallback, in: Capsule())
        }
    }
}

/// Pieces of glass that stand together: they are drawn in one pass and flow into each other when they come close.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// The page's main action as the system's prominent glass button (a filled button before iOS 26), on the
    /// accent's solid ground (graphite in dark mode, where the silver ink would not carry the white label).
    func glassAction() -> some View { modifier(GlassAction()) }

    /// The text under the bars softens as it nears the edge (iOS 26).
    @ViewBuilder func softScrollEdges() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
}

private struct GlassAction: ViewModifier {
    @Environment(\.accent) private var accent
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(accent.solid)
        } else {
            content.buttonStyle(.borderedProminent).tint(accent.solid)
        }
    }
}
