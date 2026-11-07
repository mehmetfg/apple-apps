import SwiftUI

struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var tmdbKey = APIKeyStore.value(for: .tmdb) ?? ""
    @State private var omdbKey = APIKeyStore.value(for: .omdb) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("TMDB API anahtarı", text: $tmdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Ücretsiz anahtar al", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                } header: {
                    Text("Katalog")
                } footer: {
                    Text("TV+ listesi, konular, türler ve yorumlar buradan gelir.")
                }

                Section {
                    SecureField("OMDb API anahtarı", text: $omdbKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Ücretsiz anahtar al", destination: URL(string: "https://www.omdbapi.com/apikey.aspx")!)
                } header: {
                    Text("IMDb puanları")
                } footer: {
                    Text("Ücretsiz anahtar günde 1.000 istek verir. Puanlar telefonda saklandığı için aynı yapım bir hafta yeniden sorulmaz.")
                }

                Section("Kaynaklar") {
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    Text("Platform bilgisi JustWatch'tan alınır. IMDb puanları OMDb üzerinden gelir.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        services.save(tmdbKey: tmdbKey, omdbKey: omdbKey)
                        dismiss()
                    }
                }
            }
        }
    }
}
