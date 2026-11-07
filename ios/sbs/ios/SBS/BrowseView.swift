// Göz At: every category in one list, in the manner of the Health app's Browse tab.
import PDMBus
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BrowseView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health

    var body: some View {
        let d = Derived(store, health)
        let s = d.state
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Göz At").font(.largeTitle.bold()).padding(.top, 6)
                    SectionTitle(text: "Sağlık kategorileri")
                    group {
                        row("Göstergeler", "\(s.markers.count) tahlil değeri · son \(Day.short(d.lastLab))", "testtube.2", .calm) { MarkerList(state: s) }
                        row("Analiz", "Noktalı halka, aralığa göre dağılım", "chart.dots.scatter", .sleep) { AnalysisView() }
                        row("Belirtiler ve olaylar", "\(s.episodes.count) olay", "waveform.path.ecg", .attention) { EpisodeList(state: s) }
                        row("Rahatsızlıklar ve protokoller", "\(s.conditions.count) kart: karşılaşınca ne yap", "cross.case.fill", .good) { ConditionList(state: s) }
                        row("Kriz adımları", "Küçük · orta · büyük", "brain.head.profile", .mind) { CrisisView(state: s) }
                        row("Ölçümler", "Kilo, bel çevresi, tansiyon", "ruler.fill", .move) { MeasurementsView() }
                        row("Beslenme ve takviye", "\(s.supplements.count) kalem · Özen", "leaf.fill", .food) { SupplementsView(state: s) }
                    }
                    SectionTitle(text: "Kayıtlar")
                    group {
                        row("Kayıt defteri", "Girdi \(s.counts?["input"] ?? 0) · Süreç \(s.counts?["process"] ?? 0) · Çıktı \(s.counts?["output"] ?? 0) · Varlık \(s.counts?["asset"] ?? 0)", "list.bullet.rectangle.fill", .sleep) { LedgerView(state: s) }
                        row("Belgeler", "\(s.documents.count) belge" + (store.inboxWaiting > 0 ? " · \(store.inboxWaiting) bekliyor" : ""), "doc.fill", Color(light: 0x8E8E93, dark: 0xAEAEB2)) { DocumentsView(state: s) }
                        row("Hekim raporu", "Tek dosya, PDF", "doc.richtext.fill", .heart) { ReportView() }
                    }
                    SectionTitle(text: "Sistem")
                    group { row("Ayarlar ve kaynaklar", store.origin.isEmpty ? "Veri yok" : store.origin, "gearshape.fill", Color(light: 0x636366, dark: 0x8E8E93)) { SettingsView() } }
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Card(padding: 4) { VStack(spacing: 0) { content() } }
    }

    private func row<D: View>(_ title: String, _ detail: String, _ symbol: String, _ color: Color, @ViewBuilder to: @escaping () -> D) -> some View {
        NavigationLink(destination: to) {
            HStack(spacing: 12) {
                TileIcon(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct EpisodeList: View {
    var state: SBSState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Olaylar Kıvılcım'a sesle söylediklerinden çıkar. Ne oldu, öncesinde ne vardı, ne yaptın, ne zaman geçti: dördünü söylersen tekrar ettiğinde ne iyi geldiği görünür.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { if let u = URL(string: "kivilcim://kaydet?topic=Sa%C4%9Fl%C4%B1k") { UIApplication.shared.open(u) } } label: {
                    Label("Sesle kaydet", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                ForEach(state.episodes) { EpisodeCard(episode: $0, state: state) }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Belirtiler ve olaylar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupplementsView: View {
    var state: SBSState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rutini Özen'de kurarsın; SBS yalnız okur. Doz ve takviye kararı hekimle verilir.").font(.subheadline).foregroundStyle(.secondary)
                SectionTitle(text: "Rutin")
                ForEach(state.supplements) { s in
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.subheadline.weight(.semibold))
                            if let dose = s.dose { Text(dose).font(.footnote).foregroundStyle(.secondary) }
                            if let c = s.caution, !c.isEmpty { Text(c).font(.caption).foregroundStyle(Color.watch) }
                        }
                    }
                }
                if !state.medications.isEmpty { SectionTitle(text: "Gerektiğinde kullandıkların") }
                ForEach(state.medications) { m in
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name).font(.subheadline.weight(.semibold))
                            Text([m.use, m.source].compactMap { $0 }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Beslenme ve takviye")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LedgerRow: View {
    var record: LedgerRecord

    static let look: [String: (String, Color)] = [
        "lab": ("testtube.2", .calm), "meal": ("fork.knife", .food), "supplement": ("pills.fill", .food), "water": ("drop.fill", .calm),
        "sleep": ("bed.double.fill", .sleep), "workout": ("dumbbell.fill", .move), "walk": ("figure.walk", .move), "ride": ("bicycle", .move),
        "stretch": ("figure.flexibility", .move), "activity": ("figure.walk", .move), "episode": ("waveform.path.ecg", .attention),
        "pain": ("bolt.fill", .attention), "mood": ("face.smiling", .mind), "weight": ("scalemass.fill", .move), "waist": ("ruler.fill", .move),
        "heart_rate": ("heart.fill", .heart), "blood_pressure": ("heart.text.square.fill", .heart), "redflag": ("exclamationmark.triangle.fill", .attention)]

    var body: some View {
        let look = Self.look[record.type] ?? ("circle.fill", .secondary)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: look.0).font(.footnote.weight(.semibold)).foregroundStyle(look.1).frame(width: 26, height: 26)
                .background(look.1.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title).font(.subheadline.weight(.medium))
                Text([Day.dayMonth(record.day), record.source, record.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 6)
            if let v = record.value {
                Text(v.display + (record.unit.map { " " + $0 } ?? "")).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct LedgerView: View {
    var state: SBSState
    @State private var kind = "input"

    var body: some View {
        let text = ["input": "Bedene giren: öğün, takviye, su, uyku.", "process": "Bedenin yaptığı ve yaşadığı: antrenman, yürüyüş, esneme, olay.",
                    "output": "Ölçülen: tahlil değeri, kilo, ağrı, nabız.", "asset": "Kayıtların dayandığı kalıcı şeyler."]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Tür", selection: $kind) {
                    Text("Girdi").tag("input"); Text("Süreç").tag("process"); Text("Çıktı").tag("output"); Text("Varlık").tag("asset")
                }
                .pickerStyle(.segmented)
                Text(text[kind] ?? "").font(.subheadline).foregroundStyle(.secondary)
                if kind == "asset" {
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            asset("Rahatsızlık ve protokol kartı", state.conditions.count, "cross.case.fill")
                            asset("Rutin kalemi", state.supplements.count, "pills.fill")
                            asset("İlaç", state.medications.count, "cross.vial.fill")
                            asset("Belge", state.documents.count, "doc.fill")
                            asset("Gösterge tanımı", state.markers.count, "testtube.2")
                        }
                    }
                } else {
                    let rows = state.ledger.filter { $0.kind == kind }
                    let days = Array(Set(rows.map(\.day))).sorted(by: >)
                    ForEach(days.prefix(60), id: \.self) { day in
                        Text(Day.short(day)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                        Card(padding: 4) { VStack(spacing: 0) { ForEach(rows.filter { $0.day == day }) { LedgerRow(record: $0) } } }
                    }
                    if rows.isEmpty { Text("Bu türde kayıt yok.").foregroundStyle(.secondary).padding(.top, 20) }
                }
                if let src = state.sources {
                    SectionTitle(text: "Kanallar")
                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            ForEach(src.sorted { $0.value.count > $1.value.count }, id: \.key) { name, info in
                                HStack {
                                    Text(name).font(.subheadline.weight(.medium)); Spacer()
                                    Text("\(info.count) kayıt · son \(Day.dayMonth(info.last))").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Kayıt defteri")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func asset(_ name: String, _ n: Int, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color.calm).frame(width: 26)
            Text(name).font(.subheadline.weight(.medium)); Spacer(); Text("\(n)").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct DocumentsView: View {
    var state: SBSState
    @EnvironmentObject private var store: Store
    @State private var picking = false
    @State private var photo: PhotosPickerItem?
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tahlil PDF'i, reçete, epikriz ya da görüntüleme raporu ekle. Dosya vault'a gider; Claude okur, tahlilse değerleri göstergelere işler.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { picking = true } label: { Label("Dosya ekle", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glassProminent)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Fotoğraf", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(.glass)
                }
                if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(Color.good) }
                if store.inboxWaiting > 0 {
                    Text("\(store.inboxWaiting) belge telefonda bekliyor: vault klasörü seçilince gönderilir (Ayarlar).").font(.footnote).foregroundStyle(Color.watch)
                }
                SectionTitle(text: "Arşiv", trailing: "\(state.documents.count)")
                ForEach(state.documents) { doc in
                    Card(padding: 14) {
                        HStack(spacing: 12) {
                            TileIcon(symbol: doc.kind == "lab" ? "testtube.2" : "doc.fill", color: .calm, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title).font(.subheadline.weight(.semibold))
                                Text([Day.short(doc.date), doc.note].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Belgeler")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .image, .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await store.addDocument(from: url, title: ""); note = "Eklendi: \(url.lastPathComponent)" }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await store.addDocument(data: data, title: "Fotoğraf", ext: "jpg")
                    note = "Fotoğraf eklendi."
                }
                photo = nil
            }
        }
    }
}

struct MeasurementsView: View {
    @EnvironmentObject private var health: Health
    @EnvironmentObject private var store: Store
    @State private var weight = ""
    @State private var waist = ""
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ölçümler Apple Sağlık'a yazılır ve oradan okunur. Bel çevresini haftada bir, aynı saatte ölç.").font(.subheadline).foregroundStyle(.secondary)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        field("Kilo", "kg", $weight)
                        field("Bel çevresi", "cm", $waist)
                        Button {
                            let w = Double(weight.replacingOccurrences(of: ",", with: ".")), c = Double(waist.replacingOccurrences(of: ",", with: "."))
                            Task {
                                let ok = await health.save(weightKg: w, waistCm: c)
                                note = ok ? "Apple Sağlık'a yazıldı." : "Yazılamadı: Apple Sağlık izni gerekli (Ayarlar)."
                                if ok {
                                    if let w { store.bus.emit("measure.logged", subject: "measure:weight", data: ["value": .double(w), "unit": "kg"]) }
                                    if let c { store.bus.emit("measure.logged", subject: "measure:waist", data: ["value": .double(c), "unit": "cm"]) }
                                    weight = ""; waist = ""
                                }
                            }
                        } label: { Text("Kaydet").frame(maxWidth: .infinity).padding(.vertical, 4) }
                        .buttonStyle(.glassProminent)
                        .disabled(weight.isEmpty && waist.isEmpty)
                        if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                series("Kilo", "kg", health.weight, .move)
                series("Bel çevresi", "cm", health.waist, .calm)
                series("Büyük tansiyon", "mmHg", health.systolic, .heart)
            }
            .padding(.horizontal, 18).padding(.bottom, 100)
        }
        .sbsGround()
        .navigationTitle("Ölçümler")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ name: String, _ unit: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(name).font(.subheadline.weight(.medium))
            Spacer()
            TextField("—", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90).font(.title3.weight(.semibold))
            Text(unit).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func series(_ name: String, _ unit: String, _ xs: [Sample], _ color: Color) -> some View {
        SectionTitle(text: name, trailing: xs.last.map { "\($0.value.clean) \(unit)" } ?? "Ölçüm yok")
        if xs.count > 1 {
            Card { Sparkline(values: xs.map(\.value), low: nil, high: nil, color: color).frame(height: 70) }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health

    var body: some View {
        Form {
            Section("Veri") {
                LabeledContent("Gösterilen", value: store.origin.isEmpty ? "Yok" : store.origin)
                LabeledContent("Apple Sağlık", value: health.hasAnyData ? "Veri geliyor" : "Veri yok")
                Button("Apple Sağlık iznini sor") { Task { await health.requestAccess(); await health.refresh() } }
                Button("Yenile") { Task { await store.load(); await health.refresh() } }
            }
            PDMSettingsSection(bus: store.bus)
            Section("Nasıl çalışır") {
                Text("Tahliller, olaylar, protokoller ve kayıt defteri Mac'te kurulur ve vault üzerinden gelir. Uyku, hareket, nabız ve ölçümler bu telefondaki Apple Sağlık'tan okunur; biten günlerin özeti vault'a yazılır. SBS teşhis koymaz.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ayarlar ve kaynaklar")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { Task { await store.load(); await store.flushInbox() } }
    }
}
