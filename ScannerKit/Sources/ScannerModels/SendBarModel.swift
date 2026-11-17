import Foundation
import Observation
import ScannerKit

/// The send started from a send bar: it waits for the PDFs of the scans, then runs; only one waits or runs at a time.
@MainActor @Observable
public final class SendBarModel {
    /// The way to send waiting for the PDFs; nil once it runs, and when they were already made.
    public private(set) var waiting: SendMethod?
    /// Whether a send runs; no other starts meanwhile.
    public private(set) var isSending = false
    /// The latest tap; an earlier one still waiting for the PDFs never sends.
    @ObservationIgnored private var request: UUID?

    public init() {}

    /// Sends the scans with `send` once their PDFs are made, rebuilding one deleted or renamed in Files, and again after an edit made while waiting; nothing is sent when one cannot be made.
    /// Tapping the waiting way again cancels it, another way takes its place, and nothing starts while a send runs.
    public func tap(_ method: SendMethod, scans: [ScanModel], send: @escaping @MainActor () async -> Void) {
        guard !isSending, !scans.isEmpty else { return }
        if waiting == method { return cancel() }
        let request = UUID()
        self.request = request
        waiting = scans.allSatisfy(\.hasCurrentPDF) ? nil : method
        Task {
            var inputs: [ScanModel.PDFInputs]
            repeat {
                inputs = scans.map(\.pdfInputs)
                for scan in scans { await scan.preparePDF() }
            } while self.request == request && (scans.map(\.pdfInputs) != inputs || scans.contains(where: \.isBusy))
            guard self.request == request else { return }
            cancel()
            guard scans.allSatisfy(\.hasCurrentPDF) else { return }
            isSending = true
            await send()
            isSending = false
        }
    }

    /// Stops waiting; the PDFs are still made, as a cancelled build would have to start over.
    public func cancel() {
        request = nil
        waiting = nil
    }
}
