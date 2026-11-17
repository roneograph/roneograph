import MessageUI
import ScannerKit
import ScannerModels
import SwiftUI

/// Email, Save to Files, Share and Delete, for the scan under review or the scans selected on Home.
struct SendBar<Summary: View>: View {
    let app: AppModel
    let scans: [ScanModel]
    let isReady: Bool
    /// The scans that went out or were deleted.
    var finished: (Set<UUID>) -> Void = { _ in }
    @ViewBuilder let summary: () -> Summary
    @State private var showingMail = false
    @State private var showingShare = false
    @State private var showingEmailQuestion = false
    @State private var answeredQuestion = false
    @State private var confirmingDelete = false
    @State private var choosingFolder = false
    @State private var savingFailed = false
    @State private var mailUnavailable = false
    @State private var attachingFailed = false
    @State private var folderInsideApp = false
    /// The owner the folder picker and the email question are for.
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
                Button("Email", systemImage: "envelope", action: email)
                    .buttonStyle(.glassProminent)
                    .disabled(!isReady)
                Button("Save to Files", systemImage: "folder", action: saveToFiles)
                    .buttonStyle(.glass)
                    .disabled(!isReady)
                Button("Share", systemImage: "square.and.arrow.up", action: share)
                    .buttonStyle(.glass)
                    .disabled(!isReady)
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
                    Text(destination).lineLimit(1).truncationMode(.middle)
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
            MailView(recipient: mails?.recipient, subject: (mails?.scans ?? []).map(\.scan).mailSubject, attachments: attachments) { sent in
                if sent { sentBy = .email }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingEmailQuestion, onDismiss: {
            mails?.closeQuestion(answered: answeredQuestion)
            answeredQuestion = false
            nextMail()
        }) {
            EmailQuestionView(settings: app.settings, ownerID: ownerID) { answeredQuestion = true }
                .presentationDetents([.medium])
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
        nextMail()
    }

    /// The first save for an owner asks for its folder; later ones go straight to it.
    private func saveToFiles() {
        if let owner = app.ownerWithoutFolder(among: scans) {
            ownerID = owner.id
            choosingFolder = true
            return
        }
        Task {
            guard await preparePDFs(scans) else { return }
            do {
                try app.saveToArchive(scans)
                finished(Set(scans.map(\.id)))
            } catch {
                let saved = (error as? AppModel.ArchiveError)?.saved ?? []
                if !saved.isEmpty { finished(Set(saved)) }
                ownerID = scans.first { !saved.contains($0.id) }?.owner.id
                savingFailed = true
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
        switch mails?.step {
        case .askEmail(let id):
            ownerID = id
            showingEmailQuestion = true
        case .compose:
            Task { await composeMail() }
        case .done, nil:
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
            for id in ids { app.delete(id) }
        }
        finished(ids)
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
