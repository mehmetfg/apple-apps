// Kalkanın görünümü: seçili uygulama açılınca Ekran Süresi bu ekranı gösterir.
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class Kalkan: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { yuz() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { yuz() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { yuz() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { yuz() }

    private func yuz() -> ShieldConfiguration {
        let kalan = max(0, Kapi.tavan - Kapi.bugun)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 0.92),
            icon: UIImage(systemName: "person.wave.2.fill")?.withTintColor(UIColor(red: 0.45, green: 0.78, blue: 0.95, alpha: 1), renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: "Önce tek cümle", color: .white),
            subtitle: ShieldConfiguration.Label(text: Kapi.istem + "\n\nBugün \(kalan) kapı kaldı.", color: UIColor(white: 0.85, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Söyle (Ayna)", color: .black),
            primaryButtonBackgroundColor: UIColor(red: 0.45, green: 0.78, blue: 0.95, alpha: 1),
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Geç", color: UIColor(white: 0.8, alpha: 1)))
    }
}
