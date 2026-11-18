import SwiftUI

struct AppShell: View {
    @Binding var section: AppSection
    @State private var pushGate = PushGate()
    @State private var syncProblem: SyncStatus.Problem?
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    @AppStorage("showNotesSection") private var showNotesSection = false
    @AppStorage("showGraphSection") private var showGraphSection = false

    private var visibleSections: [AppSection] {
        AppSection.visible(notesShown: showNotesSection, graphShown: showGraphSection)
    }

    var body: some View {
        TabView(selection: $section) {
            ForEach(visibleSections, id: \.self) { visibleSection in
                sectionStack(for: visibleSection)
                    .tabItem {
                        Label(visibleSection.title, systemImage: visibleSection.symbol)
                    }
                    .tag(visibleSection)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: visibleSections) { _, visible in
            if !visible.contains(section) {
                section = .learning
            }
        }
        .onChange(of: section) { _, newSection in
            if newSection == .learning {
                NotificationCenter.default.post(name: .kankiSnapshotReloaded, object: nil)
            }
        }
    }

    @ViewBuilder
    private func sectionStack(for section: AppSection) -> some View {
        switch section {
        case .learning:
            NavigationStack {
                LearningScreen(pushGate: $pushGate, syncProblem: $syncProblem)
                    .navigationDestination(for: ImportedNoteRoute.self) { $0.screen }
            }
        case .notes:
            NavigationStack {
                NotesScreen()
                    .navigationDestination(for: ImportedNoteRoute.self) { $0.screen }
            }
        case .graph:
            NavigationStack {
                NotesScreen(mode: .graph)
                    .navigationDestination(for: ImportedNoteRoute.self) { $0.screen }
            }
        case .settings:
            NavigationStack {
                SettingsScreen(pushGate: $pushGate, syncProblem: $syncProblem)
            }
        }
    }
}
