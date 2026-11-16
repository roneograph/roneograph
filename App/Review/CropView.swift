import ScannerKit
import ScannerModels
import SwiftUI
import UIKit

/// Moves the corners and sides of the page outline on the original photo; the page is flattened again on Done.
struct CropView: View {
    let scan: ScanModel
    let page: ScanPage
    @State private var quad: Quad
    @State private var photo: UIImage?
    @State private var dragging: QuadEditor.Handle?
    @State private var dragStart: CGPoint?
    @Environment(\.dismiss) private var dismiss
    private let editor = QuadEditor()

    init(scan: ScanModel, page: ScanPage) {
        self.scan = scan
        self.page = page
        _quad = State(initialValue: page.quad ?? .full)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let photo {
                    editorView(photo: photo, size: geometry.size)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24)
            .background(.black)
            .safeAreaInset(edge: .bottom) { tools }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        if quad != (page.quad ?? .full) {
                            scan.recrop(page.id, quad: quad == .full ? nil : quad)
                        }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            photo = await PageImage.load(scan.photoURL(of: page), maximumSize: 2400)
        }
    }

    private func editorView(photo: UIImage, size: CGSize) -> some View {
        let mapping = ImageViewMapping(imageSize: photo.size, viewSize: size)
        let frame = mapping.imageFrame
        return ZStack(alignment: .topLeading) {
            Image(uiImage: photo)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            Canvas { context, _ in
                var outline = Path()
                outline.addLines(quad.corners.map(mapping.viewPoint(for:)))
                outline.closeSubpath()
                var outside = Path(frame)
                outside.addPath(outline)
                context.fill(outside, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                context.stroke(outline, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .allowsHitTesting(false)
            ForEach(QuadEditor.handles, id: \.self) { handle in
                handleView(handle, mapping: mapping)
            }
            if let dragging {
                Loupe(photo: photo, point: editor.position(of: dragging, in: quad), quad: quad)
                    .position(loupePosition(for: mapping.viewPoint(for: editor.position(of: dragging, in: quad)), in: size))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(.named("crop"))
        .sensoryFeedback(.selection, trigger: snapped)
    }

    private func handleView(_ handle: QuadEditor.Handle, mapping: ImageViewMapping) -> some View {
        let position = mapping.viewPoint(for: editor.position(of: handle, in: quad))
        let isCorner = if case .corner = handle { true } else { false }
        return Circle()
            .fill(dragging == handle ? Color.accentColor : .white)
            .stroke(.tint, lineWidth: 2.5)
            .frame(width: isCorner ? 22 : 14, height: isCorner ? 22 : 14)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(position)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                .onChanged { value in
                    if dragging != handle {
                        dragging = handle
                        dragStart = editor.position(of: handle, in: quad)
                    }
                    guard let start = dragStart else { return }
                    let frame = mapping.imageFrame
                    let target = CGPoint(x: start.x + value.translation.width / frame.width, y: start.y + value.translation.height / frame.height)
                    quad = editor.moving(handle, in: quad, to: target, snapTargets: snapTargets)
                }
                .onEnded { _ in
                    dragging = nil
                    dragStart = nil
                })
            .accessibilityLabel(Self.name(of: handle))
    }

    /// Corners snap to where the page was found, and to the corners of the photo.
    private var snapTargets: [CGPoint] {
        (page.detectedQuad?.corners ?? []) + Quad.full.corners
    }

    /// Changes when a corner lands on a snap target, for the haptic.
    private var snapped: Int {
        quad.corners.filter(snapTargets.contains).count
    }

    /// In the top corner away from the finger, or the bottom one when the finger is near the top.
    private func loupePosition(for point: CGPoint, in size: CGSize) -> CGPoint {
        let x = point.x < size.width / 2 ? size.width - 60 : 60
        let y = point.y < size.height * 0.35 ? size.height - 60 : 60
        return CGPoint(x: x, y: y)
    }

    private var tools: some View {
        HStack(spacing: 28) {
            Button {
                withAnimation { quad = page.detectedQuad ?? .full }
            } label: {
                Label("Detected Edges", systemImage: "wand.and.stars")
            }
            .disabled(page.detectedQuad == nil || quad == page.detectedQuad)
            Button {
                withAnimation { quad = .full }
            } label: {
                Label("Whole Photo", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(quad == .full)
        }
        .buttonStyle(.glass)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black)
    }

    private static func name(of handle: QuadEditor.Handle) -> String {
        switch handle {
        case .corner(0): "Top left corner"
        case .corner(1): "Top right corner"
        case .corner(2): "Bottom right corner"
        case .corner: "Bottom left corner"
        case .side(0): "Top side"
        case .side(1): "Right side"
        case .side(2): "Bottom side"
        case .side: "Left side"
        }
    }
}

/// A magnified view of the photo around the handle being dragged.
private struct Loupe: View {
    let photo: UIImage
    let point: CGPoint
    let quad: Quad
    private let diameter: CGFloat = 110
    private let zoom: CGFloat = 3

    var body: some View {
        let fit = min(diameter / photo.size.width, diameter / photo.size.height)
        let size = CGSize(width: photo.size.width * fit * zoom, height: photo.size.height * fit * zoom)
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .frame(width: size.width, height: size.height)
                .overlay {
                    Canvas { context, canvas in
                        var outline = Path()
                        outline.addLines(quad.corners.map { CGPoint(x: $0.x * canvas.width, y: $0.y * canvas.height) })
                        outline.closeSubpath()
                        context.stroke(outline, with: .color(.accentColor), lineWidth: 1.5)
                    }
                }
                .offset(x: size.width / 2 - point.x * size.width, y: size.height / 2 - point.y * size.height)
            Circle().stroke(.tint, lineWidth: 2).frame(width: 14, height: 14)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(radius: 8)
    }
}
