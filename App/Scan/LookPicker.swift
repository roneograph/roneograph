import ScannerKit
import SwiftUI

/// Auto, or one of the looks a page can have.
struct LookPicker: View {
    @Binding var look: PageLook?

    var body: some View {
        Picker("Filter", selection: $look) {
            Text("Auto").tag(PageLook?.none)
            ForEach(PageLook.allCases, id: \.self) { Text($0.title).tag(PageLook?.some($0)) }
        }
    }
}
