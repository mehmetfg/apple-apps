// The video of a move: the same animation, written frame by frame to an MP4 that plays offline,
// loops, and can be saved or shared. Made once, then kept in Caches.
import AVFoundation
import AVKit
import SwiftUI

@MainActor
enum MoveVideo {
    static let side = 720
    static let fps: Int32 = 30
    static let version = 1

    static func url(for move: Move, mirrored: Bool) -> URL {
        let dir = URL.cachesDirectory.appending(path: "videos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(move.id)\(mirrored ? "-sol" : "")-v\(version).mp4")
    }

    /// The video file; made now if it is not there.
    static func make(_ move: Move, mirrored: Bool) async throws -> URL {
        let out = url(for: move, mirrored: mirrored)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        let tmp = out.deletingPathExtension().appendingPathExtension("tmp.mp4")
        try? FileManager.default.removeItem(at: tmp)

        let writer = try AVAssetWriter(outputURL: tmp, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: side, AVVideoHeightKey: side])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: side, kCVPixelBufferHeightKey as String: side])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)

        let loops = max(2, Int((8 / max(move.loopLength, 0.1)).rounded(.up)))
        let count = Int(move.loopLength * Double(loops) * Double(fps))
        for i in 0..<count {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let t = Double(i) / Double(fps)
            guard let image = frame(move, time: t, mirrored: mirrored), let buffer = pixelBuffer(image, pool: adaptor.pixelBufferPool) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
            if i % 30 == 0 { await Task.yield() }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: tmp, to: out)
        return out
    }

    private static func frame(_ move: Move, time: Double, mirrored: Bool) -> CGImage? {
        let view = ZStack {
            Theme.night
            FigureCanvas(move: move, time: time, mirrored: mirrored).padding(70)
            VStack {
                Text(move.name).font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                Text(move.dose).font(.system(size: 22, design: .rounded)).foregroundStyle(Theme.ink.opacity(0.6))
                Spacer()
                Text("Gece").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundStyle(Theme.amber.opacity(0.7))
            }
            .padding(.vertical, 28)
        }
        .frame(width: CGFloat(side), height: CGFloat(side))
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.cgImage
    }

    private static func pixelBuffer(_ image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) }
        if buffer == nil {
            CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let b = buffer else { return nil }
        CVPixelBufferLockBaseAddress(b, [])
        defer { CVPixelBufferUnlockBaseAddress(b, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(b), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return b
    }
}

/// Plays the move's video in a loop, with save and share.
struct MoveVideoView: View {
    let move: Move
    var mirrored = false
    @State private var url: URL?
    @State private var failed = false
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Theme.night
            if let url {
                VideoPlayer(player: player)
                    .aspectRatio(1, contentMode: .fit)
                    .onAppear { start(url) }
                    .onDisappear { player.pause() }
                    .overlay(alignment: .topTrailing) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up").padding(10).background(.ultraThinMaterial, in: Circle()) }
                            .accessibilityLabel("Videoyu paylaş ya da kaydet")
                            .padding(8)
                    }
            } else if failed {
                Label("Video hazırlanamadı", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.ink)
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(Theme.amber)
                    Text("Video hazırlanıyor…").font(.footnote).foregroundStyle(Theme.ink.opacity(0.7))
                }
            }
        }
        .task(id: move.id + (mirrored ? "L" : "R")) {
            do { url = try await MoveVideo.make(move, mirrored: mirrored) } catch { failed = true }
        }
    }

    private func start(_ url: URL) {
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.play()
    }
}
