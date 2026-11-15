import ScannerKit
import SwiftUI

/// One page at a time, swiping between pages: change its look, rotate it, delete it.
struct PageViewer: View {
    let scan: ScanModel
    @State var selection: UUID
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
        .onChange(of: scan.scan.pages.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    @ViewBuilder
    private var tools: some View {
        if let page {
            VStack(spacing: 14) {
                Picker("Filter", selection: Binding(get: { page.cleanup.look }, set: { scan.setLook($0, of: [page.id]) })) {
                    Text("Auto").tag(PageLook?.none)
                    ForEach(PageLook.allCases, id: \.self) { Text($0.title).tag(PageLook?.some($0)) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("Rotate Left", systemImage: "rotate.left") { scan.rotatePage(page.id, clockwise: false) }
                    Spacer()
                    Button("Apply to All Pages") { scan.setLook(page.cleanup.look, of: scan.scan.pages.map(\.id)) }
                        .disabled(scan.scan.pages.count < 2)
                    Spacer()
                    Button("Rotate Right", systemImage: "rotate.right") { scan.rotatePage(page.id, clockwise: true) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                HStack {
                    Text(page.cleanup.look == nil ? "Auto picked \(page.analysis.suggestedLook.title)" : " ")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete Page", systemImage: "trash", role: .destructive) { delete(page) }
                        .labelStyle(.titleAndIcon)
                }
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
