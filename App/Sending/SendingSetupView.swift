import ScannerKit
import ScannerModels
import SwiftUI

/// Opened from the send bar when it has nothing to send with: the ways to send of each owner of the scans.
/// Home's card opens it for the default owner, ready to type the address.
struct SendingSetupView: View {
    let app: AppModel
    let ownerIDs: [UUID]
    var focusesEmail = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(ownerIDs, id: \.self) { id in
                    SendingSection(app: app, ownerID: id, title: app.settings.value.owner(id).name, explains: id == ownerIDs.last, focusesEmail: focusesEmail && id == ownerIDs.first)
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
