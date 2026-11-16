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
    @State private var mailAfterQuestion = false
    @State private var confirmingDelete = false
    @State private var choosingFolder = false
    @State private var savingFailed = false
    /// Set when the PDFs went out, acted on once the mail or share sheet is gone.
    @State private var sentBy: SendMethod?

    private var settings: ScannerSettings { app.settings.value }

    private var pdfs: [URL] {
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
                Button("Share", systemImage: "square.and.arrow.up") { showingShare = true }
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
                if settings.hasValidEmail {
                    Text("To \(settings.email)").lineLimit(1).truncationMode(.middle)
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
        .sheet(isPresented: $showingMail, onDismiss: finishSending) {
            MailView(recipient: settings.hasValidEmail ? settings.email : nil, subject: scans.map(\.scan).mailSubject, attachments: pdfs) { sent in
                if sent { sentBy = .email }
            }
            .ignoresSafeArea()
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
            ShareSheet(items: pdfs) { completed in
                if completed { sentBy = .share }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
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
    }

    private func finishSending() {
        guard let sentBy else { return }
        self.sentBy = nil
        app.didSend(scans, by: sentBy)
        finished(Set(scans.map(\.id)))
    }

    /// The first save asks for the folder; later ones go straight to it.
    private func saveToFiles() {
        guard settings.archiveFolder != nil else {
            choosingFolder = true
            return
        }
        do {
            try app.saveToArchive(scans)
            finished(Set(scans.map(\.id)))
        } catch {
            if let error = error as? AppModel.ArchiveError, !error.saved.isEmpty { finished(Set(error.saved)) }
            savingFailed = true
        }
    }

    /// Mail needs an account in the Mail app; without one, the share sheet lets any mail app send the PDFs.
    private func email() {
        if !MFMailComposeViewController.canSendMail() {
            showingShare = true
        } else if app.settings.shouldAskForEmail {
            showingEmailQuestion = true
        } else {
            showingMail = true
        }
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
        configuration.icon.frame(maxWidth: .infinity)
    }
}
