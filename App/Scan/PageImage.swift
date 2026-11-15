import ScannerKit
import SwiftUI
import UIKit

/// A page image loaded off the main thread, reloaded when its revision changes.
struct PageImage: View {
    let url: URL
    let revision: Int
    var maximumSize: CGFloat = 800
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(.quaternary).aspectRatio(Paper.a4.aspectRatio, contentMode: .fit)
            }
        }
        .task(id: Key(url: url, revision: revision)) {
            let url = url, size = maximumSize
            let loaded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
                let scale = min(1, size / max(image.size.width, image.size.height))
                return await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * scale, height: image.size.height * scale))
            }.value
            if let loaded { image = loaded }
        }
    }

    private struct Key: Equatable {
        let url: URL
        let revision: Int
    }
}
