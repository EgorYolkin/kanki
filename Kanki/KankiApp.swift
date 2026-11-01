import SwiftUI

@main
struct KankiApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @State private var section: AppSection = .learning

    var body: some Scene {
        WindowGroup {
            AppShell(section: $section)
                .tint(.indigo)
                .preferredColorScheme(appearance.colorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        .commands {
            SectionCommands(section: $section)
        }
        #endif
    }
}
