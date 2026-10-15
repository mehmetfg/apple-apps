// Düzenleyici panelleri — duvar ve widget aynı parçaları kullanır.
import SwiftUI
import PhotosUI

struct ZeminPaneli: View {
    @Binding var z: Zemin
    var paletDegisti: ([String]) -> Void = { _ in }
    @State private var secim: PhotosPickerItem?
    @State private var yukleniyor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ZeminTuru.allCases) { t in
                        Cip(ad: t.ad, simge: t.simge, secili: z.tur == t) { z.tur = t }
                    }
                }
            }

            if z.tur == .foto {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $secim, matching: .images) {
                        Label(z.foto == nil ? "Fotoğraf seç" : "Fotoğrafı değiştir", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Renkler.kart2))
                    }
                    if let foto = z.foto {
                        Button {
                            if let img = Depo.gorsel(foto, enUzun: 400) {
                                let p = PaletCikar.renkler(img)
                                z.renkler = p
                                paletDegisti(p)
                            }
                        } label: {
                            Label("Paleti al", systemImage: "eyedropper")
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Renkler.kart2))
                        }
                    }
                }
                .buttonStyle(.plain)
                if yukleniyor { ProgressView().frame(maxWidth: .infinity) }
                Kaydirici(ad: "Bulanıklık", deger: $z.bulanik, aralik: 0...40, bicim: { String(format: "%.0f", $0) })
            } else {
                PaletSatiri(renkler: $z.renkler, paletDegisti: paletDegisti)
            }

            switch z.tur {
            case .gradyan:
                Kaydirici(ad: "Açı", deger: $z.aci, aralik: 0...360, bicim: { String(format: "%.0f°", $0) })
            case .mesh:
                Button {
                    withAnimation(.smooth(duration: 0.6)) { z.tohum += 1 }
                } label: {
                    Label("Karıştır", systemImage: "shuffle")
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Renkler.kart2))
                }
                .buttonStyle(.plain)
            case .desen:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DesenTuru.allCases) { d in
                            Button { z.desen = d } label: {
                                VStack(spacing: 6) {
                                    ZeminGorunum(zemin: { var k = z; k.desen = d; k.tane = 0; k.vinyet = 0; return k }())
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(z.desen == d ? Renkler.vurgu : .clear, lineWidth: 2))
                                    Text(d.ad).font(.caption2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { z.tohum += 1 } label: {
                    Label("Yerleşimi değiştir", systemImage: "dice")
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Renkler.kart2))
                }
                .buttonStyle(.plain)
            default: EmptyView()
            }

            Divider().overlay(Renkler.cizgi)
            Kaydirici(ad: "Karartma", deger: $z.karartma, aralik: -0.6...0.7, bicim: { $0 >= 0 ? String(format: "%.0f%%", $0 * 100) : String(format: "aydınlat %.0f%%", -$0 * 100) })
            Kaydirici(ad: "Vinyet", deger: $z.vinyet, aralik: 0...1)
            Kaydirici(ad: "Film tanesi", deger: $z.tane, aralik: 0...1)
        }
        .onChange(of: secim) { _, yeni in
            guard let yeni else { return }
            yukleniyor = true
            Task {
                if let veri = try? await yeni.loadTransferable(type: Data.self), let ad = Depo.gorselKaydet(veri) {
                    z.foto = ad
                    if let img = Depo.gorsel(ad, enUzun: 400), z.renkler == Palet.hepsi[0].renkler {
                        z.renkler = PaletCikar.renkler(img)
                        paletDegisti(z.renkler)
                    }
                }
                yukleniyor = false
                secim = nil
            }
        }
    }
}

struct PaletSatiri: View {
    @Binding var renkler: [String]
    var paletDegisti: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Palet.hepsi) { p in
                        Button {
                            withAnimation(.smooth) { renkler = p.renkler }
                            paletDegisti(p.renkler)
                        } label: {
                            VStack(spacing: 5) {
                                HStack(spacing: 0) {
                                    ForEach(p.renkler, id: \.self) { Color(hex: $0) }
                                }
                                .frame(width: 66, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(renkler == p.renkler ? Renkler.vurgu : Renkler.cizgi, lineWidth: renkler == p.renkler ? 2 : 1))
                                Text(p.ad).font(.caption2).lineLimit(1).frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(renkler.indices, id: \.self) { i in
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: renkler[i]) },
                        set: { renkler[i] = $0.hex; paletDegisti(renkler) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                Spacer()
                Text("Kendi renklerin").font(.footnote).foregroundStyle(Renkler.ikincil)
            }
        }
    }
}

struct YaziPaneli: View {
    @Binding var y: YaziStili
    var palet: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(YaziAilesi.allCases) { a in
                        Button { y.aile = a } label: {
                            VStack(spacing: 4) {
                                Text("Aa").font(a.font(26))
                                Text(a.ad).font(.caption2)
                            }
                            .frame(width: 66, height: 66)
                            .background(RoundedRectangle(cornerRadius: 14).fill(y.aile == a ? Renkler.vurgu.opacity(0.22) : Renkler.kart2))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(y.aile == a ? Renkler.vurgu : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Kaydirici(ad: "Boyut", deger: $y.olcek, aralik: 0.6...1.6, bicim: { String(format: "%.0f%%", $0 * 100) })
            Picker("Hiza", selection: $y.hiza) {
                ForEach(Hiza.allCases) { Image(systemName: $0.simge).tag($0) }
            }
            .pickerStyle(.segmented)
            RenkSecici(ad: "Yazı", hex: $y.renk, palet: palet)
            RenkSecici(ad: "Vurgu", hex: $y.vurgu, palet: palet)
            Toggle("Gölge", isOn: $y.golge)
            Toggle("BÜYÜK HARF", isOn: $y.buyukHarf)
        }
    }
}

struct RenkSecici: View {
    var ad: String
    @Binding var hex: String
    var palet: [String]

    var body: some View {
        HStack(spacing: 10) {
            Text(ad).font(.subheadline).frame(width: 52, alignment: .leading)
            ForEach(Array(Set(palet + ["#FFFFFF", "#111111"])).sorted { RenkHesap.parlaklik($0) < RenkHesap.parlaklik($1) }, id: \.self) { r in
                Circle().fill(Color(hex: r)).frame(width: 26, height: 26)
                    .overlay(Circle().stroke(hex.uppercased() == r.uppercased() ? Renkler.vurgu : Color.white.opacity(0.2), lineWidth: hex.uppercased() == r.uppercased() ? 2.5 : 1))
                    .onTapGesture { hex = r }
            }
            Spacer(minLength: 0)
            ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { hex = $0.hex }), supportsOpacity: false).labelsHidden()
        }
    }
}
