import SwiftUI

@main
struct KankiApp: App {
    @State private var section: AppSection = .learning

    init() {
        if ProcessInfo.processInfo.arguments.contains(LocalCardStore.resetArgument) {
            LocalCardStore.reset()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell(section: $section)
                .tint(.indigo)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        .commands {
            SectionCommands(section: $section)
        }
        #endif
    }
}
