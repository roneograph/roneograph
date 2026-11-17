import MessageUI
import ScannerKit
import ScannerModels
import SwiftUI

/// Archive and Email when the owners of the scans have a Paperless server or an address, Save to Files and Share unless turned off for one of them, and Delete, for the scan under review or the scans selected on Home.
/// A button that sends in a single tap is filled with the accent color, and the first one for every owner of the scans, Share aside, shows its name; with nothing to send with, a button sets up sending instead.
/// A button tapped before the PDFs are made shows a spinner, and sends once they are.
struct SendBar: View {
    let app: AppModel
    let scans: [ScanModel]
    /// The scans that went out or were deleted.
    var finished: (Set<UUID>) -> Void = { _ in }
    let summary: String
    var warning: String?
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var choosingFolder = false
    @State private var savingFailed = false
    @State private var storageFull = false
    @State private var sending = SendBarModel()
    @State private var mailUnavailable = false
    @State private var attachingFailed = false
    /// Set when Mail could not send, told once the mail sheet is gone.
    @State private var mailFailed = false
    @State private var showingMailFailure = false
    @State private var folderInsideApp = false
    @State private var archivingFailed = false
    /// The owner the folder picker is for.
    @State private var ownerID: UUID?
    @State private var mails: MailQueue?
    @State private var attachments: [MailAttachment] = []
    /// Set when the PDFs went out, acted on once the mail or share sheet is gone.
    @State private var sentBy: SendMethod?
    @State private var settingUpSending: SendingSetup?

    private func pdfs(of scans: [ScanModel]) -> [URL] {
        scans.compactMap { scan in
            if case .ready(let url, _) = scan.pdf { url } else { nil }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            let named = app.namedSendMethod(for: scans)
            let row = named == nil ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(SendButtonRow(spacing: 10))
            row {
                let methods = app.sendMethods(for: scans)
                if methods.isEmpty {
                    Button("Set Up Sending…", systemImage: "paperplane") {
                        settingUpSending = SendingSetup(ownerIDs: app.sendingOwners(for: scans).map(\.id))
                    }
                    .buttonStyle(.glass)
                    .labelStyle(SendButtonLabelStyle(showsTitle: true))
                    .font(.body.weight(.semibold))
                }
                ForEach(methods, id: \.self) { method in
                    sendButton(method, isNamed: method == named)
                }
                Button(scans.count > 1 ? "Delete Scans" : "Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red.opacity(scans.isEmpty ? 0.4 : 1))
                    .disabled(scans.isEmpty)
                    .labelStyle(SendButtonLabelStyle(fills: !methods.isEmpty))
            }
            .labelStyle(SendButtonLabelStyle())
            .controlSize(.large)
            .font(.title3)
            VStack(spacing: 2) {
                let footer = app.sendFooter(for: scans, waiting: sending.waiting, summary: summary)
                Group {
                    if let lead = footer.lead {
                        Text("\(Text(lead).bold()) · \(footer.text)")
                    } else {
                        Text(footer.text)
                    }
                }
                .truncationMode(.middle)
                .lineLimitUnlessAccessibilitySize(1)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(.warning))
                        .lineLimitUnlessAccessibilitySize(1)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: scans.map(\.id)) { sending.cancel() }
        .onDisappear { sending.cancel() }
        .confirmationDialog(scans.count > 1 ? "Delete \(scans.count) scans?" : "Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(scans.count > 1 ? "Delete \(scans.count) Scans" : "Delete Scan", role: .destructive, action: delete)
        }
        // Not on the button, which goes as soon as a way to send is set.
        .sheet(item: $settingUpSending) { setup in
            SendingSetupView(app: app, ownerIDs: setup.ownerIDs)
        }
        .sheet(isPresented: $showingMail, onDismiss: finishMail) {
            MailView(recipient: mails?.recipient, subject: (mails?.scans ?? []).map(\.scan).mailSubject, attachments: attachments) { result in
                if result == .sent { sentBy = .email }
                if result == .failed { mailFailed = true }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingShare, onDismiss: finishSharing) {
            ShareSheet(items: pdfs(of: scans)) { completed in
                if completed { sentBy = .share }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try app.settings.chooseArchiveFolder(url, for: ownerID)
                saveToFiles()
            } catch SettingsStore.FolderError.insideApp {
                folderInsideApp = true
            } catch {
                savingFailed = true
            }
        }
        .alert("The PDFs could not be archived", isPresented: $archivingFailed) {
            Button("OK") {}
        } message: {
            Text("Try to archive them again.")
        }
        .alert("This folder cannot be used", isPresented: $folderInsideApp) {
            Button("Choose Folder") { choosingFolder = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SettingsStore.FolderError.insideApp.localizedDescription)
        }
        .alert("No account in Mail", isPresented: $mailUnavailable) {
            Button("Share", action: share)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Email needs an account in the Mail app. Share the PDFs to send them with another app.")
        }
        .alert("The mail was not sent", isPresented: $showingMailFailure) {
            Button("OK") {}
        } message: {
            Text("Try to email the PDFs again.")
        }
        .alert("The PDFs could not be attached", isPresented: $attachingFailed) {
            Button("OK") {}
        } message: {
            Text("Try to email them again.")
        }
        .alert("The folder cannot be reached", isPresented: $savingFailed) {
            Button("Choose Folder") { choosingFolder = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the folder for saved PDFs again.")
        }
        .alert("The iPhone storage is full", isPresented: $storageFull) {
            Button("OK") {}
        } message: {
            Text("Free up space, then save the PDFs again.")
        }
    }

    private func finishSharing() {
        guard let sentBy else { return }
        self.sentBy = nil
        app.didSend(scans, by: sentBy)
        finished(Set(scans.map(\.id)))
    }

    private func finishMail() {
        let sent = mails?.closeMail(sent: sentBy != nil) ?? []
        sentBy = nil
        if !sent.isEmpty { finished(Set(sent.map(\.id))) }
        if mailFailed {
            mailFailed = false
            showingMailFailure = true
        }
        nextMail()
    }

    /// The button shown with its name gets a short one; VoiceOver still reads its title.
    private func sendButton(_ method: SendMethod, isNamed: Bool) -> some View {
        let isWaiting = sending.waiting == method
        return Button {
            switch method {
            case .paperless: sending.tap(.paperless, scans: scans, send: archive)
            case .email: email()
            case .files: saveToFiles()
            case .share: share()
            }
        } label: {
            Label {
                Text(isNamed ? method.buttonName : method.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: method.systemImage)
                    .opacity(isWaiting ? 0 : 1)
                    .overlay {
                        if isWaiting {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(isProminent(method) ? .white : nil)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .labelStyle(SendButtonLabelStyle(showsTitle: isNamed))
        .sendButtonStyle(isSet: isProminent(method))
        .disabled(scans.isEmpty || sending.isSending)
        .accessibilityLabel(method.title)
        .accessibilityValue(isWaiting ? (scans.count > 1 ? "Waiting for the PDFs" : "Waiting for the PDF") : "")
        .layoutValue(key: IsNamed.self, value: isNamed)
    }

    private func isProminent(_ method: SendMethod) -> Bool {
        switch method {
        case .paperless, .email: true
        case .files: app.hasFolder(for: scans)
        case .share: false
        }
    }

    /// The first save for an owner asks for its folder at once; later ones go straight to it.
    private func saveToFiles() {
        if let owner = app.ownerWithoutFolder(among: scans) {
            sending.cancel()
            ownerID = owner.id
            choosingFolder = true
            return
        }
        sending.tap(.files, scans: scans) {
            do {
                try await app.saveToArchive(scans)
                finished(Set(scans.map(\.id)))
            } catch {
                let error = error as? AppModel.ArchiveError
                let saved = error?.saved ?? []
                if !saved.isEmpty { finished(Set(saved)) }
                ownerID = scans.first { !saved.contains($0.id) }?.owner.id
                if error?.isStorageFull == true { storageFull = true } else { savingFailed = true }
            }
        }
    }

    /// The uploads go on in the background.
    private func archive() async {
        do {
            try await app.archive(scans)
            finished(Set(scans.map(\.id)))
        } catch {
            archivingFailed = true
        }
    }

    private func share() {
        sending.tap(.share, scans: scans) { showingShare = true }
    }

    /// Rebuilds a PDF deleted or renamed in Files since it was made; false when one cannot be made.
    private func preparePDFs(_ scans: [ScanModel]) async -> Bool {
        for scan in scans { await scan.preparePDF() }
        return scans.allSatisfy(\.hasCurrentPDF)
    }

    /// Mail needs an account in the Mail app; without one, the share sheet is offered so another app can send the PDFs.
    /// Scans of different owners go in one mail per owner, one after the other.
    private func email() {
        if !MFMailComposeViewController.canSendMail() {
            sending.cancel()
            mailUnavailable = true
        } else {
            sending.tap(.email, scans: scans) {
                mails = MailQueue(scans, app: app)
                await composeMail()
            }
        }
    }

    private func nextMail() {
        if mails?.scans.isEmpty == false {
            Task { await composeMail() }
        } else {
            mails = nil
        }
    }

    private func composeMail() async {
        let scans = mails?.scans ?? []
        guard await preparePDFs(scans), let read = try? pdfs(of: scans).map(MailAttachment.init(contentsOf:)) else {
            mails = nil
            attachingFailed = true
            return
        }
        attachments = read
        showingMail = true
    }

    private func delete() {
        let ids = Set(scans.map(\.id))
        withAnimation {
            app.delete(ids)
        }
        finished(ids)
    }
}

private extension View {
    @ViewBuilder
    func sendButtonStyle(isSet: Bool) -> some View {
        if isSet {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}

/// The owners whose ways to send are being set up, kept while the sheet is open.
private struct SendingSetup: Identifiable {
    let id = UUID()
    let ownerIDs: [UUID]
}

/// Icon only, or icon and title, as wide as the row lets it unless `fills` is off.
private struct SendButtonLabelStyle: LabelStyle {
    var showsTitle = false
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if showsTitle {
                HStack(spacing: 8) {
                    configuration.icon
                    configuration.title
                }
            } else {
                Label { configuration.title } icon: { configuration.icon }
                    .labelStyle(.iconOnly)
            }
        }
        .frame(maxWidth: fills ? .infinity : nil)
    }
}

/// The send buttons in a row, the one shown with its name about 2.6 times as wide as each other, narrowed when the others need more room.
private struct SendButtonRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(in: proposal.width, subviews: subviews)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(in: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(in width: CGFloat?, subviews: Subviews) -> [CGFloat] {
        guard let width else { return subviews.map { $0.sizeThatFits(.unspecified).width } }
        let room = width - spacing * CGFloat(max(subviews.count - 1, 0))
        let named = CGFloat(subviews.filter { $0[IsNamed.self] }.count)
        let unit = room / (CGFloat(subviews.count) - named + 2.6 * named)
        let others = subviews.map { $0[IsNamed.self] ? 0 : max(unit, $0.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width) }
        let left = max(0, room - others.reduce(0, +))
        return zip(subviews, others).map { $0[IsNamed.self] ? left / named : $1 }
    }
}

private struct IsNamed: LayoutValueKey {
    static let defaultValue = false
}
