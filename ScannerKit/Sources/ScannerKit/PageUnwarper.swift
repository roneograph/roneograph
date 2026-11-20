import CoreImage
import CoreML

/// Flattens a curled or folded page with UVDoc (Verhoeven et al., 2023), a small neural network that tells,
/// for a 45 × 31 grid over the flat page, where each point lies in the photo.
public struct PageUnwarper: Sendable {
    private static let inputWidth = 488, inputHeight = 712
    /// Share of the outline's size added around it, so the network sees the page edges against the background.
    private static let margin: CGFloat = 0.03

    private let context: CIContext
    private let model: Task<Model?, Never>

    /// Starts loading the network in the background: the first load takes seconds and must not hold up the launch.
    public init(context: CIContext) {
        self.init(context: context, model: Model.bundled)
    }

    /// Loads the network with `load`, in the background.
    init(context: CIContext, load: @escaping @Sendable () -> MLModel?) {
        self.init(context: context, model: Model.loading(load))
    }

    private init(context: CIContext, model: Task<Model?, Never>) {
        self.context = context
        self.model = model
    }

    /// The license of the network's code and weights, shown in the app.
    public static var license: String {
        Bundle.module.url(forResource: "UVDoc-LICENSE", withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// The page inside `quad` flattened to `size`, nil when the network cannot run.
    public func unwarp(_ photo: CIImage, quad: Quad, size: CGSize) async -> CIImage? {
        guard size.width >= 2, size.height >= 2, let model = await model.value else { return nil }
        let photo = photo.atOrigin
        let crop = Self.cropRect(of: quad, in: photo.extent.size)
        guard crop.width >= 2, crop.height >= 2 else { return nil }
        let region = photo.cropped(to: crop).atOrigin
        guard let input = input(of: region), let grid = try? await model.grid(for: input) else { return nil }
        let source = PixelBuffer(region, context: context)
        let output = grid.warp(source, width: Int(size.width.rounded()), height: Int(size.height.rounded()))
        return output.image
    }

    /// The outline's bounding box with a margin, in Core Image coordinates.
    static func cropRect(of quad: Quad, in size: CGSize) -> CGRect {
        let xs = quad.corners.map(\.x), ys = quad.corners.map(\.y)
        let marginX = margin * (xs.max()! - xs.min()!), marginY = margin * (ys.max()! - ys.min()!)
        let left = max(0, xs.min()! - marginX), right = min(1, xs.max()! + marginX)
        let top = max(0, ys.min()! - marginY), bottom = min(1, ys.max()! + marginY)
        return CGRect(x: left * size.width, y: (1 - bottom) * size.height, width: (right - left) * size.width, height: (bottom - top) * size.height).integral
    }

    /// The region squeezed to the network's input, channel after channel, values from 0 to 1.
    private func input(of region: CIImage) -> MLShapedArray<Float16>? {
        let width = Self.inputWidth, height = Self.inputHeight
        let small = region.clampedToExtent().transformed(by: CGAffineTransform(scaleX: CGFloat(width) / region.extent.width, y: CGFloat(height) / region.extent.height))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &pixels, rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var planes = [Float16](repeating: 0, count: 3 * width * height)
        for i in 0..<(width * height) {
            for channel in 0..<3 {
                planes[channel * width * height + i] = Float16(pixels[i * 4 + channel])
            }
        }
        return MLShapedArray(scalars: planes, shape: [1, 3, height, width])
    }

    private final class Model: @unchecked Sendable {
        static let bundled = loading {
            Bundle.module.url(forResource: "UVDoc", withExtension: "mlmodelc").flatMap { try? MLModel(contentsOf: $0) }
        }

        static func loading(_ load: @escaping @Sendable () -> MLModel?) -> Task<Model?, Never> {
            Task.detached(priority: .utility) { load().map(Model.init) }
        }

        private let model: MLModel

        init(_ model: MLModel) {
            self.model = model
        }

        func grid(for input: MLShapedArray<Float16>) async throws -> UnwarpGrid {
            let features = try MLDictionaryFeatureProvider(dictionary: ["image": MLMultiArray(input)])
            let output = try await model.prediction(from: features)
            guard let grid = output.featureValue(for: "grid")?.multiArrayValue else { throw CocoaError(.coderReadCorrupt) }
            return UnwarpGrid(MLShapedArray<Float>(converting: grid))
        }
    }
}

/// For each point of a grid over the flat page, its position in the photo, from -1 to 1 between the centers of the edge pixels.
struct UnwarpGrid {
    let rows: Int
    let columns: Int
    /// x then y for each point, row after row.
    let points: [SIMD2<Float>]

    init(rows: Int, columns: Int, points: [SIMD2<Float>]) {
        self.rows = rows
        self.columns = columns
        self.points = points
    }

    /// From the network's output, shaped 1 × 2 × rows × columns.
    init(_ output: MLShapedArray<Float>) {
        let rows = output.shape[2], columns = output.shape[3]
        let scalars = output.scalars
        self.init(rows: rows, columns: columns, points: (0..<(rows * columns)).map { SIMD2(scalars[$0], scalars[rows * columns + $0]) })
    }

    /// Samples the source through the grid, stretched bilinearly over the output.
    func warp(_ source: PixelBuffer, width: Int, height: Int) -> PixelBuffer {
        var output = PixelBuffer(width: width, height: height)
        let scale = SIMD2(Float(source.width - 1), Float(source.height - 1)) / 2
        var row = [SIMD2<Float>](repeating: .zero, count: columns)
        output.pixels.withUnsafeMutableBufferPointer { out in
            source.pixels.withUnsafeBufferPointer { pixels in
                for y in 0..<height {
                    let gy = height > 1 ? Float(y) * Float(rows - 1) / Float(height - 1) : 0
                    let r0 = min(Int(gy), rows - 1), r1 = min(r0 + 1, rows - 1), wy = gy - Float(r0)
                    for c in 0..<columns {
                        row[c] = points[r0 * columns + c] * (1 - wy) + points[r1 * columns + c] * wy
                    }
                    for x in 0..<width {
                        let gx = width > 1 ? Float(x) * Float(columns - 1) / Float(width - 1) : 0
                        let c0 = min(Int(gx), columns - 1), c1 = min(c0 + 1, columns - 1), wx = gx - Float(c0)
                        let p = ((row[c0] * (1 - wx) + row[c1] * wx) + 1) * scale
                        PixelBuffer.sample(pixels, width: source.width, height: source.height, at: p, into: out, offset: (y * width + x) * 4)
                    }
                }
            }
        }
        return output
    }
}

/// An sRGB RGBA8 image, row 0 at the top.
struct PixelBuffer {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 255, count: width * height * 4)
    }

    init(_ image: CIImage, context: CIContext) {
        self.init(width: Int(image.extent.width), height: Int(image.extent.height))
        context.render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    var image: CIImage {
        CIImage(bitmapData: Data(pixels), bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Bilinear sample at a pixel position, clamped to the edges.
    static func sample(_ pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, at p: SIMD2<Float>, into out: UnsafeMutableBufferPointer<UInt8>, offset: Int) {
        let x = min(max(p.x, 0), Float(width - 1)), y = min(max(p.y, 0), Float(height - 1))
        let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let wx = x - Float(x0), wy = y - Float(y0)
        let a = (y0 * width + x0) * 4, b = (y0 * width + x1) * 4, c = (y1 * width + x0) * 4, d = (y1 * width + x1) * 4
        for channel in 0..<3 {
            let top = Float(pixels[a + channel]) * (1 - wx) + Float(pixels[b + channel]) * wx
            let bottom = Float(pixels[c + channel]) * (1 - wx) + Float(pixels[d + channel]) * wx
            out[offset + channel] = UInt8(top * (1 - wy) + bottom * wy + 0.5)
        }
        out[offset + 3] = 255
    }
}
