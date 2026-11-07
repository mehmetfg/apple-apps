// Ayarlar: home and work on the map, commute and lunch times, notification times, sources.
import MapKit
import PDMBus
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    @State private var picking: String?
    @State private var attribution: (logo: URL, legal: URL)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Yerler") {
                    placeRow("Ev", s.home, "house.fill")
                    placeRow("İş", s.work, "briefcase.fill")
                }
                Section {
                    DatePicker("Evden çıkış", selection: minutesBinding($s.morningDepart), displayedComponents: .hourAndMinute)
                    DatePicker("İşten çıkış", selection: minutesBinding($s.eveningDepart), displayedComponents: .hourAndMinute)
                    Stepper("Yolculuk \(s.rideMinutes) dk", value: $s.rideMinutes, in: 10...90, step: 5)
                    Stepper("Ortalama hız \(Int(s.rideSpeed)) km/sa", value: $s.rideSpeed, in: 10...30, step: 1)
                } header: { Text("Bisiklet") } footer: { Text("Sabah 07–09, akşam 16–19 penceresi bu saatlerin çevresinde taranır; hız bisiklette hissedilen sıcaklığa girer.") }
                Section("Öğle arası") {
                    DatePicker("Başlangıç", selection: minutesBinding($s.lunchStart), displayedComponents: .hourAndMinute)
                    DatePicker("Bitiş", selection: minutesBinding($s.lunchEnd), displayedComponents: .hourAndMinute)
                }
                Section {
                    DatePicker("Sabah kararı", selection: minutesBinding($s.notifyMorning), displayedComponents: .hourAndMinute)
                    DatePicker("Kararma saati", selection: minutesBinding($s.notifyDusk), displayedComponents: .hourAndMinute)
                    DatePicker("Yarının doğuşu", selection: minutesBinding($s.notifySunrise), displayedComponents: .hourAndMinute)
                    Toggle("Yolculuktan sonra sor", isOn: $s.askFeedback)
                    Toggle("Hafta sonu da sür", isOn: $s.weekendRides)
                } header: { Text("Bildirimler") } footer: { Text("Kararma bildirimi 16–19 yağış penceresini de taşır. Ani değişim uyarısı çıkışından en çok 3 saat önce gelir.") }
                Section("Apple Sağlık") {
                    Button("Okuma izni ver") { Task { await HealthReader.shared.requestAccess(); await s.loadInsights(force: true) } }
                }
                PDMSettingsSection(bus: s.bus)
                Section {
                    LabeledContent("Open-Meteo", value: "ECMWF · ICON · GFS + topluluk")
                    LabeledContent("Apple Hava", value: appleText)
                    LabeledContent("Radar", value: "RainViewer")
                    if let a = attribution {
                        Link(destination: a.legal) {
                            AsyncImage(url: a.logo) { $0.resizable().scaledToFit() } placeholder: { Text(" Weather") }.frame(height: 14)
                        }
                    }
                } header: { Text("Kaynaklar") } footer: { Text("Yağış ihtimali üç modelin 15 dakikalık tahmini, topluluk üyelerinin oranı ve Apple'ın saatlik ihtimalinin ağırlıklı ortalamasıdır; kaynaklar ayrıştıkça güven düşer.") }
            }
            .navigationTitle("Ayarlar")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Tamam") { dismiss() } } }
            .sheet(item: Binding(get: { picking.map { PickTarget(id: $0) } }, set: { picking = $0?.id })) { t in
                PlacePicker(title: t.id, start: (t.id == "Ev" ? s.home : s.work)?.coordinate ?? s.commutePoint) { p in
                    if t.id == "Ev" { s.home = p } else { s.work = p }
                    Task { await s.refresh(); await s.loadPlaces() }
                }
            }
            .task { attribution = await AppleWeather.attribution() }
            .onDisappear { Task { s.rebuild(); s.writeSnapshot(); await Notifier.schedule(s) } }
        }
    }

    struct PickTarget: Identifiable { var id: String }

    private var appleText: String {
        switch s.appleStatus { case .ok: "açık"; case .unknown: "bekleniyor"; case .failed: "kapalı" }
    }

    private func placeRow(_ name: String, _ p: SavedPlace?, _ sym: String) -> some View {
        Button { picking = name } label: {
            HStack {
                Label(name, systemImage: sym)
                Spacer()
                Text(p?.name ?? "Seç").foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Pan the map under the pin, or search; "Kaydet" keeps the centre.
struct PlacePicker: View {
    var title: String
    var start: CLLocationCoordinate2D
    var done: (SavedPlace) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var name = ""

    init(title: String, start: CLLocationCoordinate2D, done: @escaping (SavedPlace) -> Void) {
        self.title = title; self.start = start; self.done = done
        _position = State(initialValue: .region(MKCoordinateRegion(center: start, latitudinalMeters: 3000, longitudinalMeters: 3000)))
        _center = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) { UserAnnotation() }
                    .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
                    .mapControls { MapUserLocationButton() }
                Image(systemName: "mappin").font(.system(size: 36)).foregroundStyle(.red).offset(y: -18).allowsHitTesting(false)
                VStack {
                    if !results.isEmpty {
                        List(results, id: \.self) { r in
                            Button(r.name ?? "") {
                                if let c = r.placemark.location?.coordinate {
                                    position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 800, longitudinalMeters: 800))
                                    name = r.name ?? ""
                                }
                                results = []
                            }
                        }
                        .frame(maxHeight: 260).listStyle(.plain).clipShape(RoundedRectangle(cornerRadius: 16)).padding()
                    }
                    Spacer()
                }
            }
            .searchable(text: $query, prompt: "Adres ya da yer")
            .onSubmit(of: .search) {
                let r = MKLocalSearch.Request(); r.naturalLanguageQuery = query
                r.region = MKCoordinateRegion(center: center, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
                Task { results = (try? await MKLocalSearch(request: r).start().mapItems) ?? [] }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        done(SavedPlace(name: name.isEmpty ? title : name, lat: center.latitude, lon: center.longitude)); dismiss()
                    }
                }
            }
            .onAppear { Location.shared.request() }
        }
    }
}

struct FeedbackSheet: View {
    @EnvironmentObject var s: Store
    @Environment(\.dismiss) private var dismiss
    var kind: LegKind
    @State private var baseLayer = false
    @State private var mood: Int?

    var body: some View {
        let leg = kind == .morning ? s.morning : s.evening
        VStack(spacing: 20) {
            Text(kind == .morning ? "Sabah yolu nasıldı?" : "Dönüş nasıldı?").font(.title2.weight(.semibold))
            if let f = leg?.feel { Text("Ufuk'un hesabı: bisiklette \(Fmt.deg(f))").foregroundStyle(.secondary) }
            Toggle("İçlik giymiştim", isOn: $baseLayer).padding(.horizontal)
            HStack(spacing: 12) {
                ForEach(Feel.allCases, id: \.self) { f in
                    Button {
                        s.addFeedback(f, leg: kind, baseLayer: baseLayer, mood: mood); dismiss()
                    } label: {
                        VStack(spacing: 8) { Image(systemName: f.symbol).font(.title); Text(f.label).font(.callout.weight(.semibold)) }
                            .frame(maxWidth: .infinity, minHeight: 90)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            VStack(spacing: 6) {
                Text("Enerjin (isteğe bağlı)").font(.footnote).foregroundStyle(.secondary)
                Picker("Enerji", selection: $mood) {
                    Text("—").tag(Int?.none)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.segmented).padding(.horizontal)
            }
        }
        .padding(.vertical, 24)
        .presentationDetents([.medium])
        .onAppear { baseLayer = leg?.baseLayer ?? false }
    }
}
