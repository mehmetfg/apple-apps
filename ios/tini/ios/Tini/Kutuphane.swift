import SwiftUI
import UniformTypeIdentifiers

struct KutuphaneEkrani: View {
    @EnvironmentObject var calar: Calar
    @Environment(\.dismiss) private var kapat
    enum Sekme: String, CaseIterable { case albumler = "Albümler", sanatcilar = "Sanatçılar", parcalar = "Parçalar", sira = "Sıra" }
    @AppStorage("kutuphaneSekme") private var sekme: Sekme = .albumler
    @State private var arama = ""
    @State private var dosyaSec = false
    @State private var klasorSec = false
    @State private var mesaj: String?
    @State private var esitleniyor = false

    private var suzulmus: [Parca] {
        guard !arama.isEmpty else { return calar.parcalar }
        return calar.parcalar.filter {
            $0.baslik.localizedCaseInsensitiveContains(arama) || $0.sanatci.localizedCaseInsensitiveContains(arama)
                || $0.album.localizedCaseInsensitiveContains(arama)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $sekme) {
                    ForEach(Sekme.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.bottom, 8)
                Group {
                    if calar.parcalar.isEmpty && !calar.taraniyor {
                        bos
                    } else {
                        switch sekme {
                        case .albumler: AlbumIzgarasi(albumler: Katalog.albumler(suzulmus))
                        case .sanatcilar: SanatciListesi(parcalar: suzulmus)
                        case .parcalar: ParcaListesi(parcalar: suzulmus, numara: false)
                        case .sira: SiraListesi()
                        }
                    }
                }
            }
            .searchable(text: $arama, prompt: "Parça, sanatçı, albüm")
            .navigationTitle("Kitaplık")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Kapat") { kapat() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { dosyaSec = true } label: { Label("Dosya ekle", systemImage: "plus") }
                        Button { klasorSec = true } label: {
                            Label(Depo.bagliKlasorVar ? "Kaynak klasörü değiştir" : "Klasör bağla (iCloud Drive)", systemImage: "folder.badge.plus")
                        }
                        if Depo.bagliKlasorVar {
                            Button { esitle() } label: { Label("Şimdi eşitle (\(Depo.bagliKlasorAdi ?? ""))", systemImage: "arrow.triangle.2.circlepath") }
                            Button(role: .destructive) { Depo.klasorBaginiKaldir(); mesaj = "Klasör bağı kaldırıldı." } label: {
                                Label("Klasör bağını kaldır", systemImage: "folder.badge.minus")
                            }
                        }
                        Button { calar.yenile() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    } label: { Image(systemName: "plus.circle") }
                }
            }
            .overlay(alignment: .bottom) {
                if let mesaj {
                    Text(mesaj).font(.footnote).padding(10).background(.regularMaterial, in: Capsule()).padding()
                        .onTapGesture { self.mesaj = nil }
                } else if calar.taraniyor || esitleniyor {
                    HStack(spacing: 8) { ProgressView(); Text(esitleniyor ? "Eşitleniyor…" : "Taranıyor…") }
                        .font(.footnote).padding(10).background(.regularMaterial, in: Capsule()).padding()
                }
            }
            .fileImporter(isPresented: $dosyaSec, allowedContentTypes: [.audio], allowsMultipleSelection: true) { s in
                guard case .success(let urller) = s else { return }
                var n = 0
                for u in urller {
                    let e = u.startAccessingSecurityScopedResource()
                    if (try? Depo.iceriAl(u)) == true { n += 1 }
                    if e { u.stopAccessingSecurityScopedResource() }
                }
                mesaj = "\(n) dosya eklendi."
                calar.yenile()
            }
            .fileImporter(isPresented: $klasorSec, allowedContentTypes: [.folder]) { s in
                guard case .success(let u) = s else { return }
                do { try Depo.klasorBagla(u); esitle() } catch { mesaj = "Klasör bağlanamadı." }
            }
        }
    }

    private var bos: some View {
        ContentUnavailableView {
            Label("Kitaplık boş", systemImage: "music.note.list")
        } description: {
            Text("Mac'te iCloud Drive/Fon klasörüne FLAC, ALAC, WAV ya da MP3 at, burada bir kez “Klasör bağla”. Albüm klasörleri korunur. Ya da Dosyalar › iPhone'umda › Tını klasörüne taşı.")
        } actions: {
            Button("Klasör bağla") { klasorSec = true }.buttonStyle(.borderedProminent)
            Button("Dosya ekle") { dosyaSec = true }
        }
    }

    private func esitle() {
        esitleniyor = true
        Task.detached {
            let s = Depo.esitle()
            await MainActor.run {
                esitleniyor = false
                mesaj = s.hatalar.isEmpty ? "\(s.yeni) yeni parça." : "\(s.yeni) yeni · \(s.hatalar.count) alınamadı"
                Calar.shared.yenile()
            }
        }
    }
}

struct AlbumIzgarasi: View {
    let albumler: [Album]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                ForEach(albumler) { a in
                    NavigationLink(value: a) {
                        VStack(alignment: .leading, spacing: 4) {
                            KapakGorunumu(parca: a.kapak, kose: 8).aspectRatio(1, contentMode: .fit)
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            Text(a.ad).font(.subheadline.weight(.medium)).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(a.sanatci).lineLimit(1)
                                if a.parcalar.first?.kayipsiz == true { BicimRozeti(bicim: a.bicim, kucuk: true) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationDestination(for: Album.self) { AlbumEkrani(album: $0) }
    }
}

struct AlbumEkrani: View {
    @EnvironmentObject var calar: Calar
    let album: Album
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    KapakGorunumu(parca: album.kapak, kose: 10).frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    Text(album.ad).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    Text(album.sanatci).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if album.yil > 0 { Text(String(album.yil)) }
                        Text("· \(album.parcalar.count) parça · \(sureYazi(album.sure))")
                        BicimRozeti(bicim: album.bicim, kucuk: true)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button { if let i = album.parcalar.first { calar.karisik = false; calar.cal(i, liste: album.parcalar) } } label: {
                            Label("Çal", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        Button { calar.listeyiKarisikCal(album.parcalar) } label: {
                            Label("Karışık", systemImage: "shuffle").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            ForEach(album.parcalar) { p in
                ParcaSatiri(parca: p, numara: true) { calar.cal(p, liste: album.parcalar) }
            }
        }
        .listStyle(.plain)
    }
}

struct SanatciListesi: View {
    let parcalar: [Parca]
    var body: some View {
        let gruplar = Dictionary(grouping: parcalar, by: \.albumSanatcisi).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        List(gruplar, id: \.key) { s, p in
            NavigationLink {
                AlbumIzgarasi(albumler: Katalog.albumler(p)).navigationTitle(s)
            } label: {
                HStack {
                    KapakGorunumu(parca: p.first { $0.kapak != nil }, kose: 22).frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text(s)
                        Text("\(Set(p.map(\.album)).count) albüm · \(p.count) parça").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ParcaListesi: View {
    @EnvironmentObject var calar: Calar
    let parcalar: [Parca]
    var numara: Bool
    var body: some View {
        List {
            if parcalar.count > 1 {
                Button { calar.listeyiKarisikCal(parcalar) } label: { Label("Hepsini karışık çal", systemImage: "shuffle") }
            }
            ForEach(parcalar) { p in
                ParcaSatiri(parca: p, numara: numara) { calar.cal(p, liste: parcalar) }
            }
            .onDelete { i in i.map { parcalar[$0] }.forEach(calar.sil) }
        }
        .listStyle(.plain)
    }
}

struct SiraListesi: View {
    @EnvironmentObject var calar: Calar
    var body: some View {
        List {
            Section {
                Picker("Tekrar", selection: $calar.tekrar) {
                    Text("Tekrar yok").tag(Calar.Tekrar.kapali)
                    Text("Hepsini").tag(Calar.Tekrar.tum)
                    Text("Tek parça").tag(Calar.Tekrar.tek)
                }
                Toggle("Karışık", isOn: $calar.karisik)
            }
            Section("Sıradakiler") {
                ForEach(Array(calar.kuyruk.enumerated()), id: \.offset) { i, p in
                    ParcaSatiri(parca: p, numara: false, vurgu: i == calar.sira) { calar.kuyruktan(i) }
                }
            }
        }
    }
}

struct ParcaSatiri: View {
    @EnvironmentObject var calar: Calar
    let parca: Parca
    var numara: Bool
    var vurgu: Bool? = nil
    let sec: () -> Void
    var body: some View {
        let simdi = vurgu ?? (calar.simdiki == parca)
        Button(action: sec) {
            HStack(spacing: 12) {
                if numara {
                    Text(parca.parcaNo > 0 ? "\(parca.parcaNo)" : "–").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                } else {
                    KapakGorunumu(parca: parca, kose: 5).frame(width: 42, height: 42)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(parca.baslik).lineLimit(1).foregroundStyle(simdi ? Color.accentColor : .primary)
                    Text(numara ? parca.sanatci : "\(parca.sanatci) · \(parca.album)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if simdi && calar.caliyorMu {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(Color.accentColor)
                }
                if parca.yuksekCozunurluk { BicimRozeti(bicim: "Hi-Res", kucuk: true) }
                Text(sureYazi(parca.sure)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BicimRozeti: View {
    let bicim: String
    var kucuk = false
    var body: some View {
        Text(bicim)
            .font(.system(size: kucuk ? 9 : 11, weight: .bold, design: .rounded))
            .padding(.horizontal, kucuk ? 4 : 6).padding(.vertical, kucuk ? 1 : 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1))
            .foregroundStyle(bicim.hasPrefix("FLAC") || bicim.hasPrefix("ALAC") || bicim.hasPrefix("WAV") || bicim == "Hi-Res" ? Color.orange : .secondary)
    }
}
