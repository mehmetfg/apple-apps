// Göz: kamera + nesne tanıma + etiketi eşyanın üstüne bırakma + odayı hatırlama.
//
//  • ARKit (LiDAR'lı dünya takibi) kamerayı ve 3B uzayı tutar.
//  • Saniyede ~3 kez kare Core ML modeline (Open Images V7, 601 sınıf, telefonun içinde) verilir.
//  • Tanınan sınıf sözlükte bu odanın kelimesine eşlenir; ekranda hemen adı çıkar (canlı etiket).
//  • Aynı eşya iki karede üst üste aynı yerde görülürse eşyanın üstüne kalıcı bir ARKit çapası bırakılır ve kelime okunur.
//  • Oda değişince ya da uygulama arka plana geçince dünya haritası çapalarla birlikte saklanır; odaya dönünce
//    telefon odayı tanır ve etiketler eşyaların üstünde yeniden belirir.
import ARKit
import CoreML
import RealityKit
import SwiftUI
import Vision

struct Gorunen: Identifiable, Equatable {
    let id: String
    let kelime: Kelime
    var nokta: CGPoint
    var mesafe: Float
    var otomatik: Bool
}

struct Canli: Identifiable, Equatable {
    let id: String
    let kelime: Kelime
    var kutu: CGRect
    var guven: Float
}

@MainActor
final class Goz: NSObject, ObservableObject, ARSessionDelegate {
    static let shared = Goz()

    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    let sozluk = Sozluk.paket

    @Published var oda: String = UserDefaults.standard.string(forKey: "oda") ?? "salon"
    @Published private(set) var etiketler: [Etiket] = []
    @Published private(set) var gorunenler: [Gorunen] = []
    @Published private(set) var canlilar: [Canli] = []
    @Published private(set) var ipucu: String?
    @Published var otomatikYerlestir = UserDefaults.standard.object(forKey: "otomatik") as? Bool ?? true {
        didSet { UserDefaults.standard.set(otomatikYerlestir, forKey: "otomatik") }
    }
    @Published private(set) var calisiyor = false
    let destek = ARWorldTrackingConfiguration.isSupported

    private var istek: VNCoreMLRequest?
    private var tanimaMesgul = false
    private var sonTanima = Date.distantPast
    private var sonCizim = Date.distantPast
    private var adaylar: [String: (sayi: Int, nokta: SIMD3<Float>, zaman: Date)] = [:]
    private var kayitGorevi: Task<Void, Never>?
    private let kuyruk = DispatchQueue(label: "saray.tanima", qos: .userInitiated)

    override init() {
        super.init()
        etiketler = Kasa.etiketler(oda)
        arView.session.delegate = self
        arView.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion, .disableGroundingShadows, .disableHDR, .disableFaceMesh]
        modeliYukle()
    }

    private func modeliYukle() {
        kuyruk.async {
            let c = MLModelConfiguration(); c.computeUnits = .all
            guard let u = Bundle.main.url(forResource: "SarayModel", withExtension: "mlmodelc"),
                  let m = try? MLModel(contentsOf: u, configuration: c), let vm = try? VNCoreMLModel(for: m) else { return }
            let r = VNCoreMLRequest(model: vm)
            r.imageCropAndScaleOption = .scaleFill
            DispatchQueue.main.async { self.istek = r }
        }
    }

    // MARK: oturum
    func baslat() {
        guard destek, !calisiyor else { return }
        let c = ARWorldTrackingConfiguration()
        c.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) { c.sceneReconstruction = .mesh }
        if let d = try? Data(contentsOf: Kasa.haritaURL(oda)),
           let h = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: d) {
            c.initialWorldMap = h
            ipucu = "Odayı tanıyorum… telefonu yavaşça gezdir."
        }
        arView.session.run(c, options: [.resetTracking, .removeExistingAnchors])
        calisiyor = true
    }

    func durdur() {
        guard calisiyor else { return }
        haritayiKaydet { [weak self] in
            Task { @MainActor in self?.arView.session.pause(); self?.calisiyor = false }
        }
    }

    func odaDegistir(_ yeni: String) {
        guard yeni != oda else { return }
        let eski = oda
        haritayiKaydet(oda: eski) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.oda = yeni
                UserDefaults.standard.set(yeni, forKey: "oda")
                self.etiketler = Kasa.etiketler(yeni)
                self.adaylar = [:]; self.gorunenler = []; self.canlilar = []
                self.calisiyor = false
                self.baslat()
                Haptik.secim()
            }
        }
    }

    func odayiSifirla() {
        etiketler = []
        Kasa.yaz([], oda)
        try? FileManager.default.removeItem(at: Kasa.haritaURL(oda))
        calisiyor = false
        baslat()
    }

    private func haritayiKaydet(oda: String? = nil, bitti: (() -> Void)? = nil) {
        let hedef = oda ?? self.oda
        Kasa.yaz(etiketler.filter { $0.oda == hedef }, hedef)
        guard calisiyor else { bitti?(); return }
        arView.session.getCurrentWorldMap { harita, _ in
            if let harita, let d = try? NSKeyedArchiver.archivedData(withRootObject: harita, requiringSecureCoding: true) {
                try? d.write(to: Kasa.haritaURL(hedef), options: .atomic)
            }
            bitti?()
        }
    }

    private func kayitPlanla() {
        Kasa.yaz(etiketler, oda)
        kayitGorevi?.cancel()
        kayitGorevi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.haritayiKaydet()
        }
    }

    // MARK: kare geldikçe
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { kare(frame) }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        MainActor.assumeIsolated {
            switch camera.trackingState {
            case .normal: ipucu = nil
            case .notAvailable: ipucu = "Kamera hazırlanıyor…"
            case .limited(let s):
                switch s {
                case .relocalizing: ipucu = "Odayı tanıyorum… telefonu yavaşça gezdir."
                case .excessiveMotion: ipucu = "Biraz yavaş."
                case .insufficientFeatures: ipucu = "Işık az ya da yüzey düz — eşyalara doğru tut."
                case .initializing: ipucu = "Başlıyor…"
                @unknown default: ipucu = nil
                }
            }
        }
    }

    private func kare(_ f: ARFrame) {
        let simdi = Date()
        if simdi.timeIntervalSince(sonCizim) > 1.0 / 24 { sonCizim = simdi; ciz(f) }
        guard simdi.timeIntervalSince(sonTanima) > 0.33, !tanimaMesgul, let istek, case .normal = f.camera.trackingState else { return }
        sonTanima = simdi
        tanimaMesgul = true
        let tampon = f.capturedImage
        let gorus = arView.bounds.size
        let resim = CGSize(width: CVPixelBufferGetHeight(tampon), height: CVPixelBufferGetWidth(tampon))   // dik tutuluş
        kuyruk.async { [weak self] in
            let h = VNImageRequestHandler(cvPixelBuffer: tampon, orientation: .right, options: [:])
            try? h.perform([istek])
            let sonuc = (istek.results as? [VNRecognizedObjectObservation]) ?? []
            let bulunan: [(String, Float, CGRect)] = sonuc.compactMap { o in
                guard let l = o.labels.first, l.confidence > 0.4 else { return nil }
                return (l.identifier, l.confidence, Goz.ekranKutusu(o.boundingBox, resim: resim, gorus: gorus))
            }
            DispatchQueue.main.async { self?.tanindi(bulunan); self?.tanimaMesgul = false }
        }
    }

    /// Vision kutusu (sol-alt köşe, normalize) → ekran noktası. ARView görüntüyü ekranı dolduracak biçimde (aspect-fill) gösterir.
    nonisolated static func ekranKutusu(_ b: CGRect, resim: CGSize, gorus: CGSize) -> CGRect {
        let olcek = max(gorus.width / resim.width, gorus.height / resim.height)
        let w = resim.width * olcek, h = resim.height * olcek
        let ox = (gorus.width - w) / 2, oy = (gorus.height - h) / 2
        return CGRect(x: b.minX * w + ox, y: (1 - b.maxY) * h + oy, width: b.width * w, height: b.height * h)
    }

    private func tanindi(_ bulunan: [(String, Float, CGRect)]) {
        var yeni: [Canli] = []
        for (sinif, guven, kutu) in bulunan {
            guard let k = sozluk.esle(sinif, oda: oda) else { continue }
            yeni.append(Canli(id: k.en + "\(Int(kutu.midX / 40))", kelime: k, kutu: kutu, guven: guven))
            guard otomatikYerlestir, guven > 0.5 else { continue }
            let merkez = CGPoint(x: kutu.midX, y: kutu.midY)
            guard let t = arView.raycast(from: merkez, allowing: .estimatedPlane, alignment: .any).first?.worldTransform else { continue }
            let p = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            if etiketler.contains(where: { $0.en == k.en && simd_distance($0.nokta, p) < 0.45 }) { continue }
            // iki kare üst üste aynı yerde görülmeden etiket bırakılmaz (yanlış tanımaya karşı)
            let anahtar = k.en
            if let a = adaylar[anahtar], simd_distance(a.nokta, p) < 0.35, Date().timeIntervalSince(a.zaman) < 2.5 {
                adaylar[anahtar] = nil
                birak(k, t, otomatik: true)
            } else {
                adaylar[anahtar] = (1, p, Date())
            }
        }
        // yerleşmiş etiketin üstündeki canlı kutu tekrar yazılmaz
        canlilar = yeni.filter { c in !gorunenler.contains { $0.kelime.en == c.kelime.en && hypot($0.nokta.x - c.kutu.midX, $0.nokta.y - c.kutu.midY) < 90 } }
    }

    private func birak(_ k: Kelime, _ t: simd_float4x4, otomatik: Bool) {
        let id = UUID().uuidString.prefix(10).lowercased()
        arView.session.add(anchor: ARAnchor(name: "saray:\(id)", transform: t))
        etiketler.append(Etiket(id: String(id), en: k.en, oda: oda, otomatik: otomatik, tarih: .now, konum: [t.columns.3.x, t.columns.3.y, t.columns.3.z]))
        Haptik.basari()
        Ses.shared.kendiliginden(k)
        kayitPlanla()
    }

    /// Elle yerleştirme: ekranın ortasındaki noktaya (artı işareti) seçilen kelimeyi bırakır.
    @discardableResult
    func elleBirak(_ k: Kelime, nokta: CGPoint) -> Bool {
        let sonuc = arView.raycast(from: nokta, allowing: .estimatedPlane, alignment: .any).first
            ?? arView.raycast(from: nokta, allowing: .existingPlaneInfinite, alignment: .any).first
        guard let t = sonuc?.worldTransform else { Haptik.uyari(); return false }
        birak(k, t, otomatik: false)
        Ses.shared.oku(k)
        return true
    }

    func sil(_ id: String) {
        if let a = arView.session.currentFrame?.anchors.first(where: { $0.name == "saray:\(id)" }) { arView.session.remove(anchor: a) }
        etiketler.removeAll { $0.id == id }
        gorunenler.removeAll { $0.id == id }
        kayitPlanla()
    }

    // MARK: çizim — kalıcı etiketlerin ekrandaki yeri
    private func ciz(_ f: ARFrame) {
        let cam = f.camera.transform
        let kamera = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
        let ileri = -SIMD3<Float>(cam.columns.2.x, cam.columns.2.y, cam.columns.2.z)
        var cizilen: [Gorunen] = []
        var degisti = false
        for i in etiketler.indices {
            var p = etiketler[i].nokta
            if let a = f.anchors.first(where: { $0.name == "saray:\(etiketler[i].id)" }) {
                let q = SIMD3<Float>(a.transform.columns.3.x, a.transform.columns.3.y, a.transform.columns.3.z)
                if simd_distance(q, p) > 0.02 { etiketler[i].konum = [q.x, q.y, q.z]; degisti = true }
                p = q
            } else if !f.anchors.isEmpty, ipucu != nil {
                continue      // oda henüz tanınmadı: eski koordinat yanlış yerde çizilmesin
            }
            let fark = p - kamera
            let mesafe = simd_length(fark)
            guard mesafe < 7, simd_dot(simd_normalize(fark), ileri) > 0.25, let ekran = arView.project(p) else { continue }
            guard let k = sozluk.kelime(etiketler[i].en) else { continue }
            cizilen.append(Gorunen(id: etiketler[i].id, kelime: k, nokta: ekran, mesafe: mesafe, otomatik: etiketler[i].otomatik))
        }
        gorunenler = cizilen.sorted { $0.mesafe > $1.mesafe }      // yakındaki üstte
        if degisti { Kasa.yaz(etiketler, oda) }
    }

    var odaKelimeleri: [Kelime] { sozluk.odada(oda) }
    var yerlesenler: Set<String> { Set(etiketler.map(\.en)) }
}

enum Haptik {
    static func hafif() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func secim() { UISelectionFeedbackGenerator().selectionChanged() }
    static func basari() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func uyari() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
