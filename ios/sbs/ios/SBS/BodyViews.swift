// Rahatsızlıklar, protocol cards ("when it happens, do this"), episodes and the crisis steps.
import SwiftUI

struct EpisodeCard: View {
    var episode: Episode
    var state: SBSState

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(episode.title ?? state.condition(episode.condition)?.name ?? "Olay").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Day.dayMonth(episode.date)).font(.footnote).foregroundStyle(.secondary)
                }
                if let t = episode.text { Text(t).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 6) {
                    tag(Region.name(episode.region), "figure.arms.open")
                    ForEach(episode.triggers ?? [], id: \.self) { tag($0, "bolt.fill") }
                    if let o = episode.outcome { tag(o, "checkmark") }
                }
            }
        }
    }

    private func tag(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.caption2.weight(.medium)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.track.opacity(0.6), in: Capsule())
    }
}

struct ConditionRow: View {
    var condition: Condition
    var state: SBSState

    var body: some View {
        NavigationLink { ConditionDetail(condition: condition, state: state) } label: {
            Card(padding: 14) {
                HStack(spacing: 12) {
                    TileIcon(symbol: condition.region == "mind" ? "brain.head.profile" : "cross.case.fill",
                             color: condition.kind == "open" ? .attention : (condition.region == "mind" ? .mind : .calm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(condition.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(Region.name(condition.region) + (condition.episodeCount > 0 ? " · \(condition.episodeCount) olay · son \(Day.dayMonth(condition.lastEpisode))" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ProtocolView: View {
    var card: ProtocolCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !card.general.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Hemen yap", systemImage: "bolt.heart.fill").font(.subheadline.weight(.bold)).foregroundStyle(Color.calm)
                        ForEach(Array(card.general.enumerated()), id: \.offset) { i, s in Bullet(text: s, color: .calm, symbol: "\(i + 1).circle.fill") }
                    }
                }
            }
            if !card.own.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Senin tecrüben", systemImage: "person.fill.checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Color.good)
                        ForEach(card.own, id: \.self) { Bullet(text: $0, color: .good) }
                    }
                }
            }
            if !card.redFlags.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bekleme, hekime git", systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.bold)).foregroundStyle(Color.attention)
                        ForEach(card.redFlags, id: \.self) { Bullet(text: $0, color: .attention) }
                    }
                }
            }
            if let s = card.source { Text("Kaynak: \(s)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ConditionDetail: View {
    var condition: Condition
    var state: SBSState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(condition.name).font(.title.bold())
                    Text(Region.name(condition.region) + " · " + kindName).font(.subheadline).foregroundStyle(.secondary)
                }
                if !condition.symptoms.isEmpty { chips("Belirtiler", condition.symptoms, .calm) }
                let triggers = Array(Set(condition.triggers + condition.seenTriggers)).sorted()
                if !triggers.isEmpty { chips("Tetikleyenler", triggers, .watch) }
                SectionTitle(text: "Karşılaşınca")
                ProtocolView(card: condition.protocol)
                let eps = state.episodes.filter { $0.condition == condition.id }
                if !eps.isEmpty {
                    SectionTitle(text: "Olaylar", trailing: "\(eps.count)")
                    ForEach(eps) { EpisodeCard(episode: $0, state: state) }
                }
                let ms = condition.markers.compactMap { state.marker($0) }
                if !ms.isEmpty {
                    SectionTitle(text: "Bağlı göstergeler")
                    ForEach(ms) { MarkerCard(marker: $0, state: state) }
                }
                Text("Protokol kendi notlarından ve genel ilk yardım bilgisinden kurulur; hekimin yerine geçmez.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var kindName: String {
        ["chronic": "süregelen", "recurring": "tekrarlayan", "event": "olay", "open": "açık takip"][condition.kind] ?? condition.kind
    }

    private func chips(_ title: String, _ items: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) {
                    Text($0).font(.footnote.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(color.opacity(0.14), in: Capsule()).foregroundStyle(color)
                }
            }
        }
    }
}

struct ConditionList: View {
    var state: SBSState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bir rahatsızlıkla karşılaşınca ne yapacağın burada hazır durur: önce genel ilk yardım, sonra kendi tecrüben, sonra beklememen gereken durumlar.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(state.conditions) { ConditionRow(condition: $0, state: state) }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Rahatsızlıklar ve protokoller")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CrisisView: View {
    var state: SBSState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ruh hâli bozulduğunda düşünmeden bakacağın üç basamak. Taslaktır; kendi cümlelerinle düzeltilebilir.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(state.crisisLevels.enumerated()), id: \.element.id) { i, level in
                    let color: Color = [.good, .watch, .attention][min(i, 2)]
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { ToneDot(tone: [.good, .watch, .attention][min(i, 2)], size: 12); Text(level.name).font(.headline) }
                            Text(level.when).font(.footnote).foregroundStyle(.secondary)
                            ForEach(Array(level.steps.enumerated()), id: \.offset) { j, s in Bullet(text: s, color: color, symbol: "\(j + 1).circle.fill") }
                        }
                    }
                }
                Button { if let u = URL(string: "tel://112") { UIApplication.shared.open(u) } } label: {
                    Label("112'yi ara", systemImage: "phone.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).tint(.attention)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Kriz adımları")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Opens from the body figure: what is recorded for this region and what to do.
struct RegionSheet: View {
    var region: String
    var state: SBSState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let conds = state.conditions.filter { $0.region == region }
                    let eps = state.episodes.filter { $0.region == region }
                    if conds.isEmpty && eps.isEmpty {
                        Text("Bu bölge için kayıt yok. Bir şey olursa Kıvılcım'a sesle söyle.").foregroundStyle(.secondary).padding(.top, 20)
                    }
                    if !conds.isEmpty { SectionTitle(text: "Rahatsızlıklar") }
                    ForEach(conds) { ConditionRow(condition: $0, state: state) }
                    if !eps.isEmpty { SectionTitle(text: "Olaylar") }
                    ForEach(eps) { EpisodeCard(episode: $0, state: state) }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .sbsGround()
            .navigationTitle(Region.name(region))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Wraps its children onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
