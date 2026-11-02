// Gün içine yayılmış kelime bildirimleri — pasif karşılaşma kanalı.
// Her bildirim tek kelime: kelime + söyleniş başlıkta, anlam + örnek cümle gövdede.
// Uzun basınca iki düğme: "Biliyordum" (yalnız sayılır) · "Oturumda sor" (bugünkü desteye öne alınır).
// Cümle Tezgâhı'nın günün 6 kelimesi ayrı kategoride: her biri günde `cumleTekrar` kez, ekranı yakarak
// (.active, sessiz) gelir; gövdede İngilizce tanım + Türkçe + Tezgâh cümlesi, düğmede "Cümleyi dinle".
import Foundation
import UserNotifications

enum Bildirim {
    static let kategori = "ASINA_KELIME"
    static let dinleEylemi = "DINLE"
    static let biliyordumEylemi = "BILIYORDUM"
    static let sorEylemi = "OTURUMDA_SOR"
    static let onek = "asina."
    static let cumleKategori = "ASINA_CUMLE"
    static let cumleDinleEylemi = "CUMLE_DINLE"
    /// iOS en çok 64 bekleyen bildirim tutar: 2 gün × (12 Cümle + 12 kelime + 1 hatırlatma) sığar.
    static let ufuk = 2

    static func izinIste() async -> Bool {
        let m = UNUserNotificationCenter.current()
        m.setNotificationCategories([
            UNNotificationCategory(identifier: kategori, actions: [
                // Seçenek yok = uygulamayı öne getirmez; arka planda çalar (Info.plist `audio` kipi).
                UNNotificationAction(identifier: dinleEylemi, title: "Dinle",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "speaker.wave.2.fill")),
                UNNotificationAction(identifier: biliyordumEylemi, title: "Biliyordum",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark")),
                UNNotificationAction(identifier: sorEylemi, title: "Oturumda sor",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.forward")),
            ], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: cumleKategori, actions: [
                UNNotificationAction(identifier: cumleDinleEylemi, title: "Cümleyi dinle",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "text.bubble.fill")),
                UNNotificationAction(identifier: dinleEylemi, title: "Kelimeyi dinle",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "speaker.wave.2.fill")),
                UNNotificationAction(identifier: sorEylemi, title: "Oturumda sor",
                                     options: [], icon: UNNotificationActionIcon(systemImageName: "arrow.uturn.forward")),
            ], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        return (try? await m.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Önümüzdeki üç günün bildirimlerini kurar (iOS en çok 64 bekleyen bildirim tutar).
    static func planla(_ a: Anlik, ayar: Ayarlar, bugunBitti: Bool) {
        let m = UNUserNotificationCenter.current()
        m.getPendingNotificationRequests { bekleyen in
            m.removePendingNotificationRequests(withIdentifiers: bekleyen.map(\.identifier).filter { $0.hasPrefix(onek) })
            guard ayar.bildirimSayisi > 0 || ayar.hatirlatma else { return }
            let simdi = Date()
            for ofset in 0..<ufuk {
                let gun = simdi.gun(ofset)
                let kelimeler = a.kelimeler(gun)
                let n = ayar.bildirimSayisi
                if n > 0, !kelimeler.isEmpty {
                    let bas = Double(ayar.bildirimBas) * 60, son = Double(max(ayar.bildirimSon, ayar.bildirimBas + 1)) * 60
                    for j in 0..<n {
                        let dakika = n == 1 ? bas : bas + (son - bas) * Double(j) / Double(n - 1)
                        // Saatler her gün birkaç dakika kayar; aynı ana alışıp görmezden gelme.
                        let oynama = Double((ofset * 7 + j * 13) % 11) - 5
                        guard let an = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: gun)?
                            .addingTimeInterval((dakika + oynama) * 60), an > simdi.addingTimeInterval(60) else { continue }
                        let k = kelimeler[(j + ofset * 3) % kelimeler.count]
                        m.add(istek(k, an: an, id: "\(onek)\(gun.gunAnahtari).\(j)"))
                    }
                }
                // Cümle Tezgâhı: günün 6 kelimesi, her biri `cumleTekrar` kez, gün boyuna eşit yayılmış.
                let cumle = a.cumle ?? []
                if ayar.cumleTekrar > 0, !cumle.isEmpty {
                    let adet = cumle.count * min(ayar.cumleTekrar, 3)
                    let bas = Double(ayar.bildirimBas) * 60, son = Double(max(ayar.bildirimSon, ayar.bildirimBas + 1)) * 60
                    for j in 0..<adet {
                        // Kelime bildirimlerinin arasına düşsün diye yarım aralık kaydırılır.
                        let adim = (son - bas) / Double(adet)
                        let dakika = bas + adim * (Double(j) + 0.5)
                        let oynama = Double((ofset * 5 + j * 7) % 9) - 4
                        guard let an = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: gun)?
                            .addingTimeInterval((dakika + oynama) * 60), an > simdi.addingTimeInterval(60) else { continue }
                        let k = cumle[j % cumle.count]
                        m.add(cumleIstegi(k, an: an, sira: j / cumle.count, id: "\(onek)\(gun.gunAnahtari).c\(j)"))
                    }
                }
                if ayar.hatirlatma, !(ofset == 0 && bugunBitti),
                   let an = Calendar.current.date(bySettingHour: ayar.hatirlatmaSaati, minute: 0, second: 0, of: gun),
                   an > simdi {
                    let c = UNMutableNotificationContent()
                    c.title = "Bugünün destesi hazır"
                    c.body = ofset == 0 && a.bugunYapilan > 0
                        ? "\(max(0, a.bugunHedef - a.bugunYapilan)) kelime kaldı · 3-4 dakika."
                        : "Birkaç dakika: yeni kelimeler ve unutmak üzere olduklarının."
                    c.sound = .default
                    c.threadIdentifier = "asina.hatirlatma"
                    let t = UNCalendarNotificationTrigger(
                        dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: an), repeats: false)
                    m.add(UNNotificationRequest(identifier: "\(onek)\(gun.gunAnahtari).hatirlatma", content: c, trigger: t))
                }
            }
        }
    }

    private static func cumleIstegi(_ k: WKelime, an: Date, sira: Int, id: String) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = k.ipa.isEmpty ? k.w : "\(k.w)  \(k.ipa)"
        c.subtitle = "\(k.tr) · Cümle Gün \(k.cg ?? 0)"
        var govde = k.d
        if let cu = k.cu { govde += "\n\n“\(cu)”" }
        if let ct = k.ct { govde += "\n\(ct)" }
        c.body = govde
        c.categoryIdentifier = cumleKategori
        c.threadIdentifier = "asina.cumle"
        c.userInfo = ["id": k.i, "w": k.w, "au": k.au ?? "", "cu": k.cu ?? ""]
        c.relevanceScore = 1.0
        // Ekranı yakar ve listenin başına düşer, ama çalmaz — gün boyu 12 kez sesle bölmesin.
        c.interruptionLevel = .active
        c.sound = nil
        let t = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: an), repeats: false)
        return UNNotificationRequest(identifier: id, content: c, trigger: t)
    }

    private static func istek(_ k: WKelime, an: Date, id: String) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = k.ipa.isEmpty ? k.w : "\(k.w)  \(k.ipa)"
        c.subtitle = "\(k.tr)"
        var govde = k.d
        if let x = k.ornek { govde += "\n\n“\(x)”" }
        c.body = govde
        c.categoryIdentifier = kategori
        c.threadIdentifier = "asina.kelime"
        // Uygulama kapalıyken "Dinle" için kelime ve ses adresi bildirimin içinde taşınır.
        c.userInfo = ["id": k.i, "w": k.w, "au": k.au ?? ""]
        c.relevanceScore = k.asama < 0 ? 0.8 : 0.5
        c.interruptionLevel = .passive        // sessiz gelir; ekranda belirir, çalmaz
        let t = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: an), repeats: false)
        return UNNotificationRequest(identifier: id, content: c, trigger: t)
    }
}
