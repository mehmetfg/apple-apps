// Bildirim orkestrası — kullanıcı kararı: "her olayda".
// Olay = bir sürecin durum değiştirmesi (gecikti · aksıyor · tıkalı · toparlandı), bir sabah görevinin tıkanması,
// vadenin 7/3/1/0 gün kalması, Mac verisinin eskimesi. Aynı olay bir kez bildirilir.
//
// Uygulama arka planda sürekli çalışamaz; bu yüzden zamana bağlı olaylar ÖNCEDEN kurulur: "hiçbir şey değişmezse
// Teoria cumartesi 09:00'da gecikti'ye düşer" bildirimi bugünden takvime konur, süreçe dokunulup yeniden
// hesaplanınca geri alınır. Gece 22:30–07:30 arası doğan olay sabaha kayar.
import Foundation
import UserNotifications

enum Bildirimci {
    static let kategori = "orkestra.surec"
    static let sessizBas = (22, 30)
    static let sessizBit = (7, 30)

    static func kur() {
        let ac = UNNotificationAction(identifier: "ac", title: "Aç", options: [.foreground])
        let ertele = UNNotificationAction(identifier: "ertele", title: "Yarına bırak", options: [])
        let k = UNNotificationCategory(identifier: kategori, actions: [ac, ertele], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([k])
    }

    static func izinIste() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func izinVar() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    // MARK: ana giriş
    static func isle(_ d: Durumlar) async {
        guard await izinVar() else { return }
        let merkez = UNUserNotificationCenter.current()
        var bildirilen = Depo.bildirilen
        let ilkKez = bildirilen.isEmpty
        let ertelenen = Depo.ertelenenler(d.simdi)
        let tahmin = Depo.ayar.dictionary(forKey: "tahminler") as? [String: String] ?? [:]
        var yeni: [(String, String, String, [String: String])] = []   // kimlik, başlık, gövde, userInfo

        for h in d.hukumler {
            let once = bildirilen[h.id].flatMap(Durum.init(rawValue:))
            bildirilen[h.id] = h.durum.rawValue
            guard !ilkKez, let once, once != h.durum, h.durum.hukumVar, !ertelenen.contains(h.id) else { continue }
            // önceden kurulmuş bildirim bu geçişi zaten haber verdiyse tekrar etme
            if let t = tahmin[h.id], t.hasPrefix(h.durum.rawValue + "|"),
               let ts = Double(t.split(separator: "|").last ?? ""), ts <= d.simdi.timeIntervalSince1970 { continue }
            let bilgi = ["surec": h.id, "acilis": h.surec.acilis ?? ""]
            if h.durum.sorunlu {
                yeni.append(("olay.\(h.id).\(h.durum.rawValue)", "\(h.surec.ad) · \(h.durum.ad)", h.neden, bilgi))
            } else if h.durum == .akiyor && (once == .aksiyor || once == .tikali) {
                yeni.append(("olay.\(h.id).toparlandi", "\(h.surec.ad) toparlandı", "Yeniden ritminde. \(h.surec.bugun)", bilgi))
            }
        }
        for b in d.veri.borular {
            let k = "boru.\(b.id)"
            let once = bildirilen[k]
            bildirilen[k] = b.durum
            if !ilkKez, b.durum == "tikali", once != "tikali" {
                yeni.append(("olay.\(k)", "Boru tıkandı · \(b.ad)", b.not, ["surec": b.besler.first ?? "", "acilis": ""]))
            }
        }
        for h in d.aktif {
            // bant: ≤7 · ≤3 · ≤1 · 0 — her bant bir kez (uygulama o gün açılmasa da sonraki açılışta yakalanır)
            guard let g = h.vadeGun, g >= 0, g <= 7 else { continue }
            let bant = g == 0 ? 0 : g <= 1 ? 1 : g <= 3 ? 3 : 7
            let k = "vade.\(h.id).\(h.surec.vade?.tarih ?? "").\(bant)"
            if bildirilen[k] == nil {
                bildirilen[k] = "1"
                let ne = g == 0 ? "bugün" : "\(g) gün kaldı"
                yeni.append(("olay.\(k)", "\(h.surec.ad) · vade \(ne)", h.surec.vade?.olcut ?? "",
                             ["surec": h.id, "acilis": h.surec.acilis ?? ""]))
            }
        }
        if d.veriEski {
            let k = "veri.eski.\(Tarih.iso(d.simdi).prefix(10))"
            if bildirilen[k] == nil {
                bildirilen[k] = "1"
                let saat = Int(d.veriYasi / 3600)
                yeni.append(("olay.\(k)", "Mac verisi eski", "orkestra.json \(saat) saattir tazelenmedi. Tezgâh.app'i aç ya da Mac'te orkestra.py'yi koştur.",
                             ["surec": "", "acilis": ""]))
            }
        }
        if ilkKez {
            let t = d.say(.tikali), a = d.say(.aksiyor), g = d.say(.gecikti)
            yeni.append(("olay.ilk", "Orkestra dinliyor",
                         "\(d.aktif.count) süreç izleniyor · \(t) tıkalı · \(a) aksıyor · \(g) gecikti. Nabız \(d.nabiz).",
                         ["surec": "", "acilis": ""]))
        }
        // eski vade kayıtlarını temizle (kayıt şişmesin)
        bildirilen = bildirilen.filter { kv in
            !kv.key.hasPrefix("vade.") || d.aktif.contains { h in kv.key.hasPrefix("vade.\(h.id).\(h.surec.vade?.tarih ?? "")") }
        }
        Depo.bildirilen = bildirilen

        for (kimlik, baslik, govde, bilgi) in yeni {
            let an = sessizSaatSonrasi(d.simdi)
            await gonder(merkez, kimlik: kimlik, baslik: baslik, govde: govde, bilgi: bilgi, an: an)
        }
        await onceden(merkez, d, ertelenen)
    }

    // MARK: önceden kurulan bildirimler
    static func onceden(_ merkez: UNUserNotificationCenter, _ d: Durumlar, _ ertelenen: Set<String>) async {
        let bekleyen = await merkez.pendingNotificationRequests().map(\.identifier)
        merkez.removePendingNotificationRequests(withIdentifiers: bekleyen.filter {
            $0.hasPrefix("tahmin.") || $0 == "sabah" || $0 == "aksam"
        })
        var tahmin: [String: String] = [:]
        for h in d.aktif where h.durum != .tikali && !ertelenen.contains(h.id) {
            for (an, durum) in Motor.gelecek(h.surec, d.simdi).prefix(2) {
                let g = Tarih.gunFarki(h.surec.sonDokunus ?? an, an)
                await gonder(merkez, kimlik: "tahmin.\(h.id).\(durum.rawValue)",
                             baslik: "\(h.surec.ad) · \(durum.ad)",
                             govde: "\(g) gündür sessiz." + (h.surec.bicim == "akis" ? "" : " Sırada: \(h.surec.bugun)"),
                             bilgi: ["surec": h.id, "acilis": h.surec.acilis ?? ""], an: an)
                if tahmin[h.id] == nil { tahmin[h.id] = "\(durum.rawValue)|\(an.timeIntervalSince1970)" }
            }
        }
        Depo.ayar.set(tahmin, forKey: "tahminler")

        // sabah özeti — her tazelemede bugünün hamleleriyle yeniden yazılır
        let t = Tarih.takvim
        var sabah = t.date(bySettingHour: sessizBit.0, minute: sessizBit.1, second: 0, of: d.simdi) ?? d.simdi
        if sabah <= d.simdi { sabah = t.date(byAdding: .day, value: 1, to: sabah) ?? sabah }
        let ertesi = Motor.hesapla(d.veri, simdi: sabah, ertelenen: Depo.ertelenenler(sabah))
        let satirlar = ertesi.ilk3.enumerated().map { "\($0.offset + 1). \($0.element.fiil): \($0.element.baslik)" }
        await gonder(merkez, kimlik: "sabah", baslik: "Orkestra · bugünün sırası (nabız \(ertesi.nabiz))",
                     govde: satirlar.isEmpty ? "Bütün süreçler ritminde." : satirlar.joined(separator: "\n"),
                     bilgi: ["surec": ertesi.ilk3.first?.surecId ?? "", "acilis": ""], an: sabah)

        // akşam kapanışı — ana odaktaki süreçlere bugün hiç dokunulmadıysa
        let anaSessiz = d.aktif.filter { $0.surec.kademe == "ana" && !$0.bugunDokunuldu && $0.surec.ritim == 1 }
        if !anaSessiz.isEmpty, let aksam = t.date(bySettingHour: 21, minute: 0, second: 0, of: d.simdi), aksam > d.simdi {
            await gonder(merkez, kimlik: "aksam", baslik: "Ana odak bugün sessiz",
                         govde: anaSessiz.map(\.surec.ad).joined(separator: " · ") + " — günü kapatmadan beş dakika.",
                         bilgi: ["surec": anaSessiz[0].id, "acilis": anaSessiz[0].surec.acilis ?? ""], an: aksam)
        }
    }

    static func sessizSaatSonrasi(_ simdi: Date) -> Date? {
        let t = Tarih.takvim
        let s = t.component(.hour, from: simdi) * 60 + t.component(.minute, from: simdi)
        let bas = sessizBas.0 * 60 + sessizBas.1, bit = sessizBit.0 * 60 + sessizBit.1
        guard s >= bas || s < bit else { return nil }   // gündüz: hemen
        var an = t.date(bySettingHour: sessizBit.0, minute: sessizBit.1 + 1, second: 0, of: simdi) ?? simdi
        if s >= bas { an = t.date(byAdding: .day, value: 1, to: an) ?? an }
        return an
    }

    static func gonder(_ merkez: UNUserNotificationCenter, kimlik: String, baslik: String, govde: String,
                       bilgi: [String: String], an: Date?) async {
        let c = UNMutableNotificationContent()
        c.title = baslik
        c.body = govde
        c.sound = .default
        c.categoryIdentifier = kategori
        c.userInfo = bilgi
        c.threadIdentifier = bilgi["surec"] ?? "orkestra"
        let tetik: UNNotificationTrigger?
        if let an, an > .now.addingTimeInterval(5) {
            tetik = UNCalendarNotificationTrigger(dateMatching: Tarih.takvim.dateComponents(
                [.year, .month, .day, .hour, .minute], from: an), repeats: false)
        } else {
            tetik = nil
        }
        try? await merkez.add(UNNotificationRequest(identifier: kimlik, content: c, trigger: tetik))
    }

    static func deneme() async {
        let c = UNMutableNotificationContent()
        c.title = "Orkestra · deneme"
        c.body = "Bildirimler açık. Olaylar böyle gelecek; \"Aç\" ilgili uygulamayı açar."
        c.sound = .default
        c.categoryIdentifier = kategori
        c.userInfo = ["surec": "teoria", "acilis": "teoria://"]
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "deneme", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
    }
}
