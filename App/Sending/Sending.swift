import MessageUI
import SwiftUI
import UIKit

/// Apple's mail composer, filled in with the recipient, the subject and the PDFs; the user taps Send.
struct MailView: UIViewControllerRepresentable {
    let recipient: String?
    let subject: String
    let attachments: [URL]
    let finished: (_ sent: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        if let recipient { controller.setToRecipients([recipient]) }
        for attachment in attachments {
            if let data = try? Data(contentsOf: attachment) {
                controller.addAttachmentData(data, mimeType: "application/pdf", fileName: attachment.lastPathComponent)
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator { sent in
            finished(sent)
            dismiss()
        }
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finished: (Bool) -> Void

        init(finished: @escaping (Bool) -> Void) {
            self.finished = finished
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result == .sent)
        }
    }
}

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
