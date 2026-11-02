// Cover images: decoded and scaled down once at import, stored as JPEG next to the document.
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

enum CoverMaker {
    static let maxPixel = 600

    /// Any image format ImageIO reads (JPEG, PNG, GIF, WebP…) → JPEG thumbnail, without decoding the full image.
    static func jpeg(fromImageData data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return encode(img)
    }

    static func jpeg(fromPDFPage page: PDFPage) -> Data? {
        let box = page.bounds(for: .mediaBox)
        guard box.height > 0 else { return nil }
        let scale = CGFloat(maxPixel) / box.height
        let w = Int(box.width * scale), h = maxPixel
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let img = ctx.makeImage() else { return nil }
        return encode(img)
    }

    private static func encode(_ img: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}
