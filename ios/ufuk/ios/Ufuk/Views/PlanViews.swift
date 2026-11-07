// Dışarı Planı on the Dışarı tab: this week's places in today's order, the route recorder and the
// recorded routes, and the editor for the person's own places.
import MapKit
import SwiftUI

struct PlanCard: View {
    @EnvironmentObject var s: Store
    @State private var editing = false

    var body: some View {
        let opts = s.outings
        let target = s.spots.map(\.weeklyTarget).reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Bu haftanın planı", symbol: "map")
                Spacer()
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Yerleri düzenle")
            }
            Text("\(min(s.weekVisits.count, target))/\(target) yer · \(s.weekKm.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))) km kayıtlı rota")
                .font(.title3.weight(.semibold))
            ForEach(Array(opts.enumerated()), id: \.element.id) { i, o in row(o, first: i == 0) }
            Text("Sıra: bu hafta eksik olan önce, sonra yağış ve dönüşte kalan ışık. Yerin 150 m yakınına gelince kendiliğinden işaretlenir.")
                .font(.caption2).foregroundStyle(Palette.soft)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        .sheet(isPresented: $editing) { SpotsEditor() }
    }

    private func row(_ o: OutingOption, first: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: o.spot.symbol).font(.title3).frame(width: 36, height: 36).glassPill(tint: first ? .green : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(o.spot.name).font(.callout.weight(.semibold)).lineLimit(1)
                    dots(o)
                }
                Text(o.reason).font(.caption).foregroundStyle(Palette.soft).lineLimit(2)
            }
            Spacer()
            if o.visitedToday {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Bugün gidildi")
            } else {
                Menu {
                    Button("Gittim", systemImage: "checkmark") { s.markVisit(o.spot) }
                    if let c = o.spot.coordinate {
                        Button("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond") {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: c)); item.name = o.spot.name
                            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: o.bike ? MKLaunchOptionsDirectionsModeDefault : MKLaunchOptionsDirectionsModeWalking])
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                .accessibilityLabel("\(o.spot.name) seçenekleri")
            }
        }
    }

    /// Filled dot per visit, empty per remaining one.
    private func dots(_ o: OutingOption) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(o.spot.weeklyTarget, o.done), id: \.self) { i in
                Circle().fill(i < o.done ? Color.green : Color.white.opacity(0.25)).frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("bu hafta \(o.progress)")
    }
}

struct RouteCard: View {
    @EnvironmentObject var s: Store
    @ObservedObject var rec = RouteRecorder.shared
    @State private var shown: RouteRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Rota", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            if rec.recording, let st = rec.started {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(rec.km.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "tr_TR"))) + " km").font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        Text(Fmt.span(ctx.date.timeIntervalSince(st))).font(.title3.monospacedDigit()).foregroundStyle(Palette.soft)
                    }
                }
                if rec.points.count > 1 {
                    Map { MapPolyline(coordinates: rec.points.map { .init(latitude: $0.lat, longitude: $0.lon) }).stroke(.green, lineWidth: 4); UserAnnotation() }
                        .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button { withAnimation { s.finishRoute() } } label: { Label("Bitir ve kaydet", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { rec.start() } label: { Label("Rotayı başlat", systemImage: "record.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green)
                if rec.denied { Text("Konum izni kapalı: Ayarlar › Ufuk › Konum.").font(.caption).foregroundStyle(.orange) }
                Text("Ekran kilitliyken de kaydeder. Geçtiğin kendi yerlerin ziyaret sayılır.").font(.caption2).foregroundStyle(Palette.soft)
            }
            ForEach(s.routes.prefix(8)) { r in
                Button { shown = r } label: {
                    HStack {
                        Image(systemName: r.mode == "bike" ? "bicycle" : "figure.walk").frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.callout.weight(.semibold)).lineLimit(1)
                            Text("\(Fmt.short.string(from: r.start)) \(Fmt.t(r.start)) · \(Fmt.km(r.km * 1000)) · \(r.minutes) dk\(r.temp.map { " · \(Fmt.deg($0))" } ?? "")")
                                .font(.caption).foregroundStyle(Palette.soft)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.soft)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Sil", systemImage: "trash", role: .destructive) { s.removeRoute(r) } }
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard(tint: rec.recording ? .green : nil)
        .sheet(item: $shown) { RouteSheet(route: $0) }
    }
}

struct RouteSheet: View {
    @EnvironmentObject var s: Store
    var route: RouteRecord
    @State private var pts: [RoutePoint] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Map {
                    MapPolyline(coordinates: pts.map { .init(latitude: $0.lat, longitude: $0.lon) }).stroke(.green, lineWidth: 4)
                    ForEach(s.spots.filter { route.spots.contains($0.name) && $0.coordinate != nil }) { sp in
                        Marker(sp.name, systemImage: sp.symbol, coordinate: sp.coordinate!)
                    }
                }
                .frame(minHeight: 320).clipShape(RoundedRectangle(cornerRadius: 18))
                Text("\(Fmt.km(route.km * 1000, digits: 2)) · \(route.minutes) dk · \(route.mode == "bike" ? "bisiklet" : "yürüyüş")").font(.headline)
                if let t = route.temp { Text("\(WMO.word(route.code)) · \(Fmt.deg(t))\(route.rain.map { " · yağış \(Fmt.pct($0))" } ?? "")").font(.callout) }
                if !route.spots.isEmpty { Text("Geçtiğin yerler: " + route.spots.joined(separator: ", ")).font(.callout) }
                Spacer()
            }
            .padding()
            .navigationTitle(Fmt.day.string(from: route.start)).navigationBarTitleDisplayMode(.inline)
            .task { pts = s.routePoints(route) }
        }
    }
}

/// The person's own places: name, symbol, weekly target and where it is on the map.
struct SpotsEditor: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    @State private var spots: [Spot] = []
    @State private var picking: Spot?

    var body: some View {
        NavigationStack {
            Form {
                ForEach($spots) { $sp in
                    Section {
                        TextField("Ad", text: $sp.name)
                        Stepper("Haftada \(sp.weeklyTarget) kez", value: $sp.weeklyTarget, in: 0...7)
                        Picker("Simge", selection: $sp.symbol) {
                            ForEach(Spot.symbols, id: \.self) { Image(systemName: $0).tag($0) }
                        }
                        Button { picking = sp } label: {
                            HStack {
                                Label("Haritada yeri", systemImage: "mappin.and.ellipse")
                                Spacer()
                                Text(sp.coordinate == nil ? "işaretlenmedi" : "işaretli").foregroundStyle(sp.coordinate == nil ? .orange : .secondary)
                            }
                        }
                    }
                }
                .onDelete { spots.remove(atOffsets: $0) }
                Section {
                    Button("Yer ekle", systemImage: "plus") { spots.append(Spot(name: "Yeni yer", symbol: "mappin", weeklyTarget: 1)) }
                } footer: { Text("Ufuk her gün bu yerleri, bu hafta eksik kalanı öne alarak sıralar.") }
            }
            .navigationTitle("Yerlerim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Kaydet") { s.saveSpots(spots); dismiss() } }
            }
            .onAppear { if spots.isEmpty { spots = s.spots } }
            .sheet(item: $picking) { sp in
                PlacePicker(title: sp.name, start: sp.coordinate ?? s.home?.coordinate ?? s.commutePoint) { p in
                    if let i = spots.firstIndex(where: { $0.id == sp.id }) { spots[i].lat = p.lat; spots[i].lon = p.lon }
                }
            }
        }
    }
}
