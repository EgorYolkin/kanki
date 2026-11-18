import SwiftUI

@main
struct KankiApp: App {
    @State private var section: AppSection = .learning
    @Environment(\.scenePhase) private var phase
    @State private var visitError: String?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(LocalCardStore.resetArgument) {
            do {
                try LocalCardStore.reset()
            } catch {
                preconditionFailure("Не удалось сбросить тестовое хранилище: \(error)")
            }
        }
        if arguments.contains("--reset-server") {
            try? ServerTokenStore.delete()
            UserDefaults.standard.removeObject(forKey: "serverURL")
            UserDefaults.standard.removeObject(forKey: "serverRevision")
            UserDefaults.standard.removeObject(forKey: "serverHasUnsyncedChanges")
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
                .alert("Не удалось записать посещение", isPresented: Binding(
                    get: { visitError != nil }, set: { if !$0 { visitError = nil } }
                )) {} message: { Text(visitError ?? "") }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        .commands {
            SectionCommands(section: $section)
        }
        #endif
        .onChange(of: phase, initial: true) { _, newPhase in
            guard newPhase == .active else { return }
            do {
                try LocalCardStore.recordVisit(at: .now)
                ServerClient.scheduleActivityUpload()
            } catch {
                visitError = error.localizedDescription
            }
        }
    }
}
