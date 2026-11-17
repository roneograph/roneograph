import ScannerKit
import ScannerModels
import SwiftUI

struct HomeView: View {
    let app: AppModel
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if app.scans.isEmpty {
                WelcomeView()
            } else {
                recent
            }
        }
        .toolbar { toolbar }
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
                if isSelecting {
                    SendBar(app: app, scans: selected, isReady: isReady, finished: sent) { selectionSummary }
                } else {
                    Button { app.startScan() } label: {
                        Label("Scan", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 8)
            .animation(.default, value: app.toast)
        }
        .sensoryFeedback(.success, trigger: app.toast) { _, new in new != nil }
        .onChange(of: app.toast) { _, toast in
            if let toast { AccessibilityNotification.Announcement(toast).post() }
        }
        .task(id: selection) {
            for model in selected { await model.preparePDF() }
        }
        .onChange(of: app.scans) {
            selection.formIntersection(selectable.map(\.id))
            if selectable.isEmpty { isSelecting = false }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                if selection.isEmpty {
                    Menu("Select") {
                        Button("Select All", systemImage: "checkmark.circle") { selection = Set(selectable.map(\.id)) }
                        Button("Select Not Sent", systemImage: "envelope") { selection = Set(app.notSent.map(\.id)) }
                    }
                } else {
                    Button("Deselect All") { selection = [] }
                }
            }
            ToolbarItem(placement: .principal) {
                Text(selection.isEmpty ? "Select Scans" : "\(selection.count) Selected").font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { endSelecting() }
            }
        } else {
            if canSelect {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Select") { startSelecting([]) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { app.showingSettings = true }
            }
        }
    }

    private var recent: some View {
        List(selection: isSelecting ? $selection : nil) {
            if !isSelecting {
                Section {
                    AppIcon(size: 112)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                }
                .listSectionSpacing(.compact)
                if app.suggestsSendSetup {
                    Section {
                        SendSetupCard {
                            app.showingSettings = true
                        } close: {
                            withAnimation { app.settings.value.dismissedSendSetup = true }
                        }
                    }
                }
                let notSent = app.notSent
                if notSent.count > 1 {
                    Section {
                        NotSentCard(scans: notSent, store: app.store) { startSelecting(Set(notSent.map(\.id))) }
                    }
                }
            }
            Section {
                ForEach(app.scans) { scan in
                    ScanRow(scan: scan, store: app.store, owner: app.settings.value.hasSeveralOwners ? app.settings.value.owner(scan.owner?.id) : nil, isSelecting: isSelecting, open: { app.path = [scan.id] }, continueScan: { app.continueScan(scan.id) })
                        .selectionDisabled(!scan.isFinished)
                        .swipeActions {
                            if !isSelecting {
                                Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { app.delete(scan.id) } }
                            }
                        }
                        .contextMenu {
                            if !isSelecting {
                                if canSelect, scan.isFinished {
                                    Button("Select", systemImage: "checkmark.circle") { startSelecting([scan.id]) }
                                }
                                Button("Continue Scanning", systemImage: "doc.viewfinder") { app.continueScan(scan.id) }
                                Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { app.delete(scan.id) } }
                            }
                        }
                }
            } header: {
                Text("Recent")
            } footer: {
                if let days = app.settings.value.keepScans.days {
                    Text("Sent scans are deleted after \(days.counted("day")).")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .contentMargins(.top, 0, for: .scrollContent)
    }

    /// Scans in progress have no PDF to send yet.
    private var selectable: [Scan] { app.scans.filter(\.isFinished) }

    private var canSelect: Bool { selectable.count > 1 }

    /// In the order of the list, which is the order of the attachments.
    private var selected: [ScanModel] {
        app.scans.filter { selection.contains($0.id) }.compactMap { app.model(for: $0.id) }
    }

    private var isReady: Bool {
        let selected = selected
        return !selected.isEmpty && selected.allSatisfy(\.hasCurrentPDF)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        let selected = selected
        Text(selected.selectionSummary)
        if let warning = selected.map(\.scan).alreadySent {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(.warning))
                .lineLimitUnlessAccessibilitySize(1)
        }
    }

    private func startSelecting(_ ids: Set<UUID>) {
        withAnimation {
            selection = ids
            isSelecting = true
        }
    }

    private func endSelecting() {
        withAnimation {
            isSelecting = false
            selection = []
        }
    }

    private func sent(_ ids: Set<UUID>) {
        selection.subtract(ids)
        if selection.isEmpty { endSelecting() }
    }
}

/// Offers to select at once the scans waiting to be sent, as after scanning a pile of mail.
private struct NotSentCard: View {
    let scans: [Scan]
    let store: ScanStore
    let select: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ForEach(Array(scans.prefix(3).enumerated().reversed()), id: \.element.id) { index, scan in
                    ScanThumbnail(scan: scan, store: store, width: 28)
                        .rotationEffect(.degrees([0, -9, 7][index]))
                        .offset(x: [0, -4, 4][index])
                }
            }
            .frame(width: 44, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(scans.count) scans not sent").font(.headline)
                Text(scans.map(\.title).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Select", action: select)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Points to Settings until scans can be emailed or archived in one tap.
private struct SendSetupCard: View {
    let setUp: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Send in one tap").font(.headline)
                Text("Add your email address or a Paperless server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Set Up", action: setUp)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .fontWeight(.semibold)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
        }
    }
}

private struct ScanRow: View {
    let scan: Scan
    let store: ScanStore
    /// Shown only when there are several owners.
    let owner: Owner?
    let isSelecting: Bool
    let open: () -> Void
    let continueScan: () -> Void

    var body: some View {
        if isSelecting {
            summary.opacity(scan.isFinished ? 1 : 0.45)
        } else {
            HStack(spacing: 12) {
                Button(action: open) { summary.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                continueButton
            }
        }
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

    private var continueButton: some View {
        Button(action: continueScan) {
            Image(systemName: "doc.viewfinder")
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.12), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .padding(-2)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Continue")
        .accessibilityHint("Opens the camera to add pages to this scan")
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
                WelcomePromise("Free and open source", detail: "No ads, no account, nothing uploaded.", systemImage: "hand.raised.slash")
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
