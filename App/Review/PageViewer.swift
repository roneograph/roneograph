import ScannerKit
import ScannerModels
import SwiftUI

/// One page at a time, swiping between pages: change its look, rotate it, delete it.
struct PageViewer: View {
    let scan: ScanModel
    @State var selection: UUID
    @State private var cropping: ScanPage?
    @Environment(\.dismiss) private var dismiss

    private var page: ScanPage? { scan.scan.pages.first { $0.id == selection } }
    private var number: Int { (scan.scan.pages.firstIndex { $0.id == selection } ?? 0) + 1 }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(scan.scan.pages) { page in
                    ZoomablePage(url: scan.previewURL(of: page), revision: page.revision)
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
                    Button("Delete Page", systemImage: "trash", role: .destructive) { delete(page) }
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
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1

    var body: some View {
        PageImage(url: url, revision: revision, maximumSize: 2000)
            .padding()
            .scaleEffect(scale)
            .gesture(MagnifyGesture()
                .onChanged { scale = max(1, committedScale * $0.magnification) }
                .onEnded { _ in committedScale = scale })
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = committedScale == 1 ? 2.5 : 1
                    committedScale = scale
                }
            }
    }
}
