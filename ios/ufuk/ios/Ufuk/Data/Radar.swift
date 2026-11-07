// RainViewer radar frames (past two hours and the short nowcast where it exists) as a MapKit tile overlay.
import Foundation
import MapKit
import SwiftUI

struct RadarFrame: Hashable, Sendable {
    var time: Date
    var url: String           // tile template
    var nowcast: Bool
}

enum Radar {
    static func frames() async -> [RadarFrame] {
        guard let u = URL(string: "https://api.rainviewer.com/public/weather-maps.json"),
              let (d, _) = try? await URLSession.shared.data(from: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let host = o["host"] as? String, let radar = o["radar"] as? [String: Any] else { return [] }
        func list(_ k: String, _ now: Bool) -> [RadarFrame] {
            ((radar[k] as? [[String: Any]]) ?? []).compactMap { f in
                guard let t = (f["time"] as? NSNumber)?.doubleValue, let p = f["path"] as? String else { return nil }
                // 256 px tiles, colour scheme 4 (The Weather Channel), smoothed, snow shown
                return RadarFrame(time: Date(timeIntervalSince1970: t), url: "\(host)\(p)/256/{z}/{x}/{y}/4/1_1.png", nowcast: now)
            }
        }
        return list("past", false) + list("nowcast", true)
    }
}

/// RainViewer answers only up to zoom 7 ("Zoom Level Not Supported" above it). For the city zooms this
/// overlay cuts the right part out of the zoom-7 parent tile and scales it up.
final class RadarOverlay: MKTileOverlay {
    static let maxZ = 7
    private let cache = NSCache<NSString, UIImage>()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        guard path.z > Self.maxZ else { return super.loadTile(at: path, result: result) }
        let dz = path.z - Self.maxZ
        let parent = MKTileOverlayPath(x: path.x >> dz, y: path.y >> dz, z: Self.maxZ, contentScaleFactor: path.contentScaleFactor)
        let key = "\(parent.x)/\(parent.y)" as NSString
        let cut: (UIImage) -> Data? = { img in
            let n = 1 << dz
            let side = img.size.width / CGFloat(n)
            let ox = CGFloat(path.x - (parent.x << dz)) * side, oy = CGFloat(path.y - (parent.y << dz)) * side
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: fmt).pngData { ctx in
                ctx.cgContext.interpolationQuality = .high
                img.draw(in: CGRect(x: -ox * CGFloat(n), y: -oy * CGFloat(n), width: img.size.width * CGFloat(n), height: img.size.height * CGFloat(n)))
            }
        }
        if let img = cache.object(forKey: key) { return result(cut(img), nil) }
        super.loadTile(at: parent) { [weak self] data, err in
            guard let data, let img = UIImage(data: data) else { return result(nil, err) }
            self?.cache.setObject(img, forKey: key)
            result(cut(img), nil)
        }
    }
}

/// MKMapView with the radar overlay; SwiftUI's Map cannot show tile overlays.
struct RadarMap: UIViewRepresentable {
    var center: CLLocationCoordinate2D
    var frame: RadarFrame?
    var pins: [MapPin] = []

    struct MapPin: Hashable { var lat: Double; var lon: Double; var title: String }

    func makeUIView(context: Context) -> MKMapView {
        let m = MKMapView()
        m.delegate = context.coordinator
        m.overrideUserInterfaceStyle = .dark
        m.pointOfInterestFilter = .excludingAll
        m.showsUserLocation = true
        m.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 140_000, longitudinalMeters: 140_000), animated: false)
        return m
    }

    func updateUIView(_ m: MKMapView, context: Context) {
        if context.coordinator.shown != frame?.url {
            m.removeOverlays(m.overlays)
            if let f = frame {
                let o = RadarOverlay(urlTemplate: f.url)
                o.canReplaceMapContent = false
                m.addOverlay(o, level: .aboveLabels)
            }
            context.coordinator.shown = frame?.url
        }
        let want = Set(pins.map(\.title))
        let have = Set(m.annotations.compactMap { $0.title ?? nil })
        if want != have {
            m.removeAnnotations(m.annotations.filter { !($0 is MKUserLocation) })
            m.addAnnotations(pins.map { p in
                let a = MKPointAnnotation(); a.coordinate = .init(latitude: p.lat, longitude: p.lon); a.title = p.title; return a
            })
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var shown: String?
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let t = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: t); r.alpha = 0.6; return r
        }
    }
}
