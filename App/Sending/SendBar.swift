import ScannerKit
import ScannerModels
import SwiftUI

/// Archive when every owner of the scans has a Paperless server, Share, and Delete, for the scan under review or the scans selected on Home.
/// Archive is filled with the accent color and shows its name.
/// A button tapped before the PDFs are made shows a spinner, and sends once they are.
struct SendBar: View {
    let app: AppModel
    let scans: [ScanModel]
    /// The scans that went out or were deleted.
    var finished: (Set<UUID>) -> Void = { _ in }
    let summary: String
    var warning: String?
    @State private var showingShare = false
    @State private var confirmingDelete = false
    @State private var sending = SendBarModel()
    @State private var archivingFailed = false
    /// Set when the PDFs went out, acted on once the share sheet is gone.
    @State private var sentBy: SendMethod?

    private func pdfs(of scans: [ScanModel]) -> [URL] {
        scans.compactMap { scan in
            if case .ready(let url, _) = scan.pdf { url } else { nil }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            let named = app.namedSendMethod(for: scans)
            HStack(spacing: named == nil ? 10 : 8) {
                ForEach(app.sendMethods(for: scans), id: \.self) { method in
                    sendButton(method, isNamed: method == named, isRound: named != nil && method != named)
                }
                Button(scans.count > 1 ? "Delete Scans" : "Delete Scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.glass)
                    .foregroundStyle(.red.opacity(scans.isEmpty ? 0.4 : 1))
                    .disabled(scans.isEmpty)
                    .labelStyle(SendButtonLabelStyle(shape: named != nil ? .round : .wide))
                    .buttonBorderShape(named == nil ? .automatic : .circle)
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
        .sheet(isPresented: $showingShare, onDismiss: finishSharing) {
            ShareSheet(items: pdfs(of: scans)) { completed in
                if completed { sentBy = .share }
            }
            .presentationDetents([.medium, .large])
            .ignoresSafeArea()
        }
        .alert("The PDFs could not be archived", isPresented: $archivingFailed) {
            Button("OK") {}
        } message: {
            Text("Try to archive them again.")
        }
    }

    private func finishSharing() {
        guard let sentBy else { return }
        self.sentBy = nil
        app.didSend(scans, by: sentBy)
        finished(Set(scans.map(\.id)))
    }

    /// The button shown with its name takes the room the round ones leave; VoiceOver still reads its title.
    private func sendButton(_ method: SendMethod, isNamed: Bool, isRound: Bool) -> some View {
        let isWaiting = sending.waiting == method
        return Button {
            switch method {
            case .paperless: sending.tap(.paperless, scans: scans, send: archive)
            case .share: share()
            }
        } label: {
            Label {
                Text(method.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            } icon: {
                Image(systemName: method.systemImage)
                    .opacity(isWaiting ? 0 : 1)
                    .overlay {
                        if isWaiting {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(method == .paperless ? .white : nil)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .labelStyle(SendButtonLabelStyle(shape: isNamed ? .named : isRound ? .round : .wide))
        .sendButtonStyle(isSet: method == .paperless)
        .buttonBorderShape(isRound ? .circle : .automatic)
        .disabled(scans.isEmpty || sending.isSending)
        .accessibilityLabel(method.title)
        .accessibilityValue(isWaiting ? (scans.count > 1 ? "Waiting for the PDFs" : "Waiting for the PDF") : "")
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

/// The label of a button of the send bar: its icon as wide as the row lets it, its icon in a round button next to a named one, or its name.
private struct SendButtonLabelStyle: LabelStyle {
    enum Shape {
        case wide, round, named
    }

    var shape = Shape.wide

    func makeBody(configuration: Configuration) -> some View {
        switch shape {
        case .wide:
            icon(configuration).frame(maxWidth: .infinity)
        case .round:
            // Less than the padding of a large button, so five buttons fit on the narrowest iPhone.
            icon(configuration).frame(width: 26).padding(.horizontal, -8)
        case .named:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    configuration.icon
                    configuration.title
                }
                configuration.title
                configuration.icon
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -6)
        }
    }

    private func icon(_ configuration: Configuration) -> some View {
        Label { configuration.title } icon: { configuration.icon }
            .labelStyle(.iconOnly)
    }
}
