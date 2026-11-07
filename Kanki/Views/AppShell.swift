import SwiftUI

struct AppShell: View {
    @Binding var section: AppSection
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    /// Разделы-заготовки скрыты по умолчанию; тумблеры живут в настройках.
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

    /// Стек раздела. У «Графа» нет регистрации направлений — ссылок туда не ведёт
    /// ни один экран; добавить регистрацию до появления ссылок.
    @ViewBuilder
    private func sectionStack(for section: AppSection) -> some View {
        switch section {
        case .learning:
            NavigationStack {
                LearningScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
        case .notes:
            NavigationStack {
                NotesScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
        case .graph:
            NavigationStack {
                GraphScreen()
            }
        case .settings:
            NavigationStack {
                SettingsScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
        }
    }
}
