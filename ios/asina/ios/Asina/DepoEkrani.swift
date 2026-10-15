// Depo: Oxford 5000'in tamamı (4.954 kelime) — arama, süzgeç, tek kelimenin kartı.
import SwiftUI

struct DepoEkrani: View {
    @EnvironmentObject var depo: Depo
    @State private var arama = ""
    @State private var suzgec = Suzgec.ogreniliyor
    @State private var bant = "Tümü"

    enum Suzgec: String, CaseIterable, Identifiable {
        case ogreniliyor = "Öğreniliyor", sirada = "Sırada", biliyorum = "Bildiğim", hepsi = "Hepsi"
        var id: String { rawValue }
    }

    private var liste: [Kelime] {
        let q = arama.trimmingCharacters(in: .whitespaces).lowercased()
        var l: [Kelime]
        switch suzgec {
        case .ogreniliyor:
            l = depo.kayit.kartlar.sorted { $0.value.ilk > $1.value.ilk }.compactMap { depo.kelime(ad: $0.key) }
        case .sirada:
            l = depo.kelimeler.filter { $0.s == "d" && depo.kart($0) == nil && depo.kayit.kararlar[$0.w] == nil }
                .sorted { ($0.o ?? 0) < ($1.o ?? 0) }
        case .biliyorum:
            l = depo.kelimeler.filter { $0.s == "k" || depo.kayit.kararlar[$0.w] == .biliyorum }
        case .hepsi:
            l = depo.kelimeler
        }
        if bant != "Tümü" { l = l.filter { $0.c == bant } }
        if !q.isEmpty {
            l = l.filter { $0.w.lowercased().hasPrefix(q) || $0.tr.lowercased().contains(q) }
        }
        return l
    }

    var body: some View {
        NavigationStack {
            let l = liste
            List {
                Section {
                    Picker("Süzgeç", selection: $suzgec) {
                        ForEach(Suzgec.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Tümü", "A1", "A2", "B1", "B2", "C1"], id: \.self) { b in
                                Button { withAnimation { bant = b } } label: {
                                    Text(b).font(.footnote.weight(.semibold))
                                        .foregroundStyle(bant == b ? .white : (b == "Tümü" ? R.murekkep : R.bant(b)))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(bant == b ? (b == "Tümü" ? R.murekkep : R.bant(b)) : R.yuzey2,
                                                    in: Capsule())
                                }
                                .buttonStyle(Bas())
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                }
                Section {
                    if l.isEmpty {
                        Text(suzgec == .ogreniliyor ? "Henüz tanıştığın kelime yok. Bugün sekmesinden başla."
                             : "Bu süzgeçte kelime yok.")
                            .font(.callout).foregroundStyle(R.soluk)
                    }
                    ForEach(l.prefix(400)) { k in
                        Button { depo.acilacakKelime = k } label: { satir(k) }
                    }
                    if l.count > 400 {
                        Text("İlk 400 gösteriliyor — aramayla daralt.").font(.footnote).foregroundStyle(R.soluk)
                    }
                } header: {
                    Text("\(l.count.formatted()) kelime")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(R.zemin.ignoresSafeArea())
            .navigationTitle("Depo")
            .searchable(text: $arama, prompt: "Kelime ya da Türkçesi")
        }
    }

    private func satir(_ k: Kelime) -> some View {
        let kart = depo.kart(k)
        return HStack(spacing: 12) {
            Circle()
                .fill(kart.map { R.asama($0.asama) } ?? (depo.kayit.kararlar[k.w] == .biliyorum || k.s == "k" ? R.dogru.opacity(0.4) : R.cizgi))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(k.w).font(.kelime(18)).foregroundStyle(R.murekkep)
                Text(k.tr).font(.footnote).foregroundStyle(R.ikincil).lineLimit(1)
            }
            Spacer()
            if let kart {
                Text(kart.vade <= Date().gunSonu ? "bugün" : kart.vade.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(R.soluk)
            }
            RozetKelime(k: k)
        }
        .padding(.vertical, 2)
    }
}

/// Tek kelimenin tam kartı.
struct KelimeDetay: View {
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat
    let k: Kelime

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TanitKarti(k: k)
                    durumKarti
                }
                .padding(18)
            }
            .background(R.zemin.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { kapat() }
                }
            }
        }
    }

    @ViewBuilder
    private var durumKarti: some View {
        let kart = depo.kart(k)
        let karar = depo.kayit.kararlar[k.w]
        VStack(alignment: .leading, spacing: 14) {
            if let kart {
                HStack {
                    AsamaRozeti(asama: kart.asama)
                    Spacer()
                    Text("hatırlama %\(Int(kart.hatirlama() * 100))").font(.footnote.monospacedDigit())
                        .foregroundStyle(R.ikincil)
                }
                Text(kart.asama.aciklama).font(.footnote).foregroundStyle(R.ikincil)
                HStack {
                    bilgi("Tanışma", kart.ilk.formatted(date: .abbreviated, time: .omitted))
                    bilgi("Sıradaki", kart.vade.formatted(date: .abbreviated, time: .omitted))
                    bilgi("Tekrar", "\(kart.tekrar)")
                    bilgi("Kararlılık", kart.kararlilik < 1 ? "<1 g" : "\(Int(kart.kararlilik)) g")
                }
                Button(role: .destructive) { depo.biliyorum(k); kapat() } label: {
                    Label("Bunu biliyorum — sorma", systemImage: "checkmark.circle")
                }
                .font(.subheadline)
            } else if karar == .biliyorum || k.s == "k" {
                Label(karar == .biliyorum ? "Bildiğini işaretledin." : "Atlas taramasında bilinen olarak işaretli.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(R.dogru).font(.subheadline)
                Button { depo.simdiOgren(k); kapat() } label: {
                    Label("Yine de öğrenmeye al", systemImage: "arrow.uturn.left")
                }
                .font(.subheadline)
            } else {
                HStack {
                    AsamaRozeti(asama: nil)
                    if let o = k.o { Text("sırası: \(o + 1)").font(.footnote).foregroundStyle(R.soluk) }
                    if let g = k.g { Text("· Örgü bölüm \(g)").font(.footnote).foregroundStyle(R.soluk) }
                }
                HStack(spacing: 10) {
                    Button { depo.simdiOgren(k); kapat() } label: {
                        Label("Bugün öğren", systemImage: "sparkles")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(R.vurgu.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button { depo.biliyorum(k); kapat() } label: {
                        Label("Biliyorum", systemImage: "checkmark")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(R.dogru.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(R.dogru)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .kart(18)
    }

    private func bilgi(_ ad: String, _ deger: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ad).font(.caption2).foregroundStyle(R.soluk)
            Text(deger).font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
