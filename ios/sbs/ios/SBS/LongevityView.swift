// Uzun Ömür: where things stand, area by area (lab values and habits), and the assessments still open.
// There is no single invented score here: every petal comes from measured values.
import SwiftUI

struct LongevityView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: Health
    @State private var picked: String?
    @State private var showAll = false

    var body: some View {
        let d = Derived(store, health)
        let petals = d.petals
        let open = d.assessments
        let done = open.filter(\.done).count
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        pill("Genel bakış", "\(petals.filter { $0.tone == .good }.count) alan iyi", "camera.macro", .calm)
                        pill("Bakılacak", "\(petals.filter { $0.tone == .attention || $0.tone == .watch }.count) alan", "exclamationmark.circle", .watch)
                    }
                    PetalWheel(items: petals, selected: picked) { item in picked = picked == item.id ? nil : item.id }
                        .padding(.horizontal, 26).padding(.top, 4)
                        .overlay {
                            Image(systemName: "heart.fill").font(.title2).foregroundStyle(Color.heart.opacity(0.85))
                        }
                    if let p = petals.first(where: { $0.id == picked }) {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TileIcon(symbol: p.symbol, color: p.color, size: 30)
                                    Text(p.name).font(.headline)
                                    Spacer()
                                    Text(p.tone.areaLabel).font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(p.tone.color.opacity(0.16), in: Capsule()).foregroundStyle(p.tone.color)
                                }
                                Text(p.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if d.state.areas.contains(where: { $0.id == p.id }) {
                                    NavigationLink { MarkerList(state: d.state, area: p.id) } label: {
                                        Label("Göstergeleri aç", systemImage: "chevron.right").font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nerede duruyorsun").font(.title2.bold())
                        Text(d.standing).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    legend
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Kalan değerlendirmeler").font(.headline)
                            Spacer()
                            Button(showAll ? "Daralt" : "Hepsini göster") { withAnimation { showAll.toggle() } }.font(.subheadline)
                        }
                        ProgressView(value: Double(done), total: Double(max(open.count, 1))).tint(.calm)
                        Text("\(open.count) değerlendirmeden \(done) tanesi tamam").font(.footnote).foregroundStyle(.secondary)
                        Card(padding: 4) {
                            VStack(spacing: 0) {
                                ForEach(showAll ? open : open.filter { !$0.done }) { a in
                                    HStack(spacing: 12) {
                                        Image(systemName: a.done ? "checkmark.circle.fill" : "circle").foregroundStyle(a.done ? Color.good : Color.secondary)
                                        Image(systemName: a.symbol).frame(width: 22).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(a.title).font(.subheadline.weight(.medium))
                                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                }
                            }
                        }
                    }
                    let keys = ["ldl", "homa_ir", "hba1c", "triglyceride", "hdl", "crp"].compactMap { d.state.marker($0) }
                    if !keys.isEmpty {
                        SectionTitle(text: "Uzun vadeli göstergeler", trailing: Day.short(d.lastLab))
                        VStack(spacing: 10) { ForEach(keys) { MarkerCard(marker: $0, state: d.state) } }
                    }
                    NavigationLink { ReportView() } label: {
                        Label("Hekim raporu oluştur", systemImage: "doc.richtext").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    Text("SBS tek bir 'sağlık yaşı' sayısı üretmez: böyle bir sayı doğrulanmış bir model ister. Burada gördüğün her alan ölçülmüş değerlerden gelir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
            .sbsGround()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pill(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(color.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.footnote.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach([("Dolu", "iyi yerde"), ("Açık", "sınırda"), ("Çizgi", "bakılacak"), ("Gri", "veri yok")], id: \.0) { k, v in
                VStack(alignment: .leading, spacing: 0) {
                    Text(k).font(.caption2.weight(.semibold))
                    Text(v).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
