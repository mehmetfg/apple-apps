// Pencere: solda kenar çubuğu (bugünün adımları + geçmiş + telefonun durumu), ortada tek sütun çalışma alanı,
// sağda yalnız cümle turunda ve hesapta açılan metin haritası (⌘0). Yazarken yanda başka bir şey durmaz.
import SwiftUI
import UniformTypeIdentifiers

struct Ana: View {
    @EnvironmentObject var t: Tezgah
    @State private var sutun: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sutun) {
            KenarCubugu().navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            HStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    Group {
                        switch t.gorunum {
                        case .bugun: BugunGorunum()
                        case .gecmis: GecmisGorunum()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let b = t.bildirim {
                        Text(b).font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(.regularMaterial)).shadow(radius: 6, y: 2).padding(.bottom, 22)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Renk.zemin)
                .animation(.easeOut(duration: 0.2), value: t.bildirim)
                // sağ sütun: yalnız cümle turunda ve hesapta (inspector değil — kenar çubuğuyla birlikte AppKit'i çökertiyor)
                if haritaVar && t.haritaAcik {
                    Divider()
                    MetinHaritasi().frame(width: 310).background(Renk.kart)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeOut(duration: 0.2), value: haritaVar && t.haritaAcik)
            .toolbar { AracCubugu(haritaVar: haritaVar) }
            .navigationTitle(baslik)
            .navigationSubtitle(altBaslik)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { birak($0) }
        .sheet(isPresented: $t.kuizAcik) { KuizSayfasi().environmentObject(t) }
        .sheet(item: Binding(get: { t.gramerSayfa.map(GramerListe.init) }, set: { t.gramerSayfa = $0?.konular })) { _ in
            GramerSayfasi().environmentObject(t)
        }
    }

    /// Pencereye sürüklenen gün JSON'ları içe aktarılır.
    private func birak(_ saglayicilar: [NSItemProvider]) -> Bool {
        let kilit = NSLock(), grup = DispatchGroup()
        var urller: [URL] = []
        for p in saglayicilar {
            grup.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { kilit.lock(); urller.append(u); kilit.unlock() }
                grup.leave()
            }
        }
        let tez = t
        grup.notify(queue: .main) { Task { @MainActor in tez.iceAktar(urller) } }
        return true
    }

    var haritaVar: Bool { t.gorunum == .bugun && (t.o?.adim == .cumle || t.o?.adim == .bitis) }
    var baslik: String {
        if t.gorunum == .gecmis { return "Geçmiş" }
        guard let o = t.o else { return "Cümle" }
        return "Gün \(o.gun.no) · \(o.gun.ad)" + (o.tekrar ? " · tekrar" : "")
    }
    var altBaslik: String { t.gorunum == .bugun ? (t.o?.adim.etiket ?? "Bugünün modülü") : "" }
}

struct GramerListe: Identifiable { var konular: [String]; var id: String { konular.joined(separator: "|") } }

struct AracCubugu: ToolbarContent {
    var haritaVar: Bool
    @EnvironmentObject var t: Tezgah
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if t.o != nil && t.gorunum == .bugun {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Label(t.sureYazi, systemImage: "timer").labelStyle(.titleAndIcon).monospacedDigit().foregroundStyle(.secondary)
                }
                .help("Dokunulan süre — 2 dakikadan uzun boşluk sayılmaz")
            }
            Button { t.gramerAc() } label: { Label("Gramer", systemImage: "book.closed") }.help("Bugünün gramer konuları (⌥G)")
            Button { t.kuizAcik = true } label: { Label("Kuiz", systemImage: "sparkles") }.help("Kuiz promptu → Gemini (⌘K)")
            SesMenusu()
            if haritaVar {
                Button { t.haritaAcik.toggle() } label: { Label("Metin haritası", systemImage: "sidebar.right") }.help("Metin haritası (⌘0)")
            }
        }
    }
}

struct SesMenusu: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        Menu {
            Toggle("Yazdıktan sonra doğrusunu oku", isOn: Binding(get: { t.ses.acik }, set: { t.ses.acik = $0 }))
            Picker("Hız", selection: Binding(get: { t.ses.hiz }, set: { t.ses.hiz = $0 })) {
                ForEach([0.7, 0.8, 0.9, 1.0, 1.1, 1.2], id: \.self) { Text(String(format: "%.1f×", $0)).tag($0) }
            }
            Picker("Ses", selection: Binding(get: { t.ses.ses?.identifier ?? "" }, set: { t.ses.sesAdi = $0 })) {
                ForEach(Ses.sesler, id: \.identifier) { v in Text("\(v.name) · \(v.language)").tag(v.identifier) }
            }
            Button("Sesi dene") { t.ses.dene() }
        } label: { Label("Ses", systemImage: t.ses.acik ? "speaker.wave.2" : "speaker.slash") }
        .help("Ses ayarı")
    }
}

// MARK: - Kenar çubuğu

struct KenarCubugu: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        List {
            Section("Bugün") {
                satir(simge: "sun.max", ad: t.o.map { "Gün \($0.gun.no) · \($0.gun.ad)" } ?? "Bugünün modülü", secili: t.gorunum == .bugun && t.o == nil) {
                    t.gorunum = .bugun
                }
                if let o = t.o {
                    ForEach(Adim.allCases) { a in
                        let acik = a.sira <= o.enIleri
                        Button { t.gorunum = .bugun; t.adimaGit(a) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: a.sira < o.adim.sira || (acik && a != o.adim) ? "checkmark.circle.fill" : a.simge)
                                    .foregroundStyle(a == o.adim ? Renk.vurgu : acik ? Renk.yesil : .secondary)
                                    .frame(width: 18)
                                Text("\(a.sira + 1). \(a.etiket)")
                                Spacer()
                                Text(t.sayac(a)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!acik)
                        .opacity(acik ? 1 : 0.45)
                        .listRowBackground(t.gorunum == .bugun && o.adim == a ? RoundedRectangle(cornerRadius: 6).fill(Renk.vurgu.opacity(0.14)) : nil)
                    }
                }
            }
            Section("Günler") {
                ForEach(t.gunSatirlari) { g in
                    Button { t.gunSec(g.no) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: g.durum == .yapildi ? "checkmark.circle.fill" : g.durum == .atlandi ? "arrowshape.turn.up.right.circle" : g.secili ? "circle.inset.filled" : "circle")
                                .foregroundStyle(g.durum == .yapildi ? Renk.yesil : g.durum == .atlandi ? Renk.sari : g.secili ? Renk.vurgu : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Gün \(g.no)").font(.callout.weight(g.secili ? .semibold : .regular))
                                Text(g.baslik).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            if g.ses { Image(systemName: "headphones").font(.caption2).foregroundStyle(.tertiary).help("Telefonda sesli paket hazır") }
                        }
                        .padding(.vertical, 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(g.secili ? RoundedRectangle(cornerRadius: 6).fill(Renk.vurgu.opacity(0.14)) : nil)
                }
                satir(simge: "square.and.arrow.down", ad: "İçe aktar…", secili: false) { t.iceAktarPaneli() }
            }
            Section("Arşiv") {
                satir(simge: "clock.arrow.circlepath", ad: "Geçmiş", secili: t.gorunum == .gecmis) { t.gorunum = .gecmis }
                satir(simge: "book.closed", ad: "Gramer döngüsü", secili: false) { t.gramerI = -1; t.gramerAc(nil, -1) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.035, green: 0.041, blue: 0.058))
        .safeAreaInset(edge: .bottom) { TelefonOzeti().padding(10) }
    }

    func satir(simge: String, ad: String, secili: Bool, _ e: @escaping () -> Void) -> some View {
        Button(action: e) {
            Label(ad, systemImage: simge).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(secili ? RoundedRectangle(cornerRadius: 6).fill(Renk.vurgu.opacity(0.14)) : nil)
    }
}

/// Kenar çubuğunun altında, her zaman: telefonun bu gün için yaptıkları (canlı).
struct TelefonOzeti: View {
    @EnvironmentObject var t: Tezgah
    var body: some View {
        let h = t.hazirlik
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "iphone").foregroundStyle(h.basladi ? Renk.yesil : .secondary)
                Text(h.basladi ? "Telefonda çalışıldı" : h.paket ? "Telefonda henüz yok" : "Paket yok").font(.caption.weight(.semibold))
            }
            HStack(spacing: 10) {
                Label("\(h.dinleme)", systemImage: "headphones").foregroundStyle(h.dinleme > 0 ? Renk.yesil : .secondary)
                Label(h.okuma ? "✓" : "—", systemImage: "book").foregroundStyle(h.okuma ? Renk.yesil : .secondary)
                Label("\(h.kayit)", systemImage: "mic").foregroundStyle(h.kayit > 0 ? Renk.yesil : .secondary)
                if !h.takildi.isEmpty { Label("\(h.takildi.count)", systemImage: "arrow.counterclockwise").foregroundStyle(Renk.sari).help("Telefonda takıldığın cümle") }
            }
            .font(.caption.monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Renk.kart2))
        .help("Memories (iPhone) ile ortak klasörden canlı okunur")
    }
}

// MARK: - Metin haritası (sağ)

struct MetinHaritasi: View {
    @EnvironmentObject var t: Tezgah
    @State private var kip = "tr"
    var body: some View {
        if let o = t.o {
            VStack(alignment: .leading, spacing: 0) {
                Picker("", selection: $kip) { Text("Türkçe").tag("tr"); Text("İngilizce").tag("en") }
                    .pickerStyle(.segmented).labelsHidden().padding(12)
                ScrollViewReader { sv in
                    List {
                        ForEach(0..<o.toplam, id: \.self) { i in
                            satir(o, i).id(i)
                                .listRowBackground(i == o.i && o.adim == .cumle ? RoundedRectangle(cornerRadius: 6).fill(Renk.vurgu.opacity(0.14)) : nil)
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: o.i) { _, i in withAnimation { sv.scrollTo(i, anchor: .center) } }
                }
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    if !t.hazirlik.takildi.isEmpty {
                        Label("telefonda takıldığın cümle", systemImage: "iphone").foregroundStyle(Renk.sari)
                    }
                    Text(kip == "en" ? "yazmadığın cümle gizli — cevap vermesin" : "satıra tıkla → o cümleye git")
                }
                .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    @ViewBuilder func satir(_ o: Oturum, _ i: Int) -> some View {
        let c = o.cumle(i), tr = o.tur(i), y = tr?.y
        let tam = y.map { $0.atlanan.isEmpty && $0.fazladan.isEmpty } ?? false
        Button { t.gorunum = .bugun; t.cumleGit(i) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    if kip == "tr" { Text(c.tr ?? c.en).font(.callout) }
                    else if y != nil { Text(c.en).font(.serif(14)) }
                    else { Text(i == o.i ? "— şu an yazdığın cümle —" : "— henüz yazılmadı —").font(.callout).foregroundStyle(.tertiary) }
                    if let n = t.hazirlik.takildi[i] {
                        Label(n > 1 ? "telefonda \(n) kez" : "telefonda takıldın", systemImage: "iphone").font(.caption2).foregroundStyle(Renk.sari)
                    }
                }
                Spacer(minLength: 4)
                Group {
                    if let y { Text(tam ? "✓" : "%\(y.yuzde)").foregroundStyle(tam ? Renk.yesil : y.yuzde >= 85 ? Renk.vurgu : Renk.sari) }
                    else { Text("○").foregroundStyle(.tertiary) }
                }
                .font(.caption.weight(.semibold).monospacedDigit())
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
