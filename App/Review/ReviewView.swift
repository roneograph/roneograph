import MessageUI
import ScannerKit
import ScannerModels
import SwiftUI

struct ReviewView: View {
    let app: AppModel
    let scan: ScanModel
    @State private var showingRename = false
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var showingEmailQuestion = false
    @State private var mailAfterQuestion = false
    @State private var confirmingDelete = false
    @State private var choosingFolder = false
    @State private var savingFailed = false
    @State private var viewedPage: ScanPage?
    @State private var askedForName = false
    /// Set when the PDF went out, acted on once the mail or share sheet is gone.
    @State private var sentBy: SendMethod?

    private var settings: ScannerSettings { app.settings.value }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                nameHeader
                if app.settings.showsPageTip, !scan.scan.pages.isEmpty {
                    PageTip { withAnimation { app.settings.dismissPageTip() } }
                }
                PageGrid(scan: scan, open: open, addPages: { app.camera = scan })
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { sendBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            RenameView(scan: scan, settings: app.settings)
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
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try app.settings.chooseArchiveFolder(url)
                saveToFiles()
            } catch {
                savingFailed = true
            }
        }
        .alert("The folder cannot be reached", isPresented: $savingFailed) {
            Button("Choose Folder") { choosingFolder = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the folder for saved PDFs again.")
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
                if !detailsSummary.isEmpty {
                    Text(detailsSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label("\(scan.scan.name).pdf", systemImage: "doc")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Renames the PDF and edits the details of the document")
        .padding(.top, 8)
    }

    private var detailsSummary: String {
        let details = scan.scan.details
        return [
            details.category == .other ? nil : details.category.rawValue,
            details.issuer,
            details.date?.formatted(date: .abbreviated, time: .omitted),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button("Email", systemImage: "envelope", action: email)
                    .buttonStyle(.glassProminent)
                    .disabled(!isReady)
                Button("Save to Files", systemImage: "folder", action: saveToFiles)
                    .buttonStyle(.glass)
                    .disabled(!isReady)
                Button("Share", systemImage: "square.and.arrow.up") { showingShare = true }
                    .buttonStyle(.glass)
                    .disabled(!isReady)
                Button("Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red)
            }
            .labelStyle(SendButtonLabelStyle())
            .controlSize(.large)
            .font(.title3)
            VStack(spacing: 2) {
                if settings.hasValidEmail {
                    Text("To \(settings.email)").lineLimit(1).truncationMode(.middle)
                }
                Text(summary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func open(_ page: ScanPage) {
        app.settings.dismissPageTip()
        viewedPage = page
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

    /// The first save asks for the folder; later ones go straight to it.
    private func saveToFiles() {
        guard settings.archiveFolder != nil else {
            choosingFolder = true
            return
        }
        do {
            try app.saveToArchive(scan)
        } catch {
            savingFailed = true
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

/// Icon only, full width: the three send buttons share the row equally.
private struct SendButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.icon.frame(maxWidth: .infinity)
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
                Text("Change its look, rotate or crop it. Touch and hold to move or delete it.")
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
