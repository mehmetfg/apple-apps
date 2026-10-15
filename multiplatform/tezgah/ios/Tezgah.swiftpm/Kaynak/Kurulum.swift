// İlk açılış: vault klasörünü bir kez seçtirir. Sonra hep oradan okunur.
import SwiftUI
import UniformTypeIdentifiers

struct Kurulum: View {
    @EnvironmentObject var depo: VeriDeposu
    @State private var sec = false
    @State private var goster = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            TezgahIsareti(boy: 150)
                .padding(.bottom, 28)
            Text("Tezgâh")
                .font(.system(size: 40, weight: .bold))
                .opacity(goster ? 1 : 0).offset(y: goster ? 0 : 12)
            Text("Cümle, İdrak, İngilizce ve vault —\ncebinde, tek bakışta.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(T.yumusak)
                .padding(.top, 8)
                .opacity(goster ? 1 : 0).offset(y: goster ? 0 : 12)
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                adim(1, "Aşağıdaki düğmeye dokun.")
                adim(2, "iCloud Drive › Obsidian › Personel Data Management klasörüne gir.")
                adim(3, "Sağ üstteki \"Aç\"a dokun. Bir kez yeterli.")
            }
            .padding(20)
            .background(T.yuzey, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(goster ? 1 : 0).offset(y: goster ? 0 : 20)
            Button {
                sec = true
            } label: {
                Label("Vault klasörünü seç", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(T.cumle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.top, 16)
            .sensoryFeedback(.impact(weight: .medium), trigger: sec)
            Text("Uygulama yalnız okur; vault'a hiçbir şey yazmaz.")
                .font(.footnote).foregroundStyle(T.soluk).padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(
            ZStack {
                T.zemin
                Circle().fill(T.cumle.opacity(0.18)).frame(width: 340).blur(radius: 80).offset(x: 120, y: -260)
                Circle().fill(T.muhendis.opacity(0.16)).frame(width: 300).blur(radius: 80).offset(x: -140, y: 60)
            }
            .ignoresSafeArea()
        )
        .fileImporter(isPresented: $sec, allowedContentTypes: [.folder]) { sonuc in
            if case .success(let url) = sonuc { depo.klasorSecildi(url) }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.35)) { goster = true } }
    }

    func adim(_ n: Int, _ metin: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.footnote.bold()).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(T.cumle, in: Circle())
            Text(metin).font(.callout)
        }
    }
}
