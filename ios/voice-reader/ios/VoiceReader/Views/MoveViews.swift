// Yolda's always-visible pieces: the mode's icon that moves while you move (the bicycle's wheels turn with the speed,
// the walker steps), the quiet top line (clock · battery · speed; the way's numbers large on a tap), the book switch
// and the one question the calories need (body weight).
import SwiftUI
import UIKit

// MARK: - the icon that moves

/// The bicycle with turning wheels (faster with the speed, still when stopped), or the walking figure stepping.
struct MoveIcon: View {
    let kind: MoveKind
    let speed: Double               // km/h
    var size: CGFloat = 30
    var color: Color = .primary

    var body: some View {
        switch kind {
        case .bike:
            TimelineView(.animation(minimumInterval: 1 / 30, paused: speed < 1)) { ctx in
                BikeShape(angle: Self.angle(ctx.date, speed: speed))
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.6, size / 14), lineCap: .round, lineJoin: .round))
                    .frame(width: size * 1.45, height: size)
            }
        case .walk:
            Image(systemName: "figure.walk")
                .font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(color)
                .symbolEffect(.bounce, options: .repeating.speed(max(0.6, min(2, speed / 4))), isActive: speed >= 1)
                .frame(width: size * 1.1, height: size)
        }
    }

    /// The wheel turns as a 70 cm wheel would at this speed, slowed to a quarter so the eye can follow it.
    private static func angle(_ date: Date, speed: Double) -> Double {
        let revsPerSecond = speed / 3.6 / (0.7 * .pi) / 4
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) * revsPerSecond * 2 * .pi
    }
}

/// Two wheels with spokes at `angle`, the frame, the saddle and the handlebar.
private struct BikeShape: Shape {
    var angle: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let rad = h * 0.3
        let back = CGPoint(x: r.minX + rad + 1, y: r.maxY - rad - 1)
        let front = CGPoint(x: r.maxX - rad - 1, y: back.y)
        for c in [back, front] {
            p.addEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
            for k in 0..<3 {
                let a = angle + Double(k) * .pi / 3
                let dx = cos(a) * rad * 0.82, dy = sin(a) * rad * 0.82
                p.move(to: CGPoint(x: c.x - dx, y: c.y - dy)); p.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
            }
        }
        let pedal = CGPoint(x: r.minX + w * 0.47, y: back.y)
        let seat = CGPoint(x: r.minX + w * 0.38, y: r.minY + h * 0.26)
        let head = CGPoint(x: r.minX + w * 0.70, y: r.minY + h * 0.24)
        p.move(to: back); p.addLine(to: pedal); p.addLine(to: seat); p.addLine(to: back)
        p.move(to: pedal); p.addLine(to: head); p.addLine(to: front)
        p.move(to: seat); p.addLine(to: CGPoint(x: head.x - w * 0.02, y: head.y + h * 0.02))
        p.move(to: CGPoint(x: seat.x - w * 0.07, y: seat.y - h * 0.06)); p.addLine(to: CGPoint(x: seat.x + w * 0.05, y: seat.y - h * 0.06))
        p.move(to: head); p.addLine(to: CGPoint(x: head.x + w * 0.04, y: head.y - h * 0.12))
        return p
    }
}

/// The icon as the mode's button: the view (Yolda · Kinetik · Tam metin · Klasik), switch between bicycle and
/// walking, or leave the mode (only that ends the GPS record). The icon sits outside the menu: a menu's label is
/// drawn once, so a wheel inside it would never turn.
struct MoveModeMenu: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 26
    var color: Color = .primary

    var body: some View {
        let kind = model.settings.moveKind
        ZStack {
            MoveIcon(kind: kind, speed: model.workout.speed, size: size, color: color)
                .allowsHitTesting(false)
            Menu {
                Section("Görünüm") {
                    ForEach(BikeLook.allCases) { look in
                        Button { withAnimation(.smooth(duration: 0.35)) { model.settings.bikeLook = look } } label: {
                            Label(look.name, systemImage: model.settings.bikeLook == look ? "checkmark" : look.symbol)
                        }
                    }
                }
                if kind == .bike {
                    Button { model.startMove(.walk) } label: { Label("Yürüyüşe geç", systemImage: "figure.walk") }
                } else {
                    Button { model.startMove(.bike) } label: { Label("Bisiklete geç", systemImage: "bicycle") }
                }
                Button { model.musicModeShown = true } label: { Label("Müzik modu", systemImage: "music.note") }
                Button(role: .destructive) { model.endMove() } label: {
                    Label("\(kind.name) modundan çık (GPS durur)", systemImage: "xmark.circle")
                }
            } label: {
                Color.clear.frame(width: max(44, size * 1.5), height: max(40, size))
                    .contentShape(Rectangle())
            }
        }
        .frame(minWidth: 44, minHeight: 40)
        .accessibilityLabel("\(kind.name) modu, \(Int(model.workout.speed.rounded())) kilometre")
    }
}

// MARK: - the quiet line at the top

/// The road screen's and the music mode's quiet top (2026-10-28, back to the first Yolda look): the clock and the
/// battery on one line, the speed (in a moving mode) and a label in small faint capitals under it, and, where asked,
/// the book. Time, km and calories are not on screen; a tap shows them large (MoveBoard). Asks for the body weight
/// once, when a moving mode first shows it.
struct RoadStatus: View {
    @Environment(AppModel.self) private var model
    var label: String? = nil
    var book: String? = nil
    var ink: Color = Ride.muted
    var dim: Color = Ride.dim
    @State private var askWeight = false
    @State private var weightText = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let level = UIDevice.current.batteryLevel
            let pct = level < 0 ? nil : Int((level * 100).rounded())
            let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    // the battery always has its place (unknown: a dash), never left out
                    HStack(spacing: 3) {
                        Image(systemName: charging ? "battery.100percent.bolt" : (pct ?? 100) < 20 ? "battery.25percent" : "battery.75percent")
                        Text(pct.map { "%\($0)" } ?? "–")
                    }
                    .foregroundStyle((pct ?? 100) < 10 ? Color.red : (pct ?? 100) < 20 ? Color.orange : ink)
                }
                .font(Ride.mono(12, .medium))
                .foregroundStyle(ink)
                let speed = model.settings.bikeMode ? "\(Int(model.workout.speed.rounded())) km/sa" : nil
                let second = [label, speed].compactMap { $0 }
                if !second.isEmpty {
                    Text(second.joined(separator: " · "))
                        .font(Ride.mono(11, .medium))
                        .textCase(.uppercase)
                        .tracking(1.6)
                        .foregroundStyle(dim)
                }
                if let book {
                    Text(book).font(.system(size: 11)).foregroundStyle(dim).lineLimit(1)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            if model.settings.bikeMode, model.settings.bodyWeight == 0, !UserDefaults.standard.bool(forKey: "v.weightAsked") {
                UserDefaults.standard.set(true, forKey: "v.weightAsked")
                askWeight = true
            }
        }
        .alert("Kalori için kilon", isPresented: $askWeight) {
            TextField("kg", text: $weightText).keyboardType(.numberPad)
            Button("Kaydet") {
                if let kg = Double(weightText.replacingOccurrences(of: ",", with: ".")), kg > 30, kg < 250 { model.settings.bodyWeight = kg }
            }
            Button("Sonra", role: .cancel) {}
        } message: { Text("Kalori kilona, hızına ve eğime göre hesaplanır. Girmezsen 75 kg sayılır; üst satıra dokununca açılan göstergede kaloriye dokunarak sonra da girebilirsin.") }
        .accessibilityElement(children: .combine)
    }
}

/// The way's numbers large in the middle of the screen, gone by themselves after six seconds (a tap hides them
/// sooner): time, km, calories, speed (steps on foot), average and climb.
struct MoveBoard: View {
    @Environment(AppModel.self) private var model
    @Binding var shown: Bool
    @State private var hideTask: Task<Void, Never>?
    @State private var askWeight = false
    @State private var weightText = ""

    var body: some View {
        ZStack {
            if shown {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let w = model.workout.current
                    let walk = model.settings.moveKind == .walk
                    VStack(spacing: 18) {
                        Label(model.settings.moveKind.name, systemImage: model.settings.moveKind.symbol)
                            .font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1.5).textCase(.uppercase)
                            .foregroundStyle(Ride.amber)
                        Grid(horizontalSpacing: 26, verticalSpacing: 20) {
                            GridRow {
                                big(MoveStrip.clock(w.map { ctx.date.timeIntervalSince($0.start) } ?? 0), "süre")
                                big(MoveStrip.km(w?.distance ?? 0), "km")
                            }
                            GridRow {
                                Button { weightText = model.settings.bodyWeight > 0 ? "\(Int(model.settings.bodyWeight))" : ""; askWeight = true } label: {
                                    big("\(Int((w?.calories ?? 0).rounded()))", model.settings.bodyWeight > 0 ? "kcal" : "kcal · kilo ?")
                                }
                                .buttonStyle(.plain)
                                if walk { big("\(w?.steps ?? 0)", "adım") } else { big("\(Int(model.workout.speed.rounded()))", "km/sa") }
                            }
                            GridRow {
                                big(String(format: "%.1f", w?.averageSpeed ?? 0).replacingOccurrences(of: ".", with: ","), "ort. km/sa", small: true)
                                big("\(Int((w?.climb ?? 0).rounded()))", "m tırmanış", small: true)
                            }
                        }
                        if !model.workout.status.isEmpty {
                            Text(model.workout.status).font(.system(size: 12)).foregroundStyle(Ride.muted)
                        }
                    }
                    .padding(26)
                    .background(Ride.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Ride.line, lineWidth: 1))
                    .padding(.horizontal, 20)
                    .onTapGesture { close() }
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .onAppear {
                    hideTask?.cancel()
                    hideTask = Task {
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled, !askWeight else { return }
                        close()
                    }
                }
                .onDisappear { hideTask?.cancel() }
            }
        }
        .alert("Kalori için kilon", isPresented: $askWeight) {
            TextField("kg", text: $weightText).keyboardType(.numberPad)
            Button("Kaydet") {
                if let kg = Double(weightText.replacingOccurrences(of: ",", with: ".")), kg > 30, kg < 250 { model.settings.bodyWeight = kg }
            }
            Button("Sonra", role: .cancel) {}
        } message: { Text("Kalori kilona, hızına ve eğime göre hesaplanır. Girmezsen 75 kg sayılır.") }
    }

    private func close() { withAnimation(.smooth(duration: 0.3)) { shown = false } }

    private func big(_ value: String, _ unit: String, small: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: small ? 30 : 46, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Ride.paper).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ride.muted)
        }
        .frame(minWidth: 120)
        .accessibilityElement(children: .combine)
    }
}

/// The details strip of the Klasik page, shown on a tap and gone by themselves after six seconds.
struct MoveDetails: View {
    @Binding var shown: Bool
    var ink: Color = .primary
    var dim: Color = .secondary
    var background: Color = Color(.systemBackground)
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        if shown {
            MoveStrip(ink: ink, dim: dim)
                .padding(.horizontal, 8)
                .background(background.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation(.smooth) { shown = false } }
                .onAppear {
                    hideTask?.cancel()
                    hideTask = Task {
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled else { return }
                        withAnimation(.smooth(duration: 0.4)) { shown = false }
                    }
                }
                .onDisappear { hideTask?.cancel() }
        }
    }
}

/// Km · time · calories, and steps on foot or speed on the bicycle, and the climb. (The clock and the battery are in
/// the phone's own status bar.)
struct MoveStrip: View {
    @Environment(AppModel.self) private var model
    var ink: Color = .primary
    var dim: Color = .secondary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let w = model.workout.current
            HStack(spacing: 0) {
                cell(Self.km(w?.distance ?? 0), "km")
                cell(Self.clock(w.map { ctx.date.timeIntervalSince($0.start) } ?? 0), "süre")
                cell("\(Int((w?.calories ?? 0).rounded()))", "kcal")
                if model.settings.moveKind == .walk {
                    cell("\(w?.steps ?? 0)", "adım")
                } else {
                    cell("\(Int(model.workout.speed.rounded()))", "km/sa")
                }
                if let w, w.climb >= 1 { cell("\(Int(w.climb.rounded()))", "m ↑") }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
    }

    private func cell(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(unit).font(.system(size: 10, weight: .medium)).foregroundStyle(dim).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func km(_ m: Double) -> String {
        String(format: m < 10_000 ? "%.2f" : "%.1f", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func clock(_ s: Double) -> String {
        let t = Int(s), h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m):\(String(format: "%02d", sec))"
    }
}

// MARK: - switching the book

/// A long press on the library key: the books in progress (the last opened first) and the automations, at the
/// bottom of the screen, without leaving the moving mode. The GPS record goes on.
struct BookSwitchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let recent = model.store.documents
            .filter { $0.id != model.player.documentID && $0.lastOpenedAt != nil && !$0.isFinished }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(8)
        NavigationStack {
            List {
                Section("Kitaba geç") {
                    if recent.isEmpty { Text("Süren başka kitap yok").foregroundStyle(.secondary) }
                    ForEach(Array(recent)) { d in
                        Button { model.switchRequest = d.id; dismiss() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed").foregroundStyle(Ride.amber)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                                    Text("%\(Int(d.progress * 100))").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !model.automations.list.isEmpty || model.automationRun != nil {
                    Section("Otomasyon") {
                        if model.automationRun != nil {
                            Button(role: .destructive) { model.stopAutomation(); dismiss() } label: { Label("Otomasyonu durdur", systemImage: "stop.fill") }
                        } else {
                            ForEach(model.automations.list) { a in
                                Button { model.startAutomation(a, resume: model.automations.resumePoint(for: a) != nil); dismiss() } label: {
                                    Label(a.name, systemImage: "play.fill")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Başka kitaba geç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
