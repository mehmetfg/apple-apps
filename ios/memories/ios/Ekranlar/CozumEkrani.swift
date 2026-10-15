// ③ Çözümle: Mac'te ertesi sabah yazılan cozum.json — yazımın özeti, en zayıf cümlenin düzeltmesi,
// en iyi cümle, okumaların Whisper karşılaştırması ve yarının yol haritası (en fazla 3 satır).
import SwiftUI

struct CozumEkrani: View {
    var cozum: Cozum
    @EnvironmentObject var depo: Depo
    @Environment(\.dismiss) private var kapat

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let y = cozum.yazim { yazim(y) } else {
                        Text("Yazım sonucu henüz yok — Tezgâh'ta bu gün yazılınca ertesi sabah buraya gelir.")
                            .font(.callout).foregroundStyle(.secondary).kart()
                    }
                    if cozum.macten {
                        Text("Mac'te Cümle'de yazdığın an geldi. Okumaların ertesi sabah çözümlenince bu sayfa tamamlanır.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let z = cozum.zorlar, !z.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Zorlandığın cümleler", systemImage: "pencil.and.outline").font(.headline)
                            ForEach(Array(z.enumerated()), id: \.offset) { _, d in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let tr = d.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                                    if let y = d.yazdigin { Text(y).font(Tema.ingilizce(.body)).strikethrough(color: .red.opacity(0.5)).foregroundStyle(.secondary) }
                                    if let dg = d.dogrusu { Text(dg).font(Tema.ingilizce(.title3)).foregroundStyle(Tema.yesil) }
                                }
                            }
                        }
                        .kart()
                    } else if let d = cozum.duzeltme, let dogru = d.dogrusu, let yaz = d.yazdigin {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("En çok zorlandığın cümle", systemImage: "pencil.and.outline").font(.headline)
                            if let tr = d.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                            Text(yaz).font(Tema.ingilizce(.body)).strikethrough(color: .red.opacity(0.5)).foregroundStyle(.secondary)
                            Text(dogru).font(Tema.ingilizce(.title3)).foregroundStyle(Tema.yesil)
                        }
                        .kart()
                    }
                    if let e = cozum.en_iyi, let en = e.en {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Kendinden yazdığın en iyi cümle", systemImage: "star").font(.headline)
                            Text(en).font(Tema.ingilizce(.title3))
                            if let tr = e.tr { Text(tr).font(.callout).foregroundStyle(.secondary) }
                        }
                        .kart()
                    }
                    if let o = cozum.okumalar, !o.isEmpty { okumalar(o) }
                    if let r = cozum.yol_haritasi, !r.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Yarının yol haritası", systemImage: "signpost.right").font(.headline)
                            ForEach(r) { x in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(x.tur).font(.body.weight(.semibold))
                                        Spacer()
                                        Text("son günlerde \(x.sayi)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let n = x.not { Text(n).font(.callout).foregroundStyle(.secondary) }
                                }
                            }
                            Text("Tezgâh yazmaya başlamadan önce bu satırları gösterir.").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .kart()
                    }
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(cozum.macten ? "Gün \(cozum.gun) · Mac'te yazdın" : "Gün \(cozum.gun) çözümü")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
        }
    }

    private func yazim(_ y: Cozum.Yazim) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("② Yazım", systemImage: "laptopcomputer").font(.headline)
            HStack(spacing: 22) {
                if let o = y.ilk_yazim_ort { sayi("%\(o)", "ilk yazım") }
                if let t = y.tam_isabet, let n = y.cumle { sayi("\(t)/\(n)", "tam isabet") }
                if let k = y.kendinden, let n = y.cumle { sayi("\(k)/\(n)", "bakmadan") }
            }
            if let h = y.hata_turleri, !h.isEmpty {
                let enCok = max(1, h.values.max() ?? 1)
                VStack(spacing: 6) {
                    ForEach(h.sorted { $0.value > $1.value }, id: \.key) { tur, n in
                        HStack {
                            Text(tur).font(.callout).frame(width: 70, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(Tema.kehribar.gradient).frame(width: g.size.width * CGFloat(n) / CGFloat(enCok))
                            }
                            .frame(height: 8)
                            Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .kart()
    }

    private func okumalar(_ o: [Cozum.Okuma]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Kendi sesinle okuma", systemImage: "waveform").font(.headline)
            ForEach(o, id: \.dosya) { x in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: x.cihaz == "iphone" ? "iphone" : "laptopcomputer").foregroundStyle(Tema.vurgu)
                        if let r = x.ortusme { Text("metinle %\(Int(r * 100)) örtüşüyor").font(.callout) }
                        else { Text(x.hata ?? "çözümlenemedi").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let a = x.atlanan, !a.isEmpty {
                        Text("atlanan: " + a.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(x.farkli ?? [], id: \.self) { f in
                        Text("\(f.metin) → duyulan: \(f.duyulan)").font(Tema.ingilizce(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .kart()
    }

    private func sayi(_ d: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(d).font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(Tema.vurgu)
            Text(e).font(.caption).foregroundStyle(.secondary)
        }
    }
}
