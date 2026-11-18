import ScannerKit
import ScannerModels
import SwiftUI

struct HomeView: View {
    let app: AppModel
    @State private var sending = SendBarModel()
    /// The scans the last swipe or card tap sends, once their PDFs are made.
    @State private var sendingIDs: [UUID] = []
    @State private var sharing: SharedScans?
    /// Set when the share sheet sent the PDFs, acted on once it is gone.
    @State private var shared: [ScanModel]?
    @State private var archivingFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if app.scans.isEmpty {
                WelcomeView()
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { app.showingSettings = true }
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 12) {
                if let toast = app.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                Button { app.startScan() } label: {
                    Label("Scan", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
            .animation(.default, value: app.toast)
        }
        .sensoryFeedback(.success, trigger: app.toast) { _, new in new != nil }
        .onChange(of: app.toast) { _, toast in
            if let toast { AccessibilityNotification.Announcement(toast).post() }
        }
        .sheet(item: $sharing, onDismiss: finishSharing) { sharing in
            ShareSheet(items: sharing.urls) { completed in
                if completed { shared = sharing.scans }
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

    private var list: some View {
        List {
            Section {
                AppIcon(size: 112)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            }
            .listSectionSpacing(.compact)
            if let offer = app.notSentOffer {
                Section {
                    NotSentCard(offer: offer, store: app.store, isWaiting: sending.waiting != nil && sendingIDs == offer.scans.map(\.id)) {
                        send(offer.archives ? .paperless : .share, offer.scans.map(\.id))
                    }
                }
            }
            Section {
                ForEach(app.scans) { scan in
                    ScanRow(scan: scan, store: app.store, owner: app.settings.value.hasSeveralOwners ? app.settings.value.owner(scan.owner?.id) : nil) { app.open(scan.id) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            ForEach(app.swipeActions(for: scan), id: \.self) { action in
                                Button(action.title, systemImage: action.method.systemImage) { send(action.method, [scan.id]) }
                                    .tint(action == .share ? .gray : .accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { app.delete(scan.id) } }
                        }
                }
            } footer: {
                Text("Sent scans leave this iPhone after 24 hours.")
                    .frame(maxWidth: .infinity)
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
    }

    /// Archives the scans, or opens the share sheet with their PDFs, once the PDFs are made.
    private func send(_ method: SendMethod, _ ids: [UUID]) {
        let models = ids.compactMap(app.model(for:))
        sendingIDs = ids
        sending.tap(method, scans: models) {
            switch method {
            case .paperless:
                do { try await app.archive(models) } catch { archivingFailed = true }
            case .share:
                sharing = SharedScans(scans: models)
            }
        }
    }

    private func finishSharing() {
        guard let shared else { return }
        self.shared = nil
        app.didSend(shared, by: .share)
    }
}

/// The scans in the share sheet, kept while it is open.
@MainActor
private struct SharedScans: Identifiable {
    let id = UUID()
    let scans: [ScanModel]

    var urls: [URL] {
        scans.compactMap { scan in
            if case .ready(let url, _) = scan.pdf { url } else { nil }
        }
    }
}

/// Sends at once the scans waiting to be sent, as after scanning a pile of mail.
private struct NotSentCard: View {
    let offer: NotSentOffer
    let store: ScanStore
    let isWaiting: Bool
    let send: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(offer.scans.prefix(3).enumerated().reversed()), id: \.element.id) { index, scan in
                    ScanThumbnail(scan: scan, store: store, width: 28)
                        .rotationEffect(.degrees([0, -9, 7][index]))
                        .offset(x: [0, -4, 4][index])
                }
            }
            .frame(width: 44, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title).font(.headline)
                Text(offer.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: send) {
                Text(offer.button)
                    .opacity(isWaiting ? 0 : 1)
                    .overlay { if isWaiting { ProgressView().tint(.white) } }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .fontWeight(.semibold)
            .accessibilityValue(isWaiting ? "Waiting for the PDFs" : "")
        }
        .accessibilityElement(children: .combine)
    }
}

/// A finished scan opens Review; a scan in progress opens the camera, and says so.
private struct ScanRow: View {
    let scan: Scan
    let store: ScanStore
    /// Shown only when there are several owners.
    let owner: Owner?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                summary
                if !scan.isFinished { continueCapsule }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(scan.isFinished ? "" : "Opens the camera to add pages to this scan")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            ScanThumbnail(scan: scan, store: store, width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.title).font(.headline).lineLimitUnlessAccessibilitySize(1)
                status.font(.subheadline)
                if let owner {
                    Label(owner.name, systemImage: owner.symbol.systemImage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .labelStyle(OwnerLabelStyle())
                        .lineLimitUnlessAccessibilitySize(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var continueCapsule: some View {
        Text("Continue")
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.tint, in: Capsule())
    }

    @ViewBuilder
    private var status: some View {
        if !scan.isFinished {
            Text(scan.status).foregroundStyle(.tint)
        } else if let archiving = scan.archiving {
            HStack(spacing: 4) {
                Image(systemName: archiving.isInProgress ? "arrow.up.circle" : "exclamationmark.triangle.fill")
                Text(scan.status)
            }
            .foregroundStyle(archiving.isInProgress ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.warning)))
            .lineLimitUnlessAccessibilitySize(1)
        } else if scan.sent != nil {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(scan.status).foregroundStyle(.secondary)
            }
            .lineLimitUnlessAccessibilitySize(1)
        } else {
            Text(scan.status).foregroundStyle(Color(.warning)).lineLimitUnlessAccessibilitySize(1)
        }
    }
}

/// A small symbol tinted like the app, close to the owner's name.
private struct OwnerLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}

private struct ScanThumbnail: View {
    let scan: Scan
    let store: ScanStore
    let width: CGFloat

    var body: some View {
        Group {
            if let page = scan.pages.first {
                PageImage(url: store.previewURL(scanID: scan.id, pageID: page.id), revision: page.revision, maximumSize: 160)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
        }
        .frame(width: width, height: width / Paper.a4.aspectRatio)
    }
}

private struct WelcomeView: View {
    var body: some View {
        ViewThatFits(in: .vertical) {
            content.frame(maxHeight: .infinity)
            ScrollView { content }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var content: some View {
        VStack(spacing: 0) {
            AppIcon(size: 100).accessibilityHidden(true)
            Text("Archive your paperwork")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 24)
            VStack(alignment: .leading, spacing: 20) {
                WelcomePromise("No shutter to press", detail: "Hold your iPhone above a letter, an invoice or a payslip.", systemImage: "doc.viewfinder")
                WelcomePromise("Small, searchable PDFs", detail: "PDF/A files with text you can search and copy.", systemImage: "doc.text.magnifyingglass")
                WelcomePromise("Free and open source", detail: "No ads, no account. Nothing leaves your iPhone unless you send it.", systemImage: "hand.raised.slash")
            }
            .frame(maxWidth: 330)
            .padding(.top, 30)
        }
        .padding()
    }
}

private struct WelcomePromise: View {
    let title: String
    let detail: String
    let systemImage: String

    init(_ title: String, detail: String, systemImage: String) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
