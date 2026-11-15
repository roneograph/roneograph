import MessageUI
import ScannerKit
import SwiftUI

struct ReviewView: View {
    let app: AppModel
    let scan: ScanModel
    @State private var showingRename = false
    @State private var showingOptions = false
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var viewedPage: UUID?
    @State private var askedForName = false

    private var settings: ScannerSettings { app.settings.value }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameHeader
                    PageGrid(scan: scan, open: { viewedPage = $0 }, addPages: app.addPages)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { sendBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New scan", systemImage: "doc.viewfinder") { app.newScan() }
                        .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Rename", systemImage: "pencil") { showingRename = true }
                        Button("Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .confirmationDialog("Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Scan", role: .destructive) { app.deleteScan() }
            }
        }
        .task(id: scan.pdfInputs) { await scan.buildPDF() }
        .task {
            if settings.fileNameStyle == .ask, !scan.scan.isNamedByUser, !askedForName {
                askedForName = true
                showingRename = true
            }
        }
        .sheet(isPresented: $showingRename) {
            RenameView(scan: scan)
        }
        .sheet(isPresented: $showingOptions) {
            PDFOptionsView(scan: scan)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMail) {
            if case .ready(let url, _) = scan.pdf {
                MailView(recipient: settings.hasValidEmail ? settings.email : nil, subject: scan.scan.name, attachment: url) { sent in
                    if sent { scan.markSent() }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingShare) {
            if case .ready(let url, _) = scan.pdf {
                ShareSheet(items: [url]) { completed in
                    if completed { scan.markSent() }
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: $viewedPage) { id in
            PageViewer(scan: scan, selection: id)
        }
        .alert("Something went wrong", isPresented: .constant(scan.failure != nil)) {
            Button("OK") { scan.dismissFailure() }
        } message: {
            Text(scan.failure ?? "")
        }
    }

    private var nameHeader: some View {
        Button {
            showingRename = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    (Text(scan.scan.name) + Text(".pdf").foregroundStyle(.tertiary).fontWeight(.regular))
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil").foregroundStyle(.tint)
                }
                Text(nameSource).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Renames the PDF")
        .padding(.top, 8)
    }

    private var nameSource: String {
        if scan.scan.isNamedByUser { return "Tap to rename" }
        return scan.scan.suggestions.isEmpty || scan.scan.name.hasPrefix(scan.fallbackName) ? "No name found in the text · tap to rename" : "Name found in the text · tap to rename"
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            Button(action: email) {
                Label(settings.hasValidEmail ? "Email to \(settings.email)" : "Email", systemImage: "envelope")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            Button {
                showingShare = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            HStack(spacing: 4) {
                Text(summary)
                Text("·")
                Button("Options") { showingOptions = true }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .controlSize(.large)
        .fontWeight(.semibold)
        .disabled(!isReady)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var isReady: Bool {
        if case .ready = scan.pdf { scan.processing == 0 } else { false }
    }

    private var summary: String {
        let pages = scan.scan.pages.count + scan.processing
        let count = pages == 1 ? "1 page" : "\(pages) pages"
        switch scan.pdf {
        case .ready(_, let size) where scan.processing == 0:
            return "\(count) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        case .failed:
            return "\(count) · the PDF could not be made"
        default:
            return "\(count) · preparing the PDF…"
        }
    }

    /// Mail needs an account in the Mail app; without one, the share sheet lets any mail app send the PDF.
    private func email() {
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else {
            showingShare = true
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

private struct PageGrid: View {
    let scan: ScanModel
    let open: (UUID) -> Void
    let addPages: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 16) {
            ForEach(Array(scan.scan.pages.enumerated()), id: \.element.id) { index, page in
                Button { open(page.id) } label: {
                    VStack(spacing: 5) {
                        Color.clear
                            .aspectRatio(210 / 297, contentMode: .fit)
                            .overlay {
                                PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 600)
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            }
                            .overlay(alignment: .topLeading) {
                                Text(page.look.title)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .padding(6)
                            }
                        Text("\(index + 1)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(index + 1), \(page.look.title)")
                .draggable(page.id.uuidString) {
                    PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 300).frame(width: 120)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    withAnimation { scan.movePage(id, to: page.id) }
                    return true
                }
                .contextMenu {
                    Button("Rotate Right", systemImage: "rotate.right") { scan.rotatePage(page.id, clockwise: true) }
                    Button("Rotate Left", systemImage: "rotate.left") { scan.rotatePage(page.id, clockwise: false) }
                    Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { scan.deletePage(page.id) } }
                }
            }
            ForEach(0..<scan.processing, id: \.self) { _ in
                Rectangle().fill(.quaternary).aspectRatio(210 / 297, contentMode: .fit).overlay { ProgressView() }
            }
            Button(action: addPages) {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "plus").font(.title)
                    Text("Add pages").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(210 / 297, contentMode: .fit)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }
}
