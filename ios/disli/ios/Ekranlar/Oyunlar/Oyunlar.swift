// Oyun kataloğu ve arcade ekranı. Her oyun bir yasayı oynatır; puan yalnız oyunun içinde yaşar, kaydedilmez.
import SwiftUI

enum Oyun: String, CaseIterable, Identifiable, Hashable {
    case motor, hafiza, hata, kule, merdiven, termometre, bag

    var id: String { rawValue }

    var ad: String {
        switch self {
        case .motor: "Motor"
        case .hafiza: "Hafıza"
        case .hata: "Hata Avı"
        case .kule: "Kule"
        case .merdiven: "Merdiven"
        case .termometre: "Termometre"
        case .bag: "Bağ Avı"
        }
    }

    var alt: String {
        switch self {
        case .motor: "Beş anahtarı çevir, cümle canlı değişsin. 12 zaman + edilgen + kipler tek makinede."
        case .hafiza: "Kartları çevir, konuyu örneğiyle eşle."
        case .hata: "Kaydır: doğru mu yanlış mı? Yanlışsa hatalı kelimeyi avla."
        case .kule: "Kelime taşlarını diz, her doğru cümle kuleye bir kat."
        case .merdiven: "Cümleyi bir basamak indir. Aktarma, koşul ve wish aynı merdiven."
        case .termometre: "Modalı kesinlik çizgisine yerleştir: must, might, can't…"
        case .bag: "İki konu, tek yasa. Bağlayan yasayı bul."
        }
    }

    var sembol: String {
        switch self {
        case .motor: "gearshape.2.fill"
        case .hafiza: "square.grid.3x3.fill"
        case .hata: "scope"
        case .kule: "building.columns.fill"
        case .merdiven: "stairs"
        case .termometre: "thermometer.medium"
        case .bag: "point.3.connected.trianglepath.dotted"
        }
    }

    var renk: Color {
        switch self {
        case .motor: Tema.renk("mavi")
        case .hafiza: Tema.renk("mor")
        case .hata: Tema.renk("kirmizi")
        case .kule: Tema.renk("turkuaz")
        case .merdiven: Tema.renk("turuncu")
        case .termometre: Tema.renk("gul")
        case .bag: Tema.renk("indigo")
        }
    }

    /// Oyunun oynattığı yasa
    var yasaId: String? {
        switch self {
        case .motor: "talep"
        case .merdiven: "merdiven"
        case .termometre: "olcek"
        case .kule: "anahtar"
        case .hata: "isik"
        default: nil
        }
    }

    @MainActor @ViewBuilder
    var ekran: some View {
        switch self {
        case .motor: MotorOyunu()
        case .hafiza: HafizaOyunu()
        case .hata: HataAviOyunu()
        case .kule: KuleOyunu()
        case .merdiven: MerdivenOyunu()
        case .termometre: TermometreOyunu()
        case .bag: BagAviOyunu()
        }
    }

    /// Günün konusunun yasasına göre önerilen oyun
    static func oneri(_ k: Konu) -> Oyun {
        for y in k.yasalar.map(\.id) {
            switch y {
            case "talep", "ayna": return .motor
            case "mesafe", "merdiven": return .merdiven
            case "olcek": return k.bolge == "kip" ? .termometre : .hafiza
            case "anahtar", "kapsul": return .kule
            case "isik", "kuyruk": return .hata
            case "konum": return .hafiza
            default: continue
            }
        }
        return .bag
    }

    func neden(_ k: Konu, _ depo: Depo) -> String {
        if let y = k.yasalar.first.flatMap({ depo.yasa($0.id) }) { return "Bugünün konusu “\(y.ad)” yasasıyla dönüyor" }
        return alt
    }
}

struct OyunlarEkrani: View {
    @Environment(Depo.self) private var depo
    let ac: (Acilan) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Her oyun bir yasayı oynatır. Puan oyunda kalır; kaydedilmez, kıyaslanmaz.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Oyun.allCases) { o in
                            Button { Dokunus.orta(); ac(.oyun(o)) } label: { OyunKutusu(oyun: o) }
                                .buttonStyle(BasinStil())
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Lekeler(renkler: [Tema.renk("mor"), Tema.renk("turuncu")]))
            .navigationTitle("Oyunlar")
        }
    }
}

struct OyunKutusu: View {
    @Environment(Depo.self) private var depo
    let oyun: Oyun
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cizim(ad: "oyun-" + oyun.rawValue, renk: oyun.renk, boy: 64, zemin: false)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(oyun.renk.opacity(0.13)))
            Text(oyun.ad).font(Tema.baslik(.headline)).foregroundStyle(.primary)
            Text(oyun.alt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let y = oyun.yasaId.flatMap({ depo.yasa($0) }) {
                YasaRozeti(yasa: y, kucuk: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Tema.yuzey)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Tema.cizgi))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
    }
}

struct BasinStil: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Oyun sonu: puan + kısa ders + yeniden / kapat
struct OyunSonu: View {
    @Environment(Depo.self) private var depo
    let oyun: Oyun
    let buyuk: String
    let aciklama: String
    var ders: String? = nil
    let tekrar: () -> Void
    let kapat: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer()
                Cizim(ad: "oyun-" + oyun.rawValue, renk: oyun.renk, boy: 96)
                Text(buyuk).font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(oyun.renk)
                Text(aciklama).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                if let ders {
                    Text(ders).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding().background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(oyun.renk.opacity(0.1)))
                }
                Spacer()
                Button(action: tekrar) {
                    Label("Bir tur daha", systemImage: "arrow.clockwise").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Capsule().fill(oyun.renk))
                }
                .buttonStyle(.plain)
                Button("Kapat", action: kapat).font(.headline).padding(.bottom)
            }
            .padding(.horizontal, 24)
            Konfeti()
        }
        .onAppear { depo.bitti("oyun"); Dokunus.basari() }
    }
}
