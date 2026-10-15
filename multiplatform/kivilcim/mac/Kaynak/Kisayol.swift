// Genel kısayol (Carbon, erişilebilirlik izni gerektirmez).
// Kısa bas = kaydı aç / kapat. Basılı tut (≥0,6 sn) = bas-konuş: bırakınca kayıt biter.
// Kayıt sürerken Esc = vazgeç (yalnız kayıt süresince yakalanır).
import Carbon
import AppKit

struct KisayolSecenegi: Identifiable, Hashable {
    let id: String; let ad: String; let kod: UInt32; let mod: UInt32
    static let hepsi: [KisayolSecenegi] = [
        .init(id: "ctrlOptK", ad: "⌃⌥K", kod: UInt32(kVK_ANSI_K), mod: UInt32(controlKey | optionKey)),
        .init(id: "optCmdK", ad: "⌥⌘K", kod: UInt32(kVK_ANSI_K), mod: UInt32(optionKey | cmdKey)),
        .init(id: "ctrlOptSpace", ad: "⌃⌥⌘Boşluk", kod: UInt32(kVK_Space), mod: UInt32(controlKey | optionKey | cmdKey)),
        .init(id: "f5", ad: "F5", kod: UInt32(kVK_F5), mod: 0),
    ]
    static var secili: KisayolSecenegi {
        hepsi.first { $0.id == UserDefaults.standard.string(forKey: "kisayol") } ?? hepsi[0]
    }
}

@MainActor
final class Kisayol {
    static let shared = Kisayol()
    private var ana: EventHotKeyRef?
    private var esc: EventHotKeyRef?
    private var isleyici: EventHandlerRef?
    private var basma = Date()
    private var basildigindaKayittaydi = false

    func kur() {
        if isleyici == nil {
            var turler = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            InstallEventHandler(GetApplicationEventTarget(), { _, olay, _ -> OSStatus in
                var k = EventHotKeyID()
                GetEventParameter(olay, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &k)
                let basildi = GetEventKind(olay) == UInt32(kEventHotKeyPressed)
                let no = k.id
                Task { @MainActor in Kisayol.shared.olay(no: no, basildi: basildi) }
                return noErr
            }, 2, &turler, nil, &isleyici)
        }
        if let a = ana { UnregisterEventHotKey(a); ana = nil }
        let s = KisayolSecenegi.secili
        RegisterEventHotKey(s.kod, s.mod, EventHotKeyID(signature: OSType(0x4B56_4C43), id: 1), GetApplicationEventTarget(), 0, &ana)
    }

    func escAc(_ ac: Bool) {
        if ac, esc == nil {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: OSType(0x4B56_4C43), id: 2), GetApplicationEventTarget(), 0, &esc)
        } else if !ac, let e = esc {
            UnregisterEventHotKey(e); esc = nil
        }
    }

    private func olay(no: UInt32, basildi: Bool) {
        let k = Kaydedici.shared
        if no == 2 { if basildi { k.vazgec() }; return }
        if basildi {
            basma = Date()
            basildigindaKayittaydi = k.kayitta
            if !k.kayitta { k.baslat() }
        } else {
            let tutuldu = Date().timeIntervalSince(basma) >= 0.6
            if basildigindaKayittaydi { k.bitir() }          // ikinci basış: bitir
            else if tutuldu && k.kayitta { k.bitir() }       // bas-konuş: bırakınca bitir
        }
    }
}
