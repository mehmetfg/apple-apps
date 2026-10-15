// Deyimsel fiiller (phrasal verbs): fiil + parçacık, anlamı tahmin edilemez ("give up" ≠ "vermek").
// Ayırt etmek için üç araç: parçacık haritası (up/off/out… ne demek) · fiile göre gruplar (take off ↔ take on ↔ take up
// yan yana) · oturumdaki "hangi parçacık?" sorusu.
import SwiftUI

struct ParcacikBilgi: Identifiable {
    let id: String
    let fikir: String
    let ornekler: [String]
}

enum Parcaciklar {
    static let liste: [ParcacikBilgi] = [
        .init(id: "up", fikir: "yukarı · artma · tamamlama",
              ornekler: ["pick up = kaldırmak", "use up = tüketip bitirmek", "cheer up = neşelenmek"]),
        .init(id: "down", fikir: "aşağı · azalma · durma",
              ornekler: ["slow down = yavaşlamak", "calm down = sakinleşmek", "break down = bozulmak"]),
        .init(id: "out", fikir: "dışarı · ortaya çıkma · tükenme",
              ornekler: ["find out = öğrenmek", "hand out = dağıtmak", "run out of = ... kalmamak"]),
        .init(id: "in", fikir: "içeri · katılma · teslim",
              ornekler: ["join in = katılmak", "fill in = (form) doldurmak", "give in = pes etmek"]),
        .init(id: "off", fikir: "ayrılma · kapanma · başlama",
              ornekler: ["turn off = kapatmak", "take off = havalanmak", "set off = yola çıkmak"]),
        .init(id: "on", fikir: "devam · açma · üstüne",
              ornekler: ["turn on = açmak", "carry on = devam etmek", "put on = giymek"]),
        .init(id: "away", fikir: "uzaklaşma · yok olma",
              ornekler: ["run away = kaçmak", "throw away = atmak", "give away = bedava vermek"]),
        .init(id: "back", fikir: "geri · karşılık",
              ornekler: ["come back = geri gelmek", "pay back = geri ödemek", "call back = geri aramak"]),
        .init(id: "over", fikir: "üzerinden · baştan sona gözden geçirme",
              ornekler: ["go over = gözden geçirmek", "think over = iyice düşünmek", "get over = atlatmak"]),
        .init(id: "through", fikir: "içinden geçerek · sonuna kadar",
              ornekler: ["get through = atlatmak", "go through = yaşamak, incelemek"]),
    ]
}

struct DeyimselEkrani: View {
    @EnvironmentObject var depo: Depo
    @State private var arama = ""

    private var sonuc: [Kelime] {
        let q = arama.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return depo.kelimeler.filter { $0.isPV && ($0.w.lowercased().contains(q) || $0.tr.lowercased().contains(q)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if arama.isEmpty {
                        ozet
                        kural
                        parcacikHaritasi
                        fiiller
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sonuc.prefix(60)) { k in PVKart(k: k) }
                            if sonuc.isEmpty { Text("Sonuç yok.").foregroundStyle(R.soluk) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(R.zemin.ignoresSafeArea())
            .navigationTitle("Deyimsel fiiller")
            .searchable(text: $arama, prompt: "give up, vazgeçmek…")
            .navigationDestination(for: String.self) { FiilGrubu(taban: $0) }
        }
    }

    private var ozet: some View {
        HStack(spacing: 18) {
            ZStack {
                Halka(oran: Double(depo.pvDokunulan) / Double(max(1, depo.pvToplam)), kalinlik: 10, renk: R.pv)
                Text("\(depo.pvDokunulan)").font(.title3.weight(.bold).monospacedDigit())
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(depo.pvToplam) deyimsel fiil").font(.headline)
                Text("Günde \(depo.ayar.pvSayisi) yeni gelir; kelimelerle aynı turda çalışılır. Buradan istediğin fiili öne alabilirsin.")
                    .font(.footnote).foregroundStyle(R.ikincil)
            }
        }
        .kart(18)
        .padding(.top, 6)
    }

    private var kural: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Üç kural").font(.headline)
            kuralSatiri("1", "Parçacık anlamı değiştirir", "give = vermek · give up = vazgeçmek")
            kuralSatiri("2", "Bazıları ayrılır", "turn the light off ✓  turn off the light ✓")
            kuralSatiri("3", "Zamir hep ortada", "pick it up ✓  pick up it ✗")
        }
        .kart(18)
    }

    private func kuralSatiri(_ n: String, _ baslik: String, _ ornek: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.footnote.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(R.pv, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(baslik).font(.subheadline.weight(.semibold))
                Text(ornek).font(.kelime(14, .regular)).foregroundStyle(R.ikincil)
            }
        }
    }

    private var parcacikHaritasi: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parçacık haritası").font(.headline)
            Text("Parçacığın çekirdek fikri anlamı tahmin etmene yardım eder.").font(.footnote).foregroundStyle(R.soluk)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Parcaciklar.liste) { p in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(p.id).font(.kelime(34)).foregroundStyle(R.pv)
                            Text(p.fikir).font(.footnote.weight(.semibold)).foregroundStyle(R.murekkep)
                            Divider()
                            ForEach(p.ornekler, id: \.self) {
                                Text($0).font(.kelime(13, .regular)).foregroundStyle(R.ikincil)
                            }
                        }
                        .padding(16)
                        .frame(width: 230, height: 190, alignment: .topLeading)
                        .background(R.yuzey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(R.pv.opacity(0.25), lineWidth: 1))
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var fiiller: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fiile göre").font(.headline)
            Text("Aynı fiilin deyimlerini yan yana görmek, karıştırmamanın en kısa yolu.").font(.footnote).foregroundStyle(R.soluk)
            VStack(spacing: 0) {
                ForEach(Array(depo.pvGruplari.enumerated()), id: \.element.taban) { i, g in
                    NavigationLink(value: g.taban) {
                        HStack(spacing: 12) {
                            Text(g.taban).font(.kelime(22)).foregroundStyle(R.murekkep)
                            Spacer()
                            let tanisilan = g.kelimeler.filter { depo.kart($0) != nil }.count
                            Text("\(tanisilan)/\(g.kelimeler.count)").font(.footnote.monospacedDigit())
                                .foregroundStyle(tanisilan > 0 ? R.pv : R.soluk)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(R.soluk)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    if i < depo.pvGruplari.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(R.yuzey, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Tek deyimsel fiilin satır kartı: deyim, anlam, örnek, ayrılma, durum.
struct PVKart: View {
    @EnvironmentObject var depo: Depo
    let k: Kelime

    var body: some View {
        Button { depo.acilacakKelime = k } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(k.w).font(.kelime(22)).foregroundStyle(R.murekkep)
                        if let n = k.ayrilmaNotu {
                            Text(n.baslik).font(.system(size: 10, weight: .bold)).foregroundStyle(R.pv)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(R.pv.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(k.tr).font(.subheadline.weight(.medium)).foregroundStyle(R.vurgu)
                    if let x = k.ilkCumle {
                        Text(Vurgu.metin(x, k.w, renk: R.murekkep))
                            .font(.kelime(13, .regular)).foregroundStyle(R.ikincil).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 8) {
                    SesDugmesi(kelime: k, boyut: 34)
                    AsamaRozeti(asama: depo.kart(k)?.asama)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(R.yuzey, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(R.cizgi.opacity(0.7), lineWidth: 0.5))
        }
        .buttonStyle(Bas())
    }
}

/// Bir fiilin bütün deyimleri yan yana — "take" için off · on · up · over · in · out · back · after · down…
struct FiilGrubu: View {
    @EnvironmentObject var depo: Depo
    let taban: String

    private var grup: [Kelime] { depo.pvGruplari.first { $0.taban == taban }?.kelimeler ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(taban).font(.kelime(56)).foregroundStyle(R.murekkep)
                    Text("\(grup.count) deyimsel fiil — parçacık değişince anlam değişir")
                        .font(.subheadline).foregroundStyle(R.ikincil)
                }
                .padding(.top, 8)
                VStack(spacing: 10) {
                    ForEach(grup) { k in PVKart(k: k) }
                }
                AnaDugme(baslik: "Bu fiili bugün çalış", simge: "sparkles", renk: R.pv) {
                    for k in grup.prefix(5) where depo.kart(k) == nil { depo.simdiOgren(k) }
                }
                Text("En çok 5 deyim bugünün listesine eklenir.").font(.caption).foregroundStyle(R.soluk)
            }
            .padding(18)
        }
        .background(R.zemin.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
