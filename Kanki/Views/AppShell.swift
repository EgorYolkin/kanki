import SwiftUI

struct AppShell: View {
    @Binding var section: AppSection
    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        TabView(selection: $section) {
            NavigationStack {
                LearningScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label(AppSection.learning.title, systemImage: AppSection.learning.symbol) }
            .tag(AppSection.learning)

            NavigationStack {
                NotesScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label(AppSection.notes.title, systemImage: AppSection.notes.symbol) }
            .tag(AppSection.notes)

            NavigationStack {
                GraphScreen()
            }
            .tabItem { Label(AppSection.graph.title, systemImage: AppSection.graph.symbol) }
            .tag(AppSection.graph)

            NavigationStack {
                SettingsScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        if case .conflicts = destination {
                            ConflictsScreen()
                        } else {
                            PlaceholderScreen(destination: destination)
                        }
                    }
            }
            .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.symbol) }
            .tag(AppSection.settings)
        }
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: section) { _, newSection in
            if newSection == .learning {
                NotificationCenter.default.post(name: .kankiSnapshotReloaded, object: nil)
            }
        }
    }
}
