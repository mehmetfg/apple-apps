import AVFoundation
import AudioToolbox

/// `Zincir`i AVAudioEngine'e takan, uygulama içinde kayıtlı tek efekt birimi (Audio Unit v3, süreç içi).
final class EfektBirimi: AUAudioUnit {
    static let tanim = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x74_69_6E_69,        // "tini"
        componentManufacturer: 0x46_61_74_67,   // "Fatg"
        componentFlags: 0, componentFlagsMask: 0)

    private static var kayitli = false
    static func kaydet() {
        guard !kayitli else { return }
        kayitli = true
        AUAudioUnit.registerSubclass(EfektBirimi.self, as: tanim, name: "Fatg: Tını", version: 1)
    }

    let zincir = Zincir()
    private var giris: AUAudioUnitBus!
    private var cikis: AUAudioUnitBus!
    private var girisler: AUAudioUnitBusArray!
    private var cikislar: AUAudioUnitBusArray!
    /// Girişin çekildiği kendi tamponumuz: kanal başına `maximumFramesToRender` Float.
    private var tamponListe: UnsafeMutableAudioBufferListPointer?
    private var tamponBellek: [UnsafeMutablePointer<Float>] = []
    private var kapasite: AUAudioFrameCount = 0

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let bicim = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try super.init(componentDescription: componentDescription, options: options)
        giris = try AUAudioUnitBus(format: bicim)
        giris.maximumChannelCount = 2
        cikis = try AUAudioUnitBus(format: bicim)
        cikis.maximumChannelCount = 2
        girisler = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [giris])
        cikislar = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [cikis])
        maximumFramesToRender = 4096
    }

    override var inputBusses: AUAudioUnitBusArray { girisler }
    override var outputBusses: AUAudioUnitBusArray { cikislar }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let bicim = cikis.format
        tamponuBirak()
        let kanal = Int(max(1, giris.format.channelCount))
        let liste = AudioBufferList.allocate(maximumBuffers: kanal)
        for i in 0..<kanal {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: Int(maximumFramesToRender))
            p.initialize(repeating: 0, count: Int(maximumFramesToRender))
            tamponBellek.append(p)
            liste[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: maximumFramesToRender * 4, mData: p)
        }
        tamponListe = liste
        kapasite = maximumFramesToRender
        zincir.hazirla(ornekleme: bicim.sampleRate)
    }

    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        zincir.serbestBirak()
        tamponuBirak()
    }

    private func tamponuBirak() {
        tamponBellek.forEach { $0.deallocate() }
        tamponBellek.removeAll()
        tamponListe?.unsafeMutablePointer.deallocate()
        tamponListe = nil
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // Blok self'i değil yalnız gereken nesneleri yakalar (ses iş parçacığında ObjC mesajı yok).
        let zincir = self.zincir
        let birim = self
        return { _, zaman, kareSayisi, _, cikisVerisi, _, cek in
            guard let cek, let tamponListe = birim.tamponListe else { return kAudioUnitErr_NoConnection }
            if kareSayisi > birim.kapasite { return kAudioUnitErr_TooManyFramesToProcess }
            // Girişi kendi tamponumuza çek (her seferinde işaretçi ve boy yeniden yazılır; üst birim değiştirmiş olabilir).
            for i in 0..<tamponListe.count {
                tamponListe[i].mData = UnsafeMutableRawPointer(birim.tamponBellek[i])
                tamponListe[i].mDataByteSize = kareSayisi * UInt32(MemoryLayout<Float>.size)
            }
            var bayrak = AudioUnitRenderActionFlags()
            let durum = cek(&bayrak, zaman, kareSayisi, 0, tamponListe.unsafeMutablePointer)
            if durum != noErr { return durum }

            let cikisListe = UnsafeMutableAudioBufferListPointer(cikisVerisi)
            for i in 0..<cikisListe.count {
                let kaynak = tamponListe[min(i, tamponListe.count - 1)]
                if cikisListe[i].mData == nil {
                    cikisListe[i].mData = kaynak.mData
                } else if cikisListe[i].mData != kaynak.mData, let k = kaynak.mData {
                    memcpy(cikisListe[i].mData!, k, Int(kareSayisi) * MemoryLayout<Float>.size)
                }
                cikisListe[i].mDataByteSize = kareSayisi * UInt32(MemoryLayout<Float>.size)
            }
            guard let l = cikisListe[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = cikisListe.count > 1 ? cikisListe[1].mData?.assumingMemoryBound(to: Float.self) : nil
            zincir.isle(l, r, Int(kareSayisi))
            return noErr
        }
    }
}
