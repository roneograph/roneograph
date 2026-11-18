/// The pixels of the outer rows and columns of a one-channel image.
public func edgePixels(of pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
    let rows: [UInt8] = (0..<width).flatMap { x in [pixels[x], pixels[(height - 1) * width + x]] }
    let columns: [UInt8] = (0..<height).flatMap { y in [pixels[y * width], pixels[y * width + width - 1]] }
    return rows + columns
}
