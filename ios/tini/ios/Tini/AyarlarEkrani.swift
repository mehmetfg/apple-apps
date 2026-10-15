import SwiftUI

struct AyarlarEkrani: View {
    @EnvironmentObject var calar: Calar
    @Environment(\.dismiss) private var kapat
    @AppStorage("deri") private var deri: Deri = .modern

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kip", selection: $calar.kip) {
                        ForEach(Calar.Kip.allCases) { Text($0.ad).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(calar.kip.aciklama).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Dinleme kipi") }

                if calar.kip == .kitapla {
                    Section {
                        Picker("Konuşmaya eşlik", selection: $calar.eslik) {
                            ForEach(Calar.Eslik.allCases) { Text($0.ad).tag($0) }
                        }
                        SesSurgusu(ad: calar.eslik == .onePlanaCik ? "Konuşurken" : "Müzik sesi", deger: $calar.ses)
                        if calar.eslik == .onePlanaCik { SesSurgusu(ad: "Durunca", deger: $calar.onPlanSes) }
                        if let k = calar.konusmaAlgilandi {
                            Label(k ? "Şu an konuşma var" : "Şu an konuşma yok", systemImage: k ? "waveform" : "waveform.slash")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text("Kitapla birlikte") } footer: {
                        Text("Sürgüler yalnız müziği ayarlar; telefonun ses tuşları ikisini birlikte. Ses Lab'daki \"Kitap altında\" ayarı konuşmanın frekanslarına yer açar.")
                    }
                } else {
                    Section("Ses") { SesSurgusu(ad: "Müzik sesi", deger: $calar.ses) }
                }

                Section("Uyku zamanlayıcısı") {
                    if let b = calar.uykuBitis {
                        HStack {
                            Text("Bitiş: \(b.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Button("İptal") { calar.uykuyuIptal() }
                        }
                    } else {
                        HStack {
                            ForEach([15, 30, 45, 60, 90], id: \.self) { d in
                                Button("\(d)") { calar.uyku(dakika: d) }.buttonStyle(.bordered)
                            }
                            Text("dk").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Arayüz") {
                    ForEach(Deri.allCases) { d in
                        Button { deri = d; kapat() } label: {
                            HStack {
                                Image(systemName: d.simge).frame(width: 28)
                                Etiket(d.ad, d.aciklama)
                                Spacer()
                                if d == deri { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("2. aşamada: Winamp 2.x ve Sony dijital Walkman (NW).").font(.footnote).foregroundStyle(.secondary)
                }

                Section("Kaynaklar") {
                    Label("Yerel dosyalar: FLAC, ALAC, WAV, AIFF, MP3, AAC", systemImage: "internaldrive")
                    Label("iCloud Drive/Fon klasörü (Kitaplık › + › Klasör bağla)", systemImage: "icloud")
                    Label("2. aşama: Internet Archive, Jamendo, radyo, Mac kitaplığı, Apple Music", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                }

                Section("Kestirmeler") {
                    Text("Kestirmeler › Otomasyon › Uygulama › Voice Dream › Açıldığında › \"Tını'yı çal\". Siri: \"Tını çal\", \"Tını durdur\". Arkaya Dokunma: \"Tını'yı aç/kapat\".")
                        .font(.footnote)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { kapat() } } }
        }
    }
}

struct SesSurgusu: View {
    let ad: String
    @Binding var deger: Float
    var body: some View {
        HStack {
            Text(ad).frame(width: 96, alignment: .leading)
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
            Slider(value: $deger, in: 0...1)
            Text("\(Int(deger * 100))").font(.callout.monospacedDigit()).frame(width: 32, alignment: .trailing)
        }
    }
}
