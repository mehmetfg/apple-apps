// Kamera: eşyanın adı eşyanın üstünde. Canlı etiket (kesik çerçeve) = model şu an görüyor; dolu etiket = odaya yerleşti.
// Dokun: duy + kart. Uzun bas: sil / biliyorum. + : ortadaki artıya elle kelime koy. Sına: adlar gizlenir, dokununca açılır.
import ARKit
import RealityKit
import SwiftUI

struct KameraEkrani: View {
    @EnvironmentObject var goz: Goz
    @EnvironmentObject var ses: Ses
    @State private var secili: Kelime?
    @State private var elle = false
    @State private var secici = false
    @State private var sinav = false
    @State private var acilan: Set<String> = []
    @State private var sifirSorusu = false

    var body: some View {
        ZStack {
            if goz.destek {
                ARKap().ignoresSafeArea()
                etiketKatmani.ignoresSafeArea()
            } else {
                ContentUnavailableView("Kamera ARKit ister", systemImage: "arkit",
                                       description: Text("Simülatörde çalışmaz. iPhone'da kamera açılınca eşyaların İngilizce adı üstlerinde belirir. Sözlük sekmesi burada da çalışır."))
            }
            if elle { arti }
            VStack {
                ustCubuk
                if let i = goz.ipucu { Text(i).font(.footnote.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule()) }
                Spacer()
                altCubuk
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .onAppear { goz.baslat() }
        .sheet(item: $secili) { KelimeKarti(k: $0).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $secici) {
            KelimeSecici(oda: goz.oda) { k in
                secici = false
                let o = UIScreen.main.bounds
                if goz.elleBirak(k, nokta: CGPoint(x: o.midX, y: o.midY)) { elle = false }
            }
        }
        .confirmationDialog("Bu odanın bütün etiketleri ve oda haritası silinsin mi?", isPresented: $sifirSorusu, titleVisibility: .visible) {
            Button("Odayı sıfırla", role: .destructive) { goz.odayiSifirla() }
        }
    }

    // MARK: etiketler
    private var etiketKatmani: some View {
        ZStack {
            ForEach(goz.canlilar) { c in
                CanliCerceve(c: c, gizli: sinav && !acilan.contains(c.kelime.en))
                    .onTapGesture { dokun(c.kelime) }
            }
            ForEach(goz.gorunenler) { g in
                EtiketGorunumu(g: g, gizli: sinav && !acilan.contains(g.kelime.en), bilinen: Kasa.bilinen.contains(g.kelime.en))
                    .position(g.nokta)
                    .onTapGesture { dokun(g.kelime) }
                    .contextMenu {
                        Button { ses.oku(g.kelime) } label: { Label("Dinle", systemImage: "speaker.wave.2") }
                        Button { var b = Kasa.bilinen; b.insert(g.kelime.en); Kasa.bilinen = b } label: { Label("Biliyorum", systemImage: "checkmark") }
                        Button(role: .destructive) { goz.sil(g.id) } label: { Label("Etiketi kaldır (yanlış)", systemImage: "trash") }
                    }
            }
        }
        .animation(.easeOut(duration: 0.12), value: goz.gorunenler)
    }

    private func dokun(_ k: Kelime) {
        if sinav, !acilan.contains(k.en) { acilan.insert(k.en); ses.oku(k); Haptik.secim(); return }
        ses.oku(k)
        secili = k
    }

    // MARK: çubuklar
    private var ustCubuk: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(goz.sozluk.odalar) { o in
                    Button { goz.odaDegistir(o.id) } label: { Label(o.ad, systemImage: o.simge) }
                }
            } label: {
                let o = goz.sozluk.odalar.first { $0.id == goz.oda }
                HStack(spacing: 6) {
                    Image(systemName: o?.simge ?? "house")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(o?.en ?? "").font(.system(size: 15, weight: .bold))
                        Text("\(goz.yerlesenler.count)/\(goz.odaKelimeleri.count) eşya").font(.system(size: 10, weight: .semibold)).opacity(0.75)
                    }
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
            }
            Spacer()
            yuvarlak(ses.acik ? "speaker.wave.2.fill" : "speaker.slash.fill", aktif: ses.acik) { ses.acik.toggle(); Haptik.secim() }
            yuvarlak(sinav ? "questionmark.circle.fill" : "questionmark.circle", aktif: sinav) { sinav.toggle(); acilan = []; Haptik.secim() }
            Menu {
                Toggle("Kendiliğinden etiket bırak", isOn: $goz.otomatikYerlestir)
                Toggle("Oxford'un gerçek telaffuzu", isOn: $ses.oxford)
                Picker("Aksan", selection: $ses.aksan) { Text("İngiliz").tag("en-GB"); Text("Amerikan").tag("en-US") }
                Button(role: .destructive) { sifirSorusu = true } label: { Label("Bu odayı sıfırla", systemImage: "arrow.counterclockwise") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(.black.opacity(0.45), in: Circle())
            }
        }
    }

    private var altCubuk: some View {
        HStack {
            if sinav {
                Label("Sına: adlar gizli. Önce söyle, sonra dokun.", systemImage: "brain.head.profile")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.black.opacity(0.5), in: Capsule())
            }
            Spacer()
            if elle {
                Button("Vazgeç") { elle = false }.buttonStyle(.bordered).tint(.white)
                Button { secici = true } label: { Label("Buraya ne var?", systemImage: "text.badge.plus") }
                    .buttonStyle(.borderedProminent).tint(.saray)
            } else {
                Button { elle = true; Haptik.secim() } label: {
                    Image(systemName: "plus").font(.system(size: 24, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 60, height: 60).background(Color.saray, in: Circle()).shadow(radius: 6)
                }
                .accessibilityLabel("Elle etiket koy")
            }
        }
    }

    private var arti: some View {
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 34, height: 34)
            Circle().fill(Color.saray).frame(width: 6, height: 6)
        }
        .shadow(radius: 3)
        .allowsHitTesting(false)
    }

    private func yuvarlak(_ simge: String, aktif: Bool, _ eylem: @escaping () -> Void) -> some View {
        Button(action: eylem) {
            Image(systemName: simge).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(aktif ? .black : .white)
                .frame(width: 40, height: 40)
                .background(aktif ? AnyShapeStyle(Color.saray) : AnyShapeStyle(.black.opacity(0.45)), in: Circle())
        }
    }
}

/// ARView'ı SwiftUI'ye taşır.
struct ARKap: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView { Goz.shared.arView }
    func updateUIView(_ v: ARView, context: Context) {}
}

/// Odaya yerleşmiş etiket: yakındaysa büyük, uzaktaysa küçük. İngilizce ad + telaffuz; altında Türkçe soluk.
struct EtiketGorunumu: View {
    let g: Gorunen
    let gizli: Bool
    let bilinen: Bool

    var body: some View {
        let olcek = CGFloat(max(0.62, min(1.25, 1.6 / Double(max(0.5, g.mesafe)))))
        VStack(spacing: 2) {
            Text(gizli ? "?" : g.kelime.en)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if !gizli {
                if !g.kelime.ses.isEmpty { Text(g.kelime.ses).font(.system(size: 12, weight: .medium, design: .serif)).foregroundStyle(.white.opacity(0.85)) }
                Text(g.kelime.tr).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(bilinen ? .white.opacity(0.3) : Color.saray, lineWidth: 1.5))
        .overlay(alignment: .bottom) {
            Triangle().fill(bilinen ? .white.opacity(0.3) : Color.saray).frame(width: 12, height: 7).offset(y: 7)
        }
        .scaleEffect(olcek)
        .offset(y: -24)
    }
}

/// Model şu an görüyor ama henüz odaya yerleşmedi: eşyanın çevresinde kesik çerçeve + adı.
struct CanliCerceve: View {
    let c: Canli
    let gizli: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .frame(width: c.kutu.width, height: c.kutu.height)
            Text(gizli ? "?" : c.kelime.en)
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.black)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.9), in: Capsule())
                .offset(x: 6, y: -12)
        }
        .position(x: c.kutu.midX, y: c.kutu.midY)
        .allowsHitTesting(true)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p }
}
