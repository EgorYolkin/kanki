import SwiftUI

@main
struct KankiApp: App {
    var body: some Scene {
        WindowGroup {
            AppShell()
                .tint(.indigo)
        }
    }
}

enum Destination: Hashable {
    case card, note, editor, search, library, merges, conflicts

    var title: String {
        switch self {
        case .card: "Карточка"
        case .note: "Заметка"
        case .editor: "Редактор заметки"
        case .library: "Библиотека"
        case .search: "Поиск"
        case .merges: "Очередь мержей"
        case .conflicts: "Конфликты"
        }
    }

    var symbol: String {
        switch self {
        case .card: "rectangle.on.rectangle"
        case .note: "note.text"
        case .editor: "square.and.pencil"
        case .library: "books.vertical"
        case .merges: "arrow.triangle.merge"
        case .search: "magnifyingglass"
        case .conflicts: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}

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

private struct SectionIntro: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
    }
}

private struct LearningScreen: View {
    var body: some View {
        List {
            Section {
                SectionIntro(symbol: "rectangle.stack", title: "Пока нет карточек", detail: "Очередь повторения появится после подключения хранилища и импорта заметок.")
                    .frame(maxWidth: .infinity)
            }
            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.card) {
                    Label("Экран карточки", systemImage: Destination.card.symbol)
                }
            }
        }
        .navigationTitle("Обучение")
    }
}

private struct NotesScreen: View {
    var body: some View {
        List {
            Section {
                SectionIntro(symbol: "text.magnifyingglass", title: "Заметок пока нет", detail: "Поиск, связи и редактирование заработают после импорта данных.")
                    .frame(maxWidth: .infinity)
            }
            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.search) {
                    Label("Поиск", systemImage: Destination.search.symbol)
                }
                NavigationLink(value: Destination.note) {
                    Label("Экран заметки", systemImage: Destination.note.symbol)
                }
                NavigationLink(value: Destination.editor) {
                    Label("Редактор", systemImage: Destination.editor.symbol)
                }
                NavigationLink(value: Destination.library) {
                    Label("Библиотека", systemImage: Destination.library.symbol)
                }
            }
        }
        .navigationTitle("Заметки")
    }
}

private struct GraphScreen: View {
    var body: some View {
        SectionIntro(symbol: "circle.hexagongrid", title: "Граф пуст", detail: "После импорта здесь будут заметка и её ближайшие связи.")
            .navigationTitle("Граф")
    }
}

private struct SettingsScreen: View {
    var body: some View {
        List {
            Section("Синхронизация") {
                Label("Сервер не подключён", systemImage: "icloud.slash")
                    .foregroundStyle(.secondary)
            }
            Section("Предпросмотр экранов") {
                NavigationLink(value: Destination.merges) {
                    Label("Очередь мержей", systemImage: Destination.merges.symbol)
                }
                NavigationLink(value: Destination.conflicts) {
                    Label("Конфликты", systemImage: Destination.conflicts.symbol)
                }
            }
        }
        .navigationTitle("Настройки")
    }
}

private struct PlaceholderScreen: View {
    let destination: Destination

    var body: some View {
        SectionIntro(symbol: destination.symbol, title: destination.title, detail: "Это заготовка экрана. Данные и действия появятся на следующих этапах.")
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
