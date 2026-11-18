import ScannerKit
import ScannerModels
import SwiftUI

/// The way to send shown with its name, the other one as a round button, and Delete, for the scan under review:
/// Archive, filled with the accent color, then Share when the owner of the scan has a Paperless server; Share alone otherwise.
/// A button tapped before the PDF is made shows a spinner, and sends once it is.
struct SendBar: View {
    let app: AppModel
    let scan: ScanModel
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var sending = SendBarModel()
    @State private var archivingFailed = false
    /// Set when the PDFs went out, acted on once the share sheet is gone.
    @State private var sentBy: SendMethod?
    @State private var connecting: Owner?

    private var pdfs: [URL] {
        if case .ready(let url, _) = scan.pdf { [url] } else { [] }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let status = app.sendStatus(of: scan) {
                StatusLine(status: status)
            }
            let buttons = app.sendButtons(for: scan)
            HStack(spacing: 8) {
                sendButton(buttons.named, title: buttons.title, isNamed: true, isProminent: buttons.isProminent)
                if let round = buttons.round {
                    sendButton(round, title: round.title, isNamed: false, isProminent: false)
                }
                Button("Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red)
                    .labelStyle(SendButtonLabelStyle(isNamed: false))
                    .buttonBorderShape(.circle)
            }
            .controlSize(.large)
            .font(.title3)
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: scan.id) { sending.cancel() }
        .onDisappear { sending.cancel() }
        .confirmationDialog("Delete this scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive, action: delete)
        }
        .sheet(isPresented: $showingShare, onDismiss: finishSharing) {
            ShareSheet(items: pdfs) { completed in
                if completed { sentBy = .share }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .sheet(item: $connecting) { owner in
            if let archiver = app.archiver {
                PaperlessSetupView(ownerID: owner.id, settings: app.settings, archiver: archiver)
            }
        }
        .alert("The PDF could not be archived", isPresented: $archivingFailed) {
            Button("OK") {}
        } message: {
            Text("Try to archive it again.")
        }
    }

    private var footer: some View {
        let footer = app.sendFooter(for: scan, waiting: sending.waiting)
        return HStack(spacing: 0) {
            Group {
                if let lead = footer.lead {
                    Text("\(Text(lead).bold()) · \(footer.text)")
                } else {
                    Text(footer.connectsPaperless ? "\(footer.text) · " : footer.text)
                }
            }
            .truncationMode(.middle)
            if footer.lead == nil, footer.connectsPaperless {
                Button("Connect Paperless") { connecting = app.ownerToConnect(for: scan) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .fixedSize()
            }
        }
        .lineLimitUnlessAccessibilitySize(1)
    }

    private func finishSharing() {
        guard let sentBy else { return }
        self.sentBy = nil
        app.didSend([scan], by: sentBy)
    }

    /// The button shown with its name takes the room the round ones leave; VoiceOver reads the name of a round one too.
    private func sendButton(_ method: SendMethod, title: String, isNamed: Bool, isProminent: Bool) -> some View {
        let isWaiting = sending.waiting == method
        return Button {
            switch method {
            case .paperless: sending.tap(.paperless, scans: [scan], send: archive)
            case .share: sending.tap(.share, scans: [scan]) { showingShare = true }
            }
        } label: {
            Label {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: method.systemImage)
                    .opacity(isWaiting ? 0 : 1)
                    .overlay {
                        if isWaiting {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(isProminent ? .white : nil)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .labelStyle(SendButtonLabelStyle(isNamed: isNamed))
        .sendButtonStyle(isProminent: isProminent)
        .buttonBorderShape(isNamed ? .automatic : .circle)
        .disabled(sending.isSending)
        .accessibilityLabel(title)
        .accessibilityValue(isWaiting ? "Waiting for the PDF" : "")
    }

    /// The upload goes on in the background.
    private func archive() async {
        do {
            try await app.archive([scan])
        } catch {
            archivingFailed = true
        }
    }

    private func delete() {
        withAnimation {
            app.delete(scan.id)
        }
    }
}

private extension View {
    @ViewBuilder
    func sendButtonStyle(isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
    }
}

/// The label of a button of the send bar: its icon and name taking the room left, or its icon in a round button.
private struct SendButtonLabelStyle: LabelStyle {
    let isNamed: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isNamed {
            HStack(spacing: 8) {
                configuration.icon
                configuration.title
            }
            .frame(maxWidth: .infinity)
        } else {
            // A large glass button keeps its padding even when round; this keeps it a circle.
            Label { configuration.title } icon: { configuration.icon }
                .labelStyle(.iconOnly)
                .frame(width: 26)
                .padding(.horizontal, -8)
        }
    }
}

/// Where the scan went: archived or shared and when, on its way to Paperless, or why it could not be archived.
private struct StatusLine: View {
    let status: SendStatus

    var body: some View {
        Label {
            Text(status.text)
                .foregroundStyle(status.kind == .failed ? AnyShapeStyle(Color(.warning)) : AnyShapeStyle(.secondary))
        } icon: {
            switch status.kind {
            case .sent: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .uploading: Image(systemName: "arrow.up.circle").foregroundStyle(.tint)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(.warning))
            }
        }
        .font(.footnote)
        .lineLimitUnlessAccessibilitySize(1)
    }
}
