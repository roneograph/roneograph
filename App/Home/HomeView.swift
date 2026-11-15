import ScannerKit
import ScannerModels
import SwiftUI

struct HomeView: View {
    let app: AppModel

    var body: some View {
        Group {
            if app.scans.isEmpty {
                WelcomeView(settings: app.settings)
            } else {
                recent
            }
        }
        .navigationTitle("Roneograph")
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
                Text("Scans are deleted after \(days == 1 ? "1 day" : "\(days) days").")
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
        let pages = scan.pages.count == 1 ? "1 page" : "\(scan.pages.count) pages"
        if !scan.isFinished {
            Text("In progress · \(pages)").foregroundStyle(.blue)
        } else if let sent = scan.sent {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(scan.sentBy == .share ? "Shared" : "Emailed") \(Self.relative(sent)) · \(pages)").foregroundStyle(.secondary)
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
    @Bindable var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 46))
                    .foregroundStyle(.tint)
                    .frame(width: 96, height: 96)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 28))
                    .padding(.top, 12)
                VStack(spacing: 6) {
                    Text("Scan and send").font(.title2.bold())
                    Text("Hold your iPhone above a page.\nIt is found and captured on its own.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    promise("No ads, no account", "Free and open source.", image: "hand.raised.slash", color: .green)
                    promise("Stays on your iPhone", "Nothing is uploaded.", image: "wifi.slash", color: .blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email scans to (optional)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Email", text: $settings.value.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(.tertiary))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private func promise(_ title: String, _ detail: String, image: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: image).font(.title2).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
