import ScannerKit
import SwiftUI
import VisionKit

/// Our pages next to Apple's for the same session.
struct ResultsView: View {
    let model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingAppleScanner = false

    private var session: SpikeSession { model.session }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.pages) { page in
                        NavigationLink(value: page.id) { PageRow(page: page, apple: session.applePage(for: page)) }
                    }
                } footer: {
                    Text("Scan the same pages with Apple's scanner, in the same order, to compare them side by side. Files are in Documents/Spike/\(session.directory.lastPathComponent).")
                }
            }
            .navigationTitle("\(session.pages.count) pages")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { id in
                if let page = session.pages.first(where: { $0.id == id }) {
                    PageDetailView(page: page, apple: session.applePage(for: page))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New session", role: .destructive) {
                        model.newSession()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Scan with Apple's scanner", systemImage: "apple.logo") { showingAppleScanner = true }
                        .disabled(!VNDocumentCameraViewController.isSupported)
                }
            }
            .fullScreenCover(isPresented: $showingAppleScanner) {
                AppleScannerView { images in
                    session.addApplePages(images)
                    showingAppleScanner = false
                }
                .ignoresSafeArea()
            }
        }
    }
}

private struct PageRow: View {
    let page: SpikePage
    let apple: URL?

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: page.cleanURL)
            Thumbnail(url: apple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(page.metadata.number)").font(.headline)
                Text(page.summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path()) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
        }
        .frame(width: 44, height: 60)
    }
}

extension SpikePage {
    var summary: String {
        let m = metadata
        let detector = switch m.stillDetection?.detector {
        case .documentSegmentation: "segmentation"
        case .rectangles: "rectangles"
        case nil: m.liveDetection == nil ? "no page" : "live outline"
        }
        let a = m.analysis
        return "\(m.automatic ? "Auto" : "Manual") · \(detector) · \(m.pageWidth)×\(m.pageHeight)\n"
            + String(format: "%@ · turned %@ · skew %.1f°\n", a.suggestedLook.rawValue, a.orientation.rawValue, a.skewDegrees)
            + String(format: "capture %.0f ms · flatten %.0f ms · clean %.0f ms", m.captureLatency * 1000, m.processingDuration * 1000, m.cleanupDuration * 1000)
    }
}

struct PageDetailView: View {
    enum Version: String, CaseIterable {
        case clean = "Clean", flat = "Flat", apple = "Apple", photo = "Photo"
    }

    let page: SpikePage
    let apple: URL?
    @State private var version = Version.clean

    var body: some View {
        VStack {
            Picker("Version", selection: $version) {
                ForEach(Version.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ZoomableImage(url: url, quad: version == .photo ? page.usedQuad : nil)
            Text(page.summary).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .navigationTitle("Page \(page.metadata.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: url ?? page.cleanURL)
        }
    }

    private var url: URL? {
        switch version {
        case .clean: page.cleanURL
        case .flat: page.pageURL
        case .apple: apple
        case .photo: page.photoURL
        }
    }
}

private struct ZoomableImage: View {
    let url: URL?
    let quad: Quad?
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            if let url, let image = UIImage(contentsOfFile: url.path()) {
                ZStack {
                    Image(uiImage: image).resizable().scaledToFit()
                    if let quad {
                        Canvas { context, size in
                            let fit = min(size.width / image.size.width, size.height / image.size.height)
                            let shown = CGSize(width: image.size.width * fit, height: image.size.height * fit)
                            let origin = CGPoint(x: (size.width - shown.width) / 2, y: (size.height - shown.height) / 2)
                            var path = Path()
                            path.addLines(quad.corners.map { CGPoint(x: origin.x + $0.x * shown.width, y: origin.y + $0.y * shown.height) })
                            path.closeSubpath()
                            context.stroke(path, with: .color(.green), lineWidth: 2 / scale)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(MagnifyGesture()
                    .onChanged { scale = max(1, committedScale * $0.magnification) }
                    .onEnded { _ in committedScale = scale })
                .simultaneousGesture(DragGesture()
                    .onChanged { offset = CGSize(width: committedOffset.width + $0.translation.width, height: committedOffset.height + $0.translation.height) }
                    .onEnded { _ in committedOffset = offset })
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = committedScale == 1 ? 3 : 1
                        committedScale = scale
                        offset = .zero
                        committedOffset = .zero
                    }
                }
            } else {
                ContentUnavailableView("No image", systemImage: "doc", description: Text("Scan this page with Apple's scanner from the list."))
            }
        }
        .clipped()
    }
}

struct AppleScannerView: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void

        init(completion: @escaping ([UIImage]) -> Void) {
            self.completion = completion
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion([])
        }
    }
}
