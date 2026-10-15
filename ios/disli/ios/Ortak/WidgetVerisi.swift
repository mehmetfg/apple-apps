// Uygulama → widget köprüsü: günün konusu App Group'ta tek bir JSON olarak durur.
import Foundation

struct WidgetVerisi: Codable {
    var id: String
    var ad: String
    var tr: String
    var formul: String
    var tuzakY: String
    var tuzakD: String
    var imge: String
    var renk: String
    var yasaAd: String
    var yasaSembol: String
    var yasaId: String? = nil     // v2: çizim için (eski kayıtlarda yok)

    static let grup = "group.com.fatihgocgun.disli"
    static let anahtar = "gunun-dislisi"

    static let ornek = WidgetVerisi(id: "pp-past", ad: "Present Perfect vs Past Simple", tr: "Yakın geçmiş ↔ Di'li geçmiş",
                                    formul: "have/has + V3 ↔ V2", tuzakY: "I have seen him yesterday.", tuzakD: "I saw him yesterday.",
                                    imge: "Ada ve köprü: Past Simple geçmişte kopuk bir ada; Present Perfect bugüne uzanan köprü.",
                                    renk: "mavi", yasaAd: "have + V3 = geriye bakmak", yasaSembol: "arrow.uturn.backward.circle.fill", yasaId: "ayna")

    static func oku() -> WidgetVerisi? {
        guard let d = UserDefaults(suiteName: grup)?.data(forKey: anahtar) else { return nil }
        return try? JSONDecoder().decode(WidgetVerisi.self, from: d)
    }

    func yaz() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.grup)?.set(d, forKey: Self.anahtar)
    }
}
