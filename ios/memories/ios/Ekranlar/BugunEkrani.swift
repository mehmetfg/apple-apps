// Bugün: çantadaki paket (yarın Mac'te yazılacak metin) + üç adım + dünün çözümü.
import SwiftUI

struct BugunEkrani: View {
    @EnvironmentObject var depo: Depo
    @EnvironmentObject var oynatici: Oynatici
    @Binding var sekme: Sekme
    @State private var cozumAcik = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !depo.kasa.bagli {
                        baglanti
                    } else if let p = depo.guncel {
                        kapak(p)
                        adimlar(p)
                        gunler(p)
                        if let c = depo.sonCozum { cozumKarti(c) }
                        akis
                    } else {
                        BosDurum(simge: "tray", baslik: "Paket henüz yok",
                                 metin: "Sabah görevi Mac'te paketi hazırlayınca burada görünür. Vault bağlı; aşağı çekip yenileyebilirsin.")
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Memories")
            .refreshable { await depo.esitleSimdi() }
            .sheet(isPresented: $cozumAcik) {
                if let c = depo.sonCozum { CozumEkrani(cozum: c).environmentObject(depo) }
            }
            .overlay(alignment: .top) { bilgiBandi }
        }
    }

    // MARK: Parçalar

    private var baglanti: some View {
        VStack(spacing: 16) {
            BosDurum(simge: "folder.badge.plus", baslik: "Vault'u bağla",
                     metin: "Ayarlar › Vault klasörü'nden iCloud Drive › Obsidian › Personel Data Management klasörünü bir kez seç. Paketler oradan iner, kayıtların oraya gider.")
            Button { sekme = .ayarlar } label: {
                Label("Ayarlar'a git", systemImage: "gearshape").frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .kart(20)
        .padding(.top, 20)
    }

    private func kapak(_ p: Paket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GÜN \(p.gun)").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Label(Tarih.dakika(p.sure), systemImage: "headphones").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
            }
            Text(p.ad).font(.system(.largeTitle, design: .serif).weight(.semibold)).foregroundStyle(.white)
            if let o = p.ozet {
                Text(o).font(.callout).foregroundStyle(.white.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            }
            if let k = p.sahne_konulari, !k.isEmpty {
                HStack(spacing: 6) {
                    ForEach(k, id: \.self) { Cip(metin: $0, renk: .white, simge: "textformat") }
                }
            }
            Button {
                sekme = .dinle
                oynatici.cal(p)
            } label: {
                Label(oynatici.paket?.gun == p.gun && oynatici.caliyor ? "Çalıyor — dinleme ekranı" : "Dinle",
                      systemImage: oynatici.caliyor ? "waveform" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tema.vurguKoyu)
            .background(Capsule().fill(.white))
            .disabled(depo.sesURL(p) == nil)
            .opacity(depo.sesURL(p) == nil ? 0.6 : 1)
            if depo.sesURL(p) == nil {
                Text(depo.esitleniyor ? "Ses iniyor…" : "Ses henüz telefona inmedi — aşağı çekip yenile.")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Tema.egim))
        .shadow(color: Tema.vurgu.opacity(0.25), radius: 18, y: 8)
        .padding(.top, 6)
    }

    private func adimlar(_ p: Paket) -> some View {
        let h = depo.hazirlik(p.gun)
        return VStack(spacing: 0) {
            HStack {
                Text("① Çalış").font(.headline)
                Spacer()
                if h.hazir {
                    Label("Hazırsın", systemImage: "checkmark.seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Tema.yesil)
                } else {
                    Text("\(h.adim)/3").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)
            adim("Dinle", "Açıklama → metin → kelimeler ve yapılar. İstersen 2-3 kez.",
                 AdimHalkasi(dolu: min(1, Double(h.dinleme)), renk: Tema.vurgu, simge: "headphones", sayi: h.dinleme)) { sekme = .dinle }
            Divider().padding(.leading, 62)
            adim("Ekrandan oku", "Kelimeye dokun: anlamı. Cümleye uzun bas: Türkçesi.",
                 AdimHalkasi(dolu: h.okuma ? 1 : 0, renk: Tema.kehribar, simge: "text.alignleft")) { sekme = .oku }
            Divider().padding(.leading, 62)
            adim("Kendi sesinle oku", h.kayit > 0 ? "\(h.kayit) kayıt — Mac'te ertesi sabah çözümlenir." : "Metni sesli oku, kaydet. Mac'te de yapabilirsin.",
                 AdimHalkasi(dolu: h.kayit > 0 ? 1 : 0, renk: Tema.yesil, simge: "mic", sayi: h.kayit > 1 ? h.kayit : nil)) { sekme = .kaydet }
            if !h.hazir && h.basladi {
                Button("Yeterli — hazırım") { depo.hazirim(p) }
                    .font(.subheadline.weight(.medium)).padding(.top, 12)
            }
        }
        .kart()
    }

    /// Haftalık tampon: günler arasında gezin, «Yaptım, geç» ile günü atla (Mac'te de görünür).
    private func gunler(_ p: Paket) -> some View {
        let yapilan = depo.yazilanGunler, atlanan = depo.atlananGunler
        let liste = depo.paketler.filter { !yapilan.contains($0.gun) || $0.gun == p.gun }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Günler").font(.headline)
                Spacer()
                Text("\(liste.filter { !atlanan.contains($0.gun) && !yapilan.contains($0.gun) }.count) açık").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(liste) { g in
                        let secili = g.gun == p.gun
                        let gecildi = atlanan.contains(g.gun)
                        Button { depo.gunSec(g.gun) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("Gün \(g.gun)").font(.subheadline.weight(.semibold))
                                    if gecildi { Image(systemName: "arrowshape.turn.up.right").font(.caption2) }
                                    else if yapilan.contains(g.gun) { Image(systemName: "checkmark").font(.caption2) }
                                }
                                Text(g.ad).font(.caption).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: 150, alignment: .leading)
                            .foregroundStyle(secili ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(secili ? Tema.vurgu : Color(.tertiarySystemGroupedBackground)))
                            .opacity(gecildi && !secili ? 0.6 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !yapilan.contains(p.gun) && !atlanan.contains(p.gun) {
                Button { depo.atla(p) } label: {
                    Label("Yaptım, geç", systemImage: "arrowshape.turn.up.right").font(.subheadline.weight(.medium))
                }
                Text("Bu günü başka yerde yaptıysan ya da tekrar istemiyorsan: sicile girmez, sıradaki gün açılır; Mac de görür.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kart()
    }

    private func adim<H: View>(_ baslik: String, _ alt: String, _ halka: H, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            HStack(spacing: 14) {
                halka
                VStack(alignment: .leading, spacing: 2) {
                    Text(baslik).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(alt).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cozumKarti(_ c: Cozum) -> some View {
        Button { cozumAcik = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(c.macten ? "② Gün \(c.gun) · Mac'te yazdın" : "③ Gün \(c.gun) çözümü", systemImage: c.macten ? "laptopcomputer" : "sparkles")
                        .font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if let y = c.yazim, let o = y.ilk_yazim_ort {
                    HStack(spacing: 18) {
                        sayi("%\(o)", "ilk yazım")
                        if let t = y.tam_isabet, let n = y.cumle { sayi("\(t)/\(n)", "tam isabet") }
                        if let ok = c.okumalar?.compactMap(\.ortusme).max() { sayi("%\(Int(ok * 100))", "okuma") }
                    }
                }
                if c.macten, let z = c.zorlar?.first, let d = z.dogrusu {
                    Text("Zorlandığın: “\(d)”").font(Tema.ingilizce(.callout)).foregroundStyle(.secondary).lineLimit(2)
                } else if let e = c.en_iyi?.en {
                    Text("“\(e)”").font(Tema.ingilizce(.callout)).foregroundStyle(.secondary).lineLimit(2)
                }
                if let r = c.yol_haritasi?.first {
                    Label("Yarın dikkat: \(r.tur)", systemImage: "signpost.right").font(.caption.weight(.medium)).foregroundStyle(Tema.kehribarYazi)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kart()
        }
        .buttonStyle(.plain)
    }

    private func sayi(_ d: String, _ e: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(d).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Tema.vurgu)
            Text(e).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var akis: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone").foregroundStyle(Tema.vurgu)
            Text("çalış").foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Image(systemName: "laptopcomputer").foregroundStyle(Tema.kehribar)
            Text("yaz").foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Image(systemName: "sparkles").foregroundStyle(Tema.yesil)
            Text("çözümle").foregroundStyle(.secondary)
            Spacer()
            if let s = depo.sonEsitleme { Text(Tarih.gorece(s)).font(.caption2).foregroundStyle(.tertiary) }
        }
        .font(.caption)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var bilgiBandi: some View {
        if let b = depo.bilgi {
            Text(b).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(.regularMaterial))
                .shadow(radius: 8, y: 3)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task { try? await Task.sleep(nanoseconds: 3_000_000_000); withAnimation { depo.bilgi = nil } }
        }
    }
}
