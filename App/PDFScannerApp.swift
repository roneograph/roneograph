import CoreImage
import ScannerKit
import SwiftUI

@main
struct PDFScannerApp: App {
    @State private var model: CameraModel = {
        let context = CIContext()
        let extractor = PageExtractor(context: context)
        let cleaner = PageCleaner(context: context)
        let processor = PageProcessor(extractor: extractor, cleaner: cleaner)
        let exporter = PDFExporter(cleaner: cleaner, writer: PDFWriter(context: context))
        return CameraModel(session: SpikeSession(), camera: CameraService(extractor: extractor), processor: processor, exporter: exporter)
    }()

    var body: some Scene {
        WindowGroup {
            CameraView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
