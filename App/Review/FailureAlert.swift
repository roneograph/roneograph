import ScannerModels
import SwiftUI

extension View {
    /// Tells why the scan could not be changed; only the frontmost view over the scan can show it, the others pass false.
    func failureAlert(of scan: ScanModel, isFrontmost: Bool = true) -> some View {
        alert("Something went wrong", isPresented: Binding(get: { isFrontmost && scan.failure != nil }, set: { if !$0 { scan.dismissFailure() } })) {
            Button("OK") {}
        } message: {
            Text(scan.failure ?? "")
        }
    }
}
