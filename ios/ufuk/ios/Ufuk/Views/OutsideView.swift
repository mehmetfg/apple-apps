// Dışarı: the weekly plan of own places, the route recorder, the radar, the lunch walk with places near work, and the evening ride before dark.
import MapKit
import SwiftUI

struct OutsideView: View {
    @EnvironmentObject var s: Store
    @State private var frames: [RadarFrame] = []
    @State private var frameIndex = 0
    @State private var playing = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PlanCard().rise()
                    RouteCard().rise(0.04)
                    radarCard.rise(0.08)
                    lunchCard.rise(0.12)
                    eveningCard.rise(0.16)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollContentBackground(.hidden)
            .background(SkyBackground(state: s.skyState))
            .navigationTitle("Dışarı")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                frames = await Radar.frames()
                frameIndex = max(0, (frames.lastIndex { !$0.nowcast } ?? frames.count - 1))
                await s.loadPlaces()
            }
            .task(id: playing) {
                // frames may still be loading when this starts; keep waiting instead of ending the loop
                while playing, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(frames.isEmpty ? 300 : 700))
                    if !frames.isEmpty { frameIndex = (frameIndex + 1) % frames.count }
                }
            }
        }
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Yağmur radarı", symbol: "dot.radiowaves.left.and.right")
                Spacer()
                if frames.indices.contains(frameIndex) {
                    let f = frames[frameIndex]
                    Text("\(Fmt.t(f.time))\(f.nowcast ? " · tahmin" : "")").font(.caption.monospacedDigit()).foregroundStyle(Palette.soft)
                }
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(playing ? "Durdur" : "Oynat")
            }
            RadarMap(center: s.commutePoint, frame: frames.indices.contains(frameIndex) ? frames[frameIndex] : nil,
                     pins: [s.home.map { .init(lat: $0.lat, lon: $0.lon, title: "Ev") }, s.work.map { .init(lat: $0.lat, lon: $0.lon, title: "İş") }].compactMap { $0 })
                .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if frames.count > 1 {
                Slider(value: Binding(get: { Double(frameIndex) }, set: { frameIndex = Int($0); playing = false }),
                       in: 0...Double(frames.count - 1), step: 1).tint(.white)
            }
            Text("RainViewer · son iki saat").font(.caption2).foregroundStyle(Palette.soft)
        }
        .foregroundStyle(.white).glassCard()
    }

    private var lunchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Öğle arası" + (s.lunch?.slots.first.map { Calendar.current.isDateInTomorrow($0.time) } == true ? " · yarın" : ""), symbol: "figure.walk")
            if let l = s.lunch {
                Text(l.verdict).font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if let st = l.start { Tag(text: "\(Fmt.t(st))'dan", symbol: "clock") }
                    if let f = l.feels { Tag(text: "hissedilen \(Fmt.deg(f))", symbol: "thermometer.medium") }
                }
                RainStrip(slots: l.slots, planned: nil, best: nil, height: 30)
                if s.work == nil { Text("Yer önerisi için işini işaretle.").font(.footnote).foregroundStyle(Palette.soft) }
                ForEach(s.lunchPlaces) { p in PlaceRow(p: p, walking: true) }
            } else {
                Text("Tahmin bekleniyor").foregroundStyle(Palette.soft)
            }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var eveningCard: some View {
        let from = max(Decision.at(.now, s.eveningDepart), .now)
        let light = max(0, Int(((s.sunToday.dusk ?? from).timeIntervalSince(from)) / 60))
        let mid = s.forecast?.slot(at: from)
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Akşam rotası", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            Text(light > 15 ? "Karanlığa \(Fmt.span(TimeInterval(light * 60))) var" : "Bugün ışık bitti").font(.title2.weight(.semibold))
            if let m = mid, let dir = m.windDir {
                Label("Rüzgâr \(Places.compass(dir))dan \(Int(m.wind)) km/sa. Gidişte rüzgârı karşına al, dönüşte arkandan alsın.",
                      systemImage: "wind").font(.callout)
            }
            if let e = s.evening, e.windowMax >= 0.4 {
                Label("Akşam yağış: \(e.verdict)", systemImage: "cloud.rain").font(.callout)
            }
            ForEach(s.eveningPlaces) { p in PlaceRow(p: p, walking: false) }
            if s.eveningPlaces.isEmpty, light > 15 { Text("Yakında park, sahil ya da marina bulunamadı.").font(.footnote).foregroundStyle(Palette.soft) }
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

struct PlaceRow: View {
    var p: PlaceOption
    var walking: Bool
    var body: some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: p.lat, longitude: p.lon)))
            item.name = p.name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDefault])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: p.symbol).font(.title3).frame(width: 32, height: 32).glassPill()
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(p.kind) · \(p.meters >= 1000 ? String(format: "%.1f km", p.meters / 1000) : "\(Int(p.meters)) m") · \(p.minutes) dk\(walking ? " yürüme" : " bisiklet")")
                        .font(.caption).foregroundStyle(Palette.soft)
                    if let n = p.windNote { Text(n).font(.caption2).foregroundStyle(Palette.soft) }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.soft)
            }
        }
        .buttonStyle(.plain)
    }
}
