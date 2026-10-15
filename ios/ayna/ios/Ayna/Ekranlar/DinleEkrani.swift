// Dinle: sabah yürüyüşü (telefon cepte, kulaklık tuşuyla cevap) + her anlatımın kendi sesin ↔ doğrusu karşılaştırması.
import AVFoundation
import SwiftUI

struct DinleEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    @StateObject private var y = Yuruyus.shared

    private var hazir: [Kayit] {
        let yeni = merkez.d.kayitlar.filter { $0.duzeltme != nil && !$0.dinlendi }
        return Array((yeni.isEmpty ? merkez.d.kayitlar.filter { $0.duzeltme != nil } : yeni).suffix(5))
    }

    var body: some View {
        NavigationStack {
            List {
                Section { yuruyusKarti }
                    .listRowBackground(Color.clear)
                let duz = merkez.d.kayitlar.filter { $0.duzeltme != nil }.reversed()
                if !duz.isEmpty {
                    Section("Düzeltilenler") {
                        ForEach(Array(duz)) { k in NavigationLink { KayitDetay(k: k) } label: { KayitSatiri(k: k) } }
                    }
                }
                let bek = merkez.d.kayitlar.filter { $0.duzeltme == nil }.reversed()
                if !bek.isEmpty {
                    Section {
                        ForEach(Array(bek)) { k in NavigationLink { KayitDetay(k: k) } label: { KayitSatiri(k: k) } }
                            .onDelete { i in i.map { Array(bek)[$0].id }.forEach(merkez.sil) }
                    } header: { Text("Düzeltme bekleyen") } footer: {
                        Text("Mac'te Teoria'nın sabah akışı Whisper ile döker. Düzeltme: terminal oturumu açıksa kendiliğinden; değilse Claude Code'a \"Ayna düzelt\" de.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Dinle")
            .refreshable { await merkez.esitle() }
        }
    }

    private var yuruyusKarti: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.walk").font(.title).foregroundStyle(Color.ayna)
                VStack(alignment: .leading) {
                    Text("Sabah yürüyüşü").font(.title3.weight(.bold))
                    Text(hazir.isEmpty ? "Henüz düzeltilmiş anlatım yok." : "\(hazir.count) anlatım · kendi sesin → doğrusu → sorular").font(.caption).foregroundStyle(.secondary)
                }
            }
            if y.calisiyor {
                VStack(alignment: .leading, spacing: 8) {
                    Text(y.simdi).font(.subheadline.weight(.semibold))
                    if let q = y.soru {
                        Text(q.cumle).font(.title3)
                        HStack {
                            Button { y.cevapla(.evet) } label: { Label("Doğru", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.green)
                            Button { y.cevapla(.hayir) } label: { Label("Yanlış", systemImage: "forward.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.red)
                        }
                        Text("Kulaklıkta: ▶︎ doğru · ⏭ yanlış · ⏮ tekrar").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(y.dogruSayi)/\(y.soruSayi)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button(role: .destructive) { y.bitir() } label: { Label("Bitir", systemImage: "stop.fill") }
                }
            } else {
                Button { y.baslat(hazir, merkez: merkez) } label: { Label("Başlat — telefonu cebe koy", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(hazir.isEmpty)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.07)))
    }
}

struct KayitSatiri: View {
    let k: Kayit
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: k.tur.simge).foregroundStyle(Color.ayna).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(k.istem).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(k.tarih.formatted(date: .abbreviated, time: .shortened)) · \(k.durum)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !k.hatalar.isEmpty { Text("\(k.hatalar.count)").font(.caption.weight(.bold)).padding(6).background(Circle().fill(Color.orange.opacity(0.25))) }
        }
    }
}

/// Bir anlatım: kendi sesin, senin dediğin, doğrusu, hataların; "yeniden anlat" aynı anıyı ikinci kez söyletir.
struct KayitDetay: View {
    @EnvironmentObject var merkez: Merkez
    @EnvironmentObject var rota: Rota
    let k: Kayit
    @State private var oynatici: AVAudioPlayer?

    private var g: Kayit { merkez.d.kayitlar.first { $0.id == k.id } ?? k }

    var body: some View {
        List {
            Section {
                HStack {
                    Button { cal(g.id + ".m4a") } label: { Label("Kendi sesin", systemImage: "person.wave.2") }
                    Spacer()
                    if g.duzeltme != nil {
                        Button { if g.sesVar { cal(g.id + "-duz.m4a") } else { Task { await Konusmaci.shared.soyle(g.duzeltme ?? "") } } } label: { Label("Doğrusu", systemImage: "checkmark.bubble") }
                    }
                }
                .buttonStyle(.bordered)
            }
            Section("Senin dediğin") { Text(g.dokum ?? g.onDokum ?? "Henüz yazıya dökülmedi.").foregroundStyle(g.dokum ?? g.onDokum == nil ? .secondary : .primary) }
            if let d = g.duzeltme { Section("Doğrusu") { Text(d).font(.body.weight(.medium)) } }
            if !g.hatalar.isEmpty {
                Section("Hataların") {
                    ForEach(g.hatalar, id: \.self) { h in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.yanlis).strikethrough().foregroundStyle(.secondary)
                            Text(h.dogru).fontWeight(.semibold)
                            Text(h.kural).font(.caption).foregroundStyle(Color.ayna)
                        }
                    }
                }
            }
            if g.duzeltme != nil {
                Section {
                    Button { rota.kayit = KayitIstegi(tur: .yeniden, istem: "Yeniden: " + g.istem, aciklama: "Aynı anıyı bir daha anlat. Doğrusuna bakma — hatırladığın kadarını kullan.", onceki: g.id) } label: {
                        Label("Yeniden anlat", systemImage: "arrow.counterclockwise")
                    }
                } footer: { Text("İkinci anlatımda aynı hata çıkmazsa öğrenilmiş demektir. Sayaç yok; Mac karşılaştırmayı not eder.") }
            }
        }
        .navigationTitle(g.tur.ad)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cal(_ ad: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        oynatici = try? AVAudioPlayer(contentsOf: Depo.sesKlasoru.appendingPathComponent(ad))
        oynatici?.play()
    }
}
