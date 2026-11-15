import MessageUI
import ScannerKit
import ScannerModels
import SwiftUI

struct ReviewView: View {
    let app: AppModel
    let scan: ScanModel
    @State private var showingRename = false
    @State private var showingOptions = false
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var showingEmailQuestion = false
    @State private var mailAfterQuestion = false
    @State private var confirmingDelete = false
    @State private var viewedPage: ScanPage?
    @State private var askedForName = false
    /// Set when the PDF went out, acted on once the mail or share sheet is gone.
    @State private var sentBy: SendMethod?

    private var settings: ScannerSettings { app.settings.value }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                nameHeader
                PageGrid(scan: scan, open: { viewedPage = $0 }, addPages: { app.camera = scan })
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { sendBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Rename", systemImage: "pencil") { showingRename = true }
                    Button("Add Pages", systemImage: "doc.viewfinder") { app.camera = scan }
                    Button("Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) { SettingsButton(app: app) }
        }
        .confirmationDialog("Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) { app.delete(scan.id) }
        }
        .task(id: scan.pdfInputs) { await scan.buildPDF() }
        .onChange(of: settings.fileNameFormat) { scan.applyFileName() }
        .task {
            if settings.askForName, !scan.scan.isNamedByUser, !askedForName {
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
        .sheet(isPresented: $showingMail, onDismiss: finishSending) {
            if case .ready(let url, _) = scan.pdf {
                MailView(recipient: settings.hasValidEmail ? settings.email : nil, subject: scan.scan.title, attachment: url) { sent in
                    if sent { sentBy = .email }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingEmailQuestion, onDismiss: {
            if mailAfterQuestion {
                mailAfterQuestion = false
                showingMail = true
            }
        }) {
            EmailQuestionView(settings: app.settings) { mailAfterQuestion = true }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingShare, onDismiss: finishSending) {
            if case .ready(let url, _) = scan.pdf {
                ShareSheet(items: [url]) { completed in
                    if completed { sentBy = .share }
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
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

    private var nameHeader: some View {
        Button {
            showingRename = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scan.scan.title)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil").foregroundStyle(.tint)
                }
                Label("\(scan.scan.name).pdf", systemImage: "doc")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Renames the PDF")
        .padding(.top, 8)
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            Button(action: email) {
                Label {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Email")
                        if settings.hasValidEmail {
                            Text("to \(settings.email)").font(.caption).fontWeight(.regular).lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: "envelope")
                }
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
                Button(scan.quality.title) { showingOptions = true }
                    .accessibilityHint("Changes the size of the PDF")
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
        if case .ready = scan.pdf { !scan.isBusy } else { false }
    }

    private var summary: String {
        let count = (scan.scan.pages.count + scan.processing).counted("page")
        switch scan.pdf {
        case .ready(_, let size) where !scan.isBusy:
            return "\(count) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
        case .failed:
            return "\(count) · the PDF could not be made"
        default:
            return "\(count) · preparing the PDF…"
        }
    }

    private func finishSending() {
        if let sentBy {
            self.sentBy = nil
            app.didSend(scan, by: sentBy)
        }
    }

    /// Mail needs an account in the Mail app; without one, the share sheet lets any mail app send the PDF.
    private func email() {
        if !MFMailComposeViewController.canSendMail() {
            showingShare = true
        } else if app.settings.shouldAskForEmail {
            showingEmailQuestion = true
        } else {
            showingMail = true
        }
    }
}

private struct PageGrid: View {
    let scan: ScanModel
    let open: (ScanPage) -> Void
    let addPages: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 16) {
            ForEach(Array(scan.scan.pages.enumerated()), id: \.element.id) { index, page in
                Button { open(page) } label: {
                    VStack(spacing: 5) {
                        Color.clear
                            .aspectRatio(Paper.a4.aspectRatio, contentMode: .fit)
                            .overlay {
                                PageImage(url: scan.previewURL(of: page), revision: page.revision, maximumSize: 600)
                                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                            }
                        Text("\(index + 1) · \(page.look.title)").font(.footnote).foregroundStyle(.secondary)
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
}
