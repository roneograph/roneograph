import SwiftUI
import UIKit

/// The system share sheet, telling whether the PDFs went somewhere.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let finished: (_ completed: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            finished(completed)
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
