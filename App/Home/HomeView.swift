import ScannerKit
import ScannerModels
import SwiftUI

struct HomeView: View {
    let app: AppModel

    var body: some View {
        Group {
            if app.scans.isEmpty {
                WelcomeView()
            } else {
                recent
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsButton(app: app) }
        }
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
                Button { app.startScan() } label: {
                    Label("Scan", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .animation(.default, value: app.toast)
        }
        .sensoryFeedback(.success, trigger: app.toast) { _, new in new != nil }
    }

    private var recent: some View {
        List {
            AppIcon(size: 64)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
            Section {
                ForEach(app.scans) { scan in
                    ScanRow(scan: scan, store: app.store, open: { app.path = [scan.id] }, continueScan: { app.continueScan(scan.id) })
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { app.delete(scan.id) } }
                        }
                        .contextMenu {
                            Button("Continue Scanning", systemImage: "doc.viewfinder") { app.continueScan(scan.id) }
                            Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { app.delete(scan.id) } }
                        }
                }
            } header: {
                Text("Recent")
            } footer: {
                let days = app.settings.value.keepDays
                Text("Scans are deleted after \(days.counted("day")).")
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ScanRow: View {
    let scan: Scan
    let store: ScanStore
    let open: () -> Void
    let continueScan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scan.title).font(.headline).lineLimit(1)
                        status.font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let page = scan.pages.first {
                PageImage(url: store.previewURL(scanID: scan.id, pageID: page.id), revision: page.revision, maximumSize: 160)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
        }
        .frame(width: 36, height: 48)
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
