import SwiftUI

/// Yol: Tezgâh'ın 12 alanı × 180 meselesi. Dolu meseleler açılır; boşlar haritada yerini gösterir.
struct YolEkrani: View {
    @Environment(Ilerleme.self) private var ilerleme
    @State private var acik: Set<String> = ["KRM", "ALG"]
    @State private var ders: Ders?
    @State private var bos: Mesele?
    @State private var karisik = false
    private let k = Kutuphane.shared

    private var siradaki: Ders? { k.sira.first { !ilerleme.bitti($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    baslik
                    if let s = siradaki { siradakiKart(s) } else { tumuBittiKart }
                    if ilerleme.bitenSayisi > 0 { karisikKart }
                    Text("THE MAP").font(.system(.caption, design: .rounded, weight: .heavy)).foregroundStyle(Tema.soluk)
                        .padding(.top, 6)
                    ForEach(k.icerik.alanlar) { alanKarti($0) }
                    Text("Map and Turkish titles come from Mühendis Tezgâhı. Empty problems are written there first.")
                        .font(.caption2).foregroundStyle(Tema.soluk).padding(.top, 4)
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(Tema.zemin.ignoresSafeArea())
            .navigationDestination(for: Mesele.self) { MeseleEkrani(mesele: $0) }
        }
        .fullScreenCover(item: $ders) { DersEkrani(ders: $0) }
        .fullScreenCover(isPresented: $karisik) { KarisikEkrani() }
        .sheet(item: $bos) { m in
            BosMesele(mesele: m).presentationDetents([.height(300)]).presentationBackground(Tema.zemin)
        }
    }

    private var baslik: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Engineering").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Tema.murekkep)
            let dolu = k.icerik.alanlar.flatMap(\.meseleler).filter(\.dolu).count
            Text("\(ilerleme.bitenSayisi) of \(k.icerik.dersler.count) lessons · \(dolu) of 180 problems open · \(ilerleme.bilinenSayisi) words known")
                .font(.footnote).foregroundStyle(Tema.soluk)
        }
        .padding(.top, 12)
    }

    private func siradakiKart(_ d: Ders) -> some View {
        let alan = k.alan(ofMesele: d.mesele)
        let renk = Tema.alan(alan?.renk ?? "")
        return Button { ders = d } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Etiket(metin: "NEXT UP · \(d.mesele)", renk: renk)
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill").font(.title).foregroundStyle(renk)
                }
                Text(d.baslik).font(Tema.baslik(.title)).foregroundStyle(Tema.murekkep).multilineTextAlignment(.leading)
                Text(d.kanca).font(.system(.callout, design: .serif)).foregroundStyle(Tema.soluk)
                    .multilineTextAlignment(.leading).lineLimit(3)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Tema.kart)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(renk.opacity(0.13)).frame(width: 180).offset(x: 60, y: -70)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var tumuBittiKart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every open lesson is done.").font(Tema.baslik(.title3))
            Text("New problems arrive as they are written in Mühendis Tezgâhı. Meanwhile: Mixed review and the Lab.")
                .font(.callout).foregroundStyle(Tema.soluk)
        }
        .kartYuzey(20)
    }

    private var karisikKart: some View {
        Button { karisik = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "shuffle").font(.title3).foregroundStyle(Tema.zemin)
                    .frame(width: 46, height: 46).background(Tema.murekkep, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mixed review").font(.system(.headline, design: .rounded)).foregroundStyle(Tema.murekkep)
                    Text("8 questions from finished lessons. Your misses first. No due dates.")
                        .font(.caption).foregroundStyle(Tema.soluk).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .kartYuzey(14)
        }
        .buttonStyle(.plain)
    }

    private func alanKarti(_ a: Alan) -> some View {
        let renk = Tema.alan(a.renk)
        let dolu = a.meseleler.filter(\.dolu)
        let biten = dolu.filter { ilerleme.bitenOran($0) >= 1 }.count
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { if acik.contains(a.kod) { acik.remove(a.kod) } else { acik.insert(a.kod) } }
            } label: {
                HStack(spacing: 14) {
                    Text(a.kod).font(.system(.caption, design: .rounded, weight: .heavy)).foregroundStyle(renk)
                        .frame(width: 46, height: 46).background(renk.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.en).font(.system(.headline, design: .rounded)).foregroundStyle(Tema.murekkep).multilineTextAlignment(.leading)
                        Text(a.ad).font(.caption).foregroundStyle(Tema.soluk)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(a.meseleler.count)").font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(Tema.murekkep)
                        Text(dolu.isEmpty ? "soon" : "\(biten)/\(dolu.count) open done").font(.caption2).foregroundStyle(Tema.soluk)
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Tema.soluk)
                        .rotationEffect(.degrees(acik.contains(a.kod) ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if acik.contains(a.kod) {
                VStack(spacing: 0) {
                    ForEach(a.meseleler) { m in meseleSatiri(m, renk) }
                }
                .padding(.bottom, 8)
            }
        }
        .background(Tema.kart, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Tema.cizgi, lineWidth: 0.5))
    }

    @ViewBuilder
    private func meseleSatiri(_ m: Mesele, _ renk: Color) -> some View {
        let oran = ilerleme.bitenOran(m)
        let icerik = HStack(spacing: 12) {
            ZStack {
                Circle().stroke(m.dolu ? renk.opacity(0.25) : Tema.cizgi, style: StrokeStyle(lineWidth: 2.5, dash: m.dolu ? [] : [2, 3]))
                Circle().trim(from: 0, to: oran).stroke(renk, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                if oran >= 1 { Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(renk) }
                else { Text("\(m.sira)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(m.dolu ? Tema.murekkep : Tema.soluk) }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.en).font(.system(.subheadline, design: .rounded, weight: m.dolu ? .semibold : .regular))
                    .foregroundStyle(m.dolu ? Tema.murekkep : Tema.soluk).multilineTextAlignment(.leading)
                Text(m.baslik).font(.caption2).foregroundStyle(Tema.soluk).lineLimit(1)
            }
            Spacer()
            if m.dersler.count > 1 {
                Text("\(m.dersler.count) lessons").font(.caption2.weight(.semibold)).foregroundStyle(renk)
            }
            if m.dolu { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Tema.soluk) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())

        if m.dersler.count > 1 {
            NavigationLink(value: m) { icerik }.buttonStyle(.plain)
        } else {
            Button {
                if let id = m.dersler.first, let d = k.dersler[id] { ders = d } else { bos = m }
            } label: { icerik }
            .buttonStyle(.plain)
        }
    }
}

struct BosMesele: View {
    let mesele: Mesele
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Etiket(metin: "\(mesele.id) · NOT WRITTEN YET")
            Text(mesele.en).font(Tema.baslik(.title2))
            Text(mesele.baslik).font(.callout).foregroundStyle(Tema.soluk)
            Text("“\(mesele.soru)”").font(.system(.body, design: .serif)).foregroundStyle(Tema.murekkep).padding(.top, 4)
            Text("This problem is on the map but its lessons are not written yet.").font(.caption).foregroundStyle(Tema.soluk)
            Spacer()
        }
        .padding(24)
    }
}

/// Birden çok dersi olan mesele (ör. ALG-05 Sıralama Laboratuvarı).
struct MeseleEkrani: View {
    let mesele: Mesele
    @Environment(Ilerleme.self) private var ilerleme
    @State private var ders: Ders?
    private let k = Kutuphane.shared

    var body: some View {
        let renk = Tema.alan(k.alan(ofMesele: mesele.id)?.renk ?? "")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Etiket(metin: mesele.id, renk: renk)
                Text(mesele.en).font(Tema.baslik(.largeTitle))
                Text(mesele.baslik + " — " + mesele.soru).font(.callout).foregroundStyle(Tema.soluk)
                ForEach(Array(mesele.dersler.enumerated()), id: \.offset) { i, id in
                    if let d = k.dersler[id] {
                        Button { ders = d } label: {
                            HStack(spacing: 14) {
                                Text("\(i + 1)").font(.system(.headline, design: .rounded)).foregroundStyle(ilerleme.bitti(id) ? Tema.zemin : renk)
                                    .frame(width: 40, height: 40)
                                    .background(ilerleme.bitti(id) ? renk : renk.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(d.baslik).font(.system(.headline, design: .rounded)).foregroundStyle(Tema.murekkep)
                                    Text(d.ozet).font(.caption).foregroundStyle(Tema.soluk).multilineTextAlignment(.leading).lineLimit(2)
                                }
                                Spacer()
                                if let a = d.lab.flatMap({ Algoritma(rawValue: $0.algoritma) }) {
                                    let o = a.ozellik
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(o.ort).font(Tema.kodKucuk).foregroundStyle(Tema.murekkep)
                                        Text(o.kararli ? "stable" : "unstable").font(.caption2).foregroundStyle(Tema.soluk)
                                    }
                                }
                            }
                            .kartYuzey(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
        }
        .background(Tema.zemin.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $ders) { DersEkrani(ders: $0) }
    }
}

struct KarisikEkrani: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Ilerleme.self) private var ilerleme
    @State private var sorular: [(Ders, Int)] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if !sorular.isEmpty {
                    QuizGorunumu(sorular: sorular) { _, _ in }
                        .padding(20)
                }
            }
            .background(Tema.zemin.ignoresSafeArea())
            .navigationTitle("Mixed review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .terimSecimi()
        .onAppear { if sorular.isEmpty { sorular = ilerleme.karisikSorular(Kutuphane.shared) } }
    }
}
