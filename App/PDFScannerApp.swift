import CoreImage
import ScannerKit
import SwiftUI

@main
struct PDFScannerApp: App {
    @State private var model: CameraModel = {
        let context = CIContext()
        let extractor = PageExtractor(context: context)
        let processor = PageProcessor(extractor: extractor, cleaner: PageCleaner(context: context))
        return CameraModel(session: SpikeSession(), camera: CameraService(extractor: extractor), processor: processor)
    }()

    var body: some Scene {
        WindowGroup {
            CameraView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
