// Sözlük: odanın bütün eşyaları — Oxford 3000 → Oxford 5000 → ek. Yerleşenler işaretli; kamera tanımayanları elle koyarsın.
import SwiftUI

struct SozlukEkrani: View {
    @EnvironmentObject var goz: Goz
    @EnvironmentObject var ses: Ses
    @State private var oda = Goz.shared.oda
    @State private var suzgec = 0
    @State private var arama = ""
    @State private var secili: Kelime?
    @State private var bilinen = Kasa.bilinen

    private var yerlesen: Set<String> { Set((oda == goz.oda ? goz.etiketler : Kasa.etiketler(oda)).map(\.en)) }

    private var liste: [Kelime] {
        goz.sozluk.odada(oda).filter { k in
            let a = arama.isEmpty || k.en.localizedCaseInsensitiveContains(arama) || k.tr.localizedCaseInsensitiveContains(arama)
            switch suzgec {
            case 1: return a && !yerlesen.contains(k.en)
            case 2: return a && !k.siniflar.isEmpty
            case 3: return a && k.siniflar.isEmpty
            default: return a
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Oda", selection: $oda) {
                        ForEach(goz.sozluk.odalar) { Text($0.ad).tag($0.id) }
                    }
                    Picker("Süzgeç", selection: $suzgec) {
                        Text("Hepsi").tag(0); Text("Yerleşmemiş").tag(1); Text("Kamera tanır").tag(2); Text("Elle").tag(3)
                    }
                    .pickerStyle(.segmented)
                    let tum = goz.sozluk.odada(oda)
                    HStack {
                        Gauge(value: Double(tum.filter { yerlesen.contains($0.en) }.count), in: 0...Double(max(1, tum.count))) {}
                            .gaugeStyle(.accessoryLinearCapacity).tint(.saray)
                        Text("\(tum.filter { yerlesen.contains($0.en) }.count)/\(tum.count)").font(.caption.monospacedDigit())
                    }
                }
                ForEach(["oxford3000", "oxford5000", "ek"], id: \.self) { grup in
                    let ogeler = liste.filter { $0.kaynak == grup }
                    if !ogeler.isEmpty {
                        Section {
                            ForEach(ogeler) { k in satir(k) }
                        } header: {
                            Text(grup == "oxford3000" ? "Oxford 3000 · önce bunlar" : grup == "oxford5000" ? "Oxford 5000" : "Ek · evde bilinmesi gerekenler")
                        } footer: {
                            if grup == "ek" { Text("Oxford listesinde yok ama evin dilinde temel: spatula, kevgir, priz, ampul…") }
                        }
                    }
                }
            }
            .searchable(text: $arama, prompt: "İngilizce ya da Türkçe")
            .navigationTitle(goz.sozluk.odalar.first { $0.id == oda }?.en ?? "Sözlük")
            .sheet(item: $secili) { KelimeKarti(k: $0).presentationDetents([.medium, .large]) }
            .onAppear { oda = goz.oda; bilinen = Kasa.bilinen }
        }
    }

    private func satir(_ k: Kelime) -> some View {
        Button { ses.oku(k); secili = k } label: {
            HStack(spacing: 12) {
                Image(systemName: yerlesen.contains(k.en) ? "mappin.circle.fill" : (k.siniflar.isEmpty ? "hand.point.up.left" : "camera.viewfinder"))
                    .foregroundStyle(yerlesen.contains(k.en) ? Color.saray : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(k.en).font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(bilinen.contains(k.en) ? .secondary : .primary)
                        if !k.ses.isEmpty { Text(k.ses).font(.system(size: 12, design: .serif)).foregroundStyle(.secondary) }
                    }
                    Text(k.tr).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(k.rozet).font(.caption2.weight(.bold)).foregroundStyle(k.kaynak == "ek" ? Color.secondary : Color.saray)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill((k.kaynak == "ek" ? Color.secondary : Color.saray).opacity(0.14)))
            }
        }
        .tint(.primary)
        .swipeActions {
            Button {
                var b = Kasa.bilinen
                if b.contains(k.en) { b.remove(k.en) } else { b.insert(k.en) }
                Kasa.bilinen = b; bilinen = b
            } label: { Label(bilinen.contains(k.en) ? "Bilmiyorum" : "Biliyorum", systemImage: "checkmark") }.tint(.green)
        }
    }
}

/// Eşya kartı: büyük ad, telaffuz, Türkçe, Oxford tanımı ve örneği, hangi odalarda.
struct KelimeKarti: View {
    @EnvironmentObject var ses: Ses
    @EnvironmentObject var goz: Goz
    let k: Kelime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(k.en).font(.system(size: 40, weight: .bold, design: .rounded))
                    Spacer()
                    Button { ses.oku(k) } label: { Image(systemName: "speaker.wave.2.circle.fill").font(.system(size: 40)) }.tint(.saray)
                }
                if !k.ses.isEmpty { Text(k.ses).font(.system(size: 20, design: .serif)).foregroundStyle(.secondary) }
                Text(k.tr).font(.title3)
                HStack(spacing: 6) {
                    Text(k.rozet).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.saray.opacity(0.18)))
                    ForEach(k.odalar, id: \.self) { o in
                        Text(goz.sozluk.odalar.first { $0.id == o }?.en ?? o).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(.secondary.opacity(0.12)))
                    }
                }
                if !k.tanim.isEmpty {
                    Divider()
                    Text(k.tanim).font(.body)
                    if !k.ornek.isEmpty { Text("“\(k.ornek)”").font(.body.italic()).foregroundStyle(.secondary) }
                    Button { ses.soyle(k.ornek.isEmpty ? k.tanim : k.ornek) } label: { Label("Örneği dinle", systemImage: "play.circle") }.tint(.saray)
                }
                Text(k.siniflar.isEmpty ? "Kamera bunu kendisi tanımaz: Kamera'da + ile eşyanın üstüne koy." : "Kamera bunu kendisi tanır.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(22)
        }
    }
}

/// Elle yerleştirme için kelime seçici: önce bu odanın henüz yerleşmemiş kelimeleri.
struct KelimeSecici: View {
    @EnvironmentObject var goz: Goz
    @Environment(\.dismiss) private var kapat
    let oda: String
    let sec: (Kelime) -> Void
    @State private var arama = ""

    var body: some View {
        NavigationStack {
            let yer = goz.yerlesenler
            let tum = goz.sozluk.odada(oda) + goz.sozluk.kelimeler.filter { !$0.odalar.contains(oda) }
            let liste = tum.filter { arama.isEmpty || $0.en.localizedCaseInsensitiveContains(arama) || $0.tr.localizedCaseInsensitiveContains(arama) }
                .sorted { (yer.contains($0.en) ? 1 : 0, $0.odalar.contains(oda) ? 0 : 1) < (yer.contains($1.en) ? 1 : 0, $1.odalar.contains(oda) ? 0 : 1) }
            List(liste) { k in
                Button { sec(k) } label: {
                    HStack {
                        Text(k.en).font(.headline)
                        Text(k.tr).foregroundStyle(.secondary)
                        Spacer()
                        if yer.contains(k.en) { Image(systemName: "mappin").foregroundStyle(Color.saray) }
                    }
                }
                .tint(.primary)
            }
            .searchable(text: $arama, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artının altındaki eşya ne?")
            .navigationTitle("Buraya ne var?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } } }
        }
    }
}
