import SwiftUI

struct AppShell: View {
    var body: some View {
        TabView {
            NavigationStack {
                LearningScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Обучение", systemImage: "rectangle.stack") }

            NavigationStack {
                NotesScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Заметки", systemImage: "note.text") }

            NavigationStack {
                GraphScreen()
            }
            .tabItem { Label("Граф", systemImage: "circle.hexagongrid") }

            NavigationStack {
                SettingsScreen()
                    .navigationDestination(for: Destination.self) { destination in
                        PlaceholderScreen(destination: destination)
                    }
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
    }
}
