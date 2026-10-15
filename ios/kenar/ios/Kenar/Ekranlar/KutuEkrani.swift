// Kutu: bölüme atanmayı bekleyen işaretler. Kartı basılı tutup alttaki bölüm şeridine sürükle; öneriye dokun; ya da "metne girmez".
// Sıra metinle ilgiye göredir — Kant'la ilgisi en yüksek işaret en üstte.
import SwiftUI

struct KutuEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @State private var gorunum = 0
    @State private var hedef: String?
    @State private var elle = false
    @State private var kutuphane = false

    private var liste: [Isaret] {
        let m = merkez.d.metin
        switch gorunum {
        case 1: return merkez.d.kutu.sorted { $0.tarih > $1.tarih }
        case 2: return merkez.d.isaretler.filter(\.disarida).sorted { $0.tarih > $1.tarih }
        default: return merkez.d.kutu.sorted { Ilgi.puan($0.metin, m) > Ilgi.puan($1.metin, m) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: $gorunum) {
                        Text("İlgili").tag(0); Text("Yeni").tag(1); Text("Dışarıda").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if gorunum != 2 {
                        Text("Basılı tut, alttaki bölüme sürükle. Öneriye dokunmak da olur.")
                            .font(.footnote).foregroundStyle(Color.soluk)
                    }
                    if liste.isEmpty {
                        ContentUnavailableView(gorunum == 2 ? "Dışarıda işaret yok" : "Kutu boş",
                                               systemImage: gorunum == 2 ? "xmark.bin" : "tray",
                                               description: Text(gorunum == 2 ? "Metne girmez dediklerin burada durur, silinmez." : "Voice Dream'de işaretle, kâğıt kitapta kamerayla seç ya da bir uygulamadan Kenar'a paylaş."))
                            .padding(.top, 40)
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(liste) { x in
                            IsaretKarti(x: x, satir: 7, oneriGoster: gorunum != 2)
                                .contextMenu { IsaretMenusu(x: x) }
                                .draggable(x.id) {
                                    Text(x.metin.prefix(80) + "…").font(.serif(14)).padding(10).frame(width: 240)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.kart))
                                }
                                .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .animation(.snappy, value: liste.map(\.id))
                }
                .padding(.horizontal, 16).padding(.bottom, 110)
            }
            .kagitZemin()
            .navigationTitle("Kutu")
            .refreshable { await merkez.esitle() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { elle = true } label: { Label("Elle işaret yaz", systemImage: "pencil") }
                        Button { kutuphane = true } label: { Label("Voice Dream'den seç", systemImage: "headphones") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) { if gorunum != 2 { bolumSeridi } }
            .sheet(isPresented: $elle) { ElleIsaret() }
            .sheet(isPresented: $kutuphane) { KutuphaneEkrani() }
        }
    }

    private var bolumSeridi: some View {
        HStack(spacing: 8) {
            ForEach(merkez.d.metin?.bolumler ?? []) { b in
                let isik = hedef == b.id
                VStack(spacing: 3) {
                    BolumRozeti(no: b.no, boy: isik ? 34 : 28)
                    Text(b.baslik.components(separatedBy: ":").first ?? b.baslik).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(Color.murekkep)
                    Text("\(merkez.d.kanitlar(b.id).count)").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(Color.bolum(b.no))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(isik ? Color.bolum(b.no).opacity(0.18) : .clear))
                .scaleEffect(isik ? 1.08 : 1)
                .animation(.spring(duration: 0.25), value: isik)
                .dropDestination(for: String.self) { idler, _ in
                    guard let id = idler.first else { return false }
                    withAnimation(.snappy) { merkez.ata(id, b.id) }
                    return true
                } isTargeted: { ustunde in
                    if ustunde { hedef = b.id; Haptik.secim() } else if hedef == b.id { hedef = nil }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 10).padding(.bottom, 4)
    }
}

struct ElleIsaret: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    @State private var metin = ""
    @State private var kitap = ""
    @FocusState private var odak: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Cümle") {
                    TextField("Kitaptaki cümle ya da kendi notun", text: $metin, axis: .vertical).lineLimit(4...10).focused($odak)
                }
                Section("Kaynak") {
                    TextField(merkez.d.aktifOturum?.kitapAdi ?? "Kitap adı (boş: kendi notum)", text: $kitap)
                }
            }
            .navigationTitle("Elle işaret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { kapat() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        let ad = kitap.trimmingCharacters(in: .whitespaces)
                        merkez.isaretEkle(metin, kaynak: .elle, kitap: ad.isEmpty ? nil : "elle-" + ad.tr, kitapAdi: ad.isEmpty ? nil : ad)
                        kapat()
                    }
                    .disabled(metin.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { odak = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Teoria'nın akışındaki bütün Voice Dream işaretleri; ilgisi düşük olduğu için Kutu'ya kendiliğinden düşmeyenler de burada.
struct KutuphaneEkrani: View {
    @EnvironmentObject var merkez: Merkez
    @Environment(\.dismiss) private var kapat
    @State private var arama = ""

    private var liste: [Isaret] {
        let var_olan = Set(merkez.d.isaretler.map(\.id))
        return merkez.kutuphane.filter { !var_olan.contains($0.id) && (arama.isEmpty || $0.metin.tr.contains(arama.tr) || $0.kitapAdi.tr.contains(arama.tr)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if merkez.kutuphane.isEmpty {
                    Text("Teoria'nın akış dosyası okunamadı. Vault bağlı mı? ↻ ile eşitle.").foregroundStyle(Color.soluk)
                }
                ForEach(liste.prefix(150)) { x in
                    Button { merkez.kutuphanedenEkle(x) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(x.kitapAdi).font(.caption.weight(.semibold)).foregroundStyle(Color.soluk)
                            Text(x.metin).font(.serif(15)).foregroundStyle(Color.murekkep).lineLimit(4)
                        }
                    }
                }
            }
            .searchable(text: $arama, prompt: "Kelime ya da kitap")
            .navigationTitle("Voice Dream işaretleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { kapat() } } }
        }
    }
}
