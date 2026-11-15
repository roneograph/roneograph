import CoreImage
import ScannerKit
import SwiftUI

@main
struct PDFScannerApp: App {
    @State private var model: CameraModel = {
        let extractor = PageExtractor(context: CIContext())
        return CameraModel(session: SpikeSession(), camera: CameraService(extractor: extractor), processor: PageProcessor(extractor: extractor))
    }()

    var body: some Scene {
        WindowGroup {
            CameraView(model: model)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
