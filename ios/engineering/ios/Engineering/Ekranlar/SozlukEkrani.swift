import SwiftUI

/// Mühendis İngilizcesi: bütün derslerin terimleri ve mülakat cümleleri tek yerde.
struct SozlukEkrani: View {
    enum Suzgec: String, CaseIterable, Identifiable { case hepsi = "All", ogreniyorum = "Learning", biliyorum = "Known"; var id: String { rawValue } }
    @Environment(Ilerleme.self) private var ilerleme
    @State private var arama = ""
    @State private var suzgec: Suzgec = .hepsi
    @State private var secili: Terim?
    @State private var bolum = 0
    private let k = Kutuphane.shared

    private var terimler: [Terim] {
        k.terimler.filter { t in
            (arama.isEmpty || t.terim.localizedCaseInsensitiveContains(arama) || t.tr.localizedCaseInsensitiveContains(arama))
            && (suzgec == .hepsi || (suzgec == .biliyorum) == ilerleme.biliyor(t))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Words").font(.system(size: 40, weight: .heavy, design: .rounded))
                        Text("\(ilerleme.bilinenSayisi) of \(k.terimler.count) known · every dotted word in a lesson lives here")
                            .font(.footnote).foregroundStyle(Tema.soluk)
                    }
                    .padding(.top, 12)
                    Picker("", selection: $bolum) {
                        Text("Terms").tag(0); Text("Sentences").tag(1); Text("Traps").tag(2)
                    }
                    .pickerStyle(.segmented)

                    switch bolum {
                    case 0: terimListesi
                    case 1: cumleler
                    default: tuzaklar
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(Tema.zemin.ignoresSafeArea())
            .searchable(text: $arama, prompt: "Search English or Turkish")
        }
        .sheet(item: $secili) { t in
            TerimKarti(terim: t).presentationDetents([.height(380), .large]).presentationBackground(Tema.zemin)
        }
    }

    private var terimListesi: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $suzgec) { ForEach(Suzgec.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            LazyVStack(spacing: 0) {
                ForEach(terimler) { t in
                    Button { secili = t } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(t.terim).font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(Tema.murekkep)
                                    Text(t.ipa).font(.system(.caption, design: .serif)).foregroundStyle(Tema.soluk).lineLimit(1)
                                }
                                Text(t.tr).font(.caption).foregroundStyle(Tema.soluk)
                            }
                            Spacer()
                            if ilerleme.biliyor(t) { Image(systemName: "checkmark.seal.fill").foregroundStyle(Tema.dogru) }
                            Button { Ses.shared.soyle(t.terim) } label: { Image(systemName: "speaker.wave.2") }
                                .foregroundStyle(Tema.soluk).buttonStyle(.plain)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 14)
                }
            }
            .background(Tema.kart, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var cumleler: some View {
        VStack(spacing: 10) {
            ForEach(k.icerik.dersler) { d in
                VStack(alignment: .leading, spacing: 8) {
                    Text(d.baslik.uppercased()).font(.system(.caption2, design: .rounded, weight: .heavy)).foregroundStyle(Tema.soluk)
                    Text(d.cumle.en).font(.system(.body, design: .serif)).foregroundStyle(Tema.murekkep)
                    HStack {
                        TurkceDestek(metin: d.cumle.tr)
                        Spacer()
                        SesDugmeleri(metin: d.cumle.en)
                    }
                }
                .kartYuzey(14)
            }
        }
    }

    private var tuzaklar: some View {
        VStack(spacing: 10) {
            ForEach(k.icerik.dersler) { d in
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text(d.tuzak.yanlis).strikethrough(color: Tema.yanlis) } icon: { Image(systemName: "xmark").foregroundStyle(Tema.yanlis) }
                    Label { Text(d.tuzak.dogru).fontWeight(.semibold) } icon: { Image(systemName: "checkmark").foregroundStyle(Tema.dogru) }
                    Text(d.tuzak.not).font(.caption).foregroundStyle(Tema.soluk).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .kartYuzey(14)
            }
        }
    }
}
