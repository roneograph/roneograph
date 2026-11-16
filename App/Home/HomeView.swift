import ScannerKit
import ScannerModels
import SwiftUI

struct HomeView: View {
    let app: AppModel
    @State private var isSelecting = false
    @State private var selection = Set<UUID>()

    var body: some View {
        Group {
            if app.scans.isEmpty {
                WelcomeView()
            } else {
                recent
            }
        }
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let toast = app.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                AppIcon(size: 64)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                let notSent = app.notSent
                if notSent.count > 1 {
                    Section {
                        NotSentCard(scans: notSent, store: app.store) { startSelecting(Set(notSent.map(\.id))) }
                    }
                }
            }
            Section {
                ForEach(app.scans) { scan in
                    ScanRow(scan: scan, store: app.store, isSelecting: isSelecting, open: { app.path = [scan.id] }, continueScan: { app.continueScan(scan.id) })
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
                    Text("Scans are deleted after \(days.counted("day")).")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
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
        if selected.isEmpty {
            Text("Select the scans to send")
        } else {
            let documents = selected.count.counted("document"), pages = selected.reduce(0) { $0 + $1.scan.pages.count }.counted("page")
            if isReady {
                let size = selected.reduce(0) { total, model in
                    if case .ready(_, let size) = model.pdf { total + size } else { total }
                }
                Text("\(documents) · \(pages) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
            } else {
                Text("\(documents) · \(pages) · preparing the PDFs…")
            }
            if let warning = selected.map(\.scan).alreadySent {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
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

private struct ScanRow: View {
    let scan: Scan
    let store: ScanStore
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
                Text(scan.title).font(.headline).lineLimit(1)
                status.font(.subheadline)
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
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Continue")
        .accessibilityHint("Opens the camera to add pages to this scan")
    }

    @ViewBuilder
    private var status: some View {
        let pages = scan.pages.count.counted("page")
        if !scan.isFinished {
            Text("In progress · \(pages)").foregroundStyle(.tint)
        } else if let sent = scan.sent {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\((scan.sentBy ?? .email).pastTense) \(Self.relative(sent)) · \(pages)").foregroundStyle(.secondary)
            }
            .lineLimit(1)
        } else {
            Text("Not sent · \(Self.relative(scan.created)) · \(pages)").foregroundStyle(.orange).lineLimit(1)
        }
    }

    private static func relative(_ date: Date) -> String {
        date.timeIntervalSinceNow > -60 ? "now" : date.formatted(.relative(presentation: .named))
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
        .frame(width: width, height: width * 4 / 3)
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
        VStack(spacing: 20) {
            AppIcon(size: 120)
            VStack(spacing: 8) {
                Text("Archive your paperwork").font(.title.bold())
                Text("Hold your iPhone above a letter, an invoice or a payslip.\nIt is captured on its own and saved as a small, searchable PDF/A.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                Label("Free and open source", systemImage: "checkmark.seal")
                Text("No ads, no account, nothing uploaded")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding()
    }
}
