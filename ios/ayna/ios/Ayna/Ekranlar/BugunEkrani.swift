// Bugün: anlatılacak şey senin günün. Bugünün fotoğrafları, takvimin, kapıda söylemeye söz verdiğin anlar, Kenar'ın bölümleri.
import EventKit
import Photos
import SwiftUI

struct BugunEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @State private var fotolar: [PHAsset] = []
    @State private var bugunOlay: [EKEvent] = []
    @State private var yarinOlay: [EKEvent] = []
    @State private var fotoIzni = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var takvimIzni = EKEventStore.authorizationStatus(for: .event)
    private let magaza = EKEventStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !merkez.bagli {
                        Button { rota.sekme = 3 } label: {
                            Label("Önce vault klasörünü seç (Ayarlar › Vault) — kayıtlar Mac'e oradan gider.", systemImage: "folder.badge.questionmark")
                                .font(.footnote.weight(.semibold)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.2)))
                        }.buttonStyle(.plain)
                    }
                    anaKart
                    if !merkez.kapiBekleyen.isEmpty { kapiBolumu }
                    fotoBolumu
                    takvimBolumu
                    if !merkez.bekleyenKenar.isEmpty { kenarBolumu }
                    bugunKayitlar
                }
                .padding(18)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Bugün")
            .refreshable { await merkez.esitle(); await yukle() }
            .task { await yukle() }
        }
    }

    private func yukle() async {
        if fotoIzni == .authorized || fotoIzni == .limited {
            let s = PHFetchOptions()
            s.predicate = NSPredicate(format: "creationDate >= %@ AND mediaType == %d", Calendar.current.startOfDay(for: .now) as NSDate, PHAssetMediaType.image.rawValue)
            s.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            s.fetchLimit = 20
            var l: [PHAsset] = []
            PHAsset.fetchAssets(with: s).enumerateObjects { a, _, _ in l.append(a) }
            fotolar = l
        }
        if takvimIzni == .fullAccess {
            let t = Calendar.current
            let bas = t.startOfDay(for: .now)
            let yarin = t.date(byAdding: .day, value: 1, to: bas)!, sonra = t.date(byAdding: .day, value: 2, to: bas)!
            bugunOlay = magaza.events(matching: magaza.predicateForEvents(withStart: bas, end: yarin, calendars: nil)).filter { !$0.isAllDay }
            yarinOlay = magaza.events(matching: magaza.predicateForEvents(withStart: yarin, end: sonra, calendars: nil)).filter { !$0.isAllDay }
        }
    }

    private var anaKart: some View {
        Button { rota.kayit = KayitIstegi(tur: .gun, istem: "Gününü anlat", aciklama: "Bugün ne oldu? Sabahtan akşama, 60-90 saniye. Mükemmel olması gerekmez; kendi kelimelerinle.") } label: {
            HStack(spacing: 16) {
                Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.black)
                    .frame(width: 64, height: 64).background(Circle().fill(Color.ayna))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gününü anlat").font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text("90 saniye, İngilizce. Gece Mac düzeltir, sabah kulağında.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.27), Color(red: 0.05, green: 0.08, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }

    private var kapiBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Baslik(metin: "Kapıda söz verdiklerin", simge: "hand.raised")
            ForEach(merkez.kapiBekleyen, id: \.self) { z in
                Button { merkez.kapiIsteminiKapat(z); rota.kayit = KayitIstegi(tur: .kapi, istem: "\(z.formatted(date: .omitted, time: .shortened)) — ne yapıyordun?", aciklama: Kapi.istem) } label: {
                    satir("\(z.formatted(date: .omitted, time: .shortened)) · ne yapıyordun?", "Tek cümle yeter.", "hand.raised.fill")
                }.buttonStyle(.plain)
            }
        }
    }

    private var fotoBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Baslik(metin: "Bugünün fotoğrafları", simge: "photo.on.rectangle")
            if fotoIzni == .notDetermined {
                Button("Fotoğraflara izin ver — bugün çektiklerin anlatma konusu olur") {
                    Task { fotoIzni = await PHPhotoLibrary.requestAuthorization(for: .readWrite); await yukle() }
                }.font(.footnote)
            } else if fotolar.isEmpty {
                Text("Bugün fotoğraf yok.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(fotolar, id: \.localIdentifier) { a in
                            Button { rota.kayit = KayitIstegi(tur: .an, istem: "Bu fotoğraf (\(a.creationDate?.formatted(date: .omitted, time: .shortened) ?? ""))", aciklama: "Ne görüyorsun, o an ne oldu, nasıl hissettin?", foto: a.localIdentifier) } label: {
                                Kucuk(asset: a).frame(width: 110, height: 140).clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
        }
    }

    private var takvimBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Baslik(metin: "Takvim", simge: "calendar")
            if takvimIzni == .notDetermined {
                Button("Takvime izin ver — bugünü anlat, yarına prova yap") {
                    Task { _ = try? await magaza.requestFullAccessToEvents(); takvimIzni = EKEventStore.authorizationStatus(for: .event); await yukle() }
                }.font(.footnote)
            }
            ForEach(bugunOlay, id: \.eventIdentifier) { e in
                Button { rota.kayit = KayitIstegi(tur: .an, istem: "Bugün: \(e.title ?? "")", aciklama: "Nasıl geçti? Kim vardı, ne konuşuldu?") } label: {
                    satir(e.title ?? "", "Bugün \(e.startDate.formatted(date: .omitted, time: .shortened)) · nasıl geçti?", "clock")
                }.buttonStyle(.plain)
            }
            ForEach(yarinOlay, id: \.eventIdentifier) { e in
                Button { rota.kayit = KayitIstegi(tur: .prova, istem: "Yarın: \(e.title ?? "")", aciklama: "Yarın orada söyleyeceğin üç cümleyi şimdi İngilizce söyle.") } label: {
                    satir(e.title ?? "", "Yarın \(e.startDate.formatted(date: .omitted, time: .shortened)) · prova", "calendar.badge.clock")
                }.buttonStyle(.plain)
            }
            if takvimIzni == .fullAccess, bugunOlay.isEmpty, yarinOlay.isEmpty { Text("Bugün ve yarın takvim boş.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private var kenarBolumu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Baslik(metin: "Kenar'dan", simge: "text.book.closed")
            ForEach(merkez.bekleyenKenar.prefix(2)) { x in
                Button { rota.kayit = KayitIstegi(tur: .metin, istem: "§\(x.bolumNo) \(x.baslik)", aciklama: x.paragraf, kenarIs: x.id) } label: {
                    satir("§\(x.bolumNo) \(x.baslik)", "Türkçe paragrafını İngilizce anlat", "globe")
                }.buttonStyle(.plain)
            }
        }
    }

    private var bugunKayitlar: some View {
        let b = merkez.d.kayitlar.filter { Calendar.current.isDateInToday($0.tarih) }.reversed()
        return Group {
            if !b.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Baslik(metin: "Bugün söylediklerin", simge: "waveform")
                    ForEach(Array(b)) { k in
                        NavigationLink { KayitDetay(k: k) } label: { satir(k.istem, "\(Int(k.sure)) sn · \(k.durum)", k.tur.simge) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func satir(_ a: String, _ b: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s).foregroundStyle(Color.ayna).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(a).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(b).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            Image(systemName: "mic").foregroundStyle(.white.opacity(0.4))
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
    }
}

struct Baslik: View {
    let metin: String; let simge: String
    var body: some View { Label(metin, systemImage: simge).font(.headline).foregroundStyle(.white) }
}

struct Kucuk: View {
    let asset: PHAsset
    @State private var resim: UIImage?
    var body: some View {
        ZStack { Color.white.opacity(0.08); if let resim { Image(uiImage: resim).resizable().scaledToFill() } }
            .task {
                let o = PHImageRequestOptions(); o.deliveryMode = .opportunistic; o.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 330, height: 420), contentMode: .aspectFill, options: o) { r, _ in resim = r }
            }
    }
}
