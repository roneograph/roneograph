import AVFoundation
import ScannerKit
import SwiftUI

struct CameraView: View {
    @Bindable var model: CameraModel
    @State private var showingResults = false
    @State private var flash = false

    var body: some View {
        ZStack {
            PreviewView(session: model.captureSession).ignoresSafeArea()
            QuadOverlay(detection: model.detection, imageSize: model.imageSize, state: model.state).ignoresSafeArea()
            Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                Text(model.hint)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(isWaiting ? AnyShapeStyle(.green.opacity(0.85)) : AnyShapeStyle(.black.opacity(0.55)), in: Capsule())
                    .foregroundStyle(.white)
                Spacer()
                bottomBar
            }
            .padding()
        }
        .background(.black)
        .onAppear { model.start() }
        .onChange(of: model.captureCount) {
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            withAnimation(.easeIn(duration: 0.3).delay(0.08)) { flash = false }
        }
        .sensoryFeedback(.impact, trigger: model.captureCount)
        .sheet(isPresented: $showingResults, onDismiss: { model.start() }) {
            ResultsView(model: model)
        }
    }

    private var isWaiting: Bool { model.state == .waitingForNextPage }

    private var topBar: some View {
        HStack {
            Text(stats)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .padding(6)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Spacer()
            Button(model.autoCapture ? "Auto" : "Manual") { model.autoCapture.toggle() }
                .buttonStyle(.glass)
        }
    }

    private var stats: String {
        let live = model.session.liveStats
        let detector = model.detection.map { "\($0.detector == .documentSegmentation ? "seg" : "rect") \(String(format: "%.2f", $0.confidence))" } ?? "none"
        return String(format: "%.0f ms · %@", live.averageDetectionMilliseconds, detector)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                model.stop()
                showingResults = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    if let page = model.session.pages.last, let image = UIImage(contentsOfFile: page.cleanURL.path()) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.15)).frame(width: 48, height: 60)
                    }
                    if model.processing > 0 {
                        ProgressView().tint(.white).frame(width: 48, height: 60)
                    }
                    Text("\(model.session.pages.count)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22).background(.blue, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: model.shutter) {
                ZStack {
                    Circle().stroke(.white.opacity(0.4), lineWidth: 4)
                    Circle().trim(from: 0, to: model.progress).stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Circle().fill(.white).padding(8)
                }
                .frame(width: 72, height: 72)
            }

            Button("Done") {
                model.stop()
                showingResults = true
            }
            .buttonStyle(.glassProminent)
            .disabled(model.session.pages.isEmpty)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct QuadOverlay: View {
    let detection: PageDetection?
    let imageSize: CGSize
    let state: CaptureTrigger.State

    var body: some View {
        Canvas { context, size in
            guard let quad = detection?.quad else { return }
            let mapping = ImageViewMapping(imageSize: imageSize, viewSize: size, scaling: .fit)
            var path = Path()
            path.addLines(quad.corners.map(mapping.viewPoint(for:)))
            path.closeSubpath()
            switch state {
            case .waitingForNextPage:
                context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, dash: [8, 7]))
            case .pageCutOff:
                context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            default:
                context.fill(path, with: .color(.blue.opacity(0.2)))
                context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.08), value: detection)
    }
}

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSessionBox

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session.session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
