import MessageUI
import SwiftUI
import UIKit

/// Apple's mail composer, filled in with the recipient, the subject and the PDFs; the user taps Send.
/// It is filled in once, when it is made: what it shows never follows a later change.
struct MailView: UIViewControllerRepresentable {
    let recipient: String?
    let subject: String
    let attachments: [MailAttachment]
    let finished: (MFMailComposeResult) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Mail needs an account in the Mail app.
    static var isAvailable: Bool {
        #if DEBUG
        if AppData.isUITesting { return true }
        #endif
        return MFMailComposeViewController.canSendMail()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        #if DEBUG
        if AppData.isUITesting { return MailStandIn(recipient: recipient, subject: subject, attachments: attachments, finished: context.coordinator.finished) }
        #endif
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        if let recipient { controller.setToRecipients([recipient]) }
        for attachment in attachments {
            controller.addAttachmentData(attachment.data, mimeType: "application/pdf", fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator { result in
            finished(result)
            dismiss()
        }
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let finished: (MFMailComposeResult) -> Void

        init(finished: @escaping (MFMailComposeResult) -> Void) {
            self.finished = finished
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            finished(result)
        }
    }
}

#if DEBUG
/// Stands in for the mail composer in UI tests, as the simulator has no Mail account: it lists what the mail was filled in with when it was made.
private final class MailStandIn: UIViewController {
    private let lines: [String]
    private let finished: (MFMailComposeResult) -> Void

    init(recipient: String?, subject: String, attachments: [MailAttachment], finished: @escaping (MFMailComposeResult) -> Void) {
        lines = ["To: \(recipient ?? "")", "Subject: \(subject)"] + attachments.map { "Attachment: \($0.fileName)" }
        self.finished = finished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let labels = lines.map { line in
            let label = UILabel()
            label.text = line
            label.numberOfLines = 0
            return label
        }
        let send = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: "Send Mail") { [finished] _ in finished(.sent) })
        let cancel = UIButton(configuration: .bordered(), primaryAction: UIAction(title: "Cancel Mail") { [finished] _ in finished(.cancelled) })
        let stack = UIStackView(arrangedSubviews: labels + [send, cancel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }
}
#endif

/// What a mail is filled in with.
struct MailDraft: Identifiable {
    let id = UUID()
    let recipient: String?
    let subject: String
    let attachments: [MailAttachment]
}

/// A PDF read before the mail is composed, so that one that cannot be read stops the mail instead of going missing from it.
struct MailAttachment {
    let data: Data
    let fileName: String

    init(contentsOf url: URL) throws {
        data = try Data(contentsOf: url)
        fileName = url.lastPathComponent
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
