import ScannerKit
import ScannerModels
import SwiftUI

struct ReviewView: View {
    let app: AppModel
    let scan: ScanModel
    @State private var editing: DocumentField?
    @State private var viewedPage: ScanPage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DocumentCard(scan: scan, settings: app.settings) { editing = $0 }
                    .padding(.top, 8)
                if app.settings.showsPageTip, !scan.scan.pages.isEmpty {
                    PageTip { withAnimation { app.settings.dismissPageTip() } }
                }
                PageGrid(scan: scan, open: open, addPages: { app.camera = scan })
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .safeAreaBar(edge: .bottom) {
            SendBar(app: app, scan: scan)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.startScan() } label: {
                    HStack(spacing: 4) {
                        Text("New Scan")
                        Image(systemName: "arrow.right")
                    }
                }
                .fontWeight(.semibold)
                .accessibilityLabel("New Scan")
                .accessibilityHint("Opens the camera for another document. This one stays ready to send.")
            }
        }
        .task(id: scan.pdfRequest) { await scan.buildPDF() }
        .sheet(item: $editing) { field in
            switch field {
            case .name: NameView(scan: scan)
            case .issuer, .number: DetailTextView(scan: scan, field: field)
            case .comment: CommentView(scan: scan)
            }
        }
        .fullScreenCover(item: $viewedPage) { page in
            PageViewer(scan: scan, selection: page.id)
        }
        .failureAlert(of: scan, isFrontmost: viewedPage == nil && editing == nil && app.camera == nil)
        .onChange(of: scan.isEmpty && scan.failure == nil) { _, pagesFailed in
            if pagesFailed { app.delete(scan.id) }
        }
    }

    private func open(_ page: ScanPage) {
        app.settings.dismissPageTip()
        viewedPage = page
    }

}

private struct PageGrid: View {
    let scan: ScanModel
    let open: (ScanPage) -> Void
    let addPages: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 2), spacing: 16) {
            ForEach(Array(scan.scan.pages.enumerated()), id: \.element.id) { index, page in
                pageButton(page, number: index + 1)
            }
            ForEach(0..<scan.processing, id: \.self) { _ in
                Rectangle().fill(.quaternary).aspectRatio(Paper.a4.aspectRatio, contentMode: .fit).overlay { ProgressView() }
            }
            Button(action: addPages) {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "plus").font(.title)
                    Text("Add pages").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(Paper.a4.aspectRatio, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func pageButton(_ page: ScanPage, number: Int) -> some View {
        let pages = scan.scan.pages
        return Button { open(page) } label: {
            Color.clear
                .aspectRatio(Paper.a4.aspectRatio, contentMode: .fit)
                .overlay {
                    PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 600)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(number), \(page.look.title)")
        .accessibilityHint("Changes its look, rotates, crops or deletes it")
        .accessibilityActions {
            if number > 1 {
                Button("Move Earlier") { move(page, by: -1) }
            }
            if number < pages.count {
                Button("Move Later") { move(page, by: 1) }
            }
        }
        .draggable(page.id.uuidString) {
            PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 300).frame(width: 120)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            withAnimation { scan.movePage(id, to: page.id) }
            return true
        }
    }

    private func move(_ page: ScanPage, by offset: Int) {
        let pages = scan.scan.pages
        guard let index = pages.firstIndex(where: { $0.id == page.id }), pages.indices.contains(index + offset) else { return }
        withAnimation { scan.movePage(page.id, to: pages[index + offset].id) }
    }
}

/// Shown until closed or until a page is opened: pages do more than they show.
private struct PageTip: View {
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.tap").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tap a page to adjust it").font(.subheadline.weight(.semibold))
                Text("Change its look, rotate, crop or delete it. Touch and hold to move it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .padding(-12)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
