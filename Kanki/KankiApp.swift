import SwiftUI

@main
struct KankiApp: App {
    @State private var section: AppSection = .learning

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
                #if DEBUG && targetEnvironment(simulator)
                .task {
                    if let value = ProcessInfo.processInfo.environment["KANKI_UI_IMPORT_RUN"], let run = UUID(uuidString: value) {
                        await Self.watchTestImports(run)
                    }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        .commands {
            SectionCommands(section: $section)
        }
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    // The UI runner atomically stages a package only after the screen under test is visible.
    nonisolated private static func watchTestImports(_ run: UUID) async {
        let directory = LocalCardStore.fileURL.deletingLastPathComponent()
        let pending = directory.appending(path: "\(run.uuidString)-pending.apkg")
        let package = directory.appending(path: "\(run.uuidString)-importing.apkg")
        while !Task.isCancelled {
            do {
                if FileManager.default.fileExists(atPath: pending.path) {
                    try FileManager.default.moveItem(at: pending, to: package)
                    try LocalCardStore.importAnkiPackage(at: package)
                    try FileManager.default.removeItem(at: package)
                }
                try await Task.sleep(for: .milliseconds(100))
            } catch is CancellationError {
                return
            } catch {
                preconditionFailure("Не удалось импортировать тестовый пакет: \(error)")
            }
        }
    }
    #endif
}
