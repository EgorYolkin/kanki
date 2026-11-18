import SwiftUI

extension View {
    /// Lists and editors do not supply an intrinsic sheet height on macOS.
    @ViewBuilder
    func cardSheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 480, minHeight: 440)
        #else
        self
        #endif
    }
}
