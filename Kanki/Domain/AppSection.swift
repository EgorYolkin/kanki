import Foundation

/// Разделы оболочки. `rawValue` задаёт номер горячей клавиши на macOS (⌘1–⌘4),
/// поэтому порядок и значения менять нельзя без обновления теста и документации.
enum AppSection: Int, CaseIterable {
    case learning = 1
    case notes
    case graph
    case settings

    var title: String {
        switch self {
        case .learning: "Обучение"
        case .notes: "Заметки"
        case .graph: "Граф"
        case .settings: "Настройки"
        }
    }

    var symbol: String {
        switch self {
        case .learning: "rectangle.stack"
        case .notes: "note.text"
        case .graph: "circle.hexagongrid"
        case .settings: "gearshape"
        }
    }
}
