import ScannerKit
import ScannerModels
import SwiftUI

/// One page at a time, swiping between pages: change its look, rotate, crop or delete it.
struct PageViewer: View {
    let scan: ScanModel
    @State var selection: UUID
    @State private var cropping: ScanPage?
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var page: ScanPage? { scan.scan.pages.first { $0.id == selection } }
    private var number: Int { (scan.scan.pages.firstIndex { $0.id == selection } ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(scan.scan.pages.enumerated()), id: \.element.id) { index, page in
                    ZoomablePage(url: scan.previewURL(of: page), revision: page.revision, label: "Page \(index + 1)")
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .safeAreaInset(edge: .bottom) { tools }
            .navigationTitle("Page \(number) of \(scan.scan.pages.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $cropping) { page in
            CropView(scan: scan, page: page)
        }
        .failureAlert(of: scan, isFrontmost: cropping == nil)
        .onChange(of: scan.scan.pages.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    @ViewBuilder
    private var tools: some View {
        if let page {
            VStack(spacing: 12) {
                LookPicker(look: Binding(get: { page.cleanup.look }, set: { scan.setLook($0, of: [page.id]) }))
                    .pickerStyle(.segmented)
                HStack {
                    Text(page.cleanup.look == nil ? "Auto picked \(page.analysis.suggestedLook.title)" : " ")
                    Spacer()
                    if scan.scan.pages.count > 1 {
                        Button("Apply to All Pages") { scan.setLook(page.cleanup.look, of: scan.scan.pages.map(\.id)) }
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                HStack {
                    Button("Rotate", systemImage: "rotate.right") { scan.rotatePage(page.id) }
                    Button("Crop", systemImage: "crop") { cropping = page }
                    Spacer()
                    Button("Delete Page", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete page \(number)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                            Button("Delete Page", role: .destructive) { delete(page) }
                        }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
            }
            .padding()
            .background(.black.opacity(0.6))
        }
    }

    private func delete(_ page: ScanPage) {
        let pages = scan.scan.pages
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let next = pages.indices.contains(index + 1) ? pages[index + 1] : index > 0 ? pages[index - 1] : nil
        scan.deletePage(page.id)
        if let next { selection = next.id }
    }
}

private struct ZoomablePage: View {
    let url: URL
    let revision: Int
    let label: String
    @State private var image: UIImage?

    var body: some View {
        ZoomableImage(image: image, label: label)
            .task(id: PageImage.Key(url: url, revision: revision)) {
                if let loaded = await PageImage.load(url, maximumSize: 2000) { image = loaded }
            }
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    let label: String

    func makeUIView(context: Context) -> ZoomingScrollView { ZoomingScrollView() }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        view.image = image
        view.imageLabel = label
    }
}

private final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    private let margin: CGFloat = 16
    private let doubleTapScale: CGFloat = 2.5
    private let imageView = UIImageView()
    private var fittedSize: CGSize = .zero

    var image: UIImage? {
        get { imageView.image }
        set {
            guard newValue !== imageView.image else { return }
            imageView.image = newValue
            fit()
        }
    }

    var imageLabel: String? {
        get { imageView.accessibilityLabel }
        set { imageView.accessibilityLabel = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize { fit() }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { center() }

    private func fit() {
        fittedSize = bounds.size
        zoomScale = minimumZoomScale
        let available = bounds.insetBy(dx: margin, dy: margin).size
        guard let size = imageView.image?.size, size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return }
        let scale = min(available.width / size.width, available.height / size.height)
        imageView.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        contentSize = imageView.frame.size
        center()
        contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
    }

    private func center() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }

    @objc private func toggleZoom(_ tap: UITapGestureRecognizer) {
        guard zoomScale == minimumZoomScale else {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let point = tap.location(in: imageView)
        let size = CGSize(width: bounds.width / doubleTapScale, height: bounds.height / doubleTapScale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
