import AVFoundation
import AVKit
import ScannerKit
import ScannerModels
import SwiftUI

struct CameraView: View {
    let camera: CameraModel
    let session: AVCaptureSession
    let scan: ScanModel
    let close: () -> Void
    let done: () -> Void
    @State private var flashOverlay = false
    @State private var showingLastPage = false
    /// The name of the scan when the camera opened on a scan that already had pages.
    @State private var addingTo: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.access == .denied || camera.access == .unavailable {
                deniedView
            } else {
                PreviewView(session: session).ignoresSafeArea()
                QuadOverlay(quad: camera.quad, imageSize: camera.imageSize, state: camera.state).ignoresSafeArea()
                Color.white.opacity(flashOverlay ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 12) {
                    topBar
                    hint
                    Spacer()
                    if let addingTo {
                        Text("Adding to \(Text(addingTo).bold())")
                            .font(.footnote)
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    bottomBar
                }
                .padding()
            }
            if camera.access == .denied || camera.access == .unavailable {
                VStack {
                    HStack { closeButton; Spacer() }
                    Spacer()
                }
                .padding()
            }
        }
        .onAppear {
            if !scan.scan.pages.isEmpty { addingTo = scan.scan.title }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task(id: scan.scan.id) { await camera.start(scan: scan) }
        .onDisappear { camera.stop() }
        .onChange(of: camera.captures) {
            withAnimation(.easeOut(duration: 0.08)) { flashOverlay = true }
            withAnimation(.easeIn(duration: 0.3).delay(0.08)) { flashOverlay = false }
        }
        .onChange(of: camera.hint) { _, hint in
            AccessibilityNotification.Announcement(hint.text).post()
        }
        .sensoryFeedback(.impact, trigger: camera.captures)
        .sensoryFeedback(.selection, trigger: camera.locks)
        .onCameraCaptureEvent { event in
            if event.phase == .ended { camera.shutter() }
        }
        .sheet(isPresented: $showingLastPage) {
            LastPageView(scan: scan) { retake in
                if retake { camera.retake() }
            }
            .presentationDetents([.large])
        }
    }

    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            Button("Flash", systemImage: camera.flash.systemImage) { camera.flash = camera.flash.next }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityValue(String(describing: camera.flash))
            Button(camera.autoCapture ? "Auto" : "Manual") { camera.autoCapture.toggle() }
                .buttonStyle(.glass)
                .fontWeight(.semibold)
        }
        .controlSize(.large)
    }

    private var closeButton: some View {
        Button("Close", systemImage: "xmark", action: close)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
    }

    private var hint: some View {
        Label {
            Text(camera.hint.text)
        } icon: {
            if let image = camera.hint.systemImage { Image(systemName: image) }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(camera.hint == .holdStill ? AnyShapeStyle(.tint.opacity(0.9)) : AnyShapeStyle(.black.opacity(0.6)), in: Capsule())
        .foregroundStyle(.white)
        .animation(.default, value: camera.hint)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                showingLastPage = true
            } label: {
                PageStack(scan: scan, count: camera.pageCount)
            }
            .disabled(scan.scan.pages.isEmpty)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(camera.pageCount) pages")

            Button(action: camera.shutter) {
                ZStack {
                    Circle().stroke(.white.opacity(0.4), lineWidth: 4)
                    Circle().trim(from: 0, to: camera.progress).stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Circle().fill(.white).padding(8)
                }
                .frame(width: 72, height: 72)
            }
            .accessibilityLabel("Capture")

            Button("Done", action: done)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .opacity(camera.pageCount == 0 ? 0 : 1)
                .disabled(camera.pageCount == 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var deniedView: some View {
        if camera.access == .unavailable {
            ContentUnavailableView("No camera", systemImage: "camera", description: Text("Roneograph needs an iPhone camera to scan pages."))
        } else {
            accessOffView
        }
    }

    private var accessOffView: some View {
        ContentUnavailableView {
            Label("Camera access is off", systemImage: "camera")
        } description: {
            Text("Roneograph needs the camera to scan pages.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.glassProminent)
        }
    }
}

private struct PageStack: View {
    let scan: ScanModel
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let page = scan.scan.pages.last {
                PageImage(url: scan.previewURL(of: page), revision: page.revision)
                    .frame(width: 48, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(count > 0 ? 0.3 : 0.12)).frame(width: 48, height: 60)
            }
            if scan.processing > 0 {
                ProgressView().tint(.white).frame(width: 48, height: 60)
            }
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22).background(.tint, in: Circle())
                    .offset(x: 8, y: -8)
            }
        }
    }
}

/// The last page captured, to keep it, take it again or delete it.
private struct LastPageView: View {
    let scan: ScanModel
    let done: (_ retake: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let page = scan.scan.pages.last {
                    PageImage(url: scan.previewURL(of: page), revision: page.revision)
                        .padding()
                }
            }
            .navigationTitle("Page \(scan.scan.pages.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Delete", systemImage: "trash", role: .destructive) { remove(retake: false) }
                    Spacer()
                    Button("Retake", systemImage: "camera") { remove(retake: true) }
                }
            }
        }
    }

    private func remove(retake: Bool) {
        if let page = scan.scan.pages.last { scan.deletePage(page.id) }
        done(retake)
        dismiss()
    }
}

struct QuadOverlay: View {
    let quad: Quad?
    let imageSize: CGSize
    let state: CaptureTrigger.State

    var body: some View {
        Canvas { context, size in
            guard let quad else { return }
            let mapping = ImageViewMapping(imageSize: imageSize, viewSize: size, scaling: .fit)
            var path = Path()
            path.addLines(quad.corners.map(mapping.viewPoint(for:)))
            path.closeSubpath()
            switch state {
            case .waitingForNextPage:
                context.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, dash: [8, 7]))
            case .pageCutOff, .pageTooSmall:
                context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            default:
                context.fill(path, with: .color(.accentColor.opacity(0.2)))
                context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.08), value: quad)
    }
}

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
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
