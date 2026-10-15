// Ortak parçalar: işaret kartı, bölüm rozeti, ilerleme halkası, kâğıt zemin.
import SwiftUI

struct Halka: View {
    var oran: Double
    var renk: Color = .kalem
    var kalinlik: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().stroke(Color.cizgi, lineWidth: kalinlik)
            Circle().trim(from: 0, to: max(0.001, min(1, oran)))
                .stroke(renk, style: StrokeStyle(lineWidth: kalinlik, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: oran)
        }
    }
}

struct BolumRozeti: View {
    var no: Int
    var boy: CGFloat = 26
    var dolu = true
    var body: some View {
        Text("§\(no)")
            .font(.system(size: boy * 0.46, weight: .bold, design: .serif))
            .foregroundStyle(dolu ? .white : Color.bolum(no))
            .frame(width: boy, height: boy)
            .background(Circle().fill(dolu ? Color.bolum(no) : Color.bolum(no).opacity(0.14)))
    }
}

struct Cip: View {
    var metin: String
    var simge: String? = nil
    var renk: Color = .soluk
    var body: some View {
        HStack(spacing: 4) {
            if let simge { Image(systemName: simge) }
            Text(metin)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(renk)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(renk.opacity(0.12)))
    }
}

struct IsaretKarti: View {
    @EnvironmentObject var merkez: Merkez
    let x: Isaret
    var satir: Int? = 6
    var oneriGoster = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: x.kaynak.simge).font(.caption).foregroundStyle(Color.soluk)
                Text(x.kitapAdi).font(.caption.weight(.semibold)).foregroundStyle(Color.soluk).lineLimit(1)
                Spacer(minLength: 4)
                if let r = x.rol { Cip(metin: r.ad, simge: r.simge, renk: .kalem) }
                Text(x.tarih, format: .dateTime.day().month(.abbreviated)).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(x.metin)
                .font(.serif(16))
                .foregroundStyle(Color.murekkep)
                .lineLimit(satir)
                .fixedSize(horizontal: false, vertical: true)
            if !x.not.isEmpty {
                Text(x.not).font(.footnote.italic()).foregroundStyle(Color.kalem)
            }
            if oneriGoster, let b = Ilgi.oneri(x.metin, merkez.d.metin) {
                Button { merkez.ata(x.id, b.id) } label: {
                    HStack(spacing: 6) {
                        BolumRozeti(no: b.no, boy: 20)
                        Text("Öneri: \(b.baslik)").font(.footnote.weight(.semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(Color.bolum(b.no))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.kart))
        .overlay(alignment: .leading) {
            if let b = x.bolum, let bol = merkez.d.metin?.bolumler.first(where: { $0.id == b }) {
                RoundedRectangle(cornerRadius: 2).fill(Color.bolum(bol.no)).frame(width: 4).padding(.vertical, 10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.cizgi, lineWidth: 0.6))
    }
}

/// İşarete uzun basınca çıkan menü: bölüme gönder, rol, metne girmez, sil.
struct IsaretMenusu: View {
    @EnvironmentObject var merkez: Merkez
    let x: Isaret
    var body: some View {
        if let m = merkez.d.metin {
            Section("Bölüme gönder") {
                ForEach(m.bolumler) { b in
                    Button { merkez.ata(x.id, b.id) } label: { Label("§\(b.no) \(b.baslik)", systemImage: x.bolum == b.id ? "checkmark" : "\(b.no).circle") }
                }
            }
        }
        if x.bolum != nil {
            Menu("Rol") {
                ForEach(Rol.allCases, id: \.self) { r in
                    Button { merkez.rol(x.id, x.rol == r ? nil : r) } label: { Label(r.ad, systemImage: x.rol == r ? "checkmark" : r.simge) }
                }
            }
            Button { merkez.ata(x.id, nil) } label: { Label("Kutu'ya geri al", systemImage: "tray.and.arrow.up") }
        }
        Button { UIPasteboard.general.string = x.metin } label: { Label("Kopyala", systemImage: "doc.on.doc") }
        if x.disarida {
            Button { merkez.geriAl(x.id) } label: { Label("Kutu'ya geri al", systemImage: "arrow.uturn.backward") }
        } else {
            Button(role: .destructive) { merkez.disariAt(x.id) } label: { Label("Metne girmez", systemImage: "xmark.circle") }
        }
        if x.kaynak != .vd {
            Button(role: .destructive) { merkez.sil(x.id) } label: { Label("Sil", systemImage: "trash") }
        }
    }
}

struct Baslik: View {
    var ust: String
    var ana: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ust.uppercased()).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.kalem)
            Text(ana).font(.serif(28, .semibold)).foregroundStyle(Color.murekkep)
        }
    }
}

extension View {
    func kagitZemin() -> some View { background(Color.kagit.ignoresSafeArea()) }
}
