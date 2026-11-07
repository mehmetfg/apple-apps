// Tara (2026-11-04): text from paper. The camera's document scanner (VisionKit: edges found, pages straightened,
// many pages in one go) or photos from the library; Vision reads them in Turkish and English on the phone, nothing
// leaves it. The lines are put back into paragraphs (a gap larger than a line, or an indented start, opens a new
// one), the result is shown with a title to change, and it joins the library through the same first pass for
// listening as every other format (TextCleaner).
import SwiftUI
import PhotosUI
import Vision
import VisionKit

enum TextScanner {
    /// The text of one page image, as paragraphs.
    static func read(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        let orientation = image.cgOrientation
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation)
            guard (try? handler.perform([request])) != nil else { return [] }
            return paragraphs(request.results ?? [])
        }.value
    }

    /// Lines top to bottom; a new paragraph where the gap is larger than about a line, or where a line starts
    /// clearly to the right of the column (an indent). A lone short line in the page's header or footer band
    /// that is only a number (a page number) is dropped.
    static func paragraphs(_ obs: [VNRecognizedTextObservation]) -> [String] {
        struct Line { var text: String; var box: CGRect }
        var lines = obs.compactMap { o -> Line? in
            guard let t = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return Line(text: t, box: o.boundingBox)              // normalised, origin at the bottom left
        }
        lines.removeAll { l in
            (l.box.minY > 0.93 || l.box.maxY < 0.07) && l.text.allSatisfy { $0.isNumber || $0 == "-" || $0 == " " }
        }
        lines.sort { $0.box.maxY > $1.box.maxY }
        guard !lines.isEmpty else { return [] }
        let heights = lines.map(\.box.height).sorted()
        let lineHeight = heights[heights.count / 2]
        let left = lines.map(\.box.minX).sorted()[lines.count / 4]
        var out: [String] = []
        var current = ""
        var previous: Line?
        for l in lines {
            if let p = previous {
                let gap = p.box.minY - l.box.maxY
                let indented = l.box.minX - left > lineHeight * 1.2
                if gap > lineHeight * 0.9 || indented {
                    out.append(current); current = ""
                }
            }
            if current.isEmpty { current = l.text }
            else if current.hasSuffix("-") { current = String(current.dropLast()) + l.text }   // a word broken at the line end
            else { current += " " + l.text }
            previous = l
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}

/// The camera's document scanner.
struct DocumentScanner: UIViewControllerRepresentable {
    var onDone: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onDone: ([UIImage]) -> Void
        init(onDone: @escaping ([UIImage]) -> Void) { self.onDone = onDone }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onDone((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { onDone([]) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { onDone([]) }
    }
}

/// The pages read, their text to look over, a title; then into the library.
struct ScanReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let images: [UIImage]
    var folder: String?
    @State private var pages: [[String]] = []
    @State private var title = ""
    @State private var reading = true

    private var paragraphs: [String] { pages.flatMap { $0 } }
    private var words: Int { paragraphs.reduce(0) { $0 + $1.split(separator: " ").count } }

    var body: some View {
        NavigationStack {
            Group {
                if reading {
                    ProgressView("\(images.count) sayfa okunuyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if paragraphs.isEmpty {
                    ContentUnavailableView("Metin bulunamadı", systemImage: "text.viewfinder",
                                           description: Text("Sayfayı daha yakından, ışıkta ve düz tutarak yeniden tara."))
                } else {
                    Form {
                        Section {
                            TextField("Başlık", text: $title)
                        } footer: { Text("\(images.count) sayfa · \(words.formatted()) kelime · \(paragraphs.count) paragraf") }
                        ForEach(pages.indices, id: \.self) { i in
                            Section("Sayfa \(i + 1)") {
                                Text(pages[i].joined(separator: "\n\n"))
                                    .font(.system(.callout, design: .serif))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tarama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") { add() }.disabled(reading || paragraphs.isEmpty)
                }
            }
            .task {
                var out: [[String]] = []
                for img in images { out.append(await TextScanner.read(img)) }
                pages = out
                title = paragraphs.first.map { String($0.prefix(60)) } ?? ""
                reading = false
            }
        }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let doc = DocumentImporter.assemble(title: t.isEmpty ? "Tarama" : t, author: nil, format: .txt,
                                            sourceName: "Tarama · \(Date.now.formatted(date: .abbreviated, time: .shortened))",
                                            paragraphs: paragraphs, headings: [])
        model.addScanned(doc, folder: folder)
        dismiss()
    }
}

extension AppModel {
    func addScanned(_ doc: ImportedDocument, folder: String?) {
        guard let rec = try? store.add(doc, original: nil) else { importMessage = "Tarama eklenemedi."; return }
        if let f = folder { store.update(rec.id) { $0.folder = f } }
        sync.publish(rec.id)
        importMessage = "“\(doc.title)” eklendi · \(doc.wordCount.formatted()) kelime."
    }
}

/// The two ways in, for the + menus: the camera and the photo library. Put on a view; `scan` and `photos` open them.
struct ScanImportModifier: ViewModifier {
    @Binding var scan: Bool
    @Binding var photos: Bool
    var folder: String?
    @State private var picked: [PhotosPickerItem] = []
    @State private var review: ScanBatch?

    struct ScanBatch: Identifiable { let id = UUID(); let images: [UIImage] }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $scan) {
                DocumentScanner { imgs in
                    scan = false
                    if !imgs.isEmpty { review = ScanBatch(images: imgs) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $photos, selection: $picked, maxSelectionCount: 30, matching: .images)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var imgs: [UIImage] = []
                    for it in items {
                        if let data = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: data) { imgs.append(img) }
                    }
                    picked = []
                    if !imgs.isEmpty { review = ScanBatch(images: imgs) }
                }
            }
            .sheet(item: $review) { ScanReviewSheet(images: $0.images, folder: folder) }
    }
}
