import SwiftUI
import VisionKit

/// Wraps VisionKit's live text scanner. UIKit is required here because VisionKit has no SwiftUI view.
struct LiveTextScanner: UIViewControllerRepresentable {
    let isActive: Bool
    let onItemsChanged: ([ScannedText]) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: Self.recognitionLanguages)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if isActive, !scanner.isScanning {
            do {
                try scanner.startScanning()
            } catch {
                onFailure(error.localizedDescription)
            }
        } else if !isActive, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private static var recognitionLanguages: [String] {
        let supported = Set(DataScannerViewController.supportedTextRecognitionLanguages)
        return ["tr-TR", "en-US"].filter(supported.contains)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveTextScanner

        init(parent: LiveTextScanner) {
            self.parent = parent
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            report(allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            report(allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            report(allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            parent.onFailure(error.localizedDescription)
        }

        private func report(_ items: [RecognizedItem]) {
            parent.onItemsChanged(items.compactMap { item in
                guard case .text(let text) = item else { return nil }
                return ScannedText(
                    id: text.id.uuidString,
                    text: text.transcript,
                    frame: Self.frame(of: text.bounds)
                )
            })
        }

        private static func frame(of bounds: RecognizedItem.Bounds) -> CGRect {
            let xs = [bounds.topLeft.x, bounds.topRight.x, bounds.bottomLeft.x, bounds.bottomRight.x]
            let ys = [bounds.topLeft.y, bounds.topRight.y, bounds.bottomLeft.y, bounds.bottomRight.y]
            let minX = xs.min() ?? 0
            let minY = ys.min() ?? 0
            return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
        }
    }
}
