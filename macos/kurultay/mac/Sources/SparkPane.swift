import AppKit
import SwiftUI

/// Kurultay › Kıvılcım: pick one or more recordings, read their transcripts, ask the council about them.
struct SparkPane: View {
    @EnvironmentObject var council: Council
    @ObservedObject var library: SparkLibrary
    let opened: (String) -> Void

    @State private var query = ""
    @State private var kind = "hepsi"
    @State private var focused: String?
    @State private var title = ""
    @State private var question = ""
    @State private var follow = true
    @State private var closing = true

    private var filtered: [Spark] {
        library.sparks.filter { s in
            (kind == "hepsi" || s.kindLabel == kind)
                && (query.isEmpty || [s.title, s.summary, s.text, s.topic, s.tags.joined(separator: " ")]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var chosen: [Spark] { council.sparkBasket.compactMap { library.spark($0) } }

    private var groups: [(String, [Spark])] {
        let df = DateFormatter(); df.locale = Locale(identifier: "tr_TR"); df.dateFormat = "d MMMM yyyy, EEEE"
        var out: [(String, [Spark])] = []
        for s in filtered {
            let k = df.string(from: s.date)
            if out.last?.0 == k { out[out.count - 1].1.append(s) } else { out.append((k, [s])) }
        }
        return out
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
            VStack(spacing: 0) {
                preview
                Divider()
                composer.padding(16)
            }
            .frame(minWidth: 480)
        }
        .onAppear { library.load() }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Ara: başlık, döküm, konu…", text: $query).textFieldStyle(.roundedBorder)
                Picker("", selection: $kind) {
                    Text("Hepsi").tag("hepsi")
                    ForEach(["Kıvılcım", "Uzun konuşma", "Sesli günlük", "Günlükten", "İşaret"], id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 130)
                Button { library.load() } label: { Image(systemName: "arrow.clockwise") }.help("Kıvılcım dizinini yeniden oku")
            }
            .padding(10)
            if let e = library.error { Text(e).font(.caption).foregroundStyle(.red).padding(.horizontal, 10) }
            List {
                ForEach(groups, id: \.0) { day, items in
                    Section(day) {
                        ForEach(items) { s in SparkRow(spark: s, chosen: council.sparkBasket.contains(s.id), focused: focused == s.id,
                                                       toggle: { toggle(s.id) }, focus: { focused = s.id }) }
                    }
                }
            }
            .listStyle(.inset)
            .overlay { if filtered.isEmpty { ContentUnavailableView("Kayıt yok", systemImage: "waveform") } }
            Text("\(library.sparks.count) kayıt · seçili \(chosen.count)").font(.caption).foregroundStyle(.secondary).padding(6)
        }
    }

    private func toggle(_ id: String) {
        if let i = council.sparkBasket.firstIndex(of: id) { council.sparkBasket.remove(at: i) } else { council.sparkBasket.append(id) }
        focused = id
    }

    // MARK: Preview

    private var preview: some View {
        Group {
            if let id = focused ?? chosen.last?.id, let s = library.spark(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.title).font(.system(size: 24, weight: .bold, design: .serif))
                            Spacer()
                            Button(council.sparkBasket.contains(s.id) ? "Seçimden çıkar" : "Seç") { toggle(s.id) }
                        }
                        HStack(spacing: 8) {
                            Badge(s.kindLabel); Badge(s.durationText)
                            if !s.topic.isEmpty { Badge(s.topic) }
                            Text(s.date.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        let chain = library.chain(of: s.id)
                        if chain.count > 1 {
                            HStack {
                                Text("Bu uzun konuşmanın \(chain.count) parçası var.").font(.callout).foregroundStyle(.secondary)
                                Button("Bütün parçaları seç") { council.addToBasket(chain.map(\.id)) }.buttonStyle(.link)
                            }
                        }
                        if !s.summary.isEmpty {
                            Text(s.summary).font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))
                        }
                        Text(s.text).font(.body).lineSpacing(4).textSelection(.enabled)
                    }
                    .padding(24).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.badge.magnifyingglass").font(.system(size: 40)).foregroundStyle(.tertiary)
                    Text("Soldan bir ya da birkaç kayıt seç").font(.title3)
                    Text("Seçtiğin kayıtların dökümü sorunun altına eklenir; meclis onları bağlam olarak okur.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Composer

    private var composedLength: Int { SparkPrompt.compose(question: question, sparks: chosen, closing: closing).count }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chosen.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(chosen) { s in
                            HStack(spacing: 4) {
                                Text(s.title).lineLimit(1)
                                Button { toggle(s.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                        Button("Temizle") { council.sparkBasket.removeAll() }.buttonStyle(.link).font(.caption)
                    }
                }.scrollIndicators(.hidden)
            }
            HStack {
                TextField("Başlık (isteğe bağlı)", text: $title).textFieldStyle(.roundedBorder)
                Menu("Hazır soru") {
                    ForEach(SparkPrompt.templates, id: \.0) { t in Button(t.0) { question = t.1; if title.isEmpty { title = t.0 } } }
                }.frame(width: 120)
            }
            Composer(text: $question, placeholder: "Bu kayıtlar hakkında meclise ne soralım?") { seats in
                if let id = council.askWithSparks(title: title, question: question, sparkIds: council.sparkBasket, seats: seats, follow: follow, closing: closing) {
                    question = ""; title = ""; council.sparkBasket.removeAll()
                    opened(id)
                }
            }
            .disabled(chosen.isEmpty)
            HStack(spacing: 14) {
                Toggle("Claude takip etsin", isOn: $follow).help("Cevaplar bitince Claude raporu ve tertibi yazar")
                Toggle("Standart kapanış", isOn: $closing).help(SparkPrompt.closing)
                Spacer()
                let long = council.activeSeats.filter { s in s.maxChars.map { composedLength > $0 } ?? false }
                Text("\(composedLength.formatted()) karakter").font(.caption).foregroundStyle(long.isEmpty ? Color.secondary : Color.orange).monospacedDigit()
                if !long.isEmpty { Text("· sınırı aşan: " + long.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.orange) }
            }
            .font(.callout)
            Text("Seçili dökümler dış modellere gönderilir. Kişisel bilgi içeren kaydı seçmeden önce gözden geçir.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct SparkRow: View {
    let spark: Spark
    let chosen: Bool
    let focused: Bool
    let toggle: () -> Void
    let focus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: toggle) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(chosen ? Color.accentColor : .secondary)
            }.buttonStyle(.plain).help(chosen ? "Seçimden çıkar" : "Seç")
            VStack(alignment: .leading, spacing: 3) {
                Text(spark.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(spark.summary.isEmpty ? spark.text : spark.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Text(spark.kindLabel).font(.caption2.weight(.semibold)).foregroundStyle(spark.seconds >= 600 || spark.kind == "journal" ? .indigo : .secondary)
                    if !spark.topic.isEmpty { Text("· \(spark.topic)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Text("\(spark.date.formatted(date: .omitted, time: .shortened)) · \(spark.durationText)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggle)
        .onTapGesture(perform: focus)
        .listRowBackground(focused ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
