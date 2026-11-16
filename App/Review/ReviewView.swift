import ScannerKit
import ScannerModels
import SwiftUI

struct ReviewView: View {
    let app: AppModel
    let scan: ScanModel
    @State private var editing: DocumentField?
    @State private var viewedPage: ScanPage?
    @State private var askedForName = false

    private var settings: ScannerSettings { app.settings.value }

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
        .safeAreaInset(edge: .bottom) {
            SendBar(app: app, scans: [scan], isReady: scan.hasCurrentPDF) { Text(scan.summary) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scan.pdfInputs) { await scan.buildPDF() }
        .task {
            if settings.askForName, !scan.scan.isNamedByUser, !askedForName {
                askedForName = true
                editing = .name
            }
        }
        .sheet(item: $editing) { field in
            switch field {
            case .name: NameView(scan: scan, settings: app.settings)
            case .issuer, .number: DetailTextView(scan: scan, field: field)
            }
        }
        .fullScreenCover(item: $viewedPage) { page in
            PageViewer(scan: scan, selection: page.id)
        }
        .alert("Something went wrong", isPresented: Binding(get: { scan.failure != nil }, set: { if !$0 { scan.dismissFailure() } })) {
            Button("OK") {}
        } message: {
            Text(scan.failure ?? "")
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
    @State private var deleting: UUID?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 2), spacing: 16) {
            ForEach(Array(scan.scan.pages.enumerated()), id: \.element.id) { index, page in
                Button { open(page) } label: {
                    VStack(spacing: 5) {
                        Color.clear
                            .aspectRatio(Paper.a4.aspectRatio, contentMode: .fit)
                            .overlay {
                                PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 600)
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            }
                        HStack(spacing: 3) {
                            Text("\(index + 1) · \(page.look.title)")
                            Image(systemName: "chevron.right").font(.caption2.bold())
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(index + 1), \(page.look.title)")
                .accessibilityHint("Changes its look, rotates or crops it")
                .draggable(page.id.uuidString) {
                    PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 300).frame(width: 120)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    withAnimation { scan.movePage(id, to: page.id) }
                    return true
                }
                .contextMenu {
                    Button("Rotate", systemImage: "rotate.right") { scan.rotatePage(page.id) }
                    Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { scan.deletePage(page.id) } }
                }
                .overlay(alignment: .bottomTrailing) {
                    if scan.scan.pages.count > 1 { deleteButton(page, number: index + 1) }
                }
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

    private func deleteButton(_ page: ScanPage, number: Int) -> some View {
        Button("Delete Page \(number)", systemImage: "trash") { deleting = page.id }
            .labelStyle(.iconOnly)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 24)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .confirmationDialog("Delete page \(number)?", isPresented: Binding(get: { deleting == page.id }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Page", role: .destructive) { withAnimation { scan.deletePage(page.id) } }
            }
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
                Text("Change its look, rotate or crop it. Touch and hold to move it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
