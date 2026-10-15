// Live Photo üretimi (intoLive usulü): bir fotoğraf + eşleşen kısa video, aynı kimlikle.
//   • JPEG'in MakerApple sözlüğünde "17" = kimlik
//   • MOV'da com.apple.quicktime.content.identifier = kimlik + "still-image-time" zamanlı üst verisi
// İki kaynak: kendi videon (dikey ekrana kırpılır) ya da Vitrin'in hareketli zemini (kare kare çizilir).
// Kilit ekranında: Duvar Kâğıdı › + › Fotoğraflar › Live Photo'yu seç › sol alttaki ▶︎ açık olsun.
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

enum CanliFotoHata: LocalizedError {
    case video, yazma(String)
    var errorDescription: String? {
        switch self {
        case .video: "Video okunamadı."
        case .yazma(let s): "Live Photo yazılamadı: \(s)"
        }
    }
}

/// Kareleri alır, H.264 MOV + kapak JPEG yazar.
final class CanliYazici {
    let kimlik = UUID().uuidString
    let videoURL: URL
    let fotoURL: URL
    private let yazar: AVAssetWriter
    private let girdi: AVAssetWriterInput
    private let uyarlayici: AVAssetWriterInputPixelBufferAdaptor
    private let ustGirdi: AVAssetWriterInput
    private let ustUyarlayici: AVAssetWriterInputMetadataAdaptor
    private let boy: CGSize
    private let ci = CIContext()
    private var kapakYazildi = false
    let kapakZamani: CMTime

    init(boy: CGSize, sure: Double) throws {
        self.boy = boy
        let gecici = FileManager.default.temporaryDirectory
        videoURL = gecici.appendingPathComponent("canli-\(kimlik).mov")
        fotoURL = gecici.appendingPathComponent("canli-\(kimlik).jpg")
        kapakZamani = CMTime(seconds: sure / 2, preferredTimescale: 600)
        yazar = try AVAssetWriter(outputURL: videoURL, fileType: .mov)

        girdi = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(boy.width), AVVideoHeightKey: Int(boy.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
        ])
        girdi.expectsMediaDataInRealTime = false
        uyarlayici = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: girdi, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(boy.width), kCVPixelBufferHeightKey as String: Int(boy.height),
        ])
        yazar.add(girdi)

        let kimlikOge = AVMutableMetadataItem()
        kimlikOge.keySpace = .quickTimeMetadata
        kimlikOge.key = "com.apple.quicktime.content.identifier" as NSString
        kimlikOge.value = kimlik as NSString
        kimlikOge.dataType = "com.apple.metadata.datatype.UTF-8"
        yazar.metadata = [kimlikOge]

        let tanim: [NSString: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: "com.apple.metadata.datatype.int8",
        ]
        var bicim: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                                                                     metadataSpecifications: [tanim] as CFArray, formatDescriptionOut: &bicim)
        ustGirdi = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: bicim)
        ustUyarlayici = AVAssetWriterInputMetadataAdaptor(assetWriterInput: ustGirdi)
        yazar.add(ustGirdi)

        guard yazar.startWriting() else { throw CanliFotoHata.yazma(yazar.error?.localizedDescription ?? "başlamadı") }
        yazar.startSession(atSourceTime: .zero)

        let an = AVMutableMetadataItem()
        an.keySpace = .quickTimeMetadata
        an.key = "com.apple.quicktime.still-image-time" as NSString
        an.value = 0 as NSNumber
        an.dataType = "com.apple.metadata.datatype.int8"
        ustUyarlayici.append(AVTimedMetadataGroup(items: [an], timeRange: CMTimeRange(start: kapakZamani, duration: CMTime(value: 1, timescale: 100))))
        ustGirdi.markAsFinished()
    }

    /// Kareyi tam boya doldurarak (taşanı kırparak) ekler
    func ekle(_ kaynak: CIImage, zaman: CMTime) async throws {
        let e = kaynak.extent
        let olcek = max(boy.width / e.width, boy.height / e.height)
        var img = kaynak.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: olcek, y: olcek))
        img = img.transformed(by: CGAffineTransform(translationX: -(img.extent.width - boy.width) / 2,
                                                    y: -(img.extent.height - boy.height) / 2))
            .cropped(to: CGRect(origin: .zero, size: boy))
        while !girdi.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
        guard let havuz = uyarlayici.pixelBufferPool else { throw CanliFotoHata.yazma("tampon havuzu yok") }
        var tampon: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, havuz, &tampon)
        guard let tampon else { throw CanliFotoHata.yazma("tampon") }
        ci.render(img, to: tampon)
        uyarlayici.append(tampon, withPresentationTime: zaman)
        if !kapakYazildi, zaman >= kapakZamani, let cg = ci.createCGImage(img, from: img.extent) {
            kapakYaz(cg)
        }
    }

    private func kapakYaz(_ cg: CGImage) {
        kapakYazildi = true
        guard let hedef = CGImageDestinationCreateWithURL(fotoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let ozellik: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": kimlik],
            kCGImageDestinationLossyCompressionQuality: 0.95,
        ]
        CGImageDestinationAddImage(hedef, cg, ozellik as CFDictionary)
        CGImageDestinationFinalize(hedef)
    }

    func bitir() async throws -> (foto: URL, video: URL) {
        girdi.markAsFinished()
        await yazar.finishWriting()
        guard yazar.status == .completed else { throw CanliFotoHata.yazma(yazar.error?.localizedDescription ?? "bitmedi") }
        guard kapakYazildi else { throw CanliFotoHata.yazma("kapak karesi yok") }
        return (fotoURL, videoURL)
    }
}

enum CanliFoto {
    /// Telefonun dikey ekran oranında, 1080 px genişlik
    @MainActor static var hedefBoy: CGSize {
        let e = UIScreen.main.bounds.size
        let w: CGFloat = 1080
        return CGSize(width: w, height: (w * e.height / e.width / 2).rounded() * 2)
    }

    /// Kendi videondan: [bas, bas+sure] aralığı
    static func videodan(_ url: URL, bas: Double, sure: Double, boy: CGSize) async throws -> (foto: URL, video: URL) {
        let varlik = AVURLAsset(url: url)
        guard let iz = try await varlik.loadTracks(withMediaType: .video).first else { throw CanliFotoHata.video }
        let donus = try await iz.load(.preferredTransform)
        let okur = try AVAssetReader(asset: varlik)
        okur.timeRange = CMTimeRange(start: CMTime(seconds: bas, preferredTimescale: 600), duration: CMTime(seconds: sure, preferredTimescale: 600))
        let cikis = AVAssetReaderTrackOutput(track: iz, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        cikis.alwaysCopiesSampleData = false
        okur.add(cikis)
        guard okur.startReading() else { throw CanliFotoHata.video }

        let yazici = try CanliYazici(boy: boy, sure: sure)
        let basZaman = CMTime(seconds: bas, preferredTimescale: 600)
        while let ornek = cikis.copyNextSampleBuffer() {
            guard let px = CMSampleBufferGetImageBuffer(ornek) else { continue }
            let z = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(ornek), basZaman)
            if z < .zero { continue }
            let img = CIImage(cvPixelBuffer: px).oriented(donus.yon)
            try await yazici.ekle(img, zaman: z)
        }
        return try await yazici.bitir()
    }

    /// Vitrin'in hareketli zemininden: faz 0→1 döngüsü kare kare çizilir
    @MainActor static func zeminden(_ d: Duvar, g: Gosterilen, sure: Double = 3, fps: Int = 24,
                                    ilerleme: @escaping (Double) -> Void) async throws -> (foto: URL, video: URL) {
        let boy = hedefBoy
        let yazici = try CanliYazici(boy: boy, sure: sure)
        let ekran = Cizer.ekran
        let olcek = boy.width / ekran.width
        let n = Int(sure * Double(fps))
        for i in 0..<n {
            let faz = Double(i) / Double(n)
            guard let img = Cizer.duvar(d, g: g, faz: faz, boy: ekran, olcek: olcek), let cg = img.cgImage else { continue }
            try await yazici.ekle(CIImage(cgImage: cg), zaman: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            ilerleme(Double(i + 1) / Double(n))
            await Task.yield()
        }
        return try await yazici.bitir()
    }
}

private extension CGAffineTransform {
    /// Videonun kayıt yönü (preferredTransform) → görüntü yönü; dikey iPhone videosu .right gelir
    var yon: CGImagePropertyOrientation {
        switch (a, b, c, d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
