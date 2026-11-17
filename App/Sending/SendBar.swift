import MessageUI
import ScannerKit
import ScannerModels
import SwiftUI

/// Archive and Email when the owners of the scans have a Paperless server or an address, Save to Files and Share unless turned off in Settings, and Delete, for the scan under review or the scans selected on Home.
/// A button that sends in a single tap is filled with the accent color.
struct SendBar<Summary: View>: View {
    let app: AppModel
    let scans: [ScanModel]
    let isReady: Bool
    /// The scans that went out or were deleted.
    var finished: (Set<UUID>) -> Void = { _ in }
    @ViewBuilder let summary: () -> Summary
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var choosingFolder = false
    @State private var savingFailed = false
    @State private var storageFull = false
    @State private var isSaving = false
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

    private func pdfs(of scans: [ScanModel]) -> [URL] {
        scans.compactMap { scan in
            if case .ready(let url, _) = scan.pdf { url } else { nil }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(app.sendMethods(for: scans), id: \.self) { method in
                    switch method {
                    case .paperless:
                        Button("Archive", systemImage: "archivebox", action: archive)
                            .buttonStyle(.glassProminent)
                            .disabled(!isReady)
                    case .email:
                        Button("Email", systemImage: "envelope", action: email)
                            .buttonStyle(.glassProminent)
                            .disabled(!isReady)
                    case .files:
                        Button("Save to Files", systemImage: "folder", action: saveToFiles)
                            .sendButtonStyle(isSet: app.hasFolder(for: scans))
                            .disabled(!isReady || isSaving)
                    case .share:
                        Button("Share", systemImage: "square.and.arrow.up", action: share)
                            .buttonStyle(.glass)
                            .disabled(!isReady)
                    }
                }
                Button(scans.count > 1 ? "Delete Scans" : "Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red.opacity(scans.isEmpty ? 0.4 : 1))
                    .disabled(scans.isEmpty)
            }
            .labelStyle(SendButtonLabelStyle())
            .controlSize(.large)
            .font(.title3)
            VStack(spacing: 2) {
                if let destination = app.destination(of: scans) {
                    Text(destination).lineLimitUnlessAccessibilitySize(1).truncationMode(.middle)
                }
                summary()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .confirmationDialog(scans.count > 1 ? "Delete \(scans.count) scans?" : "Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(scans.count > 1 ? "Delete \(scans.count) Scans" : "Delete Scan", role: .destructive, action: delete)
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

    /// The first save for an owner asks for its folder; later ones go straight to it.
    private func saveToFiles() {
        if let owner = app.ownerWithoutFolder(among: scans) {
            ownerID = owner.id
            choosingFolder = true
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            guard await preparePDFs(scans) else { return }
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
    private func archive() {
        Task {
            guard await preparePDFs(scans) else { return }
            do {
                try await app.archive(scans)
                finished(Set(scans.map(\.id)))
            } catch {
                archivingFailed = true
            }
        }
    }

    private func share() {
        Task {
            if await preparePDFs(scans) { showingShare = true }
        }
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
            mailUnavailable = true
        } else {
            mails = MailQueue(scans, app: app)
            nextMail()
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

/// Icon only, full width: the send buttons share the row equally.
private struct SendButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label { configuration.title } icon: { configuration.icon }
            .labelStyle(.iconOnly)
            .frame(maxWidth: .infinity)
    }
}
