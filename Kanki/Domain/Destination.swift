import Foundation

/// Навигационные заготовки экранов оболочки.
///
/// `title` и `symbol` исчерпывающе покрывают все случаи: новый экран без
/// подписи или иконки не соберётся.
enum Destination: Hashable, CaseIterable {
    case note
    case editor
    case search
    case library

    var title: String {
        switch self {
        case .note: "Заметка"
        case .editor: "Редактор заметки"
        case .library: "Библиотека"
        case .search: "Поиск"
        }
    }

    var symbol: String {
        switch self {
        case .note: "note.text"
        case .editor: "square.and.pencil"
        case .library: "books.vertical"
        case .search: "magnifyingglass"
        }
    }
}
