import SwiftUI

@main
struct KankiApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup {
            AppShell()
                .tint(.indigo)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
