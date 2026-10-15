// Bildirimler: gün içine dağılmış birkaç sessiz hatırlatma. Kilit ekranından, uygulamayı açmadan:
//   HATIRLA  → Hatırladım · Bilemedim (cevap ayrı bir bildirimle gelir) · Göster · Kendi cümlenle yaz
//   İŞARET   → Favori · Tekrar havuzuna · Yer işareti · Sesli yorum (uygulamayı açar)
// 2026-10-06 onarım: izin yalnız Ayarlar'da anahtar değişince isteniyordu → ilk kurulumda izin hiç sorulmuyor,
// planla() "izin yok" deyip sessizce çıkıyordu; üstelik düzey `passive` idi (ekranı yakmaz, ses/titreşim yok).
// Artık: izin ilk açılışta istenir, düzey `active`, ses Ayarlar'dan (varsayılan açık), Ayarlar'da durum + deneme bildirimi.
// Kural: suçluluk yok. Kaçırılan bildirim birikmez; akşam hatırlatması yalnız o gün kür yapılmadıysa
// ve yalnız uygulama o gün açıldıysa gelir (günlerce açmayana ısrar edilmez).
import Foundation
import UserNotifications

enum Bildirim {
    static let onek = "teoria."
    static let hatirlaTuru = "TEORIA_HATIRLA"
    static let isaretTuru = "TEORIA_ISARET"
    static let cevapTuru = "TEORIA_CEVAP"

    static var acik: Bool {
        get { UserDefaults.standard.object(forKey: "teoria.bildirim") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim") }
    }
    static var gunluk: Int {
        get { (UserDefaults.standard.object(forKey: "teoria.bildirim.sayi") as? Int) ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim.sayi") }
    }
    static var basSaat: Int {
        get { (UserDefaults.standard.object(forKey: "teoria.bildirim.bas") as? Int) ?? 9 }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim.bas") }
    }
    static var sonSaat: Int {
        get { (UserDefaults.standard.object(forKey: "teoria.bildirim.son") as? Int) ?? 21 }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim.son") }
    }
    /// Bildirim sesle mi gelsin? Kapalıysa yine banner olarak gelir, yalnız sessiz.
    static var sesli: Bool {
        get { UserDefaults.standard.object(forKey: "teoria.bildirim.ses") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim.ses") }
    }
    static var aksam: Bool {
        get { UserDefaults.standard.object(forKey: "teoria.bildirim.aksam") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "teoria.bildirim.aksam") }
    }

    static func kategorileriKaydet() {
        let hatirladim = UNNotificationAction(identifier: "hatirladim", title: "Hatırladım", options: [], icon: .init(systemImageName: "checkmark"))
        let bilemedim = UNNotificationAction(identifier: "bilemedim", title: "Bilemedim — cevabı göster", options: [], icon: .init(systemImageName: "eye"))
        let yaz = UNTextInputNotificationAction(identifier: "yaz", title: "Kendi cümlenle yaz", options: [],
                                                icon: .init(systemImageName: "pencil"), textInputButtonTitle: "Kaydet",
                                                textInputPlaceholder: "Bu kavram ne demek?")
        let favori = UNNotificationAction(identifier: "favori", title: "Favori", options: [], icon: .init(systemImageName: "heart"))
        let tekrar = UNNotificationAction(identifier: "hatirlat", title: "Tekrar havuzuna al", options: [], icon: .init(systemImageName: "bell"))
        let yer = UNNotificationAction(identifier: "yer", title: "Yer işareti", options: [], icon: .init(systemImageName: "bookmark"))
        let ses = UNNotificationAction(identifier: "ses", title: "Sesli yorum", options: [.foreground], icon: .init(systemImageName: "mic"))
        let isaretYaz = UNTextInputNotificationAction(identifier: "yaz", title: "Yorum yaz", options: [],
                                                      icon: .init(systemImageName: "pencil"), textInputButtonTitle: "Kaydet",
                                                      textInputPlaceholder: "Ne düşünüyorsun?")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: hatirlaTuru, actions: [hatirladim, bilemedim, yaz], intentIdentifiers: []),
            UNNotificationCategory(identifier: isaretTuru, actions: [favori, tekrar, yer, isaretYaz, ses], intentIdentifiers: []),
            UNNotificationCategory(identifier: cevapTuru, actions: [yaz], intentIdentifiers: []),
        ])
    }

    static func izinIste() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    enum Izin { case reddedildi, sorulmadi, verildi }

    static func izin() async -> Izin {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .verildi
        case .notDetermined: .sorulmadi
        default: .reddedildi
        }
    }

    /// İçeriğe düzey ve sesi uygular: ekranda belirir (active), ses ayara göre.
    static func duzey(_ c: UNMutableNotificationContent) {
        c.interruptionLevel = .active
        c.sound = sesli ? .default : nil
    }

    /// Ayarlar'daki "Deneme bildirimi": 5 sn sonra bir "Önce hatırla" kartı. Uygulamayı kapatıp beklemek için süre var.
    @MainActor
    static func dene(_ depo: Depo) async -> Bool {
        if await izin() == .sorulmadi { _ = await izinIste() }
        guard await izin() == .verildi else { return false }
        let c = UNMutableNotificationContent()
        if let k = depo.anlik().hatirla.first {
            c.title = "Önce hatırla"; c.subtitle = k.kaynak; c.body = k.soru
            c.categoryIdentifier = hatirlaTuru
            c.userInfo = ["kart": k.id, "cevap": k.cevap, "kaynak": k.kaynak]
        } else {
            c.title = "Teoria"; c.body = "Bildirimler çalışıyor."
        }
        c.threadIdentifier = "teoria"
        duzey(c)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(onek)deneme", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
        return true
    }

    /// Önümüzdeki üç günü yeniden planlar (açılışta ve her kürden sonra). Bekleyen bildirim sınırı (64) aşılmaz.
    @MainActor
    static func planla(_ depo: Depo) async {
        let m = UNUserNotificationCenter.current()
        let bekleyen = await m.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(onek) }
        m.removePendingNotificationRequests(withIdentifiers: bekleyen)
        guard acik else { return }
        // İlk açılışta izin hiç sorulmamışsa şimdi sor (eskiden yalnız Ayarlar'da sorulduğu için bildirim hiç gelmiyordu).
        if await izin() == .sorulmadi { _ = await izinIste() }
        guard await izin() == .verildi else { return }

        let anlik = depo.anlik()
        let hatirla = anlik.hatirla
        let isaretler = depo.akis.isaretler.filter { $0.metin.count < 260 }
        let favoriIsaret = isaretler.filter { depo.durum.favoriler.contains($0.id) || depo.durum.hatirlatmalar.contains($0.id) }
        // Recall havuzu: tekrar havuzundaki ya da bir kez çağrılmış işaretler. Bildirim metni göstermez, yalnız ipucu verir.
        let recallHavuzu = depo.akis.isaretler.filter { depo.durum.hatirlatmalar.contains($0.id) || depo.durum.kartlar["hatirla:isaret:\($0.id)"] != nil }
        let t = Tarih.takvim
        let simdi = Date()
        var sayac = 0
        let n = min(max(gunluk, 1), 8)
        let bas = min(basSaat, sonSaat - 1), son = max(sonSaat, basSaat + 1)
        for g in 0..<3 {
            let gun = simdi.gunBasi.gun(g)
            let gunNo = t.ordinality(of: .day, in: .era, for: gun) ?? g
            for i in 0..<n {
                // Eşit aralık + her gün birkaç dakika kayan sapma (aynı saate alışıp körleşmemek için)
                let dilim = Double(son - bas) * 3600 / Double(n)
                let sapma = (Gokyuzu.hash(gunNo * 17 + i) - 0.5) * min(dilim * 0.5, 2400)
                let an = gun.addingTimeInterval(Double(bas) * 3600 + dilim * (Double(i) + 0.5) + sapma)
                guard an > simdi.addingTimeInterval(120) else { continue }
                let c = UNMutableNotificationContent()
                c.threadIdentifier = "teoria"
                duzey(c)
                c.relevanceScore = 0.4
                if i % 3 == 2, !recallHavuzu.isEmpty {
                    let x = recallHavuzu[(gunNo * n + i) % recallHavuzu.count]
                    c.title = "Kapat, hatırla, yeniden kur"
                    c.subtitle = x.baslik
                    c.body = "“" + x.metin.split(separator: " ").prefix(4).joined(separator: " ") + "…” — devamı ne diyordu? Dokun, zihninden yaz."
                    c.userInfo = ["ac": "recall:\(x.id)"]
                } else if i % 2 == 0, !hatirla.isEmpty {
                    let k = hatirla[(gunNo * n + i) % hatirla.count]
                    c.title = "Önce hatırla"
                    c.subtitle = k.kaynak
                    c.body = k.soru
                    c.categoryIdentifier = hatirlaTuru
                    c.userInfo = ["kart": k.id, "cevap": k.cevap, "kaynak": k.kaynak]
                } else if let x = (favoriIsaret.isEmpty || i % 3 != 1 ? isaretler : favoriIsaret).randomElement() {
                    c.title = x.baslik
                    c.subtitle = "\(Tarih.goreli(x.zaman)) işaretledin"
                    c.body = x.metin
                    c.categoryIdentifier = isaretTuru
                    c.userInfo = ["isaret": x.id]
                } else { continue }
                let tetik = UNCalendarNotificationTrigger(dateMatching: t.dateComponents([.year, .month, .day, .hour, .minute], from: an), repeats: false)
                try? await m.add(UNNotificationRequest(identifier: "\(onek)\(Tarih.gun(gun)).\(i)", content: c, trigger: tetik))
                sayac += 1
            }
        }
        // Akşam: yalnız bugün, yalnız kür yapılmadıysa. Dil davet eder, hesap sormaz.
        if aksam, depo.durum.bugunKur == 0, let an = t.date(bySettingHour: min(son, 23) - 1, minute: 30, second: 0, of: simdi), an > simdi {
            let c = UNMutableNotificationContent()
            c.title = "\(depo.kurDakika) dakikalık kür hazır"
            c.body = "Bir ısınma, birkaç kart, başarıyla biten bir son. İstersen."
            duzey(c)
            c.userInfo = ["ac": "kur"]
            let tetik = UNCalendarNotificationTrigger(dateMatching: t.dateComponents([.year, .month, .day, .hour, .minute], from: an), repeats: false)
            try? await m.add(UNNotificationRequest(identifier: "\(onek)aksam", content: c, trigger: tetik))
        }
        UserDefaults.standard.set(sayac, forKey: "teoria.bildirim.planli")
    }

    /// Bir bildirim eylemi → olay. Uygulama kapalıyken de çalışır (arka plan eylemi); olay kutuya düşer.
    static func eylem(_ r: UNNotificationResponse) -> String? {
        let bilgi = r.notification.request.content.userInfo
        let kart = bilgi["kart"] as? String
        let isaret = bilgi["isaret"] as? String
        switch r.actionIdentifier {
        case "hatirladim":
            if let k = kart { Paylasim.kutuyaAt(Olay(tur: .cevap, hedef: k, hat: .hatirla, puan: 1, not: Not.iyi.rawValue, rol: "bildirim")) }
        case "bilemedim":
            if let k = kart {
                Paylasim.kutuyaAt(Olay(tur: .cevap, hedef: k, hat: .hatirla, puan: 0, not: Not.unuttum.rawValue, rol: "bildirim"))
                cevabiGoster(bilgi)
            }
        case "yaz":
            if let t = (r as? UNTextInputNotificationResponse)?.userText, !t.isEmpty {
                Paylasim.kutuyaAt(Olay(tur: .kendiCumle, hedef: kart ?? isaret, metin: t))
                if let k = kart, let cevap = bilgi["cevap"] as? String {
                    // Yazdığı, cevabın anahtar kelimesini taşıyorsa hatırlanmış sayılır.
                    let tuttu = Dil.kapsam(t, [cevap]).oran >= 1
                    Paylasim.kutuyaAt(Olay(tur: .cevap, hedef: k, hat: .hatirla, puan: tuttu ? 0.85 : 0.5,
                                           not: (tuttu ? Not.iyi : Not.zor).rawValue, metin: t, rol: "bildirim"))
                    if !tuttu { cevabiGoster(bilgi) }
                }
            }
        case "favori":
            if let i = isaret { Paylasim.kutuyaAt(Olay(tur: .favori, hedef: i, deger: true)) }
        case "hatirlat":
            if let i = isaret { Paylasim.kutuyaAt(Olay(tur: .hatirlat, hedef: i, deger: true)) }
        case "yer":
            if let i = isaret { Paylasim.kutuyaAt(Olay(tur: .yerIsareti, hedef: i, deger: true)) }
        case "ses":
            return "ses:\(isaret ?? "")"
        case UNNotificationDefaultActionIdentifier:
            if let a = bilgi["ac"] as? String { return a }
            if kart != nil { return "kur" }
            if let i = isaret { return "isaret:\(i)" }
        default: break
        }
        return nil
    }

    private static func cevabiGoster(_ bilgi: [AnyHashable: Any]) {
        guard let cevap = bilgi["cevap"] as? String else { return }
        let c = UNMutableNotificationContent()
        c.title = cevap
        c.subtitle = bilgi["kaynak"] as? String ?? ""
        c.body = "Şimdi gördün; bir dahakine kendin çağıracaksın."
        c.categoryIdentifier = cevapTuru
        c.userInfo = bilgi
        duzey(c)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(onek)cevap.\(UUID().uuidString)", content: c,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
