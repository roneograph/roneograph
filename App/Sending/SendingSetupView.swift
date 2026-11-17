import ScannerKit
import ScannerModels
import SwiftUI

/// Opened from the send bar when it has nothing to send with: the ways to send of each owner of the scans.
struct SendingSetupView: View {
    let app: AppModel
    let ownerIDs: [UUID]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(ownerIDs, id: \.self) { id in
                    SendingSection(app: app, ownerID: id, title: app.settings.value.owner(id).name, explains: id == ownerIDs.last)
                }
            }
            .navigationTitle(ownerIDs.count == 1 ? "Sending for \(app.settings.value.owner(ownerIDs.first).name)" : "Set Up Sending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}
