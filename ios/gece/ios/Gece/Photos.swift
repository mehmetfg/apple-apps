// The photos of a move: two or three still frames of the mannequin (veri/photos.py renders them from moves.json).
// Frames are shown as numbered photos: the strip on the detail page, a slow cross-fade during the night.
import Combine
import SwiftUI
import UIKit

enum MovePhotos {
    private static var cache: [String: [UIImage]] = [:]

    /// The frames of a move, in order; empty when none were rendered.
    static func images(_ id: String) -> [UIImage] {
        if let c = cache[id] { return c }
        var out: [UIImage] = []
        for n in 1...4 {
            let name = "\(id)-\(n)"
            let url = Bundle.main.url(forResource: name, withExtension: "jpg")
                ?? Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Photos")
            guard let url, let img = UIImage(contentsOfFile: url.path) else { break }
            out.append(img)
        }
        cache[id] = out
        return out
    }
}

/// One frame, mirrored for the left side, with its number in the corner.
struct PhotoFrame: View {
    var image: UIImage
    var number: Int?
    var mirrored = false
    var corner: CGFloat = 14

    var body: some View {
        Image(uiImage: image).resizable().scaledToFill()
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(alignment: .topLeading) {
                if let number {
                    Text("\(number)").font(.caption.bold()).frame(width: 22, height: 22)
                        .background(Theme.amber, in: Circle()).foregroundStyle(Theme.night).padding(8)
                }
            }
    }
}

/// The thumbnail of a move: its first frame, or the drawn figure when no photo exists.
struct MoveThumb: View {
    var move: Move
    var body: some View {
        if let first = MovePhotos.images(move.id).first {
            Image(uiImage: first).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            FigureView(move: move)
        }
    }
}

/// During the night: one big photo at a time, changing every few seconds, with the frame dots under it.
/// The timing follows the move's own keyframe rhythm closely enough: hold, then the next position.
struct PhotoPlayer: View {
    var move: Move
    var mirrored = false
    var paused = false
    @State private var shown = 0

    var body: some View {
        let imgs = MovePhotos.images(move.id)
        if imgs.isEmpty {
            FigureView(move: move, mirrored: mirrored, paused: paused)
        } else {
            VStack(spacing: 10) {
                ZStack {
                    ForEach(imgs.indices, id: \.self) { i in
                        PhotoFrame(image: imgs[i], number: imgs.count > 1 ? i + 1 : nil, mirrored: mirrored, corner: 20)
                            .opacity(i == shown % imgs.count ? 1 : 0)
                    }
                }
                .aspectRatio(900.0 / 640.0, contentMode: .fit)
                .animation(.easeInOut(duration: 0.9), value: shown)
                if imgs.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(imgs.indices, id: \.self) { i in
                            Capsule().fill(i == shown % imgs.count ? Theme.amber : Theme.line).frame(width: i == shown % imgs.count ? 22 : 8, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: shown)
                }
            }
            .onChange(of: move.id + (mirrored ? "L" : "R")) { _, _ in shown = 0 }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if !paused { shown += 1 }
            }
        }
    }
}

/// The detail page: every frame large, swipeable, and the small row of all frames under it.
struct PhotoGallery: View {
    var move: Move
    var mirrored = false
    @State private var page = 0

    var body: some View {
        let imgs = MovePhotos.images(move.id)
        if imgs.isEmpty {
            FigureView(move: move, mirrored: mirrored).frame(height: 260)
        } else {
            VStack(spacing: 10) {
                TabView(selection: $page) {
                    ForEach(imgs.indices, id: \.self) { i in
                        PhotoFrame(image: imgs[i], number: i + 1, mirrored: mirrored, corner: 18).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(900.0 / 640.0, contentMode: .fit)
                HStack(spacing: 8) {
                    ForEach(imgs.indices, id: \.self) { i in
                        Button { withAnimation { page = i } } label: {
                            PhotoFrame(image: imgs[i], number: nil, mirrored: mirrored, corner: 8)
                                .aspectRatio(900.0 / 640.0, contentMode: .fit)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == page ? Theme.amber : .clear, lineWidth: 2))
                        }
                    }
                }
            }
        }
    }
}
