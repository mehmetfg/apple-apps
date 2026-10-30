// Bugünün paketini telefonda üret: brief (Mac) → İngilizce (Qwen, cümle cümle) → Türkçe (Apple Translation,
// cihazda) → anlatım + ses (AVSpeech) → paket.json. Dil paketi yoksa sistem indirme penceresini kendisi açar.
import SwiftUI
import Translation

struct UretEkrani: View {
    @EnvironmentObject var depo: Depo
    @ObservedObject private var u = Uretici.shared
    @Environment(\.dismiss) private var kapat
    @State private var gorev: Task<Void, Never>?
    @State private var ceviriAyari: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    durumSatiri
                    if !u.modelVar {
                        Text("Model telefonda yok. Ayarlar › Telefonda üretim › Modeli içe aktar ya da Mac'ten devicectl ile kopyala (QWEN.md).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        basla()
                    } label: {
                        Label(calisiyor ? "Üretiliyor…" : "Bugünün paketini telefonda üret", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(calisiyor || !u.modelVar)
                    if calisiyor {
                        Button("Durdur", role: .destructive) { gorev?.cancel() }
                    }
                } footer: {
                    Text("Müfredatı Mac seçer (gun.py brief --json). Model yalnız İngilizce yazar; Türkçe cihazdaki Apple Çeviri'den. Ekran açık kalır.")
                }

                if let b = u.brief {
                    Section("Gün \(b.gun)") {
                        ForEach(b.sahne_konulari, id: \.self) { Label($0, systemImage: "textformat") }
                        Text("yeni: " + b.yeni.map(\.w).joined(separator: ", ")).font(.caption)
                        Text("yankı: " + b.yanki.map(\.w).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !u.cumleler.isEmpty {
                    Section("Metin") {
                        ForEach(u.cumleler) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(c.i + 1). \(c.en)").font(Tema.ingilizce(.callout))
                                if let tr = c.tr { Text(tr).font(.caption).foregroundStyle(.secondary) }
                                HStack(spacing: 6) {
                                    if let k = c.konu { Text(k).font(.caption2).foregroundStyle(Tema.kehribarYazi) }
                                    if c.deneme > 1 { Text("\(c.deneme). deneme").font(.caption2).foregroundStyle(.tertiary) }
                                }
                                if !c.sorun.isEmpty {
                                    Text("⚠ " + c.sorun.joined(separator: " · ")).font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                if let d = u.denetim {
                    Section("Denetim (derle_kurma)") {
                        Text("\(d.kelime) kelime · \(d.cumle) cümle · tanıdık %\(String(format: "%.1f", d.k3 * 100))")
                            .font(.callout.monospacedDigit())
                        if d.tamam { Label("Bütün ölçüler tuttu", systemImage: "checkmark.seal").foregroundStyle(Tema.yesil) }
                        ForEach(d.uyari, id: \.self) { Text("· " + $0).font(.caption).foregroundStyle(.orange) }
                    }
                }

                if !u.gunluk.isEmpty {
                    Section("Günlük") {
                        ForEach(Array(u.gunluk.enumerated()), id: \.offset) { Text($0.element).font(.caption2.monospaced()) }
                    }
                }
            }
            .navigationTitle("Telefonda üret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
            .translationTask(ceviriAyari) { oturum in
                await cevir(oturum)
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private var calisiyor: Bool {
        switch u.asama {
        case .hazirlik, .model, .ingilizce, .ceviri, .ses: true
        default: false
        }
    }

    @ViewBuilder private var durumSatiri: some View {
        switch u.asama {
        case .bos:
            Label(u.modelVar ? "Model hazır · \(u.modelBoyutu)" : "Model yok", systemImage: u.modelVar ? "cpu" : "exclamationmark.triangle")
        case .hazirlik: ilerleme("Brief aranıyor…", nil)
        case .model: ilerleme("Model yükleniyor…", nil)
        case .ingilizce(let i, let n):
            ilerleme("İngilizce · cümle \(i + 1)/\(n)" + (u.tokSn > 0 ? String(format: " · %.0f tok/sn", u.tokSn) : ""), Double(i) / Double(max(n, 1)))
        case .ceviri: ilerleme("Türkçe (Apple Çeviri)…", nil)
        case .ses: ilerleme("Ses ve paket…", nil)
        case .bitti(let g): Label("Gün \(g) paketi hazır — Dinle ve Oku'da", systemImage: "checkmark.circle.fill").foregroundStyle(Tema.yesil)
        case .hata(let h): Label(h, systemImage: "xmark.octagon").foregroundStyle(.red)
        }
    }

    private func ilerleme(_ metin: String, _ oran: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metin).font(.callout.monospacedDigit())
            if let oran { ProgressView(value: oran) } else { ProgressView() }
        }
    }

    private func basla() {
        UIApplication.shared.isIdleTimerDisabled = true
        gorev = Task {
            await u.ingilizceUret(depo)
            guard u.asama == .ceviri else { UIApplication.shared.isIdleTimerDisabled = false; return }
            // Çeviriyi translationTask yürütür; aynı ayarla ikinci kez tetiklemek için geçersiz kılınır.
            if ceviriAyari == nil {
                ceviriAyari = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "tr"))
            } else {
                ceviriAyari?.invalidate()
            }
        }
    }

    private func cevir(_ oturum: TranslationSession) async {
        guard u.asama == .ceviri else { return }
        do {
            try await oturum.prepareTranslation()       // dil paketi yoksa indirme penceresi burada
            let metinler = u.ceviriMetinleri
            let istek = metinler.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: "\($0.offset)") }
            var tr = [String?](repeating: nil, count: metinler.count)
            for y in try await oturum.translations(from: istek) {
                if let i = y.clientIdentifier.flatMap(Int.init), i < tr.count { tr[i] = y.targetText }
            }
            u.ceviriGeldi(tr)
            await u.paketle(depo)
        } catch {
            u.ceviriHatasi(error)
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
