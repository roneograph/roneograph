import ScannerKit
import SwiftUI
import UIKit

struct AboutView: View {
    private static let repository = URL(string: "https://github.com/roneograph/roneograph")!

    var body: some View {
        List {
            VStack(spacing: 8) {
                AppIcon(size: 84).accessibilityHidden(true)
                Text("Roneograph").font(.title2.bold())
                Text("Version \(AppVersion.full)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Copy Version", systemImage: "doc.on.doc") { UIPasteboard.general.string = AppVersion.full }
                    }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Why “Roneograph”?").font(.headline.italic()).foregroundStyle(.tint)
                    Text("roneograph, noun: a rotary stencil duplicator.").font(.footnote).foregroundStyle(.secondary)
                    Text("Offices once copied their letters, forms and circulars on a Roneo: a stencil wrapped around an inked drum, a crank, and copies rolled out one by one. Roneograph makes one faithful copy of your paperwork instead: black ink on white paper, every word kept, in a file made to last.")
                        .font(.subheadline)
                }
                .fontDesign(.serif)
                .padding(.vertical, 4)
            }

            Section("Links") {
                link("Source code", systemImage: "chevron.left.forwardslash.chevron.right", url: Self.repository)
                link("Report a problem", systemImage: "exclamationmark.bubble", url: Self.repository.appending(path: "issues"))
                link("Privacy policy", systemImage: "hand.raised", url: Self.repository.appending(path: "blob/main/PRIVACY.md"))
            }

            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Open source licenses", systemImage: "doc.text")
                }
            } header: {
                Text("Open source")
            } footer: {
                Text("MIT license. Apple frameworks, and the UVDoc network to flatten curled pages.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Label {
                    Text(title).foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary)
            }
        }
    }
}

enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static var full: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(marketing) (\(build))"
    }
}

private struct LicensesView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    LicenseText(title: "Roneograph", text: Self.license)
                } label: {
                    LabeledContent("Roneograph", value: "MIT")
                }
                NavigationLink {
                    LicenseText(title: "UVDoc", text: PageUnwarper.license)
                } label: {
                    LabeledContent("UVDoc", value: "MIT")
                }
            } footer: {
                Text("UVDoc flattens curled and folded pages. Apple frameworks are covered by the iOS license.")
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static var license: String {
        Bundle.main.url(forResource: "LICENSE", withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
}

private struct LicenseText: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
