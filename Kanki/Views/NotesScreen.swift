import SwiftUI

struct NotesScreen: View {
    var body: some View {
        List {
            Section {
                SectionIntro(
                    symbol: "text.magnifyingglass",
                    title: "Заметок пока нет",
                    detail: "Поиск, связи и редактирование заработают после импорта данных."
                )
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
