import SwiftUI

@main
struct KankiApp: App {
    @State private var section: AppSection = .learning

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(LocalCardStore.resetArgument) {
            LocalCardStore.reset()
        }
        if arguments.contains("--reset-server") {
            try? ServerTokenStore.delete()
            UserDefaults.standard.removeObject(forKey: "serverURL")
            UserDefaults.standard.removeObject(forKey: "serverRevision")
            UserDefaults.standard.removeObject(forKey: "serverHasUnsyncedChanges")
            UserDefaults.standard.removeObject(forKey: "conflictLog")
        }
        if arguments.contains("--reset-sections") {
            UserDefaults.standard.removeObject(forKey: "showNotesSection")
            UserDefaults.standard.removeObject(forKey: "showGraphSection")
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
