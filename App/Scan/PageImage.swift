import ImageIO
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
            if let loaded = await Self.load(url, maximumSize: maximumSize) { image = loaded }
        }
    }

    /// The image at most `maximumSize` pixels on its long side, turned upright, downsampled while decoding.
    static func load(_ url: URL, maximumSize: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceShouldCacheImmediately: true,
                      kCGImageSourceThumbnailMaxPixelSize: Int(maximumSize),
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    struct Key: Equatable {
        let url: URL
        let revision: Int
    }
}
